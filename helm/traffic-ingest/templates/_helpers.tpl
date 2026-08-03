{{- define "traffic-ingest.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "traffic-ingest.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "traffic-ingest.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "traffic-ingest.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "traffic-ingest.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: advanced-observability
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "traffic-ingest.selectorLabels" -}}
app.kubernetes.io/name: {{ include "traffic-ingest.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
