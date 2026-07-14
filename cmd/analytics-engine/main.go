package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"time"

	fileadapter "github.com/example/ckad-advanced-observability/internal/analytics/adapters/file"
	httpadapter "github.com/example/ckad-advanced-observability/internal/analytics/adapters/http"
	"github.com/example/ckad-advanced-observability/internal/analytics/application"
	"github.com/example/ckad-advanced-observability/internal/platform/config"
	"github.com/example/ckad-advanced-observability/internal/platform/httpx"
	"github.com/example/ckad-advanced-observability/internal/platform/server"
	"github.com/example/ckad-advanced-observability/internal/platform/telemetry"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx := context.Background()
	shutdown, err := telemetry.Initialize(ctx, "analytics-engine")
	if err != nil {
		fatal(err)
	}
	threshold, err := config.Float64("LATENCY_THRESHOLD_MS", 150)
	if err != nil {
		fatal(err)
	}
	logPath := config.String("ANALYTICS_LOG_PATH", "./data/analytics.jsonl")
	if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
		fatal(err)
	}
	eventLogger, err := fileadapter.NewEventLogger(logPath)
	if err != nil {
		fatal(err)
	}
	defer eventLogger.Close()
	timeout, err := config.Duration("HTTP_CLIENT_TIMEOUT", 5*time.Second)
	if err != nil {
		fatal(err)
	}
	alerts := httpadapter.NewAlertClient(config.String("ALERT_MANAGER_URL", "http://localhost:8082"), os.Getenv("ALERT_API_KEY"), &http.Client{Timeout: timeout})
	handler := httpadapter.NewHandler(application.NewAnalyzeMetric(threshold, eventLogger, alerts), application.NewListEvents(eventLogger))
	mux := http.NewServeMux()
	mux.HandleFunc("/health/live", httpx.HealthHandler)
	mux.HandleFunc("/health/ready", httpx.HealthHandler)
	mux.HandleFunc("/internal/v1/analyze", httpx.Method(http.MethodPost, handler.Analyze))
	mux.HandleFunc("/api/v1/events", httpx.Method(http.MethodGet, handler.ListEvents))
	if err := server.Run(config.String("HTTP_ADDR", ":8081"), httpx.TraceMiddleware("analytics-engine", mux), shutdown); err != nil {
		fatal(err)
	}
}

func fatal(err error) { slog.Error("fatal error", "error", err); os.Exit(1) }
