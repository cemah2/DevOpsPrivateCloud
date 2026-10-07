#!/usr/bin/env bash
# cles-hote-socle.sh — produit inventories/lab/known_hosts, VÉRIFIÉ, pour les contrôleurs (M04-E27)
#
# Usage (sur adm01, depuis la racine du projet) : outils/cles-hote-socle.sh [--ecrire]
#
# Pour chaque hôte de l'inventaire lab (adresse ansible_host), récupère sa clé d'hôte ed25519
# par ssh-keyscan, puis la COMPARE à celle que adm01 a déjà acceptée (~/.ssh/known_hosts,
# confiance établie depuis le module 00, éventuellement hachée). Une clé absente ou différente
# arrête tout : on ne publie jamais une clé que personne n'a vérifiée.
# Sans --ecrire : affiche seulement le résultat. Avec : écrit inventories/lab/known_hosts.
set -euo pipefail

ecrire=0
[[ "${1:-}" == "--ecrire" ]] && ecrire=1
[[ -f inventories/lab/hosts.yml ]] || { echo "À lancer depuis la racine du projet ansible" >&2; exit 2; }
connus="$HOME/.ssh/known_hosts"
[[ -r "$connus" ]] || { echo "Introuvable : $connus" >&2; exit 2; }

# Nom et adresse de chaque hôte, sans dépendre du DNS (ansible_host = IP).
mapfile -t hotes < <(uv run ansible-inventory -i inventories/lab/hosts.yml --list 2>/dev/null \
  | jq -r '._meta.hostvars | to_entries[] | select(.value.ansible_host) | "\(.key) \(.value.ansible_host)"' \
  | sort)
((${#hotes[@]} > 0)) || { echo "Aucun hôte avec ansible_host dans l'inventaire" >&2; exit 1; }

sortie="$(mktemp)"
trap 'rm -f "$sortie"' EXIT
{
  echo "# inventories/lab/known_hosts — clés d'hôte ed25519 du socle, vérifiées contre ~/.ssh/known_hosts de adm01"
  echo "# Généré par outils/cles-hote-socle.sh le $(date -I). Public : ce fichier ne contient aucun secret."
} >"$sortie"

erreurs=0
for ligne in "${hotes[@]}"; do
  read -r nom ip <<<"$ligne"
  annoncee="$(ssh-keyscan -T 5 -t ed25519 "$ip" 2>/dev/null | awk '$2 == "ssh-ed25519" { print $2, $3; exit }')"
  # ssh-keygen -F retrouve aussi une entrée hachée (HashKnownHosts yes sur Debian).
  acceptee="$(ssh-keygen -F "$ip" -f "$connus" 2>/dev/null | awk '$2 == "ssh-ed25519" { print $2, $3; exit }')"
  if [[ -z "$annoncee" ]]; then
    echo "KO  $nom ($ip) : aucune clé ed25519 annoncée (hôte injoignable ?)" >&2; erreurs=$((erreurs + 1)); continue
  fi
  if [[ -z "$acceptee" ]]; then
    echo "KO  $nom ($ip) : adm01 ne connaît pas encore cet hôte. Connecte-toi une fois et vérifie l'empreinte à la console." >&2
    erreurs=$((erreurs + 1)); continue
  fi
  if [[ "$annoncee" != "$acceptee" ]]; then
    echo "KO  $nom ($ip) : la clé annoncée DIFFÈRE de celle acceptée. Ne publie rien : enquête (réinstallation ? interception ?)." >&2
    erreurs=$((erreurs + 1)); continue
  fi
  empreinte="$(ssh-keygen -lf <(echo "$ip $annoncee") | awk '{ print $2 }')"
  echo "OK  $nom ($ip) $empreinte"
  # Nom court et adresse : Ansible se connecte à l'adresse (ansible_host).
  echo "$ip,$nom $annoncee" >>"$sortie"
done

((erreurs == 0)) || { echo "$erreurs hôte(s) en erreur : rien n'a été écrit." >&2; exit 1; }
if ((ecrire)); then
  install -m 644 "$sortie" inventories/lab/known_hosts
  echo "Écrit : inventories/lab/known_hosts (à relire et committer)."
fi
