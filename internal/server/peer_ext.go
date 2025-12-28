package server

import "sync/atomic"

func (p *peer) broadcastBinary(data []byte) {
	if p.room == nil {
		return
	}
	// Payload format: [UID_LEN][UID][DATA]
	uidBytes := []byte(p.uid)
	if len(uidBytes) > 255 {
		// Should not happen for normal UIDs, but safeguard
		uidBytes = uidBytes[:255]
	}
	payload := make([]byte, 1+len(uidBytes)+len(data))
	payload[0] = byte(len(uidBytes))
	copy(payload[1:], uidBytes)
	copy(payload[1+len(uidBytes):], data)

	p.room.mu.RLock()
	defer p.room.mu.RUnlock()

	for _, other := range p.room.peers {
		if other.uid == p.uid {
			continue
		}

		atomic.AddUint64(&other.bytesSent, uint64(len(payload)))
		atomic.AddUint64(&other.packetsSent, 1)

		if other.audioSend != nil {
			other.audioSend(payload)
		} else {
			other.send(payload)
		}
	}
}
