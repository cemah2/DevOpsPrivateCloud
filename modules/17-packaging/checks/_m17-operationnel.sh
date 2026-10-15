# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# _m17-operationnel.sh — fonctions des vérifications du palier 2 du module 17 (check-E06 à E12).
# Reprend celles du palier 1 (_m17-decouverte.sh) et ajoute les lectures propres au palier.
# LECTURE SEULE. Préfixe _m17o_.

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

# _m17o_chart_yaml — Chart.yaml de mediagenda sur main (GitLab), vide si absent.
_m17o_chart_yaml() { _m17d_gl_fichier mediagenda/chart charts/mediagenda/Chart.yaml; }

# _m17o_dependance NOM [CHAMP=VALEUR] — Chart.yaml (main) déclare la dépendance NOM (et le champ).
_m17o_dependance() {
  local y
  y="$(_m17o_chart_yaml)" || y=""
  [[ -n "$y" ]] || return 1
  if [[ -n "${2:-}" ]]; then
    yq -e ".dependencies[] | select(.name == \"$1\") | .${2%%=*} == \"${2#*=}\"" >/dev/null 2>&1 <<<"$y"
  else
    yq -e ".dependencies[] | select(.name == \"$1\")" >/dev/null 2>&1 <<<"$y"
  fi
}

# _m17o_compte_fichiers PROJET DOSSIER REGEX MIN — au moins MIN fichiers de DOSSIER dont le chemin
# correspond à REGEX.
_m17o_compte_fichiers() {
  local n
  n="$(_m17d_gl_arbre "$1" "$2" | grep -Ec -- "$3")" || n=0
  (( n >= $4 ))
}

# _m17o_pv_de ESPACE — 0 si AUCUN PersistentVolume n'est lié à un PVC de ESPACE.
_m17o_aucun_pv_de() {
  kube get pv -o json 2>/dev/null | jq -e --arg n "$1" '[.items[] | select(.spec.claimRef.namespace == $n)] | length == 0' >/dev/null 2>&1
}

# _m17o_espace_absent ESPACE — l'espace n'existe pas (ou est en cours de suppression).
_m17o_espace_absent() {
  local j
  j="$(kube get namespace "$1" -o json 2>/dev/null)" || return 0
  jq -e '.status.phase == "Terminating"' >/dev/null 2>&1 <<<"$j"
}
