{{/*
Chart de bibliothèque medisphere-commun (M17-E06).
Il ne produit aucun objet : il fournit des gabarits nommés, appelés par les charts applicatifs
avec « include ». Toutes les fonctions reçoivent le contexte racine du chart appelant ($ ou .).
Les valeurs lues sont celles du chart APPELANT (.Values.medisphere.*).
*/}}

{{/*
medisphere-commun.etiquettes — étiquettes d'organisation de MédiSphère.
  medisphere.fr/equipe         : équipe propriétaire (obligatoire)
  medisphere.fr/environnement  : dev, recette ou prod (obligatoire)
  medisphere.fr/donnees-sante  : « oui » si l'application traite des données de santé (HDS)
*/}}
{{- define "medisphere-commun.etiquettes" -}}
medisphere.fr/equipe: {{ required "medisphere.equipe est obligatoire (équipe propriétaire)" .Values.medisphere.equipe | quote }}
medisphere.fr/environnement: {{ required "medisphere.environnement est obligatoire (dev, recette ou prod)" .Values.medisphere.environnement | quote }}
medisphere.fr/donnees-sante: {{ ternary "oui" "non" (.Values.medisphere.donneesSante | default false) | quote }}
{{- end -}}

{{/*
medisphere-commun.securite.pod — contexte de sécurité de pod conforme au profil
Pod Security « restricted » (espaces mediagenda-*, M14-E18).
*/}}
{{- define "medisphere-commun.securite.pod" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
medisphere-commun.securite.conteneur — contexte de sécurité de conteneur « restricted »,
système de fichiers racine en lecture seule.
*/}}
{{- define "medisphere-commun.securite.conteneur" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
capabilities:
  drop:
    - ALL
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
medisphere-commun.image — référence d'image « registre/dépôt:étiquette » ou « registre/dépôt@digest ».
Paramètre : dict "image" <bloc image des valeurs> "defaut" <étiquette par défaut>
Le digest, s'il est fourni, l'emporte sur l'étiquette (déploiement immuable).
*/}}
{{- define "medisphere-commun.image" -}}
{{- $img := .image -}}
{{- $depot := required "image.repository est obligatoire" $img.repository -}}
{{- $base := ternary (printf "%s/%s" $img.registry $depot) $depot (not (empty $img.registry)) -}}
{{- if $img.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $img.digest) -}}
{{- fail (printf "image.digest invalide : %q (attendu : sha256:<64 caractères hexadécimaux>)" $img.digest) -}}
{{- end -}}
{{- printf "%s@%s" $base $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $base (default .defaut $img.tag) -}}
{{- end -}}
{{- end -}}
