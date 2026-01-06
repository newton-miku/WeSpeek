package server

import (
	"errors"
	"io"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/newton-miku/WeSpeek/internal/domain/entity"
	"github.com/newton-miku/WeSpeek/internal/domain/repository"
	"github.com/newton-miku/WeSpeek/internal/service"
	"github.com/newton-miku/WeSpeek/internal/store"
)

type Server struct {
	roomService  *service.RoomService
	chatService  *service.ChatService
	adminService *service.AdminService
	mediaService *service.MediaService
	fileStore    repository.FileStore

	// State
	rooms           sync.Map // map[string]*room
	clients         sync.Map // map[string]func(interface{})
	latencySubs     sync.Map // map[string]func(interface{})
	adminChallenges sync.Map
	groups          sync.Map // map[string]struct{}

	// Config
	StoreImagesAsFiles bool
	AllowUploads       bool

	startTime time.Time
}

func (s *Server) GetServerStats() ServerStats {
	var stats ServerStats
	stats.Rooms = []RoomStats{}

	var totalPing int64
	var totalQueue int
	var pingCount int
	var queueCount int

	s.rooms.Range(func(key, value interface{}) bool {
		r := value.(*room)
		stats.RoomCount++

		rs := RoomStats{
			ID: r.id,
		}
		// If description is used as name
		rs.Name = r.description

		var roomTotalPing int64
		var roomPingCount int

		r.mu.RLock()
		rs.PeerCount = len(r.peers)
		for _, p := range r.peers {
			stats.PeerCount++

			// Ping
			l := atomic.LoadInt64(&p.latency)
			if l > 0 {
				totalPing += l
				pingCount++
				roomTotalPing += l
				roomPingCount++
			}

			// Queue
			if p.getAudioQueueSize != nil {
				totalQueue += p.getAudioQueueSize()
				queueCount++
			}

			// Traffic
			pSent := atomic.LoadUint64(&p.bytesSent)
			pRecv := atomic.LoadUint64(&p.bytesReceived)

			stats.TotalBytesSent += pSent
			stats.TotalBytesReceived += pRecv
			rs.BytesSent += pSent
			rs.BytesReceived += pRecv

			stats.TotalPacketsSent += atomic.LoadUint64(&p.packetsSent)
			stats.TotalPacketsLost += atomic.LoadInt64(&p.sentPacketsLost)
		}
		r.mu.RUnlock()

		if roomPingCount > 0 {
			rs.AvgPing = float64(roomTotalPing) / float64(roomPingCount)
		}
		stats.Rooms = append(stats.Rooms, rs)

		return true
	})

	if pingCount > 0 {
		stats.AvgPing = float64(totalPing) / float64(pingCount)
	}
	if queueCount > 0 {
		stats.AvgQueueSize = float64(totalQueue) / float64(queueCount)
	}

	// System Stats
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)
	stats.GoroutineCount = runtime.NumGoroutine()
	stats.AllocMemory = memStats.Alloc
	stats.TotalAllocMemory = memStats.TotalAlloc
	stats.SysMemory = memStats.Sys
	stats.Uptime = int64(time.Since(s.startTime).Seconds())

	return stats
}

func New(s store.Store, fs repository.FileStore, storeImagesAsFiles bool, allowUploads bool) *Server {
	ms := service.NewMediaService(fs, allowUploads)
	return &Server{
		roomService:        service.NewRoomService(s, s),
		chatService:        service.NewChatService(s, ms),
		adminService:       service.NewAdminService(s),
		mediaService:       ms,
		fileStore:          fs,
		StoreImagesAsFiles: storeImagesAsFiles,
		AllowUploads:       allowUploads, // Default allow
		startTime:          time.Now(),
	}
}

func (s *Server) GetFileStore() repository.FileStore {
	return s.fileStore
}

func (s *Server) SaveImage(filename string, r io.Reader) (string, error) {
	if s.mediaService == nil {
		// Just in case Init wasn't called or something
		return "", errors.New("media service not initialized")
	}
	return s.mediaService.SaveImage(filename, r)
}

func (s *Server) Init() error {
	// Initialize MediaService
	s.mediaService = service.NewMediaService(s.fileStore, s.AllowUploads)
	// Update ChatService with new MediaService
	// Note: We need to access the repo from existing chatService or re-create it.
	// Since we don't expose repo, we can't easily re-create it without the store.
	// However, s.chatService is created in New with 's' (store).
	// But Server struct doesn't keep 's' (store).
	// Wait, Server struct DOES NOT keep the store interface.

	// Issue: Server struct in line 16 does not have 'store' field.
	// New takes 'store.Store' but doesn't save it in Server struct.
	// So we cannot re-create ChatService here unless we change Server struct.

	// BUT, we can just assume MediaService created in New is sufficient?
	// No, Init is called later, potentially after config load (AllowUploads).
	// If AllowUploads changes, we need to update MediaService.

	// Solution: Add SetMediaService to ChatService?
	// Or simply update the mediaService instance in place? No.

	// Let's check if we can add 'store' to Server struct.
	// Or just update ChatService.

	// Actually, ChatService depends on MediaService for deletion.
	// If MediaService changes (e.g. AllowUploads flag), deletion should still work?
	// Yes, deletion only depends on FileStore, which doesn't change.
	// AllowUploads only affects Save.
	// So even if we have an "old" MediaService in ChatService with old AllowUploads, DeleteFile will still work as long as FileStore is valid.
	// And FileStore is 's.fileStore' which is constant.

	// However, it's better to keep them in sync.
	// Let's see if we can easily add SetMediaService.

	// I'll add SetMediaService to ChatService.

	// For now, let's just update Init to re-create MediaService and try to update ChatService.
	// Since I can't re-create ChatService without Store, I'll add SetMediaService.

	// Step 1: Add SetMediaService to ChatService.
	// Step 2: Call it in Init.

	s.mediaService = service.NewMediaService(s.fileStore, s.AllowUploads)
	if s.chatService != nil {
		s.chatService.SetMediaService(s.mediaService)
	}

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
			id:           r.ID,
			group:        r.Group,
			order:        r.Order,
			audioCodec:   r.AudioCodec,
			audioQuality: r.AudioQuality,
			permanent:    r.Permanent,
			peers:        make(map[string]*peer),
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
