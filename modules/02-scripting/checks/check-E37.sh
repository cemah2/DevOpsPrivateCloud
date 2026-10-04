# shellcheck shell=bash
# check-E37.sh — M02-E37 « Panne : le nettoyage a supprimé trop de choses » : état sain.
# Si la panne n'a jamais été injectée (zone /opt/workbook/m02/e37 absente), il n'y a rien à
# contrôler. Sinon : les rapports qui devaient rester sont revenus (contenu identique), ce que
# la politique supprime a disparu, et le script de purge corrigé respecte la politique sur un
# jeu de données neuf (fabriqué dans un dossier temporaire, supprimé à la fin). La zone de
# l'apprenant n'est jamais modifiée.

title "M02-E37 — Purge des rapports conforme à la politique"

_m02_e37_zone=/opt/workbook/m02/e37
_m02_e37_mod="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_m02_e37_gen="$_m02_e37_mod/ressources/M02-E37/fabriquer-donnees.sh"

# _m02_e37_ecarts ZONE CONSERVER|PURGER — nombre d'écarts à l'état attendu (attendu.tsv).
_m02_e37_ecarts() {
  local z="$1" type="$2" s p h n=0
  while IFS=$'\t' read -r s p h; do
    [[ "$s" == "$type" ]] || continue
    if [[ "$type" == CONSERVER ]]; then
      [[ -f "$z/$p" && "$(sha256sum "$z/$p" | cut -d' ' -f1)" == "$h" ]] || n=$((n + 1))
    else
      [[ -e "$z/$p" ]] && n=$((n + 1))
    fi
  done <"$z/attendu.tsv"
  printf '%s\n' "$n"
}

_m02_e37_rien_ne_manque() { [[ "$(_m02_e37_ecarts "$_m02_e37_zone" CONSERVER)" == 0 ]]; }
_m02_e37_purge_faite() { [[ "$(_m02_e37_ecarts "$_m02_e37_zone" PURGER)" == 0 ]]; }

# _m02_e37_essai [--sans-marqueur] — lance le script de l'apprenant sur un jeu neuf.
#   Normal : code 0, état attendu exact. --sans-marqueur : refus (code ≠ 0), rien supprimé.
_m02_e37_essai() {
  local t rc=0 ok=1
  t="$(mktemp -d)" || return 1
  bash "$_m02_e37_gen" "$t/z" >/dev/null 2>&1 || ok=0
  printf 'RACINE=%s\nRETENTION_JOURS=30\nAPPLIS_RETIREES="legacy-rdv"\n' "$t/z/rapports" >"$t/purge.conf"
  if [[ "${1:-}" == --sans-marqueur ]]; then
    rm -f -- "$t/z/rapports/.zone-de-test"
    (cd "$t" && timeout 60 "$_m02_e37_zone/bin/ms-purge-rapports" -c "$t/purge.conf") >/dev/null 2>&1 || rc=$?
    ((rc != 0)) || ok=0
    [[ "$(_m02_e37_ecarts "$t/z" CONSERVER)" == 0 ]] || ok=0
    [[ -e "$t/z/rapports/legacy-rdv" ]] || ok=0
  else
    (cd "$t" && timeout 60 "$_m02_e37_zone/bin/ms-purge-rapports" -c "$t/purge.conf") >/dev/null 2>&1 || rc=$?
    ((rc == 0)) || ok=0
    [[ "$(_m02_e37_ecarts "$t/z" CONSERVER)" == 0 ]] || ok=0
    [[ "$(_m02_e37_ecarts "$t/z" PURGER)" == 0 ]] || ok=0
  fi
  rm -rf -- "${t:?}"
  ((ok))
}

if [[ ! -d "$_m02_e37_zone" ]]; then
  skip "zone de test $_m02_e37_zone" "panne jamais injectée : rien à contrôler"
else
  check_cmd "état attendu de la zone connu (attendu.tsv)" test -s "$_m02_e37_zone/attendu.tsv"
  check_cmd "tous les rapports qui devaient rester sont présents et intacts (récents, a-conserver, hors-zone)" \
    _m02_e37_rien_ne_manque
  check_cmd "plus aucun fichier que la politique supprime (vieux rapports, tmp/, applications retirées)" \
    _m02_e37_purge_faite
  check_cmd "script de purge présent et exécutable" test -x "$_m02_e37_zone/bin/ms-purge-rapports"
  if command -v shellcheck >/dev/null 2>&1; then
    check_cmd "script de purge : ShellCheck sans remarque" shellcheck -x "$_m02_e37_zone/bin/ms-purge-rapports"
  else
    skip "script de purge : ShellCheck" "shellcheck absent de ce poste"
  fi
  check_cmd "script de purge : sur un jeu neuf, résultat exactement conforme à la politique" _m02_e37_essai
  check_cmd "script de purge : refuse une racine non marquée, sans rien supprimer" _m02_e37_essai --sans-marqueur
fi
