package service

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"sync"
	"time"

	"github.com/newton-miku/WeSpeek/internal/domain/repository"
	"github.com/newton-miku/WeSpeek/internal/util"
)

type AdminService struct {
	repo            repository.AdminRepository
	adminSecrets    sync.Map // map[string]struct{}
	adminChallenges sync.Map // map[string]int64 (nonce -> expiry)
	adminOTT        string
	adminMu         sync.Mutex
}

func NewAdminService(repo repository.AdminRepository) *AdminService {
	s := &AdminService{
		repo: repo,
	}
	// Load secrets
	secrets, _ := repo.GetAdminSecrets()
	for _, sec := range secrets {
		s.adminSecrets.Store(sec, struct{}{})
	}
	return s
}

func (s *AdminService) CreateAdminChallenge() (string, int64) {
	nonce := util.RandString() + util.RandString()
	exp := time.Now().Add(30 * time.Minute).Unix()
	s.adminChallenges.Store(nonce, exp)
	return nonce, exp
}

func (s *AdminService) VerifyAdmin(nonce, macHex string) bool {
	// 1. Check if it's a direct secret (backwards compatibility / simple auth)
	if _, ok := s.adminSecrets.Load(nonce); ok {
		return true
	}

	// 2. Check OTT
	s.adminMu.Lock()
	ott := s.adminOTT
	s.adminMu.Unlock()
	if ott != "" && nonce == ott {
		return true
	}

	// 3. HMAC Verification
	v, ok := s.adminChallenges.Load(nonce)
	if !ok {
		return false
	}
	exp := v.(int64)
	if time.Now().Unix() > exp {
		s.adminChallenges.Delete(nonce)
		return false
	}

	verified := false
	s.adminSecrets.Range(func(key, _ interface{}) bool {
		secret := key.(string)
		mac := hmac.New(sha256.New, []byte(secret))
		_, _ = mac.Write([]byte(nonce))
		sum := mac.Sum(nil)
		if strings.EqualFold(hex.EncodeToString(sum), macHex) {
			verified = true
			return false // stop iteration
		}
		return true
	})

	if verified {
		// s.adminChallenges.Delete(nonce) // reuse allowed within window
		return true
	}
	return false
}

func (s *AdminService) CreateLoginSecret(desc string) (string, error) {
	secret := util.RandStringLen(32)
	s.adminSecrets.Store(secret, struct{}{})
	err := s.repo.AddAdminSecret(secret, desc)
	return secret, err
}

func (s *AdminService) GetOTT() string {
	s.adminMu.Lock()
	defer s.adminMu.Unlock()
	return s.adminOTT
}

func (s *AdminService) GenerateOTT() string {
	s.adminMu.Lock()
	defer s.adminMu.Unlock()

	s.adminOTT = util.RandStringLen(16)
	// Clear after 10 minutes (Setup link validity)
	go func(ott string) {
		time.Sleep(10 * time.Minute)
		s.adminMu.Lock()
		if s.adminOTT == ott {
			s.adminOTT = ""
		}
		s.adminMu.Unlock()
	}(s.adminOTT)

	return s.adminOTT
}

func (s *AdminService) VerifyAdminSetup(token string) (string, error) {
	s.adminMu.Lock()
	defer s.adminMu.Unlock()

	if s.adminOTT == "" || token != s.adminOTT {
		return "", repository.ErrNotFound // Or standard error
	}

	// Generate a new unique secret for this user
	newSecret := util.RandStringLen(32)
	// Store in DB
	if err := s.repo.AddAdminSecret(newSecret, "Setup via Link"); err != nil {
		return "", err
	}
	// Update memory
	s.adminSecrets.Store(newSecret, struct{}{})

	// Invalidate the OTT
	s.adminOTT = ""

	return newSecret, nil
}

func (s *AdminService) HasSecrets() bool {
	has := false
	s.adminSecrets.Range(func(_, _ interface{}) bool {
		has = true
		return false
	})
	return has
}
