package sns

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// GoogleUserInfo represents Google user information
type GoogleUserInfo struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	Name         string `json:"name"`
	ProfileImage string `json:"profile_image"`
}

// GoogleAPIResponse represents Google UserInfo API response
type GoogleAPIResponse struct {
	ID            string `json:"id"`
	Email         string `json:"email"`
	VerifiedEmail bool   `json:"verified_email"`
	Name          string `json:"name"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
	Picture       string `json:"picture"`
}

// VerifyGoogleToken verifies Google access token and returns user info
func VerifyGoogleToken(ctx context.Context, accessToken string) (*GoogleUserInfo, error) {
	client := &http.Client{Timeout: 10 * time.Second}

	req, err := http.NewRequestWithContext(ctx, "GET", "https://www.googleapis.com/oauth2/v2/userinfo", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+accessToken)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("google API returned status %d", resp.StatusCode)
	}

	var googleResp GoogleAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&googleResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if googleResp.ID == "" {
		return nil, fmt.Errorf("invalid google user id")
	}

	if !googleResp.VerifiedEmail {
		return nil, fmt.Errorf("email not verified")
	}

	return &GoogleUserInfo{
		ID:           googleResp.ID,
		Email:        googleResp.Email,
		Name:         googleResp.Name,
		ProfileImage: googleResp.Picture,
	}, nil
}
