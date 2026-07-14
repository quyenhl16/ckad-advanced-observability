package httpadapter

import (
	"net/http"
	"time"

	"github.com/quyenhl16/ckad-advanced-observability/internal/domain"
	"github.com/quyenhl16/ckad-advanced-observability/internal/platform/httpx"
	"github.com/quyenhl16/ckad-advanced-observability/internal/traffic/application"
	"go.opentelemetry.io/otel/trace"
)

type Handler struct{ ingest *application.IngestMetric }

func NewHandler(ingest *application.IngestMetric) *Handler { return &Handler{ingest: ingest} }

func (h *Handler) Ingest(w http.ResponseWriter, r *http.Request) {
	var metric domain.Metric
	if err := httpx.DecodeJSON(w, r, &metric); err != nil {
		httpx.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	if metric.ObservedAt.IsZero() {
		metric.ObservedAt = time.Now().UTC()
	}
	if err := h.ingest.Execute(r.Context(), metric); err != nil {
		httpx.WriteJSON(w, httpx.StatusFor(err, domain.ErrInvalidMetric), map[string]string{"error": err.Error()})
		return
	}
	httpx.WriteJSON(w, http.StatusAccepted, map[string]string{
		"status":   "accepted",
		"trace_id": trace.SpanContextFromContext(r.Context()).TraceID().String(),
	})
}
