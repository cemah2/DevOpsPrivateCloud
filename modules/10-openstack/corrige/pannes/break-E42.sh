# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M10-E42 « Panne : le tableau de bord est inaccessible »
#
# Variantes (toutes sur osctl01) :
#   1. conteneur horizon arrêté → HAProxy n'a plus de serveur : 503 sur le tableau de bord ;
#   2. /etc/kolla/haproxy/services.d/horizon.cfg (généré par Kolla, modifié hors du code) : port
#      des serveurs 8080 → 8088, haproxy redémarré → contrôles de santé en échec, 503 ;
#   3. /etc/kolla/haproxy/haproxy.pem (certificat externe) remplacé par un certificat auto-signé
#      « de dépannage » au bon nom, haproxy redémarré → certificat refusé par tous les clients ;
#   4. conteneur keepalived arrêté → les VIP 10.10.50.200 et 10.10.50.201 disparaissent : délai
#      dépassé sur le tableau de bord ET sur toutes les API (interne comprise).
# Constat : depuis adm01, https://openstack.par1.medisphere.internal/auth/login/ ne répond plus 200
# avec un certificat vérifié. Le symptôme affiché est celui que mesure curl (code HTTP, erreur TLS ou
# délai), comme le décrirait un utilisateur.
# Sauvegardes : /var/lib/workbook/M10-E42.* sur osctl01. Rien n'est rétabli qui a déjà été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

# _e42_mesure — « 200 », « HTTP 503 », « TLS » ou « DELAI » (curl avec le magasin système).
_e42_mesure() {
  local code rc=0
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve "$_M10_FQDN:443:$_M10_VIP_EXT" "https://$_M10_FQDN/auth/login/" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) if [[ "$code" == 200 ]]; then echo 200; else echo "HTTP $code"; fi ;;
    35 | 51 | 58 | 60) echo TLS ;;
    *) echo DELAI ;;
  esac
}

_e42_precondition() {
  m10_prerequis || return 1
  if [[ "$(_e42_mesure)" != 200 ]]; then
    wb_avert "le tableau de bord ne répond pas 200 avec un certificat vérifié avant la panne : lab/bin/check 10 42"
    return 1
  fi
}

_mE42_une() {
  local n="$1" rc=0
  m10_exec "$_M10_CTL" VARIANTE="$n" FQDN="$_M10_FQDN" >/dev/null <<'EOF' || rc=$?
case "$VARIANTE" in
  1)
    ctr_arreter horizon || exit $?
    ;;
  2)
    f=/etc/kolla/haproxy/services.d/horizon.cfg
    [ -f "$f" ] || exit 10
    rx='^([ \t]*server[ \t]+\S+[ \t]+[0-9.]+:)8080\b'
    subst "$f" "$rx" '\g<1>8088' || exit $?
    while subst "$f" "$rx" '\g<1>8088'; do :; done
    ctr_redemarrer haproxy || exit 1
    journal "$f : port des serveurs 8080 → 8088, haproxy redémarré"
    ;;
  3)
    f=/etc/kolla/haproxy/haproxy.pem
    [ -f "$f" ] || exit 10
    t="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=$FQDN" \
      -addext "subjectAltName=DNS:$FQDN" -keyout "$t/k.pem" -out "$t/c.pem" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
    cat "$t/c.pem" "$t/k.pem" >"$t/haproxy.pem"
    remplacer "$f" "$t/haproxy.pem" || { rm -rf "$t"; exit 1; }
    rm -rf "$t"
    ctr_redemarrer haproxy || exit 1
    journal "$f remplacé par un certificat auto-signé, haproxy redémarré"
    ;;
  4)
    ctr_arreter keepalived || exit $?
    ;;
esac
EOF
  ((rc == 0)) || return "$rc"
  sleep 15
  if [[ "$(_e42_mesure)" == 200 ]]; then
    _e42_defaire "$n"
    return 10
  fi
}

_e42_defaire() {
  m10_exec "$_M10_CTL" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (HAProxy, Horizon, keepalived)"
r=""
[ -z "$(defaire_subst)" ] || r=1
[ -z "$(retablir_remplacements)" ] || r=1
if [ -n "$r" ]; then ctr_redemarrer haproxy; fi
ctr_relancer_arretes
EOF
}

_e42_injecter() {
  _e42_precondition || return 1
  m10_essayer E42 4 "$1"
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }
panne_E42_v4() { _e42_injecter 4; }

verifier_E42() {
  local m
  m="$(_e42_mesure)"
  m10_ecrire E42 mesure "$m"
  [[ "$m" != 200 ]]
}

annuler_E42() {
  _e42_defaire "${WB_VAR:-}"
  rm -f -- "$(m10_etat E42)/mesure"
}

_e42_constat() {
  case "$(m10_lire E42 mesure)" in
    TLS) echo "le navigateur affiche un avertissement de sécurité sur le certificat, et la CLI échoue avec « certificate verify failed »" ;;
    DELAI) echo "la page ne se charge pas du tout (délai dépassé), et la CLI ne répond plus non plus" ;;
    "HTTP "*) echo "la page affiche « $(m10_lire E42 mesure) Service Unavailable » (ou équivalent)" ;;
    *) echo "la page ne s'affiche plus" ;;
  esac
}

resume_E42() {
  echo "Le tableau de bord https://$_M10_FQDN est inaccessible : $(_e42_constat)."
}

symptome_E42() {
  wb_symptome "Ticket INC-3748 — De : Sophie Laurent" \
    "Je dois montrer le tableau de bord du cloud à l'auditeur HDS à 10 h, et" \
    "https://$_M10_FQDN ne fonctionne plus : $(_e42_constat)." \
    "Hier, InfoGér a « préparé le renouvellement des certificats et la répartition de charge »." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 10 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E42 4 "$@"; }
fi
