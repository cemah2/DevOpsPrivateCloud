#!/usr/bin/env bash
# =============================================================================
# outils/verifier-roles-ci.sh — plateforme/secrets (M25-E36, INC-5236)
# Contrôle de dérive de la méthode JWT gitlab/ et de ses rôles, sur le coffre RÉEL, en lecture seule.
# Ce que tofu plan voit aussi, mais dit ici en clair et avec la raison métier :
#   - méthode : découverte OIDC de git01 (ni jwks_url, ni clé recopiée), émetteur lié, et clés
#     réellement joignables depuis le poste qui lance le contrôle ;
#   - chaque rôle ci-* : audience exacte des id_tokens, bound_claims_type glob, TOUTES les valeurs
#     liées en chaînes (un booléen ou un nombre ne correspond jamais à la revendication de GitLab),
#     ref_protected = "true", au moins une politique autre que default, et chaque politique existe.
# Ce que ça n'attrape pas : un project_id faux (comparé par tofu plan) ; le contenu des politiques
# (tests/politiques, M25-E40).
#
# Usage : outils/verifier-roles-ci.sh [montage]     (défaut : gitlab)
#   BAO_ADDR et un jeton (BAO_TOKEN ou ~/.vault-token) qui lit auth/<montage>/config, liste et lit
#   auth/<montage>/role, lit sys/policies/acl (tofu-secrets dans le pipeline, plateforme-admin sur adm01).
# Code retour : 0 si conforme, 1 si dérive, 2 si le contrôle n'a pas pu se faire. N'affiche aucun secret.
# =============================================================================
set -Eeuo pipefail

MONTAGE="${1:-gitlab}"
EMETTEUR="https://git01.par1.medisphere.internal"
AUDIENCE="openbao.medisphere.internal"
ecarts=0

for outil in bao jq curl; do
  command -v "$outil" >/dev/null || { echo "$outil requis" >&2; exit 2; }
done
ecart() { echo "ÉCART  $*"; ecarts=$((ecarts + 1)); }
ok() { echo "ok     $*"; }

conf="$(bao read -format=json "auth/$MONTAGE/config")" || { echo "auth/$MONTAGE/config illisible" >&2; exit 2; }

# --- La méthode -------------------------------------------------------------------------------------
if jq -e --arg e "$EMETTEUR" '.data.oidc_discovery_url == $e and (.data.jwks_url // "") == ""
      and ((.data.jwt_validation_pubkeys // []) | length) == 0' >/dev/null <<<"$conf"; then
  ok "$MONTAGE/ : découverte OIDC de $EMETTEUR"
else
  ecart "$MONTAGE/ : attendu oidc_discovery_url=$EMETTEUR sans jwks_url ni clé ; trouvé discovery=$(jq -r '.data.oidc_discovery_url // ""' <<<"$conf") jwks_url=$(jq -r '.data.jwks_url // ""' <<<"$conf")"
fi
if jq -e --arg e "$EMETTEUR" '.data.bound_issuer == $e' >/dev/null <<<"$conf"; then
  ok "$MONTAGE/ : émetteur lié $EMETTEUR"
else
  ecart "$MONTAGE/ : bound_issuer = $(jq -r '.data.bound_issuer // "(vide)"' <<<"$conf")"
fi

# Les clés annoncées par la découverte sont-elles servies ? (ce que fera OpenBao à la connexion)
jwks="$(curl -sf --max-time 10 "$EMETTEUR/.well-known/openid-configuration" | jq -r '.jwks_uri // empty' || true)"
if [[ -n "$jwks" ]] && curl -sf --max-time 10 "$jwks" | jq -e '.keys | length > 0' >/dev/null 2>&1; then
  ok "clés de signature servies par $jwks"
else
  ecart "découverte ou clés de $EMETTEUR injoignables depuis $(hostname -s) (à vérifier aussi depuis vault01)"
fi

# --- Les rôles --------------------------------------------------------------------------------------
roles="$(bao list -format=json "auth/$MONTAGE/role" | jq -r '.[]')" || { echo "liste des rôles illisible" >&2; exit 2; }
politiques="$(bao list -format=json sys/policies/acl | jq -r '.[]')" || { echo "liste des politiques illisible" >&2; exit 2; }

while IFS= read -r role; do
  [[ "$role" == ci-* ]] || continue
  r="$(bao read -format=json "auth/$MONTAGE/role/$role")" || { ecart "$role : illisible"; continue; }
  n=$ecarts
  jq -e --arg a "$AUDIENCE" '.data.bound_audiences == [$a]' >/dev/null <<<"$r" \
    || ecart "$role : bound_audiences = $(jq -c '.data.bound_audiences' <<<"$r") (attendu [\"$AUDIENCE\"])"
  jq -e '.data.bound_claims_type == "glob"' >/dev/null <<<"$r" \
    || ecart "$role : bound_claims_type = $(jq -r '.data.bound_claims_type' <<<"$r") (attendu glob : main,v*,conf/*)"
  # Typage : chaque valeur liée doit être une chaîne (les revendications de GitLab le sont toutes ici).
  pas_chaine="$(jq -r '.data.bound_claims // {} | to_entries[]
      | select([.value] | flatten | any(type != "string")) | "\(.key)=\(.value | tojson)"' <<<"$r")"
  [[ -z "$pas_chaine" ]] || ecart "$role : valeurs liées qui ne sont pas des chaînes : $(tr '\n' ' ' <<<"$pas_chaine")"
  jq -e '([.data.bound_claims.ref_protected] | flatten) == ["true"]' >/dev/null <<<"$r" \
    || ecart "$role : ref_protected = $(jq -c '.data.bound_claims.ref_protected' <<<"$r") (attendu \"true\")"
  utiles="$(jq -r '(.data.token_policies // [])[] | select(. != "default")' <<<"$r")"
  if [[ -z "$utiles" ]]; then
    ecart "$role : aucune politique utile (token_policies = $(jq -c '.data.token_policies' <<<"$r")) : connexion OK, lecture refusée"
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] || grep -qxF -- "$p" <<<"$politiques" || ecart "$role : la politique $p n'existe pas"
  done <<<"$utiles"
  ((ecarts > n)) || ok "$role"
done <<<"$roles"

echo "---"
if ((ecarts > 0)); then
  echo "$ecarts écart(s) : la configuration de $MONTAGE/ a dérivé. tofu plan dira quelle ressource, l'audit qui l'a écrite."
  exit 1
fi
echo "Méthode $MONTAGE/ et rôles ci-* conformes."
