# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et SQL entre apostrophes
# break-E19.sh — M27-E19 « Panne : les écritures de MédiAgenda sont bloquées » (RECETTE seulement)
#
#   1. Les DEUX réplicas de mediagenda-db (recette) sont isolés par l'annotation cnpg.io/fencedInstances
#      (PostgreSQL arrêté dans leurs pods) ; avec la réplication synchrone en dataDurability: required,
#      chaque validation attend un réplica qui ne viendra pas : les écritures restent en « SyncRep ».
#      Objet modifié en place (la base de recette est appliquée depuis plateforme/k8s par kubectl) ;
#      l'annulation ne retire l'annotation que si elle porte encore la valeur injectée.
#   2. Le pooler mediagenda-db-pooler-rw reçoit default_pool_size 1, reserve_pool_size 0 et max_client_conn 8 :
#      les clients s'entassent (cl_waiting) puis sont refusés (« no more connections allowed ») ;
#      par un commit de Lucas (overlay recette de mediagenda/deploiement si Argo CD suit le Pooler, sinon
#      plateforme/k8s + application en place).
#   3. « Moindre privilège » de Lucas : un script SQL commité dans plateforme/k8s
#      (espaces/mediagenda-recette/sql/moindre-privilege.sql) et joué sur la recette retire INSERT, UPDATE
#      et DELETE au rôle de groupe mediagenda_api : les écritures de l'API échouent (permission denied),
#      les lectures passent. Annulation : chaque droit rendu sur les tables qui l'avaient (état noté avant).
# Aucune donnée n'est touchée ; jamais mediagenda-prod.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_E19_PARAMS='{"default_pool_size":"1","reserve_pool_size":"0","max_client_conn":"8"}'
_E19_SQL_CHEMIN=espaces/mediagenda-recette/sql/moindre-privilege.sql

# --- Variante 1 : deux réplicas isolés --------------------------------------------------------------

_e19_v1_poser() {
  local c prim rep
  c="$(wb_kubectl -n "$_M27_NS_AGENDA" get cluster.postgresql.cnpg.io "$_M27_CLUSTER" -o json)" || return 1
  [[ -z "$(jq -r '.metadata.annotations["cnpg.io/fencedInstances"] // empty' <<<"$c")" ]] || return 10
  jq -e '.spec.postgresql.synchronous.dataDurability // "required" | . == "required"' <<<"$c" >/dev/null || return 10
  jq -e '(.spec.postgresql.synchronous.number // 0) >= 1' <<<"$c" >/dev/null || return 10
  prim="$(jq -r '.status.currentPrimary' <<<"$c")"
  rep="$(jq -c --arg p "$prim" '[.status.instanceNames[] | select(. != $p)]' <<<"$c")"
  [[ "$(jq 'length' <<<"$rep")" -ge 1 ]] || return 10
  wb_k8s_sauver cluster.postgresql.cnpg.io "$_M27_CLUSTER" "$_M27_NS_AGENDA"
  m27_ecrire E19 v1-valeur "$rep"
  wb_kubectl -n "$_M27_NS_AGENDA" annotate cluster.postgresql.cnpg.io "$_M27_CLUSTER" "cnpg.io/fencedInstances=$rep" >/dev/null || return 1
  m27_journal E19 "réplicas $rep isolés"
}
_e19_v1_constat() {
  local n
  n="$(m27_psql "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';")" || return 1
  [[ "$n" == 0 ]] && [[ -n "$(m27_psql 'SHOW synchronous_standby_names;')" ]]
}
_e19_v1_defaire() {
  local v cur
  v="$(m27_lire E19 v1-valeur)"
  [[ -n "$v" ]] || return 0
  cur="$(wb_kubectl -n "$_M27_NS_AGENDA" get cluster.postgresql.cnpg.io "$_M27_CLUSTER" -o jsonpath='{.metadata.annotations.cnpg\.io/fencedInstances}' 2>/dev/null)" || cur=""
  if [[ "$cur" == "$v" ]]; then
    wb_kubectl -n "$_M27_NS_AGENDA" annotate cluster.postgresql.cnpg.io "$_M27_CLUSTER" cnpg.io/fencedInstances- >/dev/null 2>&1 || true
    m27_journal E19 "isolement levé"
  fi
  m27_oublier E19 v1-valeur
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/M27-E19"
}

# --- Variante 2 : pooler minuscule -------------------------------------------------------------------

_e19_v2_poser() {
  local app tmp ops lieu
  wb_kubectl -n "$_M27_NS_AGENDA" get pooler.postgresql.cnpg.io "$_M27_POOLER" >/dev/null 2>&1 || return 10
  tmp="$(m27_etat E19)/tmp"
  mkdir -p "$tmp"
  app="$(m27_app_suivie pooler.postgresql.cnpg.io "$_M27_POOLER" "$_M27_NS_AGENDA")"
  ops="$(jq -nc --argjson p "$_E19_PARAMS" '[$p | to_entries[] | {op: "add", path: "/spec/pgbouncer/parameters/\(.key)", value: .value}]')"
  if [[ -n "$app" ]]; then
    # Suivi par Argo CD : correctif dans l'overlay de recette (seule la recette est touchée).
    m27_overlay_avec_patch "$_M27_DEPOT_AGENDA" '{"group":"postgresql.cnpg.io","kind":"Pooler","name":"'"$_M27_POOLER"'"}' \
      "$ops" "$tmp/overlay.yaml" || return 10
    m27_commit E19 v2 "$_M27_DEPOT_AGENDA" "recette : réserve du pooler resserrée (économie de connexions)" \
      "$_M27_OVERLAY" "$tmp/overlay.yaml" || return 1
    m27_ecrire E19 v2-lieu git
    m27_argo_rafraichir "$app"
  else
    # Appliqué depuis plateforme/k8s : commit du fichier (s'il est trouvé) PUIS application en place.
    wb_k8s_sauver pooler.postgresql.cnpg.io "$_M27_POOLER" "$_M27_NS_AGENDA"
    lieu="$(m27_doc_trouver "$_M27_DEPOT_K8S" espaces/mediagenda-recette \
      "(.kind == \"Pooler\") and (.metadata.name == \"$_M27_POOLER\")")" || lieu=""
    if [[ -n "$lieu" ]]; then
      m27_gl_fichier "$_M27_DEPOT_K8S" "${lieu%%$'\t'*}" >"$tmp/orig.yaml" || return 1
      IDX="${lieu##*$'\t'}" P="$_E19_PARAMS" yq 'with(select(documentIndex == (strenv(IDX) | to_number)); .spec.pgbouncer.parameters *= (strenv(P) | from_json))' \
        "$tmp/orig.yaml" >"$tmp/neuf.yaml" || return 1
      m27_commit E19 v2 "$_M27_DEPOT_K8S" "recette : réserve du pooler resserrée (économie de connexions)" \
        "${lieu%%$'\t'*}" "$tmp/neuf.yaml" || return 1
    fi
    wb_kubectl -n "$_M27_NS_AGENDA" patch pooler.postgresql.cnpg.io "$_M27_POOLER" --type merge \
      -p "$(jq -nc --argjson p "$_E19_PARAMS" '{spec: {pgbouncer: {parameters: $p}}}')" >/dev/null || return 1
    m27_ecrire E19 v2-lieu direct
  fi
  m27_journal E19 "pooler resserré ($(m27_lire E19 v2-lieu))"
}
_e19_v2_constat() {
  wb_kubectl -n "$_M27_NS_AGENDA" get pooler.postgresql.cnpg.io "$_M27_POOLER" -o json 2>/dev/null |
    jq -e '.spec.pgbouncer.parameters.default_pool_size == "1" and .spec.pgbouncer.parameters.max_client_conn == "8"' >/dev/null 2>&1
}
_e19_v2_defaire() {
  local d f cur
  if m27_commit_actif E19 v2; then
    m27_retablir E19 v2 || true
    m27_argo_rafraichir "$_M27_APP_AGENDA"
  else
    m27_oublier E19 git-v2
  fi
  if [[ "$(m27_lire E19 v2-lieu)" == direct ]]; then
    d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/M27-E19"
    f="$d/${_M27_NS_AGENDA}_pooler.postgresql.cnpg.io_${_M27_POOLER}.yaml"
    cur="$(wb_kubectl -n "$_M27_NS_AGENDA" get pooler.postgresql.cnpg.io "$_M27_POOLER" -o json 2>/dev/null | jq -c '.spec.pgbouncer.parameters // {}')" || cur=""
    [[ -n "$cur" ]] || cur='{}'
    if [[ -f "$f" ]] && jq -e --argjson p "$_E19_PARAMS" '. as $c | $p | to_entries | all(.value == $c[.key])' <<<"$cur" >/dev/null 2>&1; then
      # Paramètres d'origine remis (seulement ceux que la panne a changés).
      wb_kubectl -n "$_M27_NS_AGENDA" patch pooler.postgresql.cnpg.io "$_M27_POOLER" --type merge -p "$(
        yq -o=json '.spec.pgbouncer.parameters // {}' "$f" | jq -c --argjson p "$_E19_PARAMS" \
          '. as $o | {spec: {pgbouncer: {parameters: ($p | with_entries(.value = ($o[.key] // null)))}}}')" >/dev/null 2>&1 || true
    fi
    rm -rf "$d"
  fi
  m27_oublier E19 v2-lieu
}

# --- Variante 3 : droits d'écriture retirés -----------------------------------------------------------

# _e19_v3_tables PRIVILÈGE — tables de public (hors historique Flyway) où mediagenda_api a PRIVILÈGE.
_e19_v3_tables() {
  m27_psql "SELECT coalesce(string_agg(format('%I.%I', schemaname, tablename), ','), '') FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> 'flyway_schema_history'
      AND has_table_privilege('mediagenda_api', format('%I.%I', schemaname, tablename), '$1');"
}

_e19_v3_poser() {
  local tmp p t etat=""
  [[ "$(m27_psql "SELECT count(*) FROM pg_roles WHERE rolname = 'mediagenda_api';")" == 1 ]] || return 10
  # État d'origine noté PRIVILÈGE PAR PRIVILÈGE (« INSERT=t1,t2;UPDATE=…;DELETE=… ») : l'annulation rend
  # exactement ce qui existait, rien de plus.
  for p in INSERT UPDATE DELETE; do
    t="$(_e19_v3_tables "$p")" || return 1
    etat+="$p=$t;"
  done
  [[ "$etat" != "INSERT=;"* ]] || return 10   # aucune table où l'API écrit : variante sans objet
  m27_ecrire E19 v3-droits "$etat"
  tmp="$(m27_etat E19)/tmp"
  mkdir -p "$tmp"
  cat >"$tmp/moindre-privilege.sql" <<SQL
-- Moindre privilège pour l'API de MédiAgenda (recette) — Lucas
-- L'API lit beaucoup et écrit peu : on retire l'écriture du rôle de groupe, on verra si quelque chose casse.
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM mediagenda_api;
SQL
  m27_commit E19 v3 "$_M27_DEPOT_K8S" "recette : moindre privilège pour mediagenda_api" \
    "$_E19_SQL_CHEMIN" "$tmp/moindre-privilege.sql" || return 1
  for p in INSERT UPDATE DELETE; do
    t="${etat#*"$p="}"; t="${t%%;*}"
    [[ -z "$t" ]] || m27_psql "REVOKE $p ON $t FROM mediagenda_api;" >/dev/null || return 1
  done
  m27_journal E19 "INSERT, UPDATE, DELETE retirés à mediagenda_api ($etat)"
}
_e19_v3_constat() {
  [[ "$(m27_psql "SELECT has_table_privilege('mediagenda_api', 'public.rendez_vous', 'INSERT');")" == f ]]
}
_e19_v3_defaire() {
  local etat p t
  etat="$(m27_lire E19 v3-droits)"
  if [[ -n "$etat" ]]; then
    for p in INSERT UPDATE DELETE; do
      t="${etat#*"$p="}"; t="${t%%;*}"
      [[ -n "$t" ]] || continue
      m27_psql "GRANT $p ON $t TO mediagenda_api;" >/dev/null ||
        wb_avert "droits non rendus : GRANT $p ON $t TO mediagenda_api; (à jouer sur le primaire de recette)"
    done
    m27_journal E19 "droits d'origine rendus ($etat)"
  fi
  if m27_commit_actif E19 v3; then m27_retablir E19 v3 || true; else m27_oublier E19 git-v3; fi
  m27_oublier E19 v3-droits
}

# --- Mécanique commune --------------------------------------------------------------------------------

_m27E19_une() {
  local n="$1" rc=0
  "_e19_v${n}_poser" || rc=$?
  if ((rc != 0)); then
    "_e19_v${n}_defaire" || true
    return "$rc"
  fi
  m27_debut E19
  if ! m27_attendre 420 "_e19_v${n}_constat"; then
    "_e19_v${n}_defaire" || true
    return 10
  fi
}

panne_E19_v1() { m27_preparer base && m27_essayer E19 3 1; }
panne_E19_v2() { m27_preparer base && m27_essayer E19 3 2; }
panne_E19_v3() { m27_preparer base && m27_essayer E19 3 3; }

verifier_E19() {
  case "$WB_VAR" in
    [1-3]) "_e19_v${WB_VAR}_constat" ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  case "${WB_VAR:-}" in
    [1-3]) "_e19_v${WB_VAR}_defaire" ;;
    *) local v; for v in 1 2 3; do "_e19_v${v}_defaire" || true; done ;;
  esac
  m27_oublier E19 debut
  m27_oublier E19 tmp
  m27_journal E19 "annulation"
}

resume_E19() {
  echo "En recette, les créations de rendez-vous échouent ou attendent ; les lectures passent."
}

symptome_E19() {
  wb_symptome "Ticket INC-5419 — De : Julien Petit" \
    "En recette, depuis tout à l'heure, on ne peut plus créer de rendez-vous : la requête tourne de longues" \
    "secondes puis échoue (500 ou délai dépassé). La liste des rendez-vous et les créneaux s'affichent, parfois" \
    "lentement. On n'a rien livré dans l'API. Lucas dit avoir « fait un peu d'optimisation » côté base." \
    "Trouve ce qui bloque les écritures, corrige à la racine et dis-moi quelle alerte aurait dû sonner." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 27 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 27 E19 3 "$@"; }
fi
