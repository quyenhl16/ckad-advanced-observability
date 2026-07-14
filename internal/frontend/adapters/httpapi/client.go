package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/quyenhl16/ckad-advanced-observability/internal/frontend/application"
)

type Client struct {
	baseURL string
	client  *http.Client
}

func NewClient(baseURL string, client *http.Client) *Client {
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), client: client}
}

func (c *Client) ListEvents(ctx context.Context, limit int) ([]application.Event, error) {
	var events []application.Event
	err := c.get(ctx, "/api/v1/events", limit, &events)
	return events, err
}

func (c *Client) ListAlerts(ctx context.Context, limit int) ([]application.Alert, error) {
	var alerts []application.Alert
	err := c.get(ctx, "/api/v1/alerts", limit, &alerts)
	return alerts, err
}

func (c *Client) ListUsers(ctx context.Context) ([]application.User, error) {
	var users []application.User
	err := c.get(ctx, "/api/v1/users", 100, &users)
	return users, err
}

func (c *Client) ListSubscriptions(ctx context.Context) ([]application.Subscription, error) {
	var items []application.Subscription
	err := c.get(ctx, "/api/v1/subscriptions", 100, &items)
	return items, err
}

func (c *Client) CreateUser(ctx context.Context, user application.User) error {
	return c.post(ctx, "/api/v1/users", user)
}
func (c *Client) CreateSubscription(ctx context.Context, subscription application.Subscription) error {
	return c.post(ctx, "/api/v1/subscriptions", subscription)
}

func (c *Client) DeleteUser(ctx context.Context, id int64) error {
	return c.delete(ctx, "/api/v1/users/"+strconv.FormatInt(id, 10))
}

func (c *Client) DeleteSubscription(ctx context.Context, id int64) error {
	return c.delete(ctx, "/api/v1/subscriptions/"+strconv.FormatInt(id, 10))
}

func (c *Client) delete(ctx context.Context, path string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, c.baseURL+path, nil)
	if err != nil {
		return err
	}
	response, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		return fmt.Errorf("%s returned status %d", path, response.StatusCode)
	}
	return nil
}

func (c *Client) post(ctx context.Context, path string, body any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("%s returned status %d", path, response.StatusCode)
	}
	return nil
}

func (c *Client) get(ctx context.Context, path string, limit int, target any) error {
	endpoint, err := url.Parse(c.baseURL + path)
	if err != nil {
		return err
	}
	query := endpoint.Query()
	query.Set("limit", strconv.Itoa(limit))
	endpoint.RawQuery = query.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return err
	}
	response, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("%s returned status %d", path, response.StatusCode)
	}
	return json.NewDecoder(response.Body).Decode(target)
}
