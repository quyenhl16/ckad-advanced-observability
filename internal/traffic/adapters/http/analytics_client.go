package httpadapter

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

type AnalyticsClient struct {
	baseURL string
	client  *http.Client
}

func NewAnalyticsClient(baseURL string, client *http.Client) *AnalyticsClient {
	return &AnalyticsClient{baseURL: strings.TrimRight(baseURL, "/"), client: client}
}

func (c *AnalyticsClient) Analyze(ctx context.Context, metric domain.Metric) error {
	payload, err := json.Marshal(metric)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/internal/v1/analyze", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
	response, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("analytics returned status %d", response.StatusCode)
	}
	return nil
}
