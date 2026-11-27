// admindev: 관리자 화면(admin/) 로컬 개발용 API 서버.
// 운영 DB 없이 메모리 SQLite에 예시 데이터를 넣고 /admin/v1만 띄운다. 로그인은 개발용 로그인 버튼.
//
//	cd server && go run ./cmd/admindev        # :3000, 화면은 admin/에서 npm run dev (:3001)
package main

import (
	"flag"
	"fmt"
	"log"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/ggorockee/reviewmaps/server/internal/admin"
	"github.com/ggorockee/reviewmaps/server/internal/adminapi"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

func main() {
	addr := flag.String("addr", ":3000", "listen address")
	origin := flag.String("origin", "http://localhost:3001", "admin UI origin")
	flag.Parse()

	g, err := gorm.Open(sqlite.Open("file:admindev?mode=memory&cache=shared"), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		log.Fatal(err)
	}
	if err := g.AutoMigrate(&models.User{}, &models.SocialAccount{}, &models.EmailVerification{}, &models.FCMDevice{},
		&models.Category{}, &models.Campaign{}, &models.Keyword{}, &models.KeywordAlert{}, &models.RawCategory{},
		&models.CategoryMapping{}, &models.AppSetting{}, &models.AppVersion{}, &models.AdConfig{},
		&models.RateLimitConfig{}, &models.AdminSession{}, &models.AdminAuditLog{}); err != nil {
		log.Fatal(err)
	}
	g.Exec(`CREATE TABLE local_search_cache (title_hash text primary key, title text, category text)`)
	seed(g)

	db := &database.DB{DB: g}
	app := fiber.New()
	adminapi.Mount(app, &adminapi.Options{
		DB:        db,
		Allowlist: admin.ParseAllowlist("dev@review-maps.local"),
		Sessions:  &admin.Sessions{DB: g, TTL: 12 * time.Hour},
		Origin:    *origin,
		DevEmail:  "dev@review-maps.local",
	})
	log.Printf("admindev: %s (UI origin %s)", *addr, *origin)
	log.Fatal(app.Listen(*addr))
}

func ptr[T any](v T) *T { return &v }

func seed(g *gorm.DB) {
	now := time.Now()
	names := []string{"맛집", "뷰티/헬스", "여행/숙박", "생활", "액티비티", "쇼핑", "반려동물", "문화"}
	cats := make([]models.Category, len(names))
	for i, n := range names {
		cats[i] = models.Category{Name: n, DisplayOrder: i + 1, CreatedAt: now}
		g.Create(&cats[i])
	}
	raws := []struct {
		text  string
		cat   int // 0이면 미매핑
		usage int
	}{
		{"음식점>한식>국밥", 1, 40}, {"음식점>한식>냉면", 1, 12}, {"음식점>카페", 1, 30}, {"미용>네일샵", 2, 9},
		{"1", 0, 120}, {"2", 0, 45}, {"음식점>한식>순대국", 0, 22}, {"음식점>일식>오마카세", 0, 8},
		{"미용>왁싱", 0, 5}, {"농업>곡물재배", 0, 1}, {"스포츠시설>파크골프장", 0, 3},
	}
	for i, r := range raws {
		rc := models.RawCategory{RawText: r.text, CreatedAt: now.Add(-time.Duration(i) * time.Hour)}
		g.Create(&rc)
		if r.cat > 0 {
			g.Create(&models.CategoryMapping{RawCategoryID: rc.ID, StandardCategoryID: cats[r.cat-1].ID})
		}
		for j := 0; j < r.usage; j++ {
			g.Exec(`INSERT INTO local_search_cache (title_hash, title, category) VALUES (?, ?, ?)`, fmt.Sprintf("%d-%d", i, j), "t", r.text)
		}
	}
	var users []models.User
	for i := 1; i <= 7; i++ {
		u := models.User{Username: fmt.Sprintf("user%d", i), Email: fmt.Sprintf("user%d@example.com", i), Password: "x",
			LoginMethod: []string{"google", "kakao", "apple", "email"}[i%4], Name: fmt.Sprintf("사용자%d", i), IsActive: i != 5,
			DateJoined: now.AddDate(0, 0, -i*3)}
		g.Create(&u)
		users = append(users, u)
		g.Create(&models.SocialAccount{UserID: u.ID, Provider: u.LoginMethod, ProviderUserID: fmt.Sprint(i), Email: ptr(u.Email), CreatedAt: u.DateJoined, UpdatedAt: u.DateJoined})
		g.Create(&models.FCMDevice{UserID: &u.ID, FCMToken: fmt.Sprintf("fcmtoken%02dabcdefghijklmnop", i), DeviceType: "ios", IsActive: true, CreatedAt: now, UpdatedAt: now})
	}
	for i := 0; i < 30; i++ {
		var cat *uint
		if i%2 == 0 {
			cat = &cats[i%len(cats)].ID
		}
		src := []string{"inflexer", "리뷰노트"}[i%2]
		c := models.Campaign{Platform: src, Source: &src, Company: fmt.Sprintf("가게 %d", i+1), Title: ptr(fmt.Sprintf("[체험] 가게 %d 방문 리뷰", i+1)),
			Offer: "2인 식사권", CategoryID: cat, ApplyDeadline: ptr(now.AddDate(0, 0, i%10)), ContentLink: ptr("https://example.com"),
			CreatedAt: now.Add(-time.Duration(i) * time.Hour), UpdatedAt: now}
		g.Create(&c)
		if i < 6 {
			kw := models.Keyword{UserID: &users[i].ID, Keyword: []string{"강남", "성수", "홍대", "네일", "카페", "부산"}[i], IsActive: i != 3, CreatedAt: now, UpdatedAt: now}
			g.Create(&kw)
			g.Create(&models.KeywordAlert{KeywordID: kw.ID, CampaignID: &c.ID, MatchedField: "title", IsRead: i%2 == 0, CreatedAt: now.AddDate(0, 0, -i*10), UpdatedAt: now})
		}
	}
	g.Create(&models.AppSetting{Key: "keyword_limit", Value: []byte("10"), Description: ptr("사용자당 키워드 최대 개수"), IsActive: true, CreatedAt: now, UpdatedAt: now})
	g.Create(&models.AppVersion{Platform: "ios", Version: "2.1.0", MinimumVersion: "2.0.0", IsActive: true})
	g.Create(&models.AppVersion{Platform: "android", Version: "2.1.0", MinimumVersion: "2.0.0", IsActive: true})
}
