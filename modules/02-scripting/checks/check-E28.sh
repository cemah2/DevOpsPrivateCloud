# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E28.sh — M02-E28 : Paralléliser sans se tirer une balle dans le pied
# À lancer depuis adm01. Lance TON bin/ms-etat-hotes avec un faux « ssh » placé en tête du PATH
# (dossier temporaire) : aucune connexion réelle, durée de chaque « connexion » maîtrisée
# (2 s), hôtes injoignables simulés (code 255). Puis un relevé réel, en lecture seule, du socle.

title "M02-E28 — Paralléliser sans se tirer une balle dans le pied"
require_cmd bash mktemp

_m02_outil="${WB_SRC:-$HOME/src}/outils/bin/ms-etat-hotes"
check_cmd "bin/ms-etat-hotes existe et est exécutable" test -x "$_m02_outil"

_m02_tmp="$(mktemp -d)"
cat >"$_m02_tmp/ssh" <<'FIN'
#!/usr/bin/env bash
# Faux ssh du check M02-E28 : 2 s par appel ; « *injoignable* » → 255 ; sinon 4 lignes.
while [[ "${1:-}" == -* ]]; do case "$1" in -o|-i|-p|-l|-F|-J) shift 2 ;; *) shift ;; esac; done
echo "$1" >>"${0%/*}/appels.log"
sleep 2
case "$1" in *injoignable*) exit 255 ;; esac
printf '%s\n' "6.12.0-test" "2026-10-01 08:00:00" "42" "3"
FIN
chmod +x "$_m02_tmp/ssh"

_m02_hotes=(h1 injoignable-1 h2 h3 injoignable-2 h4 h5 h6)
_m02_debut="$SECONDS"
_m02_sortie="$(PATH="$_m02_tmp:$PATH" timeout 60 "$_m02_outil" -j 8 "${_m02_hotes[@]}" 2>/dev/null)"
_m02_code=$?
_m02_duree=$((SECONDS - _m02_debut))

check_output "8 hôtes de 2 s avec -j 8 : 8 lignes en moins de 8 s (séquentiel : 16 s)" '^ok$' \
  bash -c '(( $1 < 8 )) && [[ "$(grep -c . <<<"$2")" == 8 ]] && echo ok' _ "$_m02_duree" "$_m02_sortie"
check_output "code retour 1 quand des hôtes sont injoignables" '^1$' echo "$_m02_code"
check_output "les 8 hôtes ont été interrogés (un hôte en code 255 n'arrête pas les autres)" '^8$' \
  bash -c 'sort -u "$1" | grep -c .' _ "$_m02_tmp/appels.log"
check_output "une ligne par hôte, dans l'ordre des arguments" "^${_m02_hotes[*]}\$" \
  bash -c 'cut -f1 <<<"$1" | paste -sd " "' _ "$_m02_sortie"
check_output "états : 6 « ok » et 2 « injoignable », au bon endroit" '^ok injoignable ok ok injoignable ok ok ok$' \
  bash -c 'cut -f2 <<<"$1" | paste -sd " "' _ "$_m02_sortie"
check_output "format : 6 champs séparés par des tabulations sur chaque ligne" '^6$' \
  bash -c 'awk -F"\t" "{print NF}" <<<"$1" | sort -u' _ "$_m02_sortie"

: >"$_m02_tmp/appels.log"
_m02_debut="$SECONDS"
_m02_sortie="$(PATH="$_m02_tmp:$PATH" timeout 60 "$_m02_outil" -j 2 h1 h2 h3 h4 2>/dev/null)"
check_output "-j 2 borne le parallélisme (4 hôtes de 2 s : 4 lignes, au moins 4 s)" '^ok$' \
  bash -c '(( $1 >= 4 )) && [[ "$(grep -c . <<<"$2")" == 4 ]] && echo ok' _ "$((SECONDS - _m02_debut))" "$_m02_sortie"
check_output "-j 0 est une erreur d'usage (code 2)" '^2$' \
  bash -c 'PATH="$1:$PATH" "$2" -j 0 h1 >/dev/null 2>&1; echo $?' _ "$_m02_tmp" "$_m02_outil"
rm -rf -- "${_m02_tmp:?}"

# --- Relevé réel du socle (lecture seule) -------------------------------------------------
check_output "relevé réel : gw01, dns01, git01 et runner01 répondent « ok »" '^ok ok ok ok$' \
  bash -c 'timeout 60 "$1" -j 4 gw01 dns01 git01 runner01 2>/dev/null | cut -f2 | paste -sd " "' _ "$_m02_outil"
