#!/usr/bin/env bash
# verifier-migration.sh — prouve qu'un dépôt local et sa copie sur la forge sont identiques (M01-E06).
# Usage : verifier-migration.sh [DÉPÔT]      (défaut : $WB_DEPOT, soit ~/medisphere)
# Lecture seule pour le dépôt local ; clone temporaire supprimé à la fin.
set -euo pipefail

depot="${1:-${WB_DEPOT:-$HOME/medisphere}}"
cd "$depot"
url="$(git remote get-url origin)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Dépôt local : $depot"
echo "Forge       : $url"

# 1. Références : mêmes noms, mêmes empreintes (branches et étiquettes)
git for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort > "$tmp/local"
git ls-remote "$url" 'refs/heads/*' 'refs/tags/*' | grep -v '\^{}$' | awk '{print $1, $2}' | sort > "$tmp/distant"
if diff -u "$tmp/local" "$tmp/distant"; then
  echo "OK  références identiques ($(wc -l < "$tmp/local") références)"
else
  echo "KO  les références diffèrent (ci-dessus : - local, + forge)" >&2; exit 1
fi

# 2. Clone neuf : intégrité et nombre de commits
git clone -q --mirror "$url" "$tmp/clone.git"
git -C "$tmp/clone.git" fsck --full --no-progress
n_local=$(git rev-list --all --count)
n_clone=$(git -C "$tmp/clone.git" rev-list --all --count)
if [[ "$n_local" == "$n_clone" ]]; then
  echo "OK  $n_local commits de part et d'autre, clone intègre"
else
  echo "KO  $n_local commits en local, $n_clone sur la forge" >&2; exit 1
fi

# 3. Étiquette du socle : même objet, même type
printf 'OK  socle-v0 : %s (%s)\n' "$(git rev-parse socle-v0)" "$(git cat-file -t socle-v0)"
