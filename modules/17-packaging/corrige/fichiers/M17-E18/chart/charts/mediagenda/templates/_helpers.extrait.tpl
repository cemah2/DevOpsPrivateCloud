{{/*
M17-E18 — extrait de _helpers.tpl (chart de fin de palier 2, M17-E12) : seule la fin du gabarit
« mediagenda.envConnexion » change. Ce gabarit est commun à l'API, au Job de migration (hook) et
au conteneur d'initialisation (livraison par Kustomize) : la variable arrive partout à la fois.
*/}}
{{- define "mediagenda.envConnexion" -}}
- name: MEDIAGENDA_DB_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "mediagenda.dbSecret" . }}
      key: {{ .Values.database.secretKey }}
- name: MEDIAGENDA_VALKEY_URL
  value: {{ include "mediagenda.valkeyUrl" . | quote }}
- name: MEDIAGENDA_LOG_LEVEL
  value: {{ .Values.config.logLevel | quote }}
- name: MEDIAGENDA_LOG_FORMAT
  value: {{ .Values.config.logFormat | quote }}
# MédiAgenda ≥ 1.1.0 refuse de démarrer sans elle (code 2) : dev, recette ou prod (M17-E18).
- name: MEDIAGENDA_ENVIRONNEMENT
  value: {{ required "medisphere.environnement est obligatoire (dev, recette ou prod)" .Values.medisphere.environnement | quote }}
{{- end -}}
