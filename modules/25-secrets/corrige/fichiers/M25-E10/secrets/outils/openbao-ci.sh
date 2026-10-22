# shellcheck shell=bash
# outils/openbao-ci.sh — connexion d'un job GitLab à OpenBao par son jeton d'identité (M25-E10).
# À SOURCER dans before_script (« . outils/openbao-ci.sh <rôle> »), sur runner01 (exécuteur shell).
# Le job déclare :
#   id_tokens:
#     OPENBAO_ID_TOKEN:
#       aud: openbao.medisphere.internal
# Effets : jeton OpenBao de 10 min dans un fichier 600 du répertoire du job (jamais dans $HOME : sur
# un exécuteur shell, $HOME est partagé par tous les jobs du runner), exporté pour la CLI bao
# (BAO_TOKEN) et pour le fournisseur OpenTofu vault (VAULT_TOKEN, VAULT_ADDR). Rien n'est affiché.
# En fin de job (after_script, autre shell) : « . outils/openbao-ci.sh --fin » révoque et efface.
# Ne jamais lancer un job avec « set -x » ni CI_DEBUG_TRACE.

_openbao_ci_fichier="${CI_PROJECT_DIR:-.}/.bao-jeton"
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"
export VAULT_ADDR="$BAO_ADDR"

if [ "${1:-}" = "--fin" ]; then
  if [ -s "$_openbao_ci_fichier" ]; then
    BAO_TOKEN="$(cat "$_openbao_ci_fichier")" bao token revoke -self >/dev/null 2>&1 \
      || echo "openbao-ci : révocation impossible (jeton déjà expiré ?)"
  fi
  rm -f "$_openbao_ci_fichier"
  unset BAO_TOKEN VAULT_TOKEN
  return 0
fi

_openbao_ci_role="${1:-}"
if [ -z "$_openbao_ci_role" ]; then
  echo "openbao-ci : usage : . outils/openbao-ci.sh <rôle> | --fin" >&2
  return 1
fi
if [ -z "${OPENBAO_ID_TOKEN:-}" ]; then
  echo "openbao-ci : OPENBAO_ID_TOKEN absent (id_tokens non déclaré pour ce job ?)" >&2
  return 1
fi
command -v bao >/dev/null 2>&1 || { echo "openbao-ci : client bao absent (rôle openbao_client)" >&2; return 1; }

# Le jeton d'identité passe par l'entrée standard (« jwt=- ») : jamais dans les arguments (ps).
umask 077
if ! printf '%s' "$OPENBAO_ID_TOKEN" |
  bao write -field=token "auth/gitlab/login" role="$_openbao_ci_role" jwt=- >"$_openbao_ci_fichier"; then
  rm -f "$_openbao_ci_fichier"
  echo "openbao-ci : connexion refusée pour le rôle $_openbao_ci_role (référence protégée ? bon projet ?)" >&2
  return 1
fi
BAO_TOKEN="$(cat "$_openbao_ci_fichier")"
export BAO_TOKEN
export VAULT_TOKEN="$BAO_TOKEN"
echo "openbao-ci : connecté au rôle $_openbao_ci_role (jeton de 10 min, politiques : $(bao token lookup -format=json | jq -r '.data.policies | join(",")'))"
