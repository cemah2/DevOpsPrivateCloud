#!/usr/bin/env bash
# objets-a-la-main.sh — refait l'exercice M01-E02 en plomberie Git, pas à pas, en commentant.
# Usage : objets-a-la-main.sh [DOSSIER]      (défaut : ~/src/labo-objets ; refuse s'il existe)
set -euo pipefail

d="${1:-${WB_SRC:-$HOME/src}/labo-objets}"
[[ -e "$d" ]] && { echo "Refus : $d existe déjà." >&2; exit 1; }
git init -q -b main "$d"
cd "$d"

etape() { printf '\n=== %s ===\n' "$*"; }

etape "1. Dépôt vide : HEAD pointe vers une branche qui n'existe pas encore"
cat .git/HEAD                                   # ref: refs/heads/main

etape "2. Blob : empreinte = SHA-1 de « blob <octets>\\0<contenu> »"
contenu=$'Bonjour MédiSphère\n'
taille=$(printf '%s' "$contenu" | wc -c)        # 21 octets : é et è font 2 octets en UTF-8
b1=$(printf '%s' "$contenu" | git hash-object -w --stdin)
printf 'blob %d\0%s' "$taille" "$contenu" | sha1sum   # même empreinte, calculée sans Git
echo "blob LISEZMOI.txt : $b1 (taille $taille)"
git cat-file -t "$b1"; git cat-file -s "$b1"; git cat-file -p "$b1"
python3 -c 'import sys,zlib; print(zlib.decompress(open(sys.argv[1],"rb").read()))' \
  ".git/objects/${b1:0:2}/${b1:2}"              # b'blob 21\x00Bonjour M\xc3\xa9diSph\xc3\xa8re\n'

etape "3. Second blob"
b2=$(printf 'Les objets Git sont immuables.\n' | git hash-object -w --stdin)
echo "blob docs/notes.txt : $b2"

etape "4. Index puis arbres : write-tree crée l'arbre racine ET le sous-arbre docs"
git update-index --add --cacheinfo "100644,$b1,LISEZMOI.txt"
git update-index --add --cacheinfo "100644,$b2,docs/notes.txt"
git ls-files --stage
t1=$(git write-tree)
git cat-file -p "$t1"
git cat-file -p "$t1:docs"

etape "5. Commit racine (sans parent)"
c1=$(git commit-tree "$t1" -m "Premier commit construit à la main")
git cat-file -p "$c1"
git log 2>&1 | head -n 1 || true                # aucune branche : « does not have any commits yet »

etape "6. La branche n'est qu'un fichier qui contient une empreinte"
git update-ref refs/heads/main "$c1"
git log --oneline
git status --short                              # « D » : fichiers dans l'index, absents du disque
git restore .                                   # index -> arbre de travail
git status --short

etape "7. Second commit en plomberie : un nouveau blob, deux nouveaux arbres, un commit"
printf 'Les objets Git sont immuables.\nUne branche est un pointeur mobile.\n' > docs/notes.txt
b3=$(git hash-object -w docs/notes.txt)
git update-index --cacheinfo "100644,$b3,docs/notes.txt"
t2=$(git write-tree)
c2=$(git commit-tree "$t2" -p "$c1" -m "Deuxième commit construit à la main")
git update-ref refs/heads/main "$c2" "$c1"      # mise à jour conditionnelle : main valait c1
git cat-file -p "$t2"                           # LISEZMOI.txt garde le même blob : réutilisé
git log --oneline

etape "8. Étiquettes : une légère (référence) et une annotée (objet tag)"
git tag v0-leger "$c1"
git -c tag.gpgSign=false tag -a v0-annote -m "Étiquette annotée de l'E02" "$c1"
git cat-file -t v0-leger; git cat-file -t v0-annote
git cat-file -p v0-annote

etape "9. Déduplication : même contenu, même blob"
cp LISEZMOI.txt COPIE.txt && git add COPIE.txt
git ls-files --stage COPIE.txt LISEZMOI.txt     # même empreinte
git rm -q --cached COPIE.txt && rm COPIE.txt

etape "10. Références libres puis empaquetées"
git branch essai
cat .git/refs/heads/essai
git pack-refs --all
ls .git/refs/heads/ ; cat .git/packed-refs
git branch -d essai
git count-objects -v
git status --short
