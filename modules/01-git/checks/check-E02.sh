# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E02.sh — M01-E02 : le modèle objet de Git.
# Dépôt local ~/src/labo-objets sur adm01. Lecture seule.
# Les contenus des deux fichiers sont imposés par l'énoncé : l'empreinte de l'arbre racine du
# premier commit est donc connue d'avance (les blobs et les arbres ne dépendent que du contenu,
# des noms et des modes ; pas de l'auteur ni de la date).

title "M01-E02 — Le modèle objet de Git"
require_cmd git

_m01_d="${WB_SRC:-$HOME/src}/labo-objets"
_m01_arbre_attendu=9d90ff95f2a92e967102d836e837607d0109aaf6   # LISEZMOI.txt + docs/notes.txt
_m01_blob_lisezmoi=2453cbd5850643ef5792a0fc58ccc3fcc8f58004   # « Bonjour MédiSphère\n »

check_cmd "dépôt $_m01_d présent" git -C "$_m01_d" rev-parse --git-dir
check_output "HEAD désigne la branche main" '^refs/heads/main$' git -C "$_m01_d" symbolic-ref HEAD
check_output "main a un seul commit racine" '^1$' \
  bash -c 'git -C "$1" rev-list --max-parents=0 main | wc -l' _ "$_m01_d"

_m01_racine="$(git -C "$_m01_d" rev-list --max-parents=0 main 2>/dev/null | head -n 1)"
if [[ -n "$_m01_racine" ]]; then
  check_output "commit racine : message « Premier commit construit à la main »" \
    '^Premier commit construit à la main$' git -C "$_m01_d" log -1 --format=%s "$_m01_racine"
  check_output "commit racine : arbre = exactement LISEZMOI.txt et docs/notes.txt imposés" \
    "^${_m01_arbre_attendu}\$" git -C "$_m01_d" rev-parse "${_m01_racine}^{tree}"
  check_cmd "le blob de « Bonjour MédiSphère » est dans la base d'objets" \
    git -C "$_m01_d" cat-file -e "${_m01_blob_lisezmoi}^{blob}"
  check_cmd "main compte au moins deux commits, le deuxième a le commit racine pour parent" \
    bash -c 'c2=$(git -C "$1" rev-list --reverse --first-parent main | sed -n 2p); [ -n "$c2" ] && [ "$(git -C "$1" rev-parse "$c2^")" = "$2" ]' \
    _ "$_m01_d" "$_m01_racine"
  check_output "v0-annote est un objet étiquette (annotée)" '^tag$' git -C "$_m01_d" cat-file -t v0-annote
  check_output "v0-annote désigne le commit racine" "^${_m01_racine}\$" git -C "$_m01_d" rev-parse 'v0-annote^{commit}'
  check_output "v0-leger est une étiquette légère (référence directe vers un commit)" '^commit$' \
    git -C "$_m01_d" cat-file -t v0-leger
  check_output "v0-leger désigne le commit racine" "^${_m01_racine}\$" git -C "$_m01_d" rev-parse v0-leger
else
  skip "contrôles du commit racine, des commits et des étiquettes" "branche main introuvable"
fi

check_output "arbre de travail propre (aucune modification en attente)" '^$' \
  git -C "$_m01_d" status --porcelain
