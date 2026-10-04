# shellcheck shell=bash
# helpers/commun.bash — environnement commun des tests bats de plateforme/outils (M02-E14).
# Chargé par « load helpers/commun » dans chaque fichier .bats.
#
# Chaque test reçoit un dossier jetable (BATS_TEST_TMPDIR) avec :
#   - un faux fichier d'accès à l'API, en mode 600 (aucun secret réel) ;
#   - un faux « curl » en tête du PATH (helpers/bin/curl) qui simule pveproxy ;
#   - son propre dossier de verrous.
# Aucun test ne touche au vrai Proxmox, ni au réseau, ni à ~/.config.

RACINE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export RACINE

preparer_faux_pve() {
  export FAUX_PVE_BASE="https://pve.test:8006/api2/json"
  export FAUX_PVE_FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  export FAUX_PVE_ETAT="$BATS_TEST_TMPDIR/etat"
  export FAUX_PVE_JOURNAL="$BATS_TEST_TMPDIR/appels.log"
  export FAUX_PVE_SECRET="00000000-test-test-test-secret000000"
  mkdir -p "$FAUX_PVE_ETAT"
  : >"$FAUX_PVE_JOURNAL"

  export MS_PVE_ENV="$BATS_TEST_TMPDIR/pve-api.env"
  (
    umask 077
    cat >"$MS_PVE_ENV" <<FIN
PVE_API_URL="$FAUX_PVE_BASE"
PVE_NODE="pve01"
PVE_TOKEN_ID="wb-automation@pve!lab"
PVE_TOKEN_SECRET="$FAUX_PVE_SECRET"
FIN
  )
  # Pas de CA : le faux curl ne fait pas de TLS. Variables PVE_* de l'appelant neutralisées.
  unset PVE_API_URL PVE_NODE PVE_TOKEN_ID PVE_TOKEN_SECRET PVE_CACERT
  export MS_LOCK_DIR="$BATS_TEST_TMPDIR/verrous"
  export MS_PVE_POLL=0
  export PATH="$BATS_TEST_DIRNAME/helpers/bin:$PATH"
}

# appels MOTIF — nombre d'appels à l'API dont la ligne de journal correspond au motif (grep -E)
appels() {
  grep -cE -- "$1" "$FAUX_PVE_JOURNAL" || true
}
