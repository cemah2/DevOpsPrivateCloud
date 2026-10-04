#!/usr/bin/env bats
# Tests de bin/ms-alerte (M02-E26), ajoutés pour la livraison v1 (M02-E46).
# journalctl, logger et curl sont remplacés par de faux programmes placés en tête du PATH :
# aucun accès au vrai journal, aucun appel réseau.

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  FAUX="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAUX"
  export JOURNAL_ECRIT="$BATS_TEST_TMPDIR/logger.txt" APPELS_CURL="$BATS_TEST_TMPDIR/curl.txt"
  # Faux journalctl : affiche ses arguments puis deux lignes « d'exécution ».
  cat >"$FAUX/journalctl" <<'FIN'
#!/usr/bin/env bash
echo "args: $*"
echo "ERREUR 1 VM(s) du socle sans sauvegarde valable"
FIN
  # Faux logger : mémorise ses options et le message, en argument ou (comme le vrai, à défaut
  # d'argument) sur l'entrée standard.
  cat >"$FAUX/logger" <<'FIN'
#!/usr/bin/env bash
echo "options: $*" >>"$JOURNAL_ECRIT"
msg=()
while (($#)); do
  case "$1" in
    -t | -p) shift 2 ;;
    *) msg+=("$1"); shift ;;
  esac
done
if ((${#msg[@]})); then printf '%s\n' "${msg[*]}"; else cat; fi >>"$JOURNAL_ECRIT"
FIN
  # Faux curl : mémorise l'URL et le corps ; échoue si FAUX_CURL_ECHEC=1.
  cat >"$FAUX/curl" <<'FIN'
#!/usr/bin/env bash
{ echo "url: ${*: -1}"; cat; echo; } >>"$APPELS_CURL"
[[ "${FAUX_CURL_ECHEC:-0}" != 1 ]]
FIN
  chmod +x "$FAUX"/*
  export PATH="$FAUX:$PATH"
  unset MS_ALERTE_WEBHOOK MONITOR_INVOCATION_ID
}

@test "ms-alerte écrit une alerte crit nommant l'unité, le résultat et le code" {
  MONITOR_SERVICE_RESULT=exit-code MONITOR_EXIT_CODE=exited MONITOR_EXIT_STATUS=1 \
    run -0 "$RACINE/bin/ms-alerte" ms-verif-sauvegardes.service
  grep -q -- '-t ms-alerte -p user.crit' "$JOURNAL_ECRIT"
  grep -q 'ÉCHEC ms-verif-sauvegardes.service sur .* (résultat exit-code, code exited/1)' "$JOURNAL_ECRIT"
  grep -q 'sans sauvegarde valable' "$JOURNAL_ECRIT"
}

@test "ms-alerte lit les lignes de CETTE exécution quand systemd fournit l'identifiant d'invocation" {
  MONITOR_INVOCATION_ID=0123456789abcdef run -0 "$RACINE/bin/ms-alerte" x.service
  grep -q '_SYSTEMD_INVOCATION_ID=0123456789abcdef' "$JOURNAL_ECRIT"
}

@test "ms-alerte sans webhook n'appelle pas curl" {
  run -0 "$RACINE/bin/ms-alerte" x.service
  [[ ! -e "$APPELS_CURL" ]]
}

@test "ms-alerte envoie un JSON valide au webhook" {
  MS_ALERTE_WEBHOOK=https://notif.test/hook run -0 "$RACINE/bin/ms-alerte" x.service
  grep -q '^url: https://notif.test/hook$' "$APPELS_CURL"
  sed '1d' "$APPELS_CURL" | jq -e '.unite == "x.service" and .severite == "error"'
}

@test "webhook injoignable : l'alerte du journal reste, l'échec est signalé, code 0" {
  FAUX_CURL_ECHEC=1 MS_ALERTE_WEBHOOK='https://notif.test/hook?jeton=secret' \
    run -0 "$RACINE/bin/ms-alerte" x.service
  grep -q 'ÉCHEC x.service' "$JOURNAL_ECRIT"
  grep -q 'webhook injoignable : https://notif.test/hook$' "$JOURNAL_ECRIT"
  # La partie « requête » de l'URL (qui peut porter un jeton) n'est jamais journalisée.
  run ! grep -q 'secret' "$JOURNAL_ECRIT"
}
