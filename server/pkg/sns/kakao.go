package sns

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// KakaoUserInfo represents Kakao user information
type KakaoUserInfo struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	Name         string `json:"name"`
	ProfileImage string `json:"profile_image"`
}

// KakaoAPIResponse represents Kakao API response structure
type KakaoAPIResponse struct {
	ID           int64 `json:"id"`
	KakaoAccount struct {
		Email   string `json:"email"`
		Profile struct {
			Nickname        string `json:"nickname"`
			ProfileImageURL string `json:"profile_image_url"`
			ThumbnailURL    string `json:"thumbnail_image_url"`
		} `json:"profile"`
	} `json:"kakao_account"`
	Properties struct {
		Nickname string `json:"nickname"`
	} `json:"properties"`
}

// VerifyKakaoToken verifies Kakao access token and returns user info
func VerifyKakaoToken(ctx context.Context, accessToken string) (*KakaoUserInfo, error) {
	client := &http.Client{Timeout: 10 * time.Second}

	req, err := http.NewRequestWithContext(ctx, "GET", "https://kapi.kakao.com/v2/user/me", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded;charset=utf-8")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("kakao API returned status %d", resp.StatusCode)
	}

	var kakaoResp KakaoAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&kakaoResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if kakaoResp.ID == 0 {
		return nil, fmt.Errorf("invalid kakao user id")
	}

	// Extract user info
	name := kakaoResp.KakaoAccount.Profile.Nickname
	if name == "" {
		name = kakaoResp.Properties.Nickname
	}

	profileImage := kakaoResp.KakaoAccount.Profile.ProfileImageURL
	if profileImage == "" {
		profileImage = kakaoResp.KakaoAccount.Profile.ThumbnailURL
	}

	return &KakaoUserInfo{
		ID:           fmt.Sprintf("%d", kakaoResp.ID),
		Email:        kakaoResp.KakaoAccount.Email,
		Name:         name,
		ProfileImage: profileImage,
	}, nil
}
