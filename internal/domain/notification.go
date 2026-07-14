package domain

import (
	"errors"
	"net/mail"
	"strings"
	"time"
)

var (
	ErrInvalidUser         = errors.New("name and valid email are required")
	ErrInvalidSubscription = errors.New("valid user_id and device_type are required")
)

type User struct {
	ID        int64     `json:"id,omitempty"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

func (u User) Validate() error {
	address, err := mail.ParseAddress(u.Email)
	if strings.TrimSpace(u.Name) == "" || err != nil || address.Address != u.Email {
		return ErrInvalidUser
	}
	return nil
}

type Subscription struct {
	ID         int64      `json:"id,omitempty"`
	UserID     int64      `json:"user_id"`
	UserName   string     `json:"user_name,omitempty"`
	UserEmail  string     `json:"user_email,omitempty"`
	DeviceType DeviceType `json:"device_type"`
	DeviceID   string     `json:"device_id,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

func (s Subscription) Validate() error {
	if s.UserID <= 0 || !s.DeviceType.Valid() {
		return ErrInvalidSubscription
	}
	return nil
}

func (s Subscription) Matches(alert Alert) bool {
	return s.DeviceType == alert.DeviceType && (s.DeviceID == "" || s.DeviceID == alert.DeviceID)
}
