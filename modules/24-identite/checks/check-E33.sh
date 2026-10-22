# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E33.sh — M24-E33 : Monter de version Keycloak et FreeIPA
# À lancer depuis adm01. Lecture seule : version et unité de Keycloak sur idp01, migrations de la base
# (SELECT), santé ; paquets en attente et services de FreeIPA sur ipa01 (dnf en cache seulement,
# ipactl status, en sudo -n) ; RB-245 sur main ; absence d'idp-resto.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E33 — Monter de version Keycloak et FreeIPA"
require_cmd jq curl

check_ssh_output "idp01 : /opt/keycloak pointe sur Keycloak 26.8.1 ou une corrective ultérieure de la 26.8" "$_M24D_IDP" \
  '^/opt/keycloak-26\.8\.([1-9]|[1-9][0-9])$' "readlink -f /opt/keycloak"
check_ssh "idp01 : keycloak.service actif, en démarrage optimisé" "$_M24D_IDP" \
  "systemctl is-active --quiet keycloak.service && systemctl show -p ExecStart --value keycloak.service | grep -q 'start --optimized'"
check_cmd "idp01 : la base porte les migrations de la 26.8.0 (databasechangelog)" \
  _m24p_compare "$(_m24p_sql "SELECT count(*) FROM databasechangelog WHERE filename LIKE '%26.8.0%'")" '>' 0
check_http "idp01 : Keycloak prêt après la montée (/health/ready)" "https://idp01.par1.medisphere.internal:9000/health/ready" 200 --cacert "$_M24D_RACINE"
check_cmd "Découverte du royaume medisphere servie, émetteur inchangé" _m24d_json \
  "$(_m24d_public /realms/medisphere/.well-known/openid-configuration)" '.issuer == "https://sso.par1.medisphere.internal/realms/medisphere"'

# FreeIPA : dnf en mode cache (-C) : aucune écriture, résultat selon le dernier rafraîchissement des
# métadonnées (minuterie dnf-makecache). Code 100 = mises à jour disponibles, 0 = aucune.
check_ssh_output "ipa01 : aucune mise à jour en attente pour ipa-server (selon le cache de dnf)" "$_M24D_IPA" '^rc=0$' \
  "sudo -n dnf -C -q check-update ipa-server >/dev/null 2>&1; echo rc=\$?"
check_ssh_output "ipa01 : tous les services de FreeIPA en marche (ipactl status)" "$_M24D_IPA" '^ok$' \
  "s=\$(sudo -n ipactl status 2>&1); if grep -q RUNNING <<<\"\$s\" && ! grep -Eq 'STOPPED|not running' <<<\"\$s\"; then echo ok; fi"

_m24p_e33_rb="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -Ei 'RB-245' | head -n 1 || true)"
_m24p_e33_c=""
[[ -n "$_m24p_e33_rb" ]] && _m24p_e33_c="$(_m24p_doc "$_m24p_e33_rb")"
check_cmd "RB-245 sur main : retour arrière par restauration et durée mesurée" _m24p_tous "$_m24p_e33_c" \
  'retour arri[èe]re' 'restaur' '[0-9]+ ?(s|min)\b'
check_cmd "RB-245 : rempli (aucune valeur <N> ou <AAAA-MM-JJ> laissée)" _m24p_sans_gabarit "$_m24p_e33_c"
check_cmd "Proxmox : la copie d'essai 2242 (idp-resto) n'existe plus" _m24p_vm_absente 2242
