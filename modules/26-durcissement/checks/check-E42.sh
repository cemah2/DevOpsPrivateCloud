# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et motifs bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M26-E42 « conteneur compromis » : témoin éradiqué, quarantaine en place, RB-262 rédigé,
# preuves consignées, panne close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E42 — Le conteneur compromis est éradiqué"
require_cmd jq kubectl git

_e42_pas_de_pod() { ! kube -n "$_m26x_ns_pannes" get pods -l medisphere.internal/panne=M26-E42 -o name 2>/dev/null | grep -q .; }
_e42_incident_commite() { (cd "$_m26x_depot" 2>/dev/null && git ls-files | grep -Eq '(post-mortems|journal)/.*INC-5342.*\.md$'); }

check_cmd "le Deployment compromis (wb-mineur) est supprimé de wb-pannes" _m26x_absent deployment wb-mineur "$_m26x_ns_pannes"
check_cmd "le CronJob de persistance (wb-persistance) est supprimé" _m26x_absent cronjob wb-persistance "$_m26x_ns_pannes"
check_cmd "aucun pod de la panne M26-E42 ne subsiste dans wb-pannes" _e42_pas_de_pod
check_cmd "la politique de quarantaine (CiliumClusterwideNetworkPolicy « quarantaine ») est posée (E33)" \
  _m26x_existe ciliumclusterwidenetworkpolicies quarantaine
check_cmd "RB-262 (réponse à incident conteneur) rédigé et commité" \
  _m26x_doc_commite "docs/securite/durcissement/runbooks/RB-262-*.md"
check_cmd "RB-262 : détection → isolement → collecte → éradication → rétablissement" \
  _m26x_doc_contient "docs/securite/durcissement/runbooks/RB-262-*.md" '(isolement|quarantaine).*(collecte|preuve)|d[ée]tection.*[ée]radication'
check_cmd "un post-mortem ou journal d'incident INC-5342 est commité" _e42_incident_commite
check_cmd "panne M26-E42 close (témoin retiré)" _m26x_aucune_panne_active E42
