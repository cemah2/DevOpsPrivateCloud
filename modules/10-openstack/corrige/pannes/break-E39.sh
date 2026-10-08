# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M10-E39 « Panne : plus personne ne s'authentifie »
#
# Variantes (toutes sur osctl01) :
#   1. clés fernet (volume Docker keystone_fernet_tokens) passées en root:root 600 (« script d'audit
#      des droits ») → keystone ne peut plus les lire : aucun jeton émis ni validé (HTTP 5xx),
#      keystone_fernet devient « unhealthy » ;
#   2. keystone.conf (/etc/kolla/keystone/keystone.conf, hors du code) : mot de passe de la base dans
#      [database] connection remplacé (« rotation de mot de passe à moitié faite »), keystone
#      redémarré → keystone n'atteint plus sa base : 5xx (souvent 503 par HAProxy) ;
#   3. conteneur memcached arrêté → Horizon (sessions dans memcached) ne peut plus ouvrir de
#      session ; la CLI fonctionne encore (Keystone et les intergiciels se passent du cache).
# Sauvegardes : /var/lib/workbook/M10-E39.* sur osctl01. Rien n'est rétabli qui a déjà été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e39_precondition() {
  m10_prerequis || return 1
  m10_exec "$_M10_CTL" >/dev/null <<'EOF' || { wb_avert "osctl01 : keystone, keystone_fernet ou memcached ne tournent pas avant la panne (lab/bin/check 10 39)"; return 1; }
ctr_actif keystone && ctr_actif keystone_fernet && ctr_actif memcached
EOF
}

_mE39_une() {
  local n="$1" rc=0
  m10_exec "$_M10_CTL" VARIANTE="$n" >/dev/null <<'EOF' || rc=$?
case "$VARIANTE" in
  1)
    d="$(docker volume inspect -f '{{.Mountpoint}}' keystone_fernet_tokens 2>/dev/null </dev/null)"
    [ -n "$d" ] && [ -f "$d/0" ] || exit 10
    m="$WB_DIR/M10-E39.droits"
    if [ ! -f "$m" ]; then
      for f in "$d"/*; do printf '%s\t%s\n' "$f" "$(stat -c '%U:%G %a' "$f")"; done >"$m"
    fi
    chown root:root "$d"/* && chmod 600 "$d"/* || exit 1
    journal "clés fernet de $d passées en root:root 600"
    ;;
  2)
    f=/etc/kolla/keystone/keystone.conf
    [ -f "$f" ] || exit 10
    neuf="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    subst "$f" '^(connection[ \t]*=[ \t]*mysql\+pymysql://[^:/@]+:)[^@]+@' "\\g<1>$neuf@" || exit $?
    ctr_redemarrer keystone || exit 1
    journal "$f : mot de passe de [database] connection remplacé, keystone redémarré"
    ;;
  3)
    ctr_arreter memcached || exit $?
    ;;
esac
EOF
  ((rc == 0)) || return "$rc"
  sleep 20
  if ! verifier_E39; then
    _e39_defaire "$n"
    return 10
  fi
}

_e39_defaire() {
  m10_exec "$_M10_CTL" VARIANTE="$1" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (Keystone)"
case "$VARIANTE" in
  1)
    m="$WB_DIR/M10-E39.droits"
    [ -f "$m" ] || exit 0
    while IFS="$(printf '\t')" read -r f droits; do
      [ -e "$f" ] || continue
      if [ "$(stat -c '%U:%G %a' "$f")" = "root:root 600" ] && [ "$droits" != "root:root 600" ]; then
        chown "${droits% *}" "$f" && chmod "${droits#* }" "$f"
        journal "annulation : $f rendu à $droits"
      else
        journal "annulation : $f déjà corrigé (réparation), laissé tel quel"
      fi
    done <"$m"
    rm -f "$m"
    ;;
  2)
    if [ -n "$(defaire_subst)" ]; then ctr_redemarrer keystone; fi
    ;;
  3)
    ctr_relancer_arretes
    ;;
esac
EOF
}

_e39_injecter() {
  _e39_precondition || return 1
  m10_essayer E39 3 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }

# Variantes 1 et 2 : plus de jeton ; variante 3 : memcached ne répond plus sur osctl01.
verifier_E39() {
  case "${WB_VAR:-}" in
    3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF'
! ctr_actif memcached && ! ss -ltn 2>/dev/null | grep -q ':11211 '
EOF
      ;;
    *) ! m10_jeton_ok ;;
  esac
}

annuler_E39() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e39_defaire "$WB_VAR" ;;
    *) _e39_defaire 3; _e39_defaire 2; _e39_defaire 1 ;;
  esac
}

resume_E39() {
  case "${WB_VAR:-}" in
    3) echo "Plus personne ne peut se connecter au tableau de bord (erreur après le formulaire de connexion)." ;;
    *) echo "Plus aucune authentification : la CLI et le tableau de bord échouent à l'obtention du jeton (erreur 5xx)." ;;
  esac
}

symptome_E39() {
  local detail
  case "${WB_VAR:-}" in
    3) detail="Horizon : erreur juste après le formulaire de connexion, pour tout le monde. Karim dit que sa CLI marche." ;;
    *) detail="CLI : « openstack token issue » échoue (erreur HTTP 5xx). Horizon : connexion impossible." ;;
  esac
  wb_symptome "Ticket INC-3745 — De : Nadia Roussel" \
    "Alerte P1 à 7 h 40 : les équipes ne peuvent plus se connecter au cloud." \
    "$detail" \
    "Les instances déjà lancées tournent. InfoGér est intervenu hier soir sur osctl01" \
    "(« contrôle de conformité »), sans ticket de changement." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 10 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E39 3 "$@"; }
fi
