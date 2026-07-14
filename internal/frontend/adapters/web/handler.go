package web

import (
	"embed"
	"html/template"
	"net/http"
	"strconv"

	"github.com/example/ckad-advanced-observability/internal/frontend/application"
)

//go:embed templates/index.html
var templates embed.FS

type Handler struct {
	load *application.LoadDashboard
	page *template.Template
}

func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	if err := h.load.CreateUser(r.Context(), r.FormValue("name"), r.FormValue("email")); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/#notifications", http.StatusSeeOther)
}

func (h *Handler) CreateSubscription(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	userID, err := strconv.ParseInt(r.FormValue("user_id"), 10, 64)
	if err != nil {
		http.Error(w, "invalid user", http.StatusBadRequest)
		return
	}
	if err := h.load.CreateSubscription(r.Context(), userID, r.FormValue("device_type"), r.FormValue("device_id")); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/#notifications", http.StatusSeeOther)
}

func (h *Handler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	id, err := strconv.ParseInt(r.FormValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "invalid user", http.StatusBadRequest)
		return
	}
	if err := h.load.DeleteUser(r.Context(), id); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/#notifications", http.StatusSeeOther)
}

func (h *Handler) DeleteSubscription(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	id, err := strconv.ParseInt(r.FormValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "invalid subscription", http.StatusBadRequest)
		return
	}
	if err := h.load.DeleteSubscription(r.Context(), id); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/#notifications", http.StatusSeeOther)
}

func NewHandler(load *application.LoadDashboard) (*Handler, error) {
	page, err := template.ParseFS(templates, "templates/index.html")
	if err != nil {
		return nil, err
	}
	return &Handler{load: load, page: page}, nil
}

func (h *Handler) Dashboard(w http.ResponseWriter, r *http.Request) {
	data, err := h.load.Execute(r.Context(), application.DashboardFilter{
		TraceID: r.URL.Query().Get("trace_id"), DeviceType: r.URL.Query().Get("device_type"), DeviceID: r.URL.Query().Get("device_id"),
	})
	if err != nil {
		http.Error(w, "observability backends unavailable: "+err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.page.Execute(w, data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
