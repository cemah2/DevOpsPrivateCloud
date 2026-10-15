#!/usr/bin/env bash
# securite/generer-seccomp.sh — produit securite/seccomp-mediagenda.json (M12-E24, SEC-1324).
#
# Point de départ : le profil seccomp PAR DÉFAUT de la version de Docker Engine des hôtes,
# tel qu'il est publié dans le dépôt moby (copie « vendor » du module github.com/moby/profiles).
# Modification : retrait de la règle qui autorise ptrace, process_vm_readv et process_vm_writev
# (noyau ≥ 4.8) — MédiAgenda n'en a aucun besoin, un attaquant si (lecture de la mémoire des
# autres processus du conteneur, injection de code). Les appels réservés à CAP_SYS_PTRACE restent
# conditionnés à cette capacité, que le conteneur n'a pas (cap_drop: ALL).
#
# Usage : securite/generer-seccomp.sh [VERSION_DOCKER]   (défaut : celle du démon local)
# Le fichier produit est versionné : la MR montre le diff quand la version de Docker change.
set -euo pipefail
cd "$(dirname "$0")"
version="${1:-$(docker version --format '{{.Server.Version}}')}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version de Docker illisible : $version" >&2; exit 2; }
url="https://raw.githubusercontent.com/moby/moby/docker-v${version}/vendor/github.com/moby/profiles/seccomp/default.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --max-time 30 "$url" -o "$tmp"
jq -e '.defaultAction == "SCMP_ACT_ERRNO" and (.syscalls | length) > 10' "$tmp" >/dev/null \
  || { echo "le fichier téléchargé n'est pas un profil seccomp attendu : $url" >&2; exit 1; }
avant="$(jq '.syscalls | length' "$tmp")"
# Une seule règle doit disparaître : celle qui autorise ptrace sans capacité (minKernel 4.8).
jq 'del(.syscalls[] | select((.includes.minKernel // "") == "4.8" and (.names | index("ptrace"))))' "$tmp" \
  > seccomp-mediagenda.json.nouveau
apres="$(jq '.syscalls | length' seccomp-mediagenda.json.nouveau)"
if (( avant - apres != 1 )); then
  rm -f seccomp-mediagenda.json.nouveau
  echo "structure du profil inattendue ($avant → $apres règles) : relis le profil de Docker $version" >&2
  exit 1
fi
mv seccomp-mediagenda.json.nouveau seccomp-mediagenda.json
echo "seccomp-mediagenda.json : profil par défaut de Docker $version, sans ptrace ($avant → $apres règles)."
