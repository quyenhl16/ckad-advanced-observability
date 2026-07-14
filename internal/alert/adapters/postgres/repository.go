package postgres

import (
	"context"
	"fmt"

	"github.com/example/ckad-advanced-observability/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct{ pool *pgxpool.Pool }

func New(ctx context.Context, databaseURL string) (*Repository, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create database pool: %w", err)
	}
	return &Repository{pool: pool}, nil
}

func (r *Repository) Migrate(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS alerts (
        id BIGSERIAL PRIMARY KEY,
        trace_id VARCHAR(32) NOT NULL,
        device_type TEXT NOT NULL,
        device_id TEXT NOT NULL,
        latency_ms DOUBLE PRECISION NOT NULL,
        threshold_ms DOUBLE PRECISION NOT NULL,
        severity TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL
    )`)
	if err != nil {
		return err
	}
	_, err = r.pool.Exec(ctx, `ALTER TABLE alerts ADD COLUMN IF NOT EXISTS device_type TEXT NOT NULL DEFAULT 'server'`)
	if err != nil {
		return err
	}
	_, err = r.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS users (
		id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL
	); CREATE TABLE IF NOT EXISTS subscriptions (
		id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_type TEXT NOT NULL, device_id TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL,
		UNIQUE(user_id, device_type, device_id)
	)`)
	return err
}

func (r *Repository) Save(ctx context.Context, alert domain.Alert) (domain.Alert, error) {
	err := r.pool.QueryRow(ctx, `INSERT INTO alerts
		(trace_id, device_type, device_id, latency_ms, threshold_ms, severity, status, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`, alert.TraceID, alert.DeviceType, alert.DeviceID,
		alert.LatencyMS, alert.ThresholdMS, alert.Severity, alert.Status, alert.CreatedAt).Scan(&alert.ID)
	return alert, err
}

func (r *Repository) List(ctx context.Context, limit int) ([]domain.Alert, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, trace_id, device_type, device_id, latency_ms, threshold_ms,
        severity, status, created_at FROM alerts ORDER BY id DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	alerts := make([]domain.Alert, 0)
	for rows.Next() {
		var alert domain.Alert
		if err := rows.Scan(&alert.ID, &alert.TraceID, &alert.DeviceType, &alert.DeviceID, &alert.LatencyMS,
			&alert.ThresholdMS, &alert.Severity, &alert.Status, &alert.CreatedAt); err != nil {
			return nil, err
		}
		alerts = append(alerts, alert)
	}
	return alerts, rows.Err()
}

func (r *Repository) Ping(ctx context.Context) error { return r.pool.Ping(ctx) }
func (r *Repository) Close()                         { r.pool.Close() }

func (r *Repository) CreateUser(ctx context.Context, user domain.User) (domain.User, error) {
	err := r.pool.QueryRow(ctx, `INSERT INTO users(name,email,created_at) VALUES($1,$2,$3) RETURNING id`,
		user.Name, user.Email, user.CreatedAt).Scan(&user.ID)
	return user, err
}

func (r *Repository) ListUsers(ctx context.Context) ([]domain.User, error) {
	rows, err := r.pool.Query(ctx, `SELECT id,name,email,created_at FROM users ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	users := make([]domain.User, 0)
	for rows.Next() {
		var user domain.User
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt); err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	return users, rows.Err()
}

func (r *Repository) CreateSubscription(ctx context.Context, subscription domain.Subscription) (domain.Subscription, error) {
	err := r.pool.QueryRow(ctx, `INSERT INTO subscriptions(user_id,device_type,device_id,created_at)
		VALUES($1,$2,$3,$4) RETURNING id`, subscription.UserID, subscription.DeviceType, subscription.DeviceID, subscription.CreatedAt).Scan(&subscription.ID)
	return subscription, err
}

func (r *Repository) ListSubscriptions(ctx context.Context) ([]domain.Subscription, error) {
	rows, err := r.pool.Query(ctx, `SELECT s.id,s.user_id,u.name,u.email,s.device_type,s.device_id,s.created_at
		FROM subscriptions s JOIN users u ON u.id=s.user_id ORDER BY s.id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]domain.Subscription, 0)
	for rows.Next() {
		var s domain.Subscription
		if err := rows.Scan(&s.ID, &s.UserID, &s.UserName, &s.UserEmail, &s.DeviceType, &s.DeviceID, &s.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, s)
	}
	return items, rows.Err()
}

func (r *Repository) MatchingUsers(ctx context.Context, alert domain.Alert) ([]domain.User, error) {
	rows, err := r.pool.Query(ctx, `SELECT DISTINCT u.id,u.name,u.email,u.created_at FROM users u
		JOIN subscriptions s ON s.user_id=u.id WHERE s.device_type=$1 AND (s.device_id='' OR s.device_id=$2)`, alert.DeviceType, alert.DeviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	users := make([]domain.User, 0)
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

func (r *Repository) DeleteUser(ctx context.Context, id int64) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM users WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}

func (r *Repository) DeleteSubscription(ctx context.Context, id int64) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM subscriptions WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("subscription not found")
	}
	return nil
}
