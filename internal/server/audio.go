package server

import (
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

func (s *Server) AudioWSHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	q := r.URL.Query()
	uid := q.Get("uid")
	sid := q.Get("sid")
	if uid == "" || sid == "" {
		conn.Close()
		return
	}

	var rm *room
	var v interface{}
	var ok bool

	// Retry loop for Room existence (if it's a new room being created by join)
	for i := 0; i < 20; i++ {
		v, ok = s.rooms.Load(sid)
		if ok {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if !ok {
		conn.Close()
		return
	}
	rm = v.(*room)

	// Retry loop for Peer existence (race condition where WS 'join' hasn't processed yet)
	var p *peer

	for i := 0; i < 20; i++ { // Try for ~2 seconds
		rm.mu.RLock()
		p, ok = rm.peers[uid]
		rm.mu.RUnlock()
		if ok {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if !ok {
		conn.Close()
		return
	}

	// Audio Writer Loop
	sendCh := make(chan []byte, 256)
	var mu sync.Mutex
	closed := false

	p.audioSend = func(data []byte) {
		mu.Lock()
		defer mu.Unlock()
		if !closed {
			select {
			case sendCh <- data:
			default:
				atomic.AddInt64(&p.sentPacketsLost, 1)
			}
		}
	}

	defer func() {
		// Cleanup
		p.audioSend = nil
		mu.Lock()
		closed = true
		close(sendCh)
		mu.Unlock()
		conn.Close()
	}()

	go func() {
		for data := range sendCh {
			_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
			if err := conn.WriteMessage(websocket.BinaryMessage, data); err != nil {
				return
			}
			atomic.AddUint64(&p.packetsSent, 1)
			atomic.AddUint64(&p.bytesSent, uint64(len(data)))
		}
	}()

	// Audio Reader Loop
	for {
		mt, data, err := conn.ReadMessage()
		if err != nil {
			break
		}
		if mt == websocket.BinaryMessage {
			atomic.AddUint64(&p.packetsReceived, 1)
			atomic.AddUint64(&p.bytesReceived, uint64(len(data)))
			p.broadcastBinary(data)
		}
	}
}
