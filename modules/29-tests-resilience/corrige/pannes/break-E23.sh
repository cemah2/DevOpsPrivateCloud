# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E23.sh — M29-E23 « Astreinte : la journée de jeu réveille une vraie faiblesse » (recette)
#
# Scène : un défaut latent est introduit par un commit de Lucas dans mediagenda/deploiement (overlay
# recette SEULEMENT, par un « patches » de overlays/recette/kustomization.yaml), Argo CD le déploie, puis
# la « journée de jeu automatique de Karim » (Workflow de chaos-experiences, deadlines courtes) s'exécute
# sur la recette. Faiblesse de conception réelle, présente dans l'application depuis le M12 : /pret
# exige Valkey, donc une coupure du cache rend TOUS les pods de l'API non prêts.
#   1. défaut latent : sonde de VIVACITÉ de l'API sur /pret (« plus honnête que /sante ») ;
#      journée de jeu : partition API ↔ Valkey de 45 s en parallèle d'un pod-kill d'une API ;
#      effet : redémarrages en chaîne de toutes les API (vivacité), CrashLoopBackOff, retour lent ;
#   2. défaut latent : minReplicas de l'HPA à 1 en recette (« économiser le quota ») ;
#      journée de jeu : pod-kill d'une API, pause, container-kill de Valkey ;
#      effet : plus aucune API prête le temps qu'un pod remplace l'unique réplique, puis coupure du cache.
# L'injection vérifie l'effet (fenêtre sans aucune API prête ≥ 20 s ; redémarrages pour la variante 1).
# Annulation : Workflow supprimé (expériences filles comprises), commit inverse si intact.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m29-commun.sh
source "$WB_ROOT/modules/29-tests-resilience/corrige/pannes/_m29-commun.sh"

_E23_DEPOT="${WB_M29_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_E23_KUSTO="${WB_M29_FICHIER_KUSTO_RECETTE:-overlays/recette/kustomization.yaml}"
_E23_WF=journee-de-jeu-auto

_e23_app() { m29_app_de_espace "$_M29_RECETTE"; }

_e23_sain() {
  m29_outils ssh || return 1
  m29_chaos_sain || { echo "Chaos Mesh n'est pas sain (lab/bin/check 29 09)." >&2; return 1; }
  if (($(m29_api_pretes) < 2)); then
    echo "Il faut au moins deux pods prêts de l'API MédiAgenda en recette avant l'astreinte." >&2
    return 1
  fi
  local a
  a="$(_e23_app)"
  if [[ -z "$a" ]] || ! m29_app_saine "$a"; then
    echo "L'Application Argo CD de $_M29_RECETTE doit être Synced/Healthy." >&2
    return 1
  fi
  m29_poser E23 app "$a"
  if wb_kubectl -n "$_M29_CHAOS_NS" get workflow "$_E23_WF" >/dev/null 2>&1; then
    echo "Un Workflow $_E23_WF existe déjà dans $_M29_CHAOS_NS : supprime-le avant." >&2
    return 1
  fi
  wb_kubectl get pods -n "$_M29_RECETTE" -l app.kubernetes.io/name=valkey -o name 2>/dev/null | grep -q . ||
    { echo "Pas de pod Valkey (app.kubernetes.io/name=valkey) dans $_M29_RECETTE." >&2; return 1; }
}

# --- Défaut latent ----------------------------------------------------------------------------------

_e23_sonde_pret() {
  # Tous les pods prêts de l'API ont une vivacité sur /pret.
  wb_kubectl -n "$_M29_RECETTE" get pods -l "$_M29_API_SEL" -o json 2>/dev/null |
    jq -e '[.items[] | select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] as $p
           | ($p | length) >= 1 and all($p[]; any(.spec.containers[]; .livenessProbe.httpGet.path? == "/pret"))' >/dev/null 2>&1
}
_e23_une_replique() {
  wb_kubectl -n "$_M29_RECETTE" get hpa -o json 2>/dev/null | jq -e 'any(.items[]; .spec.minReplicas == 1)' >/dev/null 2>&1 &&
    (($(m29_api_pretes) == 1))
}

_e23_latent() {
  local n="$1" tmp expr
  tmp="$(m29_etat E23)/kustomization.yaml"
  m29_git_lire "$_E23_DEPOT" "$_E23_KUSTO" >"$tmp.orig" 2>/dev/null || return 10
  if ((n == 1)); then
    expr='.patches += [{"target": {"kind": "Deployment", "name": "mediagenda"},
      "patch": "- op: replace\n  path: /spec/template/spec/containers/0/livenessProbe/httpGet/path\n  value: /pret\n"}]'
  else
    expr='.patches += [{"target": {"kind": "HorizontalPodAutoscaler"},
      "patch": "- op: replace\n  path: /spec/minReplicas\n  value: 1\n"}]'
  fi
  yq "$expr" "$tmp.orig" >"$tmp" || return 10
  m29_git_debut E23 "$_E23_DEPOT"
  m29_git_fichier E23 "$_E23_KUSTO" "$tmp"
  if ((n == 1)); then
    m29_git_valider E23 "fix(recette): vivacité sur /pret, plus honnête que /sante (M29-E23)

Un pod qui ne joint plus ses dépendances ne sert à rien, autant le redémarrer. -- Lucas" || return $?
  else
    m29_git_valider E23 "chore(recette): minReplicas à 1 pour économiser le quota la nuit (M29-E23)

L'HPA remonte de toute façon s'il y a de la charge. -- Lucas" || return $?
  fi
  m29_rafraichir "$(m29_lire E23 app)"
  if ((n == 1)); then
    m29_attendre 900 _e23_sonde_pret || return 10
  else
    m29_attendre 720 _e23_une_replique || return 10
  fi
}

# --- Journée de jeu automatique ---------------------------------------------------------------------

_e23_workflow() {
  if (($1 == 1)); then
    cat <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: Workflow
metadata:
  name: $_E23_WF
  namespace: $_M29_CHAOS_NS
  labels: {medisphere.internal/auteur: karim.benali}
  annotations:
    medisphere.internal/hypothese: "Cache coupé 45 s et une API perdue : aucun impact visible (Valkey est un cache, 2 réplicas)"
spec:
  entry: jeu
  templates:
    - name: jeu
      templateType: Parallel
      deadline: 2m
      children: [coupure-cache, perte-api]
    - name: coupure-cache
      templateType: NetworkChaos
      deadline: 45s
      networkChaos:
        action: partition
        mode: all
        selector:
          namespaces: [$_M29_RECETTE]
          labelSelectors: {app.kubernetes.io/name: mediagenda, app.kubernetes.io/component: api}
        direction: both
        target:
          mode: all
          selector:
            namespaces: [$_M29_RECETTE]
            labelSelectors: {app.kubernetes.io/name: valkey}
    - name: perte-api
      templateType: PodChaos
      deadline: 30s
      podChaos:
        action: pod-kill
        mode: one
        selector:
          namespaces: [$_M29_RECETTE]
          labelSelectors: {app.kubernetes.io/name: mediagenda, app.kubernetes.io/component: api}
EOF
  else
    cat <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: Workflow
metadata:
  name: $_E23_WF
  namespace: $_M29_CHAOS_NS
  labels: {medisphere.internal/auteur: karim.benali}
  annotations:
    medisphere.internal/hypothese: "Une API perdue puis un redémarrage du cache : aucun impact visible"
spec:
  entry: jeu
  templates:
    - name: jeu
      templateType: Serial
      deadline: 4m
      children: [perte-api, attente, redemarrage-cache]
    - name: perte-api
      templateType: PodChaos
      deadline: 30s
      podChaos:
        action: pod-kill
        mode: one
        selector:
          namespaces: [$_M29_RECETTE]
          labelSelectors: {app.kubernetes.io/name: mediagenda, app.kubernetes.io/component: api}
    - name: attente
      templateType: Suspend
      deadline: 30s
    - name: redemarrage-cache
      templateType: PodChaos
      deadline: 30s
      podChaos:
        action: container-kill
        mode: one
        containerNames: [valkey]
        selector:
          namespaces: [$_M29_RECETTE]
          labelSelectors: {app.kubernetes.io/name: valkey}
EOF
  fi
}

# _e23_restarts — somme des redémarrages des conteneurs des pods de l'API.
_e23_restarts() {
  wb_kubectl -n "$_M29_RECETTE" get pods -l "$_M29_API_SEL" -o json 2>/dev/null |
    jq '[.items[].status.containerStatuses[]?.restartCount] | add // 0' 2>/dev/null || echo 0
}

# _e23_jouer N — lance la journée de jeu et mesure la plus longue fenêtre sans API prête (s).
_e23_jouer() {
  local n="$1" t=0 zero=0 max=0 r0 trafic
  r0="$(_e23_restarts)"
  m29_poser E23 restarts-avant "$r0"
  trafic="$(m29_trafic_recette 420)"
  _e23_workflow "$n" | wb_kubectl apply -f - >/dev/null || return 1
  m29_poser E23 workflow 1
  m29_journal E23 "journée de jeu automatique lancée"
  while ((t < 420)); do
    if (($(m29_api_pretes) == 0)); then
      zero=$((zero + 5))
      ((zero > max)) && max=$zero
    else
      zero=0
      # sortie anticipée : le jeu est fini depuis 2 min et tout est prêt
      ((t > 300)) && break
    fi
    sleep 5
    t=$((t + 5))
  done
  kill "$trafic" 2>/dev/null || true
  m29_poser E23 indisponibilite "$max"
  m29_poser E23 restarts-apres "$(_e23_restarts)"
  m29_journal E23 "plus longue fenêtre sans API prête : ${max} s"
}

_m29E23_une() {
  local n="$1"
  _e23_latent "$n" || return $?
  _e23_jouer "$n" || return 1
  (($(m29_lire E23 indisponibilite) >= 20)) || return 10
  if ((n == 1)); then
    (($(m29_lire E23 restarts-apres) > $(m29_lire E23 restarts-avant))) || return 10
  fi
  m29_journal E23 "variante $n posée"
}

_m29E23_defaire() {
  local e t noeuds filles=()
  if [[ -n "$(m29_lire E23 workflow)" ]]; then
    # Expériences filles : créées par les WorkflowNode du Workflow (étiquette chaos-mesh.org/workflow
    # sur les nœuds, chaos-mesh.org/controlled-by=<nœud> sur les expériences). Relevées AVANT la
    # suppression (le ramasse-miettes les emporte ensuite avec leurs finaliseurs).
    noeuds="$(wb_kubectl -n "$_M29_CHAOS_NS" get workflownodes -l "chaos-mesh.org/workflow=$_E23_WF" -o name 2>/dev/null | sed 's|.*/||' | paste -sd, -)"
    if [[ -n "$noeuds" ]]; then
      for t in networkchaos podchaos; do
        while IFS= read -r e; do
          [[ -n "$e" ]] && filles+=("$t $e")
        done < <(wb_kubectl -n "$_M29_CHAOS_NS" get "$t" -l "chaos-mesh.org/controlled-by in ($noeuds)" -o name 2>/dev/null | sed 's|.*/||')
      done
    fi
    # Un Workflow n'a pas de pause (Chaos Mesh 2.8) : on le supprime directement.
    wb_kubectl -n "$_M29_CHAOS_NS" delete workflow "$_E23_WF" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    sleep 20
    for e in "${filles[@]}"; do
      # shellcheck disable=SC2086  # « type nom » découpé volontairement
      m29_supprimer_chaos "$_M29_CHAOS_NS" $e
    done
    m29_oublier E23 workflow
  fi
  m29_git_annuler E23 || true
  m29_rafraichir "$(m29_lire E23 app)"
}

panne_E23_v1() { _e23_sain && m29_essayer E23 2 1; }
panne_E23_v2() { _e23_sain && m29_essayer E23 2 2; }

verifier_E23() { m29_git_injecte E23 && (($(m29_lire E23 indisponibilite) >= 20)); }

annuler_E23() {
  _m29E23_defaire
  m29_journal E23 "annulation"
}

resume_E23() {
  echo "La journée de jeu automatique de la recette a rendu MédiAgenda indisponible $(m29_lire E23 indisponibilite) s d'affilée au lieu de « aucun impact »."
}

symptome_E23() {
  wb_symptome "Ticket INC-5623 — De : Nadia Roussel — Copie : Julien Petit, Claire Morel" \
    "La journée de jeu automatique de Karim (Workflow « $_E23_WF » sur la recette) s'est lancée" \
    "il y a quelques minutes. Hypothèse affichée : « aucun impact visible ». Résultat : MédiAgenda" \
    "recette n'avait plus AUCUN pod prêt pendant au moins $(m29_lire E23 indisponibilite) s d'affilée, et Julien voit encore" \
    "des choses bizarres. Karim dit que ses expériences ne duraient pas plus d'une minute." \
    "Rétablis, trouve pourquoi c'était si grave, et écris le post-mortem INC-5623." \
    "" \
    "Temps cible : service rétabli en 15 min, enquête et post-mortem en 1 h 15. Contrôle : lab/bin/check 29 23"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 29 E23 2 "$@"; }
fi
