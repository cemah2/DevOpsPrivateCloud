# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E12.sh — M16-E12 : Classes de stockage : défaut, topologie, liaison différée
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), API GitLab en GET.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E12 — Classes de stockage : défaut, topologie, liaison différée"
require_cmd jq kubectl curl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "ceph-rbd est la SEULE classe par défaut" _m16o_defaut_unique
check_cmd "aucune classe d'essai wb-essai-* ne reste" _m16o_json "$(_m16o_kj get storageclass)" \
  '[.items[] | select(.metadata.name | startswith("wb-essai-"))] | length == 0'
check_cmd "aucun PVC d'essai de l'exercice ne reste dans wb-essais (sans-classe, classe-vide, differee, baie-a)" \
  _m16o_json "$(_m16o_kj get pvc -n wb-essais)" \
  '[.items[] | select(.metadata.name | IN("sans-classe", "classe-vide", "differee", "baie-a"))] | length == 0'
_m16o_cat="$(_m16o_contenu_main "$_M16O_PROJET_DOC" docs/kubernetes/stockage/classes.md)"
check_cmd "docs/kubernetes/stockage/classes.md sur main de plateforme/medisphere" test -n "$_m16o_cat"
check_cmd "le catalogue décrit ceph-rbd, ceph-rbd-retain et cephfs, et la position sur WaitForFirstConsumer" \
  bash -c 'grep -q "ceph-rbd-retain" <<<"$1" && grep -q "cephfs" <<<"$1" && grep -qi "WaitForFirstConsumer" <<<"$1"' _ "$_m16o_cat"
check_cmd "journal ~/m16/e12/journal.md rédigé" _m16o_journal E12 10
