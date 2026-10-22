# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# _m23-commun.sh — fonctions partagées par les scripts de panne du module 23 (M23-E19 à M23-E23).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_avert, WB_EX, WB_VAR…) ; lab/bin/break
# a déjà chargé lab/lib/check-lib.sh (grafana_api, prom_requete, harbor_api, remote).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées hors de
# tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.11 « Pannes des blocs D et E ») :
#   - une panne de configuration GitOps passe par un COMMIT IDENTIFIABLE sur la branche main du dépôt
#     concerné (auteur lucas.martin, marqueur M23-EXX dans le message), poussé par l'API de GitLab avec le
#     jeton d'administration du lab (WB_GITLAB_ADMIN_TOKEN_FILE). Si la branche refuse la poussée directe,
#     la modification passe par une MR fusionnée automatiquement. L'annulation est un COMMIT INVERSE qui
#     remet le contenu d'origine, et seulement si le fichier porte encore exactement le contenu injecté
#     (une réparation de l'apprenant n'est jamais défaite) ; jamais de réécriture d'historique ;
#   - les objets posés directement dans le cluster (CiliumNetworkPolicy) portent une annotation propre à la
#     panne et ne sont retirés que si elle est encore là ; le déclencheur de base de données (lenteur) porte
#     un commentaire propre à la panne ;
#   - aucune donnée n'est supprimée (compartiments tempo-k8s-par1, loki-k8s-par1, bases, volumes) ;
#   - l'auto-synchronisation d'Argo CD n'est jamais désactivée : on demande seulement un rafraîchissement.
#
# Environnement visé : MédiAgenda et MédiDoc de DEV (espaces mediagenda-dev et medidoc-dev, synchronisés
# automatiquement, sans canary). Témoin de trafic : déploiement « trafic-agenda » de l'espace wb-pannes, créé
# à la première injection (jamais supprimé par les pannes), qui appelle l'API de dev par la Gateway.
#
# Variables facultatives de lab/lab.env :
#   WB_M23_IMAGE_AGENDA   image du témoin (défaut : celle de MédiAgenda qui tourne en dev, sinon Harbor)
#   WB_M23_TRAFIC_URL     URL publiée de MédiAgenda dev (défaut https://mediagenda-dev.apps.par1.medisphere.internal)
#   WB_M23_APPEL_DOC      « MÉTHODE /chemin/{id}… » de l'appel MédiAgenda → MédiDoc ajouté en M23-E06
#                         (défaut : découvert dans /openapi.json, ex. POST /api/v1/rendez-vous/{rdv_id}/pieces-jointes)
#   WB_M23_TEMPO_UID      UID de la source Grafana Tempo (défaut : découvert par /api/frontend/settings)
#   WB_M23_ATTR_ENV       attribut d'environnement des traces (défaut resource.deployment.environment.name)
#   WB_RACINE_PKI         racine MédiSphère sur adm01 (défaut /usr/local/share/ca-certificates/medisphere-root-ca.crt)

# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M23_NS=wb-pannes
  _M23_TRACES=traces
  _M23_NS_AGENDA=mediagenda-dev
  _M23_NS_DOC=medidoc-dev
  _M23_PASSERELLE=otel-passerelle
  _M23_AGENT=otel-agent
  _M23_DEPOT_OBS=plateforme/observabilite
  _M23_DEPOT_AGENDA=mediagenda/deploiement
  _M23_DEPOT_DOC=medidoc/deploiement
  _M23_OVERLAY=overlays/dev/kustomization.yaml
  _M23_LUCAS_NOM="Lucas Martin"
  _M23_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
  _M23_ATTR_ENV="${WB_M23_ATTR_ENV:-resource.deployment.environment.name}"
  _M23_SEL_AGENDA="{resource.service.name = \"mediagenda-api\" && ${WB_M23_ATTR_ENV:-resource.deployment.environment.name} = \"dev\"}"
}

# ---------------------------------------------------------------------------
# État local (adm01) et journal
# ---------------------------------------------------------------------------

# m23_etat EXX — dossier d'état local de la panne (créé en 700).
m23_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M23-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m23_journal() {
  local ex="$1" d
  shift
  d="$(m23_etat "$ex")"
  printf '%s %s [M23-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}
m23_lire() {
  local f
  f="$(m23_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m23_ecrire() {
  local d
  d="$(m23_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}
m23_oublier() {
  local d
  d="$(m23_etat "$1")"
  rm -rf -- "${d:?}/$2"
}

# m23_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m23_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m23_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » (configuration différente de celle du corrigé) : on passe à la suivante.
m23_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m23${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M23-$ex n'a d'effet sur ce lab (configuration différente du corrigé)"
  return 1
}

m23_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }

# ---------------------------------------------------------------------------
# GitLab (jeton d'administration du lab, écriture) : commits de Lucas et commits inverses
# ---------------------------------------------------------------------------

_m23_gl_jeton() {
  local f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton GitLab d'administration illisible : $f (WB_GITLAB_ADMIN_TOKEN_FILE)"; return 1; }
  printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"$f")"
}

# m23_gl MÉTHODE CHEMIN — appel de l'API v4 ; corps JSON lu sur l'entrée standard pour POST et PUT.
m23_gl() {
  local m="$1" url="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/$2" cfg
  cfg="$(_m23_gl_jeton)" || return 1
  if [[ "$m" == GET ]]; then
    curl -sf --max-time 30 -K <(printf '%s\n' "$cfg") "$url" </dev/null
  else
    curl -sf --max-time 60 -X "$m" -H "Content-Type: application/json" --data-binary @- -K <(printf '%s\n' "$cfg") "$url"
  fi
}

_m23_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# m23_gl_fichier PROJET CHEMIN — contenu brut du fichier sur main (code 1 s'il n'existe pas).
m23_gl_fichier() {
  m23_gl GET "projects/$(_m23_enc "$1")/repository/files/$(_m23_enc "$2")/raw?ref=main"
}

# m23_gl_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
m23_gl_arbre() {
  local p page=1 r
  p="$(_m23_enc "$1")"
  while ((page < 20)); do
    r="$(m23_gl GET "projects/$p/repository/tree?ref=main&path=$(_m23_enc "$2")&recursive=true&per_page=100&page=$page")" || return 1
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    [[ "$(jq 'length' <<<"$r")" -ge 100 ]] || return 0
    page=$((page + 1))
  done
}

# _m23_gl_pousser PROJET MESSAGE NOM COURRIEL ACTIONS_JSON — commit sur main ; si la poussée directe est
# refusée (branche protégée), branche + MR fusionnée automatiquement (attente bornée de la fusion).
_m23_gl_pousser() {
  local p msg="$2" nom="$3" mel="$4" actions="$5" br r iid i etat
  p="$(_m23_enc "$1")"
  if jq -n --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    m23_gl POST "projects/$p/repository/commits" >/dev/null 2>&1; then
    return 0
  fi
  br="wb-m23-$(date +%s)-$RANDOM"
  jq -n --arg b "$br" --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: $b, start_branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    m23_gl POST "projects/$p/repository/commits" >/dev/null || return 1
  r="$(jq -n --arg b "$br" --arg t "$msg" \
    '{source_branch: $b, target_branch: "main", title: $t, remove_source_branch: true}' |
    m23_gl POST "projects/$p/merge_requests")" || return 1
  iid="$(jq -r '.iid' <<<"$r")"
  for ((i = 0; i < 60; i++)); do
    sleep 10
    printf '{"auto_merge": true}' | m23_gl PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
    etat="$(m23_gl GET "projects/$p/merge_requests/$iid" | jq -r '.state' 2>/dev/null)" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && return 1
  done
  wb_avert "la MR !$iid de $1 n'a pas été fusionnée en 10 min (pipeline ?)"
  return 1
}

# m23_commit EXX CLÉ PROJET "message" CHEMIN FICHIER_LOCAL [CHEMIN FICHIER_LOCAL…]
#   Remplace chaque CHEMIN de main par le contenu de FICHIER_LOCAL, au nom de Lucas. Mémorise, par CLÉ,
#   le contenu d'origine et le contenu injecté (pour le commit inverse de m23_retablir).
m23_commit() {
  local ex="$1" cle="$2" projet="$3" msg="$4" d actions='[]' chemin local_ n=0
  shift 4
  d="$(m23_etat "$ex")/git-$cle"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$projet" >"$d/projet"
  : >"$d/fichiers"
  while (($# >= 2)); do
    chemin="$1" local_="$2"
    shift 2
    n=$((n + 1))
    m23_gl_fichier "$projet" "$chemin" >"$d/orig-$n" || { wb_avert "$projet : $chemin introuvable sur main"; return 1; }
    cp "$local_" "$d/injecte-$n"
    printf '%s\t%s\n' "$n" "$chemin" >>"$d/fichiers"
    actions="$(jq --arg c "$chemin" --rawfile t "$local_" '. + [{action: "update", file_path: $c, content: $t}]' <<<"$actions")"
  done
  _m23_gl_pousser "$projet" "$msg

M23-$ex (lab/bin/break 23 ${ex#E})" "$_M23_LUCAS_NOM" "$_M23_LUCAS_COURRIEL" "$actions" || {
    rm -rf -- "$d"
    return 1
  }
  m23_journal "$ex" "commit de Lucas sur $projet ($(cut -f2 "$d/fichiers" | paste -sd' ' -)) [$cle]"
}

# m23_retablir EXX CLÉ — commit inverse : chaque fichier qui porte ENCORE exactement le contenu injecté
# reprend son contenu d'origine ; les autres (réparés ou modifiés depuis) ne sont pas touchés.
m23_retablir() {
  local ex="$1" cle="$2" d projet n chemin courant actions='[]' f
  d="$(m23_etat "$ex")/git-$cle"
  [[ -f "$d/fichiers" ]] || return 0
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if m23_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then
      actions="$(jq --arg c "$chemin" --rawfile t "$d/orig-$n" '. + [{action: "update", file_path: $c, content: $t}]' <<<"$actions")"
    else
      m23_journal "$ex" "annulation : $projet/$chemin modifié depuis la panne, laissé tel quel"
    fi
    rm -f "$f"
  done <"$d/fichiers"
  if [[ "$(jq 'length' <<<"$actions")" -gt 0 ]]; then
    _m23_gl_pousser "$projet" "Annulation de la panne M23-$ex (lab/bin/break 23 ${ex#E} --annuler)" \
      "Lab workbook" "workbook@medisphere.internal" "$actions" ||
      wb_avert "commit inverse impossible sur $projet : remets toi-même le contenu d'origine (copie : $d)"
  fi
  rm -rf -- "$d"
  m23_journal "$ex" "annulation des commits [$cle]"
}

# m23_commit_actif EXX CLÉ — le commit de la panne est encore en place (au moins un fichier injecté).
m23_commit_actif() {
  local d projet n chemin f r=1
  d="$(m23_etat "$1")/git-$2"
  [[ -f "$d/fichiers" ]] || return 1
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if m23_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then r=0; fi
    rm -f "$f"
  done <"$d/fichiers"
  return "$r"
}

# ---------------------------------------------------------------------------
# Argo CD : rafraîchissement (jamais de changement de politique de synchronisation)
# ---------------------------------------------------------------------------

# m23_argo_rafraichir ESPACE… — demande un rafraîchissement des Applications qui déploient dans ces espaces.
m23_argo_rafraichir() {
  local a
  for a in $(wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --args '.items[] | select(.spec.destination.namespace as $n | $ARGS.positional | index($n)) | .metadata.name' "$@"); do
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

# ---------------------------------------------------------------------------
# Charges applicatives (Deployment de dev) et overlays kustomize
# ---------------------------------------------------------------------------

# m23_charge ESPACE NOM_APP — « NOM_DU_DEPLOYMENT INDEX_DU_CONTENEUR » du déploiement de l'application
# (étiquette app.kubernetes.io/name=NOM_APP ; conteneur qui porte OTEL_SERVICE_NAME, sinon le premier).
m23_charge() {
  wb_kubectl -n "$1" get deployments -o json 2>/dev/null | jq -r --arg a "$2" '
    [.items[] | select(.spec.template.metadata.labels["app.kubernetes.io/name"] == $a)
     | select((.spec.template.metadata.labels["app.kubernetes.io/component"] // "api") != "test")][0]
    | if . == null then empty else
        (.spec.template.spec.containers | to_entries
         | (map(select([.value.env[]?.name] | index("OTEL_SERVICE_NAME"))) + .)[0].key) as $i
        | "\(.metadata.name) \($i)" end'
}

# m23_env_effective ESPACE DEPLOYMENT INDEX VARIABLE — valeur effective (env littéral, sinon ConfigMap de envFrom).
m23_env_effective() {
  local ns="$1" dep="$2" i="$3" v="$4" d cm val
  d="$(wb_kubectl -n "$ns" get deployment "$dep" -o json 2>/dev/null)" || return 1
  val="$(jq -r --argjson i "$i" --arg v "$v" '.spec.template.spec.containers[$i].env[]? | select(.name == $v) | .value // empty' <<<"$d")"
  if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  for cm in $(jq -r --argjson i "$i" '.spec.template.spec.containers[$i].envFrom[]?.configMapRef.name // empty' <<<"$d"); do
    val="$(wb_kubectl -n "$ns" get configmap "$cm" -o json 2>/dev/null | jq -r --arg v "$v" '.data[$v] // empty')"
    if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  done
  return 1
}

# m23_patch_env ESPACE DEPLOYMENT INDEX VARIABLE VALEUR — opération JSON 6902 (JSON) qui pose VARIABLE=VALEUR
# dans le gabarit de pod (remplace l'entrée env existante, sinon l'ajoute ; env l'emporte sur envFrom).
m23_patch_env() {
  local d
  d="$(wb_kubectl -n "$1" get deployment "$2" -o json 2>/dev/null)" || return 1
  jq -c --argjson i "$3" --arg v "$4" --arg val "$5" '
    .spec.template.spec.containers[$i] as $c
    | ([$c.env[]?.name] | index($v)) as $j
    | if $j != null then [{op: "replace", path: "/spec/template/spec/containers/\($i)/env/\($j)", value: {name: $v, value: $val}}]
      elif ($c.env // null) != null then [{op: "add", path: "/spec/template/spec/containers/\($i)/env/-", value: {name: $v, value: $val}}]
      else [{op: "add", path: "/spec/template/spec/containers/\($i)/env", value: [{name: $v, value: $val}]}] end' <<<"$d"
}

# m23_overlay_avec_patch PROJET DEPLOYMENT OPS_JSON SORTIE — écrit dans SORTIE la kustomization de l'overlay
# dev de PROJET complétée d'un patch JSON 6902 (cible : Deployment DEPLOYMENT). Nécessite yq (mikefarah).
m23_overlay_avec_patch() {
  local projet="$1" dep="$2" ops="$3" sortie="$4" orig
  orig="$(mktemp)"
  m23_gl_fichier "$projet" "$_M23_OVERLAY" >"$orig" || { rm -f "$orig"; return 1; }
  DEP="$dep" PATCH="$(yq -P '.' <<<"$ops")" yq '.patches += [{"target": {"kind": "Deployment", "name": strenv(DEP)}, "patch": strenv(PATCH)}]' "$orig" >"$sortie" ||
    { rm -f "$orig"; return 1; }
  rm -f "$orig"
}

# m23_deploiement_a ESPACE DEPLOYMENT INDEX 'filtre jq sur le conteneur' — le déploiement est entièrement
# déployé ET son gabarit satisfait le filtre (attente d'une synchronisation Argo CD et d'un déploiement).
m23_deploiement_a() {
  wb_kubectl -n "$1" get deployment "$2" -o json 2>/dev/null | jq -e --argjson i "$3" "
    (.spec.template.spec.containers[\$i] | $4)
    and (.status.observedGeneration // 0) >= .metadata.generation
    and (.status.updatedReplicas // 0) == (.spec.replicas // 1)
    and (.status.availableReplicas // 0) == (.spec.replicas // 1)
    and (.status.replicas // 0) == (.spec.replicas // 1)" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Collectors OpenTelemetry (fichiers de plateforme/observabilite/otel/, CR vivants)
# ---------------------------------------------------------------------------

# m23_otel_fichier NOM — chemin, dans plateforme/observabilite, du fichier qui déclare l'OpenTelemetryCollector NOM.
m23_otel_fichier() {
  local f c
  for f in $(m23_gl_arbre "$_M23_DEPOT_OBS" otel | grep -E '\.ya?ml$'); do
    c="$(m23_gl_fichier "$_M23_DEPOT_OBS" "$f" 2>/dev/null)" || continue
    if NOM="$1" yq -e 'select(.kind == "OpenTelemetryCollector" and .metadata.name == strenv(NOM)) | .metadata.name' >/dev/null 2>&1 <<<"$c"; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# m23_otel_modifier NOM 'expression yq sur .spec.config' FICHIER_ENTRÉE SORTIE — applique l'expression au
# document du collector NOM (les autres documents du fichier sont recopiés tels quels).
m23_otel_modifier() {
  NOM="$1" yq "(select(.kind == \"OpenTelemetryCollector\" and .metadata.name == strenv(NOM)) | .spec.config) |= ($2)" "$3" >"$4"
}

# m23_otel_vivant NOM 'filtre jq sur .spec.config' — le CR vivant satisfait le filtre et sa charge est à jour.
m23_otel_vivant() {
  local cr type
  cr="$(wb_kubectl -n "$_M23_TRACES" get opentelemetrycollectors.opentelemetry.io "$1" -o json 2>/dev/null)" || return 1
  jq -e ".spec.config | $2" >/dev/null 2>&1 <<<"$cr" || return 1
  type="$(jq -r '.spec.mode // "deployment"' <<<"$cr")"
  case "$type" in
    daemonset)
      wb_kubectl -n "$_M23_TRACES" get daemonset "$1-collector" -o json 2>/dev/null | jq -e '
        (.status.observedGeneration // 0) >= .metadata.generation
        and (.status.updatedNumberScheduled // 0) == .status.desiredNumberScheduled
        and (.status.numberReady // 0) == .status.desiredNumberScheduled' >/dev/null 2>&1 ;;
    *)
      wb_kubectl -n "$_M23_TRACES" get deployment "$1-collector" -o json 2>/dev/null | jq -e '
        (.status.observedGeneration // 0) >= .metadata.generation
        and (.status.updatedReplicas // 0) == (.spec.replicas // 1)
        and (.status.availableReplicas // 0) == (.spec.replicas // 1)' >/dev/null 2>&1 ;;
  esac
}

# m23_tempo_values — chemin des values de Tempo dans plateforme/observabilite (tempo/values*.yaml).
m23_tempo_values() {
  m23_gl_arbre "$_M23_DEPOT_OBS" tempo | grep -E '(^|/)values[^/]*\.ya?ml$' | head -n 1 | grep .
}

# ---------------------------------------------------------------------------
# Traces (Tempo par le proxy de la source Grafana) et métriques
# ---------------------------------------------------------------------------

m23_tempo_uid() {
  if [[ -n "${WB_M23_TEMPO_UID:-}" ]]; then printf '%s\n' "$WB_M23_TEMPO_UID"; return 0; fi
  grafana_api "frontend/settings" 2>/dev/null | jq -r '[.datasources[]? | select(.type == "tempo")][0].uid // empty' | grep .
}

# m23_traceql_nb 'TraceQL' DEPUIS — nombre de traces (au plus 100) qui commencent après DEPUIS (epoch).
m23_traceql_nb() {
  local uid q fin
  uid="$(m23_tempo_uid)" || { echo 0; return 1; }
  q="$(_m23_enc "$1")"
  fin="$(date +%s)"
  grafana_api "datasources/proxy/uid/$uid/api/search?q=$q&start=$2&end=$fin&limit=100" 2>/dev/null |
    jq --argjson t "$2" '[.traces[]? | select(((.startTimeUnixNano // "0") | tonumber) / 1e9 >= $t)] | length' 2>/dev/null || echo 0
}

# m23_prom_positif 'PromQL' — la requête renvoie au moins une valeur strictement positive.
m23_prom_positif() {
  prom_requete "$1" 2>/dev/null | jq -e '[.data.result[]?.value[1] | tonumber | select(. > 0)] | length > 0' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Témoin de trafic (espace wb-pannes)
# ---------------------------------------------------------------------------

m23_image_agenda() {
  local img tag
  if [[ -n "${WB_M23_IMAGE_AGENDA:-}" ]]; then printf '%s\n' "$WB_M23_IMAGE_AGENDA"; return 0; fi
  img="$(wb_kubectl -n "$_M23_NS_AGENDA" get pods -o json 2>/dev/null | jq -r '
    [.items[].spec.containers[].image | select(test("/medisphere/mediagenda-api[:@]"))][0] // empty')"
  if [[ -n "$img" ]]; then printf '%s\n' "$img"; return 0; fi
  tag="$(harbor_api 'projects/medisphere/repositories/mediagenda-api/artifacts?with_tag=true&page_size=30&sort=-push_time' 2>/dev/null |
    jq -r '[.[].tags[]?.name | select(test("^v[0-9]"))][0] // empty')"
  [[ -n "$tag" ]] || return 1
  printf 'registry.par1.medisphere.internal/medisphere/mediagenda-api:%s\n' "$tag"
}

# Script du témoin : deux requêtes par seconde sur l'API de dev (créneaux, liste), toutes les dix un cycle
# création → lecture → annulation du rendez-vous, et une fois sur deux, au milieu du cycle, l'appel qui
# traverse MédiDoc (M23-E06 : POST …/pieces-jointes, découvert dans /openapi.json). Données factices ;
# MédiDoc n'ayant pas d'API de suppression, chaque appel y laisse un objet de quelques octets (≈ 8 600 par
# jour dans le compartiment de dev) : supprime le témoin quand le module est terminé.
_m23_trafic_script() {
  cat <<'PY'
import json, os, random, re, ssl, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

CIBLE = os.environ["CIBLE"].rstrip("/")
RYTHME = float(os.environ.get("RYTHME", "2"))
CTX = ssl.create_default_context(cafile=os.environ.get("CA", "/etc/racine/racine.crt"))
PARIS = ZoneInfo("Europe/Paris")
STATS = {"ok": 0, "erreurs": 0, "appels_doc": 0}


def requete(methode, chemin, corps=None, brut=None, type_contenu="application/json"):
    donnees = brut if brut is not None else (json.dumps(corps).encode() if corps is not None else None)
    r = urllib.request.Request(CIBLE + chemin, data=donnees, method=methode,
                               headers={"Content-Type": type_contenu, "User-Agent": "trafic-temoin/1.0"})
    try:
        with urllib.request.urlopen(r, timeout=20, context=CTX) as rep:
            STATS["ok"] += 1
            return rep.status, rep.read()
    except urllib.error.HTTPError as e:
        STATS["erreurs"] += 1
        return e.code, b""
    except Exception as e:  # réseau, TLS, délai
        STATS["erreurs"] += 1
        print(json.dumps({"niveau": "WARNING", "message": "échec", "chemin": chemin, "erreur": str(e)}), flush=True)
        return 0, b""


def appel_doc():
    appel = os.environ.get("APPEL_DOC", "").strip()
    if appel:
        return appel
    statut, corps = requete("GET", "/openapi.json")
    if statut != 200:
        return ""
    for chemin, ops in json.loads(corps).get("paths", {}).items():
        if chemin.startswith("/api/v1/rendez-vous/") and re.search(r"document|piece", chemin):
            for methode in ("post", "get"):
                if methode in ops:
                    return methode.upper() + " " + chemin
    return ""


def cycle_creation(appel, avec_doc):
    jour = date.today() + timedelta(days=random.randint(30, 300))
    heure = random.choice([8, 9, 10, 11, 14, 15, 16, 17])
    debut = datetime(jour.year, jour.month, jour.day, heure, random.choice([0, 30]), tzinfo=PARIS)
    corps = {"patient": "Patient Témoin", "praticien": f"dr-temoin-{random.randint(1, 5)}",
             "debut": debut.isoformat(), "duree_minutes": 30, "motif": "contrôle"}
    statut, rep = requete("POST", "/api/v1/rendez-vous", corps)
    if statut != 201:
        return
    rdv = json.loads(rep)["id"]
    if appel and avec_doc:
        methode, chemin = appel.split(" ", 1)
        chemin = re.sub(r"\{[^}]+\}", str(rdv), chemin, count=1)
        if methode == "POST":  # pièce jointe factice de quelques octets, rangée par MédiDoc
            requete("POST", chemin + "?nom=temoin.txt", brut=b"document temoin", type_contenu="text/plain")
        else:
            requete(methode, chemin)
        STATS["appels_doc"] += 1
    requete("GET", f"/api/v1/rendez-vous/{rdv}")
    requete("DELETE", f"/api/v1/rendez-vous/{rdv}")


def main():
    appel = appel_doc()
    print(json.dumps({"niveau": "INFO", "message": "démarrage", "cible": CIBLE, "appel_doc": appel}), flush=True)
    i, dernier = 0, time.monotonic()
    while True:
        i += 1
        jour = (date.today() + timedelta(days=random.randint(1, 14))).isoformat()
        requete("GET", f"/api/v1/creneaux?date={jour}&praticien=dr-temoin-{random.randint(1, 5)}")
        if i % 3 == 0:
            requete("GET", "/api/v1/rendez-vous?limite=20")
        if i % 10 == 0:
            cycle_creation(appel, avec_doc=(i % 20 == 0))
        if time.monotonic() - dernier > 60:
            print(json.dumps({"niveau": "INFO", "message": "bilan", **STATS}), flush=True)
            dernier = time.monotonic()
        time.sleep(1 / RYTHME)


if __name__ == "__main__":
    main()
PY
}

_m23_trafic_manifeste() {
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trafic-agenda
  namespace: $_M23_NS
  labels: {app.kubernetes.io/name: trafic-agenda, medisphere.internal/ticket: PLAT-2419}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: trafic-agenda}}
  template:
    metadata:
      labels: {app.kubernetes.io/name: trafic-agenda}
    spec:
      automountServiceAccountToken: false
      imagePullSecrets: [{name: harbor-pull}]
      securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: trafic
          image: $1
          command: ["python", "/trafic/trafic.py"]
          env:
            - {name: CIBLE, value: "${WB_M23_TRAFIC_URL:-https://mediagenda-dev.apps.par1.medisphere.internal}"}
            - {name: RYTHME, value: "2"}
            - {name: APPEL_DOC, value: "${WB_M23_APPEL_DOC:-}"}
            - {name: CA, value: /etc/racine/racine.crt}
          resources: {requests: {cpu: 10m, memory: 48Mi}, limits: {cpu: 200m, memory: 96Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          volumeMounts:
            - {name: script, mountPath: /trafic, readOnly: true}
            - {name: racine, mountPath: /etc/racine, readOnly: true}
      volumes:
        - {name: script, configMap: {name: trafic-agenda}}
        - {name: racine, configMap: {name: racine-medisphere}}
EOF
}

m23_trafic_pret() {
  wb_kubectl -n "$_M23_NS" get deploy trafic-agenda -o json 2>/dev/null | jq -e '(.status.availableReplicas // 0) >= 1' >/dev/null 2>&1
}

# m23_trafic — crée le témoin de trafic s'il n'existe pas, puis attend qu'il tourne.
m23_trafic() {
  local img racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}" tmp
  if ! wb_kubectl -n "$_M23_NS" get deploy trafic-agenda >/dev/null 2>&1; then
    echo "Première injection du palier 4 : création du témoin de trafic dans l'espace $_M23_NS (1 à 2 min)…"
    [[ -r "$racine" ]] || { echo "Racine MédiSphère illisible : $racine (WB_RACINE_PKI)." >&2; return 1; }
    img="$(m23_image_agenda)" || {
      echo "Image MédiAgenda introuvable : renseigne WB_M23_IMAGE_AGENDA dans lab/lab.env." >&2
      return 1
    }
    if ! wb_kubectl get namespace "$_M23_NS" >/dev/null 2>&1; then
      wb_kubectl create namespace "$_M23_NS" >/dev/null || return 1
      wb_kubectl label namespace "$_M23_NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null || return 1
    fi
    if ! wb_kubectl -n "$_M23_NS" get secret harbor-pull >/dev/null 2>&1; then
      wb_kubectl -n "$_M23_NS_AGENDA" get secret harbor-pull -o json |
        jq --arg ns "$_M23_NS" '{apiVersion, kind, type, data, metadata: {name: "harbor-pull", namespace: $ns}}' |
        wb_kubectl apply -f - >/dev/null || { echo "Secret harbor-pull introuvable dans $_M23_NS_AGENDA." >&2; return 1; }
    fi
    wb_kubectl -n "$_M23_NS" create configmap racine-medisphere --from-file=racine.crt="$racine" \
      --dry-run=client -o yaml | wb_kubectl apply -f - >/dev/null || return 1
    tmp="$(mktemp -d)"
    _m23_trafic_script >"$tmp/trafic.py"
    wb_kubectl -n "$_M23_NS" create configmap trafic-agenda --from-file=trafic.py="$tmp/trafic.py" \
      --dry-run=client -o yaml | wb_kubectl apply -f - >/dev/null || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    _m23_trafic_manifeste "$img" | wb_kubectl apply -f - >/dev/null || return 1
  fi
  m23_attendre 180 m23_trafic_pret || {
    echo "Le témoin de trafic ($_M23_NS/trafic-agenda) ne démarre pas (kubectl -n $_M23_NS describe pod) : rien n'est cassé." >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

_m23_traces_recentes() { (($(m23_traceql_nb "$_M23_SEL_AGENDA" "$(($(date +%s) - 600))") > 0)); }

# m23_sain — refuse de casser une chaîne de traces qui ne fonctionne pas.
m23_sain() {
  local nom
  for nom in "$_M23_PASSERELLE" "$_M23_AGENT"; do
    if ! m23_otel_vivant "$nom" '. != null'; then
      echo "Le collector $nom (espace $_M23_TRACES) n'est pas entièrement prêt : répare d'abord (lab/bin/check 23 02)." >&2
      return 1
    fi
  done
  if ! m23_tempo_uid >/dev/null; then
    echo "Source Grafana Tempo introuvable avec le jeton des checks (WB_M23_TEMPO_UID ?) : rien n'est cassé." >&2
    return 1
  fi
  if ! m23_attendre 240 _m23_traces_recentes; then
    echo "Aucune trace récente de mediagenda-api en dev (TraceQL $_M23_SEL_AGENDA) : la chaîne doit marcher avant d'être cassée." >&2
    return 1
  fi
}

# m23_preparer — précondition commune ; pendant l'astreinte M23-E23 (_M23_ASTREINTE=1), break-E23 a déjà
# fait ces contrôles une fois.
m23_preparer() {
  if [[ -n "${_M23_ASTREINTE:-}" ]]; then return 0; fi
  command -v yq >/dev/null || { echo "yq (mikefarah) est requis sur adm01 pour les pannes du module 23." >&2; return 1; }
  m23_trafic || return 1
  m23_sain
}

# m23_debut EXX — mémorise l'heure de fin d'injection (epoch).
m23_debut() { m23_ecrire "$1" debut "$(date +%s)"; }

# m23_plus_de_traces EXX — aucune nouvelle trace de mediagenda-api (dev) depuis la fin de l'injection + 60 s ;
# attend que la fenêtre fasse au moins 2 min.
m23_plus_de_traces() {
  local t
  t="$(m23_lire "$1" debut)"
  [[ -n "$t" ]] || return 1
  t=$((t + 60))
  while (($(date +%s) < t + 120)); do sleep 10; done
  (($(m23_traceql_nb "$_M23_SEL_AGENDA" "$t") == 0))
}
