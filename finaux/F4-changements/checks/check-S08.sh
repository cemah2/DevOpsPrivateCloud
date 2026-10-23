# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes évaluées sur les nœuds entre apostrophes
# check-S08.sh — F4-S08 « Monter OpenStack de 2026.1 à 2026.2 ». Selon la décision de CHG-3408 :
#   go    : projet uv de plateforme/openstack en Kolla-Ansible 23.x avec un ansible-core de la plage
#           exigée, conteneurs en images 2026.2, services OpenStack sains, déploiement tracé (deploye-*) ;
#   no-go : répétition documentée, la production reste en 22.x.
# Dans les deux cas : mesure conforme côté témoin (k8s-par1 arrêté), fiche et RB-344.
# Les contrôles de services sont ignorés (et dits ignorés) si le profil openstack est arrêté.
# Lecture seule.
#
# Variables : WB_SRC (défaut ~/src), WB_OS_CLOUD (défaut medisphere-admin), WB_F4_KOLLA_SERIE (défaut 23),
# WB_F4_OPENSTACK_SERIE (défaut 2026.2), WB_F4_ANSIBLE_CORE_RE (défaut ^2\.(20|21)\.).

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S08 — Monter OpenStack de 2026.1 à 2026.2"
require_cmd curl jq ssh

_f4_s08_src="${WB_SRC:-$HOME/src}/openstack"
_f4_s08_cloud="${WB_OS_CLOUD:-medisphere-admin}"
_f4_s08_kolla="${WB_F4_KOLLA_SERIE:-23}"
_f4_s08_serie="${WB_F4_OPENSTACK_SERIE:-2026.2}"
_f4_s08_ac_re="${WB_F4_ANSIBLE_CORE_RE:-^2\.(20|21)\.}"
_f4_s08_noeuds=(osctl01 oscmp01 oscmp02)

_f4_s08_decision="$(_f4m_decision CHG-3408 2>/dev/null || true)"
check_cmd "CHG-3408 : décision go ou no-go dans l'en-tête" test -n "$_f4_s08_decision"

# Version épinglée dans uv.lock du dépôt (main), lue par l'API (le clone local peut être sur une branche).
_f4_s08_lock="$(_f4m_fichier plateforme/openstack uv.lock 2>/dev/null || true)"
_f4_s08_version_lock() {
  awk -v p="$1" '$0 == "name = \"" p "\"" { getline; gsub(/version = |"/, ""); print; exit }' <<<"$_f4_s08_lock"
}
_f4_s08_ka="$(_f4_s08_version_lock kolla-ansible || true)"
_f4_s08_ac="$(_f4_s08_version_lock ansible-core || true)"

if [[ "$_f4_s08_decision" == go ]]; then
  title "Issue « go » : production en $_f4_s08_serie"
  check_output "plateforme/openstack uv.lock (main) : kolla-ansible $_f4_s08_kolla.x (trouvé : ${_f4_s08_ka:-rien})" \
    "^${_f4_s08_kolla}\\.[0-9]+" printf '%s\n' "${_f4_s08_ka:-}"
  check_output "plateforme/openstack uv.lock (main) : ansible-core de la plage de Kolla $_f4_s08_kolla (trouvé : ${_f4_s08_ac:-rien})" \
    "$_f4_s08_ac_re" printf '%s\n' "${_f4_s08_ac:-}"
  check_cmd "plateforme/openstack (main) : openstack_release ou openstack_tag de la série $_f4_s08_serie" bash -c \
    'grep -Eq "^(openstack_release|openstack_tag):.*${1//./\\.}" <<<"$2"' _ "$_f4_s08_serie" \
    "$(_f4m_fichier plateforme/openstack etc/kolla/globals.yml 2>/dev/null || true)"
  # Étiquettes deploye-AAAAMMJJ-HHMM (heure locale d'adm01, M10-E46) : marge de 3 h pour le fuseau.
  _f4_s08_etiquette() {
    local d0
    d0="$(_f4m_epoch "$(_f4m_fiche_cle CHG-3408 mesure-debut)")" || return 1
    gitlab_api "projects/plateforme%2Fopenstack/repository/tags?search=%5Edeploye-&per_page=100" 2>/dev/null |
      jq -e --argjson d0 "$d0" '[.[].name | select(test("^deploye-[0-9]{8}-[0-9]{4}$"))
        | ltrimstr("deploye-") | strptime("%Y%m%d-%H%M") | mktime | select(. >= ($d0 - 10800))] | length > 0' >/dev/null 2>&1
  }
  check_cmd "plateforme/openstack : une étiquette deploye-* posée pendant ou après la fenêtre de CHG-3408" _f4_s08_etiquette

  if timeout 60 openstack --os-cloud "$_f4_s08_cloud" token issue -f json >/dev/null 2>&1; then
    title "Services OpenStack"
    _f4_s08_os() { timeout 90 openstack --os-cloud "$_f4_s08_cloud" "$@" -f json 2>/dev/null; }
    check_cmd "services de calcul : tous activés et « up »" bash -c \
      'jq -e "type == \"array\" and length > 0 and all(.[]; .State == \"up\" and .Status == \"enabled\")" >/dev/null <<<"$1"' _ \
      "$(_f4_s08_os compute service list || echo null)"
    check_cmd "agents réseau OVN : tous vivants" bash -c \
      'jq -e "type == \"array\" and length > 0 and all(.[]; .Alive == true)" >/dev/null <<<"$1"' _ \
      "$(_f4_s08_os network agent list || echo null)"
    check_cmd "services Cinder : tous « up »" bash -c \
      'jq -e "type == \"array\" and length > 0 and all(.[]; .State == \"up\")" >/dev/null <<<"$1"' _ \
      "$(_f4_s08_os volume service list || echo null)"
    for _f4_s08_h in "${_f4_s08_noeuds[@]}"; do
      check_ssh "$_f4_s08_h : conteneurs Kolla en images $_f4_s08_serie, aucun unhealthy ni arrêté" "$_f4_s08_h" \
        "out=\$(sudo -n docker ps -a --format '{{.Image}} {{.Status}}') || exit 1
         [ -n \"\$out\" ] || exit 1
         ! printf '%s\n' \"\$out\" | grep -Eq 'unhealthy|Exited|Restarting' || exit 1
         printf '%s\n' \"\$out\" | awk '{print \$1}' | grep -v '^$' | grep -vq '$_f4_s08_serie' && exit 1
         exit 0"
    done
  else
    skip "services OpenStack" "API injoignable avec le profil $_f4_s08_cloud (profil openstack arrêté ?) : relance le profil pour vérifier"
  fi
elif [[ "$_f4_s08_decision" == no-go ]]; then
  title "Issue « no-go » : répétition et attente de la stable"
  check_output "plateforme/openstack uv.lock (main) : la production reste en kolla-ansible 22.x (trouvé : ${_f4_s08_ka:-rien})" \
    '^22\.' printf '%s\n' "${_f4_s08_ka:-}"
  check_cmd "CHG-3408 : répétition faite (rc, résultats) et condition de reprise écrite" \
    _f4m_fiche_contient CHG-3408 'r(é|e)p(é|e)tition' 'rc|candidate' 'reprise|stable'
fi

title "Mesure et traces"
if [[ "$(_f4m_fiche_cle CHG-3408 mesure-source 2>/dev/null || true)" == temoin ]]; then
  _ok "CHG-3408 : mesure prise par le témoin de mon01 (k8s-par1 arrêté)"
else
  _ko "CHG-3408 : mesure-source attendue « temoin » (le cluster est arrêté pendant la montée)"
fi
check_cmd "CHG-3408 : mesure restreinte aux sondes de l'IP flottante (mesure-groupes vise continuite-openstack)" \
  bash -c '[[ -n "$1" ]] && grep -q "openstack" <<<"$1"' _ "$(_f4m_fiche_cle CHG-3408 mesure-groupes 2>/dev/null || true)"
_f4m_controles_mesure CHG-3408
check_cmd "CHG-3408 : k8s-par1 arrêté, sauvegarde PBS de la base, prechecks, IP flottante mesurée" \
  _f4m_fiche_contient CHG-3408 'k8s-par1' 'pbs|mariadb-backup|mariabackup' 'prechecks' 'flottante|fip'
check_cmd "RB-344 publié : montée de série OpenStack" _f4m_doc runbooks '^RB-344' 'kolla-mergepwd|mergepwd' 'upgrade' 'ansible-core'
