#!/usr/bin/env bash
# verifier-overlay.sh — contrôles des overlays de mediagenda/deploiement qui manquaient au pipeline
# de validation (M20-E36, complété en M20-E41). À placer dans outils/ du dépôt mediagenda/deploiement.
#
#   outils/verifier-overlay.sh overlays/dev [RÉFÉRENCE]      (RÉFÉRENCE : défaut origin/main)
#
# Le rendu « kustomize build » et kubeconform (déjà dans le composant deploiement du M19) disent si
# les manifestes sont BIEN FORMÉS. Ils ne disent pas si le cluster et Argo CD les ACCEPTERONT, ni ce
# que la fusion SUPPRIMERA. Ce script ajoute, sans aucun accès au cluster :
#   1. ressources de portée cluster (refusées par les AppProjects d'application, M20-E07) ;
#   2. Services LoadBalancer/NodePort (quota services.loadbalancers=0, exposition par la Gateway) ;
#   3. hooks Argo CD sans politique de suppression ni délai (un hook bloqué bloque la synchro) ;
#   4. sélecteurs de Deployment/StatefulSet modifiés par rapport à la référence (champ immuable) ;
#   5. objets qui disparaîtraient du rendu (élagage) : refus si l'un porte des données (PVC, base
#      CNPG, StatefulSet avec volumeClaimTemplates), liste affichée dans tous les cas.
# Sortie : 0 si tout va bien ; 1 sinon (le job de MR échoue, avec la raison).
set -euo pipefail

overlay="${1:?usage : $0 OVERLAY [RÉFÉRENCE]}"
ref="${2:-origin/main}"
for c in kustomize yq git; do
  command -v "$c" >/dev/null || { echo "outil nécessaire : $c" >&2; exit 2; }
done
yq --version | grep -q mikefarah || { echo "yq doit être celui de mikefarah" >&2; exit 2; }

# Argo CD 3.5 embarque Kustomize 5.8.1 : la CI doit rendre avec la même version.
attendue="${KUSTOMIZE_ATTENDUE:-v5.8.1}"
if [[ "$(kustomize version 2>/dev/null)" != "$attendue"* ]]; then
  echo "AVERTISSEMENT : kustomize $(kustomize version 2>/dev/null) ≠ $attendue (version d'Argo CD) : les rendus peuvent différer" >&2
fi

tmp="$(mktemp -d)"
trap 'git worktree remove --force "$tmp/ref" >/dev/null 2>&1 || true; rm -rf -- "$tmp"' EXIT
kustomize build "$overlay" >"$tmp/nouveau.yaml"
ko=0
signaler() { printf 'REFUS : %s\n' "$*"; ko=1; }

# 1. Portée cluster
while read -r o; do
  [[ -n "$o" ]] && signaler "$overlay : ressource de portée cluster $o (interdite par l'AppProject, à porter par plateforme/k8s)"
done < <(yq -N 'select(.kind | test("^(Namespace|ClusterRole|ClusterRoleBinding|CustomResourceDefinition|PriorityClass|StorageClass|PersistentVolume|IngressClass|GatewayClass|ValidatingWebhookConfiguration|MutatingWebhookConfiguration|ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding)$")) | .kind + "/" + .metadata.name' "$tmp/nouveau.yaml")

# 2. Exposition hors Gateway
while read -r o; do
  [[ -n "$o" ]] && signaler "$overlay : Service $o de type LoadBalancer ou NodePort (exposition par gw-par1 seulement)"
done < <(yq -N 'select(.kind == "Service" and ((.spec.type // "ClusterIP") | test("LoadBalancer|NodePort"))) | .metadata.name' "$tmp/nouveau.yaml")

# 3. Hooks
while read -r o; do
  [[ -n "$o" ]] && signaler "$overlay : hook $o sans argocd.argoproj.io/hook-delete-policy ou sans activeDeadlineSeconds"
done < <(yq -N 'select(.metadata.annotations["argocd.argoproj.io/hook"] != null)
  | select(.metadata.annotations["argocd.argoproj.io/hook-delete-policy"] == null or (.kind == "Job" and .spec.activeDeadlineSeconds == null))
  | .kind + "/" + .metadata.name' "$tmp/nouveau.yaml")

# 4 et 5 : comparaison avec la référence
if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
  git worktree add --quiet --detach "$tmp/ref" "$ref"
  if [[ -d "$tmp/ref/$overlay" ]]; then
    kustomize build "$tmp/ref/$overlay" >"$tmp/ref.yaml"
    sel() { yq -N 'select(.kind == "Deployment" or .kind == "StatefulSet") | .kind + "/" + .metadata.name + " " + (.spec.selector | to_json(0))' "$1" | sort; }
    while read -r o; do
      [[ -n "$o" ]] && signaler "$overlay : sélecteur modifié pour ${o%% *} (champ immuable : l'API refusera la synchronisation)"
    done < <(comm -13 <(sel "$tmp/ref.yaml") <(sel "$tmp/nouveau.yaml") | while read -r obj s; do
      grep -q "^$obj " <(sel "$tmp/ref.yaml") && printf '%s %s\n' "$obj" "$s"
    done)
    ids() { yq -N '.kind + "/" + .metadata.name' "$1" | sort -u; }
    perdus="$(comm -23 <(ids "$tmp/ref.yaml") <(ids "$tmp/nouveau.yaml"))"
    if [[ -n "$perdus" ]]; then
      printf 'Objets qui DISPARAISSENT du rendu (Argo CD les élaguera si prune est actif) :\n%s\n' "$perdus"
      while read -r o; do
        k="${o%%/*}"
        n="${o#*/}"
        case "$k" in
          PersistentVolumeClaim | Cluster) signaler "$overlay : $o porte des données et disparaîtrait du rendu" ;;
          StatefulSet)
            if K="$k" N="$n" yq -e 'select(.kind == env(K) and .metadata.name == env(N)) | .spec.volumeClaimTemplates | length > 0' "$tmp/ref.yaml" >/dev/null 2>&1; then
              signaler "$overlay : $o (volumeClaimTemplates) disparaîtrait du rendu"
            fi
            ;;
        esac
      done <<<"$perdus"
    fi
  else
    echo "$overlay absent de $ref : comparaison sautée (nouvel overlay)"
  fi
else
  echo "AVERTISSEMENT : référence $ref introuvable (GIT_DEPTH trop faible ?) : sélecteurs et élagage non comparés" >&2
fi

if ((ko)); then exit 1; fi
echo "$overlay : aucun refus prévisible."
