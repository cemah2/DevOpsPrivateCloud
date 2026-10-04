# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M02-E36 « Panne : medictl ne parle plus à Proxmox »
#
# Variantes :
#   1. jeton wb-automation@pve!lab expiré (date d'expiration passée) — pve01 ;
#   2. ACL de l'UTILISATEUR wb-automation@pve retirée sur /pool/lab (celle du jeton reste :
#      jeton à privilèges séparés = intersection des deux → plus aucun droit sur le pool) — pve01 ;
#   3. fichier de CA PVE_CACERT de adm01 remplacé par la racine de la PKI provisoire
#      (« mise à jour des certificats ») : la vérification TLS échoue — adm01 ;
#   4. compte wb-automation@pve désactivé (« revue trimestrielle des accès ») — pve01.
# Sauvegardes : /var/lib/workbook/M02-E36.* sur pve01 (expiration, ACL, état du compte) et
# sur adm01 (copie du fichier de CA). Effet de bord voulu : tout ce qui utilise ce compte,
# ce jeton ou ce fichier de CA (ms-snapshot, timer de M02-E26…) est touché aussi.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E36_ENV="${MEDICTL_ENV_FILE:-$HOME/.config/workbook/pve-api.env}"

# _e36_cacert — chemin du fichier de CA déclaré dans pve-api.env (défaut M00-E17).
_e36_cacert() {
  local c
  # shellcheck source=/dev/null
  c="$(source "$_E36_ENV" 2>/dev/null && printf '%s' "${PVE_CACERT:-}")"
  printf '%s\n' "${c:-$HOME/.config/workbook/pve-root-ca.pem}"
}

# _e36_appel CHEMIN — appelle l'API avec le jeton de pve-api.env ; affiche « code_curl code_http ».
_e36_appel() {
  local rc=0 code
  # shellcheck disable=SC1090
  code="$(source "$_E36_ENV" && printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time 15 --cacert "$PVE_CACERT" -H @- "$PVE_API_URL$1")" || rc=$?
  printf '%s %s\n' "$rc" "${code:-000}"
}

_e36_nb_vms() {
  # shellcheck disable=SC1090
  (source "$_E36_ENV" && printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" \
    | curl -sf --max-time 15 --cacert "$PVE_CACERT" -H @- "$PVE_API_URL/cluster/resources?type=vm" \
    | jq '.data | length')
}

_e36_precondition() {
  [[ -r "$_E36_ENV" ]] || { wb_avert "$_E36_ENV illisible"; return 1; }
  local r
  r="$(_e36_appel /version)"
  [[ "$r" == "0 200" ]] || { wb_avert "l'API ne répond pas normalement avant la panne ($r) : lab/bin/check 02 36"; return 1; }
}

panne_E36_v1() {
  _e36_precondition || return 1
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF'
j="$(pveum user token list wb-automation@pve --output-format json)" || exit 1
exp="$(printf '%s' "$j" | perl -MJSON::PP -0777 -ne 'for (@{decode_json($_)}) { print $_->{expire} // 0 if $_->{tokenid} eq "lab" }')"
[ -n "$exp" ] || { echo "jeton wb-automation@pve!lab introuvable" >&2; exit 1; }
[ -f "$WB_DIR/M02-E36.expire" ] || printf '%s\n' "$exp" >"$WB_DIR/M02-E36.expire"
pveum user token modify wb-automation@pve lab --expire "$(( $(date +%s) - 3600 ))" >/dev/null || exit 1
journal "jeton wb-automation@pve!lab : expiration $exp → il y a une heure"
EOF
}

panne_E36_v2() {
  _e36_precondition || return 1
  [[ "$(_e36_nb_vms)" =~ ^[1-9] ]] || { wb_avert "le jeton ne voit déjà aucune VM : lab/bin/check 02 36"; return 1; }
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF'
ligne="$(pveum acl list --output-format json | perl -MJSON::PP -0777 -ne '
  for (@{decode_json($_)}) {
    print "$_->{roleid} ", ($_->{propagate} // 1), "\n"
      if $_->{path} eq "/pool/lab" && $_->{type} eq "user" && $_->{ugid} eq "wb-automation\@pve";
  }' | head -n 1)"
[ -n "$ligne" ] || { echo "aucune ACL utilisateur wb-automation@pve sur /pool/lab" >&2; exit 1; }
[ -f "$WB_DIR/M02-E36.acl" ] || printf '%s\n' "$ligne" >"$WB_DIR/M02-E36.acl"
role="${ligne%% *}"
pveum acl delete /pool/lab --users wb-automation@pve --roles "$role" || exit 1
journal "ACL utilisateur wb-automation@pve ($role) retirée de /pool/lab (celle du jeton conservée)"
EOF
}

panne_E36_v3() {
  _e36_precondition || return 1
  local ca
  ca="$(_e36_cacert)"
  [[ -f "$ca" ]] || { wb_avert "fichier de CA $ca absent"; return 1; }
  wb_exec localhost CA="$ca" U="$(id -un)" >/dev/null <<'EOF'
sauver "$CA"
src=/usr/local/share/ca-certificates/medisphere-provisoire.crt
if [ -s "$src" ] && ! cmp -s "$src" "$CA"; then
  cat "$src" >"$CA"
else
  # Pas de PKI provisoire sur ce poste : une autre CA, tout aussi étrangère à pve01.
  t="$(mktemp -d)"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
    -subj "/CN=MédiSphère CA provisoire" -keyout "$t/k" -out "$t/c" >/dev/null 2>&1 || exit 1
  cat "$t/c" >"$CA"
  rm -rf -- "$t"
fi
chown "$U" "$CA"
journal "fichier de CA $CA remplacé par une autre racine"
EOF
}

panne_E36_v4() {
  _e36_precondition || return 1
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF'
en="$(pveum user list --output-format json | perl -MJSON::PP -0777 -ne '
  for (@{decode_json($_)}) { print $_->{enable} // 1 if $_->{userid} eq "wb-automation\@pve" }')"
[ -n "$en" ] || { echo "utilisateur wb-automation@pve introuvable" >&2; exit 1; }
if [ ! -f "$WB_DIR/M02-E36.enable" ]; then
  printf '%s\n' "$en" >"$WB_DIR/M02-E36.enable"
  pveum user list --output-format json | perl -MJSON::PP -0777 -ne '
    for (@{decode_json($_)}) { print $_->{comment} // "" if $_->{userid} eq "wb-automation\@pve" }' \
    >"$WB_DIR/M02-E36.commentaire"
fi
pveum user modify wb-automation@pve --enable 0 --comment "Désactivé lors de la revue trimestrielle des accès (SEC-381)" || exit 1
journal "utilisateur wb-automation@pve désactivé"
EOF
}

verifier_E36() {
  local r
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1 | 4)
      r="$(_e36_appel /version)"
      [[ "$r" == "0 401" ]] ;;
    2)
      [[ "$(_e36_nb_vms)" == 0 ]] ;;
    3)
      r="$(_e36_appel /version)"
      [[ "${r%% *}" == 60 ]] ;;
    *) return 1 ;;
  esac
}

annuler_E36() {
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/M02-E36.expire" ]; then
  pveum user token modify wb-automation@pve lab --expire "$(cat "$WB_DIR/M02-E36.expire")" && rm -f "$WB_DIR/M02-E36.expire"
  journal "annulation : expiration du jeton rétablie"
fi
if [ -f "$WB_DIR/M02-E36.acl" ]; then
  read -r role prop <"$WB_DIR/M02-E36.acl"
  pveum acl modify /pool/lab --users wb-automation@pve --roles "$role" --propagate "${prop:-1}" \
    && rm -f "$WB_DIR/M02-E36.acl"
  journal "annulation : ACL utilisateur sur /pool/lab rétablie"
fi
if [ -f "$WB_DIR/M02-E36.enable" ]; then
  pveum user modify wb-automation@pve --enable "$(cat "$WB_DIR/M02-E36.enable")" \
    --comment "$(cat "$WB_DIR/M02-E36.commentaire" 2>/dev/null)" \
    && rm -f "$WB_DIR/M02-E36.enable" "$WB_DIR/M02-E36.commentaire"
  journal "annulation : compte wb-automation@pve réactivé"
fi
exit 0
EOF
  wb_exec localhost >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
restaurer_fichiers
exit 0
EOF
}

resume_E36() {
  echo "medictl ne parle plus à Proxmox depuis adm01 (erreurs, ou listes vides) ; ms-snapshot est touché aussi."
}

symptome_E36() {
  wb_symptome "Ticket INC-2842 — De : Karim Benali" \
    "Depuis ce matin, medictl ne fonctionne plus depuis adm01 : « medictl vm list --pool lab »" \
    "échoue ou ne renvoie plus rien, alors que les VMs tournent (l'interface web de Proxmox les" \
    "montre). ms-snapshot est en erreur aussi. Personne n'a touché au code de plateforme/outils" \
    "depuis la dernière release. J'ai une intervention à 14 h qui a besoin des instantanés." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 02 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E36 4 "$@"; }
fi
