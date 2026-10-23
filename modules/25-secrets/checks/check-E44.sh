# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et requêtes LogQL entre apostrophes
#
# check-E44.sh — M25-E44 « Sous le capot : barrière, trousseau, Raft et baux » : le trousseau a tourné
# (terme ≥ 2) ; la rotation (sys/rotate) et une génération de jeton racine sont tracées dans l'audit
# depuis 30 jours ; aucun jeton racine vivant ; compte rendu sur main avec ses sections, des chiffres et
# aucun secret.
# Lecture seule : bao_api (sys/key-status si wb-checks a l'extrait M25-E44 ; accessors), Loki (audit),
# gitlab_api.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E44 — Sous le capot : barrière, trousseau, Raft et baux"
require_cmd curl jq
_m25p_connexion

_m25x_e44_ks="$(_m25p_bao sys/key-status)"
if [[ "$_m25x_e44_ks" == null ]]; then
  skip "trousseau tourné (sys/key-status : terme ≥ 2)" "wb-checks ne lit pas sys/key-status (extrait M25-E44)"
else
  check_cmd "trousseau tourné au moins une fois (sys/key-status : terme $(jq -r '.data.term // "?"' <<<"$_m25x_e44_ks"))" \
    _m25p_jq "$_m25x_e44_ks" '(.data.term // 0) >= 2'
fi
check_cmd "rotation du trousseau (sys/rotate) tracée dans l'audit depuis 30 jours" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |~ `"path":"sys/rotate(/keyring)?"`' 720h)"
check_cmd "génération de jeton racine (sys/generate-root-token) tracée dans l'audit depuis 30 jours" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |= `sys/generate-root-token/update`' 720h)"

check_cmd "aucun jeton racine vivant (révoqué après la rotation)" _m25x_aucune_racine

_m25x_e44_cr="docs/securite/secrets/analyses/sous-le-capot-openbao.md"
_m25x_e44_txt="$(_m25p_fichier "$_M25P_DOC" "$_m25x_e44_cr" || true)"
check_cmd "compte rendu sur main ($_m25x_e44_cr)" test -n "$_m25x_e44_txt"
for _m25x_e44_s in 'Les clés' 'La rotation du trousseau' 'Le disque d.un nœud' 'Raft' 'Le nœud en attente' 'Les baux' 'Réponses aux questions'; do
  check_output "compte rendu : section « ${_m25x_e44_s} »" "^## +${_m25x_e44_s}" printf '%s\n' "$_m25x_e44_txt"
done
check_output "compte rendu : chiffres relevés (term, index Raft, codes HTTP 200/307)" \
  '(term|terme).{0,40}[0-9]' printf '%s\n' "$_m25x_e44_txt"
check_output "compte rendu : la redirection (307) ou la transmission d'un nœud en attente est observée" \
  '307|X-Vault-No-Request-Forwarding|transmi' printf '%s\n' "$_m25x_e44_txt"
check_cmd "compte rendu : aucun jeton, aucune clé, aucun secret" _m25x_sans_secret "$_m25x_e44_txt"
