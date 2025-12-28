package server

import (
	"fmt"

	"github.com/newton-miku/WeSpeek/internal/store"
)

func (s *Server) InitAdmin(gen bool) {
	hasSecret := s.adminService.HasSecrets()

	if hasSecret && !gen {
		return
	}

	if gen || !hasSecret {
		ott := s.adminService.GenerateOTT()
		fmt.Printf("Admin Setup Link: /?setup_admin=%s\n", ott)
	}
}

func (s *Server) VerifyAdminSetup(token string) (string, error) {
	return s.adminService.VerifyAdminSetup(token)
}

func (s *Server) CreateAdminChallenge() (string, int64) {
	return s.adminService.CreateAdminChallenge()
}

func (s *Server) VerifyAdmin(nonce, macHex string) bool {
	return s.adminService.VerifyAdmin(nonce, macHex)
}

func (s *Server) MoveUser(uid, targetRoomID string) error {
	// Find user
	var targetPeer *peer
	s.rooms.Range(func(_, v any) bool {
		rm := v.(*room)
		if p, ok := rm.peers[uid]; ok {
			targetPeer = p
			return false
		}
		return true
	})

	if targetPeer == nil {
		return store.ErrNotFound
	}

	// Find target room
	_, ok := s.rooms.Load(targetRoomID)
	if !ok {
		return store.ErrNotFound
	}

	targetPeer.send(struct {
		Method string `json:"method"`
		Params struct {
			Target string `json:"target"`
		} `json:"params"`
	}{
		Method: "room.move",
		Params: struct {
			Target string `json:"target"`
		}{Target: targetRoomID},
	})

	return nil
}
