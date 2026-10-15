{{/* Nom complet : « mediagenda » si la release s'appelle déjà ainsi. */}}
{{- define "mediagenda.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Étiquettes de sélection : immuables pendant la vie de la release. */}}
{{- define "mediagenda.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mediagenda.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "mediagenda.selectorLabels" . }}
app.kubernetes.io/version: {{ include "mediagenda.tag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
medisphere.fr/environnement: {{ .Values.environnement }}
{{- end -}}

{{- define "mediagenda.tag" -}}
{{- default (printf "v%s" .Chart.AppVersion) .Values.image.tag -}}
{{- end -}}
