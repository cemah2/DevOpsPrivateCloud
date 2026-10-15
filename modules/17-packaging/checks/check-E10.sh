# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E10.sh — M17-E10 « Helmfile : décrire la plateforme ». Lecture seule : fichiers de
# plateforme/k8s (GitLab, et « helmfile list » sur une copie de origin/main, sans contact avec le
# cluster), étiquettes de chart des objets en place, diff final enregistré.

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E10 — Helmfile : décrire la plateforme"
require_cmd jq kubectl git

check_cmd "plateforme/k8s (main) : helmfile.yaml" _m17d_gl_existe plateforme/k8s helmfile.yaml
check_cmd "plateforme/k8s (main) : releases/_communs.yaml" _m17d_gl_existe plateforme/k8s releases/_communs.yaml
check_cmd "plateforme/k8s (main) : au moins un releases/*.yaml.gotmpl" _m17o_compte_fichiers plateforme/k8s releases '\.yaml\.gotmpl$' 1

_e10_attendues="kube-system/cilium cert-manager/cert-manager external-dns/external-dns ceph-csi/ceph-csi-rbd ceph-csi/ceph-csi-cephfs cnpg-system/cnpg cnpg-system/plugin-barman-cloud velero/velero kube-system/metrics-server"
_e10_liste=""
if command -v helmfile >/dev/null 2>&1; then
  _e10_k="$(_m17d_extraire "$_m17d_k8s_clone" .)" || _e10_k=""
  if [[ -n "$_e10_k" ]]; then
    _e10_liste="$(cd "$_e10_k" && helmfile -e par1 list --output json 2>/dev/null)" || _e10_liste=""
  fi
fi
if [[ -z "$_e10_liste" ]]; then
  skip "contenu de helmfile -e par1 list" "helmfile absent, clone $_m17d_k8s_clone absent, ou fichier qui ne se rend pas"
fi

# _e10_version_vivante ESPACE RELEASE CHART VERSION — 0 si aucun objet de la release n'annonce une autre
# version de chart ; 2 si aucune étiquette de version n'est lisible ; 1 si écart.
_e10_version_vivante() {
  local j vals
  j="$(kube get deploy,daemonset,statefulset -n "$1" -o json 2>/dev/null)" || return 1
  vals="$(jq -r --arg r "$2" '.items[] | select((.metadata.annotations["meta.helm.sh/release-name"] // "") == $r)
          | .metadata.labels // {} | to_entries[] | .value' <<<"$j" 2>/dev/null | grep -E "^$3-v?[0-9]" | sort -u)" || vals=""
  [[ -n "$vals" ]] || return 2
  grep -qvx -- "$3-$4" <<<"$vals" && return 1
  return 0
}

for _e10_a in $_e10_attendues; do
  _e10_ns="${_e10_a%%/*}"; _e10_r="${_e10_a##*/}"
  _e10_existe() {
    kube get deploy,daemonset -n "$_e10_ns" -o json 2>/dev/null \
      | jq -e --arg r "$_e10_r" '[.items[] | select((.metadata.annotations["meta.helm.sh/release-name"] // "") == $r)] | length > 0' >/dev/null 2>&1
  }
  check_cmd "$_e10_a : la release existe toujours dans le cluster" _e10_existe
  [[ -n "$_e10_liste" ]] || continue
  _e10_e="$(jq -c --arg n "$_e10_r" --arg ns "$_e10_ns" '[.[] | select(.name == $n and .namespace == $ns)][0] // empty' <<<"$_e10_liste")" || _e10_e=""
  if [[ -z "$_e10_e" ]]; then
    check_cmd "$_e10_a : déclarée dans Helmfile" false
    continue
  fi
  check_cmd "$_e10_a : déclarée dans Helmfile avec les étiquettes groupe et composant" \
    _m17d_jq "$_e10_e" '(.labels // "") | test("groupe:") and test("composant:")'
  _e10_chart="$(jq -r '.chart | sub(".*/"; "")' <<<"$_e10_e")" || _e10_chart=""
  _e10_ver="$(jq -r '.version // ""' <<<"$_e10_e")" || _e10_ver=""
  _e10_rc=0; _e10_version_vivante "$_e10_ns" "$_e10_r" "$_e10_chart" "$_e10_ver" || _e10_rc=$?
  case "$_e10_rc" in
    0) check_cmd "$_e10_a : version déclarée $_e10_ver = version en place" true ;;
    2) skip "$_e10_a : version en place" "aucune étiquette $_e10_chart-<version> sur les objets : compare avec helm list -A" ;;
    *) check_cmd "$_e10_a : version déclarée $_e10_ver = version en place" false ;;
  esac
done

_e10_diff="$_m17d_brouillons/e10/diff-final.txt"
check_cmd "diff-final.txt : helmfile diff terminé avec le code 0" _m17d_fichier_contient "$_e10_diff" '(code de sortie|exit code)[^0-9]*0[[:space:]]*$'
_e10_sans_ecart() { [[ -s "$_e10_diff" ]] && ! grep -Eq '^[[:space:]]*[-+][[:space:]]+[A-Za-z]|has changed|will be (created|deleted)' "$_e10_diff"; }
check_cmd "diff-final.txt : aucune ligne d'écart" _e10_sans_ecart

_e10_secrets() {
  local f c
  for f in $(_m17d_gl_arbre plateforme/k8s composants | grep -E 'values[^/]*\.ya?ml$'); do
    c="$(_m17d_gl_fichier plateforme/k8s "$f")"
    if grep -iE '^[[:space:]]*[A-Za-z_]*(password|passwd|token|secretaccesskey|accesskey|privatekey|tsigsecret)[[:space:]]*:[[:space:]]*[^[:space:]{]' <<<"$c" \
        | grep -viqE '(existing|secretname|secretref|_ref|keyref|file|name)[A-Za-z_]*[[:space:]]*:'; then
      return 1
    fi
  done
  return 0
}
check_cmd "composants/*/values : aucune valeur secrète en clair" _e10_secrets
