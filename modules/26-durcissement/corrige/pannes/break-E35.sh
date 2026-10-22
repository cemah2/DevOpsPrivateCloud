# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq entre apostrophes
# break-E35.sh — M26-E35 « Panne : plus aucun déploiement ne passe en recette »
#
# Toutes les variantes passent par une MR de lucas.martin dans plateforme/politiques ou plateforme/k8s,
# et ne touchent QUE l'espace mediagenda-recette (jamais kube-system, kyverno, argocd, cilium ni la prod) :
#   1. une ValidatingPolicy d'audit (ex. exiger-etiquettes) passée en « Deny » avec une condition trop
#      large : toute charge de la recette est refusée (symptôme : admission webhook denied the request) ;
#   2. la même politique scopée à mediagenda-recette passe en failurePolicy: Fail avec une matchCondition
#      CEL qui référence un champ absent : son évaluation échoue, et « Fail » refuse la requête (le
#      contrôleur Kyverno n'est JAMAIS arrêté : seul l'espace recette est bloqué) ;
#   3. une GeneratingPolicy pose sur la recette un refus réseau total sans autoriser le DNS ni les sondes :
#      les nouveaux pods démarrent mais ne passent plus leurs sondes, le déploiement n'aboutit jamais.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E35_NS=mediagenda-recette

# Politique d'étiquettes (ValidatingPolicy) retrouvée dans plateforme/politiques.
_e35_fichier_etiquettes() {
  m26_git_trouver "$_M26_PROJ_POL" '.kind == "ValidatingPolicy" and (.metadata.name | test("etiquette|limites|registre"))' kyverno/validation
}

# v1 : Audit → Deny, et matchCondition supplémentaire qui exige une annotation que les charges n'ont pas.
_e35_t1() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.validationActions) = ["Deny"]
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions) += [{"name": "exiger-change", "expression": "has(object.metadata.annotations) && \"medisphere.internal/change\" in object.metadata.annotations"}]
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions[-1]) head_comment = "SEC-2735 (Lucas) : refuser toute charge sans ticket de changement"'
}
_e35_i1() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.validationActions) = ["Audit"]
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions) |= map(select(.name != "exiger-change"))'
}
# v2 : failurePolicy Fail + matchCondition CEL vers un champ absent (évaluation en échec → refus).
_e35_t2() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.failurePolicy) = "Fail"
      | (select(.kind == "ValidatingPolicy") | .spec.matchConstraints.namespaceSelector.matchLabels) = {"kubernetes.io/metadata.name": "mediagenda-recette"}
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions) += [{"name": "garde-recette", "expression": "object.spec.template.metadata.labels.absent == \"oui\""}]'
}
_e35_i2() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.failurePolicy) = "Ignore"
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions) |= map(select(.name != "garde-recette"))'
}

_e35_effet() {
  case "$1" in
    1 | 2) ! m26_admis "$_E35_NS" ;;   # un pod conforme est désormais refusé en recette
    3) wb_kubectl -n "$_E35_NS" get networkpolicy,ciliumnetworkpolicies -o name 2>/dev/null | grep -qi 'refus\|deny\|default-deny' ;;
  esac
}

_m26E35_une() {
  local n="$1" f
  m26_ecrire E35 variante "$n"
  case "$n" in
    1 | 2)
      f="$(_e35_fichier_etiquettes)" || return 10
      if ((n == 1)); then
        m26_git_transformer E35 pol "$_M26_PROJ_POL" "$f" \
          "feat(validation): refuser les charges sans ticket de changement (M26-E35)" _e35_t1 || return
      else
        m26_git_transformer E35 pol "$_M26_PROJ_POL" "$f" \
          "fix(validation): garde stricte de mediagenda-recette (M26-E35)" _e35_t2 || return
      fi
      ;;
    3)
      # GeneratingPolicy existante (networkpolicy-par-defaut) ou, à défaut, objet posé directement dans
      # l'espace recette (sauvegardé pour l'annulation). Ici : refus total sans DNS ni sondes.
      m26_sauver_objet E35 ciliumnetworkpolicies refus-total "$_E35_NS"
      wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: refus-total
  namespace: $_E35_NS
  annotations:
    medisphere.internal/auteur: lucas.martin
    medisphere.internal/ticket: "SEC-2735"
  labels: {medisphere.internal/panne: M26-E35}
spec:
  endpointSelector: {}
  ingress: []
  egress: []
EOF
      ;;
  esac
  m26_journal E35 "variante $n posée"
  m26_attendre 300 _e35_effet "$n" || { _e35_defaire "$n"; return 10; }
}

_e35_defaire() {
  case "$1" in
    1) m26_git_defaire E35 pol _e35_i1 "revert(validation): retour en audit (M26-E35, annulation)" ;;
    2) m26_git_defaire E35 pol _e35_i2 "revert(validation): garde recette retirée (M26-E35, annulation)" ;;
    3) m26_restaurer_objet E35 ciliumnetworkpolicies refus-total "$_E35_NS" ;;
  esac
}

panne_E35_v1() { m26_kube_sain && m26_essayer E35 3 1; }
panne_E35_v2() { m26_kube_sain && m26_essayer E35 3 2; }
panne_E35_v3() { m26_kube_sain && m26_essayer E35 3 3; }

verifier_E35() { _e35_effet "$WB_VAR"; }

annuler_E35() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-3]$ ]] || v="$(m26_lire E35 variante)"
  [[ -n "$v" ]] && _e35_defaire "$v"
  m26_oublier E35 variante
  m26_journal E35 "annulation"
}

resume_E35() { echo "Aucun déploiement ne passe plus dans mediagenda-recette (admission refusée ou pods jamais prêts)."; }

symptome_E35() {
  wb_symptome "Ticket INC-5335 — De : Julien Petit" \
    "Depuis cet après-midi, plus aucune MR de déploiement ne finit en recette." \
    "Argo CD montre mediagenda-recette en échec de synchronisation (ou les pods restent" \
    "indéfiniment « non prêts »). La prod n'est pas touchée. Lucas a fusionné une MR dans" \
    "plateforme/politiques ce matin « pour durcir la recette »." \
    "On doit livrer une correction de MédiAgenda avant ce soir." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 26 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E35 3 "$@"; }
fi
