{{/* Gabarits nommés du chart mediagenda (M17-E03, enrichis en E05, E06 et E12). */}}

{{/* Nom court de l'application (63 caractères au plus : limite des noms DNS). */}}
{{- define "mediagenda.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nom complet des objets. Si le nom de la release contient déjà le nom du chart, on ne le répète pas :
release « mediagenda » → objets « mediagenda » (mêmes noms qu'aux modules 14 à 16).
*/}}
{{- define "mediagenda.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Étiquette helm.sh/chart : nom-version (le « + » de SemVer est interdit dans une étiquette). */}}
{{- define "mediagenda.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Étiquettes de SÉLECTION : stables pour toute la vie de la release (le sélecteur d'un Deployment
est immuable). N'y mets jamais la version.
*/}}
{{- define "mediagenda.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mediagenda.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Étiquettes communes : sélection + version + gestionnaire + organisation MédiSphère. */}}
{{- define "mediagenda.labels" -}}
helm.sh/chart: {{ include "mediagenda.chart" . }}
{{ include "mediagenda.selectorLabels" . }}
app.kubernetes.io/version: {{ include "mediagenda.imageTag" . | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mediagenda
{{ include "medisphere-commun.etiquettes" . }}
{{- end -}}

{{/* Étiquette d'image effective (sert aussi à MEDIAGENDA_VERSION). */}}
{{- define "mediagenda.imageTag" -}}
{{- default (printf "v%s" .Chart.AppVersion) .Values.image.tag -}}
{{- end -}}

{{/* Référence complète de l'image (digest prioritaire). */}}
{{- define "mediagenda.image" -}}
{{- include "medisphere-commun.image" (dict "image" .Values.image "defaut" (include "mediagenda.imageTag" .)) -}}
{{- end -}}

{{- define "mediagenda.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "mediagenda.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Nom du cluster CloudNativePG rendu par le chart. */}}
{{- define "mediagenda.cnpgName" -}}
{{- default (printf "%s-db" (include "mediagenda.fullname" .)) .Values.postgresql.cnpg.name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{/* Secret qui porte l'URL PostgreSQL. */}}
{{- define "mediagenda.dbSecret" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else if .Values.postgresql.cnpg.enabled -}}
{{- printf "%s-app" (include "mediagenda.cnpgName" .) -}}
{{- else -}}
mediagenda-db-app
{{- end -}}
{{- end -}}

{{/* URL de Valkey : service du sous-chart, ou instance externe. */}}
{{- define "mediagenda.valkeyUrl" -}}
{{- if .Values.valkey.enabled -}}
{{- printf "redis://%s-valkey:%v/0" .Release.Name .Values.valkeyImporte.port -}}
{{- else -}}
{{- required "externalValkey.url est obligatoire quand valkey.enabled est faux" .Values.externalValkey.url -}}
{{- end -}}
{{- end -}}

{{/* Nom publié par la HTTPRoute (tpl permis dans la valeur). */}}
{{- define "mediagenda.hostname" -}}
{{- if .Values.httpRoute.hostname -}}
{{- tpl .Values.httpRoute.hostname . -}}
{{- else -}}
{{- printf "mediagenda-%s.apps.par1.medisphere.internal" .Values.medisphere.environnement -}}
{{- end -}}
{{- end -}}

{{/*
Annotation de hook du Job de migration (M17-E12).
- Base externe (recette) : pre-install,pre-upgrade — le schéma est prêt AVANT les nouveaux pods.
- Base rendue par le chart (dev, prod) : à la première installation, le cluster CNPG n'existe pas
  encore au moment des hooks pre-install (les hooks passent AVANT les objets ordinaires) : la
  migration de l'installation initiale passe donc en post-install ; les montées restent pre-upgrade.
*/}}
{{- define "mediagenda.migrations.hook" -}}
{{- if .Values.postgresql.cnpg.enabled -}}
post-install,pre-upgrade
{{- else -}}
pre-install,pre-upgrade
{{- end -}}
{{- end -}}

{{/* Variables d'environnement de connexion, communes à l'API et aux migrations. */}}
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
{{- end -}}

{{/* Conteneur de migration (Job de hook ou conteneur d'initialisation). */}}
{{- define "mediagenda.conteneurMigration" -}}
- name: migrations
  image: {{ include "mediagenda.image" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command: ["python", "-m", "mediagenda.migrate"]
  env:
    {{- include "mediagenda.envConnexion" . | nindent 4 }}
    - name: MEDIAGENDA_MIGRATIONS_DIR
      value: {{ .Values.migrations.repertoire | quote }}
  securityContext:
    {{- include "medisphere-commun.securite.conteneur" . | nindent 4 }}
  resources:
    {{- toYaml .Values.migrations.resources | nindent 4 }}
{{- end -}}

{{/*
Vérifications transverses, appelées une fois (deployment.yaml) : ce que le schéma JSON ne sait
pas exprimer parce que la règle porte sur plusieurs valeurs à la fois.
*/}}
{{- define "mediagenda.verifications" -}}
{{- if and (eq .Values.medisphere.environnement "prod") (lt (int .Values.replicaCount) 2) -}}
{{- fail "prod : replicaCount doit valoir au moins 2" -}}
{{- end -}}
{{- if and .Values.database.existingSecret .Values.postgresql.cnpg.enabled -}}
{{- fail "database.existingSecret et postgresql.cnpg.enabled sont exclusifs : la base rendue par le chart fournit son propre Secret" -}}
{{- end -}}
{{- end -}}
