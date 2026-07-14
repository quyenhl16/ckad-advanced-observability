package application

import (
	"context"
	"time"
)

type Event struct {
	Timestamp          time.Time `json:"timestamp"`
	TraceID            string    `json:"trace_id"`
	DeviceType         string    `json:"device_type"`
	DeviceID           string    `json:"device_id"`
	CPUUsagePercent    float64   `json:"cpu_usage_percent"`
	MemoryUsagePercent float64   `json:"memory_usage_percent"`
	TemperatureCelsius float64   `json:"temperature_celsius"`
	LatencyMS          float64   `json:"latency_ms"`
	PacketLossPercent  float64   `json:"packet_loss_percent"`
	ThresholdMS        float64   `json:"threshold_ms"`
	Status             string    `json:"status"`
}

type Alert struct {
	ID          int64     `json:"id"`
	TraceID     string    `json:"trace_id"`
	DeviceType  string    `json:"device_type"`
	DeviceID    string    `json:"device_id"`
	LatencyMS   float64   `json:"latency_ms"`
	ThresholdMS float64   `json:"threshold_ms"`
	Severity    string    `json:"severity"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type User struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}
type Subscription struct {
	ID         int64  `json:"id"`
	UserID     int64  `json:"user_id"`
	UserName   string `json:"user_name"`
	UserEmail  string `json:"user_email"`
	DeviceType string `json:"device_type"`
	DeviceID   string `json:"device_id"`
}

type EventSource interface {
	ListEvents(context.Context, int) ([]Event, error)
}
type AlertSource interface {
	ListAlerts(context.Context, int) ([]Alert, error)
}
type NotificationAdmin interface {
	ListUsers(context.Context) ([]User, error)
	ListSubscriptions(context.Context) ([]Subscription, error)
	CreateUser(context.Context, User) error
	CreateSubscription(context.Context, Subscription) error
	DeleteUser(context.Context, int64) error
	DeleteSubscription(context.Context, int64) error
}

type Dashboard struct {
	Events        []Event
	Alerts        []Alert
	TraceID       string
	DeviceType    string
	DeviceID      string
	DeviceTypes   []string
	Users         []User
	Subscriptions []Subscription
}

type DashboardFilter struct {
	TraceID    string
	DeviceType string
	DeviceID   string
}

type LoadDashboard struct {
	events EventSource
	alerts AlertSource
	admin  NotificationAdmin
}

func NewLoadDashboard(events EventSource, alerts AlertSource, admins ...NotificationAdmin) *LoadDashboard {
	loader := &LoadDashboard{events: events, alerts: alerts}
	if len(admins) > 0 {
		loader.admin = admins[0]
	}
	return loader
}

func (uc *LoadDashboard) Execute(ctx context.Context, filter DashboardFilter) (Dashboard, error) {
	events, err := uc.events.ListEvents(ctx, 100)
	if err != nil {
		return Dashboard{}, err
	}
	alerts, err := uc.alerts.ListAlerts(ctx, 100)
	if err != nil {
		return Dashboard{}, err
	}
	result := Dashboard{
		TraceID: filter.TraceID, DeviceType: filter.DeviceType, DeviceID: filter.DeviceID,
		DeviceTypes: []string{"router", "switch", "server", "firewall", "access_point"},
	}
	if uc.admin != nil {
		result.Users, err = uc.admin.ListUsers(ctx)
		if err != nil {
			return Dashboard{}, err
		}
		result.Subscriptions, err = uc.admin.ListSubscriptions(ctx)
		if err != nil {
			return Dashboard{}, err
		}
	}
	for _, event := range events {
		if matches(filter, event.TraceID, event.DeviceType, event.DeviceID) {
			result.Events = append(result.Events, event)
		}
	}
	for _, alert := range alerts {
		if matches(filter, alert.TraceID, alert.DeviceType, alert.DeviceID) {
			result.Alerts = append(result.Alerts, alert)
		}
	}
	return result, nil
}

func (uc *LoadDashboard) CreateUser(ctx context.Context, name, email string) error {
	return uc.admin.CreateUser(ctx, User{Name: name, Email: email})
}

func (uc *LoadDashboard) CreateSubscription(ctx context.Context, userID int64, deviceType, deviceID string) error {
	return uc.admin.CreateSubscription(ctx, Subscription{UserID: userID, DeviceType: deviceType, DeviceID: deviceID})
}

func (uc *LoadDashboard) DeleteUser(ctx context.Context, id int64) error {
	return uc.admin.DeleteUser(ctx, id)
}

func (uc *LoadDashboard) DeleteSubscription(ctx context.Context, id int64) error {
	return uc.admin.DeleteSubscription(ctx, id)
}

func matches(filter DashboardFilter, traceID, deviceType, deviceID string) bool {
	return (filter.TraceID == "" || traceID == filter.TraceID) &&
		(filter.DeviceType == "" || deviceType == filter.DeviceType) &&
		(filter.DeviceID == "" || deviceID == filter.DeviceID)
}
