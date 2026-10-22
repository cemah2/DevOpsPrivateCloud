#!/usr/bin/env bash
# plateforme/k8s — outils/grafana-rotation-admin.sh (M21-E29, SEC-2229)
# Rotation du mot de passe du compte « admin » de Grafana.
#
# Pourquoi un script : le Secret grafana-admin (admin.existingSecret) ne sert qu'à la PREMIÈRE
# initialisation de la base de Grafana. Changer le Secret ensuite ne change PAS le mot de passe
# enregistré dans la base (SQLite, volume ceph-rbd) : il faut le changer par l'API, puis aligner le
# Secret (pour une réinstallation) et le Vault (source de vérité).
#
# Préalable : le NOUVEAU mot de passe est déjà dans le Vault « critique » (secrets/grafana.yml, clé
# $CLE_VAULT), saisi par « ansible-vault edit » ; l'ANCIEN est encore dans le Secret du cluster.
# Ordre : 1. lire l'ancien (Secret) ; 2. lire le nouveau (Vault) ; 3. changer dans Grafana (API) ;
# 4. vérifier avec le nouveau ; 5. réaligner le Secret (secrets-k8s.sh grafana).
# Aucun mot de passe n'est affiché ni passé en argument d'une commande (visible dans ps).
set -euo pipefail

GRAFANA_URL="${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}"
CLE_VAULT="${CLE_VAULT:-grafana_admin_password}"
VAULT_ID="${VAULT_ID:-critique@$HOME/src/ansible/outils/vault-pass-client.sh}"
cd "$(dirname "$0")/.."    # racine de plateforme/k8s

ancien="$(kubectl -n supervision get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
nouveau="$(uv run --project "$HOME/src/ansible" ansible-vault view --vault-id "$VAULT_ID" secrets/grafana.yml \
  | yq -r ".${CLE_VAULT}")"

[[ -n "$ancien" && -n "$nouveau" && "$nouveau" != null ]] || { echo "mot de passe ancien ou nouveau introuvable" >&2; exit 1; }
[[ "$ancien" != "$nouveau" ]] || { echo "le Vault contient encore l'ancien mot de passe : mets d'abord le nouveau" >&2; exit 1; }
# Politique de mots de passe de Grafana (auth.basic.password_policy) : 12 caractères au moins,
# une majuscule, une minuscule, un chiffre, un symbole.
if (( ${#nouveau} < 12 )) || ! [[ "$nouveau" =~ [A-Z] && "$nouveau" =~ [a-z] && "$nouveau" =~ [0-9] && "$nouveau" =~ [^A-Za-z0-9] ]]; then
  echo "le nouveau mot de passe ne respecte pas la politique de Grafana" >&2; exit 1
fi

# 3. Changement par l'API (PUT /api/user/password, le compte change son propre mot de passe).
#    Identifiants par un fichier de configuration curl (substitution de processus), corps JSON par
#    l'entrée standard : rien dans la liste des processus.
jq -n --arg a "$ancien" --arg n "$nouveau" '{oldPassword: $a, newPassword: $n, confirmNew: $n}' \
  | curl -sf --max-time 10 -K <(printf 'user = "admin:%s"\n' "$ancien") \
      -X PUT -H 'Content-Type: application/json' --data @- "$GRAFANA_URL/api/user/password" >/dev/null \
  || { echo "Grafana a refusé le changement (ancien mot de passe faux ? politique ?)" >&2; exit 1; }

# 4. Vérification : le nouveau fonctionne, l'ancien non.
curl -sf --max-time 10 -K <(printf 'user = "admin:%s"\n' "$nouveau") "$GRAFANA_URL/api/user" >/dev/null \
  || { echo "connexion avec le nouveau mot de passe impossible : NE PAS réaligner le Secret, enquêter" >&2; exit 1; }
if curl -sf --max-time 10 -K <(printf 'user = "admin:%s"\n' "$ancien") "$GRAFANA_URL/api/user" >/dev/null; then
  echo "l'ancien mot de passe fonctionne encore : anomalie" >&2; exit 1
fi

# 5. Secret aligné sur le Vault (réinstallation de Grafana sur un volume neuf).
outils/secrets-k8s.sh grafana
echo "rotation faite : base de Grafana, Vault et Secret alignés. Note la date au registre des secrets."
