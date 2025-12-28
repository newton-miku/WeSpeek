package server

import (
	"encoding/json"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

type Client struct {
	server   *Server
	conn     *websocket.Conn
	msgCh    chan interface{}
	peer     *peer
	id       string
	remoteIP string
}

func (s *Server) newClient(conn *websocket.Conn, id, ip string) *Client {
	return &Client{
		server:   s,
		conn:     conn,
		msgCh:    make(chan interface{}, 64),
		id:       id,
		remoteIP: ip,
	}
}

func (c *Client) writeLoop() {
	pingTicker := time.NewTicker(5 * time.Second)
	defer pingTicker.Stop()
	defer c.conn.Close()

	for {
		select {
		case m, ok := <-c.msgCh:
			if !ok {
				return
			}
			switch v := m.(type) {
			case []byte:
				_ = c.conn.WriteMessage(websocket.BinaryMessage, v)
			default:
				_ = c.conn.WriteJSON(v)
			}
		case <-pingTicker.C:
			// Send ping with current timestamp
			now := time.Now().UnixNano()
			_ = c.conn.WriteControl(websocket.PingMessage, []byte(fmt.Sprintf("%d", now)), time.Now().Add(time.Second))
		}
	}
}

func (c *Client) readLoop() {
	defer func() {
		if c.peer != nil {
			c.peer.close()
		}
		c.server.clients.Delete(c.id)
		close(c.msgCh)
		c.conn.Close()
	}()

	c.conn.SetPongHandler(func(appData string) error {
		if c.peer != nil {
			var sentTime int64
			fmt.Sscanf(appData, "%d", &sentTime)
			if sentTime > 0 {
				rtt := (time.Now().UnixNano() - sentTime) / 1e6 // ms
				atomic.StoreInt64(&c.peer.latency, rtt)
			}
		}
		return nil
	})

	for {
		mt, data, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		if mt == websocket.BinaryMessage {
			if c.peer != nil {
				atomic.AddUint64(&c.peer.bytesReceived, uint64(len(data)))
				atomic.AddUint64(&c.peer.packetsReceived, 1)
				c.peer.broadcastBinary(data)
			}
			continue
		}
		
		var m rpcMessage
		if err := json.Unmarshal(data, &m); err != nil {
			continue
		}
		
		c.server.dispatchRPC(c, m)
	}
}
