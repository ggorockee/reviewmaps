package firebase

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"sync"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// FCMService handles Firebase Cloud Messaging operations
type FCMService struct {
	client *messaging.Client
	mu     sync.RWMutex
}

var (
	fcmService *FCMService
	fcmOnce    sync.Once
)

// GetFCMService returns singleton FCM service instance
func GetFCMService() *FCMService {
	fcmOnce.Do(func() {
		fcmService = &FCMService{}
		fcmService.initialize()
	})
	return fcmService
}

func (s *FCMService) initialize() {
	ctx := context.Background()

	// Try environment variable first (K8s Secret)
	credJSON := os.Getenv("FIREBASE_CREDENTIALS")
	var app *firebase.App
	var err error

	if credJSON != "" {
		// Parse JSON to validate
		var credMap map[string]interface{}
		if err := json.Unmarshal([]byte(credJSON), &credMap); err != nil {
			log.Printf("[Firebase] Invalid JSON in FIREBASE_CREDENTIALS: %v", err)
			return
		}

		opt := option.WithCredentialsJSON([]byte(credJSON))
		app, err = firebase.NewApp(ctx, nil, opt)
	} else {
		// Try file path
		credPath := os.Getenv("FIREBASE_CREDENTIALS_PATH")
		if credPath == "" {
			credPath = "secrets/firebase-service-account.json"
		}

		if _, err := os.Stat(credPath); os.IsNotExist(err) {
			log.Printf("[Firebase] Credentials file not found: %s", credPath)
			return
		}

		opt := option.WithCredentialsFile(credPath)
		app, err = firebase.NewApp(ctx, nil, opt)
	}

	if err != nil {
		log.Printf("[Firebase] Failed to initialize app: %v", err)
		return
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[Firebase] Failed to get messaging client: %v", err)
		return
	}

	s.client = client
	log.Println("[Firebase] Successfully initialized")
}

// IsInitialized returns whether FCM is ready
func (s *FCMService) IsInitialized() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.client != nil
}

// SendPushResult represents the result of a push operation
type SendPushResult struct {
	SuccessCount int
	FailureCount int
	FailedTokens []string
}

// SendPush sends a push notification to a single device
func (s *FCMService) SendPush(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.client == nil {
		log.Println("[Firebase] Not initialized, skipping push")
		return false, nil
	}

	message := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data:  data,
		Token: token,
	}

	response, err := s.client.Send(ctx, message)
	if err != nil {
		if messaging.IsUnregistered(err) {
			log.Printf("[Firebase] Token unregistered: %s...", token[:min(20, len(token))])
			return false, nil
		}
		log.Printf("[Firebase] Push error: %v", err)
		return false, err
	}

	log.Printf("[Firebase] Push sent successfully: %s", response)
	return true, nil
}

// SendPushMultiple sends push notifications to multiple devices
func (s *FCMService) SendPushMultiple(ctx context.Context, tokens []string, title, body string, data map[string]string) *SendPushResult {
	result := &SendPushResult{
		FailedTokens: make([]string, 0),
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.client == nil {
		log.Println("[Firebase] Not initialized, skipping push")
		result.FailureCount = len(tokens)
		result.FailedTokens = tokens
		return result
	}

	if len(tokens) == 0 {
		return result
	}

	message := &messaging.MulticastMessage{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data:   data,
		Tokens: tokens,
	}

	response, err := s.client.SendEachForMulticast(ctx, message)
	if err != nil {
		log.Printf("[Firebase] Multicast error: %v", err)
		result.FailureCount = len(tokens)
		result.FailedTokens = tokens
		return result
	}

	result.SuccessCount = response.SuccessCount
	result.FailureCount = response.FailureCount

	// Collect failed tokens
	for idx, resp := range response.Responses {
		if !resp.Success {
			result.FailedTokens = append(result.FailedTokens, tokens[idx])
		}
	}

	log.Printf("[Firebase] Multicast sent - success: %d, failure: %d", result.SuccessCount, result.FailureCount)
	return result
}
