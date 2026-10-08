#!/usr/bin/env bash
# verifier.sh — contrôles hors ligne du projet plateforme/provisioning (pipeline et poste).
# M11-E03 (scripts iPXE, ShellCheck), M11-E04 (preseed), M11-E05 (kickstart), M11-E06 (rendu),
# M11-E13 (ShellCheck étendu à ipxe/construire-ipxe.sh).
#
#   outils/verifier.sh [dossier…]     (défaut : ipxe preseed kickstart, plus rendu/http s'il existe)
#
# Un outil manquant fait ÉCHOUER la vérification dès qu'un fichier en a besoin : un contrôle
# sauté en silence ne protège de rien.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"
if [[ $# -gt 0 ]]; then
  dossiers=("$@")
else
  dossiers=(ipxe preseed kickstart)
  [[ -d rendu/http ]] && dossiers+=(rendu/http)
fi
echecs=0
ko() { printf 'KO  %s\n' "$*"; echecs=$((echecs + 1)); }
ok() { printf 'ok  %s\n' "$*"; }
outil() { command -v "$1" >/dev/null 2>&1 || { ko "outil manquant : $1"; return 1; }; }

mapfile -d '' ipxe < <(find "${dossiers[@]}" -name '*.ipxe' -type f -print0 2>/dev/null)
mapfile -d '' preseeds < <(find "${dossiers[@]}" -name '*.cfg' -type f -print0 2>/dev/null)
mapfile -d '' kickstarts < <(find "${dossiers[@]}" -name '*.ks' -type f -print0 2>/dev/null)
mapfile -d '' scripts < <(find outils ipxe -name '*.sh' -type f -print0 2>/dev/null)

# 1. Scripts iPXE : première ligne exacte (sinon iPXE l'exécute comme… une image à démarrer).
for f in "${ipxe[@]}"; do
  if [[ "$(head -n 1 "$f")" == "#!ipxe" ]]; then ok "$f : en-tête #!ipxe"; else ko "$f : la première ligne doit être #!ipxe"; fi
done

# 2. Aucun mot de passe en clair (preseed, kickstart, scripts).
#    preseed : passwd/…-password password … (la forme sûre est …-password-crypted) ;
#    kickstart : --plaintext, « rootpw <mot> » sans option, « user … --password » sans --iscrypted.
for f in "${preseeds[@]}" "${kickstarts[@]}"; do
  if grep -nE 'passwd/(root|user)-password(-again)?[[:space:]]+password[[:space:]]+[^[:space:]]' "$f" \
     || grep -nE -- '--plaintext' "$f" \
     || grep -nE '^[[:space:]]*rootpw[[:space:]]+[^-[:space:]]' "$f" \
     || grep -nE '^[[:space:]]*user[[:space:]].*--password' "$f" | grep -v -- '--iscrypted'; then
    ko "$f : mot de passe en clair"
  else
    ok "$f : aucun mot de passe en clair"
  fi
done

# 3. Preseed : syntaxe debconf (paquet debconf).
if [[ ${#preseeds[@]} -gt 0 ]] && outil debconf-set-selections; then
  for f in "${preseeds[@]}"; do
    if debconf-set-selections -c "$f"; then ok "$f : syntaxe debconf"; else ko "$f : syntaxe debconf"; fi
  done
fi

# 4. Kickstart : ksvalidator (pykickstart), syntaxe RHEL 10.
if [[ ${#kickstarts[@]} -gt 0 ]] && outil ksvalidator; then
  for f in "${kickstarts[@]}"; do
    if ksvalidator -v RHEL10 "$f"; then ok "$f : ksvalidator RHEL10"; else ko "$f : ksvalidator RHEL10"; fi
  done
fi

# 5. Scripts du projet : ShellCheck.
if [[ ${#scripts[@]} -gt 0 ]] && outil shellcheck; then
  if shellcheck -x "${scripts[@]}"; then ok "ShellCheck (${#scripts[@]} scripts)"; else ko "ShellCheck"; fi
fi

if (( echecs > 0 )); then
  echo "$echecs contrôle(s) en échec."
  exit 1
fi
echo "Tous les contrôles passent."
