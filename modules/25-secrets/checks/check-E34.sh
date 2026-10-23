# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, PromQL et LogQL entre apostrophes
#
# check-E34.sh — M25-E34 « Rotation d'urgence en temps limité » (CHRONO), à lancer à la fin.
# Compare l'état final à l'état de départ relevé par « lab/bin/break 25 34 »
# (~/.local/state/workbook/M25-E34/etat.json, gardé après l'annulation) :
#   - nouvelle version de kv/plateforme/grafana/oidc et de kv/mediagenda/recette/harbor-pull, écrite après T0 ;
#   - secret du client grafana régénéré dans Keycloak après T0 ;
#   - les ExternalSecret qui lisent ces deux chemins se sont rafraîchis après la nouvelle version ;
#   - pas plus d'une minute d'indisponibilité de Grafana (sonde du témoin) ni de la recette (5xx) ;
#   - journal INC-5234 sur main.
# Ce qui n'est PAS vérifiable par un check en lecture seule (et l'est par le corrigé) : que les ANCIENS
# secrets soient refusés (il faudrait les connaître).
# Lecture seule : AppRole wb-checks (métadonnées), Keycloak (view-clients), « kube » (objets d'ESO,
# jamais les Secrets), témoin de mon01, Prometheus du cluster, GitLab.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E34 — Rotation d'urgence en temps limité"
require_cmd jq curl kubectl
_m25p_connexion

_m25_e34_etat="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M25-E34/etat.json"
_m25_e34_t0="$(jq -r '.t0 // empty' "$_m25_e34_etat" 2>/dev/null || true)"
if [[ ! "$_m25_e34_t0" =~ ^[0-9]+$ ]]; then
  check_cmd "état de départ relevé (lance d'abord « lab/bin/break 25 34 » : c'est T0)" false
  # Script sourcé par lab/bin/check : « return » termine ce script, le bilan s'affiche quand même.
  return 0
fi
_m25_e34_fin="$(jq -r '.fin // empty' "$_m25_e34_etat" 2>/dev/null || true)"
_m25_e34_fin="${_m25_e34_fin:-$(date +%s)}"
_m25_e34_fenetre=$(( _m25_e34_fin - _m25_e34_t0 + 60 ))

# --- Coffre : nouvelles versions après T0 -------------------------------------------------------------------
for _m25_e34_c in grafana:plateforme/grafana/oidc harbor:mediagenda/recette/harbor-pull; do
  _m25_e34_cle="${_m25_e34_c%%:*}"; _m25_e34_kv="${_m25_e34_c#*:}"
  _m25_e34_avant="$(jq -r --arg k "$_m25_e34_cle" '.[$k].version' "$_m25_e34_etat" 2>/dev/null || echo 0)"
  check_cmd "kv/$_m25_e34_kv : nouvelle version écrite après T0 (version de départ : $_m25_e34_avant)" \
    _m25p_jq "$(_m25p_kv_meta "$_m25_e34_kv")" '.version > ($v | tonumber) and .cree >= ($t | tonumber)' \
    --arg v "$_m25_e34_avant" --arg t "$_m25_e34_t0"
done

# --- Keycloak : secret régénéré (attribut client.secret.creation.time, en s ou en ms) ----------------------------
_m25_e34_kc="$(keycloak_api "clients?clientId=grafana" 2>/dev/null | jq -r '.[0].attributes["client.secret.creation.time"] // empty' 2>/dev/null || true)"
if [[ -z "$(jq -r '.keycloak_secret_cree // empty' "$_m25_e34_etat" 2>/dev/null)" ]]; then
  skip "secret du client grafana régénéré dans Keycloak" "date du secret illisible au départ (attribut absent ou droits)"
else
  check_cmd "client grafana : secret régénéré dans Keycloak après T0" \
    bash -c '[[ "$1" =~ ^[0-9]+$ ]] && { s=$1; ((s > 100000000000)) && s=$((s / 1000)); ((s >= $2)); }' _ "$_m25_e34_kc" "$_m25_e34_t0"
fi

# --- ESO : les ExternalSecret qui lisent ces chemins se sont rafraîchis après T0 -------------------------------
_m25_e34_es="$(kube get externalsecrets.external-secrets.io -A -o json 2>/dev/null || echo null)"
for _m25_e34_kv in plateforme/grafana/oidc mediagenda/recette/harbor-pull; do
  check_cmd "ExternalSecret lisant $_m25_e34_kv : rafraîchi après T0 et prêt" _m25p_jq "$_m25_e34_es" '
    [.items[] | select([.spec.data[]?.remoteRef.key, .spec.dataFrom[]?.extract.key] | map(select(. != null)) | any(contains($k)))]
    | length > 0 and all(
        ((.status.refreshTime // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601) >= ($t | tonumber)
        and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
    --arg k "$_m25_e34_kv" --arg t "$_m25_e34_t0"
done

# --- Sans coupure -----------------------------------------------------------------------------------------------
_m25_e34_grafana="$(_m25p_temoin_valeur "(1 - avg_over_time(probe_success{instance=~\".*grafana\\\\.apps.*\"}[${_m25_e34_fenetre}s])) * $_m25_e34_fenetre")"
if [[ -z "$_m25_e34_grafana" ]]; then
  check_cmd "sonde de Grafana sur le témoin de mon01 (aucune donnée sur la fenêtre)" false
else
  check_cmd "Grafana : moins d'une minute d'indisponibilité pendant l'exercice (≈ ${_m25_e34_grafana%.*} s)" \
    _m25p_compare "$_m25_e34_grafana" '<=' 60
fi
_m25_e34_recette="$(_m25p_valeur "count_over_time(((sum(rate(mediagenda_http_requests_total{namespace=\"mediagenda-recette\", code=~\"5..\"}[1m])) / sum(rate(mediagenda_http_requests_total{namespace=\"mediagenda-recette\"}[1m]))) > 0.5)[${_m25_e34_fenetre}s:30s]) * 30 or vector(0)")"
check_cmd "MédiAgenda recette : pas plus d'une minute à plus de 50 % d'erreurs 5xx (≈ ${_m25_e34_recette:-?} s)" \
  _m25p_compare "${_m25_e34_recette:-}" '<=' 60

# --- Journal ------------------------------------------------------------------------------------------------------
_m25_e34_j="$(_m25p_doc_chemin "$_M25P_DOC" docs/socle/journal 'INC-5234[^/]*\.md$')"
if [[ -z "$_m25_e34_j" ]]; then
  check_cmd "journal docs/socle/journal/*INC-5234*.md sur main de $_M25P_DOC" false
else
  _m25_e34_txt="$(_m25p_fichier "$_M25P_DOC" "$_m25_e34_j" || true)"
  check_output "journal : au moins cinq étapes horodatées" '^([5-9]|[1-9][0-9]+)$' \
    bash -c 'grep -Eo "\b([01]?[0-9]|2[0-3])[:h][0-5][0-9]\b" <<<"$1" | sort -u | grep -c .' _ "$_m25_e34_txt"
  check_cmd "journal : preuves citées (audit, versions du coffre, ExternalSecret ou Keycloak)" \
    bash -c 'grep -Eqi "audit|loki" <<<"$1" && grep -Eqi "version|metadata|m[ée]tadonn" <<<"$1" && grep -Eqi "externalsecret|keycloak" <<<"$1"' _ "$_m25_e34_txt"
fi
check_cmd "exercice clos (lab/bin/break 25 34 --annuler)" _m25p_marqueur_absent E34
