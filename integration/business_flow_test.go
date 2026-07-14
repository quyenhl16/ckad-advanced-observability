package integration_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"

	alerthttp "github.com/quyenhl16/ckad-advanced-observability/internal/alert/adapters/http"
	alertapp "github.com/quyenhl16/ckad-advanced-observability/internal/alert/application"
	fileadapter "github.com/quyenhl16/ckad-advanced-observability/internal/analytics/adapters/file"
	analyticshttp "github.com/quyenhl16/ckad-advanced-observability/internal/analytics/adapters/http"
	analyticsapp "github.com/quyenhl16/ckad-advanced-observability/internal/analytics/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/telemetry"
	traffichttp "github.com/quyenhl16/ckad-advanced-observability/internal/traffic/adapters/http"
	trafficapp "github.com/quyenhl16/ckad-advanced-observability/internal/traffic/application"
)

type memoryAlertRepository struct {
	mu     sync.Mutex
	alerts []domain.Alert
}

func (r *memoryAlertRepository) Save(_ context.Context, alert domain.Alert) (domain.Alert, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	alert.ID = int64(len(r.alerts) + 1)
	r.alerts = append(r.alerts, alert)
	return alert, nil
}

func (r *memoryAlertRepository) List(_ context.Context, limit int) ([]domain.Alert, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if limit > len(r.alerts) {
		limit = len(r.alerts)
	}
	return append([]domain.Alert(nil), r.alerts[:limit]...), nil
}

func (r *memoryAlertRepository) Ping(context.Context) error { return nil }

func TestMetricAboveThresholdFlowsThroughAllServices(t *testing.T) {
	ctx := context.Background()
	shutdown, err := telemetry.Initialize(ctx, "business-flow-test")
	if err != nil {
		t.Fatal(err)
	}
	defer shutdown(ctx)

	repository := &memoryAlertRepository{}
	alertHandler := alerthttp.NewHandler(
		alertapp.NewCreateAlert(repository), alertapp.NewListAlerts(repository), "test-key", repository,
	)
	alertMux := http.NewServeMux()
	alertMux.HandleFunc("/internal/v1/alerts", httpx.Method(http.MethodPost, alertHandler.Create))
	alertServer := httptest.NewServer(httpx.TraceMiddleware("alert-manager", alertMux))
	defer alertServer.Close()

	logPath := filepath.Join(t.TempDir(), "events.jsonl")
	eventLogger, err := fileadapter.NewEventLogger(logPath)
	if err != nil {
		t.Fatal(err)
	}
	defer eventLogger.Close()
	alertClient := analyticshttp.NewAlertClient(alertServer.URL, "test-key", alertServer.Client())
	analyticsHandler := analyticshttp.NewHandler(analyticsapp.NewAnalyzeMetric(150, eventLogger, alertClient))
	analyticsMux := http.NewServeMux()
	analyticsMux.HandleFunc("/internal/v1/analyze", httpx.Method(http.MethodPost, analyticsHandler.Analyze))
	analyticsServer := httptest.NewServer(httpx.TraceMiddleware("analytics-engine", analyticsMux))
	defer analyticsServer.Close()

	analyticsClient := traffichttp.NewAnalyticsClient(analyticsServer.URL, analyticsServer.Client())
	trafficHandler := traffichttp.NewHandler(trafficapp.NewIngestMetric(analyticsClient))
	trafficMux := http.NewServeMux()
	trafficMux.HandleFunc("/api/v1/metrics", httpx.Method(http.MethodPost, trafficHandler.Ingest))
	trafficServer := httptest.NewServer(httpx.TraceMiddleware("traffic-ingest", trafficMux))
	defer trafficServer.Close()

	payload := []byte(`{"device_type":"router","device_id":"router-hcm-01","cpu_usage_percent":72.5,"memory_usage_percent":64.2,"temperature_celsius":68.4,"latency_ms":240,"packet_loss_percent":2.1}`)
	response, err := trafficServer.Client().Post(trafficServer.URL+"/api/v1/metrics", "application/json", bytes.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		t.Fatalf("status = %d", response.StatusCode)
	}
	var accepted struct {
		TraceID string `json:"trace_id"`
	}
	if err := json.NewDecoder(response.Body).Decode(&accepted); err != nil {
		t.Fatal(err)
	}
	if len(accepted.TraceID) != 32 {
		t.Fatalf("trace_id = %q", accepted.TraceID)
	}
	t.Logf("traffic-ingest response: status=%d accepted=%t trace_id=%s", response.StatusCode, true, accepted.TraceID)

	alerts, _ := repository.List(ctx, 10)
	if len(alerts) != 1 {
		t.Fatalf("alerts stored = %d", len(alerts))
	}
	if alerts[0].TraceID != accepted.TraceID {
		t.Fatalf("alert trace_id = %q, request trace_id = %q", alerts[0].TraceID, accepted.TraceID)
	}
	if alerts[0].DeviceType != domain.DeviceRouter || alerts[0].DeviceID != "router-hcm-01" || alerts[0].Status != domain.AlertOpen {
		t.Fatalf("unexpected alert: %+v", alerts[0])
	}
	alertJSON, err := json.MarshalIndent(alerts[0], "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("alert-manager stored alert:\n%s", alertJSON)

	file, err := filepath.Abs(logPath)
	if err != nil {
		t.Fatal(err)
	}
	logFile, err := os.Open(file)
	if err != nil {
		t.Fatal(err)
	}
	defer logFile.Close()
	var event analyticsapp.AnalysisEvent
	if err := json.NewDecoder(bufio.NewReader(logFile)).Decode(&event); err != nil {
		t.Fatal(err)
	}
	if event.TraceID != accepted.TraceID || event.Status != "THRESHOLD_EXCEEDED" {
		t.Fatalf("unexpected analysis event: %+v", event)
	}
	eventJSON, err := json.MarshalIndent(event, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("analytics-engine structured log:\n%s", eventJSON)
}
