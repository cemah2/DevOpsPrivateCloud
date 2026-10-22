#!/usr/bin/env bash
# outils/vault-pass-client.sh — script client des mots de passe Ansible Vault (M04-E30), réécrit en
# M25-E11 (PLAT-2611) : les mots de passe viennent d'OpenBao.
#
# Ansible l'appelle pour chaque identité de vault_identity_list (ansible.cfg) :
#   outils/vault-pass-client.sh --vault-id <identité>
# et lit le mot de passe sur la sortie standard. Contrat inchangé : code 0 trouvé, 1 introuvable ou
# refusé, 2 erreur d'usage ; jamais de mot de passe dans un message.
#
# Source normale : OpenBao, secret kv/plateforme/ansible-vault/<identité>, clé « mot-de-passe »,
# lu avec le jeton DÉJÀ présent (la CLI bao le trouve dans BAO_TOKEN ou dans ~/.vault-token) :
#   - une personne : « bao login -method=oidc » avant ansible-playbook (SSO, OTP pour les admins) ;
#   - un job : jeton du rôle JWT obtenu dans before_script (outils/openbao-ci.sh).
# Le script ne se connecte jamais lui-même : il n'a aucun secret pour le faire.
#
# Mode secours (coffre fermé, RB-255 / docs/securite/secrets/ansible-et-openbao.md) : seulement si
# VAULT_PASS_SECOURS=1 est posé EXPLICITEMENT, les anciennes sources sont lues, dans l'ordre :
#   VAULT_PASS_<ID> (chemin d'un fichier), VAULT_MDP_<ID> (valeur), ~/.config/workbook/ansible-vault[-<id>].pass
# Un fichier lisible par le groupe ou les autres est refusé.
set -euo pipefail

id=""
while (($# > 0)); do
  case "$1" in
    --vault-id) id="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --vault-id=*) id="${1#*=}"; shift ;;
    *) echo "Usage : $0 --vault-id IDENTITÉ" >&2; exit 2 ;;
  esac
done
[[ "$id" =~ ^[a-z0-9_-]+$ ]] || { echo "vault-pass-client : identité absente ou invalide" >&2; exit 2; }
maj="${id^^}"
maj="${maj//-/_}"

# lire_fichier CHEMIN — première ligne du fichier ; refuse s'il est lisible par d'autres.
lire_fichier() {
  local f="$1" mode ligne
  [[ -f "$f" && -r "$f" ]] || return 1
  mode="$(stat -c '%a' "$f")"
  if (((8#$mode & 8#077) != 0)); then
    echo "vault-pass-client : refus, $f est accessible au groupe ou aux autres (mode $mode, attendu 600)" >&2
    exit 1
  fi
  IFS= read -r ligne <"$f" || [[ -n "$ligne" ]]
  [[ -n "$ligne" ]] || { echo "vault-pass-client : $f est vide" >&2; exit 1; }
  printf '%s\n' "$ligne"
}

secours() {
  local var_fichier="VAULT_PASS_${maj}" var_valeur="VAULT_MDP_${maj}" f
  if [[ -n "${!var_fichier:-}" ]]; then
    lire_fichier "${!var_fichier}" && exit 0
    echo "vault-pass-client : $var_fichier désigne un fichier illisible" >&2
    exit 1
  fi
  if [[ -n "${!var_valeur:-}" ]]; then
    printf '%s\n' "${!var_valeur}"
    exit 0
  fi
  for f in "$HOME/.config/workbook/ansible-vault-${id}.pass" "$HOME/.config/workbook/ansible-vault.pass"; do
    [[ "$f" == */ansible-vault.pass && "$id" != lab ]] && continue
    if [[ -e "$f" ]]; then
      lire_fichier "$f" && exit 0
      echo "vault-pass-client : $f est illisible" >&2
      exit 1
    fi
  done
  echo "vault-pass-client : mode secours, aucune source pour « $id » (copie hors ligne : voir ansible-et-openbao.md)" >&2
  exit 1
}

if [[ "${VAULT_PASS_SECOURS:-0}" == 1 ]]; then
  echo "vault-pass-client : MODE SECOURS demandé pour « $id » (OpenBao ignoré)" >&2
  secours
fi

command -v bao >/dev/null 2>&1 || { echo "vault-pass-client : client bao absent (rôle openbao_client)" >&2; exit 1; }
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"

# Un jeton valide ? (lookup-self est permis par la politique « default ».)
if ! bao token lookup >/dev/null 2>&1; then
  echo "vault-pass-client : pas de jeton OpenBao valide pour « $id ». Connecte-toi : bao login -method=oidc" >&2
  echo "                    (coffre fermé ? procédure de secours : docs/securite/secrets/ansible-et-openbao.md)" >&2
  exit 1
fi

if ! mdp="$(bao kv get -mount=kv -field=mot-de-passe "plateforme/ansible-vault/${id}" 2>/dev/null)"; then
  echo "vault-pass-client : OpenBao refuse kv/plateforme/ansible-vault/${id} (politique ansible-${id} absente de ton jeton ?)" >&2
  exit 1
fi
[[ -n "$mdp" ]] || { echo "vault-pass-client : mot de passe vide pour « $id »" >&2; exit 1; }
printf '%s\n' "$mdp"
