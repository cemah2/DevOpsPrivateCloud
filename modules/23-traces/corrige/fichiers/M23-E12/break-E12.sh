# shellcheck shell=bash
# shellcheck disable=SC2016  # SQL et boucle distante entre apostrophes : évalués ailleurs (psql, bash fils)
# break-E12.sh — M23-E12 « Trouver où passe le temps » : LENTEUR injectée dans mediagenda-recette.
# ⚠️ Ne lis pas ce fichier avant d'avoir résolu : il révèle la cause.
#
# Format des scripts de panne (lab/lib/pannes-lib.sh) : à placer dans corrige/pannes/ sous le nom
# break-E12.sh pour « lab/bin/break 23 12 » ; M23-E23 (astreinte) enchaîne ses fonctions (resume_E12…).
#
# Deux variantes, réversibles, SANS suppression de données :
#   1. PostgreSQL : un déclencheur « BEFORE INSERT OR DELETE » sur rendez_vous qui attend 400 ms
#      (fonction journal_modifications(), commentée « wb:M23-E12 ») dans la base de recette (CNPG
#      mediagenda-db, instance primaire) ;
#   2. Valkey : une boucle lancée depuis adm01 suspend Valkey de recette (CLIENT PAUSE 300 ms, toutes
#      les commandes) environ deux fois par seconde.
# Effets attendus : variante 1, prise et annulation de rendez-vous ≥ 400 ms (span INSERT/DELETE) ;
# variante 2, créneaux et créations ralentis par à-coups (spans GET/SET/DEL de Valkey).

# Emplacement final : corrige/pannes/ (chemin relatif de la directive ci-dessous).
# shellcheck source=/dev/null
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_M23E12_NS=mediagenda-recette
_M23E12_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook"
_M23E12_PID="$_M23E12_ETAT/M23-E12.boucle.pid"

# _m23e12_primaire — nom du pod primaire PostgreSQL de recette (vide si introuvable).
_m23e12_primaire() {
  local p
  p="$(wb_kubectl -n "$_M23E12_NS" get pods -l cnpg.io/cluster=mediagenda-db,cnpg.io/instanceRole=primary \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || p=""
  if [[ -z "$p" ]]; then
    p="$(wb_kubectl -n "$_M23E12_NS" get pods -l cnpg.io/cluster=mediagenda-db,role=primary \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || p=""
  fi
  printf '%s\n' "$p"
}

# _m23e12_psql 'SQL' — exécute du SQL dans la base mediagenda (superutilisateur local du conteneur).
_m23e12_psql() {
  local p
  p="$(_m23e12_primaire)"
  [[ -n "$p" ]] || return 1
  wb_kubectl -n "$_M23E12_NS" exec "$p" -c postgres -- \
    psql -X -q -t -A -v ON_ERROR_STOP=1 -d mediagenda -c "$1"
}

panne_E12_v1() {
  _m23e12_psql "
CREATE OR REPLACE FUNCTION journal_modifications() RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  PERFORM pg_sleep(0.4);
  RETURN COALESCE(NEW, OLD);
END \$\$;
COMMENT ON FUNCTION journal_modifications() IS 'wb:M23-E12';
DROP TRIGGER IF EXISTS rendez_vous_journal ON rendez_vous;
CREATE TRIGGER rendez_vous_journal BEFORE INSERT OR DELETE ON rendez_vous
  FOR EACH ROW EXECUTE FUNCTION journal_modifications();" >/dev/null
}

panne_E12_v2() {
  local kcfg="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
  mkdir -p "$_M23E12_ETAT"
  # Valkey joignable et sans mot de passe exigé (sinon la variante ne peut rien injecter).
  wb_kubectl -n "$_M23E12_NS" exec sts/valkey -- valkey-cli PING 2>/dev/null | grep -qx PONG || return 1
  KCFG="$kcfg" NS="$_M23E12_NS" nohup setsid bash -c '
    # wb:M23-E12 — boucle de suspension de Valkey (arrêtée par « lab/bin/break 23 12 --annuler »).
    while :; do
      kubectl --kubeconfig "$KCFG" -n "$NS" exec sts/valkey -- valkey-cli CLIENT PAUSE 300 ALL >/dev/null 2>&1
      sleep 0.5
    done' >/dev/null 2>&1 </dev/null &
  echo $! >"$_M23E12_PID"
}

verifier_E12() {
  case "${WB_VAR:-0}" in
    1) [[ "$(_m23e12_psql "SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
          WHERE t.tgname = 'rendez_vous_journal' AND obj_description(p.oid, 'pg_proc') = 'wb:M23-E12';" 2>/dev/null)" == 1 ]] ;;
    2) [[ -s "$_M23E12_PID" ]] && kill -0 "$(cat "$_M23E12_PID")" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E12() {
  # Variante 2 : arrêt de la boucle (seulement la nôtre : PID enregistré), puis levée de la pause.
  if [[ -s "$_M23E12_PID" ]]; then
    kill -- "-$(cat "$_M23E12_PID")" 2>/dev/null || kill "$(cat "$_M23E12_PID")" 2>/dev/null || true
    rm -f "$_M23E12_PID"
    wb_kubectl -n "$_M23E12_NS" exec sts/valkey -- valkey-cli CLIENT UNPAUSE >/dev/null 2>&1 || true
  fi
  # Variante 1 : on ne retire le déclencheur QUE s'il porte encore notre marque (une réparation de
  # l'apprenant, ou un déclencheur légitime du même nom, n'est jamais écrasée).
  _m23e12_psql "
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'journal_modifications'
             AND obj_description(oid, 'pg_proc') = 'wb:M23-E12') THEN
    DROP TRIGGER IF EXISTS rendez_vous_journal ON rendez_vous;
    DROP FUNCTION journal_modifications();
  END IF;
END \$\$;" >/dev/null 2>&1 || true
}

symptome_E12() {
  wb_symptome "INC-5012 — MédiAgenda de recette lente" \
    "De : Nadia Roussel — Support" \
    "Julien signale que l'API de RECETTE est lente depuis ce matin : certaines opérations prennent" \
    "près d'une demi-seconde, voire plus, au lieu de quelques millisecondes. Aucune erreur, /pret" \
    "répond, les pods ne redémarrent pas. Les testeurs de recette attendent." \
    "Trouve OÙ passe le temps, corrige, et consigne ta démarche (journal de diagnostic)."
}

resume_E12() {
  echo "l'API MédiAgenda de recette est lente sur une partie des opérations, sans erreur"
}

main() { wb_main 23 E12 2 "$@"; }
