# shellcheck shell=bash
# check-E39.sh — M02-E39 « Panne : set -e ne fait pas ce qu'on croit » : état sain.
# Si la panne n'a jamais été injectée (zone /opt/workbook/m02/e39 absente), rien à contrôler.
# Sinon : les journaux de chaque hôte sont soit encore dans le spool, soit dans une archive
# complète ; le script d'archivage corrigé échoue bruyamment (code ≠ 0, spool conservé) quand
# un fichier est illisible, et archive tout quand le spool est sain. Les essais tournent sur des
# spools neufs dans un dossier temporaire (supprimé à la fin) ; la zone n'est jamais modifiée.

title "M02-E39 — Archivage des journaux : aucun échec silencieux"

_m02_e39_zone=/opt/workbook/m02/e39
_m02_e39_mod="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_m02_e39_gen="$_m02_e39_mod/ressources/M02-E39/fabriquer-spool.sh"

# _m02_e39_couvert ZONE HÔTE — chaque journal attendu de HÔTE est dans le spool ou dans une
# archive HÔTE-*.tar.gz lisible.
_m02_e39_couvert() {
  local z="$1" h="$2" f a trouve
  [[ -s "$z/attendu/$h.liste" ]] || return 1
  while IFS= read -r f; do
    [[ -e "$z/spool/$h/$f" ]] && continue
    trouve=0
    for a in "$z/archives/$h"-*.tar.gz; do
      [[ -f "$a" ]] || continue
      if tar -tzf "$a" 2>/dev/null | sed 's#^\./##' | grep -qxF -- "$f"; then
        trouve=1
        break
      fi
    done
    ((trouve)) || return 1
  done <"$z/attendu/$h.liste"
}

_m02_e39_tous_couverts() {
  local h
  for h in gw01 dns01 git01; do
    _m02_e39_couvert "$_m02_e39_zone" "$h" || return 1
  done
}

# _m02_e39_essai [--sain] — lance le script de l'apprenant sur un spool neuf.
_m02_e39_essai() {
  local t rc=0 ok=1 h
  t="$(mktemp -d)" || return 1
  bash "$_m02_e39_gen" "$@" "$t/z" >/dev/null 2>&1 || ok=0
  timeout 60 "$_m02_e39_zone/bin/ms-archiver-journaux" -s "$t/z/spool" -a "$t/z/archives" >/dev/null 2>&1 || rc=$?
  if [[ "${1:-}" == --sain ]]; then
    ((rc == 0)) || ok=0
    for h in gw01 dns01 git01; do
      _m02_e39_couvert "$t/z" "$h" || ok=0
      [[ -z "$(find "$t/z/spool/$h" -type f 2>/dev/null)" ]] || ok=0
    done
  else
    ((rc != 0)) || ok=0
    # dns01 (fichier illisible) : rien n'a quitté le spool
    [[ "$(find "$t/z/spool/dns01" -type f | wc -l)" == "$(wc -l <"$t/z/attendu/dns01.liste")" ]] || ok=0
    # les autres hôtes ont quand même été archivés complètement
    for h in gw01 git01; do
      _m02_e39_couvert "$t/z" "$h" || ok=0
    done
  fi
  chmod -R u+rwX "$t" 2>/dev/null
  rm -rf -- "${t:?}"
  ((ok))
}

if [[ ! -d "$_m02_e39_zone" ]]; then
  skip "zone de test $_m02_e39_zone" "panne jamais injectée : rien à contrôler"
else
  check_cmd "aucun journal perdu : chacun est dans le spool ou dans une archive complète" _m02_e39_tous_couverts
  check_cmd "script d'archivage présent et exécutable" test -x "$_m02_e39_zone/bin/ms-archiver-journaux"
  if command -v shellcheck >/dev/null 2>&1; then
    check_cmd "script d'archivage : ShellCheck sans remarque" shellcheck -x "$_m02_e39_zone/bin/ms-archiver-journaux"
  else
    skip "script d'archivage : ShellCheck" "shellcheck absent de ce poste"
  fi
  check_cmd "fichier illisible : le script échoue (code ≠ 0) et ne vide pas le spool de l'hôte en erreur" _m02_e39_essai
  check_cmd "spool sain : le script réussit (code 0) et chaque archive contient tous les journaux" _m02_e39_essai --sain
fi
