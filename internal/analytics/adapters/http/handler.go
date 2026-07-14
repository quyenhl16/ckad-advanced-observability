package httpadapter

import (
	"net/http"
	"strconv"

	"github.com/quyenhl16/ckad-advanced-observability/internal/analytics/application"
	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
)

type Handler struct {
	analyze *application.AnalyzeMetric
	events  *application.ListEvents
}

func NewHandler(analyze *application.AnalyzeMetric, events ...*application.ListEvents) *Handler {
	handler := &Handler{analyze: analyze}
	if len(events) > 0 {
		handler.events = events[0]
	}
	return handler
}

func (h *Handler) Analyze(w http.ResponseWriter, r *http.Request) {
	var metric domain.Metric
	if err := httpx.DecodeJSON(w, r, &metric); err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	if err := h.analyze.Execute(r.Context(), metric); err != nil {
		httpx.WriteJSON(w, httpx.StatusFor(err, domain.ErrInvalidMetric), map[string]string{"error": err.Error()})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "analyzed"})
}

func (h *Handler) ListEvents(w http.ResponseWriter, r *http.Request) {
	if h.events == nil {
		httpx.WriteJSON(w, http.StatusNotImplemented, map[string]string{"error": "event reader unavailable"})
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	events, err := h.events.Execute(r.Context(), limit)
	if err != nil {
		httpx.WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "list events"})
		return
	}
	httpx.WriteJSON(w, http.StatusOK, events)
}
