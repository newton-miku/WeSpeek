package server

import (
	"encoding/json"
	"sync"
	"time"
)

type joinParams struct {
	SID  string `json:"sid"`
	UID  string `json:"uid"`
	Name string `json:"name"`
}

type rpcMessage struct {
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}

type peer struct {
	server         *Server
	uid            string
	name           string
	ip             string
	room           *room
	joinTime       time.Time
	send           func(interface{})
	audioSend      func([]byte)
	inputDisabled  bool
	outputDisabled bool
	latency        int64

	// Stats (atomic)
	bytesReceived   uint64
	packetsReceived uint64
	bytesSent       uint64
	packetsSent     uint64
	sentPacketsLost int64
}

type adminUserInfoResponse struct {
	UID   string     `json:"uid"`
	Name  string     `json:"name"`
	IP    string     `json:"ip,omitempty"`
	Room  string     `json:"room"`
	Stats *UserStats `json:"stats,omitempty"`
}

type UserStats struct {
	BytesReceived   uint64 `json:"bytesReceived"`
	PacketsReceived uint64 `json:"packetsReceived"`
	PacketsLost     int64  `json:"packetsLost"`

	BytesSent       uint64 `json:"bytesSent"`
	PacketsSent     uint64 `json:"packetsSent"`
	SentPacketsLost int64  `json:"sentPacketsLost"`
}

type room struct {
	mu          sync.RWMutex
	id          string
	group       string
	description string
	order       int
	audioCodec  string
	audioQuality int
	peers       map[string]*peer
	permanent   bool
	deleteTimer *time.Timer
}

type memberInfo struct {
	UID            string `json:"uid"`
	Name           string `json:"name"`
	InputDisabled  bool   `json:"inputDisabled"`
	OutputDisabled bool   `json:"outputDisabled"`
	Latency        int64  `json:"latency"`
}

type ChatMessage struct {
	UID  string `json:"uid"`
	Name string `json:"name"`
	Text string `json:"text"`
	Time int64  `json:"time"`
}

type RoomInfo struct {
	ID          string              `json:"id"`
	Group       string              `json:"group"`
	Description string              `json:"description"`
	Order       int                 `json:"order"`
	AudioCodec  string              `json:"audioCodec"`
	AudioQuality int                `json:"audioQuality"`
	Count       int                 `json:"count"`
	Members     []RoomMemberSummary `json:"members"`
	Permanent   bool                `json:"permanent"`
}

type RoomMemberSummary struct {
	UID            string `json:"uid"`
	Name           string `json:"name"`
	InputDisabled  bool   `json:"inputDisabled"`
	OutputDisabled bool   `json:"outputDisabled"`
	Latency        int64  `json:"latency"`
	JoinTime       int64  `json:"joinTime"`
}

type roomsUpdateParams struct {
	Rooms  []RoomInfo `json:"rooms"`
	Groups []string   `json:"groups"`
}
