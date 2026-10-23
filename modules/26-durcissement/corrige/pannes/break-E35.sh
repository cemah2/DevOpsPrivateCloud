# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq entre apostrophes
# break-E35.sh — M26-E35 « Panne : plus aucun déploiement ne passe en recette »
#
# Toutes les variantes passent par une MR de lucas.martin dans plateforme/politiques ou plateforme/k8s,
# et ne touchent QUE l'espace mediagenda-recette (jamais kube-system, kyverno, argocd, cilium ni la prod) :
#   1. une ValidatingPolicy déjà en « Deny » qui couvre la recette (ex. exiger-etiquettes) reçoit une
#      validation de trop, limitée par son expression à mediagenda-recette : « toute charge doit citer
#      son ticket de changement » (annotation que les charges n'ont pas) ; toute charge de la recette est
#      refusée (admission webhook denied the request). NB : une matchCondition n'aurait PAS cet effet
#      (une matchCondition fausse fait IGNORER la politique, elle ne refuse rien) ;
#   2. la même politique passe en failurePolicy: Fail avec une matchCondition CEL qui, pour la seule
#      recette, référence un champ absent : son évaluation échoue, et « Fail » refuse la requête (le
#      contrôleur Kyverno n'est JAMAIS arrêté ; le namespaceSelector n'est pas touché) ;
#   3. une CiliumNetworkPolicy « refus-total » (règles vides : refus par défaut en entrée et en sortie)
#      posée à la main dans la recette : les pods qui dépendent du réseau (DNS, base) ne sont plus prêts.
# Les autres espaces (dont la prod) ne sont jamais concernés : chaque garde vise mediagenda-recette.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E35_NS=mediagenda-recette

# ValidatingPolicy de plateforme/politiques déjà en « Deny » (étiquettes, limites ou registres).
_e35_fichier_etiquettes() {
  m26_git_trouver "$_M26_PROJ_POL" '.kind == "ValidatingPolicy" and (.metadata.name | test("etiquette|limites|registre"))
    and ((.spec.validationActions // []) | any_c(. == "Deny"))' kyverno/validation
}

# v1 : validation de trop, limitée à la recette par son expression (marque : SEC-2735 dans le message).
_e35_t1() {
  yq 'with(select(.kind == "ValidatingPolicy");
        .spec.validations += [{"expression": "object.metadata.namespace != \"mediagenda-recette\" || (has(object.metadata.annotations) && \"medisphere.internal/change\" in object.metadata.annotations)", "message": "SEC-2735 (Lucas) : toute charge de la recette doit citer son ticket de changement (annotation medisphere.internal/change)"}])'
}
_e35_i1() {
  yq 'with(select(.kind == "ValidatingPolicy");
        .spec.validations |= map(select((.message // "") | test("SEC-2735") | not)))'
}
# v2 : failurePolicy Fail + matchCondition qui échoue POUR LA RECETTE SEULEMENT (ailleurs, la partie
# gauche du « || » est vraie et la condition ne s'évalue pas plus loin). Valeur d'origine de
# failurePolicy mémorisée (E35/fp-orig) pour l'annulation.
_e35_t2() {
  yq 'with(select(.kind == "ValidatingPolicy");
        .spec.failurePolicy = "Fail"
        | .spec.matchConditions += [{"name": "garde-recette", "expression": "object.metadata.namespace != \"mediagenda-recette\" || object.spec.template.metadata.labels.absent == \"oui\""}])'
}
_e35_i2() {
  FP="$(m26_lire E35 fp-orig)" yq 'with(select(.kind == "ValidatingPolicy" and ((.spec.matchConditions // []) | any_c(.name == "garde-recette")));
        .spec.matchConditions |= map(select(.name != "garde-recette"))
        | with(select((.spec.matchConditions | length) == 0); del(.spec.matchConditions))
        | with(select(strenv(FP) == "" or strenv(FP) == "absent"); del(.spec.failurePolicy))
        | with(select(strenv(FP) != "" and strenv(FP) != "absent"); .spec.failurePolicy = strenv(FP)))'
}

_e35_effet() {
  case "$1" in
    1 | 2) ! m26_admis "$_E35_NS" ;;   # un pod conforme est désormais refusé en recette
    # Effet réel : la politique est là ET au moins un pod de la recette n'est plus prêt.
    3) wb_kubectl -n "$_E35_NS" get ciliumnetworkpolicies refus-total -o name >/dev/null 2>&1 \
         && wb_kubectl -n "$_E35_NS" get pods -o json 2>/dev/null \
            | jq -e '[.items[] | select(.status.phase == "Running") | select(any(.status.conditions[]?; .type == "Ready" and .status != "True"))] | length > 0' >/dev/null 2>&1 ;;
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
        m26_ecrire E35 fp-orig "$(m26_git_lire "$_M26_PROJ_POL" "$f" | yq 'select(.kind == "ValidatingPolicy") | .spec.failurePolicy // "absent"' 2>/dev/null | head -n 1)"
        m26_git_transformer E35 pol "$_M26_PROJ_POL" "$f" \
          "fix(validation): garde stricte de mediagenda-recette (M26-E35)" _e35_t2 || return
      fi
      ;;
    3)
      # Objet posé directement dans l'espace recette (sauvegardé pour l'annulation) : refus total, sans
      # DNS ni base. Une règle VIDE ({}) active le refus par défaut dans son sens ; une liste vide ([])
      # serait ignorée par Cilium (aucun effet).
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
  ingress:
    - {}
  egress:
    - {}
EOF
      ;;
  esac
  m26_journal E35 "variante $n posée"
  m26_attendre 300 _e35_effet "$n" || { _e35_defaire "$n"; return 10; }
}

_e35_defaire() {
  case "$1" in
    1) m26_git_defaire E35 pol _e35_i1 "revert(validation): retour en audit (M26-E35, annulation)" ;;
    2) m26_git_defaire E35 pol _e35_i2 "revert(validation): garde recette retirée (M26-E35, annulation)"
       m26_oublier E35 fp-orig ;;
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
