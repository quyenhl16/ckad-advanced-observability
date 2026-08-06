{{- define "alert-manager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "alert-manager.fullname" -}}
{{- default (include "alert-manager.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "alert-manager.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "alert-manager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: alerting
app.kubernetes.io/part-of: advanced-observability
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "alert-manager.selectorLabels" -}}
app: alert-manager
app.kubernetes.io/name: {{ include "alert-manager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
