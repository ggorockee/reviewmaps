package email

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/smtp"
	"strings"

	"github.com/ggorockee/reviewmaps/server/internal/config"
)

type EmailService struct {
	cfg *config.Config
}

func NewEmailService(cfg *config.Config) *EmailService {
	return &EmailService{cfg: cfg}
}

// SendVerificationCode sends email verification code
func (s *EmailService) SendVerificationCode(toEmail, code string) error {
	subject := "[ReviewMaps] 이메일 인증코드"
	body := fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #4CAF50;">ReviewMaps 이메일 인증</h2>
        <p>안녕하세요,</p>
        <p>ReviewMaps 회원가입을 위한 인증코드입니다.</p>
        <div style="background-color: #f4f4f4; padding: 20px; border-radius: 5px; text-align: center; margin: 20px 0;">
            <h1 style="color: #4CAF50; font-size: 36px; margin: 0; letter-spacing: 5px;">%s</h1>
        </div>
        <p>인증코드는 <strong>10분간</strong> 유효합니다.</p>
        <p>본인이 요청하지 않은 경우, 이 이메일을 무시하셔도 됩니다.</p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
        <p style="color: #999; font-size: 12px;">
            이 이메일은 ReviewMaps에서 자동으로 발송되었습니다.<br>
            문의사항이 있으시면 고객센터로 연락주세요.
        </p>
    </div>
</body>
</html>
`, code)

	return s.sendEmail(toEmail, subject, body)
}

// sendEmail sends an email using SMTP
func (s *EmailService) sendEmail(to, subject, body string) error {
	// Gmail requires sender to match authenticated user
	from := s.cfg.EmailHostUser

	// Display name for From header (optional)
	displayFrom := from
	if s.cfg.DefaultFromEmail != "" {
		displayFrom = fmt.Sprintf("ReviewMaps <%s>", from)
	}

	// Set up authentication
	auth := smtp.PlainAuth("", s.cfg.EmailHostUser, s.cfg.EmailHostPassword, s.cfg.EmailHost)

	// Build message with proper RFC 5321 format
	headers := make(map[string]string)
	headers["From"] = displayFrom
	headers["To"] = to
	headers["Subject"] = subject
	headers["MIME-Version"] = "1.0"
	headers["Content-Type"] = "text/html; charset=UTF-8"
	headers["Content-Transfer-Encoding"] = "quoted-printable"

	message := ""
	for k, v := range headers {
		message += fmt.Sprintf("%s: %s\r\n", k, v)
	}
	message += "\r\n" + body

	// Server address
	addr := fmt.Sprintf("%s:%d", s.cfg.EmailHost, s.cfg.EmailPort)

	// Send email - use authenticated user as sender
	if s.cfg.EmailUseTLS {
		return s.sendMailTLS(addr, auth, from, []string{to}, []byte(message))
	}

	return smtp.SendMail(addr, auth, from, []string{to}, []byte(message))
}

// sendMailTLS sends email with STARTTLS
func (s *EmailService) sendMailTLS(addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	// Connect to server with plain TCP first
	host := strings.Split(addr, ":")[0]
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to dial: %w", err)
	}
	defer conn.Close()

	// Create SMTP client
	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return fmt.Errorf("failed to create client: %w", err)
	}
	defer client.Close()

	// Start TLS (STARTTLS command)
	tlsConfig := &tls.Config{
		ServerName: host,
	}
	if err = client.StartTLS(tlsConfig); err != nil {
		return fmt.Errorf("failed to start TLS: %w", err)
	}

	// Auth
	if auth != nil {
		if err = client.Auth(auth); err != nil {
			return fmt.Errorf("failed to authenticate: %w", err)
		}
	}

	// Set sender
	if err = client.Mail(from); err != nil {
		return fmt.Errorf("failed to set sender: %w", err)
	}

	// Set recipients
	for _, addr := range to {
		if err = client.Rcpt(addr); err != nil {
			return fmt.Errorf("failed to set recipient: %w", err)
		}
	}

	// Send data
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("failed to get data writer: %w", err)
	}

	_, err = w.Write(msg)
	if err != nil {
		return fmt.Errorf("failed to write message: %w", err)
	}

	err = w.Close()
	if err != nil {
		return fmt.Errorf("failed to close data writer: %w", err)
	}

	return client.Quit()
}
