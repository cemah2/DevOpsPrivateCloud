# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S12.sh — F1-S12 « Panne : la reconstruction coince ».
# Vérifie l'état sain quelle que soit la variante tirée (sans la nommer), la clôture de la panne et la
# documentation. Lecture seule : OpenBao (auth/k8s-par1/config par l'AppRole wb-checks), DNS faisant
# autorité (dig sans récursion), HTTPRoutes, configurations de webhooks et Services (si le compte des
# checks les lit), statuts des ExternalSecrets et des pods, documents sur main.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S12 — Panne : la reconstruction coince"
require_cmd kubectl jq curl dig openssl

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi

# --- Confiance du coffre --------------------------------------------------------------------------
check_cmd "OpenBao (auth/k8s-par1/config) fait confiance à l'autorité du cluster actuel" _f1c_ca_coherente
_f1_s12_ko="$(_f1c_es_non_prets | head -n 5 | paste -sd ' ' -)"
_f1_s12_nb_es="$(_f1c_nb externalsecrets.external-secrets.io -A)"
check_cmd "tous les ExternalSecrets prêts ($_f1_s12_nb_es)${_f1_s12_ko:+ — en erreur : $_f1_s12_ko}" \
  test -z "$_f1_s12_ko" -a "$_f1_s12_nb_es" -gt 0

# --- Noms publiés ----------------------------------------------------------------------------------
_f1_s12_noms="$(_f1c_noms_publies | wc -l)"
check_cmd "noms *.apps publiés par les HTTPRoutes de gw-par1 lus ($_f1_s12_noms)" test "$_f1_s12_noms" -gt 0
_f1_s12_mal="$(_f1c_noms_mal_publies | head -n 5 | paste -sd ';' -)"
check_cmd "chaque nom publié vise $_f1c_gw_ip et appartient à k8s-par1${_f1_s12_mal:+ — écarts : $_f1_s12_mal}" \
  test -z "$_f1_s12_mal" -a "$_f1_s12_noms" -gt 0
check_cmd "portail.$_f1c_zone_apps répond (via le DNS du lab)" \
  bash -c 'c="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://portail.$1/")"; [[ "$c" =~ ^(200|30[0-9]|401)$ ]]' _ "$_f1c_zone_apps"

# --- Admission ---------------------------------------------------------------------------------------
# _f1_s12_webhooks_orphelins — webhooks (validation et mutation) dont le Service visé n'existe pas.
_f1_s12_webhooks_orphelins() {
  local svc vw mw
  svc="$(_f1c_kj services -A | jq -c '[.items[]? | "\(.metadata.namespace)/\(.metadata.name)"]' 2>/dev/null || echo '[]')"
  vw="$(_f1c_kj validatingwebhookconfigurations)"
  mw="$(_f1c_kj mutatingwebhookconfigurations)"
  [[ -n "$vw" ]] || vw='{"items":[]}'
  [[ -n "$mw" ]] || mw='{"items":[]}'
  jq -rn --argjson s "${svc:-[]}" --argjson v "$vw" --argjson m "$mw" '
    [($v.items[]?, $m.items[]?) | .metadata.name as $c | .webhooks[]? | select(.clientConfig.service != null)
     | select(("\(.clientConfig.service.namespace)/\(.clientConfig.service.name)") as $k | $s | index($k) | not)
     | "\($c) → \(.clientConfig.service.namespace)/\(.clientConfig.service.name)"] | unique | .[]' 2>/dev/null || true
}
if _f1c_peut list validatingwebhookconfigurations.admissionregistration.k8s.io && _f1c_peut list services --all-namespaces; then
  _f1_s12_wh="$(_f1_s12_webhooks_orphelins | head -n 3 | paste -sd ';' -)"
  check_cmd "aucun webhook d'admission ne vise un Service inexistant${_f1_s12_wh:+ — $_f1_s12_wh}" test -z "$_f1_s12_wh"
else
  skip "webhooks d'admission" "le compte des checks ne lit pas les configurations de webhooks"
fi
check_cmd "mediagenda-recette : tous les pods de l'API voulus sont prêts (Rollout)" _f1c_kq \
  '(.status.replicas // 0) >= 1 and (.status.availableReplicas // 0) >= (.spec.replicas // 1)' \
  -n mediagenda-recette rollouts.argoproj.io mediagenda

# --- Clôture et documentation ----------------------------------------------------------------------------
check_cmd "panne F1-S12 close (lab/bin/break F1 12 --annuler après réparation)" _f1c_panne_close F1-S12
check_cmd "journal de diagnostic docs/day0/journal/*INC-5712* (hypothèses, commandes, conclusion)" \
  _f1c_doc 'INC-5712' 'hypoth' 'conclu'
_f1_s12_pm() {
  local f
  f="$(_f1c_doc_chemin 'INC-5712' "$_f1c_doc/post-mortems")" || return 1
  _f1c_contient "$(_f1c_fichier "$_f1c_projet_doc" "$f")" 'chronolog' 'impact' 'cause' 'd[ée]tect' '[0-9]{4}-[0-9]{2}-[0-9]{2}'
}
check_cmd "post-mortem docs/day0/post-mortems/INC-5712*.md : chronologie, impact, cause, détection, actions datées" _f1_s12_pm
