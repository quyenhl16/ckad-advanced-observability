package domain

import (
	"errors"
	"time"
)

var ErrInvalidAlert = errors.New("invalid alert")

type AlertStatus string

const AlertOpen AlertStatus = "OPEN"

type Alert struct {
	ID          int64       `json:"id,omitempty"`
	TraceID     string      `json:"trace_id"`
	DeviceType  DeviceType  `json:"device_type"`
	DeviceID    string      `json:"device_id"`
	LatencyMS   float64     `json:"latency_ms"`
	ThresholdMS float64     `json:"threshold_ms"`
	Severity    string      `json:"severity"`
	Status      AlertStatus `json:"status"`
	CreatedAt   time.Time   `json:"created_at"`
}

func (a Alert) Validate() error {
	if a.TraceID == "" || !a.DeviceType.Valid() || a.DeviceID == "" || a.ThresholdMS < 0 || a.LatencyMS < 0 {
		return ErrInvalidAlert
	}
	return nil
}
