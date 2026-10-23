#!/usr/bin/env bash
# plateforme/resilience — outils/chaos-arret.sh (M29-E13, PLAT-3013 ; RB-294)
# Arrêt d'urgence de TOUTES les expériences de chaos de l'espace des expériences :
#   1. met en pause (annotation experiment.chaos-mesh.org/pause=true) les Schedule, INTERROMPT les
#      Workflow (annotation workflow.chaos-mesh.org/abort=true : Chaos Mesh 2.8 n'a pas de pause de
#      Workflow, l'annotation de pause y est ignorée ; l'interruption termine les nœuds en cours, qui
#      suppriment leurs expériences), puis met en pause chaque expérience : le contrôleur fait retirer
#      les pannes par les chaos-daemon ;
#   2. affiche ce qui reste injecté (enregistrements par conteneur encore « Injected ») ;
#   3. avec --supprimer : supprime tout (Schedule et Workflow d'abord : ils recréeraient des enfants).
# Usage : outils/chaos-arret.sh [--espace chaos-experiences] [--supprimer]
# Droits : ceux de l'identité personnelle (OIDC) de la plateforme ; n'agit QUE dans l'espace donné.
set -euo pipefail

espace=chaos-experiences
supprimer=0
while (($#)); do
  case "$1" in
    --espace) espace="${2:?--espace attend un nom}"; shift 2 ;;
    --supprimer) supprimer=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

mapfile -t types < <(kubectl api-resources --api-group=chaos-mesh.org --namespaced -o name |
  grep -Ev '^(podnetworkchaos|podiochaos|podhttpchaos|workflownodes|statuschecks|remoteclusters|physicalmachines)\.')
# Ordre : ce qui crée d'abord (Schedule, Workflow), puis les expériences.
ordre=()
for t in schedules.chaos-mesh.org workflows.chaos-mesh.org; do ordre+=("$t"); done
for t in "${types[@]}"; do
  [[ "$t" == schedules.* || "$t" == workflows.* ]] || ordre+=("$t")
done

echo "== Pause de tout ce qui vit dans $espace (Workflow : interruption, ils n'ont pas de pause) =="
for t in "${ordre[@]}"; do
  while IFS= read -r o; do
    [[ -n "$o" ]] || continue
    if [[ "$t" == workflows.* ]]; then
      kubectl -n "$espace" annotate "$o" workflow.chaos-mesh.org/abort=true --overwrite
    else
      kubectl -n "$espace" annotate "$o" experiment.chaos-mesh.org/pause=true --overwrite
    fi
  done < <(kubectl -n "$espace" get "$t" -o name 2>/dev/null)
done

echo "== Attente du retrait (30 s) =="
sleep 30
echo "== Ce qui est encore injecté =="
reste=0
for t in "${ordre[@]}"; do
  [[ "$t" == schedules.* || "$t" == workflows.* ]] && continue
  while IFS=$'\t' read -r nom n; do
    [[ -n "$nom" ]] || continue
    echo "  $t/$nom : $n conteneur(s) encore Injected"
    reste=1
  done < <(kubectl -n "$espace" get "$t" -o json 2>/dev/null |
    jq -r '.items[] | [.metadata.name, ([.status.experiment.containerRecords[]? | select(.phase == "Injected")] | length)]
           | select(.[1] > 0) | @tsv')
done
((reste)) || echo "  rien"

if ((supprimer)); then
  echo "== Suppression =="
  for t in "${ordre[@]}"; do
    kubectl -n "$espace" delete "$t" --all --wait=false 2>/dev/null || true
  done
  echo "Vérifie dans 1 min : kubectl -n $espace get $(IFS=,; echo "${ordre[*]}")"
  echo "Un objet bloqué en suppression (finaliseur chaos-mesh/records) : RB-297."
fi
((reste == 0))
