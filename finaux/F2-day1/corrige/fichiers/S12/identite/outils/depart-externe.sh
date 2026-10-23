#!/usr/bin/env bash
# outils/depart-externe.sh — ce que l'annuaire ne coupe pas, au départ d'une équipe externe
# (F2-S12, SEC-3212 ; RB-242 étapes A.2 à A.4, RB-329 § C). Rangé dans plateforme/identite.
#
# À lancer APRÈS la fusion et l'application de la MR de départ (personnes « disabled », groupe vidé,
# espace retiré), depuis adm01, par une personne de plateforme-admins. Écrit sur stdout des lignes de
# PREUVE horodatées (sans aucune valeur de secret) à coller dans docs/accueil/departs/<société>.md.
#
# Usage : depart-externe.sh [--simulation] --projet GROUPE/PROJET IDENTIFIANT…
#
# Pour chaque personne : sessions Keycloak fermées (royaume medisphere) ; GitLab : jetons personnels
# révoqués, clés SSH supprimées, appartenance au projet retirée, compte BLOQUÉ (jamais supprimé :
# l'historique des MR et des commits garde son auteur).
# Identités : KEYCLOAK_CLIENT_ID / KEYCLOAK_CLIENT_SECRET (svc-tofu-keycloak, ~/.config/workbook/
# keycloak-tofu.env) ; GITLAB_TOKEN (jeton d'administration, portée api). Jamais en argument.
# Codes retour : 0 succès, 1 au moins une étape en échec, 2 usage.
set -euo pipefail

KC="${KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
GL="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
usage() { echo "Usage : $0 [--simulation] --projet GROUPE/PROJET IDENTIFIANT…" >&2; exit 2; }
enc() { jq -rn --arg s "$1" '$s|@uri'; }
preuve() { printf '%s | %-14s | %-10s | %s\n' "$(date -Is)" "$1" "$2" "$3"; }

jeton_kc() {
  curl -sf --max-time 20 -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
    -d grant_type=client_credentials "$KC/realms/master/protocol/openid-connect/token" | jq -r '.access_token // empty'
}
kc() {
  local m="$1" p="$2"
  curl -sf --max-time 20 -X "$m" -K <(printf 'header = "Authorization: Bearer %s"\n' "$JETON_KC") \
    "$KC/admin/realms/medisphere/$p"
}
gl() {
  local m="$1" p="$2"
  shift 2
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GL/api/v4/$p" "$@"
}

main() {
  local simulation=0 projet="" echec=0 u kid uid pid n t k
  while (($#)); do
    case "$1" in
      --simulation) simulation=1; shift ;;
      --projet) (($# >= 2)) || usage; projet="$2"; shift 2 ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  (($# >= 1)) && [[ -n "$projet" ]] || usage
  [[ -n "${KEYCLOAK_CLIENT_ID:-}" && -n "${KEYCLOAK_CLIENT_SECRET:-}" && -n "${GITLAB_TOKEN:-}" ]] ||
    { echo "identités absentes (KEYCLOAK_CLIENT_ID/SECRET, GITLAB_TOKEN)" >&2; exit 1; }
  JETON_KC="$(jeton_kc)" || JETON_KC=""
  [[ -n "$JETON_KC" ]] || { echo "jeton Keycloak refusé" >&2; exit 1; }
  pid="$(gl GET "projects/$(enc "$projet")" | jq -r '.id // empty')" || pid=""
  [[ -n "$pid" ]] || { echo "projet introuvable : $projet" >&2; exit 1; }

  preuve "début" "-" "départ de : $* (projet $projet)$( ((simulation)) && echo ' — SIMULATION')"
  for u in "$@"; do
    # --- Keycloak : sessions et jetons de rafraîchissement ---
    kid="$(kc GET "users?username=$(enc "$u")&exact=true" | jq -r '.[0].id // empty')" || kid=""
    if [[ -z "$kid" ]]; then
      preuve "$u" keycloak "inconnue de Keycloak (jamais connectée) : rien à fermer"
    else
      n="$(kc GET "users/$kid/sessions" | jq 'length')" || n="?"
      if ((simulation)); then
        preuve "$u" keycloak "$n session(s) seraient fermées"
      elif kc POST "users/$kid/logout" >/dev/null; then
        preuve "$u" keycloak "$n session(s) fermées ; reste : $(kc GET "users/$kid/sessions" | jq 'length')"
      else
        preuve "$u" keycloak "ÉCHEC de la fermeture des sessions"; echec=1
      fi
    fi

    # --- GitLab ---
    uid="$(gl GET "users?username=$(enc "$u")" | jq -r '.[0].id // empty')" || uid=""
    if [[ -z "$uid" ]]; then
      preuve "$u" gitlab "pas d'utilisateur GitLab"
      continue
    fi
    while IFS= read -r t; do
      [[ -n "$t" ]] || continue
      if ((simulation)); then preuve "$u" gitlab "jeton personnel $t serait révoqué"; continue; fi
      if gl DELETE "personal_access_tokens/$t" >/dev/null; then preuve "$u" gitlab "jeton personnel $t révoqué"
      else preuve "$u" gitlab "ÉCHEC révocation du jeton $t"; echec=1; fi
    done < <(gl GET "personal_access_tokens?user_id=$uid&state=active&per_page=100" | jq -r '.[].id')
    while IFS= read -r k; do
      [[ -n "$k" ]] || continue
      if ((simulation)); then preuve "$u" gitlab "clé SSH $k serait supprimée"; continue; fi
      if gl DELETE "users/$uid/keys/$k" >/dev/null; then preuve "$u" gitlab "clé SSH $k supprimée"
      else preuve "$u" gitlab "ÉCHEC suppression de la clé $k"; echec=1; fi
    done < <(gl GET "users/$uid/keys" | jq -r '.[].id')
    if gl GET "projects/$pid/members/$uid" >/dev/null 2>&1; then
      if ((simulation)); then preuve "$u" gitlab "serait retirée de $projet"
      elif gl DELETE "projects/$pid/members/$uid" >/dev/null; then preuve "$u" gitlab "retirée de $projet"
      else preuve "$u" gitlab "ÉCHEC retrait de $projet"; echec=1; fi
    fi
    if ((simulation)); then
      preuve "$u" gitlab "serait bloquée (état actuel : $(gl GET "users/$uid" | jq -r .state))"
    elif gl POST "users/$uid/block" >/dev/null || [[ "$(gl GET "users/$uid" | jq -r .state)" == blocked ]]; then
      preuve "$u" gitlab "compte bloqué (état : $(gl GET "users/$uid" | jq -r .state))"
    else
      preuve "$u" gitlab "ÉCHEC du blocage"; echec=1
    fi
  done
  preuve "fin" "-" "$( ((echec)) && echo 'AU MOINS UNE ÉTAPE EN ÉCHEC : voir ci-dessus' || echo 'toutes les étapes réussies')"
  return "$echec"
}

main "$@"
