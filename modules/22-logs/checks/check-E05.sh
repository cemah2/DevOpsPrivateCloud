# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M22-E05 : Alloy sur les VMs du socle
# À lancer depuis adm01. Lecture seule : séries « journald » par VM dans le locataire plateforme
# (LogQL métrique, 2 h), étiquettes indexées, service alloy des VMs (systemctl is-active en SSH),
# fichiers sur main (GitLab). Liste des VMs attendues : WB_M22_VMS_SOCLE (lab.env), sinon le socle v4.

# shellcheck source=_m22-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-decouverte.sh"

title "M22-E05 — Alloy sur les VMs du socle"
require_cmd jq curl ssh

_m22d_e05_r="$(_m22d_requete 'sum by (host, role, site) (count_over_time({job="journald", host=~".+"}[2h]))' plateforme 2h)"
_m22d_e05_hotes="$(jq -r '.data.result[]?.metric.host' <<<"${_m22d_e05_r:-{\}}" 2>/dev/null | sort -u || true)"

for _m22d_e05_vm in "${_M22D_VMS[@]}"; do
  check_cmd "$_m22d_e05_vm : journal systemd reçu par Loki depuis 2 h (job=journald, host=$_m22d_e05_vm)" \
    grep -qx -- "$_m22d_e05_vm" <<<"$_m22d_e05_hotes"
done
check_cmd "chaque flux de VM porte les étiquettes role et site=par1" _m22d_json "$_m22d_e05_r" \
  '(.data.result | length) > 0 and all(.data.result[]; (.metric.role // "") != "" and (.metric.role != "inconnu") and .metric.site == "par1")'
_m22d_e05_hors="$(_m22d_hors_liste plateforme 2h)"
check_cmd "plateforme : aucune étiquette indexée hors liste (${_m22d_e05_hors:-aucune})" bash -c '[[ -z "$1" ]]' _ "$_m22d_e05_hors"
check_cmd "unité et niveau en métadonnées structurées (pas en étiquettes)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22d_nb_resultats '{job="journald", host=~".+"} | unite=~".+\\.service" | niveau=~".+"' plateforme 2h)"
if [[ -n "$_m22d_e05_hotes" ]]; then
  check_cmd "niveau debug jamais envoyé" bash -c '[[ "$1" -eq 0 ]]' _ \
    "$(_m22d_nb_resultats '{job="journald", host=~".+"} | niveau="debug"' plateforme 2h)"
else
  skip "niveau debug jamais envoyé" "aucun journal de VM reçu : contrôle sans objet"
fi

# --- Agent sur les VMs (échantillon : adm01 et une VM de l'INFRA) -------------------------------------
check_cmd "adm01 : service alloy actif, exécuté par le compte alloy" bash -c \
  '[[ "$(systemctl is-active alloy 2>/dev/null)" == active && "$(systemctl show -p User --value alloy 2>/dev/null)" == alloy ]]'
check_ssh "mon01 : service alloy actif" mon01 "systemctl is-active --quiet alloy"
check_ssh "mon01 : /usr/local/bin/alloy est la version 1.21" mon01 "/usr/local/bin/alloy --version | grep -q 'v1\\.21\\.'"
check_ssh "mon01 : interface de l'agent fermée au réseau (127.0.0.1:12345 seulement)" mon01 \
  "ss -Hltn 'sport = :12345' | awk '{print \$4}' | grep -qx '127.0.0.1:12345'"

# --- Le code ----------------------------------------------------------------------------------------------
_m22d_e05_p="projects/plateforme%2Fansible"
for _m22d_e05_f in roles/alloy/tasks/main.yml roles/alloy/templates/config.alloy.j2 playbooks/journaux-vms.yml; do
  check_cmd "plateforme/ansible (main) : $_m22d_e05_f" _m22d_fichier_main "$_m22d_e05_p" "$_m22d_e05_f"
done
check_output "pare-feu de la bordure : flux vers Loki 10.10.41.62:3100 décrit (pare_feu.yml)" 'LOKI|10\.10\.41\.62' \
  _m22d_contenu_main "$_m22d_e05_p" inventories/lab/group_vars/role_routeur/pare_feu.yml
check_output "matrice des flux (plateforme/medisphere) : Loki 10.10.41.62 TCP 3100" '10\.10\.41\.62' \
  _m22d_contenu_main "$_M22D_P_DOC" docs/socle/matrice-flux.md
