# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m28-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 28
# (check-E19 à check-E25). Sourcé, jamais lancé seul. S'appuie sur _m28-production.sh (préfixe _m28p_).
# Lecture seule. Préfixe _m28x_.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

# _m28x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M28-* si aucune) n'est marquée active.
_m28x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M28-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M28-$e" ]] || return 1
  done
}

# _m28x_evenements ESPACE RAISON [MINUTES=15] — somme des « count » des événements récents de cette raison.
_m28x_evenements() {
  local depuis
  depuis="$(date -u -d "-${3:-15} minutes" +%Y-%m-%dT%H:%M:%SZ)"
  kube -n "$1" get events --field-selector "reason=$2" -o json 2>/dev/null |
    jq --arg d "$depuis" '[.items[] | select((.lastTimestamp // .eventTime // "") >= $d) | (.count // 1)] | add // 0'
}

# _m28x_aucun_evenement ESPACE RAISON [MINUTES] — l'API répond et aucun événement récent de cette raison.
_m28x_aucun_evenement() {
  local n
  n="$(_m28x_evenements "$@")" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] && ((n == 0))
}

# _m28x_aucun_oom ESPACE [SÉLECTEUR] [MINUTES=15] — aucun conteneur terminé par OOMKilled récemment.
_m28x_aucun_oom() {
  local depuis
  depuis="$(date -u -d "-${3:-15} minutes" +%Y-%m-%dT%H:%M:%SZ)"
  kube -n "$1" get pods ${2:+-l "$2"} -o json 2>/dev/null | jq -e --arg d "$depuis" '
    [.items[].status.containerStatuses[]? | .lastState.terminated // empty
     | select(.reason == "OOMKilled" and (.finishedAt // "") >= $d)] | length == 0' >/dev/null 2>&1
}

# _m28x_catalogue 'chemin' 'filtre jq' — l'API du catalogue répond et satisfait le filtre.
_m28x_catalogue() { backstage_api "$1" 2>/dev/null | jq -e "$2" >/dev/null 2>&1; }
