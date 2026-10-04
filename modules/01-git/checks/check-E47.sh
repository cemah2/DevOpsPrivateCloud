# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E47.sh — M01-E47 « Mini-projet : la forge MédiSphère »
# Contrôle global de la forge (à lancer depuis adm01) + dossier de livraison dans
# plateforme/medisphere. Lecture seule. Les contrôles détaillés restent dans leurs exercices.

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E47 — La forge MédiSphère : contrôle global"
require_cmd git jq curl ssh dig

# --- 1. VMs de la forge ------------------------------------------------------------------
title "1/8 VMs git01 et runner01"
for _m01_vm in "1004 role-gitlab" "1007 role-runner"; do
  read -r _m01_id _m01_role <<<"$_m01_vm"
  check_ssh_output "VM $_m01_id : démarrée" "$WB_PVE_HOST" '^status: running' "qm status $_m01_id"
  check_ssh "VM $_m01_id : démarrage automatique, étiquettes socle et $_m01_role" "$WB_PVE_HOST" \
    "c=\$(qm config $_m01_id); echo \"\$c\" | grep -q '^onboot: 1' && echo \"\$c\" | grep -Eq '^tags:.*(^|[;, ])socle([;, ]|\$)' && echo \"\$c\" | grep -q '^tags:.*$_m01_role'"
done
check_ssh "VMs 1004 et 1007 rangées dans le pool lab" "$WB_PVE_HOST" \
  'p=$(pvesh get /pools/lab --output-format json); for i in 1004 1007; do echo "$p" | grep -Eq "\"vmid\" *: *$i([^0-9]|\$)" || exit 1; done'
check_ssh "git01 démarre après dns01 (ordre de démarrage)" "$WB_PVE_HOST" \
  'o() { qm config "$1" | sed -nE "s/^startup:.*order=([0-9]+).*/\1/p"; }; d=$(o 1002); g=$(o 1004); [ -n "$g" ] && [ "$g" -gt "${d:-0}" ]'
check_ssh "aucune VM jetable du module oubliée (2010-2019)" "$WB_PVE_HOST" \
  '! qm list | awk "NR>1 {print \$1}" | grep -Eq "^201[0-9]$"'

# --- 2. DNS --------------------------------------------------------------------------------
title "2/8 DNS"
check_dns "A git01.par1.medisphere.internal" git01.par1.medisphere.internal A '^10\.10\.20\.12$' 10.10.20.10
check_dns "A runner01.par1.medisphere.internal" runner01.par1.medisphere.internal A '^10\.10\.20\.15$' 10.10.20.10
check_dns "PTR 10.10.20.12" 12.20.10.10.in-addr.arpa PTR '^git01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_dns "PTR 10.10.20.15" 15.20.10.10.in-addr.arpa PTR '^runner01\.par1\.medisphere\.internal\.$' 10.10.20.10

# --- 3. GitLab ---------------------------------------------------------------------------
title "3/8 GitLab"
check_http "HTTPS de GitLab avec un certificat reconnu par adm01" \
  "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/users/sign_in" 200
check_cmd "GitLab en version 19.4.x" _m01_api_ok version '.version | startswith("19.4.")'
check_ssh_output "git01 : sonde /-/readiness au vert" git01 '"status":"ok"' \
  "curl -s --max-time 10 --resolve $_M01_FQDN_GIT:443:127.0.0.1 https://$_M01_FQDN_GIT/-/readiness"
check_cmd "Git en SSH : GitLab accueille ton compte" _m01_ssh_bienvenue

# --- 4. Runner -----------------------------------------------------------------------------
title "4/8 Runner"
check_ssh "runner01 : gitlab-runner actif et activé" runner01 \
  'systemctl is-active -q gitlab-runner && systemctl is-enabled -q gitlab-runner'
check_cmd "runner d'instance shell+socle : unique, en ligne, actif" \
  _m01_api_ok 'runners/all?type=instance_type&tag_list=shell,socle&per_page=100' \
  'length == 1 and .[0].status == "online" and (.[0].paused | not)'

# --- 5. Projets de la plateforme ---------------------------------------------------------------
title "5/8 Projets plateforme/*"
_m01_projets="$(gitlab_api 'groups/plateforme/projects?per_page=100&include_subgroups=true&archived=false' 2>/dev/null \
  | jq -r '.[].path_with_namespace' 2>/dev/null)" || _m01_projets=""
check_cmd "groupe plateforme : au moins medisphere et ci-templates" bash -c \
  'grep -qx plateforme/medisphere <<<"$1" && grep -qx plateforme/ci-templates <<<"$1"' _ "$_m01_projets"
while IFS= read -r _m01_p; do
  [[ -n "$_m01_p" ]] || continue
  _m01_e="projects/$(jq -rn --arg p "$_m01_p" '$p|@uri')"
  check_cmd "$_m01_p : branche par défaut main, fusion conditionnée au pipeline et aux discussions" \
    _m01_api_ok "$_m01_e" '.default_branch == "main" and .only_allow_merge_if_pipeline_succeeds
       and .only_allow_merge_if_all_discussions_are_resolved and (.allow_merge_on_skipped_pipeline | not)'
  check_cmd "$_m01_p : méthode de fusion de l'équipe (commit de fusion, historique semi-linéaire)" \
    _m01_api_ok "$_m01_e" '.merge_method == "rebase_merge"'
  check_cmd "$_m01_p : étiquettes v* protégées" _m01_api_existe "$_m01_e/protected_tags/v%2A"
  check_cmd "$_m01_p : main protégée, poussée directe interdite" \
    _m01_api_ok "$_m01_e/protected_branches/main" '[.push_access_levels[].access_level] | length > 0 and all(. == 0)'
  check_cmd "$_m01_p : .pre-commit-config.yaml sur main" \
    _m01_api_existe "$_m01_e/repository/files/.pre-commit-config.yaml?ref=main"
  check_cmd "$_m01_p : .gitlab-ci.yml sur main" \
    _m01_api_existe "$_m01_e/repository/files/.gitlab-ci.yml?ref=main"
  check_cmd "$_m01_p : dernier pipeline de main réussi" \
    _m01_api_ok "$_m01_e/pipelines?ref=main&per_page=1" '.[0].status == "success"'
done <<<"$_m01_projets"
check_cmd "plateforme/medisphere : CONTRIBUTING.md sur main" \
  _m01_api_existe "$_M01_P_MED/repository/files/CONTRIBUTING.md?ref=main"
check_cmd "plateforme/medisphere : modèle de MR par défaut sur main" \
  _m01_api_existe "$_M01_P_MED/repository/files/.gitlab%2Fmerge_request_templates%2FDefault.md?ref=main"

# --- 6. Releases -----------------------------------------------------------------------------
title "6/8 Releases"
for _m01_p in plateforme/medisphere plateforme/ci-templates; do
  _m01_e="projects/$(jq -rn --arg p "$_m01_p" '$p|@uri')"
  check_cmd "$_m01_p : au moins une Release vX.Y.Z" \
    _m01_api_ok "$_m01_e/releases?per_page=1" '.[0].tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")'
done
check_cmd "plateforme/medisphere : étiquette annotée forge-v1 publiée" \
  _m01_api_ok "$_M01_P_MED/repository/tags/forge-v1" '(.message // "") != ""'

# --- 7. Sauvegarde ---------------------------------------------------------------------------
title "7/8 Sauvegarde de GitLab"
check_ssh "git01 : sauvegarde gitlab-backup de moins de 48 h" git01 \
  'sudo -n find /var/opt/gitlab/backups -maxdepth 1 -name "*_gitlab_backup.tar" -mmin -2880 | grep -q .'
check_ssh "git01 : sauvegarde de la configuration (backup-etc) de moins de 8 jours" git01 \
  'sudo -n find /etc/gitlab/config_backup /var/opt/gitlab/config_backup /var/opt/gitlab/backups -name "gitlab_config_*.tar" -mtime -8 2>/dev/null | grep -q .'
check_ssh "git01 → pbs01 : API PBS joignable (TCP/8007)" git01 "timeout 5 bash -c '</dev/tcp/10.20.10.10/8007'"
check_ssh "pbs01 : instantané de moins de 48 h dans l'espace de noms par1/git01" "$WB_PBS_HOST" '
  p=$(proxmox-backup-manager datastore show ds-lab --output-format json | perl -MJSON::PP -0777 -ne "print decode_json(\$_)->{path}")
  [ -n "$p" ] && find "$p/ns/par1/ns/git01" -mindepth 3 -maxdepth 3 -type d -mmin -2880 2>/dev/null | grep -q .'

# --- 8. Dossier de livraison et hygiène ----------------------------------------------------------
title "8/8 Dossier de livraison (plateforme/medisphere) et hygiène"
_m01_depot="${WB_DEPOT:-$HOME/medisphere}"
_m01_doc="$_m01_depot/docs/socle"
check_output "dépôt local : aucune modification non commitée" '^$' git -C "$_m01_depot" status --porcelain
check_cmd "fiche de service docs/socle/forge.md : composants, sauvegarde et RTO" bash -c \
  'for m in git01 runner01 RB-010 RTO; do grep -qF "$m" "$1" || exit 1; done' _ "$_m01_doc/forge.md"
check_cmd "test de restauration de GitLab consigné (tests/restauration.md : git01, durée mesurée)" bash -c \
  'grep -qi "git01" "$1" && grep -Eq "([0-9]+ ?min|[0-9]+:[0-9]{2}|RTO)" "$1"' _ "$_m01_doc/tests/restauration.md"
check_cmd "ADR-0010 présent (docs/socle/adr/)" bash -c 'ls "$1"/ADR-0010*.md >/dev/null 2>&1' _ "$_m01_doc/adr"
check_cmd "runbooks du module RB-010 à RB-013 présents" \
  bash -c 'for r in RB-010 RB-011 RB-012 RB-013; do ls "$1/$r"*.md >/dev/null 2>&1 || exit 1; done' _ "$_m01_doc/runbooks"
check_cmd "post-mortem de l'astreinte INC-2788 présent" \
  bash -c 'ls "$1"/*INC-2788*.md >/dev/null 2>&1' _ "$_m01_doc/post-mortems"
check_cmd "inventaire : git01 (10.10.20.12) et runner01 (10.10.20.15)" bash -c \
  'for m in git01 10.10.20.12 runner01 10.10.20.15; do grep -qF "$m" "$1" || exit 1; done' _ "$_m01_doc/inventaire.md"
check_cmd "matrice des flux : flux de la forge (10.10.20.12, 10.10.20.15, 8007)" bash -c \
  'for m in 10.10.20.12 10.10.20.15 8007; do grep -qF "$m" "$1" || exit 1; done' _ "$_m01_doc/matrice-flux.md"
check_cmd "aucun jeton GitLab dans l'historique du dépôt" bash -c \
  '! git -C "$1" log --all -p 2>/dev/null | grep -Eq "gl(pat|rt|ptt|dt|imp)-[0-9A-Za-z_-]{20,}"' _ "$_m01_depot"
check_cmd "aucune panne M01 encore marquée active" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M01-* >/dev/null 2>&1'
