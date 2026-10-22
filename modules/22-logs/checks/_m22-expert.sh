# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _m22-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 22
# (check-E19 à check-E25). Sourcé, jamais lancé seul. S'appuie sur _m22-production.sh (préfixe _m22p_).
# Lecture seule : « kube » (wb-checks), SSH + sudo -n de commandes de consultation sur les nœuds,
# Prometheus et Loki en GET. Préfixe _m22x_.

# shellcheck source=_m22-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-production.sh"

read -r -a _m22x_cp <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _m22x_w <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_m22x_noeuds=("${_m22x_cp[@]}" "${_m22x_w[@]}")

# _m22x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m22x_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

_m22x_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _m22x_noeud HÔTE 'commande' — commande de LECTURE en root (sudo -n) sur un nœud ; code de retour.
_m22x_noeud() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }

# _m22x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M22-* si aucune) n'est marquée.
_m22x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M22-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M22-$e" ]] || return 1
  done
}

# _m22x_prom_zero 'PromQL' — la requête répond et ne renvoie que des zéros (ou rien) ; code 2 si
# Prometheus ne collecte pas Loki (pas de série loki_build_info).
_m22x_prom_zero() {
  local r
  r="$(prom_requete 'count(loki_build_info)' 2>/dev/null)" || return 2
  jq -e '.data.result | length > 0' >/dev/null 2>&1 <<<"$r" || return 2
  r="$(prom_requete "$1" 2>/dev/null)" || return 1
  jq -e '.status == "success" and all(.data.result[]?; (.value[1] | tonumber) == 0)' >/dev/null 2>&1 <<<"$r"
}

# _m22x_alloy_complet — le DaemonSet alloy est prêt sur tous les nœuds Ready.
_m22x_alloy_complet() {
  local n
  n="$(kube get nodes -o json 2>/dev/null | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length' 2>/dev/null)" || return 1
  kube -n journaux get daemonset alloy -o json 2>/dev/null |
    jq -e --argjson n "${n:-0}" '$n > 0 and .status.desiredNumberScheduled == $n and .status.numberReady == $n' >/dev/null 2>&1
}

# _m22x_alloy_sur NŒUD — un pod alloy prêt tourne sur le nœud.
_m22x_alloy_sur() {
  kube -n journaux get pods -l app.kubernetes.io/name=alloy --field-selector "spec.nodeName=$1" -o json 2>/dev/null |
    jq -e '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 1' >/dev/null 2>&1
}

# _m22x_lignes_recentes LOCATAIRE 'sélecteur' [DEPUIS=10m] — au moins une ligne.
_m22x_lignes_recentes() { (($(_m22p_nb_lignes "$1" "$2" "${3:-10m}") > 0)); }

# _m22x_audit_recent [DEPUIS=10m] — le locataire audit reçoit (sélecteurs usuels).
_m22x_audit_recent() {
  local s
  for s in '{job=~".+"}' '{node=~".+"}' '{cluster=~".+"}'; do
    _m22x_lignes_recentes audit "$s" "${1:-10m}" && return 0
  done
  return 1
}
