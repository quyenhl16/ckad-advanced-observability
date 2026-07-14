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

type AlertClient struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

func NewAlertClient(baseURL, apiKey string, client *http.Client) *AlertClient {
	return &AlertClient{strings.TrimRight(baseURL, "/"), apiKey, client}
}

func (c *AlertClient) Create(ctx context.Context, alert domain.Alert) error {
	payload, err := json.Marshal(alert)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/internal/v1/alerts", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", c.apiKey)
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
	response, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("alert manager returned status %d", response.StatusCode)
	}
	return nil
}
