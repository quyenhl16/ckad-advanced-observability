package memory

import (
	"context"
	"errors"
	"sync"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type Repository struct {
	mu            sync.RWMutex
	alerts        []domain.Alert
	users         []domain.User
	subscriptions []domain.Subscription
}

func New() *Repository { return &Repository{} }

func (r *Repository) Save(_ context.Context, alert domain.Alert) (domain.Alert, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	alert.ID = int64(len(r.alerts) + 1)
	r.alerts = append(r.alerts, alert)
	return alert, nil
}

func (r *Repository) List(_ context.Context, limit int) ([]domain.Alert, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	if limit > len(r.alerts) {
		limit = len(r.alerts)
	}
	result := make([]domain.Alert, 0, limit)
	for i := len(r.alerts) - 1; i >= len(r.alerts)-limit; i-- {
		result = append(result, r.alerts[i])
	}
	return result, nil
}

func (r *Repository) Ping(context.Context) error { return nil }

func (r *Repository) CreateUser(_ context.Context, user domain.User) (domain.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, existing := range r.users {
		if existing.Email == user.Email {
			return domain.User{}, errors.New("email already exists")
		}
	}
	user.ID = int64(len(r.users) + 1)
	r.users = append(r.users, user)
	return user, nil
}

func (r *Repository) ListUsers(context.Context) ([]domain.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return append([]domain.User(nil), r.users...), nil
}

func (r *Repository) CreateSubscription(_ context.Context, subscription domain.Subscription) (domain.Subscription, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var user domain.User
	for _, candidate := range r.users {
		if candidate.ID == subscription.UserID {
			user = candidate
			break
		}
	}
	if user.ID == 0 {
		return domain.Subscription{}, errors.New("user not found")
	}
	for _, existing := range r.subscriptions {
		if existing.UserID == subscription.UserID && existing.DeviceType == subscription.DeviceType && existing.DeviceID == subscription.DeviceID {
			return domain.Subscription{}, errors.New("subscription already exists")
		}
	}
	subscription.ID = int64(len(r.subscriptions) + 1)
	subscription.UserName, subscription.UserEmail = user.Name, user.Email
	r.subscriptions = append(r.subscriptions, subscription)
	return subscription, nil
}

func (r *Repository) ListSubscriptions(context.Context) ([]domain.Subscription, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return append([]domain.Subscription(nil), r.subscriptions...), nil
}

func (r *Repository) MatchingUsers(_ context.Context, alert domain.Alert) ([]domain.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	matched := make(map[int64]bool)
	users := make([]domain.User, 0)
	for _, subscription := range r.subscriptions {
		if !subscription.Matches(alert) || matched[subscription.UserID] {
			continue
		}
		for _, user := range r.users {
			if user.ID == subscription.UserID {
				users = append(users, user)
				matched[user.ID] = true
				break
			}
		}
	}
	return users, nil
}

func (r *Repository) DeleteUser(_ context.Context, id int64) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	found := false
	users := r.users[:0]
	for _, user := range r.users {
		if user.ID == id {
			found = true
			continue
		}
		users = append(users, user)
	}
	if !found {
		return errors.New("user not found")
	}
	r.users = users
	subscriptions := r.subscriptions[:0]
	for _, item := range r.subscriptions {
		if item.UserID != id {
			subscriptions = append(subscriptions, item)
		}
	}
	r.subscriptions = subscriptions
	return nil
}

func (r *Repository) DeleteSubscription(_ context.Context, id int64) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	found := false
	items := r.subscriptions[:0]
	for _, item := range r.subscriptions {
		if item.ID == id {
			found = true
			continue
		}
		items = append(items, item)
	}
	if !found {
		return errors.New("subscription not found")
	}
	r.subscriptions = items
	return nil
}
