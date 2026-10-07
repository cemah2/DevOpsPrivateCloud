# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M06-E42 « Panne : les baux n'apparaissent plus dans le DNS »
#
# Préalable : DDNS de M06-E17 (kea-dhcp-ddns → PowerDNS en RFC 2136, clé TSIG ddns-kea). Variantes :
#   1. kea-dhcp-ddns (dns01) : secret de la clé TSIG modifié côté Kea seulement (« rotation » faite
#      d'un seul côté) → PowerDNS refuse les mises à jour (signature invalide) ;
#   2. PowerDNS Authoritative (dns01) : dnsupdate=no (« durcissement ») → mises à jour refusées ;
#   3. PowerDNS : métadonnée TSIG-ALLOW-DNSUPDATE de la zone pointée vers une clé « ddns-kea-2026 »
#      qui n'existe pas (rotation préparée, jamais terminée) → mises à jour refusées ;
#   4. kea-dhcp4 (dns01, et dns02 s'il porte Kea) : dhcp-ddns.enable-updates à false → Kea ne
#      transmet plus rien à kea-dhcp-ddns ; tout le reste est sain.
# Constat (variantes 1 à 3) : une mise à jour RFC 2136 signée avec la clé que kea-dhcp-ddns
# utilise (nsupdate, enregistrement TXT wb-sonde-m06-e42, retiré aussitôt) est refusée.
# Sauvegardes : /var/lib/workbook/M06-E42.* sur dns01 (et dns02) ; annulation sans écraser une
# réparation.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

# Aide distante supplémentaire : lecture de la configuration de kea-dhcp-ddns (JSON avec
# commentaires) et essai de mise à jour signée comme le ferait kea-dhcp-ddns.
read -r -d '' _E42_AIDE <<'AIDE' || true
d2_conf=/etc/kea/kea-dhcp-ddns.conf
# d2_info — « nom algorithme secret serveur port » de la première clé et du premier serveur DNS
# du domaine direct (forward-ddns) de kea-dhcp-ddns.
d2_info() {
  python3 - "$d2_conf" <<'PY'
import json, re, sys
def sans_commentaires(t):
    out, i, n, chaine = [], 0, len(t), False
    while i < n:
        c = t[i]
        if chaine:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(t[i + 1]); i += 2; continue
            if c == '"':
                chaine = False
            i += 1; continue
        if c == '"':
            chaine = True; out.append(c); i += 1; continue
        if t.startswith("//", i) or c == "#":
            while i < n and t[i] != "\n": i += 1
            continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return "".join(out)
c = json.loads(sans_commentaires(open(sys.argv[1], encoding="utf-8").read()))["DhcpDdns"]
k = (c.get("tsig-keys") or [{}])[0]
secret = k.get("secret", "")
if not secret and k.get("secret-file"):
    secret = open(k["secret-file"], encoding="utf-8").read().strip()
dom = (c.get("forward-ddns", {}).get("ddns-domains") or [{}])[0]
srv = (dom.get("dns-servers") or [{}])[0]
print(k.get("name", ""), k.get("algorithm", "").lower(), secret, srv.get("ip-address", ""), srv.get("port", 53))
PY
}
# essai_maj ZONE — 0 si une mise à jour signée avec la clé de kea-dhcp-ddns est acceptée.
essai_maj() {
  local nom alg sec ip port
  read -r nom alg sec ip port <<<"$(d2_info)"
  [ -n "$nom" ] && [ -n "$sec" ] && [ -n "$ip" ] || return 2
  printf 'server %s %s\nzone %s\nupdate add wb-sonde-m06-e42.%s 60 TXT "sonde du workbook"\nsend\nupdate delete wb-sonde-m06-e42.%s TXT\nsend\n' \
    "$ip" "$port" "$1" "$1" "$1" | nsupdate -t 5 -y "$alg:$nom:$sec" >/dev/null 2>&1
}
AIDE

_e42_exec() {
  { printf '%s\n' "$_E42_AIDE"; cat; } | m06_wb_exec "$@"
}

_e42_precondition() {
  _e42_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || { wb_avert "dns01 : kea-dhcp-ddns inactif, configuration illisible ou mise à jour signée refusée avant la panne : lab/bin/check 06 42"; return 1; }
command -v nsupdate >/dev/null || exit 1
s="$(service_d2)" && systemctl is-active -q "$s" || exit 1
essai_maj "$ZONE"
EOF
}

_mE42_une() {
  local n="$1" rc=0 h
  case "$n" in
    1 | 2 | 3)
      _e42_exec dns01 N="$n" ZONE="$_M06_ZONE" >/dev/null <<'EOF' || rc=$?
case "$N" in
  1)
    read -r nom alg sec ip port <<<"$(d2_info)"
    [ -n "$sec" ] || exit 10
    # Même nombre d'octets, base64 valide : seul le contenu change.
    nb="$(printf '%s' "$sec" | base64 -d 2>/dev/null | wc -c)"
    [ "$nb" -gt 0 ] || exit 10
    nouveau="$(head -c "$nb" /dev/urandom | base64 -w0)"
    f="$d2_conf"
    if ! grep -qF "\"$sec\"" "$f"; then
      f="$(sed -nE 's/.*"secret-file"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$d2_conf" | head -n 1)"
      [ -n "$f" ] && [ -f "$f" ] || exit 10
    fi
    subst "$f" "$(printf '%s' "$sec" | sed 's/[][\.*^$+?(){}|]/\\&/g')" "$nouveau" || exit $?
    systemctl restart "$(service_d2)"
    journal "kea-dhcp-ddns : secret TSIG de $nom modifié ($f)"
    ;;
  2)
    f="$(pdns_fichier_de dnsupdate)"
    [ -n "$f" ] || exit 10
    subst "$f" '^([ \t]*dnsupdate[ \t]*=[ \t]*)yes[ \t]*$' '\1no' || exit $?
    systemctl restart pdns
    journal "PowerDNS : dnsupdate=no ($f)"
    ;;
  3)
    v="$(pdnsutil metadata get "$ZONE" TSIG-ALLOW-DNSUPDATE 2>/dev/null | sed -nE 's/^TSIG-ALLOW-DNSUPDATE = (.*)$/\1/p')"
    printf '%s\n' "$v" >"$WB_DIR/M06-E42.tsig-allow"
    pdnsutil metadata set "$ZONE" TSIG-ALLOW-DNSUPDATE ddns-kea-2026 >/dev/null || exit 1
    systemctl restart pdns
    journal "zone $ZONE : TSIG-ALLOW-DNSUPDATE = ddns-kea-2026 (avant : ${v:-vide})"
    ;;
esac
sleep 2
if essai_maj "$ZONE"; then exit 20; fi
EOF
      ;;
    4)
      for h in dns01 dns02; do
        m06_wb_exec "$h" >/dev/null 2>&1 <<'EOF' || rc=$?
s="$(service_kea4)" && [ -f /etc/kea/kea-dhcp4.conf ] || exit 3
subst /etc/kea/kea-dhcp4.conf '("enable-updates"[ \t]*:[ \t]*)true' '\1false' || exit $?
systemctl restart "$s" || true
journal "kea-dhcp4 : dhcp-ddns.enable-updates à false"
EOF
        # dns01 doit porter la variante ; dns02 (Kea de secours) est facultatif.
        if [[ "$h" == dns01 ]] && ((rc != 0)); then rc=10; break; fi
        rc=0
      done
      ;;
  esac
  if ((rc == 20)); then
    _e42_defaire "$n"
    return 10
  fi
  ((rc == 0)) || { _e42_defaire "$n"; return "$rc"; }
}

_e42_defaire() {
  local h
  case "$1" in
    1 | 2 | 3)
      m06_wb_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
if [ -f "$WB_DIR/$WB_EX.subst" ]; then
  r="$(defaire_subst)"
  case "$r" in
    "") ;;
    */etc/powerdns/*) systemctl restart pdns ;;
    *) systemctl restart "$(service_d2)" || true ;;
  esac
fi
f="$WB_DIR/M06-E42.tsig-allow"
if [ -f "$f" ]; then
  if pdnsutil metadata get "$ZONE" TSIG-ALLOW-DNSUPDATE 2>/dev/null | grep -q 'ddns-kea-2026'; then
    v="$(cat "$f")"
    # shellcheck disable=SC2086
    pdnsutil metadata set "$ZONE" TSIG-ALLOW-DNSUPDATE $v >/dev/null
    systemctl restart pdns
    journal "annulation : TSIG-ALLOW-DNSUPDATE rétabli (${v:-vide})"
  else
    journal "annulation : TSIG-ALLOW-DNSUPDATE déjà modifié (réparation), laissé tel quel"
  fi
  rm -f "$f"
fi
EOF
      ;;
    4)
      for h in dns01 dns02; do
        m06_wb_exec "$h" >/dev/null 2>&1 <<'EOF' || true
[ -f "$WB_DIR/$WB_EX.subst" ] || exit 0
if [ -n "$(defaire_subst)" ]; then systemctl restart "$(service_kea4)" || true; fi
EOF
      done
      ;;
  esac
}

_e42_injecter() {
  _e42_precondition || return 1
  m06_essayer E42 4 "$1"
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }
panne_E42_v4() { _e42_injecter 4; }

verifier_E42() {
  case "${WB_VAR:-0}" in
    1 | 2 | 3)
      _e42_exec dns01 ZONE="$_M06_ZONE" >/dev/null 2>&1 <<'EOF'
! essai_maj "$ZONE"
EOF
      ;;
    4)
      # Kea ne transmet plus rien : constaté sur la configuration chargée (fichier modifié et service
      # redémarré après la modification, ou arrêté).
      m06_wb_exec dns01 >/dev/null 2>&1 <<'EOF'
grep -Eq '"enable-updates"[[:space:]]*:[[:space:]]*false' /etc/kea/kea-dhcp4.conf || exit 1
s="$(service_kea4)" || exit 1
systemctl is-active -q "$s" || exit 0
debut="$(date -d "$(systemctl show "$s" -p ActiveEnterTimestamp --value)" +%s)"
[ "$debut" -ge "$(stat -c %Y /etc/kea/kea-dhcp4.conf)" ]
EOF
      ;;
    *) return 1 ;;
  esac
}

annuler_E42() {
  case "${WB_VAR:-}" in
    [1-4]) _e42_defaire "$WB_VAR" ;;
    *) _e42_defaire 4; _e42_defaire 1 ;;
  esac
}

resume_E42() {
  echo "Les nouvelles VMs du VLAN 99 ont une adresse, mais leur nom sbxNN n'apparaît plus dans le DNS."
}

symptome_E42() {
  wb_symptome "Ticket INC-3348 — De : Julien Petit" \
    "Mes VMs de test du VLAN sandbox obtiennent bien une adresse, mais depuis hier leur nom" \
    "(sbxNN.par1.medisphere.internal) ne se résout plus : NXDOMAIN, et rien non plus en inverse." \
    "Les VMs plus anciennes ont toujours leur nom. Mes tests d'intégration s'appuient dessus." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 06 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E42 4 "$@"; }
fi
