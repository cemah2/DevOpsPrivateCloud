# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq entre apostrophes
# break-E37.sh — M26-E37 « Panne : Falco est muet »
#
# Falco ne détecte (ou n'achemine) plus rien. Toutes les variantes passent par une MR de lucas.martin
# (valeurs du chart : plateforme/gitops, valeurs/falco/values.yaml ; règles : plateforme/politiques,
# falco/regles-medisphere.yaml, clé customRules) et ne touchent jamais kube-system, kyverno, argocd ni cilium :
#   1. un nodeSelector ajouté au DaemonSet exclut les travailleurs : Falco ne tourne plus là où sont les
#      charges applicatives ;
#   2. une règle de MédiSphère désactivée par une surcharge (« - rule: … enabled: false ») ;
#   3. la sortie falcosidekick pointe vers une mauvaise URL d'Alertmanager : les détections n'arrivent plus ;
#   4. la priorité minimale chargée est relevée (priority: critical) : les règles d'avertissement/notice
#      ne sont plus évaluées.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E37_VALEURS=valeurs/falco/values.yaml   # plateforme/gitops (M26-E08, E19)
_E37_REGLES=falco/regles-medisphere.yaml

_e37_t1() {
  yq '.nodeSelector = {"node-role.kubernetes.io/control-plane": ""}
      | .nodeSelector head_comment = "PLAT-2737 (Lucas) : limiter Falco aux nœuds de contrôle (essai)"'
}
_e37_i1() { yq 'with(select((.nodeSelector // {}) | has("node-role.kubernetes.io/control-plane")); del(.nodeSelector))'; }
_e37_t3() {
  yq '.falcosidekick.config.alertmanager.hostport |= sub(":9093$"; ":9095")'
}
_e37_i3() {
  yq '.falcosidekick.config.alertmanager.hostport |= sub(":9095$"; ":9093")'
}
_e37_t4() { yq '.falco.priority = "critical" | .falco.priority line_comment = "PLAT-2737 (Lucas) : moins de bruit"'; }
# Inverse : seulement si la marque est encore là ; « notice » est la valeur d'E08/E19.
_e37_i4() {
  yq 'with(select((.falco.priority | line_comment) | test("PLAT-2737")); .falco.priority = "notice" | .falco.priority line_comment = "")'
}
# v2 : désactiver une règle MédiSphère par une surcharge ajoutée à la fin du bloc customRules.
_E37_REGLE="MédiSphère — shell interactif dans un conteneur applicatif"
_e37_t2() {
  R="$_E37_REGLE" yq '.customRules["regles-medisphere.yaml"] += "\n\n# PLAT-2737 (Lucas) : règle trop bruyante, désactivée le temps d un réglage\n- rule: " + strenv(R) + "\n  enabled: false"'
}
_e37_i2() {
  grep -v -F 'PLAT-2737 (Lucas) : règle trop bruyante' | awk -v r="- rule: $_E37_REGLE" '
    { t = $0; sub(/^[ ]+/, "", t) }
    t == r { buf = $0; if ((getline n) > 0) { if (n ~ /^[ ]+enabled: false/) next; print buf; print n; next } }
    { print }'
}

# Effet observé sur le cluster (kubectl d'administration).
_e37_falco_cm() { wb_kubectl -n "$_M26_NS_FALCO" get configmap -o json 2>/dev/null; }
_e37_effet() {
  case "$1" in
    # Effet réel : le DaemonSet porte le nodeSelector ET aucun pod Falco ne tourne sur un travailleur.
    # (Comparer desiredNumberScheduled au nombre de TRAVAILLEURS ne marchait pas : 3 nœuds de contrôle
    # tolérés = 3 travailleurs.)
    1)
      local t nb=0
      wb_kubectl -n "$_M26_NS_FALCO" get daemonset falco -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null \
        | grep -q 'node-role.kubernetes.io/control-plane' || return 1
      for t in $(wb_kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name 2>/dev/null); do
        nb=$((nb + $(wb_kubectl -n "$_M26_NS_FALCO" get pods -l app.kubernetes.io/name=falco \
          --field-selector "spec.nodeName=${t#node/}" --no-headers 2>/dev/null | grep -c Running)))
      done
      ((nb == 0))
      ;;
    2) _e37_falco_cm | jq -e '[.items[].data // {} | to_entries[] | .value | select(test("shell interactif dans un conteneur applicatif"; "i") and test("enabled: *false"))] | length > 0' >/dev/null 2>&1 ;;
    # La configuration de falcosidekick est dans un Secret (variables d'environnement) : on la décode.
    3) wb_kubectl -n "$_M26_NS_FALCO" get secret -o json 2>/dev/null \
         | jq -r '.items[].data // {} | .[] | @base64d' 2>/dev/null | grep -q 'kps-alertmanager.*:9095' ;;
    4) _e37_falco_cm | jq -e '[.items[].data["falco.yaml"] // "" | select(test("(?m)^priority: *critical"))] | length > 0' >/dev/null 2>&1 ;;
  esac
}

_m26E37_une() {
  local n="$1"
  m26_ecrire E37 variante "$n"
  case "$n" in
    1) m26_git_transformer E37 val "$_M26_PROJ_GITOPS" "$_E37_VALEURS" "chore(falco): limiter aux nœuds de contrôle (M26-E37)" _e37_t1 || return ;;
    2) m26_git_transformer E37 reg "$_M26_PROJ_POL" "$_E37_REGLES" "chore(falco): désactiver une règle bruyante (M26-E37)" _e37_t2 || return ;;
    3) m26_git_transformer E37 val "$_M26_PROJ_GITOPS" "$_E37_VALEURS" "fix(falco): corriger le port d'Alertmanager (M26-E37)" _e37_t3 || return ;;
    4) m26_git_transformer E37 val "$_M26_PROJ_GITOPS" "$_E37_VALEURS" "chore(falco): ne garder que les critiques (M26-E37)" _e37_t4 || return ;;
  esac
  m26_journal E37 "variante $n posée"
  m26_attendre 300 _e37_effet "$n" || { _e37_defaire "$n"; return 10; }
}

_e37_defaire() {
  case "$1" in
    1) m26_git_defaire E37 val _e37_i1 "revert(falco): DaemonSet sur tous les nœuds (M26-E37, annulation)" ;;
    2) m26_git_defaire E37 reg _e37_i2 "revert(falco): règle réactivée (M26-E37, annulation)" ;;
    3) m26_git_defaire E37 val _e37_i3 "revert(falco): port d'Alertmanager rétabli (M26-E37, annulation)" ;;
    4) m26_git_defaire E37 val _e37_i4 "revert(falco): priorité minimale rétablie (M26-E37, annulation)" ;;
  esac
}

panne_E37_v1() { m26_kube_sain && m26_essayer E37 4 1; }
panne_E37_v2() { m26_kube_sain && m26_essayer E37 4 2; }
panne_E37_v3() { m26_kube_sain && m26_essayer E37 4 3; }
panne_E37_v4() { m26_kube_sain && m26_essayer E37 4 4; }

verifier_E37() { _e37_effet "$WB_VAR"; }

annuler_E37() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-4]$ ]] || v="$(m26_lire E37 variante)"
  [[ -n "$v" ]] && _e37_defaire "$v"
  m26_oublier E37 variante
  m26_journal E37 "annulation"
}

resume_E37() { echo "Falco ne remonte plus de détection (shell dans un conteneur, lecture d'un jeton…) vers Alertmanager ni Loki."; }

symptome_E37() {
  wb_symptome "Ticket SEC-5337 — De : Sophie Laurent" \
    "Je fais mon essai hebdomadaire : j'ouvre un shell dans un pod de wb-essais, je lis /etc/shadow." \
    "D'habitude Falco crie en quelques secondes (Alertmanager, Loki locataire audit). Là : rien." \
    "La détection à l'exécution, c'est ce qui me reste quand l'admission a laissé passer quelque chose." \
    "Lucas a « réglé le bruit de Falco » cette semaine." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 26 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E37 4 "$@"; }
fi
