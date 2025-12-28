package service

import (
	"github.com/newton-miku/WeSpeek/internal/domain/entity"
	"github.com/newton-miku/WeSpeek/internal/domain/repository"
)

type ChatService struct {
	repo repository.ChatRepository
}

func NewChatService(repo repository.ChatRepository) *ChatService {
	return &ChatService{repo: repo}
}

func (s *ChatService) SaveMessage(msg entity.ChatMessage) error {
	return s.repo.SaveChatMessage(msg)
}

func (s *ChatService) GetChatHistory(roomID string, limit int) ([]entity.ChatMessage, error) {
	return s.repo.GetChatHistory(roomID, limit)
}

func (s *ChatService) GetPublicHistory() []entity.ChatMessage {
	msgs, _ := s.repo.GetChatHistory("", 50)
	if msgs == nil {
		return []entity.ChatMessage{}
	}
	return msgs
}

func (s *ChatService) GetRoomHistory(roomID string) []entity.ChatMessage {
	msgs, _ := s.repo.GetChatHistory(roomID, 50)
	if msgs == nil {
		return []entity.ChatMessage{}
	}
	return msgs
}

func (s *ChatService) CleanupOldMessages(days int) error {
	return s.repo.DeleteOldChatMessages(days)
}
