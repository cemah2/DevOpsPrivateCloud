# shellcheck shell=bash
#
# check-E16.sh — M01-E16 : Gitleaks sur adm01 et configuration .gitleaks.toml de plateforme/medisphere
# Lancé depuis adm01. Lecture seule (binaire local, copies temporaires, clone $WB_DEPOT, API GitLab).
# Les « secrets » utilisés pour tester les règles sont factices et générés ici.

title "M01-E16 — Gitleaks : arrêter un secret avant qu'il parte"
require_cmd curl jq git

_m01_depot="${WB_DEPOT:-$HOME/medisphere}"

check_output "Gitleaks 8.30.x installé sur adm01" '^v?8\.30\.' gitleaks version
check_output "le binaire gitleaks vient de /usr/local/bin (pas du paquet Debian 8.16)" '^/usr/local/bin/gitleaks$' \
  command -v gitleaks

_m01_cfg="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/.gitleaks.toml/raw?ref=main" 2>/dev/null)" || _m01_cfg=""
check_cmd ".gitleaks.toml est sur main de plateforme/medisphere" test -n "$_m01_cfg"
check_cmd ".gitleaks.toml étend les règles par défaut (useDefault)" grep -Eq '^[[:space:]]*useDefault[[:space:]]*=[[:space:]]*true' <<<"$_m01_cfg"

_m01_tmp="$(mktemp -d)"
printf '%s\n' "$_m01_cfg" > "$_m01_tmp/gitleaks.toml"
# Jeton Proxmox factice, sous la forme d'un en-tête HTTP (non détecté par les règles par défaut)
_m01_uuid="$(printf '%08x-%04x-4%03x-a%03x-%012x' $((RANDOM*RANDOM)) $RANDOM $((RANDOM%4096)) $((RANDOM%4096)) $((RANDOM*RANDOM*RANDOM)))"
_m01_detecte() {
  printf 'curl -H "Authorization: PVEAPIToken=wb-automation@pve!lab=%s" https://pve01:8006/api2/json/version\n' "$_m01_uuid" \
    | gitleaks stdin --no-banner --redact --log-level error --config "$_m01_tmp/gitleaks.toml" >/dev/null 2>&1
  [[ $? -eq 1 ]]
}
check_cmd "ta configuration détecte un secret de jeton d'API Proxmox (en-tête PVEAPIToken)" _m01_detecte
_m01_detecte_env() {
  printf 'PVE_TOKEN_SECRET=%s\n' "$_m01_uuid" \
    | gitleaks stdin --no-banner --redact --log-level error --config "$_m01_tmp/gitleaks.toml" >/dev/null 2>&1
  [[ $? -eq 1 ]]
}
check_cmd "ta configuration détecte un secret de jeton d'API Proxmox (variable PVE_TOKEN_SECRET)" _m01_detecte_env

_m01_histoire_propre() {
  git -C "$_m01_depot" rev-parse -q --verify origin/main >/dev/null || return 1
  gitleaks git --no-banner --redact --log-level error --config "$_m01_tmp/gitleaks.toml" \
    --log-opts="origin/main" "$_m01_depot" >/dev/null 2>&1
}
check_cmd "l'historique complet de main (dernier fetch) ne contient aucun secret détecté" _m01_histoire_propre

_m01_pc="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/.pre-commit-config.yaml/raw?ref=main" 2>/dev/null)" || _m01_pc=""
check_cmd "le hook gitleaks est actif dans .pre-commit-config.yaml (M01-E15)" grep -Eq 'id:[[:space:]]*gitleaks' <<<"$_m01_pc"

rm -rf "$_m01_tmp"
