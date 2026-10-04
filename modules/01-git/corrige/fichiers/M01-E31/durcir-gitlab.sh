#!/usr/bin/env bash
# =============================================================================
# durcir-gitlab.sh — applique et vérifie les réglages de sécurité de la forge
# M01-E31 (ticket SEC-258). Versionné dans plateforme/medisphere : forge/durcissement/.
#
# Usage (depuis adm01) :
#   forge/durcissement/durcir-gitlab.sh            applique puis vérifie
#   forge/durcissement/durcir-gitlab.sh --verifier vérifie seulement (code ≠ 0 si écart)
#
# Idempotent : relancé après une réinstallation ou une restauration (RB-010), il
# remet les réglages applicatifs (stockés en base, pas dans gitlab.rb).
# Jeton : jeton d'administration (portées api + admin_mode), fichier 600.
# Chaque réglage est justifié dans docs/socle/securite/durcissement-gitlab.md.
# =============================================================================
set -euo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
MODE="${1:-appliquer}"

[[ -r "$JETON_FICHIER" ]] || { echo "Jeton d'administration illisible : $JETON_FICHIER" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq requis" >&2; exit 2; }

# Réglage → valeur attendue (telle que renvoyée par GET /application/settings).
declare -A ATTENDU=(
  # Comptes et authentification
  [signup_enabled]=false                       # pas d'auto-inscription (E05)
  [require_two_factor_authentication]=true     # 2FA pour tous les comptes humains
  [two_factor_grace_period]=48                 # heures pour s'enrôler
  [admin_mode]=true                            # privilèges d'admin sur réauthentification
  [password_authentication_enabled_for_git]=false   # Git HTTPS : jetons seulement
  [remember_me_enabled]=false                  # pas de session « se souvenir de moi »
  [session_expire_delay]=480                   # minutes (8 h) ; redémarrage requis
  # Visibilité
  [default_project_visibility]=private
  [default_group_visibility]=private
  # Clés SSH
  [dsa_key_restriction]=-1                     # DSA interdit
  [rsa_key_restriction]=3072                   # RSA ≥ 3072 bits
  [ecdsa_key_restriction]=256
  # Runners
  [allow_runner_registration_token]=false      # seul le flux glrt- (E23) reste possible
  # Souveraineté : rien ne part vers des tiers sans décision
  [usage_ping_enabled]=false
  [version_check_enabled]=false                # compensé : abonnement aux annonces de sécurité
  [gravatar_enabled]=false
  [snowplow_enabled]=false
  # Réseau
  [allow_local_requests_from_web_hooks_and_services]=false
  [allow_local_requests_from_system_hooks]=false
  # Limitation de débit des requêtes non authentifiées
  [throttle_unauthenticated_api_enabled]=true
  [throttle_unauthenticated_api_period_in_seconds]=60
  [throttle_unauthenticated_api_requests_per_period]=300
  [throttle_unauthenticated_web_enabled]=true
  [throttle_unauthenticated_web_period_in_seconds]=60
  [throttle_unauthenticated_web_requests_per_period]=600
)
VISIBILITES_INTERDITES='["public"]'

api() {   # api MÉTHODE CHEMIN [arguments curl...]
  local m="$1" p="$2"; shift 2
  curl -sf --max-time 20 -X "$m" -H "PRIVATE-TOKEN: $(<"$JETON_FICHIER")" "$@" "$URL/api/v4/$p"
}

if [[ "$MODE" != --verifier ]]; then
  args=()
  for cle in "${!ATTENDU[@]}"; do
    args+=(--data-urlencode "$cle=${ATTENDU[$cle]}")
  done
  args+=(--data-urlencode "restricted_visibility_levels[]=public")
  api PUT application/settings "${args[@]}" >/dev/null \
    || { echo "Échec de la mise à jour (jeton sans portée admin_mode ? valeur refusée ?)" >&2; exit 1; }
  echo "Réglages appliqués."
fi

reglages="$(api GET application/settings)" \
  || { echo "Lecture des réglages impossible (jeton sans portée admin_mode ?)" >&2; exit 1; }

ecarts=0
for cle in $(printf '%s\n' "${!ATTENDU[@]}" | sort); do
  obtenu="$(jq -r --arg k "$cle" '.[$k] | tostring' <<<"$reglages")"
  if [[ "$obtenu" == "${ATTENDU[$cle]}" ]]; then
    printf '[OK]  %-52s %s\n' "$cle" "$obtenu"
  else
    printf '[KO]  %-52s %s (attendu %s)\n' "$cle" "$obtenu" "${ATTENDU[$cle]}"
    ecarts=$((ecarts + 1))
  fi
done
if jq -e --argjson v "$VISIBILITES_INTERDITES" '(.restricted_visibility_levels // []) as $r | all($v[]; . as $x | $r | index($x))' <<<"$reglages" >/dev/null; then
  printf '[OK]  %-52s %s\n' restricted_visibility_levels "$(jq -c .restricted_visibility_levels <<<"$reglages")"
else
  printf '[KO]  %-52s %s (attendu : contient public)\n' restricted_visibility_levels "$(jq -c .restricted_visibility_levels <<<"$reglages")"
  ecarts=$((ecarts + 1))
fi

# Contrôles qui ne sont pas des réglages : projets ou groupes déjà publics.
publics="$(api GET 'projects?visibility=public&per_page=100' | jq length)"
if [[ "$publics" == 0 ]]; then echo "[OK]  aucun projet public"; else echo "[KO]  $publics projet(s) public(s)"; ecarts=$((ecarts + 1)); fi

if ((ecarts == 0)); then echo "Conforme."; else echo "$ecarts écart(s)."; exit 1; fi
