package notifier

import (
	"context"
	"testing"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/alert/adapters/memory"
	"github.com/quyenhl16/ckad-advanced-observability/internal/alert/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
)

type senderSpy struct{ recipients []string }

func (s *senderSpy) Send(_ context.Context, user domain.User, _ domain.Alert) error {
	s.recipients = append(s.recipients, user.Email)
	return nil
}

func TestSubscriptionNotifierMatchesTypeAndSpecificDevice(t *testing.T) {
	ctx := context.Background()
	repository := memory.New()
	manage := application.NewManageNotifications(repository)
	alice, _ := manage.CreateUser(ctx, domain.User{Name: "Alice", Email: "alice@example.test"})
	bob, _ := manage.CreateUser(ctx, domain.User{Name: "Bob", Email: "bob@example.test"})
	_, _ = manage.CreateSubscription(ctx, domain.Subscription{UserID: alice.ID, DeviceType: domain.DeviceRouter})
	_, _ = manage.CreateSubscription(ctx, domain.Subscription{UserID: bob.ID, DeviceType: domain.DeviceRouter, DeviceID: "router-vip-01"})

	sender := &senderSpy{}
	NewSubscriptionNotifier(repository, sender).Notify(ctx, domain.Alert{DeviceType: domain.DeviceRouter, DeviceID: "router-vip-01", CreatedAt: time.Now()})
	if len(sender.recipients) != 2 {
		t.Fatalf("VIP recipients=%v", sender.recipients)
	}
	sender.recipients = nil
	NewSubscriptionNotifier(repository, sender).Notify(ctx, domain.Alert{DeviceType: domain.DeviceRouter, DeviceID: "router-other-01"})
	if len(sender.recipients) != 1 || sender.recipients[0] != alice.Email {
		t.Fatalf("other router recipients=%v", sender.recipients)
	}
	if err := manage.DeleteUser(ctx, bob.ID); err != nil {
		t.Fatal(err)
	}
	items, err := manage.ListSubscriptions(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].UserID != alice.ID {
		t.Fatalf("subscriptions after deleting Bob=%v", items)
	}
	if err := manage.DeleteSubscription(ctx, items[0].ID); err != nil {
		t.Fatal(err)
	}
	items, _ = manage.ListSubscriptions(ctx)
	if len(items) != 0 {
		t.Fatalf("subscriptions after unsubscribe=%v", items)
	}
}
