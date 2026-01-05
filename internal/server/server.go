package server

import (
	"sync"
	"sync/atomic"
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
	latencySubs     sync.Map // map[string]func(interface{})
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
			audioCodec: r.AudioCodec,
			audioQuality: r.AudioQuality,
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
	go s.startLatencyLoop()

	return nil
}

func (s *Server) startLatencyLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		// Collect latencies
		latencies := make(map[string]int64)
		s.rooms.Range(func(_, value any) bool {
			rm := value.(*room)
			rm.mu.RLock()
			for uid, p := range rm.peers {
				l := atomic.LoadInt64(&p.latency)
				if l > 0 {
					latencies[uid] = l
				}
			}
			rm.mu.RUnlock()
			return true
		})

		if len(latencies) == 0 {
			continue
		}

		// Broadcast to subscribers
		out := struct {
			Method string           `json:"method"`
			Params map[string]int64 `json:"params"`
		}{
			Method: "latency.update",
			Params: latencies,
		}

		s.latencySubs.Range(func(key, value any) bool {
			if fn, ok := value.(func(interface{})); ok {
				fn(out)
			}
			return true
		})
	}
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
