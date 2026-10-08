#!/usr/bin/env bash
# verifier-rendu.sh — contrôles SÉMANTIQUES du rendu avant tout dépôt sur pxe01 (M11-E15, pipeline),
# en complément de outils/verifier.sh (syntaxe, mots de passe, ShellCheck, M11-E03 à E06).
# Usage : outils/verifier-rendu.sh <dossier de rendu>     (dans le pipeline : rendu/http)
#   ipxe/*.ipxe   : en-tête « #!ipxe », aucune URL http:// (HTTPS vers pxe01 seulement)
#   preseed/*.cfg : debconf-set-selections -c, confirmation du partitionnement, aucun mot de passe en clair
#   kickstart/*.ks: ksvalidator (version RHEL10), rootpw verrouillé, aucun --plaintext
# Code de retour : 0 si tout est valide, 1 sinon (chaque défaut est listé).
set -uo pipefail

[[ $# -eq 1 && -d "$1" ]] || { echo "Usage : $0 <dossier de rendu>" >&2; exit 2; }
d="$1"
ko=0
defaut() { echo "KO  $1 : $2"; ko=1; }

shopt -s nullglob
for f in "$d"/ipxe/*.ipxe "$d"/boot.ipx[e]; do
  [[ "$(head -n 1 "$f")" == "#!ipxe" ]] || defaut "$f" "première ligne différente de #!ipxe"
  if grep -Eq 'http://' "$f"; then defaut "$f" "URL http:// (la chaîne est en HTTPS)"; fi
  # Seuls pxe01 et le dépôt officiel de Rocky (inst.repo, authentifié par une autorité publique)
  # peuvent apparaître : un script iPXE qui vise un autre serveur est une redirection de la chaîne.
  if grep -Eo 'https://[^/ ]+' "$f" | grep -Evqx 'https://(pxe01\.par1\.medisphere\.internal|dl\.rockylinux\.org)'; then
    defaut "$f" "URL vers un autre serveur que pxe01 ou le dépôt de Rocky"
  fi
done
for f in "$d"/preseed/*.cfg; do
  debconf-set-selections -c "$f" >/dev/null 2>&1 || defaut "$f" "rejeté par debconf-set-selections -c"
  grep -Eq '^d-i partman/confirm boolean true' "$f" || defaut "$f" "partman/confirm non prérempli (question à l'écran)"
  grep -Eq '^d-i partman/confirm_nooverwrite boolean true' "$f" || defaut "$f" "partman/confirm_nooverwrite non prérempli"
  if grep -Eq '^d-i passwd/(root|user)-password(-again)? ' "$f"; then defaut "$f" "mot de passe en clair"; fi
done
for f in "$d"/kickstart/*.ks; do
  ksvalidator -v RHEL10 "$f" >/dev/null 2>&1 || defaut "$f" "rejeté par ksvalidator -v RHEL10"
  grep -Eq '^rootpw .*--lock' "$f" || defaut "$f" "root non verrouillé"
  if grep -Eq -- '--plaintext' "$f"; then defaut "$f" "mot de passe en clair (--plaintext)"; fi
  grep -Eq '^ignoredisk --only-use=' "$f" || defaut "$f" "ignoredisk absent (risque d'effacer un autre disque)"
done
((ko == 0)) && echo "Rendu valide."
exit "$ko"
