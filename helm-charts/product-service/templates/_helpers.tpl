{{/*
_helpers.tpl — product-service Helm template helpers
Named templates are reusable across all template files in this chart.
*/}}

{{/* Expand the name of the chart */}}
{{- define "product-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name */}}
{{- define "product-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Selector labels — used in Deployment.spec.selector and Service.spec.selector */}}
{{- define "product-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "product-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Common labels — applied to all resources */}}
{{- define "product-service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "product-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* ServiceAccount name */}}
{{- define "product-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "product-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
