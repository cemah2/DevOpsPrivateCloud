#!/usr/bin/env bats
# Tests de bin/ms-purge-rapports (M02-E37, INC-2843). Données fictives fabriquées dans le dossier
# du test par fixtures/fabriquer-donnees.sh (copie de ressources/M02-E37 du workbook) ; l'état
# attendu après une purge conforme à la politique PLAT-384 est dans attendu.tsv.
# Un test par bogue de la version 0.1 (variantes de la panne), plus le contrat du script.

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  Z="$BATS_TEST_TMPDIR/z"
  CONF="$BATS_TEST_TMPDIR/purge.conf"
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-donnees.sh" "$Z" >/dev/null
  printf 'RACINE=%s\nRETENTION_JOURS=30\nAPPLIS_RETIREES="legacy-rdv"\n' "$Z/rapports" >"$CONF"
  PURGE="$RACINE/bin/ms-purge-rapports"
}

# ecarts CONSERVER|PURGER — nombre de fichiers qui ne sont pas dans l'état attendu.
ecarts() {
  local s p h n=0
  while IFS=$'\t' read -r s p h; do
    [[ "$s" == "$1" ]] || continue
    if [[ "$1" == CONSERVER ]]; then
      [[ -f "$Z/$p" && "$(sha256sum "$Z/$p" | cut -d' ' -f1)" == "$h" ]] || n=$((n + 1))
    elif [[ -e "$Z/$p" ]]; then
      n=$((n + 1))
    fi
  done <"$Z/attendu.tsv"
  echo "$n"
}

@test "la purge produit exactement l'état de la politique" {
  run -0 "$PURGE" -c "$CONF"
  [[ "$(ecarts CONSERVER)" == 0 ]]
  [[ "$(ecarts PURGER)" == 0 ]]
}

@test "une seconde purge ne fait plus rien (idempotence)" {
  run -0 "$PURGE" -c "$CONF"
  run -0 --separate-stderr "$PURGE" -c "$CONF"
  [[ -z "$output" ]]
}

@test "dry-run : rien n'est supprimé et le plan annonce chaque fichier à purger" {
  run -0 --separate-stderr "$PURGE" --dry-run -c "$CONF"
  [[ "$(ecarts CONSERVER)" == 0 ]]
  [[ -d "$Z/rapports/legacy-rdv" ]]
  [[ "$output" == *"supprimerait : $Z/rapports/legacy-rdv"* ]]
  [[ "$output" == *"supprimerait : $Z/rapports/medi-doc/tmp/export-1.tmp"* ]]
}

@test "racine non marquée : refus (3), rien supprimé" {
  rm "$Z/rapports/.zone-de-test"
  run -3 "$PURGE" -c "$CONF"
  [[ "$(ecarts CONSERVER)" == 0 ]]
  [[ -d "$Z/rapports/legacy-rdv" ]]
}

@test "configuration invalide (racine relative, rétention non numérique) : refus (3)" {
  printf 'RACINE=rapports\nRETENTION_JOURS=30\n' >"$CONF"
  run -3 "$PURGE" -c "$CONF"
  printf 'RACINE=%s\nRETENTION_JOURS=trente\n' "$Z/rapports" >"$CONF"
  run -3 "$PURGE" -c "$CONF"
  [[ "$(ecarts CONSERVER)" == 0 ]]
}

@test "option inconnue : usage (2)" {
  run -2 "$PURGE" --tout-supprimer
}

@test "régression v1 : la racine n'est jamais supprimée, quelle que soit la liste des retirées" {
  printf 'APPLIS_RETIREES="legacy-rdv appli-inexistante"\n' >>"$CONF"
  run -0 "$PURGE" -c "$CONF"
  [[ -f "$Z/rapports/.zone-de-test" ]]
  [[ "$(ecarts CONSERVER)" == 0 ]]
}

@test "régression v1 : un nom d'application retirée dangereux est refusé (3)" {
  printf 'APPLIS_RETIREES="../hors-zone"\n' >>"$CONF"
  run -3 "$PURGE" -c "$CONF"
  [[ -f "$Z/hors-zone/temoin.pdf" ]]
}

@test "régression v2 : les PDF récents et ceux de a-conserver/ restent" {
  run -0 "$PURGE" -c "$CONF"
  run -0 find "$Z/rapports/medi-agenda/a-conserver" -name '*.pdf'
  [[ -n "$output" ]]
  [[ "$(find "$Z/rapports" -name '*.pdf' -mtime -30 | wc -l)" -gt 0 ]]
}

@test "régression v3 : une application sans tmp/ n'entraîne aucune suppression hors de tmp/" {
  [[ ! -d "$Z/rapports/medi-notif/tmp" ]]
  run -0 "$PURGE" -c "$CONF"
  [[ -f "$Z/rapports/medi-notif/LISEZMOI.txt" ]]
  [[ -d "$Z/rapports/medi-doc/tmp" ]]
}

@test "régression v4 : rien de récent n'est supprimé, tout ce qui est ancien l'est" {
  run -0 "$PURGE" -c "$CONF"
  [[ -z "$(find "$Z/rapports" -path '*/a-conserver' -prune -o -type f \( -name '*.json' -o -name '*.pdf' \) -mtime +30 -print)" ]]
  [[ "$(ecarts CONSERVER)" == 0 ]]
}
