# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M19-E38 « Panne : le cache ne sert plus » : compartiment ci-cache dans le gabarit du
# runner et lisible par l'identité ci-cache, clé de cache du canari stable et chemins dans le projet,
# dernier canari avec cache restauré, RB-196, panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E38 — Le cache sert à nouveau"
require_cmd jq yq kubectl curl

if _m19x_api_repond; then
  check_cmd "gabarit du runner : compartiment de cache « ci-cache »" \
    bash -c '[[ "$1" == ci-cache ]]' _ "$(_m19x_toml_valeur BucketName)"
else
  skip "gabarit du runner" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
_m19_e38_env="${HOME}/.config/workbook/s3-ci-cache.env"
if command -v aws >/dev/null 2>&1 && [[ -r "$_m19_e38_env" ]]; then
  check_cmd "identité ci-cache : le compartiment ci-cache se liste sur s3-01" bash -c '
    set -a; . "$1"; set +a
    aws --endpoint-url "${AWS_ENDPOINT_URL:-https://s3-01.par1.medisphere.internal:8333}" s3api list-objects-v2 \
      --bucket ci-cache --max-items 1 >/dev/null 2>&1' _ "$_m19_e38_env"
else
  skip "accès S3 au compartiment ci-cache" "aws ou $_m19_e38_env absent (M19-E07)"
fi
if _m19x_temoin_existe; then
  _m19_e38_g="$(_m19x_canari_gabarit)" || _m19_e38_g=""
  check_cmd "composant canari consommé : clé de cache par fichier de verrou (pas par pipeline ni par job)" \
    bash -c 'yq -e "select(documentIndex == 1) | .canari.cache.key.files | length > 0" <<<"$1" >/dev/null 2>&1' _ "$_m19_e38_g"
  check_cmd "composant canari consommé : chemins de cache relatifs au projet" \
    bash -c 'yq -e "select(documentIndex == 1) | ((.canari.cache.paths | length > 0) and (.canari.cache.paths | all_c(test(\"^[^/\$]\"))))" <<<"$1" >/dev/null 2>&1' _ "$_m19_e38_g"
  check_cmd "dernier canari de main réussi, avec « CANARI cache restauré : oui »" _m19x_canari_trace 'CANARI cache restauré : oui'
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 38)"
fi
check_cmd "RB-196 : section sur le cache (identité S3, compartiment, clé, chemins)" _m19x_doc_contient 'RB-196*.md' 'cache'
check_cmd "panne M19-E38 close (lab/bin/break 19 38 --annuler après réparation)" _m19x_aucune_panne_active E38
