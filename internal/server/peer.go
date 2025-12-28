package server

import (
	"sync/atomic"

	"time"

	"github.com/newton-miku/WeSpeek/internal/util"
)

func (s *Server) newPeer(uid, name, ip string, rm *room, send func(interface{})) *peer {
	me := &peer{
		server:   s,
		uid:      uid,
		name:     name,
		ip:       ip,
		room:     rm,
		send:     send,
		joinTime: time.Now(),
	}

	rm.mu.Lock()
	rm.peers[uid] = me

	if rm.deleteTimer != nil {
		rm.deleteTimer.Stop()
		rm.deleteTimer = nil
	}
	rm.mu.Unlock()

	s.broadcastRoomUpdate(rm)
	s.broadcastRoomsUpdate()

	return me
}

func (p *peer) GetPeerStats() *UserStats {
	return &UserStats{
		BytesReceived:   atomic.LoadUint64(&p.bytesReceived),
		PacketsReceived: atomic.LoadUint64(&p.packetsReceived),
		BytesSent:       atomic.LoadUint64(&p.bytesSent),
		PacketsSent:     atomic.LoadUint64(&p.packetsSent),
		SentPacketsLost: atomic.LoadInt64(&p.sentPacketsLost),
	}
}

func (p *peer) close() {
	p.room.mu.Lock()
	delete(p.room.peers, p.uid)
	p.room.mu.Unlock()

	p.server.broadcastRoomUpdate(p.room)
	p.server.broadcastRoomsUpdate()
	p.server.scheduleRoomCleanup(p.room)
}

func (s *Server) doRename(p *peer, want string) {
	rm := p.room
	old := p.uid
	if old == want {
		return
	}
	target := want

	rm.mu.Lock()
	if _, exists := rm.peers[target]; exists {
		target = want + "-" + util.RandString()[:4]
	}
	delete(rm.peers, old)
	rm.peers[target] = p
	rm.mu.Unlock()

	p.uid = target
	// No tracks to remap
	s.broadcastRoomUpdate(rm)
	s.broadcastRoomsUpdate()
}
