# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E21.sh — M13-E21 « Panne : la signature n'est plus reconnue »
#
# Variantes :
#   1. clé publique de la sonde remplacée par celle d'une nouvelle paire (« rotation » sans re-signature)
#      → « no matching signatures » ;
#   2. étiquette déplacée : une autre image est poussée sous wb-sonde/signee:1.0 ; la signature reste
#      attachée à l'ancien digest → « no signatures found » sur l'étiquette ;
#   3. signature supprimée côté registre (accessoire signature.cosign de l'artefact signé) ;
#   4. la sonde utilise l'image Cosign 2.5 (celle de Debian 13), qui ne lit pas les signatures rangées
#      en référents OCI 1.1 par Cosign 3.
# Valeurs d'origine dans ~/.local/state/workbook/M13-E21/ (adm01) et /var/lib/workbook/ (runner02).
# Aucune signature n'est perdue sans moyen de la refaire : la clé privée de test est sur runner02.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m13-commun.sh
source "$WB_ROOT/modules/13-registre-supply-chain/corrige/pannes/_m13-commun.sh"

_E21_REPO=projects/wb-sonde/repositories/signee/artifacts

# _e21_digest_attendu — digest signé noté à la création des témoins (temoins.txt de runner02).
_e21_digest_attendu() {
  remote "$_M13_RUNNER" "sudo -n cat /etc/workbook/sonde-registre/temoins.txt" 2>/dev/null \
    | awk '$1 == "signee:1.0" { print $2 }'
}
_e21_digest_etiquette() { m13_api GET "$_E21_REPO/1.0" | jq -r '.digest // empty'; }
_e21_signatures() {
  m13_api GET "$_E21_REPO/$1/accessories?page_size=50" | jq -r '.[]? | select(.type == "signature.cosign") | .digest'
}

# _e21_resigner DIGEST — signe à nouveau DIGEST avec la clé de test (annulation de la variante 3).
_e21_resigner() {
  wb_exec "$_M13_RUNNER" REG="$_M13_REGISTRE" DIGEST="$1" <<'EOF'
set -e
D=/etc/workbook/sonde-registre K=/var/lib/workbook/temoins-m13
# shellcheck source=/dev/null
. "$D/sonde.conf"
docker --config "$D/tirage" run --rm --network host --user 0:0 -v "$K:/k" -v "$D/ci:/cfg:ro" \
  -v "$RACINE:/ca.crt:ro" -e DOCKER_CONFIG=/cfg -e SSL_CERT_FILE=/ca.crt \
  -e COSIGN_PASSWORD="$(cat "$K/cosign-sonde.pass")" "$COSIGN_IMAGE" \
  sign --yes --key /k/cosign-sonde.key --signing-config /k/signing-config.json "$REG/wb-sonde/signee@$DIGEST" >/dev/null 2>&1
journal "signee@$DIGEST signée à nouveau (clé de test)"
EOF
}

_e21_poser() {
  local att s
  att="$(_e21_digest_attendu)"
  [[ "$att" == sha256:* ]] || return 1
  m13_ecrire E21 digest "$att"
  case "$1" in
    1)
      wb_exec "$_M13_RUNNER" <<'EOF' || return 1
set -e
D=/etc/workbook/sonde-registre A="$WB_DIR/$WB_EX.autre-cle"
# shellcheck source=/dev/null
. "$D/sonde.conf"
sauver "$D/cosign.pub"
install -d -m 0700 "$A"
docker --config "$D/tirage" run --rm --user 0:0 -v "$A:/k" -w /k -e COSIGN_PASSWORD=rotation-2026 \
  "$COSIGN_IMAGE" generate-key-pair --output-key-prefix cosign-rotation >/dev/null 2>&1
cp "$A/cosign-rotation.pub" "$D/cosign.pub"
journal "clé publique de la sonde remplacée (nouvelle paire, rien de re-signé)"
EOF
      ;;
    2)
      wb_exec "$_M13_RUNNER" REG="$_M13_REGISTRE" <<'EOF' || return 1
set -e
D=/etc/workbook/sonde-registre
t="$(mktemp -d)"
printf 'reconstruction du %s\n' "$(date -Is)" > "$t/temoin.txt"
printf 'FROM scratch\nCOPY temoin.txt /\n' > "$t/Dockerfile"
docker build -q -t "$REG/wb-sonde/signee:1.0" "$t" >/dev/null
rm -rf "$t"
docker --config "$D/ci" push -q "$REG/wb-sonde/signee:1.0" >/dev/null
journal "nouvelle image poussée sous wb-sonde/signee:1.0"
EOF
      [[ "$(_e21_digest_etiquette)" != "$att" ]] || return 1
      m13_ecrire E21 digest_nouveau "$(_e21_digest_etiquette)"
      ;;
    3)
      s="$(_e21_signatures "$att" | head -n 1)"
      [[ -n "$s" ]] || return 10
      m13_api DELETE "$_E21_REPO/$s" >/dev/null || return 1
      m13_ecrire E21 signature_supprimee "$s"
      ;;
    4)
      wb_exec "$_M13_RUNNER" ANCIENNE="$_M13_COSIGN_IMAGE_ANCIENNE" <<'EOF' || return 1
set -e
f=/etc/workbook/sonde-registre/sonde.conf
sauver "$f"
sed -i "s|^COSIGN_IMAGE=.*|COSIGN_IMAGE=$ANCIENNE|" "$f"
journal "image Cosign de la sonde : $ANCIENNE"
EOF
      ;;
  esac
  m13_journal E21 "variante $1 posée"
}

_e21_defaire() {
  local att cour
  att="$(m13_lire E21 digest)"
  case "$1" in
    1 | 4)
      wb_exec "$_M13_RUNNER" <<'EOF' || wb_avert "annulation : fichiers de la sonde non rétablis"
if [ -f "$WB_DIR/$WB_EX.manifeste" ]; then restaurer_fichiers; journal "fichiers de la sonde rétablis"; fi
rm -rf "$WB_DIR/$WB_EX.autre-cle"
EOF
      ;;
    2)
      [[ -n "$att" ]] || return 0
      cour="$(_e21_digest_etiquette)"
      if [[ -n "$cour" && "$cour" != "$att" ]]; then
        m13_api DELETE "$_E21_REPO/$cour/tags/1.0" >/dev/null || true
        m13_api POST "$_E21_REPO/$att/tags" '{"name":"1.0"}' >/dev/null || wb_avert "annulation : étiquette 1.0 non replacée"
      fi
      cour="$(m13_lire E21 digest_nouveau)"
      # L'artefact poussé par la panne, s'il n'a plus d'étiquette, est retiré.
      if [[ -n "$cour" ]] && m13_api GET "$_E21_REPO/$cour?with_tag=true" | jq -e '(.tags // []) | length == 0' >/dev/null 2>&1; then
        m13_api DELETE "$_E21_REPO/$cour" >/dev/null || true
      fi
      ;;
    3)
      [[ -n "$att" && -n "$(m13_lire E21 signature_supprimee)" ]] || return 0
      [[ -n "$(_e21_signatures "$att")" ]] || _e21_resigner "$att" || wb_avert "annulation : signature non refaite"
      ;;
  esac
}

_e21_injecter() { m13_preparer || return 1; _e21_poser "$1"; }
panne_E21_v1() { _e21_injecter 1; }
panne_E21_v2() { _e21_injecter 2; }
panne_E21_v3() { _e21_injecter 3; }
panne_E21_v4() { _e21_injecter 4; }

verifier_E21() { m13_attendre 90 m13_sonde_echoue signature; }

annuler_E21() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e21_defaire "$WB_VAR" ;;
    *) _e21_defaire 4; _e21_defaire 3; _e21_defaire 2; _e21_defaire 1 ;;
  esac
  m13_journal E21 "annulation"
  rm -rf -- "$(m13_etat E21)"
}

resume_E21() { echo "La vérification de signature avant déploiement échoue sur une image déployée depuis des semaines."; }

symptome_E21() {
  wb_symptome "Ticket INC-4021 — De : Nadia Roussel (copie : Sophie Laurent)" \
    "La vérification Cosign avant déploiement échoue sur wb-sonde/signee:1.0, qu'on déploie depuis" \
    "des semaines. Personne n'a touché à l'image, paraît-il. Reproduction : « sudo wb-sonde-registre »" \
    "sur runner02, étape « signature ». Sophie : on ne contourne rien, et on ne re-signe pas une image" \
    "dont on ne sait pas d'où elle vient." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 13 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 13 E21 4 "$@"; }
fi
