{{/*
_helpers.tpl — api-gateway-bff Helm template helpers
*/}}

{{- define "api-gateway-bff.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "api-gateway-bff.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "api-gateway-bff.selectorLabels" -}}
app.kubernetes.io/name: {{ include "api-gateway-bff.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "api-gateway-bff.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "api-gateway-bff.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "api-gateway-bff.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "api-gateway-bff.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
