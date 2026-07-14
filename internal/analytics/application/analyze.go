package application

import (
	"context"
	"fmt"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"go.opentelemetry.io/otel/trace"
)

type EventLogger interface {
	Log(context.Context, AnalysisEvent) error
}

type EventReader interface {
	List(context.Context, int) ([]AnalysisEvent, error)
}

type ListEvents struct{ reader EventReader }

func NewListEvents(reader EventReader) *ListEvents { return &ListEvents{reader: reader} }

func (uc *ListEvents) Execute(ctx context.Context, limit int) ([]AnalysisEvent, error) {
	return uc.reader.List(ctx, limit)
}

type AlertGateway interface {
	Create(context.Context, domain.Alert) error
}

type AnalysisEvent struct {
	Timestamp          time.Time         `json:"timestamp"`
	TraceID            string            `json:"trace_id"`
	DeviceType         domain.DeviceType `json:"device_type"`
	DeviceID           string            `json:"device_id"`
	CPUUsagePercent    float64           `json:"cpu_usage_percent"`
	MemoryUsagePercent float64           `json:"memory_usage_percent"`
	TemperatureCelsius float64           `json:"temperature_celsius"`
	LatencyMS          float64           `json:"latency_ms"`
	PacketLossPercent  float64           `json:"packet_loss_percent"`
	ThresholdMS        float64           `json:"threshold_ms"`
	Status             string            `json:"status"`
}

type AnalyzeMetric struct {
	threshold float64
	logger    EventLogger
	alerts    AlertGateway
}

func NewAnalyzeMetric(threshold float64, logger EventLogger, alerts AlertGateway) *AnalyzeMetric {
	return &AnalyzeMetric{threshold: threshold, logger: logger, alerts: alerts}
}

func (uc *AnalyzeMetric) Execute(ctx context.Context, metric domain.Metric) error {
	if err := metric.Validate(); err != nil {
		return err
	}
	traceID := trace.SpanContextFromContext(ctx).TraceID().String()
	observedAt := metric.ObservedAt
	if observedAt.IsZero() {
		observedAt = time.Now().UTC()
	}
	status := "NORMAL"
	if metric.LatencyMS > uc.threshold {
		status = "THRESHOLD_EXCEEDED"
	}
	event := AnalysisEvent{
		Timestamp: observedAt, TraceID: traceID, DeviceType: metric.DeviceType, DeviceID: metric.DeviceID,
		CPUUsagePercent: metric.CPUUsagePercent, MemoryUsagePercent: metric.MemoryUsagePercent,
		TemperatureCelsius: metric.TemperatureCelsius, LatencyMS: metric.LatencyMS,
		PacketLossPercent: metric.PacketLossPercent, ThresholdMS: uc.threshold, Status: status,
	}
	if err := uc.logger.Log(ctx, event); err != nil {
		return fmt.Errorf("write analysis event: %w", err)
	}
	if status == "NORMAL" {
		return nil
	}
	alert := domain.Alert{TraceID: traceID, DeviceType: metric.DeviceType, DeviceID: metric.DeviceID, LatencyMS: metric.LatencyMS,
		ThresholdMS: uc.threshold, Severity: "critical", Status: domain.AlertOpen, CreatedAt: time.Now().UTC()}
	if err := uc.alerts.Create(ctx, alert); err != nil {
		return fmt.Errorf("create alert: %w", err)
	}
	return nil
}
