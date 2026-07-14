package domain

import (
	"errors"
	"time"
)

var ErrInvalidMetric = errors.New("invalid device metric")

type DeviceType string

const (
	DeviceRouter      DeviceType = "router"
	DeviceSwitch      DeviceType = "switch"
	DeviceServer      DeviceType = "server"
	DeviceFirewall    DeviceType = "firewall"
	DeviceAccessPoint DeviceType = "access_point"
)

func (d DeviceType) Valid() bool {
	switch d {
	case DeviceRouter, DeviceSwitch, DeviceServer, DeviceFirewall, DeviceAccessPoint:
		return true
	default:
		return false
	}
}

type Metric struct {
	DeviceType         DeviceType `json:"device_type"`
	DeviceID           string     `json:"device_id"`
	CPUUsagePercent    float64    `json:"cpu_usage_percent"`
	MemoryUsagePercent float64    `json:"memory_usage_percent"`
	TemperatureCelsius float64    `json:"temperature_celsius"`
	LatencyMS          float64    `json:"latency_ms"`
	PacketLossPercent  float64    `json:"packet_loss_percent"`
	ObservedAt         time.Time  `json:"observed_at"`
}

func (m Metric) Validate() error {
	if !m.DeviceType.Valid() || m.DeviceID == "" ||
		m.CPUUsagePercent < 0 || m.CPUUsagePercent > 100 ||
		m.MemoryUsagePercent < 0 || m.MemoryUsagePercent > 100 ||
		m.TemperatureCelsius < -50 || m.TemperatureCelsius > 150 ||
		m.LatencyMS < 0 ||
		m.PacketLossPercent < 0 || m.PacketLossPercent > 100 {
		return ErrInvalidMetric
	}
	return nil
}
