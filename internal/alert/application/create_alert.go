package application

import (
	"context"
	"fmt"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type AlertRepository interface {
	Save(context.Context, domain.Alert) (domain.Alert, error)
	List(context.Context, int) ([]domain.Alert, error)
	Ping(context.Context) error
}

type AlertNotifier interface {
	Notify(context.Context, domain.Alert)
}

type CreateAlert struct {
	repository AlertRepository
	notifier   AlertNotifier
}

func NewCreateAlert(repository AlertRepository, notifiers ...AlertNotifier) *CreateAlert {
	useCase := &CreateAlert{repository: repository}
	if len(notifiers) > 0 {
		useCase.notifier = notifiers[0]
	}
	return useCase
}

func (uc *CreateAlert) Execute(ctx context.Context, alert domain.Alert) (domain.Alert, error) {
	if err := alert.Validate(); err != nil {
		return domain.Alert{}, err
	}
	saved, err := uc.repository.Save(ctx, alert)
	if err != nil {
		return domain.Alert{}, fmt.Errorf("save alert: %w", err)
	}
	if uc.notifier != nil {
		uc.notifier.Notify(ctx, saved)
	}
	return saved, nil
}

type ListAlerts struct{ repository AlertRepository }

func NewListAlerts(repository AlertRepository) *ListAlerts { return &ListAlerts{repository} }

func (uc *ListAlerts) Execute(ctx context.Context, limit int) ([]domain.Alert, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return uc.repository.List(ctx, limit)
}
