#!/usr/bin/env bash
# outils/vault-pass-client.sh — script client des mots de passe Ansible Vault (M04-E30),
# copié tel quel dans plateforme/openstack (M10-E03) : même contrat, mêmes fichiers.
#
# Ansible l'appelle pour chaque identité de vault_identity_list (ansible.cfg) :
#   outils/vault-pass-client.sh --vault-id <identité>
# et lit le mot de passe sur la sortie standard (le nom en « -client » le lui indique).
# Le même script sert partout ; il cherche, dans l'ordre, pour l'identité « x » (X = X en
# majuscules, « - » remplacé par « _ ») :
#   1. VAULT_PASS_X : CHEMIN d'un fichier contenant le mot de passe (variable CI de type fichier)
#   2. VAULT_MDP_X  : le mot de passe lui-même (secret de type variable d'environnement, Semaphore)
#   3. ~/.config/workbook/ansible-vault-x.pass (poste d'administration) ;
#      pour « lab », ~/.config/workbook/ansible-vault.pass (nom historique, E12)
# Un fichier lisible par le groupe ou les autres est refusé. Rien n'est écrit ailleurs que sur
# la sortie standard ; les messages d'erreur ne contiennent jamais le mot de passe.
# Codes : 0 trouvé · 1 introuvable ou refusé · 2 erreur d'usage.
# Sans mot de passe pour une identité, Ansible affiche un avertissement et continue : seules
# les tâches qui utilisent une variable de cette identité échouent.
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
  local f="$1" mode
  [[ -f "$f" && -r "$f" ]] || return 1
  mode="$(stat -c '%a' "$f")"
  if (((8#$mode & 8#077) != 0)); then
    echo "vault-pass-client : refus, $f est accessible au groupe ou aux autres (mode $mode, attendu 600)" >&2
    exit 1
  fi
  local ligne
  IFS= read -r ligne <"$f" || [[ -n "$ligne" ]]
  [[ -n "$ligne" ]] || { echo "vault-pass-client : $f est vide" >&2; exit 1; }
  printf '%s\n' "$ligne"
}

var_fichier="VAULT_PASS_${maj}"
var_valeur="VAULT_MDP_${maj}"

if [[ -n "${!var_fichier:-}" ]]; then
  lire_fichier "${!var_fichier}" && exit 0
  echo "vault-pass-client : $var_fichier désigne un fichier illisible" >&2
  exit 1
fi
if [[ -n "${!var_valeur:-}" ]]; then
  printf '%s\n' "${!var_valeur}"
  exit 0
fi
candidats=("$HOME/.config/workbook/ansible-vault-${id}.pass")
if [[ "$id" == lab ]]; then candidats+=("$HOME/.config/workbook/ansible-vault.pass"); fi
for f in "${candidats[@]}"; do
  if [[ -e "$f" ]]; then
    lire_fichier "$f" && exit 0
    echo "vault-pass-client : $f est illisible" >&2
    exit 1
  fi
done

echo "vault-pass-client : aucun mot de passe pour l'identité « $id » ($var_fichier, $var_valeur, ~/.config/workbook/)" >&2
exit 1
