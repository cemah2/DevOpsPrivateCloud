# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E24.sh — M24-E24 : Keycloak en haute disponibilité : essai à deux nœuds
# À lancer depuis adm01, APRÈS le retour à un nœud. Lecture seule : rôle keycloak et ADR-0241 sur main
# (GitLab), absence d'idp02 (Proxmox, DNS, NetBox, HAProxy), état mononœud d'idp01 (keycloak.conf,
# écoute et pg_hba.conf de PostgreSQL, en sudo -n).

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E24 — Keycloak en haute disponibilité : essai à deux nœuds"
require_cmd jq curl dig

# --- 1. Le rôle et la décision ---------------------------------------------------------------------
_m24p_e24_gabarit="$(_m24d_contenu_main plateforme/ansible roles/keycloak/templates/keycloak.conf.j2)"
check_cmd "Rôle keycloak (main) : configuration de grappe (cache=ispn, pile jdbc-ping) sous keycloak_grappe" \
  _m24d_contient "$_m24p_e24_gabarit" 'cache-stack=jdbc-ping'
check_cmd "Rôle keycloak (main) : base distante en TLS (db-url-properties) et retour à cache=local" \
  _m24p_tous "$_m24p_e24_gabarit" 'db-url-properties' '^cache=local$'
_m24p_e24_adr="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/adr" | grep -Ei 'ADR-0241' | head -n 1 || true)"
_m24p_e24_adr_c=""
[[ -n "$_m24p_e24_adr" ]] && _m24p_e24_adr_c="$(_m24p_doc "$_m24p_e24_adr")"
check_cmd "ADR-0241 (haute disponibilité de Keycloak) sur main de plateforme/medisphere" test -n "$_m24p_e24_adr_c"
check_cmd "ADR-0241 : une section Décision et une section Mesures" _m24p_tous "$_m24p_e24_adr_c" '^#+ .*d[ée]cision' '^#+ .*mesure'
check_cmd "ADR-0241 : rempli (aucune valeur <N> ou <AAAA-MM-JJ> laissée)" _m24p_sans_gabarit "$_m24p_e24_adr_c"
check_output "ADR-0241 : au moins trois durées mesurées (en secondes)" '^([3-9]|[1-9][0-9]+)$' \
  _m24p_nb_durees "$_m24p_e24_adr_c"

# --- 2. idp02 a disparu ------------------------------------------------------------------------------
check_cmd "Proxmox : la VM 2241 (idp02) n'existe plus" _m24p_vm_absente 2241
check_cmd "DNS : idp02.par1.medisphere.internal ne résout plus" _m24p_vide "$(dig +short +time="$WB_TIMEOUT" idp02.par1.medisphere.internal A 2>/dev/null || true)"
check_cmd "NetBox : plus de VM idp02" _m24d_json \
  "$(netbox_api "virtualization/virtual-machines/?name=idp02" 2>/dev/null || true)" '.count == 0'
for _m24p_e24_lb in lb01 lb02; do
  _m24p_e24_be="$(_m24d_ssh "$_m24p_e24_lb" "sudo -n sed -n '/^backend be_sso/,/^\(backend\|frontend\|listen\) /p' /etc/haproxy/haproxy.cfg")"
  check_cmd "$_m24p_e24_lb : be_sso ne sert plus que idp01" _m24p_aucun 'server +idp02' "$_m24p_e24_be"
done

# --- 3. idp01 est revenu à un nœud ----------------------------------------------------------------------
check_ssh_output "idp01 : cache local (keycloak_grappe à false)" "$_M24D_IDP" '^cache=local$' \
  "sudo -n grep -E '^cache=' /opt/keycloak/conf/keycloak.conf"
check_ssh_output "idp01 : PostgreSQL n'écoute plus que sur la boucle locale" "$_M24D_IDP" '^local$' \
  "if ss -Hltn 'sport = :5432' | awk '{print \$4}' | grep -Evq '^(127\\.0\\.0\\.1|\\[::1\\]):5432\$'; then echo exposé; else echo local; fi"
check_ssh_output "idp01 : plus aucune ligne d'accès distant à la base dans pg_hba.conf" "$_M24D_IDP" '^0$' \
  "sudo -n grep -Ec '^[[:space:]]*host(ssl)?[[:space:]]+keycloak[[:space:]]' /etc/postgresql/17/main/pg_hba.conf || true"
check_http "idp01 : Keycloak prêt (/health/ready)" "https://idp01.par1.medisphere.internal:9000/health/ready" 200 --cacert "$_M24D_RACINE"
