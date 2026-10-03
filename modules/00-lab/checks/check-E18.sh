# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E18.sh — M00-E18 : Créer une VM uniquement par l'API
# À lancer depuis adm01, après au moins un cycle complet du script. Lecture seule.

title "M00-E18 — Créer une VM uniquement par l'API"

script="$HOME/lab-scripts/vm-api.sh"

# --- Le script ---
check_cmd "script ~/lab-scripts/vm-api.sh présent et exécutable" test -x "$script"
check_cmd "le script passe shellcheck sans avertissement" shellcheck "$script"
check_cmd "le script n'appelle ni qm ni pvesh, ni ssh vers pve01" \
  bash -c "test -f \"$script\" && ! grep -v '^[[:space:]]*#' \"$script\" | grep -Eq '(^|[^[:alnum:]_.-])(qm|pvesh)[[:space:]]|ssh[^#]*pve01'"
check_cmd "aucun secret de jeton écrit en clair dans le script" \
  bash -c "test -f \"$script\" && ! grep -Eiq '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \"$script\""

# --- Traces laissées sur pve01 (journal des tâches) ---
check_ssh "pve01 : clone du template 9000 exécuté par le jeton, terminé OK" "$WB_PVE_HOST" \
  'pvesh get /nodes/$(hostname)/tasks --vmid 9000 --typefilter qmclone --userfilter wb-automation --limit 200 --output-format json | tr "}" "\n" | grep -F "wb-automation@pve!lab" | grep -Eq "\"status\" *: *\"OK\""'
check_ssh "pve01 : démarrage de 5001 exécuté par le jeton, terminé OK" "$WB_PVE_HOST" \
  'pvesh get /nodes/$(hostname)/tasks --vmid 5001 --typefilter qmstart --userfilter wb-automation --limit 200 --output-format json | tr "}" "\n" | grep -F "wb-automation@pve!lab" | grep -Eq "\"status\" *: *\"OK\""'
check_ssh "pve01 : destruction de 5001 exécutée par le jeton, terminée OK" "$WB_PVE_HOST" \
  'pvesh get /nodes/$(hostname)/tasks --vmid 5001 --typefilter qmdestroy --userfilter wb-automation --limit 200 --output-format json | tr "}" "\n" | grep -F "wb-automation@pve!lab" | grep -Eq "\"status\" *: *\"OK\""'
check_ssh "pve01 : la VM 5001 n'existe plus (cycle terminé)" "$WB_PVE_HOST" \
  '! qm status 5001 >/dev/null 2>&1'
