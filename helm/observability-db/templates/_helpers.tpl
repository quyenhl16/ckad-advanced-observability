{{- define "observability-db.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability-db.fullname" -}}
{{- default (include "observability-db.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "observability-db.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "observability-db.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: advanced-observability
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "observability-db.selectorLabels" -}}
app: observability-db
app.kubernetes.io/name: {{ include "observability-db.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
