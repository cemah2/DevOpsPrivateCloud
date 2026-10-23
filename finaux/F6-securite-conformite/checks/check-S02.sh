# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S02.sh — F6-S02 « Les preuves se collectent seules » (LIBRE) : compartiment preuves-conformite
# en verrouillage d'objets (COMPLIANCE, rétention ≥ WB_F6_RETENTION_MIN jours), lots récents déposés
# par le pipeline planifié, empreintes et signature du dernier lot, outil et catalogue publiés.
# Lecture seule : identité S3 de LECTURE (preuves-lecture), GitLab en GET.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S02 — Les preuves se collectent seules"
require_cmd curl jq aws sha256sum

_f6_s02_outil() {
  _f6c_fichier "$_f6c_outils" bin/ms-preuves >/dev/null 2>&1 && _f6c_fichier "$_f6c_outils" preuves/catalogue.yaml >/dev/null 2>&1 &&
    _f6c_fichier "$_f6c_outils" tests/ms-preuves/lancer.sh >/dev/null 2>&1
}
check_cmd "plateforme/outils (main) : bin/ms-preuves, son catalogue et ses tests" _f6_s02_outil
_f6_s02_cat="$(_f6c_contenu preuves.md)"
check_cmd "docs/conformite/preuves.md : catalogue (identifiants P-…, mesures, fréquence, rétention, vérification)" \
  _f6c_contient "$_f6_s02_cat" 'P-[A-Z]{2,4}-[0-9]{2}' 'COMPLIANCE' 'r(é|e)tention' 'v(é|e)rifi' '(5|8)\.[0-9]+'

if ! _f6c_preuves_identite; then
  skip "compartiment $_f6c_bucket" "identité de lecture absente : $_f6c_preuves_env (utilisateur RGW preuves-lecture)"
else
  _f6_s02_v="$(_f6c_verrou || true)"
  [[ -n "$_f6_s02_v" ]] || _f6_s02_v="{}"
  _f6_s02_jv() { jq -e "$@" <<<"$_f6_s02_v" >/dev/null 2>&1; }
  check_cmd "$_f6c_bucket : verrouillage d'objets actif avec une rétention par défaut" \
    _f6_s02_jv '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled" and (.ObjectLockConfiguration.Rule.DefaultRetention.Mode // "") != ""'
  check_cmd "$_f6c_bucket : mode COMPLIANCE, rétention ≥ $_f6c_retention_min jours (fin de la phase d'essai)" \
    _f6_s02_jv --argjson m "$_f6c_retention_min" '.ObjectLockConfiguration.Rule.DefaultRetention
      | .Mode == "COMPLIANCE" and (((.Days // 0) >= $m) or ((.Years // 0) * 365 >= $m))'
  _f6_s02_versions() { _f6c_s3 s3api get-bucket-versioning --bucket "$_f6c_bucket" | jq -e '.Status == "Enabled"' >/dev/null; }
  check_cmd "$_f6c_bucket : versionnage activé" _f6_s02_versions

  _f6_s02_lot="$(_f6c_dernier_lot || true)"
  _f6_s02_recent() {
    local l="${_f6_s02_lot##*/}" t
    [[ "$l" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z ]] || return 1
    t="$(date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}Z" +%s)" || return 1
    (($(date +%s) - t <= _f6c_lot_age_max * 3600))
  }
  check_cmd "un lot de preuves de moins de ${_f6c_lot_age_max} h est déposé (dernier : ${_f6_s02_lot:-aucun})" _f6_s02_recent

  _f6_s02_tmp="$(mktemp -d)"
  trap 'rm -rf -- "$_f6_s02_tmp"' EXIT
  if [[ -n "$_f6_s02_lot" ]] && _f6c_s3 s3 cp --recursive --only-show-errors "s3://$_f6c_bucket/$_f6_s02_lot/" "$_f6_s02_tmp/" >/dev/null; then
    check_cmd "dernier lot : lot.json, manifeste et signature présents" \
      test -s "$_f6_s02_tmp/lot.json" -a -s "$_f6_s02_tmp/MANIFESTE.sha256" -a -s "$_f6_s02_tmp/MANIFESTE.sha256.sigstore.json"
    _f6_s02_empreintes() { (cd "$_f6_s02_tmp" && sha256sum --quiet --strict -c MANIFESTE.sha256); }
    check_cmd "dernier lot : les empreintes du manifeste sont justes" _f6_s02_empreintes
    check_cmd "dernier lot : au moins 8 preuves collectées, provenant d'un pipeline" \
      jq -e '(.preuves | map(select(.statut == "ok")) | length) >= 8 and (.origine.pipeline // "") != ""' "$_f6_s02_tmp/lot.json"
    _f6_s02_pub="$(_f6c_contenu cle-preuves.pub)"
    if ! command -v cosign >/dev/null 2>&1 || [[ -z "$_f6_s02_pub" ]]; then
      skip "signature du dernier lot" "cosign absent d'adm01 ou docs/conformite/cle-preuves.pub non publiée"
    else
      printf '%s\n' "$_f6_s02_pub" >"$_f6_s02_tmp/cle.pub"
      check_cmd "dernier lot : signature du manifeste vérifiée avec docs/conformite/cle-preuves.pub" \
        cosign verify-blob --key "$_f6_s02_tmp/cle.pub" --insecure-ignore-tlog=true \
        --bundle "$_f6_s02_tmp/MANIFESTE.sha256.sigstore.json" "$_f6_s02_tmp/MANIFESTE.sha256"
    fi
    _f6_s02_retenu() {
      _f6c_s3 s3api head-object --bucket "$_f6c_bucket" --key "$_f6_s02_lot/MANIFESTE.sha256" |
        jq -e --arg n "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '(.ObjectLockMode // "") != "" and (.ObjectLockRetainUntilDate // "") > $n' >/dev/null
    }
    check_cmd "dernier lot : le manifeste porte une rétention en cours" _f6_s02_retenu
  else
    _ko "dernier lot : illisible avec l'identité de lecture (aucun lot, ou droits de lecture absents)"
  fi
fi
check_cmd "plateforme/outils : un pipeline planifié de main a réussi récemment" _f6c_pipelines_planifies_ok "$_f6c_outils" 10
