package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/newton-miku/WeSpeek/internal/server"
	"github.com/newton-miku/WeSpeek/internal/store"
)

type API struct {
	server *server.Server
}

func New(s *server.Server) *API {
	return &API{server: s}
}

// Admin Helpers

func (a *API) isAdmin(r *http.Request) bool {
	// Prefer HMAC auth: X-Admin-Auth: nonce:macHex
	if auth := r.Header.Get("X-Admin-Auth"); auth != "" {
		parts := strings.Split(auth, ":")
		if len(parts) == 2 {
			return a.server.VerifyAdmin(parts[0], parts[1])
		}
	}
	return false
}

// Handlers

func (a *API) RoomsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		list := a.server.GetRoomsSnapshot()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(list)
	case http.MethodPost:
		if !a.isAdmin(r) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		var body struct {
			ID           string  `json:"id"`
			Permanent    *bool   `json:"permanent"`
			Group        *string `json:"group"`
			Parent       *string `json:"parent"`
			Order        *int    `json:"order"`
			AudioCodec   *string `json:"audioCodec"`
			AudioQuality *int    `json:"audioQuality"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.ID == "" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if (body.Group == nil || *body.Group == "") && body.Parent != nil && *body.Parent != "" {
			body.Group = body.Parent
		}

		// Decide whether to update room metadata or only audio settings
		metaProvided := body.Permanent != nil || body.Group != nil || body.Order != nil
		if metaProvided {
			permanent := false
			group := ""
			order := 0
			if body.Permanent != nil {
				permanent = *body.Permanent
			}
			if body.Group != nil {
				group = *body.Group
			}
			if body.Order != nil {
				order = *body.Order
			}
			if err := a.server.CreateOrUpdateRoom(body.ID, permanent, group, order); err != nil {
				http.Error(w, "failed to save room", http.StatusInternalServerError)
				return
			}
		}
		if body.AudioCodec != nil || body.AudioQuality != nil {
			codec := ""
			quality := 0
			if body.AudioCodec != nil {
				codec = *body.AudioCodec
			}
			if body.AudioQuality != nil {
				quality = *body.AudioQuality
			}
			_ = a.server.UpdateRoomAudio(body.ID, codec, quality)
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (a *API) RoomMembersHandler(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Path[len("/api/rooms/"):]
	switch r.Method {
	case http.MethodGet:
		members, err := a.server.GetRoomMembers(id)
		type resp struct {
			ID      string                     `json:"id"`
			Members []server.RoomMemberSummary `json:"members"`
		}
		w.Header().Set("Content-Type", "application/json")
		if err == store.ErrNotFound {
			_ = json.NewEncoder(w).Encode(resp{ID: id, Members: []server.RoomMemberSummary{}})
			return
		}
		_ = json.NewEncoder(w).Encode(resp{ID: id, Members: members})
	case http.MethodDelete:
		if !a.isAdmin(r) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		err := a.server.DeleteRoom(id)
		if err == store.ErrNotEmpty {
			http.Error(w, "room not empty", http.StatusConflict)
			return
		}
		if err != nil {
			// Ignore other errors (e.g. not found)
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (a *API) GroupsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(a.server.GetGroupsSnapshot())
	case http.MethodPost:
		if !a.isAdmin(r) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		var body struct {
			Name string `json:"name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Name == "" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}

		if err := a.server.CreateGroup(body.Name); err != nil {
			http.Error(w, "failed to save group", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	case http.MethodDelete:
		if !a.isAdmin(r) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		name := r.URL.Path[len("/api/groups/"):]

		err := a.server.DeleteGroup(name)
		if err == store.ErrNotEmpty {
			http.Error(w, "group not empty", http.StatusConflict)
			return
		}
		if err != nil {
			http.Error(w, "failed to delete group", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (a *API) PublicChatHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(a.server.GetPublicChatHistory())
}

func (a *API) RoomChatHandler(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Path[len("/api/chat/room/"):]
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	history, err := a.server.GetRoomChatHistory(id)
	if err == store.ErrNotFound {
		http.Error(w, "room not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(history)
}

func (a *API) AdminSetupHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	secret, err := a.server.VerifyAdminSetup(body.Token)
	if err != nil {
		http.Error(w, "invalid token", http.StatusForbidden)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(struct {
		Secret string `json:"secret"`
	}{Secret: secret})
}

func (a *API) AdminChallengeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	nonce, exp := a.server.CreateAdminChallenge()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(struct {
		Nonce string `json:"nonce"`
		Exp   int64  `json:"exp"`
	}{Nonce: nonce, Exp: exp})
}

func (a *API) AdminMoveUserHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !a.isAdmin(r) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	var body struct {
		UID    string `json:"uid"`
		RoomID string `json:"room_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if err := a.server.MoveUser(body.UID, body.RoomID); err != nil {
		if err == store.ErrNotFound {
			http.Error(w, "user or room not found", http.StatusNotFound)
			return
		}
		http.Error(w, "failed to move user", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) WSHandler(w http.ResponseWriter, r *http.Request) {
	a.server.WSHandler(w, r)
}

func (a *API) AudioWSHandler(w http.ResponseWriter, r *http.Request) {
	a.server.AudioWSHandler(w, r)
}
