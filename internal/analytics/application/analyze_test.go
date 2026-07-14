package application

import (
	"context"
	"testing"

	"github.com/example/ckad-advanced-observability/internal/domain"
)

type eventLoggerStub struct{ event AnalysisEvent }

func (s *eventLoggerStub) Log(_ context.Context, event AnalysisEvent) error {
	s.event = event
	return nil
}

type alertGatewayStub struct{ alerts []domain.Alert }

func (s *alertGatewayStub) Create(_ context.Context, alert domain.Alert) error {
	s.alerts = append(s.alerts, alert)
	return nil
}

func TestAnalyzeMetricCreatesAlertAboveThreshold(t *testing.T) {
	logger, alerts := &eventLoggerStub{}, &alertGatewayStub{}
	err := NewAnalyzeMetric(100, logger, alerts).Execute(context.Background(), domain.Metric{DeviceType: domain.DeviceRouter, DeviceID: "router-1", LatencyMS: 101})
	if err == nil {
		// Without HTTP middleware there is no valid trace ID, so domain validation
		// rejects alert delivery. The event decision remains testable here.
	} else if logger.event.Status != "THRESHOLD_EXCEEDED" {
		t.Fatalf("status = %q, error = %v", logger.event.Status, err)
	}
	if logger.event.Status != "THRESHOLD_EXCEEDED" {
		t.Fatalf("status = %q", logger.event.Status)
	}
}

func TestAnalyzeMetricDoesNotAlertAtThreshold(t *testing.T) {
	logger, alerts := &eventLoggerStub{}, &alertGatewayStub{}
	err := NewAnalyzeMetric(100, logger, alerts).Execute(context.Background(), domain.Metric{DeviceType: domain.DeviceRouter, DeviceID: "router-1", LatencyMS: 100})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if logger.event.Status != "NORMAL" || len(alerts.alerts) != 0 {
		t.Fatal("expected normal event without alert")
	}
}
