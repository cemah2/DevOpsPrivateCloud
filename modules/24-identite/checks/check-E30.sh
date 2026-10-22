# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E30.sh — M24-E30 : Revue des accès automatisée : qui a accès à quoi
# À lancer depuis adm01. Lecture seule : outil et planification de pipeline de plateforme/identite,
# rapports sur main de plateforme/medisphere, courriel dans Mailpit.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E30 — Revue des accès automatisée : qui a accès à quoi"
require_cmd jq curl

_m24p_e30_outil="$(_m24p_arbre plateforme/identite outils/revue-acces)"
check_cmd "plateforme/identite : outils/revue-acces/ sur main, avec son README" _m24d_contient "$_m24p_e30_outil" 'outils/revue-acces/README\.md$'
check_cmd "outils/revue-acces/ : au moins un programme (hors README)" _m24d_contient \
  "$(grep -Ev 'README\.md$' <<<"$_m24p_e30_outil" || true)" '\.(py|sh|go|ts|js)$'

# _m24p_e30_statut ID — statut du dernier pipeline lancé par la planification ID.
_m24p_e30_statut() {
  gitlab_api "projects/$(_m24d_uri plateforme/identite)/pipeline_schedules/$1" 2>/dev/null \
    | jq -r '.last_pipeline.status // empty' 2>/dev/null || true
}

_m24p_e30_plan="$(gitlab_api "projects/$(_m24d_uri plateforme/identite)/pipeline_schedules?scope=active&per_page=100" 2>/dev/null || true)"
# Un planning mensuel : jour du mois fixé (3e champ ≠ *), sur main.
check_cmd "plateforme/identite : pipeline planifié mensuel actif sur main" _m24d_json "$_m24p_e30_plan" \
  'any(.[]; .active == true and (.ref == "main" or .ref == "refs/heads/main") and ((.cron | split(" "))[2] != "*"))'
_m24p_e30_id="$(jq -r '[.[] | select(.active == true and ((.cron | split(" "))[2] != "*"))][0].id // empty' <<<"$_m24p_e30_plan" 2>/dev/null || true)"
if [[ -n "$_m24p_e30_id" ]]; then
  check_output "Dernière exécution du pipeline planifié réussie" '^success$' \
    _m24p_e30_statut "$_m24p_e30_id"
else
  _ko "Aucun pipeline planifié mensuel lisible : dernière exécution non contrôlée"
fi

_m24p_e30_rapports="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/revue-acces" | grep -E '/20[0-9]{2}-[01][0-9]\.md$' | sort || true)"
_m24p_e30_dernier="$(tail -n 1 <<<"$_m24p_e30_rapports")"
_m24p_e30_c=""
[[ -n "$_m24p_e30_dernier" ]] && _m24p_e30_c="$(_m24p_doc "$_m24p_e30_dernier")"
check_cmd "Rapport AAAA-MM.md sur main de plateforme/medisphere, avec une section Écarts" _m24p_tous "$_m24p_e30_c" '^#+ *[ÉE]carts'
check_cmd "Rapport : aucun secret (jeton GitLab, clé age, mot de passe, secret de client)" _m24p_aucun \
  'glpat-|AGE-SECRET-KEY|client_secret|mot_de_passe *[:=]|password *[:=]|BEGIN [A-Z ]*PRIVATE KEY' "$_m24p_e30_c"
check_cmd "Rapport : l'écart volontaire d'essai a disparu du dernier rapport (essai-revue)" _m24p_aucun 'essai-revue' "$_m24p_e30_c"
check_cmd "Mailpit : courriel « Revue des accès » reçu par securite@medisphere.internal" _m24d_json \
  "$(mailpit_api "search?query=$(_m24d_uri 'to:securite@medisphere.internal subject:"Revue des accès"')" 2>/dev/null || true)" \
  '.messages_count > 0'
