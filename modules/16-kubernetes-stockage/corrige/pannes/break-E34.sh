# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E34.sh — M16-E34 « Restaurer la base de MédiAgenda en temps limité » (CHRONO, INC-4334).
#
# Ce n'est pas une panne à diagnostiquer : c'est l'INCIDENT de l'exercice chronométré.
#   1. vérifie les prérequis (mediagenda-db sain, archivage continu actif, sauvegarde de base
#      « completed », API publiée qui répond) ;
#   2. crée par l'API des rendez-vous de test (praticiens dr-garnier et dr-roux) ;
#   3. note l'heure, puis supprime en UNE transaction SQL tous les rendez-vous de dr-garnier
#      (le « script de nettoyage ») dans le primaire de mediagenda-db ;
#   4. après 90 s, crée par l'API des rendez-vous « postérieurs », dont un qui reprend le créneau
#      d'un rendez-vous supprimé (conflit, exigence 3 du dossier) ;
#   5. enregistre la vérité de référence pour check-E34.sh dans ~/.local/state/workbook/M16-E34/.
# --annuler supprime tous les rendez-vous créés par l'injection (état d'avant l'injection) et la
# vérité de référence. Il ne touche à rien d'autre (les clusters temporaires de l'apprenant
# restent à sa charge).
#
# Agit uniquement sur mediagenda-recette (PLAN §4.10 « Pannes du bloc C »). Les écritures SQL se
# font par « kubectl exec » dans le conteneur postgres du primaire (psql en postgres, socket local).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E34_NS=mediagenda-recette
_E34_CLUSTER=mediagenda-db
_E34_API="${WB_M16_API_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
_E34_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M16-E34"
_E34_PRATICIEN=dr-garnier
_E34_AUTRE=dr-roux

# --- Accès à la base -------------------------------------------------------------------------

_e34_primaire() {
  wb_kubectl get cluster "$_E34_CLUSTER" -n "$_E34_NS" -o jsonpath='{.status.currentPrimary}' 2>/dev/null
}

# Base applicative : celle de bootstrap.initdb (défaut CloudNativePG : app).
_e34_base() {
  local b
  b="$(wb_kubectl get cluster "$_E34_CLUSTER" -n "$_E34_NS" -o jsonpath='{.spec.bootstrap.initdb.database}' 2>/dev/null)"
  printf '%s\n' "${b:-app}"
}

# _e34_sql "REQUÊTE" — exécute la requête sur le primaire (sortie brute, sans en-tête).
_e34_sql() {
  local p b
  p="$(_e34_primaire)" || return 1
  [[ -n "$p" ]] || return 1
  b="$(_e34_base)"
  wb_kubectl exec -n "$_E34_NS" "$p" -c postgres -- \
    psql -X -q -At -v ON_ERROR_STOP=1 -d "$b" -c "$1"
}

# --- Accès à l'API -----------------------------------------------------------------------------

# _e34_creer PRATICIEN DÉBUT_ISO PATIENT MOTIF — crée un rendez-vous, écrit le JSON sur stdout.
# Code 3 si le créneau est déjà pris (409).
_e34_creer() {
  local corps code sortie
  corps="$(jq -cn --arg pr "$1" --arg d "$2" --arg pa "$3" --arg m "$4" \
    '{patient: $pa, praticien: $pr, debut: $d, duree_minutes: 30, motif: $m}')"
  sortie="$(mktemp)"
  code="$(curl -s -o "$sortie" -w '%{http_code}' --max-time 10 -H 'Content-Type: application/json' \
    -d "$corps" "$_E34_API/api/v1/rendez-vous")" || code=000
  if [[ "$code" == 201 ]]; then
    cat "$sortie"; rm -f "$sortie"; return 0
  fi
  rm -f "$sortie"
  [[ "$code" == 409 ]] && return 3
  return 1
}

# _e34_debut JOUR HH:MM — horodatage ISO avec le décalage de Paris ce jour-là.
_e34_debut() { TZ=Europe/Paris date -d "$1 $2" +%Y-%m-%dT%H:%M:%S%:z; }

# --- Prérequis ---------------------------------------------------------------------------------

_e34_prerequis() {
  local c
  if ! command -v jq >/dev/null || ! command -v curl >/dev/null; then
    wb_avert "jq et curl sont nécessaires sur adm01"; return 1
  fi
  c="$(wb_kubectl get cluster "$_E34_CLUSTER" -n "$_E34_NS" -o json 2>/dev/null)" \
    || { wb_avert "cluster $_E34_CLUSTER introuvable dans $_E34_NS"; return 1; }
  jq -e '.status.phase == "Cluster in healthy state"' >/dev/null <<<"$c" \
    || { wb_avert "$_E34_CLUSTER n'est pas sain : termine E18-E19 (ou attends la fin d'une opération)"; return 1; }
  jq -e 'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' >/dev/null <<<"$c" \
    || { wb_avert "l'archivage continu de $_E34_CLUSTER n'est pas actif : sans WAL archivés, l'exercice est impossible"; return 1; }
  wb_kubectl get backups.postgresql.cnpg.io -n "$_E34_NS" -o json 2>/dev/null \
    | jq -e --arg c "$_E34_CLUSTER" 'any(.items[]; .spec.cluster.name == $c and .status.phase == "completed")' >/dev/null \
    || { wb_avert "aucune sauvegarde de base « completed » de $_E34_CLUSTER"; return 1; }
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_E34_API/pret")" == 200 ]] \
    || { wb_avert "l'API $_E34_API ne répond pas « prête »"; return 1; }
  _e34_sql "SELECT 1" >/dev/null || { wb_avert "impossible d'exécuter psql dans le primaire"; return 1; }
}

# --- Injection -----------------------------------------------------------------------------------

panne_E34_v1() {
  local jour h r f debut i ids_avant=() suppr t_err tl uid cree conflit_debut conflit_id
  _e34_prerequis || return 1
  mkdir -p "$_E34_ETAT" && chmod 700 "$_E34_ETAT"
  : >"$_E34_ETAT/crees.ids"

  # 1. Rendez-vous de départ : 8 pour dr-garnier, 3 pour dr-roux, un jour libre de 2029.
  for _ in 1 2 3 4 5; do
    jour="$(date -d "2029-01-07 +$((RANDOM % 330)) days" +%F)"
    r=0
    for h in 09:00 09:30 10:00 10:30 11:00 11:30 14:00 14:30; do
      i=$(( ${#ids_avant[@]} + 1 ))
      if f="$(_e34_creer "$_E34_PRATICIEN" "$(_e34_debut "$jour" "$h")" "Patient E34-$i" "Suivi E34")"; then
        ids_avant+=("$(jq -r .id <<<"$f")")
        jq -r .id <<<"$f" >>"$_E34_ETAT/crees.ids"
      else
        r=$?; break
      fi
    done
    ((r == 0)) && break
    ((r == 3)) || return 1
    # Créneau déjà pris ce jour-là : on nettoie ce qui a été créé et on change de jour.
    _e34_nettoyer_crees; ids_avant=()
  done
  ((${#ids_avant[@]} == 8)) || return 1
  for h in 09:00 09:30 10:00; do
    f="$(_e34_creer "$_E34_AUTRE" "$(_e34_debut "$jour" "$h")" "Patient E34-R$h" "Contrôle E34")" || return 1
    jq -r .id <<<"$f" >>"$_E34_ETAT/crees.ids"
  done
  printf '%s\n' "$jour" >"$_E34_ETAT/jour"

  # Laisse le temps aux écritures d'être nettement antérieures à l'erreur.
  sleep 60

  # 2. L'erreur : heure notée juste avant, suppression en une transaction, lignes conservées.
  tl="$(wb_kubectl get cluster "$_E34_CLUSTER" -n "$_E34_NS" -o jsonpath='{.status.timelineID}')"
  uid="$(wb_kubectl get cluster "$_E34_CLUSTER" -n "$_E34_NS" -o jsonpath='{.metadata.uid}')"
  t_err="$(TZ=Europe/Paris date '+%Y-%m-%d %H:%M:%S%:z')"
  suppr="$(_e34_sql "WITH d AS (DELETE FROM rendez_vous WHERE praticien = '$_E34_PRATICIEN' RETURNING *)
    SELECT coalesce(json_agg(json_build_object('id', id, 'patient', patient, 'praticien', praticien,
      'debut', to_char(debut AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'), 'duree_minutes', duree_minutes,
      'motif', motif, 'cree_le', to_char(cree_le AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')) ORDER BY id), '[]') FROM d")" \
    || return 1
  # Écrit AVANT tout contrôle : en cas d'échec, --annuler (appelé par lab/bin/break) doit pouvoir
  # remettre les rendez-vous de dr-garnier qui existaient avant l'injection.
  printf '%s\n' "$suppr" >"$_E34_ETAT/supprimes.json"
  chmod 600 "$_E34_ETAT/supprimes.json"
  jq -e 'length >= 8' >/dev/null <<<"$suppr" || return 1

  # 3. La vie continue : écritures postérieures, dont un conflit sur le créneau de 10:00.
  sleep 90
  conflit_debut="$(_e34_debut "$jour" 10:00)"
  : >"$_E34_ETAT/apres.ids"
  for f in "$_E34_AUTRE|14:00" "$_E34_AUTRE|14:30" "$_E34_PRATICIEN|10:00" "$_E34_PRATICIEN|16:00"; do
    debut="$(_e34_debut "$jour" "${f#*|}")"
    cree="$(_e34_creer "${f%%|*}" "$debut" "Patient E34-P${f#*|}" "Pris après l'incident")" || return 1
    jq -r .id <<<"$cree" | tee -a "$_E34_ETAT/crees.ids" >>"$_E34_ETAT/apres.ids"
  done
  # Identifiant du rendez-vous supprimé dont le créneau a été repris (comparaison des instants).
  conflit_id="$(jq -r --arg d "$(date -u -d "$conflit_debut" +%Y-%m-%dT%H:%M:%SZ)" \
    '.[] | select(.debut == $d) | .id' "$_E34_ETAT/supprimes.json" | head -n 1)"
  [[ -n "$conflit_id" ]] || return 1

  jq -n --arg t "$t_err" --arg tl "$tl" --arg uid "$uid" --arg c "$conflit_id" --arg p "$_E34_PRATICIEN" \
    --arg inj "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{heure_erreur: $t, timeline: ($tl | tonumber), cluster_uid: $uid, id_conflit: ($c | tonumber),
      praticien: $p, injection: $inj}' >"$_E34_ETAT/etat.json"
  chmod 600 "$_E34_ETAT"/*
}

# _e34_nettoyer_crees — supprime par SQL les rendez-vous créés par l'injection (liste crees.ids).
_e34_nettoyer_crees() {
  local ids
  [[ -s "$_E34_ETAT/crees.ids" ]] || return 0
  ids="$(grep -E '^[0-9]+$' "$_E34_ETAT/crees.ids" | paste -sd, -)"
  [[ -n "$ids" ]] || return 0
  _e34_sql "DELETE FROM rendez_vous WHERE id IN ($ids)" >/dev/null
  : >"$_E34_ETAT/crees.ids"
}

verifier_E34() {
  local id code
  [[ -s "$_E34_ETAT/etat.json" && -s "$_E34_ETAT/supprimes.json" ]] || return 1
  # Les rendez-vous supprimés ne sont plus servis par l'API, les postérieurs le sont.
  for id in $(jq -r '.[].id' "$_E34_ETAT/supprimes.json"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_E34_API/api/v1/rendez-vous/$id")"
    [[ "$code" == 404 ]] || return 1
  done
  while read -r id; do
    [[ -n "$id" ]] || continue
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_E34_API/api/v1/rendez-vous/$id")"
    [[ "$code" == 200 ]] || return 1
  done <"$_E34_ETAT/apres.ids"
}

annuler_E34() {
  local etrangers q="'"
  if [[ -d "$_E34_ETAT" ]]; then
    # Rendez-vous de dr-garnier qui existaient AVANT l'injection (créés par toi) : remis tels quels.
    if [[ -s "$_E34_ETAT/supprimes.json" ]]; then
      etrangers="$(jq -c --rawfile c "$_E34_ETAT/crees.ids" \
        '($c | split("\n") | map(select(length > 0) | tonumber)) as $ids | map(select(.id as $i | $ids | index($i) | not))' \
        "$_E34_ETAT/supprimes.json" 2>/dev/null)" || etrangers='[]'
      if jq -e 'length > 0' >/dev/null <<<"$etrangers"; then
        _e34_sql "INSERT INTO rendez_vous OVERRIDING SYSTEM VALUE
          SELECT * FROM json_populate_recordset(NULL::rendez_vous, '${etrangers//$q/$q$q}')
          ON CONFLICT DO NOTHING" >/dev/null || wb_avert "rendez-vous antérieurs non réinsérés : voir $_E34_ETAT/supprimes.json"
      fi
    fi
    _e34_nettoyer_crees || wb_avert "rendez-vous de l'injection non supprimés : liste dans $_E34_ETAT/crees.ids"
    if [[ ! -s "$_E34_ETAT/crees.ids" ]]; then
      rm -rf "$_E34_ETAT"
    fi
  fi
}

symptome_E34() {
  local t
  t="$(jq -r .heure_erreur "$_E34_ETAT/etat.json")"
  wb_symptome "INC-4334 — rendez-vous disparus (recette de MédiAgenda)" \
    "Le secrétariat ne voit plus aucun rendez-vous de « $_E34_PRATICIEN » dans l'agenda de recette." \
    "Un script de nettoyage a été lancé par erreur sur la base de recette." \
    "Heure de lancement du script (heure de Paris) : $t" \
    "D'autres rendez-vous ont été pris depuis : ils doivent être conservés." \
    "" \
    "T0 = maintenant. Ouvre le dossier : modules/16-kubernetes-stockage/ressources/E34-dossier-chrono.md" \
    "Vérification à T3 : lab/bin/check 16 34"
}

resume_E34() { echo "tous les rendez-vous d'un praticien ont disparu de la recette de MédiAgenda"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then main() { wb_main 16 E34 1 "$@"; }; fi
