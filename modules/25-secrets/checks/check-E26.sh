# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E26.sh — M25-E26 « Instantanés chiffrés et restauration éprouvée » : minuterie active sur les
# trois nœuds ; dernier succès de moins de 2 h ; dernier objet de openbao-instantanes récent, non vide,
# chiffré age ; cycle de vie de 30 jours ; politique de compartiment qui refuse la suppression (dépôt) ;
# RB-252 avec RPO et RTO mesurés ; bao-restauration (2252) détruite ; plus de flux vsandbox → kms01.
# À lancer depuis adm01. Lecture seule : SSH en consultation, s3-01 en LECTURE (identité
# openbao-instantanes : list, get ; identité d'administration : lecture du cycle de vie), GitLab, qm status.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E26 — Instantanés chiffrés et restauration éprouvée"
require_cmd jq aws

for _m25_e26_n in "${_M25P_NOEUDS[@]}"; do
  check_ssh "$_m25_e26_n : openbao-instantane.timer actif et activé, script en place" "$_m25_e26_n" \
    'systemctl is-active --quiet openbao-instantane.timer && systemctl is-enabled --quiet openbao-instantane.timer && test -x /usr/local/sbin/openbao-instantane'
done

_m25_e26_dernier() {
  local n t max=0
  for n in "${_M25P_NOEUDS[@]}"; do
    t="$(_m25p_ssh_sortie "$n" 'cut -d" " -f1 /var/lib/openbao-instantane/dernier-succes 2>/dev/null')"
    [[ "$t" =~ ^[0-9]+$ ]] && ((t > max)) && max="$t"
  done
  ((max > 0 && $(date +%s) - max < 7200))
}
check_cmd "dernier instantané réussi (trace d'un nœud) il y a moins de 2 h" _m25_e26_dernier

_m25_e26_objet="$(_m25p_s3 "$_M25P_S3_ENV" s3api list-objects-v2 --bucket openbao-instantanes --prefix horaire/ 2>/dev/null \
  | jq -c '[.Contents[]?] | sort_by(.LastModified) | last // empty' 2>/dev/null || true)"
if [[ ! -r "$_M25P_S3_ENV" ]]; then
  check_cmd "identité S3 openbao-instantanes lisible ($_M25P_S3_ENV)" false
elif [[ -z "$_m25_e26_objet" ]]; then
  check_cmd "au moins un objet dans s3://openbao-instantanes/horaire/" false
else
  check_cmd "dernier objet de moins de 2 h et non vide ($(jq -r .Key <<<"$_m25_e26_objet"))" \
    _m25p_jq "$_m25_e26_objet" '(.Size > 1000) and ((now - (.LastModified | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601)) < 7200)'
  _m25_e26_age() {
    _m25p_s3 "$_M25P_S3_ENV" s3 cp "s3://openbao-instantanes/$(jq -r .Key <<<"$_m25_e26_objet")" - 2>/dev/null \
      | head -c 22 | grep -q '^age-encryption.org/v1'
  }
  check_cmd "le dernier objet est chiffré par age (en-tête age-encryption.org/v1)" _m25_e26_age
fi

if [[ -r "$_M25P_S3_ADMIN" ]]; then
  check_cmd "cycle de vie du compartiment : expiration à 30 jours sur horaire/" \
    _m25p_jq "$(_m25p_s3 "$_M25P_S3_ADMIN" s3api get-bucket-lifecycle-configuration --bucket openbao-instantanes 2>/dev/null || echo null)" \
    '[.Rules[] | select(.Status == "Enabled") | select(((.Filter.Prefix // .Prefix // "") | startswith("horaire")) or ((.Filter.Prefix // .Prefix // "") == "")) | .Expiration.Days] | any(. == 30)'
else
  skip "cycle de vie du compartiment" "identité d'administration S3 absente ($_M25P_S3_ADMIN)"
fi
check_cmd "politique du compartiment (plateforme/infra outils/s3/) : suppression refusée à openbao-instantanes" \
  bash -c '_c="$1"; grep -q "openbao-instantanes" <<<"$_c" && grep -q "s3:DeleteObject" <<<"$_c" && grep -q "\"Deny\"" <<<"$_c"' _ \
  "$(_m25p_fichier plateforme/infra outils/s3/politique-openbao-instantanes.json || true)"

check_cmd "RB-252 sur main : RPO et RTO mesurés (valeurs chiffrées)" \
  _m25p_doc "$_M25P_DOC" "$_M25P_RB" 'RB-252[^/]*\.md$' 30 'RPO[^|]*\|[^|]*[0-9]+ ?(min|s|h)' 'RTO[^|]*\|[^|]*[0-9]+ ?(min|s|h)' 'kms01'

check_cmd "bao-restauration (VMID 2252) n'existe plus" _m25p_vm_absente 2252
check_cmd "matrice de la bordure (pare_feu.yml, main) : plus de flux depuis 10.10.99.52" \
  _m25p_fichier_sans "$_M25P_ANSIBLE" inventories/lab/group_vars/role_routeur/pare_feu.yml '^[^#]*10\.10\.99\.52'
check_cmd "pare-feu local de kms01 (main) : plus de flux depuis vsandbox" \
  _m25p_fichier_sans "$_M25P_ANSIBLE" inventories/lab/host_vars/kms01/pare_feu_local.yml '^[^#]*10\.10\.99\.'
