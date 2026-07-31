{{- define "observer-demo.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "observer-demo.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "observer-demo.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "observer-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
lab: "5.4"
{{- end -}}

{{- define "observer-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "observer-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
