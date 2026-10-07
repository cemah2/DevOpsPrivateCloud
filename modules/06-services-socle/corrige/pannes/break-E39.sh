# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M06-E39 « Panne : NetBox en erreur »
#
# Variantes (toutes sur nbx01) :
#   1. PostgreSQL : pg_hba.conf commence par des lignes « reject » pour la base de NetBox
#      (« durcissement » d'InfoGér) → erreur 500, OperationalError dans les journaux ;
#   2. Valkey : port passé de 6379 à 6380 (« alignement avec le modèle de configuration ») → erreur 500,
#      ConnectionError vers le cache ;
#   3. configuration.py : ALLOWED_HOSTS réduit au nom court → 400 Bad Request sur le FQDN ;
#   4. gunicorn.py : bind sur 127.0.0.1:8002 au lieu de 8001 → 502 Bad Gateway de nginx.
# Les modifications sont des remplacements de texte mémorisés (subst) : l'annulation ne remet que ce
# qui porte encore la marque de la panne. Sauvegardes : /var/lib/workbook/M06-E39.* sur nbx01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

_E39_FQDN="nbx01.$_M06_ZONE"

# _e39_code — code HTTP de la page de connexion de NetBox (TLS non vérifié : ce n'est pas le sujet,
# et M06-E37 peut casser la chaîne en même temps pendant l'astreinte).
_e39_code() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$_E39_FQDN:443:${_M06_IP[nbx01]}" \
    "https://$_E39_FQDN/login/" 2>/dev/null || true
}

_e39_precondition() {
  if [[ "$(_e39_code)" != 200 ]]; then
    wb_avert "NetBox ne répond déjà pas 200 sur /login/ avant la panne : lab/bin/check 06 39"
    return 1
  fi
  m06_wb_exec nbx01 >/dev/null <<'EOF' || { wb_avert "nbx01 : installation NetBox non standard (/opt/netbox, services netbox et postgresql)"; return 1; }
[ -f /opt/netbox/netbox/netbox/configuration.py ] && systemctl is-active -q netbox && systemctl is-active -q postgresql
EOF
}

_mE39_une() {
  local n="$1" rc=0
  m06_wb_exec nbx01 N="$n" >/dev/null <<'EOF' || rc=$?
conf=/opt/netbox/netbox/netbox/configuration.py
case "$N" in
  1)
    f="$(ls /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | tail -n 1)"
    [ -n "$f" ] || exit 10
    base="$(python3 - "$conf" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"DATABASE\s*=\s*\{.*?['\"]NAME['\"]\s*:\s*['\"]([^'\"]+)['\"]", t, re.S)
print(m.group(1) if m else "netbox")
PY
)"
    bloc="# Durcissement InfoGér (audit 2026) : accès direct à la base $base interdit
local   $base   all   reject
host    $base   all   127.0.0.1/32   reject
host    $base   all   ::1/128   reject
"
    subst "$f" '\A' "$bloc" || exit $?
    systemctl reload postgresql
    journal "$f : lignes reject en tête pour la base $base"
    ;;
  2)
    f=/etc/valkey/valkey.conf
    systemctl is-active -q valkey-server || exit 10
    subst "$f" '^port 6379[ \t]*$' 'port 6380' || exit $?
    systemctl restart valkey-server
    journal "$f : port 6380"
    ;;
  3)
    subst "$conf" '^ALLOWED_HOSTS[ \t]*=[ \t]*\[[^\n\]]*\][ \t]*(#.*)?$' "ALLOWED_HOSTS = ['nbx01']  # INC-3345 : nom court seulement, demandé par l'audit" || exit $?
    journal "$conf : ALLOWED_HOSTS réduit à nbx01"
    ;;
  4)
    f=/opt/netbox/gunicorn.py
    subst "$f" '^(bind[ \t]*=[ \t]*["'"'"'][^"'"'"':]+:)8001(["'"'"'])' '\g<1>8002\2' || exit $?
    journal "$f : gunicorn sur le port 8002"
    ;;
esac
systemctl restart netbox netbox-rq >/dev/null 2>&1 || true
EOF
  ((rc == 0)) || { _e39_defaire; return "$rc"; }
  sleep 5
  if [[ "$(_e39_code)" == 200 ]]; then
    _e39_defaire
    return 10
  fi
}

_e39_defaire() {
  m06_wb_exec nbx01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur nbx01"
[ -f "$WB_DIR/$WB_EX.subst" ] || exit 0
r="$(defaire_subst)"
[ -n "$r" ] || exit 0
case "$r" in *pg_hba.conf*) systemctl reload postgresql ;; esac
case "$r" in *valkey.conf*) systemctl restart valkey-server ;; esac
systemctl restart netbox netbox-rq >/dev/null 2>&1 || true
EOF
}

_e39_injecter() {
  _e39_precondition || return 1
  m06_essayer E39 4 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

verifier_E39() {
  [[ "$(_e39_code)" != 200 ]]
}

annuler_E39() {
  _e39_defaire
}

resume_E39() {
  echo "NetBox renvoie une page d'erreur (navigateur, API) : la synchronisation et l'inventaire échouent."
}

symptome_E39() {
  wb_symptome "Ticket INC-3345 — De : Claire Morel" \
    "NetBox ne répond plus correctement : la page d'accueil affiche une erreur, l'API aussi." \
    "La synchronisation Proxmox → NetBox de cette nuit a échoué, et la MR de Karim attend un" \
    "plan OpenTofu qui interroge NetBox. InfoGér a « fait une passe d'audit » sur la VM hier." \
    "Rétablis le service, et dis-moi ce qui a été touché." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 06 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E39 4 "$@"; }
fi
