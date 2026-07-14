package application

import (
	"context"
	"testing"
)

type eventSourceStub []Event

func (s eventSourceStub) ListEvents(context.Context, int) ([]Event, error) { return s, nil }

type alertSourceStub []Alert

func (s alertSourceStub) ListAlerts(context.Context, int) ([]Alert, error) { return s, nil }

func TestLoadDashboardFiltersByDeviceTypeAndID(t *testing.T) {
	events := eventSourceStub{
		{TraceID: "trace-router", DeviceType: "router", DeviceID: "router-01"},
		{TraceID: "trace-server", DeviceType: "server", DeviceID: "server-01"},
	}
	alerts := alertSourceStub{
		{TraceID: "trace-router", DeviceType: "router", DeviceID: "router-01"},
		{TraceID: "trace-router-02", DeviceType: "router", DeviceID: "router-02"},
	}
	dashboard, err := NewLoadDashboard(events, alerts).Execute(context.Background(), DashboardFilter{
		DeviceType: "router", DeviceID: "router-01",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(dashboard.Events) != 1 || len(dashboard.Alerts) != 1 {
		t.Fatalf("events=%d alerts=%d", len(dashboard.Events), len(dashboard.Alerts))
	}
}

func TestLoadDashboardFiltersByTraceID(t *testing.T) {
	events := eventSourceStub{{TraceID: "wanted"}, {TraceID: "other"}}
	dashboard, err := NewLoadDashboard(events, alertSourceStub{}).Execute(context.Background(), DashboardFilter{TraceID: "wanted"})
	if err != nil {
		t.Fatal(err)
	}
	if len(dashboard.Events) != 1 || dashboard.Events[0].TraceID != "wanted" {
		t.Fatalf("events=%+v", dashboard.Events)
	}
}
