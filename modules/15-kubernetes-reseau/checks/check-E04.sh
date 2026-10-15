# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2001  # filtres jq entre apostrophes ; sed sur un texte multiligne
#
# check-E04.sh — M15-E04 : CoreDNS : résolution interne et DNS de MédiSphère
# À lancer depuis adm01. Lecture seule : ConfigMap et Deployment coredns (wb-checks), pod sonde-ndots,
# fichiers de plateforme/k8s et plateforme/medisphere sur main (API GitLab en GET).

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E04 — CoreDNS : résolution interne et DNS de MédiSphère"
require_cmd kubectl jq yq curl

_m15d_e04_corefile="$(kube -n kube-system get configmap coredns -o json 2>/dev/null | jq -r '.data.Corefile // ""' 2>/dev/null || true)"
# Corefile sans commentaires, pour ne pas compter une ligne mise en commentaire.
_m15d_e04_cf="$(sed 's/#.*$//' <<<"$_m15d_e04_corefile")"

# _m15d_e04_bloc ZONE — contenu du bloc de serveur « ZONE:53 { … } » (premier niveau d'accolades).
_m15d_e04_bloc() {
  awk -v z="$1" '
    !dedans && $0 ~ "^[[:space:]]*" z ":53[[:space:]]*\\{" { dedans = 1; prof = 0 }
    dedans { print; n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); prof += n - m; if (prof == 0) exit }
  ' <<<"$_m15d_e04_cf"
}
_m15d_e04_general="$(_m15d_e04_bloc '\\.')"
_m15d_e04_interne="$(_m15d_e04_bloc 'medisphere\\.internal')"

check_cmd "le Corefile a un bloc général « .:53 »" test -n "$_m15d_e04_general"
check_output "bloc général : forward vers 10.10.20.10 et 10.10.20.16" \
  'forward[[:space:]]+\.[[:space:]]+10\.10\.20\.10[[:space:]]+10\.10\.20\.16' echo "$_m15d_e04_general"
check_cmd "bloc général : plus de transfert vers /etc/resolv.conf du nœud" \
  bash -c '[[ -n "$1" ]] && ! grep -q "/etc/resolv.conf" <<<"$1"' _ "$_m15d_e04_general"
check_output "bloc général : greffon kubernetes pour cluster.local conservé" \
  'kubernetes[[:space:]]+cluster\.local' echo "$_m15d_e04_general"
check_cmd "bloc général : greffons loop, reload, cache, health, ready conservés" \
  bash -c 'for g in loop reload cache health ready; do grep -Eq "^[[:space:]]*$g([[:space:]{]|$)" <<<"$1" || exit 1; done' _ "$_m15d_e04_general"
check_cmd "un bloc « medisphere.internal:53 » distinct existe" test -n "$_m15d_e04_interne"
check_output "bloc medisphere.internal : forward vers 10.10.20.10 et 10.10.20.16" \
  'forward[[:space:]]+\.[[:space:]]+10\.10\.20\.10[[:space:]]+10\.10\.20\.16' echo "$_m15d_e04_interne"

_m15d_e04_dep="$(_m15d_get -n kube-system deployment coredns)"
check_cmd "CoreDNS : au moins 2 réplicas prêts" _m15d_json "$_m15d_e04_dep" '(.status.readyReplicas // 0) >= 2'
_m15d_e04_svc="$(_m15d_get -n kube-system service kube-dns)"
check_cmd "Service kube-dns en 10.96.0.10" _m15d_json "$_m15d_e04_svc" '.spec.clusterIP == "10.96.0.10"'

# --- Le Corefile du cluster est celui du dépôt ----------------------------------------------------------
_m15d_e04_depot="$(_m15d_contenu_main "$_M15D_PROJET_K8S" composants/coredns/configmap-coredns.yaml)"
check_cmd "composants/coredns/configmap-coredns.yaml sur main de plateforme/k8s" test -n "$_m15d_e04_depot"
_m15d_e04_corefile_depot() {
  # Le fichier peut contenir plusieurs documents : on prend le Corefile de la ConfigMap coredns.
  yq 'select(.kind == "ConfigMap" and .metadata.name == "coredns") | .data.Corefile' <<<"$_m15d_e04_depot" 2>/dev/null || true
}
_m15d_e04_norm() { sed 's/#.*$//; s/[[:space:]]\+/ /g; s/^ //; s/ $//' | grep -v '^$' || true; }
check_cmd "le Corefile du cluster est identique à celui du dépôt (commentaires et espaces ignorés)" \
  bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ \
  "$(_m15d_e04_norm <<<"$_m15d_e04_corefile")" "$(_m15d_e04_corefile_depot | _m15d_e04_norm)"

# --- La sonde à ndots réduit ------------------------------------------------------------------------------
_m15d_e04_pod="$(_m15d_get -n "$_M15D_NS" pod sonde-ndots)"
check_cmd "pod sonde-ndots en marche, dnsPolicy ClusterFirst et option ndots 2" _m15d_json "$_m15d_e04_pod" \
  '.status.phase == "Running" and (.spec.dnsPolicy // "ClusterFirst") == "ClusterFirst"
   and any(.spec.dnsConfig.options[]?; .name == "ndots" and .value == "2")'

# --- La fiche ----------------------------------------------------------------------------------------------
_m15d_e04_doc="$(_m15d_contenu_main "$_M15D_PROJET_DOC" docs/kubernetes/reseau/dns-du-cluster.md)"
check_cmd "docs/kubernetes/reseau/dns-du-cluster.md sur main" test -n "$_m15d_e04_doc"
check_cmd "la fiche explique ndots et dnsPolicy" \
  bash -c 'grep -qi "ndots" <<<"$1" && grep -qi "dnsPolicy" <<<"$1"' _ "$_m15d_e04_doc"
