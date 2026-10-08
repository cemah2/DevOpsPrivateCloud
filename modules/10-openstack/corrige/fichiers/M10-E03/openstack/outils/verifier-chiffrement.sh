#!/usr/bin/env bash
# outils/verifier-chiffrement.sh — échoue si un secret est en clair dans etc/ ou donnees/
# (M10-E03). Lancé par le pipeline de MR et par un crochet pre-commit facultatif.
#
# Règles :
#   1. etc/kolla/passwords.yml et donnees/vault-*.yml : chiffrés par Ansible Vault, identité « critique » ;
#   2. tout fichier sous etc/ qui contient une clé privée PEM : chiffré par Ansible Vault ;
#   3. tout trousseau Ceph (*.keyring) sous etc/ : chiffré, OU gabarit dont la clé est une
#      expression Jinja (« key = {{ … }} », valeur tirée de passwords.yml chiffré, M10-E10).
# Usage : outils/verifier-chiffrement.sh  (depuis la racine du dépôt ; code 1 si un défaut)
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"

defauts=0
signaler() { echo "EN CLAIR : $1 ($2)" >&2; defauts=$((defauts + 1)); }

# chiffre_critique FICHIER — première ligne d'un fichier Vault 1.2 de l'identité « critique ».
chiffre_critique() {
  local entete
  IFS= read -r entete <"$1" || true
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête
  [[ "$entete" == '$ANSIBLE_VAULT;1.2;AES256;critique' ]]
}

# 1. Fichiers de secrets attendus.
for f in etc/kolla/passwords.yml donnees/vault-*.yml; do
  [[ -e "$f" ]] || continue
  chiffre_critique "$f" || signaler "$f" "doit être chiffré sous l'identité critique"
done
[[ -e etc/kolla/passwords.yml ]] || signaler etc/kolla/passwords.yml "absent : Kolla ne pourra pas déployer"

# 2 et 3. Clés privées et trousseaux sous etc/.
while IFS= read -r -d '' f; do
  chiffre_critique "$f" && continue
  if grep -q -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f"; then
    signaler "$f" "clé privée PEM"
  elif [[ "$f" == *.keyring ]] && grep -Eq '^[[:space:]]*key[[:space:]]*=' "$f" \
       && ! grep -Eq '^[[:space:]]*key[[:space:]]*=[[:space:]]*\{\{' "$f"; then
    signaler "$f" "trousseau Ceph avec une clé littérale"
  fi
done < <(find etc -type f -print0)

if ((defauts > 0)); then
  echo "$defauts fichier(s) à chiffrer : ansible-vault encrypt --encrypt-vault-id critique <fichier>" >&2
  exit 1
fi
echo "Aucun secret en clair sous etc/ et donnees/."
