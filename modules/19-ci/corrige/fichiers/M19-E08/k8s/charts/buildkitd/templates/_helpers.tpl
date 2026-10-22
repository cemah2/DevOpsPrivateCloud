{{/* Étiquettes communes */}}
{{- define "buildkitd.etiquettes" -}}
app.kubernetes.io/name: buildkitd
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.version | quote }}
app.kubernetes.io/part-of: ci
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "buildkitd.selecteur" -}}
app.kubernetes.io/name: buildkitd
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Image : dépôt:étiquette@empreinte (empreinte obligatoire) */}}
{{- define "buildkitd.image" -}}
{{- $e := required "image.empreinte est obligatoire (sha256:…)" .Values.image.empreinte -}}
{{- if not (hasPrefix "sha256:" $e) -}}{{- fail "image.empreinte doit commencer par sha256:" -}}{{- end -}}
{{ printf "%s:%s@%s" .Values.image.depot .Values.image.version $e }}
{{- end -}}
