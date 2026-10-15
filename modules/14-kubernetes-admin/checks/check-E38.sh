# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M14-E38 « Panne : CrashLoopBackOff » : agenda déployé et stable, configuration
# conforme au contrat de l'application (variables, sonde de vivacité sur /sante:8000, mémoire,
# commande de l'image), plus aucun conteneur en boucle, RB-145 (section CrashLoopBackOff), panne close.
# Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E38 — Plus aucun pod en CrashLoopBackOff"
require_cmd jq kubectl

if ! _m14x_api_repond; then
  skip "pods" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
else
  # shellcheck disable=SC2046
  check_cmd "aucun conteneur en CrashLoopBackOff ni en erreur de démarrage (wb-*, mediagenda-*)" \
    _m14x_pods_sans '(.state.waiting.reason // "") | test("CrashLoopBackOff|RunContainerError|CreateContainerError")' \
    $(_m14x_espaces_workbook)
  if _m14x_temoins; then
    _m14_e38_c='.spec.template.spec.containers[] | select(.name == "agenda")'
    check_cmd "déploiement agenda (wb-pannes) entièrement à jour et disponible" _m14x_deploy_pret "$_m14x_ns" agenda
    check_cmd "agenda : MEDIAGENDA_DB_URL et MEDIAGENDA_VALKEY_URL fournies" \
      _m14x_kq "$_m14_e38_c | [.env[]?.name] | (index(\"MEDIAGENDA_DB_URL\") != null) and (index(\"MEDIAGENDA_VALKEY_URL\") != null)" \
      -n "$_m14x_ns" deploy agenda
    check_cmd "agenda : sonde de vivacité sur /sante, port de l'application (8000)" \
      _m14x_kq "$_m14_e38_c | .livenessProbe.httpGet | .path == \"/sante\" and (.port == 8000 or .port == \"http\")" \
      -n "$_m14x_ns" deploy agenda
    _m14_e38_memoire() {
      local q
      q="$(kube -n "$_m14x_ns" get deploy agenda -o json 2>/dev/null | jq -r "$_m14_e38_c | .resources.limits.memory // \"0\"")"
      (($(_m14x_memoire_mio "$q") >= 128))
    }
    check_cmd "agenda : limite de mémoire d'au moins 128 Mi" _m14_e38_memoire
    check_cmd "agenda : commande de l'image conservée (pas de « mediagenda-api »)" \
      _m14x_kq "$_m14_e38_c | (.command // []) | index(\"mediagenda-api\") | not" -n "$_m14x_ns" deploy agenda
    check_cmd "agenda : aucun pod n'a redémarré plus de 2 fois" \
      _m14x_kq '[.items[].status.containerStatuses[]? | select(.restartCount > 2)] | length == 0' \
      -n "$_m14x_ns" pods -l app.kubernetes.io/name=agenda
  else
    skip "témoins de wb-pannes" "absents : ils sont créés à la première injection (lab/bin/break 14 38)"
  fi
fi
check_cmd "RB-145 : section sur CrashLoopBackOff" \
  _m14x_doc_contient 'docs/kubernetes/runbooks/RB-145-*.md' '^#+ .*CrashLoop'
check_cmd "RB-145 commité dans le dépôt de documentation" _m14x_doc_commite 'docs/kubernetes/runbooks/RB-145-*.md'
check_cmd "panne M14-E38 close (lab/bin/break 14 38 --annuler après réparation)" _m14x_aucune_panne_active E38
