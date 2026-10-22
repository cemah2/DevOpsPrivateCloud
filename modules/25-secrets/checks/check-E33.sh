# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et requêtes LogQL entre apostrophes
#
# check-E33.sh — M25-E33 « Une politique de rotation automatisée » (LIBRE) : politique et RB-254 sur
# main ; pipeline planifié de plateforme/secrets réussi dans les 8 derniers jours ; chaque secret de
# kv/plateforme/ porte « proprietaire » et « rotation » et la version courante est plus jeune que sa
# période ; rotation du trousseau et d'une version de sops-plateforme tracées dans l'audit (30 jours).
# À lancer depuis adm01. Lecture seule : GitLab, AppRole wb-checks (kv/metadata : jamais une valeur),
# Loki (locataire audit).

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E33 — Une politique de rotation automatisée"
require_cmd jq curl
_m25p_connexion

_m25_e33_politique() {
  local f c n
  f="$(_m25p_doc_chemin "$_M25P_DOC" docs/securite/secrets 'politique-rotation\.md$')"
  [[ -n "$f" ]] || return 1
  c="$(_m25p_fichier "$_M25P_DOC" "$f")" || return 1
  # Lignes de tableau hors en-tête et séparateur : au moins dix types de secrets.
  n="$(grep -E '^\|' <<<"$c" | grep -Evc '^\|[ :-]+\|' || true)"
  ((n >= 11))
}
check_cmd "politique-rotation.md sur main : au moins dix types de secrets dans le tableau" _m25_e33_politique
check_cmd "RB-254 sur main (rotation par type, à la main, non-coupure, retour arrière)" \
  _m25p_doc "$_M25P_DOC" "$_M25P_RB" 'RB-254[^/]*\.md$' 20 'keycloak' 'gitlab' 'coupure' 'retour arri|rollback'

_m25_e33_planifie() {
  local depuis
  depuis="$(date -u -d '-8 days' +%Y-%m-%dT%H:%M:%SZ)"
  gitlab_api "projects/$(jq -rn --arg v "$_M25P_SECRETS" '$v|@uri')/pipelines?source=schedule&ref=main&status=success&updated_after=$depuis&per_page=1" 2>/dev/null \
    | jq -e 'length >= 1' >/dev/null 2>&1
}
check_cmd "un pipeline planifié de $_M25P_SECRETS a réussi sur main dans les 8 derniers jours" _m25_e33_planifie

# Métadonnées et âge de chaque secret de kv/plateforme/ (versions : created_time de la courante).
_m25_e33_feuilles="$(_m25p_kv_feuilles plateforme/)"
_m25_e33_nb="$(grep -c . <<<"$_m25_e33_feuilles" || true)"
if ((_m25_e33_nb == 0)); then
  check_cmd "secrets de kv/plateforme/ listables par wb-checks" false
else
  _m25_e33_sans="" ; _m25_e33_retard=""
  while IFS= read -r _m25_e33_s; do
    [[ -n "$_m25_e33_s" ]] || continue
    _m25_e33_m="$(_m25p_kv_meta "$_m25_e33_s")"
    if ! _m25p_jq "$_m25_e33_m" '(.meta.proprietaire // "") != "" and ((.meta.rotation // "") | test("^[0-9]+h$"))'; then
      _m25_e33_sans="$_m25_e33_sans $_m25_e33_s"
    elif ! _m25p_jq "$_m25_e33_m" '(now - .cree) <= ((.meta.rotation | rtrimstr("h") | tonumber) * 3600)'; then
      _m25_e33_retard="$_m25_e33_retard $_m25_e33_s"
    fi
  done <<<"$_m25_e33_feuilles"
  check_cmd "les $_m25_e33_nb secrets de kv/plateforme/ portent proprietaire et rotation${_m25_e33_sans:+ — manquent :$_m25_e33_sans}" \
    test -z "$_m25_e33_sans"
  check_cmd "aucun secret de kv/plateforme/ n'a dépassé sa période${_m25_e33_retard:+ — en retard :$_m25_e33_retard}" \
    test -z "$_m25_e33_retard"
fi

_m25_e33_trace() { [[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]; }
check_cmd "rotation du trousseau (sys/rotate) tracée dans l'audit depuis 30 jours" _m25_e33_trace \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |~ `"path":"sys/rotate(/keyring)?"`' 720h)"
check_cmd "rotation de la clé transit sops-plateforme tracée dans l'audit depuis 30 jours" _m25_e33_trace \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |= `transit/keys/sops-plateforme/rotate`' 720h)"
