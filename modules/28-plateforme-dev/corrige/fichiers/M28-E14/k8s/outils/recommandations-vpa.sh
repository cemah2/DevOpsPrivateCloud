#!/usr/bin/env bash
# plateforme/k8s — outils/recommandations-vpa.sh (M28-E14, PLAT-2914)
#
# Compare les recommandations des VerticalPodAutoscaler (mode « Off » : le VPA recommande, il ne
# touche pas aux pods) aux requests déclarées par le gabarit de pods de leur cible, et produit un
# rapport Markdown daté. Avec --mr, ajoute ce rapport à une branche de plateforme/k8s et ouvre une MR
# (les équipes reportent ensuite les valeurs dans LEUR dépôt de déploiement : le script ne modifie
# aucune charge).
#
# Usage :
#   outils/recommandations-vpa.sh [--seuil POURCENT] [--sortie DOSSIER] [--mr] [--json FICHIER]
#     --seuil   écart minimal (en %, valeur absolue) pour retenir une ligne (défaut : 30)
#     --sortie  dossier du rapport (défaut : rapports/vpa)
#     --mr      pousse le rapport sur une branche et ouvre une MR (GITLAB_TOKEN : jeton de projet
#               de plateforme/k8s, portée api, rôle Developer ; GITLAB_URL, GITLAB_PROJET facultatifs)
#     --json    lit les VPA et les cibles dans un fichier (essais hors cluster) au lieu de kubectl :
#               {"vpa": <kubectl get vpa -A -o json>, "cibles": {"<ns>/<Kind>/<nom>": <objet>}}
#
# Droits Kubernetes : lecture des verticalpodautoscalers, deployments, statefulsets, daemonsets et
# rollouts (le compte wb-checks suffit : KUBECONFIG=~/.config/workbook/k8s-checks.kubeconfig).
# Sortie : 0 (rapport écrit, avec ou sans écart), 1 (erreur), 2 (usage).
set -euo pipefail

seuil=30
sortie=rapports/vpa
mr=0
json=""
while (($#)); do
  case "$1" in
    --seuil) seuil="${2:?}"; shift 2 ;;
    --sortie) sortie="${2:?}"; shift 2 ;;
    --mr) mr=1; shift ;;
    --json) json="${2:?}"; shift 2 ;;
    -h | --help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
[[ "$seuil" =~ ^[0-9]+$ ]] || { echo "--seuil attend un entier" >&2; exit 2; }
command -v jq >/dev/null || { echo "outil manquant : jq" >&2; exit 1; }

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT

# --- 1. Collecte : VPA et gabarit de pods de chaque cible -------------------------------------------
if [[ -n "$json" ]]; then
  jq '.vpa' "$json" >"$travail/vpa.json"
  jq '.cibles' "$json" >"$travail/cibles.json"
else
  command -v kubectl >/dev/null || { echo "outil manquant : kubectl" >&2; exit 1; }
  kubectl get verticalpodautoscalers.autoscaling.k8s.io -A -o json >"$travail/vpa.json"
  echo '{}' >"$travail/cibles.json"
  # Une ligne par cible : espace, type, nom
  jq -r '.items[] | [.metadata.namespace, .spec.targetRef.kind, .spec.targetRef.name] | @tsv' "$travail/vpa.json" |
    while IFS=$'\t' read -r ns kind nom; do
      obj="$(kubectl -n "$ns" get "$kind" "$nom" -o json 2>/dev/null)" || obj='null'
      # Rollout en workloadRef (M20-E16) : le gabarit est dans le Deployment référencé.
      ref="$(jq -r 'select(. != null) | .spec.workloadRef // empty | "\(.kind)/\(.name)"' <<<"$obj")"
      if [[ -n "$ref" ]]; then
        obj="$(kubectl -n "$ns" get "${ref%%/*}" "${ref#*/}" -o json 2>/dev/null)" || obj='null'
      fi
      jq --arg k "$ns/$kind/$nom" --argjson o "$obj" '. + {($k): $o}' "$travail/cibles.json" >"$travail/c.tmp"
      mv "$travail/c.tmp" "$travail/cibles.json"
    done
fi

# --- 2. Calcul des écarts ------------------------------------------------------------------------------
# Quantités Kubernetes → nombres : CPU en cœurs, mémoire en octets.
jq -n --slurpfile v "$travail/vpa.json" --slurpfile c "$travail/cibles.json" --argjson seuil "$seuil" '
  def num:
    tostring as $s
    | ($s | capture("^(?<n>[0-9.]+)(?<u>[A-Za-z]*)$")) as $m
    | ($m.n | tonumber) * ({"": 1, "m": 0.001, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
                           "Ki": 1024, "Mi": 1048576, "Gi": 1073741824, "Ti": 1099511627776}[$m.u]
                          // error("unité inconnue : " + $s));
  def ecart($cible; $decl): if $decl == null or $decl == 0 then null else (($cible - $decl) / $decl * 100 | round) end;
  [ $v[0].items[]
    | . as $vpa
    | ($vpa.metadata.namespace + "/" + $vpa.spec.targetRef.kind + "/" + $vpa.spec.targetRef.name) as $cle
    | ($c[0][$cle] // null) as $obj
    | ($vpa.status.recommendation.containerRecommendations // [])[]
    | . as $rec
    | (($obj.spec.template.spec.containers // []) | map(select(.name == $rec.containerName)) | .[0].resources.requests // {}) as $req
    | {
        espace: $vpa.metadata.namespace, vpa: $vpa.metadata.name, cible: $cle,
        mode: ($vpa.spec.updatePolicy.updateMode // "Auto"),
        conteneur: $rec.containerName,
        cpu_decl: ($req.cpu // null), cpu_cible: ($rec.target.cpu // null),
        mem_decl: ($req.memory // null), mem_cible: ($rec.target.memory // null),
        cible_absente: ($obj == null)
      }
    | . + {
        ecart_cpu: (if .cpu_cible then ecart(.cpu_cible | num; (.cpu_decl // null) | if . then num else null end) else null end),
        ecart_mem: (if .mem_cible then ecart(.mem_cible | num; (.mem_decl // null) | if . then num else null end) else null end)
      }
    | . + {retenu: (.cible_absente or .mode != "Off" or .cpu_decl == null or .mem_decl == null
                    or ((.ecart_cpu // 0) | fabs) >= $seuil or ((.ecart_mem // 0) | fabs) >= $seuil)}
  ]' >"$travail/lignes.json"

# --- 3. Rapport --------------------------------------------------------------------------------------
jour="$(date +%F)"
mkdir -p "$sortie"
rapport="$sortie/$jour.md"
{
  printf '# Recommandations du VPA — %s\n\n' "$jour"
  printf "Généré par \`outils/recommandations-vpa.sh --seuil %s\` (M28-E14). Le VPA est en mode \`Off\` : rien n'est appliqué. " "$seuil"
  printf 'Chaque équipe reporte les valeurs retenues dans son dépôt de déploiement (requests ; limites mémoire à au moins 1,5 × la cible).\n\n'
  printf '| Espace | Charge | Conteneur | CPU déclaré | CPU recommandé | Écart CPU | Mémoire déclarée | Mémoire recommandée | Écart mémoire | Remarque |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|\n'
  jq -r '.[] | select(.retenu) |
    def pct: if . == null then "—" else (if . > 0 then "+" else "" end) + (tostring) + " %" end;
    [ .espace, (.cible | split("/")[1:] | join("/")), .conteneur,
      (.cpu_decl // "absent"), (.cpu_cible // "—"), (.ecart_cpu | pct),
      (.mem_decl // "absent"), (.mem_cible // "—"), (.ecart_mem | pct),
      (if .cible_absente then "cible introuvable"
       elif .mode != "Off" then "VPA en mode " + .mode + " (attendu : Off)"
       elif .cpu_decl == null or .mem_decl == null then "requests manquantes"
       else "" end)
    ] | "| " + join(" | ") + " |"' "$travail/lignes.json"
  printf '\n%s ligne(s) retenue(s) sur %s conteneur(s) suivi(s).\n' \
    "$(jq '[.[] | select(.retenu)] | length' "$travail/lignes.json")" "$(jq 'length' "$travail/lignes.json")"
} >"$rapport"
echo "Rapport : $rapport"

# --- 4. MR (facultatif) -------------------------------------------------------------------------------
if ((mr)); then
  : "${GITLAB_TOKEN:?GITLAB_TOKEN (jeton de projet de plateforme/k8s, portée api) requis avec --mr}"
  command -v curl >/dev/null || { echo "outil manquant : curl" >&2; exit 1; }
  url="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
  projet="$(jq -rn --arg p "${GITLAB_PROJET:-plateforme/k8s}" '$p|@uri')"
  branche="vpa/recommandations-$jour"
  entete="$travail/entete"
  printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN" >"$entete"
  api() { curl -sf --max-time 30 -H @"$entete" "$@"; }
  # Création si le fichier n'existe pas encore sur la branche, mise à jour sinon (relance le même jour).
  action=create
  if api "$url/api/v4/projects/$projet/repository/files/$(jq -rn --arg f "$rapport" '$f|@uri')?ref=$branche" >/dev/null 2>&1; then
    action=update
  else
    api -X POST "$url/api/v4/projects/$projet/repository/branches" \
      --data-urlencode "branch=$branche" --data-urlencode "ref=main" >/dev/null 2>&1 || true
  fi
  jq -n --arg b "$branche" --arg p "$rapport" --arg a "$action" --rawfile c "$rapport" \
    '{branch: $b, commit_message: ("docs(vpa): recommandations du " + ($b | split("-")[-3:] | join("-"))),
      actions: [{action: $a, file_path: $p, content: $c}]}' |
    api -X POST -H 'Content-Type: application/json' --data-binary @- \
      "$url/api/v4/projects/$projet/repository/commits" >/dev/null
  if ! api "$url/api/v4/projects/$projet/merge_requests?state=opened&source_branch=$branche" | jq -e 'length > 0' >/dev/null; then
    api -X POST "$url/api/v4/projects/$projet/merge_requests" \
      --data-urlencode "source_branch=$branche" --data-urlencode "target_branch=main" \
      --data-urlencode "title=Recommandations du VPA du $jour" \
      --data-urlencode "description=Rapport généré par outils/recommandations-vpa.sh (seuil ${seuil} %). À relire avec les équipes concernées ; aucune charge n'est modifiée par cette MR." \
      --data-urlencode "remove_source_branch=true" | jq -r '"MR : " + .web_url'
  else
    echo "MR déjà ouverte pour $branche : rapport mis à jour."
  fi
fi
