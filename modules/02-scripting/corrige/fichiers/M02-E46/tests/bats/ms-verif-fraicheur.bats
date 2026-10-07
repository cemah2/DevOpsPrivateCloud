#!/usr/bin/env bats
# Tests de bin/ms-verif-fraicheur (chien de garde de M02-E41), ajoutés pour la livraison v1
# (M02-E46). systemctl est remplacé par un faux programme placé en tête du PATH, qui lit les
# propriétés des unités dans des fichiers : aucun accès au vrai systemd.

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  FAUX="$BATS_TEST_TMPDIR/bin"
  export FAUX_SYSTEMD="$BATS_TEST_TMPDIR/unites"
  mkdir -p "$FAUX" "$FAUX_SYSTEMD"
  # Faux « systemctl show UNITÉ -p PROPRIÉTÉ --value [--timestamp=unix] » : contenu du
  # fichier $FAUX_SYSTEMD/UNITÉ/PROPRIÉTÉ, vide s'il n'existe pas (comme une propriété inconnue).
  cat >"$FAUX/systemctl" <<'FIN'
#!/usr/bin/env bash
[[ "$1" == show ]] || exit 1
unite="$2" prop=""
shift 2
while (($#)); do
  case "$1" in
    -p) prop="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat "$FAUX_SYSTEMD/$unite/$prop" 2>/dev/null || true
FIN
  chmod +x "$FAUX/systemctl"
  export PATH="$FAUX:$PATH"
  VERIF="$RACINE/bin/ms-verif-fraicheur"
  maintenant="$(date +%s)"
  # État sain : timer chargé, actif, activé, prochaine échéance dans 10 h ;
  # dernier passage du service exécuté et réussi il y a 2 h.
  unite ms-verif-sauvegardes.timer LoadState loaded
  unite ms-verif-sauvegardes.timer ActiveState active
  unite ms-verif-sauvegardes.timer UnitFileState enabled
  unite ms-verif-sauvegardes.timer NextElapseUSecRealtime "@$((maintenant + 10 * 3600))"
  unite ms-verif-sauvegardes.timer Triggers ms-verif-sauvegardes.service
  unite ms-verif-sauvegardes.service ConditionResult yes
  unite ms-verif-sauvegardes.service Result success
  unite ms-verif-sauvegardes.service ExecMainExitTimestamp "@$((maintenant - 2 * 3600))"
}

# unite UNITÉ PROPRIÉTÉ VALEUR — fixe la valeur que renverra le faux systemctl.
unite() {
  mkdir -p "$FAUX_SYSTEMD/$1"
  printf '%s\n' "$3" >"$FAUX_SYSTEMD/$1/$2"
}

@test "contrôle frais : code 0 et une ligne OK" {
  run -0 --separate-stderr "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == "ms-verif-sauvegardes.timer"*" OK "* ]]
}

@test "timer arrêté et désactivé : code 1, les deux défauts cités" {
  unite ms-verif-sauvegardes.timer ActiveState inactive
  unite ms-verif-sauvegardes.timer UnitFileState disabled
  run -1 --separate-stderr "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"timer inactif"* && "$output" == *"non activé"* ]]
  [[ "$stderr" == *"sans passage récent réussi"* ]]
}

@test "dernier passage sauté par une condition : code 1, même si Result vaut success" {
  unite ms-verif-sauvegardes.service ConditionResult no
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"sauté"* ]]
}

@test "dernier passage trop ancien (30 h) : code 1" {
  unite ms-verif-sauvegardes.service ExecMainExitTimestamp "@$((maintenant - 30 * 3600))"
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"dernier passage il y a 30 h"* ]]
}

@test "aucun passage enregistré : code 1, jamais un faux succès" {
  rm -f "$FAUX_SYSTEMD/ms-verif-sauvegardes.service/ExecMainExitTimestamp"
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"aucun passage enregistré"* ]]
}

@test "après un redémarrage (résultat oublié par systemd), déclenchement récent du timer : code 0" {
  rm -f "$FAUX_SYSTEMD/ms-verif-sauvegardes.service/ExecMainExitTimestamp"
  unite ms-verif-sauvegardes.service ConditionResult no
  unite ms-verif-sauvegardes.timer LastTriggerUSec "@$((maintenant - 5 * 3600))"
  run -0 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *" OK "*"avant le redémarrage"* ]]
}

@test "après un redémarrage, démarrage sauté par une condition : code 1" {
  rm -f "$FAUX_SYSTEMD/ms-verif-sauvegardes.service/ExecMainExitTimestamp"
  unite ms-verif-sauvegardes.timer LastTriggerUSec "@$((maintenant - 1 * 3600))"
  unite ms-verif-sauvegardes.service ConditionTimestamp "@$((maintenant - 1 * 3600))"
  unite ms-verif-sauvegardes.service ConditionResult no
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"sauté"* ]]
}

@test "après un redémarrage, dernier déclenchement trop ancien (30 h) : code 1" {
  rm -f "$FAUX_SYSTEMD/ms-verif-sauvegardes.service/ExecMainExitTimestamp"
  unite ms-verif-sauvegardes.timer LastTriggerUSec "@$((maintenant - 30 * 3600))"
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"dernier déclenchement il y a 30 h"* ]]
}

@test "prochaine échéance trop lointaine (planification modifiée) : code 1" {
  unite ms-verif-sauvegardes.timer NextElapseUSecRealtime "@$((maintenant + 72 * 3600))"
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"prochaine échéance dans 72 h"* ]]
}

@test "timer non chargé (fichier supprimé ou erroné) : code 1" {
  unite ms-verif-sauvegardes.timer LoadState not-found
  run -1 "$VERIF" ms-verif-sauvegardes.timer
  [[ "$output" == *"timer non chargé (not-found)"* ]]
}

@test "usage : sans timer, nom invalide ou seuil invalide renvoient 2" {
  run -2 "$VERIF"
  run -2 "$VERIF" 'ms-verif;reboot.timer'
  run -2 "$VERIF" ms-verif-sauvegardes.service
  run -2 "$VERIF" --age-max 0 ms-verif-sauvegardes.timer
  run -0 "$VERIF" --help
  [[ "$output" == Usage* ]]
}
