package httpadapter

import (
	"net/http"
	"strconv"

	"github.com/quyenhl16/ckad-advanced-observability/internal/alert/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
)

type Handler struct {
	create *application.CreateAlert
	list   *application.ListAlerts
	manage *application.ManageNotifications
	apiKey string
	repo   application.AlertRepository
}

func NewHandler(create *application.CreateAlert, list *application.ListAlerts, apiKey string, repo application.AlertRepository, managers ...*application.ManageNotifications) *Handler {
	handler := &Handler{create: create, list: list, apiKey: apiKey, repo: repo}
	if len(managers) > 0 {
		handler.manage = managers[0]
	}
	return handler
}

func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
	var user domain.User
	if err := httpx.DecodeJSON(w, r, &user); err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	saved, err := h.manage.CreateUser(r.Context(), user)
	if err != nil {
		httpx.WriteJSON(w, httpx.StatusFor(err, domain.ErrInvalidUser), map[string]string{"error": err.Error()})
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, saved)
}

func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := h.manage.ListUsers(r.Context())
	if err != nil {
		httpx.WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "list users"})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, users)
}

func (h *Handler) CreateSubscription(w http.ResponseWriter, r *http.Request) {
	var subscription domain.Subscription
	if err := httpx.DecodeJSON(w, r, &subscription); err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	saved, err := h.manage.CreateSubscription(r.Context(), subscription)
	if err != nil {
		httpx.WriteJSON(w, httpx.StatusFor(err, domain.ErrInvalidSubscription), map[string]string{"error": err.Error()})
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, saved)
}

func (h *Handler) ListSubscriptions(w http.ResponseWriter, r *http.Request) {
	items, err := h.manage.ListSubscriptions(r.Context())
	if err != nil {
		httpx.WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "list subscriptions"})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, items)
}

func (h *Handler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid user id"})
		return
	}
	if err := h.manage.DeleteUser(r.Context(), id); err != nil {
		httpx.WriteJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) DeleteSubscription(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid subscription id"})
		return
	}
	if err := h.manage.DeleteSubscription(r.Context(), id); err != nil {
		httpx.WriteJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	if h.apiKey == "" || r.Header.Get("X-API-Key") != h.apiKey {
		httpx.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var alert domain.Alert
	if err := httpx.DecodeJSON(w, r, &alert); err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	saved, err := h.create.Execute(r.Context(), alert)
	if err != nil {
		httpx.WriteJSON(w, httpx.StatusFor(err, domain.ErrInvalidAlert), map[string]string{"error": err.Error()})
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, saved)
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	alerts, err := h.list.Execute(r.Context(), limit)
	if err != nil {
		httpx.WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "list alerts"})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, alerts)
}

func (h *Handler) Ready(w http.ResponseWriter, r *http.Request) {
	if err := h.repo.Ping(r.Context()); err != nil {
		httpx.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "database unavailable"})
		return
	}
	httpx.HealthHandler(w, r)
}
