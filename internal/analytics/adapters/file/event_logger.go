package fileadapter

import (
	"bufio"
	"context"
	"encoding/json"
	"os"
	"sync"

	"github.com/example/ckad-advanced-observability/internal/analytics/application"
)

type EventLogger struct {
	mu   sync.Mutex
	file *os.File
	path string
}

func NewEventLogger(path string) (*EventLogger, error) {
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, err
	}
	return &EventLogger{file: file, path: path}, nil
}

func (l *EventLogger) Log(_ context.Context, event application.AnalysisEvent) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return json.NewEncoder(l.file).Encode(event)
}

func (l *EventLogger) Close() error { return l.file.Close() }

func (l *EventLogger) List(_ context.Context, limit int) ([]application.AnalysisEvent, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	file, err := os.Open(l.path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	events := make([]application.AnalysisEvent, 0)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var event application.AnalysisEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			continue
		}
		events = append(events, event)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if len(events) > limit {
		events = events[len(events)-limit:]
	}
	for left, right := 0, len(events)-1; left < right; left, right = left+1, right-1 {
		events[left], events[right] = events[right], events[left]
	}
	return events, nil
}
