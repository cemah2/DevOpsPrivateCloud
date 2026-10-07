# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M06-E35 « Panne : un nom interne ne se résout plus »
#
# Variantes (toutes sur dns01) :
#   1. récurseur : les relais (forwarders) des zones internes pointent vers le port 5301 au lieu de
#      5300 (« faute de frappe » d'un changement) → SERVFAIL sur les noms internes ;
#   2. récurseur : les zones relayées medisphere.internal et par1.medisphere.internal sont écrites
#      « …medisphere.interne » (les deux : la zone parente, relayée elle aussi, servirait sinon par1)
#      → les noms de par1 partent vers la racine d'Internet → NXDOMAIN de la racine (ou SERVFAIL si
#      l'ancre positive de par1, M06-E26, ne trouve aucune clé) ;
#   3. autoritaire : l'enregistrement A de git01 supprimé (« nettoyage » par pdnsutil, série incrémentée,
#      NOTIFY vers dns02), puis interrogé une fois → NXDOMAIN partout, et réponse négative en cache
#      dans le récurseur (même quand la source est réparée) ;
#   4. autoritaire : base du backend (gsqlite3 ou LMDB) repassée en root:root 600 sur dns01 ET dns02
#      (« script d'audit des droits » passé sur les deux serveurs DNS) → aucun serveur faisant autorité
#      ne sert plus rien (les récurseurs relaient vers les deux : une seule base cassée serait masquée).
# Sauvegardes : /var/lib/workbook/M06-E35.* sur dns01 (texte d'origine de recursor.yml, RRset de git01,
# propriétaire et droits de la base) et sur dns02 (droits de la base, variante 4). Rien n'est rétabli
# qui a déjà été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

_e35_git01_ok() { m06_resout_bien "git01.$_M06_ZONE" "${_M06_IP[git01]}"; }

_e35_precondition() {
  if ! _e35_git01_ok; then
    wb_avert "dns01 ne résout déjà pas git01.$_M06_ZONE avant la panne : lab/bin/check 06 35"
    return 1
  fi
  if [[ "$(m06_dig_statut 10.10.20.10 deb.debian.org A)" != NOERROR ]]; then
    wb_avert "dns01 ne résout pas les noms d'Internet avant la panne : lab/bin/check 06 35"
    return 1
  fi
  m06_wb_exec dns01 >/dev/null <<'EOF' || { wb_avert "dns01 : PowerDNS Recursor (recursor.yml) ou Authoritative introuvable"; return 1; }
[ -f /etc/powerdns/recursor.yml ] && systemctl is-active -q pdns-recursor && systemctl is-active -q pdns \
  && [ -x /usr/bin/pdnsutil ] && command -v dig >/dev/null
EOF
}

_mE35_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m06_wb_exec dns01 >/dev/null <<'EOF' || rc=$?
rx='(127\.0\.0\.1|10\.10\.20\.1[06]):5300\b'
subst /etc/powerdns/recursor.yml "$rx" '\1:5301' || exit $?
# Toutes les occurrences : un relais restant vers 5300 (ou vers dns02) masquerait la panne.
while subst /etc/powerdns/recursor.yml "$rx" '\1:5301'; do :; done
systemctl restart pdns-recursor
journal "recursor.yml : relais des zones internes vers le port 5301"
EOF
      ;;
    2)
      m06_wb_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || rc=$?
rx='(zone:[ \t]*["'"'"']?)((?:par1\.)?medisphere\.)internal(?=\.?["'"'"']?([ \t]*$|[ \t]*[,}#]))'
subst /etc/powerdns/recursor.yml "$rx" '\1\2interne' || exit $?
# medisphere.internal ET par1.medisphere.internal : la zone parente relayée servirait encore par1.
while subst /etc/powerdns/recursor.yml "$rx" '\1\2interne'; do :; done
systemctl restart pdns-recursor
journal "recursor.yml : zones relayées renommées (medisphere.interne, par1.medisphere.interne)"
EOF
      ;;
    3)
      m06_wb_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || rc=$?
nom="git01.$ZONE"
f="$WB_DIR/M06-E35.rrset"
dig +noall +answer @127.0.0.1 -p 5300 "$nom" A | awk '$4 == "A" { print $2, $5 }' >"$f.tmp"
[ -s "$f.tmp" ] || { rm -f "$f.tmp"; exit 10; }
[ -f "$f" ] || mv "$f.tmp" "$f"
rm -f "$f.tmp"
pdnsutil rrset delete "$ZONE" "$nom" A >/dev/null 2>&1 || exit 1
pdnsutil zone rectify "$ZONE" >/dev/null 2>&1 || true
pdnsutil zone increase-serial "$ZONE" >/dev/null 2>&1 || true
pdns_control notify "$ZONE" >/dev/null 2>&1 || true
pdns_control purge "$nom" >/dev/null 2>&1 || true
rec_vider "$nom"
dig +time=2 +tries=1 @127.0.0.1 "$nom" A >/dev/null 2>&1 || true
journal "RRset A de $nom supprimé ($(tr '\n' ' ' <"$f")), série incrémentée, NOTIFY envoyé"
EOF
      ;;
    4)
      local h4
      for h4 in dns01 dns02; do
        # dns02 facultatif (avant M06-E24) ; dns01 obligatoire.
        if [[ "$h4" == dns02 ]] && ! m06_existe dns02; then continue; fi
        m06_wb_exec "$h4" >/dev/null <<'EOF' || rc=$?
b="$(pdns_reglage launch)"
case "$b" in
  *gsqlite3*) base="$(pdns_reglage gsqlite3-database)" ;;
  *lmdb*) base="$(pdns_reglage lmdb-filename)" ;;
  *) exit 10 ;;
esac
[ -n "$base" ] && [ -f "$base" ] || exit 10
[ -f "$WB_DIR/M06-E35.base" ] || printf '%s\t%s\n' "$base" "$(stat -c '%U:%G %a' "$base")" >"$WB_DIR/M06-E35.base"
chown root:root "$base" && chmod 600 "$base"
systemctl restart pdns >/dev/null 2>&1 || true
journal "base $base passée en root:root 600, pdns redémarré"
EOF
        ((rc == 0)) || break
      done
      # Sans vidage, le cache des récurseurs masquerait la panne jusqu'à expiration des TTL.
      ((rc != 0)) || m06_vider_caches_rec "$_M06_ZONE"
      ;;
  esac
  ((rc == 0)) || return "$rc"
  sleep 3
  if _e35_git01_ok; then
    # Sans effet sur ce lab (dns02 relaie, zone générée autrement…) : défaire et passer à la suivante.
    _e35_defaire "$n"
    return 10
  fi
}

# _e35_defaire N — retire la variante N (annulation, ou variante sans effet).
_e35_defaire() {
  case "$1" in
    1 | 2)
      m06_wb_exec dns01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01 (recursor.yml)"
if [ -n "$(defaire_subst)" ]; then systemctl restart pdns-recursor; fi
EOF
      ;;
    3)
      m06_wb_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01 (enregistrement de git01)"
nom="git01.$ZONE"
f="$WB_DIR/M06-E35.rrset"
[ -s "$f" ] || exit 0
if [ -n "$(dig +short @127.0.0.1 -p 5300 "$nom" A)" ]; then
  journal "annulation : $nom de nouveau présent (réparation), laissé tel quel"
else
  ttl="$(head -n 1 "$f" | cut -d' ' -f1)"
  # shellcheck disable=SC2046
  pdnsutil rrset replace "$ZONE" "$nom" A "$ttl" $(cut -d' ' -f2 "$f") >/dev/null
  pdnsutil zone rectify "$ZONE" >/dev/null 2>&1 || true
  pdnsutil zone increase-serial "$ZONE" >/dev/null 2>&1 || true
  pdns_control notify "$ZONE" >/dev/null 2>&1 || true
  pdns_control purge "$nom" >/dev/null 2>&1 || true
  journal "annulation : RRset A de $nom recréé"
fi
rm -f "$f"
EOF
      m06_vider_caches_rec "git01.$_M06_ZONE"
      ;;
    4)
      local h4
      for h4 in dns01 dns02; do
        if [[ "$h4" == dns02 ]] && ! m06_existe dns02; then continue; fi
        m06_wb_exec "$h4" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h4 (base PowerDNS)"
f="$WB_DIR/M06-E35.base"
[ -f "$f" ] || exit 0
IFS="$(printf '\t')" read -r base droits <"$f"
if [ "$(stat -c '%U:%G %a' "$base" 2>/dev/null)" = "root:root 600" ]; then
  chown "${droits% *}" "$base" && chmod "${droits#* }" "$base"
  systemctl restart pdns
  journal "annulation : $base rendu à ${droits}"
else
  journal "annulation : $base déjà corrigé (réparation), laissé tel quel"
  systemctl is-active -q pdns || systemctl restart pdns || true
fi
rm -f "$f"
EOF
      done
      ;;
  esac
}

_e35_injecter() {
  _e35_precondition || return 1
  m06_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

verifier_E35() {
  ! _e35_git01_ok
}

annuler_E35() {
  # Chaque élément ne bouge que s'il porte encore la marque de la panne : on peut tout tenter
  # (les variantes 1 et 2 partagent le même mécanisme de retour : defaire_subst).
  case "${WB_VAR:-}" in
    1 | 2) _e35_defaire 1 ;;
    3 | 4) _e35_defaire "$WB_VAR" ;;
    *) _e35_defaire 4; _e35_defaire 3; _e35_defaire 1 ;;
  esac
}

resume_E35() {
  echo "La sonde DNS est rouge : git01.par1.medisphere.internal ne se résout plus sur dns01 (Internet se résout)."
}

symptome_E35() {
  wb_symptome "Ticket INC-3341 — De : Nadia Roussel" \
    "Depuis 6 h 50, la sonde DNS de supervision (depuis adm01, vers dns01) est rouge :" \
    "« git01.par1.medisphere.internal ne se résout pas ». Plusieurs jobs de CI ont échoué" \
    "avec « Could not resolve host: git01.par1.medisphere.internal », d'autres sont passés." \
    "Les noms d'Internet se résolvent normalement. Personne n'a touché au DNS, paraît-il." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 06 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E35 4 "$@"; }
fi
