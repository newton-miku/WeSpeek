package server

import (
	"sync"
	"time"

	"github.com/newton-miku/WeSpeek/internal/domain/entity"
	"github.com/newton-miku/WeSpeek/internal/service"
	"github.com/newton-miku/WeSpeek/internal/store"
)

type Server struct {
	roomService  *service.RoomService
	chatService  *service.ChatService
	adminService *service.AdminService

	// State
	rooms           sync.Map // map[string]*room
	clients         sync.Map // map[string]func(interface{})
	adminChallenges sync.Map
	groups          sync.Map // map[string]struct{}
}

func New(s store.Store) *Server {
	return &Server{
		roomService:  service.NewRoomService(s, s),
		chatService:  service.NewChatService(s),
		adminService: service.NewAdminService(s),
	}
}

func (s *Server) Init() error {
	// Load rooms
	rooms, err := s.roomService.GetRooms()
	if err != nil {
		return err
	}

	// Create default rooms if none exist
	if len(rooms) == 0 {
		defaults := []entity.Room{
			{ID: "大厅", Permanent: true, Order: 0},
		}
		for _, r := range defaults {
			if err := s.roomService.SaveRoom(r); err != nil {
				return err
			}
		}
		// Reload rooms
		rooms, err = s.roomService.GetRooms()
		if err != nil {
			return err
		}
	}

	for _, r := range rooms {
		s.rooms.Store(r.ID, &room{
			id:        r.ID,
			group:     r.Group,
			order:     r.Order,
			permanent: r.Permanent,
			peers:     make(map[string]*peer),
		})
	}

	// Load groups
	groups, err := s.roomService.GetGroups()
	if err != nil {
		return err
	}
	for _, g := range groups {
		s.groups.Store(g, struct{}{})
	}

	// Start cleanup loop
	go s.startCleanupLoop()

	// Start latency broadcast loop
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			s.broadcastRoomsUpdate()
		}
	}()

	return nil
}

func (s *Server) startCleanupLoop() {
	// Initial cleanup
	_ = s.chatService.CleanupOldMessages(30)

	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	for range ticker.C {
		_ = s.chatService.CleanupOldMessages(30)
	}
}
