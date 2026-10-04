# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E12.sh — M02-E12 : traiter des fichiers en masse sans piège
# À lancer depuis adm01. Le contrôle fabrique un jeu de données jetable dans un dossier
# temporaire (ressources/M02-E12/fabriquer-jeu.sh), y lance TON ms-ranger, compare le
# résultat à ce qui est attendu, puis supprime ce dossier. Rien d'autre n'est touché.

title "M02-E12 — Traiter des fichiers en masse sans piège"
require_cmd find sha256sum shellcheck git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_ranger="$_m02_r/bin/ms-ranger"
_m02_jeu="$ROOT/modules/02-scripting/ressources/M02-E12/fabriquer-jeu.sh"

check_cmd "bin/ms-ranger présent et exécutable" test -x "$_m02_ranger"
check_cmd "ms-ranger passe ShellCheck" bash -c 'cd "$1" && shellcheck -x bin/ms-ranger' _ "$_m02_r"
check_cmd "ms-ranger est fusionné dans main (GitLab)" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/bin%2Fms-ranger?ref=main"

_m02_tmp="$(mktemp -d)"
_m02_src="$_m02_tmp/exports-infoger"
_m02_dst="$_m02_tmp/archive"
# nb FICHIERS : compte des NUL, pas des lignes (certains noms contiennent un retour à la ligne)
_m02_nb() { find "$@" -print0 | tr -cd '\0' | wc -c; }

if bash "$_m02_jeu" "$_m02_tmp" >/dev/null 2>&1; then
  _m02_anciens="$(_m02_nb "$_m02_src" -type f -mtime +90)"
  _m02_recents="$(_m02_nb "$_m02_src" -type f -mtime -91)"

  check_cmd "--dry-run : rien n'est déplacé" bash -c '
    "$1" --dry-run "$2" "$3" </dev/null >/dev/null 2>&1 || exit 1
    [[ ! -e "$3" || -z "$(find "$3" -type f -print -quit)" ]] && [[ -f "$2/-divers/-rf" ]]' \
    _ "$_m02_ranger" "$_m02_src" "$_m02_dst"
  check_cmd "DESTINATION à l'intérieur de SOURCE : refus, code 3" bash -c '
    rc=0; "$1" "$2" "$2/archive" </dev/null >/dev/null 2>&1 || rc=$?; ((rc == 3)) && [[ ! -e "$2/archive" ]]' \
    _ "$_m02_ranger" "$_m02_src"

  _m02_rc=0
  "$_m02_ranger" "$_m02_src" "$_m02_dst" </dev/null >/dev/null 2>&1 || _m02_rc=$?
  check_cmd "rangement du jeu de test : code 0" test "$_m02_rc" -eq 0
  check_output "les $_m02_anciens fichiers de plus de 90 jours sont rangés dans DESTINATION" "^${_m02_anciens}\$" \
    _m02_nb "$_m02_dst" -type f ! -name 'MANIFESTE*'
  check_output "les $_m02_recents fichiers récents sont restés dans SOURCE" "^${_m02_recents}\$" \
    _m02_nb "$_m02_src" -type f
  check_cmd "le lien symbolique n'a été ni suivi ni déplacé" test -L "$_m02_src/archives/lien-vers-rapport"
  check_cmd "nom avec retour à la ligne : rangé intact dans 2025-01/" \
    test -f "$_m02_dst/2025-01/journaux/ligne un"$'\n'"ligne deux.log"
  check_cmd "nom à tiret initial : rangé intact dans 2025-01/" test -f "$_m02_dst/2025-01/-divers/-rf"
  check_cmd "noms à caractères de motif et de shell : rangés intacts" bash -c '
    [[ -f "$1/2025-01/factures/facture [2025] *finale*.txt" && -f "$1/2025-03/factures/devis \$(reboot).txt" \
       && -f "$1/2025-02/factures/C:\Windows\chemin.txt" && -f "$1/2025-06/accentués/日本語.txt" ]]' _ "$_m02_dst"
  check_cmd "fichier caché rangé aussi (2025-01/archives/.verrou-infoger)" \
    test -f "$_m02_dst/2025-01/archives/.verrou-infoger"
  check_cmd "un manifeste SHA-256 existe et sha256sum --check le valide" bash -c '
    cd "$1" && m=(MANIFESTE*.sha256) && [[ -f "${m[0]}" ]] && sha256sum --check --strict --quiet -- "${m[@]}"' _ "$_m02_dst"
  check_output "le manifeste couvre les $_m02_anciens fichiers rangés" "^${_m02_anciens}\$" \
    bash -c 'cd "$1" && cat MANIFESTE*.sha256 | grep -c .' _ "$_m02_dst"
  check_cmd "seconde exécution : rien à faire, code 0, rien de déplacé" bash -c '
    avant="$(find "$3" -type f -print0 | tr -cd "\0" | wc -c)"
    "$1" "$2" "$3" </dev/null >/dev/null 2>&1 || exit 1
    apres="$(find "$3" -type f ! -name "MANIFESTE*" -print0 | tr -cd "\0" | wc -c)"
    [[ -n "$avant" ]] && ((apres <= avant))' _ "$_m02_ranger" "$_m02_src" "$_m02_dst"
else
  skip "contrôles fonctionnels de ms-ranger" "jeu de données impossible à fabriquer ($_m02_jeu)"
fi
rm -rf -- "${_m02_tmp:?}"
