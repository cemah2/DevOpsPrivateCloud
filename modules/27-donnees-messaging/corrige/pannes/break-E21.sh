# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et SQL entre apostrophes
# break-E21.sh — M27-E21 « Panne : la migration bloque la mise en production » (RECETTE seulement)
#
# Chaque variante est suivie d'une synchronisation de l'Application de recette de MédiAgenda (comme
# « argocd app sync », au nom de lucas.martin), qui rejoue le Job hook mediagenda-migrations (Flyway).
#   1. Session « idle in transaction » ouverte par « Lucas » dans le primaire (psql, application_name psql) :
#      BEGIN ; ALTER TABLE flyway_schema_history ADD COLUMN ticket_lucas text ; … puis plus rien.
#      L'ALTER tient un verrou ACCESS EXCLUSIVE sur l'historique : le SELECT de Flyway attend (sans fin
#      sans lock_timeout, jusqu'au délai du Job ; ou échoue vite et clairement si le Job pose un lock_timeout). Annulation : pg_terminate_backend de cette session
#      seulement (l'ALTER non validé est annulé avec elle).
#   2. La dernière migration versionnée appliquée (V4 au corrigé de M27-E06) est marquée en échec dans
#      flyway_schema_history (success = false) : « Detected failed migration to version … » au validate du
#      migrate. (Une ligne en échec d'une version ≥ 90 serait « future » et ignorée par Flyway : d'où ce choix.)
#   3. La somme de contrôle de cette même migration est décalée : « Migration checksum mismatch ».
# Annulation de 2 et 3 : la valeur d'origine est remise si la ligne porte encore la valeur injectée. Aucune
# ligne applicative n'est touchée ; aucune migration n'est créée ni supprimée ; jamais mediagenda-prod.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_E21_MARQUE=ticket_lucas

# _e21_derniere — « installed_rank|version|checksum » de la dernière migration versionnée SQL réussie.
_e21_derniere() {
  m27_psql "SELECT installed_rank || '|' || version || '|' || checksum FROM flyway_schema_history
            WHERE success AND type = 'SQL' AND version IS NOT NULL AND checksum IS NOT NULL
            ORDER BY installed_rank DESC LIMIT 1;" | grep .
}

_e21_job_en_echec() {
  wb_kubectl -n "$_M27_NS_AGENDA" logs "job/$_M27_JOB_MIGR" --tail=200 2>/dev/null | grep -Eqi "$1"
}

# --- Variante 1 : session oisive en transaction qui verrouille l'historique -------------------------

_e21_v1_poser() {
  local p
  [[ "$(m27_psql "SELECT to_regclass('public.flyway_schema_history') IS NOT NULL;")" == t ]] || return 10
  p="$(m27_pg_primaire)" || return 1
  # Session détachée DANS le conteneur postgres du primaire (elle survit à la fin de kubectl exec) ;
  # psql lit son entrée sur un tube que « sleep » garde ouvert : la transaction reste ouverte, oisive.
  wb_kubectl -n "$_M27_NS_AGENDA" exec -i "$p" -c postgres -- bash -s >/dev/null 2>&1 <<SH || return 1
nohup setsid bash -c '{ printf "%s\n" "SET application_name = '"'"'psql'"'"';" "BEGIN;" "ALTER TABLE public.flyway_schema_history ADD COLUMN $_E21_MARQUE text;"; sleep 21600; } | psql -X -q -d mediagenda' </dev/null >/dev/null 2>&1 &
SH
  m27_ecrire E21 v1-primaire "$p"
  m27_attendre 60 _e21_v1_session >/dev/null || return 1
  m27_journal E21 "session oisive en transaction ouverte sur $p (verrou sur flyway_schema_history)"
  m27_argo_synchroniser "$_M27_APP_AGENDA" || return 1
}
_e21_v1_session() {
  m27_psql "SELECT pid FROM pg_stat_activity WHERE datname = 'mediagenda' AND state LIKE 'idle in transaction%'
            AND query LIKE '%$_E21_MARQUE%' LIMIT 1;" | grep -E '^[0-9]+$'
}
# Constat : la session tient toujours son verrou ET Flyway s'y est heurté (session bloquée par elle, ou,
# si le Job pose un lock_timeout (M27-E06), échec « lock timeout » dans son journal).
_e21_v1_constat() {
  local pid
  pid="$(_e21_v1_session)" || return 1
  [[ "$(m27_psql "SELECT count(*) FROM pg_stat_activity WHERE $pid = ANY(pg_blocking_pids(pid));")" -ge 1 ]] ||
    _e21_job_en_echec 'lock timeout|canceling statement due to lock'
}
_e21_v1_defaire() {
  local pid
  pid="$(_e21_v1_session 2>/dev/null)" || pid=""
  if [[ -n "$pid" ]]; then
    m27_psql "SELECT pg_terminate_backend($pid);" >/dev/null 2>&1 || true
    m27_journal E21 "session $pid terminée"
  fi
  m27_oublier E21 v1-primaire
}

# --- Variantes 2 et 3 : historique Flyway altéré ------------------------------------------------------

_e21_v23_poser() {
  local n="$1" d rang version somme
  d="$(_e21_derniere)" || return 10
  IFS='|' read -r rang version somme <<<"$d"
  m27_ecrire E21 "v$n-ligne" "$rang|$version|$somme"
  if [[ "$n" == 2 ]]; then
    m27_psql "UPDATE flyway_schema_history SET success = false WHERE installed_rank = $rang AND success;" >/dev/null || return 1
    m27_journal E21 "migration $version (rang $rang) marquée en échec"
  else
    m27_psql "UPDATE flyway_schema_history SET checksum = $((somme + 1)) WHERE installed_rank = $rang AND checksum = $somme;" >/dev/null || return 1
    m27_journal E21 "somme de contrôle de la migration $version (rang $rang) décalée"
  fi
  m27_argo_synchroniser "$_M27_APP_AGENDA" || return 1
}
_e21_v23_altere() {
  local n="$1" rang version somme
  IFS='|' read -r rang version somme <<<"$(m27_lire E21 "v$n-ligne")"
  [[ -n "$rang" ]] || return 1
  if [[ "$n" == 2 ]]; then
    [[ "$(m27_psql "SELECT success FROM flyway_schema_history WHERE installed_rank = $rang;")" == f ]]
  else
    [[ "$(m27_psql "SELECT checksum FROM flyway_schema_history WHERE installed_rank = $rang;")" == "$((somme + 1))" ]]
  fi
}
_e21_v23_defaire() {
  local n="$1" rang version somme
  IFS='|' read -r rang version somme <<<"$(m27_lire E21 "v$n-ligne")"
  if [[ -n "$rang" ]]; then
    if [[ "$n" == 2 ]]; then
      m27_psql "UPDATE flyway_schema_history SET success = true WHERE installed_rank = $rang AND NOT success;" >/dev/null 2>&1 || true
    else
      m27_psql "UPDATE flyway_schema_history SET checksum = $somme WHERE installed_rank = $rang AND checksum = $((somme + 1));" >/dev/null 2>&1 || true
    fi
    m27_journal E21 "historique Flyway remis (rang $rang) s'il portait encore la valeur de la panne"
  fi
  m27_oublier E21 "v$n-ligne"
}

_e21_v2_poser() { _e21_v23_poser 2; }
_e21_v3_poser() { _e21_v23_poser 3; }
_e21_v2_constat() { _e21_v23_altere 2 && _e21_job_en_echec 'Detected failed migration'; }
_e21_v3_constat() { _e21_v23_altere 3 && _e21_job_en_echec 'checksum mismatch'; }
_e21_v2_defaire() { _e21_v23_defaire 2; }
_e21_v3_defaire() { _e21_v23_defaire 3; }

# --- Mécanique commune --------------------------------------------------------------------------------

_m27E21_une() {
  local n="$1" rc=0
  "_e21_v${n}_poser" || rc=$?
  if ((rc != 0)); then
    "_e21_v${n}_defaire" || true
    return "$rc"
  fi
  m27_debut E21
  if ! m27_attendre 420 "_e21_v${n}_constat"; then
    "_e21_v${n}_defaire" || true
    return 10
  fi
}

_e21_preparer() {
  m27_preparer base || return 1
  wb_kubectl -n argocd get applications.argoproj.io "$_M27_APP_AGENDA" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and (.status.operationState.phase // "Succeeded") == "Succeeded"' >/dev/null || {
    echo "L'Application $_M27_APP_AGENDA n'est pas Synced avec une dernière opération réussie : répare d'abord (lab/bin/check 27 21)." >&2
    return 1
  }
}

panne_E21_v1() { _e21_preparer && m27_essayer E21 3 1; }
panne_E21_v2() { _e21_preparer && m27_essayer E21 3 2; }
panne_E21_v3() { _e21_preparer && m27_essayer E21 3 3; }

verifier_E21() {
  case "$WB_VAR" in
    1) _e21_v1_session >/dev/null ;;
    2) _e21_v23_altere 2 ;;
    3) _e21_v23_altere 3 ;;
    *) return 1 ;;
  esac
}

annuler_E21() {
  case "${WB_VAR:-}" in
    [1-3]) "_e21_v${WB_VAR}_defaire" ;;
    *) local v; for v in 1 2 3; do "_e21_v${v}_defaire" || true; done ;;
  esac
  m27_argo_rafraichir "$_M27_APP_AGENDA"
  m27_oublier E21 debut
  m27_journal E21 "annulation (relance la synchronisation de $_M27_APP_AGENDA si elle a échoué)"
}

resume_E21() {
  echo "La synchronisation de la recette de MédiAgenda reste bloquée ou échoue sur le Job de migration."
}

symptome_E21() {
  wb_symptome "Ticket INC-5421 — De : Julien Petit, en copie Karim Benali" \
    "Lucas a relancé la synchronisation de la recette de MédiAgenda ce matin pour une répétition de mise" \
    "en production : Argo CD reste sur le Job de migration (« Syncing »), puis l'opération échoue. On n'a" \
    "ajouté aucune migration depuis la dernière livraison. La mise en production est prévue demain." \
    "Trouve ce qui bloque, débloque sans abîmer le schéma, et dis-moi comment on évite que ça recommence." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 27 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 27 E21 3 "$@"; }
fi
