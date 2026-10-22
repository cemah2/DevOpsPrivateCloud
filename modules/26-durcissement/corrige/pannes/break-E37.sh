# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq entre apostrophes
# break-E37.sh — M26-E37 « Panne : Falco est muet »
#
# Falco ne détecte (ou n'achemine) plus rien. Toutes les variantes passent par une MR de lucas.martin
# dans plateforme/politiques (valeurs du chart falco/values.yaml, ou falco/regles-medisphere.yaml) et ne
# touchent jamais kube-system, kyverno, argocd ni cilium :
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

_E37_VALEURS=falco/values.yaml
_E37_REGLES=falco/regles-medisphere.yaml

_e37_t1() {
  yq '.falco.nodeSelector = {"node-role.kubernetes.io/control-plane": ""}
      | .falco.nodeSelector | head_comment = "PLAT-2737 (Lucas) : limiter Falco aux nœuds de contrôle (essai)"'
}
_e37_i1() { yq 'del(.falco.nodeSelector)'; }
_e37_t3() {
  yq '(.falcosidekick.config.alertmanager.hostport) = "http://kps-alertmanager.supervision:9095"'
}
_e37_i3() {
  yq '(.falcosidekick.config.alertmanager.hostport) = "http://kps-alertmanager.supervision:9093"'
}
_e37_t4() { yq '.falco.falco.priority = "critical"'; }
_e37_i4() { yq '.falco.falco.priority = "notice"'; }
# v2 : désactiver une règle MédiSphère par une surcharge en fin de fichier de règles.
_e37_t2() {
  cat
  cat <<'EOF'
# PLAT-2737 (Lucas) : règle trop bruyante, désactivée le temps d'un réglage
- rule: Shell interactif dans un conteneur applicatif
  enabled: false
EOF
}
_e37_i2() {
  grep -v -F 'PLAT-2737 (Lucas) : règle trop bruyante' | awk '
    /^- rule: Shell interactif dans un conteneur applicatif$/ { buf=$0; getline n; if (n ~ /enabled: false/) { next } else { print buf; print n; next } }
    { print }'
}

# Effet observé sur le cluster (kubectl d'administration).
_e37_falco_cm() { wb_kubectl -n "$_M26_NS_FALCO" get configmap -o json 2>/dev/null; }
_e37_effet() {
  case "$1" in
    1)
      local prog dispo
      prog="$(wb_kubectl -n "$_M26_NS_FALCO" get daemonset falco -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)" || return 1
      dispo="$(wb_kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name 2>/dev/null | wc -l)"
      [[ -n "$prog" ]] && ((prog < dispo))
      ;;
    2) _e37_falco_cm | jq -e '[.items[].data // {} | to_entries[] | .value | select(test("Shell interactif dans un conteneur applicatif") and test("enabled: *false"))] | length > 0' >/dev/null 2>&1 ;;
    3) wb_kubectl -n "$_M26_NS_FALCO" get deploy,cm -o json 2>/dev/null | grep -q '9095' ;;
    4) _e37_falco_cm | jq -e '[.items[].data["falco.yaml"] // "" | select(test("(?m)^priority: *critical"))] | length > 0' >/dev/null 2>&1 ;;
  esac
}

_m26E37_une() {
  local n="$1"
  m26_ecrire E37 variante "$n"
  case "$n" in
    1) m26_git_transformer E37 val "$_M26_PROJ_POL" "$_E37_VALEURS" "chore(falco): limiter aux nœuds de contrôle (M26-E37)" _e37_t1 || return ;;
    2) m26_git_transformer E37 reg "$_M26_PROJ_POL" "$_E37_REGLES" "chore(falco): désactiver une règle bruyante (M26-E37)" _e37_t2 || return ;;
    3) m26_git_transformer E37 val "$_M26_PROJ_POL" "$_E37_VALEURS" "fix(falco): corriger le port d'Alertmanager (M26-E37)" _e37_t3 || return ;;
    4) m26_git_transformer E37 val "$_M26_PROJ_POL" "$_E37_VALEURS" "chore(falco): ne garder que les critiques (M26-E37)" _e37_t4 || return ;;
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
