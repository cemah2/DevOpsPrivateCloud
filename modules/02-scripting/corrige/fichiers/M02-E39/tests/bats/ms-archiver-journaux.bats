#!/usr/bin/env bats
# Tests de bin/ms-archiver-journaux (M02-E39, INC-2844). Spool fictif fabriqué dans le dossier du
# test par fixtures/fabriquer-spool.sh (copie de ressources/M02-E39 du workbook).
# Contrat testé : un fichier ne quitte le spool que s'il est dans une archive vérifiée ; un hôte
# en erreur n'empêche pas les autres ; le code retour dit la vérité.

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  Z="$BATS_TEST_TMPDIR/z"
  ARCH="$RACINE/bin/ms-archiver-journaux"
}

teardown() {
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# archive_complete HÔTE — une archive de l'hôte contient exactement sa liste attendue.
archive_complete() {
  local a
  for a in "$Z/archives/$1"-*.tar.gz; do
    [[ -f "$a" ]] || continue
    if diff <(tar -tzf "$a" | sed 's#^\./##' | grep -v '^$' | sort) <(sort "$Z/attendu/$1.liste") >/dev/null; then
      return 0
    fi
  done
  return 1
}

nb_spool() { find "$Z/spool/$1" -type f | wc -l; }

@test "spool sain : code 0, une archive complète par hôte, spool vidé" {
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-spool.sh" --sain "$Z" >/dev/null
  run -0 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  for h in gw01 dns01 git01; do
    archive_complete "$h"
    [[ "$(nb_spool "$h")" == 0 ]]
  done
}

@test "fichier illisible : code 1, spool de l'hôte intact, les autres hôtes archivés" {
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-spool.sh" "$Z" >/dev/null
  if [[ -r "$Z/spool/dns01/dnsmasq.log.1" ]]; then
    skip "ce compte lit les fichiers en mode 000 (root ?) : test sans objet"
  fi
  run -1 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  [[ "$(nb_spool dns01)" == 3 ]]
  archive_complete gw01
  archive_complete git01
  [[ "$output" == *"dns01"* ]]
  # Aucune archive partielle ne traîne.
  [[ -z "$(find "$Z/archives" -name '*.partiel')" ]]
}

@test "archive incomplète (tar qui « oublie » un fichier sans erreur) : code 1, spool conservé" {
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-spool.sh" --sain "$Z" >/dev/null
  local vrai_tar
  vrai_tar="$(command -v tar)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # Faux tar : à la création d'archive, retire le dernier fichier de la liste.
  cat >"$BATS_TEST_TMPDIR/bin/tar" <<FIN
#!/usr/bin/env bash
if [[ " \$* " == *" -czf "* ]]; then set -- "\${@:1:\$((\$# - 1))}"; fi
exec "$vrai_tar" "\$@"
FIN
  chmod +x "$BATS_TEST_TMPDIR/bin/tar"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run -1 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  [[ "$(nb_spool gw01)" == 3 ]]
  [[ "$(nb_spool dns01)" == 3 ]]
}

@test "deuxième passage sur un spool vidé : code 0, rien à archiver" {
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-spool.sh" --sain "$Z" >/dev/null
  run -0 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  run -0 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  [[ "$output" == *"rien à archiver"* ]]
}

@test "spool non marqué : refus (3), rien n'est touché" {
  bash "$BATS_TEST_DIRNAME/fixtures/fabriquer-spool.sh" --sain "$Z" >/dev/null
  rm "$Z/spool/.zone-de-test"
  run -3 "$ARCH" -s "$Z/spool" -a "$Z/archives"
  [[ "$(nb_spool gw01)" == 3 ]]
}

@test "usage : option inconnue ou argument superflu (2)" {
  run -2 "$ARCH" -x
  run -2 "$ARCH" -s /tmp superflu
}
