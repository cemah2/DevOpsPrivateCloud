# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M09-E36 « Panne : un nœud ne rejoint plus le cluster »
#
# Cible : hv03 (dernier nœud entré, M09-E08). Variantes :
#   1. /etc/corosync/authkey de hv03 remplacée (« restauration » d'une vieille sauvegarde), corosync
#      redémarré → hv03 hors de la membre Corosync, seul et sans quorum (HA désarmée avant, sinon
#      hv03 se clôturerait) ; hv01 et hv02 gardent le quorum ;
#   2. horloge de hv03 avancée de 3 h, chrony arrêté et désactivé → Corosync ne voit rien, mais les
#      tickets d'API signés par les autres nœuds sont refusés par hv03 (et Ceph signale l'écart) ;
#      HA désarmée avant : pmxcfs date l'âge des verrous (agents, maître du CRM) avec l'horloge
#      locale, un saut de 3 h les ferait paraître expirés vus de hv03 ;
#   3. certificat présenté par pveproxy sur hv03 (pveproxy-ssl.pem s'il existe, sinon pve-ssl.pem,
#      dans /etc/pve/nodes/hv03/) remplacé par un certificat autosigné d'une autre clé, pveproxy
#      redémarré → la clé ne correspond plus, l'API de hv03 ne répond plus ;
#   4. /etc/hosts de hv03 : son propre nom pointe vers 10.10.10.63, pve-cluster redémarré → hv03
#      annonce une mauvaise adresse dans .members ; les autres nœuds lui parlent dans le vide.
# Sauvegardes : /var/lib/workbook/M09-E36.* sur hv03.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E36_CIBLE=hv03

# _e36_api_ok — depuis hv01, l'API de hv03 répond (appel relayé par pveproxy).
_e36_api_ok() {
  m09_ssh hv01 "timeout 25 pvesh get /nodes/$_E36_CIBLE/version --output-format json" >/dev/null 2>&1
}

# _e36_membre — hv03 est dans la membre Corosync vue de hv01.
_e36_membre() {
  m09_ssh hv01 "corosync-quorumtool -l 2>/dev/null" 2>/dev/null | grep -qw "$_E36_CIBLE"
}

# _e36_ecart — écart d'horloge de hv03 par rapport à adm01, en secondes (valeur absolue).
_e36_ecart() {
  local t
  t="$(m09_ssh "$_E36_CIBLE" "date +%s" 2>/dev/null)" || { echo 0; return; }
  local d=$((t - $(date +%s)))
  echo "${d#-}"
}

# _e36_ip_annoncee — adresse de hv03 dans /etc/pve/.members vue de hv01.
_e36_ip_annoncee() {
  m09_ssh hv01 "cat /etc/pve/.members" 2>/dev/null | jq -r --arg n "$_E36_CIBLE" '.nodelist[$n].ip // empty' 2>/dev/null
}

_e36_effet() {
  case "$1" in
    1) ! _e36_membre ;;
    2) (($(_e36_ecart) > 3600)) ;;
    3) ! m09_ssh "$_E36_CIBLE" "systemctl is-active -q pveproxy && timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8006'" >/dev/null 2>&1 || ! _e36_api_ok ;;
    4) [[ "$(_e36_ip_annoncee)" == 10.10.10.63 ]] || ! _e36_api_ok ;;
  esac
}

_e36_precondition() {
  m09_cluster_sain || return 1
  if ! _e36_api_ok; then
    wb_avert "l'API de $_E36_CIBLE ne répond déjà pas depuis hv01 avant la panne : lab/bin/check 09 36"
    return 1
  fi
}

_mE36_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m09_ha_geler E36 || return 1
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || rc=$?
f=/etc/corosync/authkey
[ -f "$f" ] || exit 10
b="$WB_DIR/$WB_EX.authkey.orig"
[ -f "$b" ] || cp -a "$f" "$b"
head -c 256 /dev/urandom >"$f.neuve" && chmod 400 "$f.neuve" && mv "$f.neuve" "$f"
pose "$f"
systemctl restart corosync
journal "authkey de corosync remplacée, corosync redémarré"
EOF
      ;;
    2)
      m09_ha_geler E36 || return 1
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || rc=$?
systemctl cat chrony >/dev/null 2>&1 || exit 10
: >"$WB_DIR/$WB_EX.horloge"
systemctl disable --now chrony >/dev/null 2>&1
date -s "@$(( $(date +%s) + 10800 ))" >/dev/null
journal "chrony arrêté et désactivé, horloge avancée de 3 h"
EOF
      ;;
    3)
      m09_exec "$_E36_CIBLE" N="$_E36_CIBLE" >/dev/null <<'EOF' || rc=$?
d="/etc/pve/nodes/$N"
f="$d/pveproxy-ssl.pem"
[ -f "$f" ] || f="$d/pve-ssl.pem"
[ -f "$f" ] || exit 10
command -v openssl >/dev/null || exit 10
garder "$f"
printf '%s\n' "$f" >"$WB_DIR/$WB_EX.certificat"
t="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=$N.par1.medisphere.internal" \
  -keyout "$t/cle.pem" -out "$t/cert.pem" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
cat "$t/cert.pem" >"$f"
rm -rf "$t"
pose "$f"
systemctl restart pveproxy >/dev/null 2>&1 || true
journal "certificat $f remplacé par un autosigné d'une autre clé, pveproxy redémarré"
EOF
      ;;
    4)
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || rc=$?
f=/etc/hosts
grep -Eq '^10\.10\.10\.53[[:space:]]' "$f" || exit 10
garder "$f"
sed -i -E 's/^10\.10\.10\.53([[:space:]])/10.10.10.63\1/' "$f"
pose "$f"
systemctl restart pve-cluster
journal "/etc/hosts : 10.10.10.53 remplacé par 10.10.10.63, pve-cluster redémarré"
EOF
      ;;
  esac
  ((rc == 0)) || { _e36_defaire "$n"; return "$rc"; }
  if ! m09_attendre 60 _e36_effet "$n"; then
    _e36_defaire "$n"
    return 10
  fi
}

_e36_defaire() {
  case "$1" in
    1)
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv03 (authkey)"
f=/etc/corosync/authkey
b="$WB_DIR/$WB_EX.authkey.orig"
[ -f "$b" ] || exit 0
if encore_pose "$f"; then
  cp -a "$b" "$f"
  systemctl restart corosync
  journal "annulation : authkey d'origine remise, corosync redémarré"
else
  journal "annulation : authkey modifiée depuis l'injection (réparation), laissée telle quelle"
fi
rm -f "$b" "$WB_DIR/$WB_EX.$(_cle "$f").pose"
EOF
      if [[ -n "$(m09_lire E36 ha-desarmee)" ]]; then m09_attendre 60 m09_quorate "$_E36_CIBLE" || true; fi
      m09_ha_rearmer E36
      ;;
    2)
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv03 (horloge) : systemctl enable --now chrony"
[ -f "$WB_DIR/$WB_EX.horloge" ] || exit 0
if systemctl is-active -q chrony; then
  journal "annulation : chrony déjà actif (réparation)"
else
  systemctl enable --now chrony >/dev/null 2>&1
  journal "annulation : chrony réactivé"
fi
systemctl is-enabled -q chrony || systemctl enable chrony >/dev/null 2>&1 || true
sleep 3
chronyc makestep >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX.horloge"
EOF
      m09_ha_rearmer E36
      ;;
    3)
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv03 (certificat de pveproxy)"
[ -f "$WB_DIR/$WB_EX.certificat" ] || exit 0
f="$(cat "$WB_DIR/$WB_EX.certificat")"
if [ "$(rendre "$f")" = retabli ]; then systemctl restart pveproxy; fi
rm -f "$WB_DIR/$WB_EX.certificat"
EOF
      ;;
    4)
      m09_exec "$_E36_CIBLE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv03 (/etc/hosts)"
[ -f "$WB_DIR/$WB_EX.$(_cle /etc/hosts).pose" ] || exit 0
if [ "$(rendre /etc/hosts)" = retabli ]; then systemctl restart pve-cluster; fi
EOF
      ;;
  esac
}

_e36_injecter() {
  _e36_precondition || return 1
  m09_essayer E36 4 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }
panne_E36_v4() { _e36_injecter 4; }

verifier_E36() {
  _e36_effet "${WB_VAR:-1}"
}

annuler_E36() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e36_defaire "$WB_VAR" ;;
    *) _e36_defaire 4; _e36_defaire 3; _e36_defaire 2; _e36_defaire 1 ;;
  esac
}

resume_E36() {
  echo "hv03 n'apparaît plus correctement dans le cluster : ses VMs ne se gèrent plus depuis les autres nœuds."
}

symptome_E36() {
  local note="Temps cible : 45 min. Contrôle : lab/bin/check 09 36"
  if [[ -n "$(m09_lire E36 ha-desarmee)" ]]; then
    note="Note : l'injection a désarmé la pile HA (mode freeze) ; ce n'est pas la cause. $note"
  fi
  wb_symptome "Ticket INC-3642 — De : Karim Benali" \
    "Après une intervention de nuit sur hv03, ce nœud n'est plus « dans » le cluster comme avant :" \
    "depuis l'interface de hv01, hv03 est marqué en rouge ou avec un point d'interrogation, et ses" \
    "VMs ne se consultent plus (erreurs 401, 595 ou délai dépassé, selon l'écran). Je n'ai pas le" \
    "détail de ce qui a été fait cette nuit, le prestataire est injoignable avant 10 h." \
    "Interdiction de retirer hv03 du cluster (pvecm delnode) pour « repartir propre »." \
    "" \
    "$note"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E36 4 "$@"; }
fi
