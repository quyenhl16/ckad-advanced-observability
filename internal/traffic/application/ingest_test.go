package application

import (
	"context"
	"testing"

	"github.com/example/ckad-advanced-observability/internal/domain"
)

type analyticsStub struct{ called bool }

func (s *analyticsStub) Analyze(_ context.Context, _ domain.Metric) error {
	s.called = true
	return nil
}

func TestIngestMetricValidatesAndForwards(t *testing.T) {
	stub := &analyticsStub{}
	if err := NewIngestMetric(stub).Execute(context.Background(), domain.Metric{DeviceType: domain.DeviceRouter, DeviceID: "router-1", LatencyMS: 42}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !stub.called {
		t.Fatal("analytics gateway was not called")
	}
}

func TestIngestMetricRejectsInvalidMetric(t *testing.T) {
	stub := &analyticsStub{}
	if err := NewIngestMetric(stub).Execute(context.Background(), domain.Metric{LatencyMS: -1}); err == nil {
		t.Fatal("Execute() expected validation error")
	}
	if stub.called {
		t.Fatal("analytics gateway must not be called")
	}
}
