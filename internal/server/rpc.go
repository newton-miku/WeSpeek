package server

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/newton-miku/WeSpeek/internal/domain/entity"
	"github.com/newton-miku/WeSpeek/internal/util"
)

func (s *Server) dispatchRPC(c *Client, m rpcMessage) {
	switch m.Method {
	case "subscribe":
		s.handleSubscribe(c)
	case "join":
		s.handleJoin(c, m.Params)
	case "chat.public":
		s.handleChatPublic(c, m.Params)
	case "chat.room":
		s.handleChatRoom(c, m.Params)
	case "rename":
		s.handleRename(c, m.Params)
	case "name":
		s.handleName(c, m.Params)
	case "io.set":
		s.handleIOSet(c, m.Params)
	case "leave":
		s.handleLeave(c)
	case "admin.get_user_info":
		s.handleAdminGetUserInfo(c, m.Params)
	case "admin.login":
		s.handleAdminLogin(c, m.Params)
	case "admin.delete_room":
		s.handleAdminDeleteRoom(c, m.Params)
	case "admin.update_room":
		s.handleAdminUpdateRoom(c, m.Params)
	case "admin.kick":
		s.handleAdminKick(c, m.Params)
	case "admin.mute":
		s.handleAdminMute(c, m.Params)
	case "admin.create_group":
		s.handleAdminCreateGroup(c, m.Params)
	case "admin.delete_group":
		s.handleAdminDeleteGroup(c, m.Params)
	}
}

func (s *Server) handleSubscribe(c *Client) {
	c.msgCh <- struct {
		Method string            `json:"method"`
		Params roomsUpdateParams `json:"params"`
	}{Method: "rooms.update", Params: roomsUpdateParams{
		Rooms:  s.GetRoomsSnapshot(),
		Groups: s.GetGroupsSnapshot(),
	}}

	// Get public chat history from DB
	publicHistory := s.GetPublicChatHistory()
	c.msgCh <- struct {
		Method string        `json:"method"`
		Params []ChatMessage `json:"params"`
	}{Method: "chat.public.history", Params: publicHistory}
}

func (s *Server) handleJoin(c *Client, params json.RawMessage) {
	var prm joinParams
	if err := json.Unmarshal(params, &prm); err != nil {
		return
	}

	// Ensure single channel membership: leave current room if any
	if c.peer != nil {
		c.peer.close()
	}

	rm := s.getOrCreateRoom(prm.SID)
	name := prm.Name
	if name == "" {
		name = prm.UID
	}

	// Use the IP resolved during connection
	ip := c.remoteIP

	// Create peer and link to client
	c.peer = s.newPeer(prm.UID, name, ip, rm, func(v interface{}) { c.msgCh <- v })

	roomHistory, _ := s.GetRoomChatHistory(rm.id)
	if roomHistory == nil {
		roomHistory = []ChatMessage{}
	}
	c.msgCh <- struct {
		Method string        `json:"method"`
		Params []ChatMessage `json:"params"`
	}{Method: "chat.room.history", Params: roomHistory}
}

func (s *Server) handleChatPublic(c *Client, params json.RawMessage) {
	var in struct {
		UID  string `json:"uid"`
		Name string `json:"name"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	name := in.Name
	if c.peer != nil {
		name = c.peer.name
	} else if name == "" {
		name = in.UID
	}
	if name == "" {
		return
	}
	msg := ChatMessage{
		UID:  in.UID,
		Name: name,
		Text: in.Text,
		Time: time.Now().Unix(),
	}

	// Save to DB
	_ = s.chatService.SaveMessage(entity.ChatMessage{
		RoomID:    "",
		UID:       msg.UID,
		Name:      msg.Name,
		Text:      msg.Text,
		CreatedAt: msg.Time,
	})

	// Broadcast
	s.clients.Range(func(key, value interface{}) bool {
		send := value.(func(interface{}))
		send(struct {
			Method string      `json:"method"`
			Params ChatMessage `json:"params"`
		}{Method: "chat.public", Params: msg})
		return true
	})
}

func (s *Server) handleChatRoom(c *Client, params json.RawMessage) {
	var in struct {
		UID  string `json:"uid"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	if c.peer == nil {
		return
	}
	msg := ChatMessage{
		UID:  c.peer.uid,
		Name: c.peer.name,
		Text: in.Text,
		Time: time.Now().Unix(),
	}

	// Save to DB
	_ = s.chatService.SaveMessage(entity.ChatMessage{
		RoomID:    c.peer.room.id,
		UID:       msg.UID,
		Name:      msg.Name,
		Text:      msg.Text,
		CreatedAt: msg.Time,
	})

	for _, peer := range c.peer.room.peers {
		peer.send(struct {
			Method string      `json:"method"`
			Params ChatMessage `json:"params"`
		}{Method: "chat.room", Params: msg})
	}
}

func (s *Server) handleRename(c *Client, params json.RawMessage) {
	var in struct {
		UID string `json:"uid"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	if c.peer == nil || in.UID == "" {
		return
	}
	s.doRename(c.peer, in.UID)
}

func (s *Server) handleName(c *Client, params json.RawMessage) {
	var in struct {
		UID  string `json:"uid"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	if c.peer == nil || in.UID == "" {
		return
	}
	c.peer.room.mu.Lock()
	c.peer.name = in.Name
	c.peer.room.mu.Unlock()
	s.broadcastRoomUpdate(c.peer.room)
	s.broadcastRoomsUpdate()
}

func (s *Server) handleIOSet(c *Client, params json.RawMessage) {
	var in struct {
		InputDisabled  *bool `json:"inputDisabled"`
		OutputDisabled *bool `json:"outputDisabled"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	if c.peer == nil {
		return
	}
	if in.InputDisabled != nil {
		c.peer.inputDisabled = *in.InputDisabled
	}
	if in.OutputDisabled != nil {
		c.peer.outputDisabled = *in.OutputDisabled
	}
	s.broadcastRoomUpdate(c.peer.room)
}

func (s *Server) handleLeave(c *Client) {
	if c.peer != nil {
		c.peer.close()
		c.peer = nil
	}
}

func (s *Server) handleAdminGetUserInfo(c *Client, params json.RawMessage) {
	var in struct {
		UID  string `json:"uid"`
		Auth string `json:"auth"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}

	// HMAC check
	isAdmin := false
	if in.Auth != "" {
		parts := strings.Split(in.Auth, ":")
		if len(parts) == 2 {
			isAdmin = s.VerifyAdmin(parts[0], parts[1])
		}
	}

	var targetPeer *peer
	s.rooms.Range(func(key, value interface{}) bool {
		r := value.(*room)
		r.mu.RLock()
		if p, ok := r.peers[in.UID]; ok {
			targetPeer = p
			r.mu.RUnlock()
			return false
		}
		r.mu.RUnlock()
		return true
	})

	if targetPeer != nil {
		resp := adminUserInfoResponse{
			UID:   targetPeer.uid,
			Name:  targetPeer.name,
			Room:  targetPeer.room.id,
			Stats: targetPeer.GetPeerStats(),
		}
		if isAdmin {
			resp.IP = targetPeer.ip
		}

		c.msgCh <- struct {
			Method string                `json:"method"`
			Params adminUserInfoResponse `json:"params"`
		}{Method: "admin.user_info", Params: resp}
	}
}

func (s *Server) handleAdminLogin(c *Client, params json.RawMessage) {
	var in struct {
		Password string `json:"password"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	if in.Password == util.EnvOr("ADMIN_PASSWORD", "admin") {
		secret, err := s.adminService.CreateLoginSecret("admin login")
		if err != nil {
			return
		}

		c.msgCh <- struct {
			Method string `json:"method"`
			Params struct {
				Secret string `json:"secret"`
			} `json:"params"`
		}{Method: "admin.login", Params: struct {
			Secret string `json:"secret"`
		}{Secret: secret}}
	}
}

func (s *Server) handleAdminDeleteRoom(c *Client, params json.RawMessage) {
	var in struct {
		Auth string `json:"auth"`
		ID   string `json:"id"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	if r, ok := s.rooms.Load(in.ID); ok {
		rm := r.(*room)
		rm.mu.Lock()
		for _, p := range rm.peers {
			p.room = nil // Detach
			// Notify user?
		}
		rm.mu.Unlock()
		s.rooms.Delete(in.ID)
		_ = s.roomService.DeleteRoom(in.ID)
		s.broadcastRoomsUpdate()
	}
}

func (s *Server) handleAdminUpdateRoom(c *Client, params json.RawMessage) {
	var in struct {
		Auth      string `json:"auth"`
		ID        string `json:"id"`
		Permanent bool   `json:"permanent"`
		Order     int    `json:"order"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	if r, ok := s.rooms.Load(in.ID); ok {
		rm := r.(*room)
		rm.permanent = in.Permanent
		rm.order = in.Order
		_ = s.roomService.SaveRoom(entity.Room{
			ID:        rm.id,
			Permanent: rm.permanent,
			Order:     rm.order,
			Group:     rm.group,
		})
		s.broadcastRoomsUpdate()
	}
}

func (s *Server) handleAdminKick(c *Client, params json.RawMessage) {
	var in struct {
		Auth string `json:"auth"`
		UID  string `json:"uid"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	// Find peer
	var targetPeer *peer
	s.rooms.Range(func(key, value interface{}) bool {
		r := value.(*room)
		r.mu.RLock()
		if p, ok := r.peers[in.UID]; ok {
			targetPeer = p
			r.mu.RUnlock()
			return false
		}
		r.mu.RUnlock()
		return true
	})

	if targetPeer != nil {
		targetPeer.close()
	}
}

func (s *Server) handleAdminMute(c *Client, params json.RawMessage) {
	var in struct {
		Auth string `json:"auth"`
		UID  string `json:"uid"`
		Mute bool   `json:"mute"` // true=mute, false=unmute
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	// Find peer
	var targetPeer *peer
	s.rooms.Range(func(key, value interface{}) bool {
		r := value.(*room)
		r.mu.RLock()
		if p, ok := r.peers[in.UID]; ok {
			targetPeer = p
			r.mu.RUnlock()
			return false
		}
		r.mu.RUnlock()
		return true
	})

	if targetPeer != nil {
		targetPeer.inputDisabled = in.Mute
		s.broadcastRoomUpdate(targetPeer.room)
	}
}

func (s *Server) handleAdminCreateGroup(c *Client, params json.RawMessage) {
	var in struct {
		Auth string `json:"auth"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	s.groups.Store(in.Name, struct{}{})
	_ = s.roomService.SaveGroup(in.Name)
	s.broadcastRoomsUpdate()
}

func (s *Server) handleAdminDeleteGroup(c *Client, params json.RawMessage) {
	var in struct {
		Auth string `json:"auth"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(params, &in); err != nil {
		return
	}
	parts := strings.Split(in.Auth, ":")
	if len(parts) != 2 || !s.VerifyAdmin(parts[0], parts[1]) {
		return
	}

	s.groups.Delete(in.Name)
	_ = s.roomService.DeleteGroup(in.Name)
	// Also update rooms in this group to have no group?
	// Implementation choice: current logic doesn't strictly enforce foreign keys
	// But let's clear group from rooms for consistency
	s.rooms.Range(func(key, value interface{}) bool {
		r := value.(*room)
		if r.group == in.Name {
			r.group = ""
			_ = s.roomService.SaveRoom(entity.Room{
				ID:        r.id,
				Permanent: r.permanent,
				Order:     r.order,
				Group:     "",
			})
		}
		return true
	})

	s.broadcastRoomsUpdate()
}
