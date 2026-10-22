# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq/yq et scripts distants entre apostrophes
# _m21-commun.sh — fonctions partagées par les scripts de panne du module 21 (M21-E35 à M21-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.11 « Pannes des blocs D et E ») :
#   - à partir du M20, ce qui est décrit dans Git est réconcilié par Argo CD (selfHeal) : modifier un
#     objet géré à la main ne tiendrait pas. Les pannes passent donc, selon le cas :
#       * par une MR de lucas.martin (jeton d'emprunt d'identité, révoqué aussitôt) fusionnée par ton
#         jeton d'administration GitLab (WB_GITLAB_ADMIN_TOKEN_FILE) dans plateforme/observabilite ou
#         mediagenda/deploiement : le commit porte le marqueur « M21-EXX » ; l'annulation passe par une
#         seconde MR (« revert(M21-EXX) ») qui applique la transformation INVERSE, et seulement si la
#         marque de la panne est encore dans le fichier (une réparation de l'apprenant n'est jamais
#         défaite, l'historique n'est jamais réécrit). Si le pipeline refuse la MR de Lucas, la variante
#         est « sans effet » (la CI a fait son travail) et le script en essaie une autre ;
#       * par des objets que rien ne réconcilie : Secrets créés hors Git, silences d'Alertmanager,
#         objets ajoutés dans des espaces non suivis, témoins de l'espace wb-pannes ;
#       * par des fichiers des VMs (mon01, VMs du socle), sauvegardés avant (pannes-lib : sauver).
#   - jamais de suppression de données : ni blocs Thanos (thanos-k8s-par1), ni volumes, ni séries ;
#     la panne de cardinalité (E38) est bornée (200 000 séries au plus) ;
#   - les objets Kubernetes modifiés sont sauvegardés en JSON nettoyé dans ~/.local/state/workbook/
#     M21-EXX/ et ne sont restaurés que s'ils portent encore la marque de la panne.
#
# Témoins (m21_temoins) : dans l'espace wb-pannes (créé au M14, sinon créé ici), une petite application
# « temoin-metriques » (2 réplicas, image Python tirée par le cache Harbor) qui expose des métriques
# pilotées par la ConfigMap « temoin-etat », son Service, son ServiceMonitor, sa PrometheusRule (alertes
# TemoinFileAttenteHaute, EssaiChaineAlerteCritique, EssaiChaineAlerteAvertissement) et une
# CiliumNetworkPolicy qui autorise la collecte depuis « supervision » sans mettre les pods en refus par
# défaut. Les témoins ne sont jamais supprimés par les pannes ; au repos, ils ne déclenchent rien.

_M21_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M21_NS=wb-pannes
_M21_SUP=supervision
_M21_PROM_URL="${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"
_M21_AM_URL="${WB_AM_URL:-http://alertmanager.apps.par1.medisphere.internal:9093}"
_M21_GL_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
_M21_PROJ_OBS="plateforme/observabilite"
_M21_PROJ_DEP="mediagenda/deploiement"
_M21_MON01="${WB_M21_MON01:-mon01}"
_M21_IMAGE_PY="${WB_M21_IMAGE_PYTHON:-registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie}"
_M21_SEL_CLE="medisphere.internal/supervision"
_M21_SEL_VAL="oui"
_M21_LUCAS_NOM="Lucas Martin"
_M21_LUCAS_MEL="lucas.martin@medisphere.internal"
_M21_JETON_LUCAS=""
read -r -a _M21_VMS <<<"${WB_M21_VMS_PANNE:-nbx01 dns02 runner01}"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m21_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m21_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M21-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

m21_journal() {
  local ex="$1" d
  shift
  d="$(m21_etat "$ex")"
  printf '%s %s [M21-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m21_lire EXX CLÉ / m21_ecrire EXX CLÉ VALEUR (écrase) / m21_oublier EXX CLÉ — petites valeurs d'état.
m21_lire() {
  local f
  f="$(m21_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m21_ecrire() {
  local d
  d="$(m21_etat "$1")"
  (umask 077 && printf '%s\n' "$3" >"$d/$2")
}
m21_oublier() {
  local d
  d="$(m21_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# m21_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m21_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m21_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10
# est « sans effet sur ce lab » (configuration différente de celle attendue, ou refusée par la CI) :
# on passe à la suivante. La fonction _m21EXX_une N fait l'injection ET attend son effet.
m21_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m21${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
    m21_journal "$ex" "variante $n sans effet sur ce lab, suivante"
  done
  wb_avert "aucune variante de M21-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

m21_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }
m21_maintenant() { date +%s; }

# ---------------------------------------------------------------------------
# Objets Kubernetes : sauvegarde nettoyée et restauration (adm01, kubeconfig d'administration)
# ---------------------------------------------------------------------------

_m21_fichier_objet() { printf '%s/%s_%s_%s.json\n' "$(m21_etat "$1")" "${4:-_cluster}" "${2//\//-}" "$3"; }

# m21_sauver_objet EXX TYPE NOM [ESPACE] — une seule fois par panne ; « ABSENT » si l'objet n'existe pas.
m21_sauver_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m21_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null | jq '
      del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation,
          .metadata.managedFields, .metadata.selfLink, .status)
      | if .metadata.annotations then .metadata.annotations |= del(."kubectl.kubernetes.io/last-applied-configuration") else . end' >"$f.tmp" 2>/dev/null &&
    [[ -s "$f.tmp" ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    printf 'ABSENT\n' >"$f"
  fi
  chmod 600 "$f"
}

# m21_objet_sauve EXX TYPE NOM [ESPACE] — affiche la copie sauvegardée (JSON) ; code 1 si aucune.
m21_objet_sauve() {
  local f
  f="$(_m21_fichier_objet "$@")"
  [[ -s "$f" ]] && [[ "$(head -c 6 "$f")" != ABSENT ]] && cat "$f"
}

# m21_restaurer_objet EXX TYPE NOM [ESPACE] — remet la copie (replace simple, jamais --force), ou
# supprime l'objet s'il n'existait pas, puis oublie la copie.
m21_restaurer_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m21_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] || return 0
  if [[ "$(head -c 6 "$f")" == ABSENT ]]; then
    wb_kubectl delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found >/dev/null 2>&1 || wb_avert "suppression de $type/$nom impossible"
  elif wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} >/dev/null 2>&1; then
    wb_kubectl replace -f "$f" >/dev/null 2>&1 || wb_avert "restauration de $type/$nom impossible (copie : $f)"
  else
    wb_kubectl create -f "$f" >/dev/null 2>&1 || wb_avert "recréation de $type/$nom impossible (copie : $f)"
  fi
  rm -f -- "$f"
}

# m21_oublier_objet EXX TYPE NOM [ESPACE] — efface la copie sans rien restaurer.
m21_oublier_objet() { rm -f -- "$(_m21_fichier_objet "$@")"; }

# ---------------------------------------------------------------------------
# Prometheus (vue globale, 10.10.41.60) et Alertmanager (10.10.41.61), depuis adm01 (MGMT)
# ---------------------------------------------------------------------------

# m21_promql 'expr' — requête instantanée, JSON de l'API.
m21_promql() {
  curl -sf --max-time 30 -H 'Accept: application/json' --data-urlencode "query=$1" "$_M21_PROM_URL/api/v1/query"
}
# m21_prom_valeur 'expr' — valeur du premier résultat (vide si aucun).
m21_prom_valeur() { m21_promql "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null; }
# m21_prom_nb 'expr' — nombre de séries renvoyées (0 si erreur).
m21_prom_nb() {
  local n
  n="$(m21_promql "$1" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null)" || n=0
  printf '%s\n' "${n:-0}"
}
# m21_prom_api 'chemin' — GET sur l'API de la vue globale (rules, stores, targets…).
m21_prom_api() { curl -sf --max-time 30 -H 'Accept: application/json' "$_M21_PROM_URL/api/v1/$1"; }

# m21_am MÉTHODE 'chemin' [options curl…] — API v2 d'Alertmanager du cluster (écriture : silences).
m21_am() {
  local m="$1" p="$2"
  shift 2
  curl -sS --fail --max-time 20 -X "$m" -H 'Accept: application/json' "$_M21_AM_URL/api/v2/$p" "$@"
}

# m21_am_config — configuration chargée par Alertmanager (texte YAML).
m21_am_config() { m21_am GET status 2>/dev/null | jq -r '.config.original // empty'; }

# m21_am_alerte NOM — alertes de ce nom vues par Alertmanager (JSON, tableau).
m21_am_alerte() {
  m21_am GET "alerts?filter=$(jq -rn --arg n "alertname=\"$1\"" '$n|@uri')" 2>/dev/null
}

# ---------------------------------------------------------------------------
# L'objet Prometheus de kube-prometheus-stack et ses sélecteurs
# ---------------------------------------------------------------------------

# m21_prom_cr_json — premier objet Prometheus de l'espace supervision (nom fixé en M21-E02).
m21_prom_cr_json() {
  wb_kubectl -n "$_M21_SUP" get prometheuses.monitoring.coreos.com -o json 2>/dev/null | jq -e '.items[0]'
}

# m21_etiquettes_objet CHAMP — étiquettes (JSON) qu'un objet doit porter pour être retenu par le
# sélecteur CHAMP (serviceMonitorSelector, ruleSelector…) : matchLabels, et pour matchExpressions
# « In » la première valeur, « Exists » la valeur « oui ». Toujours au moins la convention du module.
m21_etiquettes_objet() {
  m21_prom_cr_json 2>/dev/null | jq -c --arg c "$1" --arg k "$_M21_SEL_CLE" --arg v "$_M21_SEL_VAL" '
    (.spec[$c] // {}) as $s
    | ({($k): $v} + ($s.matchLabels // {})
       + ([$s.matchExpressions[]? | select(.operator == "In") | {(.key): .values[0]}] | add // {})
       + ([$s.matchExpressions[]? | select(.operator == "Exists") | {(.key): "oui"}] | add // {}))' 2>/dev/null ||
    jq -nc --arg k "$_M21_SEL_CLE" --arg v "$_M21_SEL_VAL" '{($k): $v}'
}

# m21_espace_retenu CHAMP ESPACE — 0 si l'espace est retenu par le sélecteur d'espaces CHAMP
# (ruleNamespaceSelector…) : {} = tous ; absent = l'espace de Prometheus seulement.
m21_espace_retenu() {
  local cr ns_json
  cr="$(m21_prom_cr_json)" || return 1
  ns_json="$(wb_kubectl get namespace "$2" -o json 2>/dev/null)" || return 1
  jq -en --argjson cr "$cr" --argjson ns "$ns_json" --arg c "$1" '
    ($cr.spec[$c]) as $s | ($ns.metadata.labels // {}) as $l
    | if $s == null then ($ns.metadata.name == $cr.metadata.namespace)
      else
        ([($s.matchLabels // {}) | to_entries[] | $l[.key] == .value] | all)
        and ([$s.matchExpressions[]? |
              if .operator == "In" then ($l[.key] as $x | .values | index($x)) != null
              elif .operator == "NotIn" then ($l[.key] as $x | .values | index($x)) == null
              elif .operator == "Exists" then $l | has(.key)
              elif .operator == "DoesNotExist" then ($l | has(.key)) | not
              else false end] | all)
      end' >/dev/null 2>&1
}

# m21_rendre_retenu ESPACE — pose sur l'espace les étiquettes demandées par les sélecteurs d'espaces
# des ServiceMonitors, PodMonitors et règles (matchLabels, « In » → première valeur, « Exists »).
# Code 1 si un sélecteur absent (espace de Prometheus seulement) l'interdit.
m21_rendre_retenu() {
  local ns="$1" c lbl
  for c in serviceMonitorNamespaceSelector ruleNamespaceSelector; do
    if m21_espace_retenu "$c" "$ns"; then continue; fi
    lbl="$(m21_prom_cr_json | jq -r --arg c "$c" '
      .spec[$c] as $s | if $s == null then empty else
        (($s.matchLabels // {}) + ([$s.matchExpressions[]? | select(.operator == "In") | {(.key): .values[0]}] | add // {})
         + ([$s.matchExpressions[]? | select(.operator == "Exists") | {(.key): "oui"}] | add // {}))
        | to_entries[] | "\(.key)=\(.value)" end')" || return 1
    [[ -n "$lbl" ]] || return 1
    # shellcheck disable=SC2086  # une étiquette par mot
    wb_kubectl label namespace "$ns" $lbl --overwrite >/dev/null || return 1
    m21_espace_retenu "$c" "$ns" || return 1
  done
}

# ---------------------------------------------------------------------------
# Argo CD (objets Application lus et rafraîchis avec le kubeconfig d'administration)
# ---------------------------------------------------------------------------

m21_app_json() { wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null; }

# m21_apps_du_depot CHEMIN_PROJET — Applications dont une source est ce dépôt GitLab (une par ligne).
m21_apps_du_depot() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null | jq -r --arg p "$1" '
    .items[] | select([(.spec.source // empty), (.spec.sources[]? // empty)] | map(.repoURL // "")
                      | any(sub("\\.git$"; "") | endswith("/" + $p)))
    | .metadata.name'
}

# m21_app_rafraichir APP — demande à Argo CD de relire Git maintenant.
m21_app_rafraichir() {
  wb_kubectl -n argocd annotate applications.argoproj.io "$1" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
}

# m21_app_revision_vue APP SHA — Argo CD a vu cette révision (source unique ou multi-sources).
m21_app_revision_vue() {
  m21_app_json "$1" | jq -e --arg s "$2" '
    ((.status.sync.revision // "") == $s) or ((.status.sync.revisions // []) | index($s) != null)' >/dev/null 2>&1
}

# m21_app_synchro_faite APP SHA — dernière opération terminée, sur cette révision.
m21_app_synchro_faite() {
  m21_app_json "$1" | jq -e --arg s "$2" '
    (.status.operationState.phase // "") as $p
    | ($p == "Succeeded" or $p == "Failed" or $p == "Error")
    and (((.status.operationState.syncResult.revision // "") == $s)
         or ((.status.operationState.syncResult.revisions // []) | index($s) != null))' >/dev/null 2>&1
}

# m21_app_synchro_reussie APP — dernière opération réussie et application Synced.
m21_app_synchro_reussie() {
  m21_app_json "$1" | jq -e '.status.operationState.phase == "Succeeded" and .status.sync.status == "Synced"' >/dev/null 2>&1
}

# m21_app_synchro_echouee APP — dernière opération en échec.
m21_app_synchro_echouee() {
  m21_app_json "$1" | jq -e '(.status.operationState.phase // "") | test("^(Failed|Error)$")' >/dev/null 2>&1
}

# m21_apps_attendre CHEMIN_PROJET SHA — pour chaque Application qui suit ce dépôt (hors *-prod, que
# l'on ne synchronise jamais à sa place) : rafraîchit, déclenche la synchronisation si elle n'est pas
# automatique, attend que l'opération sur SHA soit terminée (réussie ou non). Délai : 6 min par app.
m21_apps_attendre() {
  local proj="$1" sha="$2" a j
  while read -r a; do
    [[ -n "$a" && "$a" != *-prod ]] || continue
    m21_app_rafraichir "$a"
    if ! m21_attendre 180 m21_app_revision_vue "$a" "$sha"; then
      wb_avert "Argo CD n'a pas vu la révision ${sha:0:8} sur $a"
      continue
    fi
    j="$(m21_app_json "$a")"
    if ! jq -e '.spec.syncPolicy.automated' >/dev/null 2>&1 <<<"$j"; then
      wb_kubectl -n argocd patch applications.argoproj.io "$a" --type merge \
        -p '{"operation":{"initiatedBy":{"username":"lucas.martin"},"sync":{}}}' >/dev/null 2>&1 || true
    fi
    m21_attendre 360 m21_app_synchro_faite "$a" "$sha" || wb_avert "synchronisation de $a non terminée"
  done < <(m21_apps_du_depot "$proj")
}

# ---------------------------------------------------------------------------
# GitLab : lecture, MR de Lucas, fusion, transformation inverse
# ---------------------------------------------------------------------------

_m21_enc() { jq -rn --arg v "$1" '$v|@uri'; }

# m21_gl [--lucas] MÉTHODE CHEMIN [options curl…] — API v4 ; le jeton ne passe jamais en argument.
m21_gl() {
  local jeton
  if [[ "$1" == --lucas ]]; then
    shift
    jeton="$_M21_JETON_LUCAS"
  else
    jeton="$(<"${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}")" || return 1
  fi
  local m="$1" p="$2"
  shift 2
  curl -sS --fail --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$jeton") "$_M21_GL_URL/$p" "$@"
}

# m21_git_lire PROJET CHEMIN — contenu brut du fichier sur main.
m21_git_lire() {
  m21_gl GET "projects/$(_m21_enc "$1")/repository/files/$(_m21_enc "$2")/raw?ref=main"
}

# m21_git_arbre PROJET [DOSSIER] — chemins des fichiers (récursif), un par ligne.
m21_git_arbre() {
  local p=1 r
  while ((p < 50)); do
    r="$(m21_gl GET "projects/$(_m21_enc "$1")/repository/tree?ref=main&recursive=true&per_page=100&page=$p${2:+&path=$(_m21_enc "$2")}")" || return 1
    [[ "$(jq 'length' <<<"$r")" -gt 0 ]] || break
    jq -r '.[] | select(.type == "blob") | .path' <<<"$r"
    p=$((p + 1))
  done
}

# m21_git_tete PROJET — sha du dernier commit de main.
m21_git_tete() { m21_gl GET "projects/$(_m21_enc "$1")/repository/branches/main" | jq -r '.commit.id'; }

# _m21_lucas_jeton — jeton d'emprunt d'identité de lucas.martin (portée api, expire demain).
_m21_lucas_jeton() {
  local uid r
  uid="$(m21_gl GET 'users?username=lucas.martin' | jq -r '.[0].id // empty')" || return 1
  [[ -n "$uid" ]] || return 1
  r="$(m21_gl POST "users/$uid/impersonation_tokens" --data-urlencode "name=workbook-${WB_EX:-M21}" \
    --data-urlencode "expires_at=$(date -d tomorrow +%F)" --data-urlencode 'scopes[]=api')" || return 1
  _M21_JETON_LUCAS="$(jq -r '.token' <<<"$r")"
  _M21_LUCAS_IDS="$uid $(jq -r '.id' <<<"$r")"
}
_m21_lucas_revoquer() {
  local uid jid
  read -r uid jid <<<"${_M21_LUCAS_IDS:-}"
  if [[ -n "${jid:-}" ]]; then m21_gl DELETE "users/$uid/impersonation_tokens/$jid" >/dev/null 2>&1 || true; fi
  _M21_JETON_LUCAS=""
  _M21_LUCAS_IDS=""
}

# _m21_mr_etat PROJET IID — « état statut_fusion statut_pipeline » d'une MR.
_m21_mr_etat() {
  m21_gl GET "projects/$(_m21_enc "$1")/merge_requests/$2" |
    jq -r '"\(.state) \(.detailed_merge_status // .merge_status // "?") \(.head_pipeline.status // "aucun")"'
}

# m21_git_livrer PROJET TITRE ACTIONS_JSON [lucas|workbook] — branche, commit, MR, fusion (avec
# fusion automatique quand le pipeline réussit). Affiche le sha de main après fusion.
# Code 10 : la MR n'a pas pu être fusionnée (pipeline en échec, conflit) — elle est fermée.
m21_git_livrer() {
  local proj="$1" titre="$2" actions="$3" qui="${4:-lucas}" pe br corps iid t=0 e st pl opt=() rc=0
  pe="$(_m21_enc "$proj")"
  br="wb/${WB_EX:-M21}-$(date +%Y%m%d%H%M%S)"
  [[ "$qui" == lucas ]] && br="lucas/${WB_EX:-M21}-$(date +%Y%m%d%H%M%S)"
  if [[ "$qui" == lucas ]] && _m21_lucas_jeton && m21_gl --lucas POST "projects/$pe/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode ref=main >/dev/null 2>&1; then
    opt=(--lucas)
  else
    # Lucas n'a pas de droit d'écriture sur ce projet (ou annulation) : branche créée avec ton jeton,
    # commit signé « Lucas Martin » comme auteur pour la panne.
    m21_gl POST "projects/$pe/repository/branches" --data-urlencode "branch=$br" --data-urlencode ref=main >/dev/null || { _m21_lucas_revoquer; return 1; }
  fi
  corps="$(jq -n --arg b "$br" --arg m "$titre" --argjson a "$actions" --arg qui "$qui" \
    --arg n "$_M21_LUCAS_NOM" --arg e "$_M21_LUCAS_MEL" '
      {branch: $b, commit_message: $m, actions: $a}
      + (if $qui == "lucas" then {author_name: $n, author_email: $e} else {} end)')"
  if ! m21_gl "${opt[@]}" POST "projects/$pe/repository/commits" -H 'Content-Type: application/json' --data "$corps" >/dev/null; then
    m21_gl DELETE "projects/$pe/repository/branches/$(_m21_enc "$br")" >/dev/null 2>&1 || true
    _m21_lucas_revoquer
    return 1
  fi
  iid="$(m21_gl "${opt[@]}" POST "projects/$pe/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode target_branch=main --data-urlencode "title=$titre" --data-urlencode remove_source_branch=true \
    --data-urlencode "description=${WB_EX:-M21} — modification injectée par lab/bin/break (workbook)." | jq -r '.iid')" || iid=""
  _m21_lucas_revoquer
  [[ -n "$iid" && "$iid" != null ]] || return 1
  m21_journal "${WB_EX#M21-}" "MR !$iid ouverte sur $proj ($titre)"
  # Fusion (automatique au succès du pipeline si le projet l'exige). Jusqu'à 15 min.
  while ((t < 900)); do
    read -r e st pl <<<"$(_m21_mr_etat "$proj" "$iid" 2>/dev/null || echo "? ? ?")"
    case "$e" in
      merged) break ;;
      closed) rc=10; break ;;
    esac
    if [[ "$pl" =~ ^(failed|canceled)$ ]]; then rc=10; break; fi
    if [[ "$st" =~ ^(conflict|need_rebase|broken_status)$ ]]; then rc=10; break; fi
    if [[ ! "$st" =~ ^(checking|unchecked|preparing|approvals_syncing)$ ]]; then
      m21_gl PUT "projects/$pe/merge_requests/$iid/merge" --data-urlencode should_remove_source_branch=true \
        --data-urlencode auto_merge=true --data-urlencode merge_when_pipeline_succeeds=true >/dev/null 2>&1 || true
    fi
    sleep 15
    t=$((t + 15))
  done
  if [[ "$e" != merged ]]; then
    ((rc == 10)) || rc=10
    m21_gl PUT "projects/$pe/merge_requests/$iid" --data-urlencode state_event=close >/dev/null 2>&1 || true
    m21_gl DELETE "projects/$pe/repository/branches/$(_m21_enc "$br")" >/dev/null 2>&1 || true
    m21_journal "${WB_EX#M21-}" "MR !$iid de $proj non fusionnée (pipeline : $pl, état : $st) : fermée"
    return "$rc"
  fi
  m21_git_tete "$proj"
}

# m21_git_transformer EXX CLÉ PROJET CHEMIN TITRE FONCTION [lucas|workbook]
#   Lit CHEMIN sur main, le passe dans FONCTION (entrée → sortie standard), livre le résultat par MR
#   s'il diffère, attend les Applications qui suivent ce dépôt. Mémorise « PROJET CHEMIN » sous CLÉ
#   (pour l'annulation). Code 10 : rien à changer (fichier différent de l'attendu) ou MR refusée.
m21_git_transformer() {
  local ex="$1" cle="$2" proj="$3" chemin="$4" titre="$5" fn="$6" qui="${7:-lucas}" t sha rc=0 act
  t="$(mktemp -d)"
  if ! m21_git_lire "$proj" "$chemin" >"$t/avant"; then rm -rf -- "$t"; return 10; fi
  "$fn" <"$t/avant" >"$t/apres" 2>/dev/null || { rm -rf -- "$t"; return 10; }
  if [[ ! -s "$t/apres" ]] || cmp -s "$t/avant" "$t/apres"; then rm -rf -- "$t"; return 10; fi
  act="$(jq -n --arg p "$chemin" --rawfile c "$t/apres" '[{action: "update", file_path: $p, content: $c}]')"
  rm -rf -- "$t"
  [[ "$qui" == lucas ]] && m21_ecrire "$ex" "git-$cle" "$proj $chemin"
  sha="$(m21_git_livrer "$proj" "$titre" "$act" "$qui")" || rc=$?
  if ((rc != 0)); then
    [[ "$qui" == lucas ]] && m21_oublier "$ex" "git-$cle"
    return "$rc"
  fi
  m21_journal "$ex" "$proj:$chemin modifié (${sha:0:8})"
  m21_apps_attendre "$proj" "$sha"
}

# m21_git_defaire EXX CLÉ FONCTION_INVERSE TITRE — annulation d'une transformation : applique la
# fonction inverse au fichier COURANT (elle ne change rien si la marque de la panne n'y est plus).
m21_git_defaire() {
  local ex="$1" cle="$2" fn="$3" titre="$4" l proj chemin
  l="$(m21_lire "$ex" "git-$cle")"
  [[ -n "$l" ]] || return 0
  read -r proj chemin <<<"$l"
  m21_git_transformer "$ex" "annul-$cle" "$proj" "$chemin" "$titre" "$fn" workbook >/dev/null ||
    m21_journal "$ex" "annulation $cle : rien à défaire (déjà réparé ?) ou MR d'annulation refusée"
  m21_oublier "$ex" "git-$cle"
}

# m21_git_trouver PROJET 'filtre yq (vrai/faux)' [DOSSIER] — premier fichier YAML du dépôt dont un
# document satisfait le filtre (ex. '.kind == "ServiceMonitor"').
m21_git_trouver() {
  local proj="$1" f="$2" d="${3:-}" p t
  t="$(mktemp)"
  while read -r p; do
    [[ "$p" =~ \.ya?ml$ ]] || continue
    m21_git_lire "$proj" "$p" >"$t" 2>/dev/null || continue
    if [[ "$(yq "[$f] | any" "$t" 2>/dev/null | grep -c true)" -gt 0 ]]; then
      rm -f "$t"
      printf '%s\n' "$p"
      return 0
    fi
  done < <(m21_git_arbre "$proj" "$d")
  rm -f "$t"
  return 1
}

# m21_git_valeurs_kps — chemin du fichier de valeurs de kube-prometheus-stack (fixé en M21-E02 :
# kps/values.yaml de plateforme/observabilite ; sinon premier fichier qui porte .alertmanager et .prometheus).
m21_git_valeurs_kps() {
  if m21_git_lire "$_M21_PROJ_OBS" kps/values.yaml >/dev/null 2>&1; then
    echo kps/values.yaml
    return 0
  fi
  m21_git_trouver "$_M21_PROJ_OBS" 'has("alertmanager") and has("prometheus")'
}

# ---------------------------------------------------------------------------
# Hôtes (VMs du socle et mon01)
# ---------------------------------------------------------------------------

# m21_ssh HÔTE 'commande' — commande courte en root sur une VM (sortie standard).
m21_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null; }

# Aide ajoutée devant les scripts distants : retrouver une unité systemd par son binaire et lire une
# option de sa ligne de commande.
read -r -d '' _M21_AIDE <<'AIDE' || true
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# unite_de BINAIRE — unité de service dont l'ExecStart lance ce binaire (nom de base).
unite_de() {
  local u x
  for u in $(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk '{print $1}'); do
    x="$(systemctl show -p ExecStart --value "$u" 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -n 1)"
    [ "$(basename "${x:-/}")" = "$1" ] && { echo "$u"; return 0; }
  done
  return 1
}
# option_de UNITÉ OPTION — valeur d'une option longue (--opt=v ou --opt v) de la ligne de commande.
option_de() {
  systemctl show -p ExecStart --value "$1" 2>/dev/null | tr ' ;' '\n\n' |
    sed -n "s/^--$2=\(.*\)/\1/p; /^--$2\$/{n;p}" | head -n 1
}
oublier_fichiers() {
  local m="$WB_DIR/$WB_EX.manifeste" src dst
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r src dst; do
    [ "$dst" = ABSENT ] || rm -f -- "$dst"
  done < "$m"
  rm -f "$m"
}
AIDE

# m21_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec avec l'aide ci-dessus.
m21_wb_exec() {
  local h="$1"
  shift
  { printf '%s\n' "$_M21_AIDE"; cat; } | wb_exec "$h" "$@"
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m21_sain — refuse de casser une supervision qui ne va pas bien.
m21_sain() {
  local a
  if [[ "$(m21_prom_valeur 'vector(1)')" != 1 ]]; then
    echo "La vue globale ($_M21_PROM_URL) ne répond pas : rien n'est cassé (lab/bin/check 21 24)." >&2
    return 1
  fi
  if ! m21_am GET status >/dev/null 2>&1; then
    echo "Alertmanager ($_M21_AM_URL) ne répond pas : rien n'est cassé (lab/bin/check 21 06)." >&2
    return 1
  fi
  if ! m21_prom_cr_json >/dev/null; then
    echo "Aucun objet Prometheus dans l'espace $_M21_SUP (kubectl d'administration) : rien n'est cassé." >&2
    return 1
  fi
  for a in kube-prometheus-stack observabilite; do
    if ! m21_app_json "$a" | jq -e '.status.health.status == "Healthy" and .status.sync.status == "Synced"' >/dev/null 2>&1; then
      echo "L'Application Argo CD « $a » n'est pas Synced/Healthy : rien n'est cassé (lab/bin/check 21 02, 21 07)." >&2
      return 1
    fi
  done
  [[ -r "${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}" ]] || {
    echo "Jeton d'administration GitLab illisible (WB_GITLAB_ADMIN_TOKEN_FILE) : rien n'est cassé." >&2
    return 1
  }
  if ! yq --version 2>/dev/null | grep -q mikefarah; then
    echo "yq (mikefarah, v4) est nécessaire sur adm01 : rien n'est cassé." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Témoins (espace wb-pannes)
# ---------------------------------------------------------------------------

# Code de l'application témoin : Python 3, bibliothèque standard seulement. Elle relit l'état
# (/etc/temoin/etat.json, ConfigMap temoin-etat) à chaque collecte.
read -r -d '' _M21_TEMOIN_PY <<'PY' || true
"""Application témoin du palier 4 du module 21 (workbook MédiSphère)."""
import json
import os
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ETAT = "/etc/temoin/etat.json"
DEBUT = time.time()
FILES = ["f1", "f2", "f3", "f4", "f5"]
BORNE = 100000   # valeurs distinctes au plus, par pod (2 pods : 200 000 séries au plus)
LOT = 2500       # nouvelles valeurs par tranche de 15 s


def etat():
    try:
        with open(ETAT, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def file_attente(mode, nom, t):
    if mode == "pics":        # 45 s au-dessus du seuil toutes les 3 min, file f1
        return 80 if nom == "f1" and t % 180 < 45 else 5
    if mode == "continu":     # f1 au-dessus du seuil en permanence
        return 80 if nom == "f1" else 5
    if mode == "episodes":    # toutes les files hautes 20 min sur 30
        return 80 if t % 1800 < 1200 else 5
    return 3 + zlib.crc32(("%s%d" % (nom, t // 60)).encode()) % 5


def cardinalite(genre, t):
    if genre not in ("requete_id", "chemin", "utilisateur"):
        return []
    lignes = ["# HELP mediagenda_rapports_requetes_total Requetes du service de rapports.",
              "# TYPE mediagenda_rapports_requetes_total counter"]
    debut = (int(t // 15) * LOT) % BORNE
    for i in range(debut, debut + LOT):
        n = i % BORNE
        if genre == "requete_id":
            e = 'requete_id="%08x-%04x"' % ((n * 2654435761) % 4294967296, n % 65536)
        elif genre == "chemin":
            e = 'chemin="/api/v1/rendezvous/%d"' % (100000 + n)
        else:
            e = 'utilisateur="patient%06d@exemple.invalid"' % n
        lignes.append("mediagenda_rapports_requetes_total{%s} 1" % e)
    return lignes


def metriques():
    s = etat()
    t = time.time()
    l = ["# HELP temoin_file_attente Longueur des files du temoin.",
         "# TYPE temoin_file_attente gauge"]
    for f in FILES:
        l.append('temoin_file_attente{file="%s"} %d' % (f, file_attente(s.get("mode_file", "calme"), f, int(t))))
    l += ["# HELP temoin_essai_alerte Essai de la chaine d'alerte (1 = en cours).",
          "# TYPE temoin_essai_alerte gauge"]
    for niveau in ("critique", "avertissement"):
        l.append('temoin_essai_alerte{niveau="%s"} %d' % (niveau, 1 if s.get("essai") == 1 else 0))
    l += ["# HELP temoin_requetes_total Requetes servies par le temoin.",
          "# TYPE temoin_requetes_total counter",
          'temoin_requetes_total{code="200"} %d' % int((t - DEBUT) * 3)]
    l += cardinalite(s.get("cardinalite", "aucune"), t)
    return ("\n".join(l) + "\n").encode()


class Gestion(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/metrics"):
            corps, type_ = metriques(), "text/plain; version=0.0.4; charset=utf-8"
        elif self.path.startswith("/sante"):
            corps, type_ = b"ok\n", "text/plain"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("", int(os.environ.get("PORT", "8000"))), Gestion).serve_forever()
PY

# _m21_temoins_yaml — manifestes des témoins (étiquettes de sélection ajoutées ensuite).
_m21_temoins_yaml() {
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: temoin-etat
  namespace: $_M21_NS
  labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}
data:
  etat.json: '{"mode_file": "calme", "essai": 0, "cardinalite": "aucune"}'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: temoin-metriques
  namespace: $_M21_NS
  labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}
spec:
  replicas: 2
  selector: {matchLabels: {app.kubernetes.io/name: temoin-metriques}}
  template:
    metadata: {labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}}
    spec:
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: temoin
          image: $_M21_IMAGE_PY
          command: ["python3", "-B", "/opt/temoin/temoin.py"]
          env: [{name: PYTHONDONTWRITEBYTECODE, value: "1"}, {name: PORT, value: "8000"}]
          ports: [{name: metriques, containerPort: 8000}]
          readinessProbe: {httpGet: {path: /sante, port: metriques}, periodSeconds: 10}
          resources: {requests: {cpu: 20m, memory: 32Mi}, limits: {cpu: 300m, memory: 128Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          volumeMounts:
            - {name: code, mountPath: /opt/temoin, readOnly: true}
            - {name: etat, mountPath: /etc/temoin, readOnly: true}
      volumes:
        - {name: code, configMap: {name: temoin-code}}
        - {name: etat, configMap: {name: temoin-etat}}
---
apiVersion: v1
kind: Service
metadata:
  name: temoin-metriques
  namespace: $_M21_NS
  labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}
spec:
  selector: {app.kubernetes.io/name: temoin-metriques}
  ports: [{name: metriques, port: 8000, targetPort: metriques}]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: temoin-metriques
  namespace: $_M21_NS
  labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}
spec:
  selector: {matchLabels: {app.kubernetes.io/name: temoin-metriques}}
  endpoints: [{port: metriques, path: /metrics, interval: 15s}]
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: temoin-metriques
  namespace: $_M21_NS
  labels: {app.kubernetes.io/name: temoin-metriques, app.kubernetes.io/part-of: workbook-m21}
spec:
  groups:
    - name: temoin-m21
      rules:
        - alert: TemoinFileAttenteHaute
          expr: temoin_file_attente > 50
          for: 5m
          labels: {gravite: critique, equipe: plateforme}
          annotations:
            resume: "File {{ \$labels.file }} du service de rappels témoin au-dessus de 50 depuis 5 min"
            description: "Le pod {{ \$labels.pod }} a {{ \$value }} messages en attente dans la file {{ \$labels.file }}."
            runbook_url: "https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/observabilite/metriques/runbooks/RB-218-alertes-muettes-ou-bavardes.md"
        - alert: EssaiChaineAlerteCritique
          expr: max(temoin_essai_alerte{niveau="critique"}) == 1
          labels: {gravite: critique, equipe: plateforme}
          annotations:
            resume: "Essai de la chaîne d'alerte (critique) : ce courriel doit arriver à l'astreinte"
            description: "Essai déclenché depuis la ConfigMap temoin-etat de wb-pannes. Ne rien faire, accuser réception."
            runbook_url: "https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/observabilite/metriques/runbooks/RB-218-alertes-muettes-ou-bavardes.md"
        - alert: EssaiChaineAlerteAvertissement
          expr: max(temoin_essai_alerte{niveau="avertissement"}) == 1
          labels: {gravite: avertissement, equipe: plateforme}
          annotations:
            resume: "Essai de la chaîne d'alerte (avertissement)"
            description: "Essai déclenché depuis la ConfigMap temoin-etat de wb-pannes."
            runbook_url: "https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/observabilite/metriques/runbooks/RB-218-alertes-muettes-ou-bavardes.md"
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: temoin-metriques-collecte
  namespace: $_M21_NS
  labels: {app.kubernetes.io/part-of: workbook-m21}
spec:
  endpointSelector: {matchLabels: {app.kubernetes.io/name: temoin-metriques}}
  enableDefaultDeny: {ingress: false, egress: false}
  ingress:
    - fromEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": $_M21_SUP}}]
      toPorts: [{ports: [{port: "8000", protocol: TCP}]}]
EOF
}

# m21_temoin_cibles_ok — les deux pods témoins sont collectés (up == 1).
m21_temoin_cibles_ok() {
  [[ "$(m21_prom_nb "up{namespace=\"$_M21_NS\",service=\"temoin-metriques\"} == 1")" -ge 2 ]]
}
# m21_temoin_regles_ok — le groupe de règles des témoins est chargé.
m21_temoin_regles_ok() {
  m21_prom_api 'rules?type=alert' 2>/dev/null | jq -e '[.data.groups[]? | select(.name == "temoin-m21")] | length > 0' >/dev/null 2>&1
}
m21_temoins_prets() {
  wb_kubectl -n "$_M21_NS" get deploy temoin-metriques -o json 2>/dev/null |
    jq -e '(.status.availableReplicas // 0) >= 2' >/dev/null 2>&1 && m21_temoin_cibles_ok && m21_temoin_regles_ok
}

# m21_temoins — crée les témoins s'ils n'existent pas, puis attend qu'ils soient collectés.
m21_temoins() {
  local sm pr t
  if ! wb_kubectl -n "$_M21_NS" get deploy temoin-metriques >/dev/null 2>&1; then
    echo "Première injection du palier 4 : création des témoins dans l'espace $_M21_NS (2 à 5 min)…"
    if ! wb_kubectl get namespace "$_M21_NS" >/dev/null 2>&1; then
      wb_kubectl create namespace "$_M21_NS" >/dev/null || return 1
      wb_kubectl label namespace "$_M21_NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null || return 1
    fi
    if ! m21_rendre_retenu "$_M21_NS"; then
      echo "Les sélecteurs d'espaces de Prometheus n'admettent pas $_M21_NS (voir l'en-tête de enonce/04-expert.md) : rien n'est cassé." >&2
      return 1
    fi
    sm="$(m21_etiquettes_objet serviceMonitorSelector)"
    pr="$(m21_etiquettes_objet ruleSelector)"
    t="$(mktemp -d)"
    _m21_temoins_yaml >"$t/temoins.yaml"
    SM="$sm" PR="$pr" yq -i '
      (select(.kind == "ServiceMonitor") | .metadata.labels) *= (strenv(SM) | from_json)
      | (select(.kind == "PrometheusRule") | .metadata.labels) *= (strenv(PR) | from_json)' "$t/temoins.yaml" || { rm -rf -- "$t"; return 1; }
    printf '%s\n' "$_M21_TEMOIN_PY" >"$t/temoin.py"
    if ! wb_kubectl -n "$_M21_NS" create configmap temoin-code --from-file=temoin.py="$t/temoin.py" \
      --dry-run=client -o yaml | wb_kubectl apply -f - >/dev/null; then
      rm -rf -- "$t"
      return 1
    fi
    if ! wb_kubectl apply -f "$t/temoins.yaml" --dry-run=server >/dev/null; then
      echo "Les témoins sont refusés par l'API (admission, CRD absente ?) : rien n'a été créé." >&2
      rm -rf -- "$t"
      return 1
    fi
    wb_kubectl apply -f "$t/temoins.yaml" >/dev/null || { rm -rf -- "$t"; return 1; }
    rm -rf -- "$t"
  fi
  if ! m21_attendre 420 m21_temoins_prets; then
    echo "Les témoins de $_M21_NS ne sont pas collectés par Prometheus (cible up{namespace=\"$_M21_NS\"}, groupe de règles temoin-m21) :" >&2
    echo "vérifie les sélecteurs de l'objet Prometheus et la politique réseau de l'espace $_M21_SUP. Rien n'est cassé." >&2
    return 1
  fi
}

# m21_temoin_etat 'filtre jq' — modifie l'état des témoins (ConfigMap temoin-etat), ex. '.essai = 1'.
m21_temoin_etat() {
  local cm neuf
  cm="$(wb_kubectl -n "$_M21_NS" get configmap temoin-etat -o json)" || return 1
  neuf="$(jq -c "(.data[\"etat.json\"] | fromjson) | $1" <<<"$cm")" || return 1
  wb_kubectl -n "$_M21_NS" patch configmap temoin-etat --type merge \
    -p "$(jq -nc --arg e "$neuf" '{data: {"etat.json": $e}}')" >/dev/null
}
# m21_temoin_etat_lire — état courant (JSON).
m21_temoin_etat_lire() {
  wb_kubectl -n "$_M21_NS" get configmap temoin-etat -o json 2>/dev/null | jq -c '.data["etat.json"] | fromjson' 2>/dev/null
}

# m21_preparer — précondition commune : supervision saine, puis témoins prêts (créés au besoin).
# Pendant l'astreinte (M21-E43, _M21_ASTREINTE=1), break-E43 a fait ces contrôles une fois.
m21_preparer() {
  if [[ -n "${_M21_ASTREINTE:-}" ]]; then return 0; fi
  m21_sain || return 1
  m21_temoins
}
