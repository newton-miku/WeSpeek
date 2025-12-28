package sqlite

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"github.com/newton-miku/WeSpeek/internal/domain/entity"
	"github.com/newton-miku/WeSpeek/internal/store"
)

type SqliteStore struct {
	db *sql.DB
}

func New(path string) (*SqliteStore, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return nil, fmt.Errorf("failed to create db directory: %w", err)
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open db: %w", err)
	}

	s := &SqliteStore{db: db}
	if err := s.init(); err != nil {
		db.Close()
		return nil, err
	}

	return s, nil
}

func (s *SqliteStore) init() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS rooms (
			id TEXT PRIMARY KEY,
			group_name TEXT,
			sort_order INTEGER,
			permanent INTEGER
		);`,
		`CREATE TABLE IF NOT EXISTS groups (
			name TEXT PRIMARY KEY
		);`,
		`CREATE TABLE IF NOT EXISTS admin_secrets (
			secret TEXT PRIMARY KEY,
			description TEXT,
			created_at INTEGER
		);`,
		`CREATE TABLE IF NOT EXISTS chat_messages (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			room_id TEXT,
			uid TEXT,
			name TEXT,
			text TEXT,
			created_at INTEGER
		);`,
		`CREATE INDEX IF NOT EXISTS idx_chat_room_time ON chat_messages(room_id, created_at);`,
	}

	for _, q := range queries {
		if _, err := s.db.Exec(q); err != nil {
			return fmt.Errorf("init query failed: %w", err)
		}
	}
	return nil
}

func (s *SqliteStore) Close() error {
	return s.db.Close()
}

func (s *SqliteStore) GetRooms() ([]entity.Room, error) {
	rows, err := s.db.Query("SELECT id, group_name, sort_order, permanent FROM rooms")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rooms []entity.Room
	for rows.Next() {
		var r entity.Room
		var perm int
		if err := rows.Scan(&r.ID, &r.Group, &r.Order, &perm); err != nil {
			return nil, err
		}
		r.Permanent = perm == 1
		rooms = append(rooms, r)
	}
	return rooms, nil
}

func (s *SqliteStore) GetRoom(id string) (*entity.Room, error) {
	row := s.db.QueryRow("SELECT id, group_name, sort_order, permanent FROM rooms WHERE id = ?", id)
	var r entity.Room
	var perm int
	if err := row.Scan(&r.ID, &r.Group, &r.Order, &perm); err != nil {
		if err == sql.ErrNoRows {
			return nil, store.ErrNotFound
		}
		return nil, err
	}
	r.Permanent = perm == 1
	return &r, nil
}

func (s *SqliteStore) SaveRoom(r entity.Room) error {
	perm := 0
	if r.Permanent {
		perm = 1
	}
	_, err := s.db.Exec(`
		INSERT INTO rooms (id, group_name, sort_order, permanent)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
		group_name = excluded.group_name,
		sort_order = excluded.sort_order,
		permanent = excluded.permanent
	`, r.ID, r.Group, r.Order, perm)
	return err
}

func (s *SqliteStore) DeleteRoom(id string) error {
	_, err := s.db.Exec("DELETE FROM rooms WHERE id = ?", id)
	return err
}

func (s *SqliteStore) GetGroups() ([]string, error) {
	rows, err := s.db.Query("SELECT name FROM groups")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var groups []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		groups = append(groups, name)
	}
	return groups, nil
}

func (s *SqliteStore) SaveGroup(name string) error {
	_, err := s.db.Exec("INSERT OR IGNORE INTO groups (name) VALUES (?)", name)
	return err
}

func (s *SqliteStore) DeleteGroup(name string) error {
	_, err := s.db.Exec("DELETE FROM groups WHERE name = ?", name)
	return err
}

func (s *SqliteStore) GetAdminSecrets() ([]string, error) {
	rows, err := s.db.Query("SELECT secret FROM admin_secrets")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var secrets []string
	for rows.Next() {
		var secret string
		if err := rows.Scan(&secret); err != nil {
			return nil, err
		}
		secrets = append(secrets, secret)
	}
	return secrets, nil
}

func (s *SqliteStore) AddAdminSecret(secret, description string) error {
	_, err := s.db.Exec("INSERT OR IGNORE INTO admin_secrets (secret, description, created_at) VALUES (?, ?, strftime('%s', 'now'))", secret, description)
	return err
}

func (s *SqliteStore) DeleteAdminSecret(secret string) error {
	_, err := s.db.Exec("DELETE FROM admin_secrets WHERE secret = ?", secret)
	return err
}

func (s *SqliteStore) SaveChatMessage(msg entity.ChatMessage) error {
	_, err := s.db.Exec(`
		INSERT INTO chat_messages (room_id, uid, name, text, created_at)
		VALUES (?, ?, ?, ?, ?)
	`, msg.RoomID, msg.UID, msg.Name, msg.Text, msg.CreatedAt)
	return err
}

func (s *SqliteStore) GetChatHistory(roomID string, limit int) ([]entity.ChatMessage, error) {
	rows, err := s.db.Query(`
		SELECT id, room_id, uid, name, text, created_at
		FROM chat_messages
		WHERE room_id = ?
		ORDER BY created_at DESC
		LIMIT ?
	`, roomID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []entity.ChatMessage
	for rows.Next() {
		var m entity.ChatMessage
		if err := rows.Scan(&m.ID, &m.RoomID, &m.UID, &m.Name, &m.Text, &m.CreatedAt); err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}

	// Reverse to return chronological order
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}

	return msgs, nil
}

func (s *SqliteStore) DeleteOldChatMessages(retentionDays int) error {
	cutoff := time.Now().AddDate(0, 0, -retentionDays).Unix()
	_, err := s.db.Exec("DELETE FROM chat_messages WHERE created_at < ?", cutoff)
	return err
}
