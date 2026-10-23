# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m27-operationnel.sh — fonctions partagées par les checks M27-E06 à M27-E12 (lecture seule).
# Reprend celles du palier 1 (_m27-decouverte.sh : _m27d_k, _m27d_json, _m27d_app, _m27d_rmq,
# _m27d_prom, _m27d_contenu_main, _m27d_doc_contient…) et ajoute les siennes, préfixe _m27o_.
# Accès : mêmes que le palier 1 (kube = wb-checks, jamais les Secrets ; rabbitmq_api ; Prometheus ;
# GitLab en lecture). Sous « set -euo pipefail » : tout ce qui peut échouer est protégé.

# shellcheck source=_m27-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-decouverte.sh"

# Mineure attendue de Valkey (E07).
_M27O_VALKEY="${WB_M27_VALKEY_VERSION:-9.1}"
_M27O_VALKEY_RE="${_M27O_VALKEY//./\\.}"
# Même chose pour une chaîne PromQL : barres obliques inverses doublées (9\\.1).
_M27O_VALKEY_PROM="${_M27O_VALKEY//./\\\\.}"
_M27O_TRAVAIL="${WB_M27_TRAVAIL:-$HOME/m27}"

# _m27o_job_reussi PROJET NOM_JOB — un job de ce nom a réussi sur main (100 derniers jobs réussis).
_m27o_job_reussi() {
  local j
  j="$(gitlab_api "$1/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null || true)"
  [[ -n "$j" ]] && jq -e --arg n "$2" 'any(.[]; .name == $n and .ref == "main")' <<<"$j" >/dev/null 2>&1
}

# _m27o_absent ARGS… — l'objet n'existe pas (kubectl répond NotFound). Faux si l'API ne répond pas.
_m27o_absent() {
  local sortie
  sortie="$(kube get "$@" -o name 2>&1)" && return 1
  grep -q 'NotFound' <<<"$sortie"
}

# _m27o_groupe_absent GROUPE — aucun type de ce groupe d'API n'est servi (CRD supprimées).
_m27o_groupe_absent() {
  local r
  r="$(kube api-resources --api-group="$1" -o name 2>/dev/null)" || return 1
  [[ -z "$r" ]]
}

# _m27o_journal_job NS JOB — journal du dernier pod réussi d'un Job (vide sinon).
_m27o_journal_job() {
  local pod
  pod="$(_m27d_k get pods -n "$1" -l "job-name=$2" -o json |
    jq -r '[.items[] | select(.status.phase == "Succeeded")] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty' 2>/dev/null || true)"
  [[ -n "$pod" ]] && _m27d_k logs -n "$1" "$pod"
  return 0
}

# _m27o_geree_par OBJET_JSON APPLICATION — l'objet est suivi par cette Application d'Argo CD
# (annotation de suivi « <app>:<groupe>/<type>:<espace>/<nom> », ou étiquette d'instance).
_m27o_geree_par() {
  _m27d_json "$1" '((.metadata.annotations["argocd.argoproj.io/tracking-id"] // "") | startswith($a + ":"))
                   or ((.metadata.labels["app.kubernetes.io/instance"] // "") == $a)' --arg a "$2"
}
