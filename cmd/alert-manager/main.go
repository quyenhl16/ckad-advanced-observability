package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"

	httpadapter "github.com/example/ckad-advanced-observability/internal/alert/adapters/http"
	"github.com/example/ckad-advanced-observability/internal/alert/adapters/memory"
	"github.com/example/ckad-advanced-observability/internal/alert/adapters/notifier"
	"github.com/example/ckad-advanced-observability/internal/alert/adapters/postgres"
	"github.com/example/ckad-advanced-observability/internal/alert/application"
	"github.com/example/ckad-advanced-observability/internal/platform/config"
	"github.com/example/ckad-advanced-observability/internal/platform/httpx"
	"github.com/example/ckad-advanced-observability/internal/platform/server"
	"github.com/example/ckad-advanced-observability/internal/platform/telemetry"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx := context.Background()
	shutdown, err := telemetry.Initialize(ctx, "alert-manager")
	if err != nil {
		fatal(err)
	}
	var repository application.AlertRepository
	if config.String("ALERT_REPOSITORY", "postgres") == "memory" {
		repository = memory.New()
		slog.Warn("using volatile in-memory alert repository")
	} else {
		postgresRepository, err := postgres.New(ctx, os.Getenv("DATABASE_URL"))
		if err != nil {
			fatal(err)
		}
		defer postgresRepository.Close()
		if err := postgresRepository.Migrate(ctx); err != nil {
			fatal(err)
		}
		repository = postgresRepository
	}
	notificationRepository := repository.(application.NotificationRepository)
	var mailSender notifier.MailSender = notifier.LogSender{}
	if config.String("ALERT_NOTIFIER", "log") == "smtp" {
		smtpSender, err := notifier.NewSMTPSender(notifier.SMTPConfig{Address: os.Getenv("SMTP_ADDRESS"), Host: os.Getenv("SMTP_HOST"), Username: os.Getenv("SMTP_USERNAME"), Password: os.Getenv("SMTP_PASSWORD"), From: os.Getenv("SMTP_FROM")})
		if err != nil {
			fatal(err)
		}
		mailSender = smtpSender
	}
	dispatcher := notifier.NewSubscriptionNotifier(notificationRepository, mailSender)
	manage := application.NewManageNotifications(notificationRepository)
	handler := httpadapter.NewHandler(application.NewCreateAlert(repository, dispatcher), application.NewListAlerts(repository), os.Getenv("ALERT_API_KEY"), repository, manage)
	mux := http.NewServeMux()
	mux.HandleFunc("/health/live", httpx.HealthHandler)
	mux.HandleFunc("/health/ready", handler.Ready)
	mux.HandleFunc("/internal/v1/alerts", httpx.Method(http.MethodPost, handler.Create))
	mux.HandleFunc("/api/v1/alerts", httpx.Method(http.MethodGet, handler.List))
	mux.HandleFunc("/api/v1/users", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			handler.CreateUser(w, r)
		} else if r.Method == http.MethodGet {
			handler.ListUsers(w, r)
		} else {
			httpx.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/api/v1/subscriptions", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			handler.CreateSubscription(w, r)
		} else if r.Method == http.MethodGet {
			handler.ListSubscriptions(w, r)
		} else {
			httpx.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("DELETE /api/v1/users/{id}", handler.DeleteUser)
	mux.HandleFunc("DELETE /api/v1/subscriptions/{id}", handler.DeleteSubscription)
	if err := server.Run(config.String("HTTP_ADDR", ":8082"), httpx.TraceMiddleware("alert-manager", mux), shutdown); err != nil {
		fatal(err)
	}
}

func fatal(err error) { slog.Error("fatal error", "error", err); os.Exit(1) }
