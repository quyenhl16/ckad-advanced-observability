package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/frontend/adapters/httpapi"
	"github.com/quyenhl16/ckad-advanced-observability/internal/frontend/adapters/web"
	"github.com/quyenhl16/ckad-advanced-observability/internal/frontend/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/config"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/server"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/telemetry"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx := context.Background()
	shutdown, err := telemetry.Initialize(ctx, "observability-frontend")
	if err != nil {
		fatal(err)
	}
	client := &http.Client{Timeout: 5 * time.Second}
	events := httpapi.NewClient(config.String("ANALYTICS_URL", "http://localhost:8081"), client)
	alerts := httpapi.NewClient(config.String("ALERT_MANAGER_URL", "http://localhost:8082"), client)
	handler, err := web.NewHandler(application.NewLoadDashboard(events, alerts, alerts))
	if err != nil {
		fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", httpx.Method(http.MethodGet, handler.Dashboard))
	mux.HandleFunc("/users", httpx.Method(http.MethodPost, handler.CreateUser))
	mux.HandleFunc("/subscriptions", httpx.Method(http.MethodPost, handler.CreateSubscription))
	mux.HandleFunc("/users/delete", httpx.Method(http.MethodPost, handler.DeleteUser))
	mux.HandleFunc("/subscriptions/delete", httpx.Method(http.MethodPost, handler.DeleteSubscription))
	mux.HandleFunc("/health/live", httpx.HealthHandler)
	mux.HandleFunc("/health/ready", httpx.HealthHandler)
	if err := server.Run(config.String("HTTP_ADDR", ":8083"), httpx.TraceMiddleware("observability-frontend", mux), shutdown); err != nil {
		fatal(err)
	}
}

func fatal(err error) { slog.Error("fatal error", "error", err); os.Exit(1) }
