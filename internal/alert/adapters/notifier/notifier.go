package notifier

import (
	"context"
	"fmt"
	"log/slog"
	"net/smtp"
	"strings"

	"github.com/quyenhl16/ckad-advanced-observability/internal/alert/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type MailSender interface {
	Send(context.Context, domain.User, domain.Alert) error
}

type SubscriptionNotifier struct {
	repository application.NotificationRepository
	sender     MailSender
}

func NewSubscriptionNotifier(repository application.NotificationRepository, sender MailSender) *SubscriptionNotifier {
	return &SubscriptionNotifier{repository: repository, sender: sender}
}

func (n *SubscriptionNotifier) Notify(ctx context.Context, alert domain.Alert) {
	users, err := n.repository.MatchingUsers(ctx, alert)
	if err != nil {
		slog.Error("find alert subscribers", "error", err)
		return
	}
	for _, user := range users {
		if err := n.sender.Send(ctx, user, alert); err != nil {
			slog.Error("send alert email", "email", user.Email, "error", err)
		}
	}
}

type LogSender struct{}

func (LogSender) Send(_ context.Context, user domain.User, alert domain.Alert) error {
	slog.Info("alert email delivered", "to", user.Email, "user", user.Name, "device_type", alert.DeviceType,
		"device_id", alert.DeviceID, "trace_id", alert.TraceID, "latency_ms", alert.LatencyMS)
	return nil
}

type SMTPConfig struct{ Address, Host, Username, Password, From string }
type SMTPSender struct{ config SMTPConfig }

func NewSMTPSender(config SMTPConfig) (*SMTPSender, error) {
	if config.Address == "" || config.Host == "" || config.From == "" {
		return nil, fmt.Errorf("SMTP address, host and from are required")
	}
	return &SMTPSender{config: config}, nil
}

func (s *SMTPSender) Send(_ context.Context, user domain.User, alert domain.Alert) error {
	subject := fmt.Sprintf("Network alert: %s %s", alert.DeviceType, alert.DeviceID)
	body := fmt.Sprintf("Hello %s,\r\n\r\nDevice %s (%s) exceeded the latency threshold.\r\nLatency: %.1f ms\r\nThreshold: %.1f ms\r\nTrace ID: %s\r\nStatus: %s\r\n",
		user.Name, alert.DeviceID, alert.DeviceType, alert.LatencyMS, alert.ThresholdMS, alert.TraceID, alert.Status)
	message := []byte("To: " + user.Email + "\r\nSubject: " + subject + "\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n" + body)
	var auth smtp.Auth
	if strings.TrimSpace(s.config.Username) != "" {
		auth = smtp.PlainAuth("", s.config.Username, s.config.Password, s.config.Host)
	}
	return smtp.SendMail(s.config.Address, auth, s.config.From, []string{user.Email}, message)
}
