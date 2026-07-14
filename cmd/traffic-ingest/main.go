package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/config"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/server"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/telemetry"
	httpadapter "github.com/quyenhl16/ckad-advanced-observability/internal/traffic/adapters/http"
	"github.com/quyenhl16/ckad-advanced-observability/internal/traffic/application"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx := context.Background()
	shutdown, err := telemetry.Initialize(ctx, "traffic-ingest")
	if err != nil {
		slog.Error("initialize telemetry", "error", err)
		os.Exit(1)
	}
	timeout, err := config.Duration("HTTP_CLIENT_TIMEOUT", 5*time.Second)
	if err != nil {
		slog.Error("configuration", "error", err)
		os.Exit(1)
	}
	client := httpadapter.NewAnalyticsClient(config.String("ANALYTICS_URL", "http://localhost:8081"), &http.Client{Timeout: timeout})
	handler := httpadapter.NewHandler(application.NewIngestMetric(client))
	mux := http.NewServeMux()
	mux.HandleFunc("/health/live", httpx.HealthHandler)
	mux.HandleFunc("/health/ready", httpx.HealthHandler)
	mux.HandleFunc("/api/v1/metrics", httpx.Method(http.MethodPost, handler.Ingest))
	if err := server.Run(config.String("HTTP_ADDR", ":8080"), httpx.TraceMiddleware("traffic-ingest", mux), shutdown); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
