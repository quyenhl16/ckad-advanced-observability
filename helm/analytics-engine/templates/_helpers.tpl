{{- define "analytics-engine.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "analytics-engine.fullname" -}}
{{- default (include "analytics-engine.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "analytics-engine.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "analytics-engine.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: analytics
app.kubernetes.io/part-of: advanced-observability
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "analytics-engine.selectorLabels" -}}
app: analytics-engine
app.kubernetes.io/name: {{ include "analytics-engine.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
