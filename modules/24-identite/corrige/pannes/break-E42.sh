# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E42.sh — M24-E42 « Panne : le fournisseur d'identité ne répond plus comme avant »
#
# Le fournisseur lui-même (idp01 : Keycloak, PostgreSQL) ou sa publication (lb01/lb02 : HAProxy) :
#   1. keycloak.conf : « hostname » réglé sur https://sso.par1.medisphere.internal:8443 (« le port de
#      Keycloak », dit Lucas) ; Keycloak redémarré : l'émetteur annoncé et celui des jetons changent,
#      les pages de connexion renvoient vers un port que la VIP ne publie pas ;
#   2. certificat de Keycloak (/etc/keycloak/tls/keycloak.{crt,key}) remplacé par un certificat
#      AUTOSIGNÉ au nom public sso.par1.medisphere.internal (« le certificat doit porter le nom public »),
#      Keycloak redémarré : HAProxy (verify required, verifyhost idp01) refuse le serveur, contrôle de
#      santé compris → 503 ;
#   3. HAProxy (lb01 ET lb02) : contrôle de santé de be_sso déplacé du port 9000 (gestion) au port 8443
#      (trafic), où /health/ready n'existe pas (404) : serveur DOWN, 503 ;
#   4. PostgreSQL d'idp01 : max_connections = 6 par un fichier conf.d « réglage mémoire » de Lucas,
#      PostgreSQL redémarré : 3 connexions pour Keycloak, refus « too many clients » / « remaining
#      connection slots are reserved » dès qu'il en veut plus ; lenteurs et erreurs par moments.
# Les fichiers modifiés sont sauvegardés sur l'hôte (/var/lib/workbook/M24-E42.*) ; l'annulation ne les
# remet que s'ils portent encore la marque de la panne, puis attend que la découverte réponde.
# Jamais pve01, jamais le royaume master, jamais une base autre que celle de Keycloak.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_E42_CONF="${WB_M24_KC_CONF:-/opt/keycloak/conf/keycloak.conf}"
_E42_TLS_DIR="${WB_M24_KC_TLS:-/etc/keycloak/tls}"
_E42_HAPROXY="${WB_M24_HAPROXY_CFG:-/etc/haproxy/haproxy.cfg}"
_E42_PG_CONFD="${WB_M24_PG_CONFD:-/etc/postgresql/17/main/conf.d}"
_E42_PG_FICHIER="$_E42_PG_CONFD/90-reglage-memoire.conf"
_E42_HOSTNAME_FAUX="${_M24_SSO}:8443"
_E42_MARQUE="M24-E42"

# --- Aides ---------------------------------------------------------------------------------------------

# _e42_attendre_keycloak — Keycloak répond « UP » sur son interface de gestion, depuis idp01 (180 s max).
# (-k : sur l'hôte même, seule la disponibilité compte ; la chaîne est vérifiée par HAProxy.)
_e42_kc_pret() { m24_ssh "$_M24_IDP" 'curl -sk --max-time 5 https://127.0.0.1:9000/health/ready' | grep -q '"UP"'; }

# _e42_sso_sain — la découverte publique répond avec l'émetteur attendu.
_e42_sso_sain() { [[ "$(m24_decouverte_emetteur)" == "$_M24_EMETTEUR" ]]; }

# _e42_code_decouverte — code HTTP de la découverte publique (000 si rien).
_e42_code_decouverte() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 --cacert "$_M24_RACINE" "$_M24_EMETTEUR/.well-known/openid-configuration" 2>/dev/null || true
}

_e42_kc_conf_hostname() {
  m24_wb_exec "$_M24_IDP" "F=$_E42_CONF" "H=$_E42_HOSTNAME_FAUX" "MARQUE=$_E42_MARQUE" <<'EOF'
[ -f "$F" ] || exit 10
grep -Eq '^hostname=https://sso\.par1\.medisphere\.internal/?$' "$F" || exit 10
sauver "$F"
t="$(mktemp)"
sed -E "s|^hostname=.*|# $MARQUE Lucas : le port de Keycloak\nhostname=$H|" "$F" > "$t"
cat "$t" > "$F"
rm -f "$t"
systemctl restart keycloak
journal "keycloak.conf : hostname=$H ; keycloak redémarré"
EOF
}

_e42_kc_conf_retablir() {
  m24_wb_exec "$_M24_IDP" "F=$_E42_CONF" "MARQUE=$_E42_MARQUE" <<'EOF'
if grep -qF "$MARQUE" "$F" 2>/dev/null; then
  restaurer_en_place
  systemctl restart keycloak || true
  journal "annulation : keycloak.conf remis, keycloak redémarré"
else
  m="$WB_DIR/$WB_EX.manifeste"
  [ -f "$m" ] && while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
EOF
}

_e42_certificat() {
  m24_wb_exec "$_M24_IDP" "D=$_E42_TLS_DIR" "MARQUE=$_E42_MARQUE" <<'EOF'
[ -f "$D/keycloak.crt" ] && [ -f "$D/keycloak.key" ] || exit 10
sauver "$D/keycloak.crt"
sauver "$D/keycloak.key"
t="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout "$t/k" -out "$t/c" \
  -subj "/O=$MARQUE/CN=sso.par1.medisphere.internal" -addext "subjectAltName=DNS:sso.par1.medisphere.internal" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
cat "$t/c" > "$D/keycloak.crt"
cat "$t/k" > "$D/keycloak.key"
rm -rf "$t"
systemctl restart keycloak
journal "certificat de Keycloak remplacé par un autosigné (CN=sso…) ; keycloak redémarré"
EOF
}

_e42_certificat_retablir() {
  m24_wb_exec "$_M24_IDP" "D=$_E42_TLS_DIR" "MARQUE=$_E42_MARQUE" <<'EOF'
if openssl x509 -in "$D/keycloak.crt" -noout -subject 2>/dev/null | grep -qF "$MARQUE"; then
  restaurer_en_place
  systemctl restart keycloak || true
  journal "annulation : certificat de Keycloak remis, keycloak redémarré"
else
  m="$WB_DIR/$WB_EX.manifeste"
  [ -f "$m" ] && while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
EOF
}

# _e42_haproxy LB — contrôle de santé de be_sso déplacé sur 8443 ; config validée avant rechargement.
_e42_haproxy() {
  m24_wb_exec "$1" "F=$_E42_HAPROXY" "MARQUE=$_E42_MARQUE" <<'EOF'
[ -f "$F" ] || exit 10
grep -Eq '^[[:space:]]*server idp0[0-9][[:space:]].*check port 9000' "$F" || exit 10
sauver "$F"
t="$(mktemp)"
sed -E "/^[[:space:]]*server idp0[0-9][[:space:]]/ s/check port 9000/check port 8443/; /^[[:space:]]*backend be_sso/ a\\    # $MARQUE Lucas : contrôle aligné sur le port du trafic" "$F" > "$t"
if ! haproxy -c -q -f "$t" >/dev/null 2>&1; then rm -f "$t"; restaurer_fichiers; exit 1; fi
cat "$t" > "$F"
rm -f "$t"
systemctl reload haproxy
journal "be_sso : contrôle de santé sur 8443 ; haproxy rechargé"
EOF
}

_e42_haproxy_retablir() {
  m24_wb_exec "$1" "F=$_E42_HAPROXY" "MARQUE=$_E42_MARQUE" <<'EOF'
if grep -qF "$MARQUE" "$F" 2>/dev/null; then
  restaurer_en_place
  haproxy -c -q -f "$F" >/dev/null 2>&1 && systemctl reload haproxy
  journal "annulation : haproxy.cfg remis, haproxy rechargé"
else
  m="$WB_DIR/$WB_EX.manifeste"
  [ -f "$m" ] && while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
EOF
}

_e42_postgresql() {
  m24_wb_exec "$_M24_IDP" "D=$_E42_PG_CONFD" "F=$_E42_PG_FICHIER" "MARQUE=$_E42_MARQUE" <<'EOF'
[ -d "$D" ] || exit 10
[ -e "$F" ] && exit 10
sauver "$F"
printf '# %s Lucas : réglage mémoire (PLAT-2542) — idp01 manque de RAM\nmax_connections = 6\n' "$MARQUE" > "$F"
chown postgres:postgres "$F"
chmod 0644 "$F"
systemctl restart postgresql
sleep 3
if ! systemctl is-active --quiet postgresql; then
  restaurer_fichiers
  systemctl restart postgresql || true
  journal "postgresql ne repart pas avec max_connections = 6 : fichier retiré"
  exit 10
fi
journal "max_connections = 6 ($F) ; postgresql redémarré"
EOF
}

_e42_postgresql_retablir() {
  m24_wb_exec "$_M24_IDP" "F=$_E42_PG_FICHIER" "MARQUE=$_E42_MARQUE" <<'EOF'
if grep -qF "$MARQUE" "$F" 2>/dev/null; then
  restaurer_fichiers
  systemctl restart postgresql || true
  sleep 3
  systemctl restart keycloak || true
  journal "annulation : fichier de réglage retiré, postgresql puis keycloak redémarrés"
else
  m="$WB_DIR/$WB_EX.manifeste"
  [ -f "$m" ] && while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
EOF
}

# _e42_pg_refus DEPUIS — PostgreSQL a refusé des connexions à Keycloak depuis DEPUIS (journal de Keycloak).
_e42_pg_refus() {
  m24_ssh "$_M24_IDP" "journalctl -u keycloak --since @$1 --no-pager -o cat | grep -Eqi 'too many clients|remaining connection slots|too many connections'"
}

# _e42_charge — quelques lectures parallèles de l'API d'administration (lecture seule) : elles demandent
# plusieurs connexions à la base en même temps.
_e42_charge() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    m24_kc GET "users?max=5&first=$i" >/dev/null 2>&1 &
  done
  wait || true
}

# --- Variantes ---------------------------------------------------------------------------------------------

_m24E42_une() {
  local n="$1" lb rc=0
  m24_ecrire E42 variante "$n"
  m24_ecrire E42 depuis "$(m24_maintenant)"
  case "$n" in
    1)
      m24_sain_hote "$_M24_IDP" || return 1
      _e42_kc_conf_hostname || rc=$?
      ;;
    2)
      m24_sain_hote "$_M24_IDP" || return 1
      _e42_certificat || rc=$?
      ;;
    3)
      for lb in "${_M24_LB[@]}"; do m24_sain_hote "$lb" || return 1; done
      for lb in "${_M24_LB[@]}"; do
        _e42_haproxy "$lb" || { rc=$?; break; }
      done
      ;;
    4)
      m24_sain_hote "$_M24_IDP" || return 1
      _e42_postgresql || rc=$?
      ;;
  esac
  ((rc == 0)) || return "$rc"
  m24_journal E42 "variante $n posée"
}

_e42_effet() {
  local e
  case "$1" in
    1)
      _e42_kc_pret || return 1
      e="$(m24_decouverte_emetteur)"
      [[ "$e" == "$_E42_HOSTNAME_FAUX/realms/medisphere" ]]
      ;;
    2 | 3) [[ "$(_e42_code_decouverte)" == 503 ]] ;;
    4)
      _e42_kc_pret || return 1
      _e42_charge
      _e42_pg_refus "$(m24_lire E42 depuis)"
      ;;
    *) return 1 ;;
  esac
}

verifier_E42() { m24_attendre 240 _e42_effet "$WB_VAR"; }

# Pas de m24_sain_keycloak ici pour la variante 3 seule : elle n'a pas besoin de l'API ; mais le
# fournisseur doit être sain AVANT la panne (sinon le symptôme serait ambigu).
panne_E42_v1() { m24_sain_keycloak && m24_essayer E42 4 1; }
panne_E42_v2() { m24_sain_keycloak && m24_essayer E42 4 2; }
panne_E42_v3() { m24_sain_keycloak && m24_essayer E42 4 3; }
panne_E42_v4() { m24_sain_keycloak && m24_essayer E42 4 4; }

annuler_E42() {
  local v lb
  v="$(m24_lire E42 variante)"
  case "$v" in
    1) _e42_kc_conf_retablir >/dev/null 2>&1 || wb_avert "$_M24_IDP : keycloak.conf à vérifier (rejoue le rôle keycloak)" ;;
    2) _e42_certificat_retablir >/dev/null 2>&1 || wb_avert "$_M24_IDP : certificat de Keycloak à vérifier (cert-renewer@keycloak, rôle certificats_acme)" ;;
    3)
      for lb in "${_M24_LB[@]}"; do
        _e42_haproxy_retablir "$lb" >/dev/null 2>&1 || wb_avert "$lb : haproxy.cfg à vérifier (rejoue le rôle haproxy)"
      done
      ;;
    4) _e42_postgresql_retablir >/dev/null 2>&1 || wb_avert "$_M24_IDP : $_E42_PG_FICHIER à retirer, puis redémarrer postgresql" ;;
  esac
  # Les annulations des autres pannes (astreinte M24-E43) passent par l'API : attendre le retour du SSO.
  if [[ -n "$v" ]] && ! m24_attendre 240 _e42_sso_sain; then
    wb_avert "la découverte de $_M24_EMETTEUR ne répond pas encore normalement (lab/bin/check 24 42)"
  fi
  m24_oublier E42 variante
  m24_oublier E42 depuis
  m24_journal E42 "annulation"
}

resume_E42() { echo "Le SSO lui-même va mal : page d'erreur, 503, ou lenteurs et échecs par moments, pour tous les services."; }

symptome_E42() {
  local detail
  case "$WB_VAR" in
    1) detail="Depuis le redémarrage de Keycloak par Lucas, plus rien : Grafana dit « Login failed », kubectl « Unauthorized », et quand je clique sur « SSO MédiSphère », le navigateur part sur une adresse qui ne répond pas." ;;
    2 | 3) detail="https://sso.par1.medisphere.internal répond « 503 Service Unavailable » à tout le monde. Plus personne n'entre nulle part par le SSO." ;;
    *) detail="Le SSO est devenu très lent ; une connexion sur deux finit sur « We are sorry… An internal server error has occurred » ; ça va mieux, puis ça recommence." ;;
  esac
  wb_symptome "Ticket INC-5142 — De : Julien Petit" \
    "$detail" \
    "Lucas a « optimisé » quelque chose sur idp01 ou sur les répartiteurs hier soir, il ne sait plus quoi exactement." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 24 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E42 4 "$@"; }
fi
