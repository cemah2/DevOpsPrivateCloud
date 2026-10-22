# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E28.sh — M26-E28 « Audit Kubernetes revisité : politique, détection, rétention »
# À lancer depuis adm01. Lecture seule : politique d'audit des trois nœuds de contrôle (SSH, sudo -n
# cat/sha256sum), règles du ruler de Loki (locataire audit), événements d'audit des 7 derniers jours
# (Loki), liaison de test absente (compte wb-checks), documentation sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E28 — Audit Kubernetes revisité : politique, détection, rétention"
require_cmd jq curl ssh yq

title "Politique d'audit des nœuds de contrôle"
_m26_e28_empreintes=""
for _m26_e28_n in "${_M26P_CP[@]}"; do
  _m26_e28_empreintes+="$(remote "$_m26_e28_n" 'sudo -n sha256sum /etc/kubernetes/audit/politique.yaml' 2>/dev/null | awk '{print $1}' || true)"$'\n'
done
check_output "la politique est identique sur les trois nœuds de contrôle (une seule empreinte)" '^1$' \
  bash -c 'grep -E "^[0-9a-f]{64}$" <<<"$1" | sort -u | grep -c . || true' _ "$_m26_e28_empreintes"
check_output "les trois empreintes ont été lues" '^3$' \
  bash -c 'grep -cE "^[0-9a-f]{64}$" <<<"$1" || true' _ "$_m26_e28_empreintes"
_m26_e28_pol="$(remote "${_M26P_CP[0]}" 'sudo -n cat /etc/kubernetes/audit/politique.yaml' 2>/dev/null || true)"
# yq (mikefarah, installé sur adm01 au M14) ne sert qu'à convertir en JSON ; les filtres sont en jq.
_m26_e28_json="$(yq -o=json '.' <<<"$_m26_e28_pol" 2>/dev/null || echo null)"
[[ -n "$_m26_e28_pol" ]] || _m26_e28_json=null
_m26_e28_yq() { _m26p_jq "$_m26_e28_json" "$1"; }
check_cmd "une règle Request couvre les politiques de Kyverno (policies.kyverno.io)" _m26_e28_yq \
  '[.rules[] | select(.level == "Request") | .resources[]? | select(.group == "policies.kyverno.io")] | length > 0'
check_cmd "une règle Request couvre les politiques et TracingPolicy de cilium.io" _m26_e28_yq \
  '[.rules[] | select(.level == "Request") | .resources[]? | select(.group == "cilium.io")] | length > 0'
check_cmd "aucune règle Request/RequestResponse ne vise les Secrets" _m26_e28_yq \
  '[.rules[] | select(.level == "Request" or .level == "RequestResponse")
    | select((.resources == null and .nonResourceURLs == null)
             or any(.resources[]?; (.group // "") == "" and (.resources == null or (.resources | any(. == "secrets" or . == "*")))))]
   | length == 0'
check_cmd "les Secrets restent au niveau Metadata" _m26_e28_yq \
  '[.rules[] | select(.level == "Metadata") | .resources[]? | select((.group // "") == "" and ((.resources // []) | any(. == "secrets")))] | length > 0'

title "Détections (ruler de Loki, locataire audit)"
_m26_e28_regles="$(_m26p_regles_loki audit)"
for _m26_e28_a in AuditExecProduction AuditLectureSecretParPersonne AuditLiaisonRoleCluster AuditBrisDeGlace; do
  check_output "règle $_m26_e28_a chargée" "alert: *$_m26_e28_a\$" echo "$_m26_e28_regles"
done

title "Essais (événements des 7 derniers jours)"
check_cmd "un exec en production par une personne a été enregistré" _m26p_loki_trouve \
  '{job="kubernetes-audit"} |~ `"subresource":"(exec|attach)"` | object_ns=~"mediagenda-prod|medidoc-prod" | user=~"oidc:.*"' audit 168h
check_cmd "une lecture de Secret par une personne a été enregistrée" _m26p_loki_trouve \
  '{job="kubernetes-audit"} | resource="secrets" | verb=~"get|list" | user=~"oidc:.*"' audit 168h
check_cmd "la liaison de test wb-test-liaison a été créée (événement d'audit)" _m26p_loki_trouve \
  '{job="kubernetes-audit"} | resource="clusterrolebindings" | object_name="wb-test-liaison" | verb="create"' audit 168h
check_cmd "le bris de glace (kubernetes-admin) a été utilisé pendant l'essai" _m26p_loki_trouve \
  '{job="kubernetes-audit"} |= `"username":"kubernetes-admin"`' audit 168h
check_cmd "la liaison de test wb-test-liaison n'existe plus" _m26p_absent clusterrolebinding wb-test-liaison

title "Documentation"
check_cmd "$_M26P_DOC : conformite-continue.md contient la section des traces (rétentions)" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement 'conformite-continue\.md$' 20 'traces' 'audit' '(1 an|un an|365)'
