# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M05-E36 « Panne : "Error acquiring the state lock" »
#
# Un verrou d'état (objet <clé>.tflock du compartiment tofu-state, use_lockfile) bloque les plans
# et apply. Variantes :
#   1. verrou orphelin sur l'état socle, laissé par un job CI « apply » interrompu
#      (Who gitlab-runner@runner01, posé il y a 9 h) : plus aucun processus ne le détient ;
#   2. verrou VIVANT sur l'état socle : une session « tofu console » oubliée sur adm01 (processus
#      détaché, entrée standard ouverte) le détient réellement — un force-unlock serait une faute ;
#   3. verrou orphelin sur l'état envs/lab-m05, laissé par un « tofu plan » de adm01 dont la
#      session SSH a été coupée (Who admin@adm01, plus aucun processus) ;
#   4. objet de verrou illisible sur l'état socle (reste d'un essai d'écriture conditionnelle à la
#      main, M05-E12) : OpenTofu ne peut pas en lire l'ID, « tofu force-unlock » est inutilisable.
# L'injection refuse si un verrou existe déjà. Annulation : l'objet de verrou n'est supprimé que
# s'il est encore celui posé par la panne (même empreinte) ; la console de la v2 est fermée
# proprement (fin de son entrée standard), ce qui libère le verrou.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

# _e36_cle N — clé d'état visée par la variante N.
_e36_cle() {
  if [[ "$1" == 3 ]]; then printf '%s\n' "$_M05_CLE_ENVS"; else printf '%s\n' "$_M05_CLE_SOCLE"; fi
}

_e36_verrou_present() {
  m05_aws s3api head-object --bucket "$_M05_BUCKET" --key "$1.tflock" >/dev/null 2>&1
}

# _e36_poser_objet CLÉ FICHIER — écriture conditionnelle (comme OpenTofu) de l'objet de verrou.
_e36_poser_objet() {
  m05_aws s3api put-object --bucket "$_M05_BUCKET" --key "$1.tflock" --body "$2" \
    --content-type application/json --if-none-match '*' >/dev/null 2>&1
}

_e36_version_tofu() {
  tofu version -json 2>/dev/null | jq -r '.terraform_version // empty' 2>/dev/null || true
}

_e36_console() {
  local d pid i
  d="$(m05_etat E36)"
  rm -f -- "$d/console.in"
  mkfifo -m 600 "$d/console.in" || return 1
  (
    cd "$_M05_SOCLE" || exit 1
    m05_charger_env
    unset TF_INPUT
    exec setsid tofu console -no-color <"$d/console.in" >"$d/console.out" 2>&1
  ) &
  pid=$!
  # Garde l'entrée standard de la console ouverte (sans rien y écrire).
  (exec setsid sleep 864000 >"$d/console.in") &
  printf '%s\n' "$!" >"$d/console.tenue"
  printf '%s\n' "$pid" >"$d/console.pid"
  for i in $(seq 1 30); do
    if _e36_verrou_present "$_M05_CLE_SOCLE"; then
      m05_journal E36 "tofu console (pid $pid) détient le verrou de $_M05_CLE_SOCLE"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 2
  done
  wb_avert "la console OpenTofu n'a pas pris le verrou ($i essais) : $(tail -n 3 "$d/console.out" 2>/dev/null | tr '\n' ' ')"
  return 1
}

_e36_fermer_console() {
  local d pid tenue
  d="$(m05_etat E36)"
  pid="$(m05_lire E36 console.pid)"
  tenue="$(m05_lire E36 console.tenue)"
  if [[ -n "$tenue" ]] && ps -o args= -p "$tenue" 2>/dev/null | grep -q '^sleep 864000'; then
    kill "$tenue" 2>/dev/null || true
  fi
  if [[ -n "$pid" ]]; then
    local i
    for i in $(seq 1 20); do
      ps -o args= -p "$pid" 2>/dev/null | grep -q 'tofu console' || break
      sleep 1
    done
    # La console ignore SIGINT et SIGTERM (vérifié avec OpenTofu 1.13.1) ; SIGHUP/SIGKILL la
    # tueraient sans rendre le verrou. Elle se ferme proprement sur « exit » lu sur son entrée.
    if ps -o args= -p "$pid" 2>/dev/null | grep -q 'tofu console'; then
      # shellcheck disable=SC2016  # $1 développé par le bash enfant
      timeout 5 bash -c 'echo exit > "/proc/$1/fd/0"' _ "$pid" 2>/dev/null || true
      for i in $(seq 1 10); do
        ps -o args= -p "$pid" 2>/dev/null | grep -q 'tofu console' || break
        sleep 1
      done
    fi
    if ps -o args= -p "$pid" 2>/dev/null | grep -q 'tofu console'; then
      # Dernier recours : arrêt brutal, puis retrait du verrou s'il est bien celui d'une console
      # (OperationTypeInvalid) posée depuis ce compte sur cet hôte.
      kill -KILL "$pid" 2>/dev/null || true
      sleep 1
      if m05_aws s3 cp "s3://$_M05_BUCKET/$_M05_CLE_SOCLE.tflock" - 2>/dev/null \
         | jq -e --arg w "$(id -un)@$(hostname)" '.Operation == "OperationTypeInvalid" and .Who == $w' >/dev/null 2>&1; then
        m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "$_M05_CLE_SOCLE.tflock" >/dev/null 2>&1 || true
        m05_journal E36 "annulation : console tuée, son verrou retiré"
      fi
    fi
    m05_journal E36 "annulation : console OpenTofu (pid $pid) fermée"
  fi
  rm -f -- "$d/console.in" "$d/console.pid" "$d/console.tenue" "$d/console.out"
}

_m05E36_une() {
  local n="$1" cle d f v id cree qui op
  cle="$(_e36_cle "$n")"
  d="$(m05_etat E36)"
  if _e36_verrou_present "$cle"; then
    wb_avert "un verrou existe déjà sur $cle : libère-le avant d'injecter"
    return 1
  fi
  m05_ecrire E36 cle "$cle"
  if [[ "$n" == 2 ]]; then
    _e36_console || { _e36_fermer_console; return 1; }
    return 0
  fi
  f="$d/verrou.json"
  case "$n" in
    1 | 3)
      v="$(_e36_version_tofu)"
      id="$(cat /proc/sys/kernel/random/uuid)"
      if [[ "$n" == 1 ]]; then
        qui="gitlab-runner@runner01"
        op="OperationTypeApply"
        cree="$(date -u -d '9 hours ago' +%Y-%m-%dT%H:%M:%S.%NZ)"
      else
        qui="admin@adm01"
        op="OperationTypePlan"
        cree="$(date -u -d '14 hours ago' +%Y-%m-%dT%H:%M:%S.%NZ)"
      fi
      jq -cn --arg id "$id" --arg op "$op" --arg qui "$qui" --arg v "${v:-1.13.0}" \
        --arg c "$cree" --arg p "$_M05_BUCKET/$cle" \
        '{ID: $id, Operation: $op, Info: "", Who: $qui, Version: $v, Created: $c, Path: $p}' >"$f"
      ;;
    4)
      printf 'essai M05-E12 : écriture conditionnelle (if-none-match) — à supprimer\n' >"$f"
      ;;
  esac
  _e36_poser_objet "$cle" "$f" || { wb_avert "écriture de $cle.tflock impossible"; return 1; }
  m05_ecrire E36 empreinte "$(m05_aws s3api head-object --bucket "$_M05_BUCKET" --key "$cle.tflock" 2>/dev/null | jq -r '.ETag // empty')"
  m05_journal E36 "objet de verrou $cle.tflock posé ($(head -c 120 "$f"))"
}

panne_E36_v1() { m05_prerequis socle envs && m05_essayer E36 4 1; }
panne_E36_v2() { m05_prerequis socle envs && m05_essayer E36 4 2; }
panne_E36_v3() { m05_prerequis socle envs && m05_essayer E36 4 3; }
panne_E36_v4() { m05_prerequis socle envs && m05_essayer E36 4 4; }

verifier_E36() {
  local cle pid
  cle="$(m05_lire E36 cle)"
  [[ -n "$cle" ]] && _e36_verrou_present "$cle" || return 1
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  if [[ "${WB_VAR:-}" == 2 ]]; then
    pid="$(m05_lire E36 console.pid)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
  fi
}

annuler_E36() {
  local cle etag actuel
  _e36_fermer_console || true
  cle="$(m05_lire E36 cle)"
  etag="$(m05_lire E36 empreinte)"
  if [[ -n "$cle" && -n "$etag" ]]; then
    actuel="$(m05_aws s3api head-object --bucket "$_M05_BUCKET" --key "$cle.tflock" 2>/dev/null | jq -r '.ETag // empty' 2>/dev/null || true)"
    if [[ "$actuel" == "$etag" ]]; then
      m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "$cle.tflock" >/dev/null 2>&1 \
        && m05_journal E36 "annulation : objet de verrou $cle.tflock supprimé"
    else
      m05_journal E36 "annulation : $cle.tflock absent ou remplacé depuis l'injection, laissé tel quel"
    fi
  fi
  rm -f -- "$(m05_etat E36)/cle" "$(m05_etat E36)/empreinte" "$(m05_etat E36)/verrou.json" "$(m05_etat E36)/variante"
}

resume_E36() {
  echo "« tofu plan » s'arrête sur « Error acquiring the state lock » : plus personne ne peut planifier ni appliquer."
}

# shellcheck disable=SC2088  # chemin affiché tel quel dans le ticket
symptome_E36() {
  local ou="~/src/infra/socle"
  # shellcheck disable=SC2031
  if [[ "${WB_VAR:-}" == 3 ]]; then ou="~/src/infra/envs/lab-m05"; fi
  wb_symptome "Ticket INC-3242 — De : Julien Petit" \
    "Impossible de lancer le moindre plan ce matin dans $ou : OpenTofu répond" \
    "« Error acquiring the state lock » et s'arrête. Le pipeline de ma MR échoue pareil." \
    "Lucas me conseille « tofu force-unlock, ça marche toujours ». Je préfère te demander avant." \
    "Débloque-nous, mais sans risquer de corrompre l'état, et dis-moi qui détenait ce verrou." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 05 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E36 4 "$@"; }
fi
