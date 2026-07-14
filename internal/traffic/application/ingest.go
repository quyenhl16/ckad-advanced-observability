package application

import (
	"context"
	"fmt"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type AnalyticsGateway interface {
	Analyze(context.Context, domain.Metric) error
}

type IngestMetric struct{ analytics AnalyticsGateway }

func NewIngestMetric(analytics AnalyticsGateway) *IngestMetric {
	return &IngestMetric{analytics: analytics}
}

func (uc *IngestMetric) Execute(ctx context.Context, metric domain.Metric) error {
	if err := metric.Validate(); err != nil {
		return err
	}
	if err := uc.analytics.Analyze(ctx, metric); err != nil {
		return fmt.Errorf("send metric to analytics: %w", err)
	}
	return nil
}
