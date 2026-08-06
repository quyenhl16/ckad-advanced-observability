{{- define "observability-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability-frontend.fullname" -}}
{{- default (include "observability-frontend.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability-frontend.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "observability-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: frontend
app.kubernetes.io/part-of: advanced-observability
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "observability-frontend.selectorLabels" -}}
app: observability-frontend
app.kubernetes.io/name: {{ include "observability-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
