# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S04.sh — F6-S04 « Panne : les écarts cachés de l'audit à blanc » (BF) : état sain sur TOUS les
# points où un écart a pu être injecté (quel que soit le lot tiré), et un écart formalisé par écart
# injecté (ECA-3611 et suivants). Les contrôles sont génériques : ils ne nomment pas les écarts.
# Lecture seule ; lit (sans le modifier) le nombre d'écarts injectés dans l'état local de l'injection.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S04 — Panne : les écarts cachés de l'audit à blanc"
require_cmd curl jq

_f6_s04_lot="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F6-S04/lot" 2>/dev/null || true)"
_f6_s04_n="$(wc -w <<<"$_f6_s04_lot")"
((_f6_s04_n > 0)) || _f6_s04_n=4

# --- Comptes ----------------------------------------------------------------------------------------
_f6_s04_externes_inactifs() {
  local u e
  for u in $_f6c_externes; do
    e="$(gitlab_api "users?username=$(_f6c_enc "$u")" 2>/dev/null | jq -r '.[0].state // "absent"')" || return 1
    [[ "$e" != active ]] || return 1
  done
}
check_cmd "GitLab : aucun compte de prestataire parti n'est actif" _f6_s04_externes_inactifs

# --- Bordure ----------------------------------------------------------------------------------------
for _f6_s04_gw in $_f6c_passerelles; do
  _f6_s04_rc=0
  _f6c_bordure_conforme "$_f6_s04_gw" || _f6_s04_rc=$?
  if ((_f6_s04_rc == 2)); then
    skip "bordure $_f6_s04_gw" "lecture impossible (SSH admin et sudo -n nft list)"
  else
    check_cmd "bordure $_f6_s04_gw : toutes les règles actives sont décrites dans la configuration persistée" test "$_f6_s04_rc" -eq 0
  fi
done

if ! _f6c_api_repond; then
  skip "contrôles Kubernetes" "l'API ne répond pas au compte des checks"
else
  # --- Dérogations ----------------------------------------------------------------------------------
  check_cmd "Kyverno : chaque dérogation a une échéance et figure au registre" _f6c_kq \
    '[.items[] | select((.spec.expiresAt // "") == "" or ((.metadata.labels // {})["medisphere.internal/registre-exceptions"] != "oui"))] | length == 0' \
    -n kyverno-exceptions policyexceptions.policies.kyverno.io
  # --- Données des espaces applicatifs --------------------------------------------------------------
  check_cmd "aucune ConfigMap d'un espace applicatif ne contient de mot de passe ou de jeton en clair" _f6c_kq \
    '[.items[] | select(.metadata.namespace | test("^(mediagenda|medidoc|medinotif|legacy|medivisio|data)-"))
      | (.data // {}) | to_entries[]
      | select((.key | test("(?i)(password|passwd|mot_de_passe|secret|token|api_?key)$")) and ((.value // "") | length) > 0)] | length == 0' \
    configmaps -A
  # --- Sauvegardes -----------------------------------------------------------------------------------
  check_cmd "Velero : aucune planification suspendue" _f6c_kq '[.items[] | select(.spec.paused == true)] | length == 0' \
    -n velero schedules.velero.io
  # --- Droits ----------------------------------------------------------------------------------------
  check_cmd "RBAC : aucun compte de service d'un espace applicatif ou d'essai n'est cluster-admin" _f6c_kq \
    '[.items[] | select(.roleRef.name == "cluster-admin") | .subjects[]?
      | select(.kind == "ServiceAccount" and (.namespace | test("^(mediagenda|medidoc|medinotif|legacy|medivisio|data|wb)-")))] | length == 0' \
    clusterrolebindings
fi

# --- Supervision -------------------------------------------------------------------------------------
_f6_s04_silences() {
  local s
  s="$(am_api silences 2>/dev/null)" || return 2
  jq -e '[.[] | select(.status.state == "active")
      | select(any(.matchers[]; .name == "alertname" and (.value | test("Falco|Audit")))
               or (((.endsAt | sub("\\.[0-9]+"; "") | fromdateiso8601) - (.startsAt | sub("\\.[0-9]+"; "") | fromdateiso8601)) > 7 * 86400))]
    | length == 0' <<<"$s" >/dev/null 2>&1
}
_f6_s04_rc=0
_f6_s04_silences || _f6_s04_rc=$?
if ((_f6_s04_rc == 2)); then
  skip "Alertmanager" "API injoignable"
else
  check_cmd "Alertmanager : aucun silence actif sur les alertes de sécurité, aucun silence de plus de 7 jours" test "$_f6_s04_rc" -eq 0
fi

# --- Formalisation ----------------------------------------------------------------------------------
_f6_s04_ecarts() {
  local f n=0
  while IFS= read -r f; do
    [[ "${f##*/}" =~ ^ECA-36(1[1-9]|[2-9][0-9])([-_.].*)?\.md$ ]] || continue
    _f6c_contient "$(_f6c_fichier "$_f6c_doc_projet" "$f" 2>/dev/null || true)" \
      'cause|origine' 'correct|rem(é|e)di' 'pr(é|e)vention|emp(ê|e)ch|action corrective' '(5|6|7|8)\.[0-9]+' || continue
    n=$((n + 1))
  done < <(_f6c_arbre "$_f6c_doc_projet" "$_f6c_doc_dir/ecarts")
  ((n >= _f6_s04_n))
}
check_cmd "écarts ECA-3611 et suivants : au moins $_f6_s04_n formalisés (cause, mesure ISO, correction, prévention)" _f6_s04_ecarts
