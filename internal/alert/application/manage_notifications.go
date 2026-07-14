package application

import (
	"context"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type NotificationRepository interface {
	CreateUser(context.Context, domain.User) (domain.User, error)
	ListUsers(context.Context) ([]domain.User, error)
	CreateSubscription(context.Context, domain.Subscription) (domain.Subscription, error)
	ListSubscriptions(context.Context) ([]domain.Subscription, error)
	MatchingUsers(context.Context, domain.Alert) ([]domain.User, error)
	DeleteUser(context.Context, int64) error
	DeleteSubscription(context.Context, int64) error
}

type ManageNotifications struct{ repository NotificationRepository }

func NewManageNotifications(repository NotificationRepository) *ManageNotifications {
	return &ManageNotifications{repository: repository}
}

func (uc *ManageNotifications) CreateUser(ctx context.Context, user domain.User) (domain.User, error) {
	if err := user.Validate(); err != nil {
		return domain.User{}, err
	}
	user.CreatedAt = time.Now().UTC()
	return uc.repository.CreateUser(ctx, user)
}

func (uc *ManageNotifications) ListUsers(ctx context.Context) ([]domain.User, error) {
	return uc.repository.ListUsers(ctx)
}

func (uc *ManageNotifications) CreateSubscription(ctx context.Context, subscription domain.Subscription) (domain.Subscription, error) {
	if err := subscription.Validate(); err != nil {
		return domain.Subscription{}, err
	}
	subscription.CreatedAt = time.Now().UTC()
	return uc.repository.CreateSubscription(ctx, subscription)
}

func (uc *ManageNotifications) ListSubscriptions(ctx context.Context) ([]domain.Subscription, error) {
	return uc.repository.ListSubscriptions(ctx)
}

func (uc *ManageNotifications) DeleteUser(ctx context.Context, id int64) error {
	if id <= 0 {
		return domain.ErrInvalidUser
	}
	return uc.repository.DeleteUser(ctx, id)
}

func (uc *ManageNotifications) DeleteSubscription(ctx context.Context, id int64) error {
	if id <= 0 {
		return domain.ErrInvalidSubscription
	}
	return uc.repository.DeleteSubscription(ctx, id)
}
