{{- define "medidoc.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Sélection : stable pour toute la vie de la release (jamais la version). */}}
{{- define "medidoc.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "medidoc.labels" -}}
{{ include "medidoc.selectorLabels" . }}
app.kubernetes.io/version: {{ include "medidoc.tag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
medisphere.internal/environnement: {{ .Values.environnement | quote }}
{{- end -}}

{{- define "medidoc.tag" -}}
{{- $tag := default (printf "v%s" .Chart.AppVersion) .Values.image.tag -}}
{{- if eq $tag "latest" -}}{{- fail "image.tag=latest est interdit" -}}{{- end -}}
{{- $tag -}}
{{- end -}}
