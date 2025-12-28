package repository

import (
	"errors"

	"github.com/newton-miku/WeSpeek/internal/domain/entity"
)

var (
	ErrNotFound = errors.New("not found")
	ErrNotEmpty = errors.New("not empty")
)

type RoomRepository interface {
	GetRooms() ([]entity.Room, error)
	SaveRoom(room entity.Room) error
	DeleteRoom(id string) error
}

type GroupRepository interface {
	GetGroups() ([]string, error)
	SaveGroup(name string) error
	DeleteGroup(name string) error
}

type ChatRepository interface {
	SaveChatMessage(msg entity.ChatMessage) error
	GetChatHistory(roomID string, limit int) ([]entity.ChatMessage, error)
	DeleteOldChatMessages(retentionDays int) error
}

type AdminRepository interface {
	GetAdminSecrets() ([]string, error)
	AddAdminSecret(secret, description string) error
	DeleteAdminSecret(secret string) error
}
