#!/usr/bin/env bash
# =============================================================================
# outils/promouvoir.sh (mediagenda/deploiement) — promouvoir une version de MédiAgenda d'un
# environnement au suivant, PAR MR (M20-E14, PLAT-2114).
#
# Recopie de l'overlay SOURCE vers l'overlay CIBLE :
#   - l'entrée de l'image de l'API du bloc « images: » de kustomization.yaml (posée par la CI en dev,
#     M19-E17) : étiquette (newTag = la version) ET digest — c'est le digest qui fixe le contenu ;
#   - la version lisible (data.version de livraison.yaml) : étiquettes, MEDIAGENDA_VERSION.
# Le garde-fou outils/verifier-livraison.sh (M17-E21, M19-E17) exige que newTag = livraison.yaml.
# Rien n'est reconstruit ni re-étiqueté : on promeut le MÊME artefact, signé, déjà éprouvé en amont.
# Le script vérifie la signature Cosign du digest, crée la branche promotion/<cible>-<version>,
# committe, pousse et ouvre la MR (options de « git push » de GitLab). La fusion reste humaine
# (Maintainers : Julien Petit, Karim Benali) ; Argo CD fait le reste (recette : automatique ; prod :
# synchronisation manuelle).
#
# Usage, depuis un clone à jour de mediagenda/deploiement, branche main propre :
#   outils/promouvoir.sh dev recette
#   outils/promouvoir.sh recette prod
# Options :
#   --sans-mr   prépare la branche et le commit sans pousser (relecture locale)
# Variables :
#   COSIGN_PUB  clé publique MédiSphère (défaut : MS_COSIGN_PUB, sinon ~/medisphere/docs/registre/cosign.pub)
# Prérequis : git, yq 4 (mikefarah), kubectl 1.36 (rendu par son Kustomize intégré), cosign 3.
# Codes retour : 0 MR ouverte (ou rien à faire) ; 1 refus ou échec ; 2 usage ou préalable manquant.
# =============================================================================
set -Eeuo pipefail

IMAGE="registry.par1.medisphere.internal/medisphere/mediagenda-api"
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLE="${COSIGN_PUB:-${MS_COSIGN_PUB:-$HOME/medisphere/docs/registre/cosign.pub}}"

usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; }
erreur() { printf 'promouvoir.sh : %s\n' "$*" >&2; }

pousser=1
args=()
for a in "$@"; do
  case "$a" in
    --sans-mr) pousser=0 ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) args+=("$a") ;;
  esac
done
((${#args[@]} == 2)) || { usage >&2; exit 2; }
source_env="${args[0]}"
cible="${args[1]}"

# Seuls les chemins de promotion prévus : on ne saute pas la recette, on ne redescend pas.
case "$source_env>$cible" in
  "dev>recette" | "recette>prod") ;;
  *) erreur "promotion $source_env → $cible refusée (chemins permis : dev → recette, recette → prod)"; exit 1 ;;
esac

for outil in git yq kubectl cosign; do
  command -v "$outil" >/dev/null || { erreur "$outil absent"; exit 2; }
done
[[ -r "$CLE" ]] || { erreur "clé publique Cosign illisible : $CLE"; exit 2; }

cd "$RACINE"
[[ -z "$(git status --porcelain)" ]] || { erreur "copie de travail modifiée : committe ou range d'abord"; exit 1; }
git fetch --quiet origin main
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || { erreur "place-toi sur main"; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || { erreur "main n'est pas à jour avec origin/main (git pull --ff-only)"; exit 1; }

# lire_digest OVERLAY — digest de l'image de l'API dans overlays/OVERLAY/kustomization.yaml (vide si absent).
lire_digest() {
  IMG="$IMAGE" yq -r '(.images // [])[] | select(.name == strenv(IMG)) | .digest // ""' \
    "overlays/$1/kustomization.yaml"
}
lire_version() { yq -r '.data.version // ""' "overlays/$1/livraison.yaml"; }
lire_etiquette() {
  IMG="$IMAGE" yq -r '(.images // [])[] | select(.name == strenv(IMG)) | .newTag // ""' \
    "overlays/$1/kustomization.yaml"
}

digest="$(lire_digest "$source_env")"
version="$(lire_version "$source_env")"
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] \
  || { erreur "overlays/$source_env : aucun digest valide pour $IMAGE (promotion de la CI absente ?)"; exit 1; }
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { erreur "overlays/$source_env/livraison.yaml : version « $version » invalide"; exit 1; }
[[ "$(lire_etiquette "$source_env")" == "$version" ]] \
  || { erreur "overlays/$source_env : étiquette de l'image ≠ version de livraison.yaml (source incohérente)"; exit 1; }

if [[ "$(lire_digest "$cible")" == "$digest" && "$(lire_version "$cible")" == "$version" ]]; then
  echo "overlays/$cible livre déjà $version ($digest) : rien à promouvoir"
  exit 0
fi

# La signature MédiSphère du digest, sans journal de transparence public (M13). Le pipeline de MR
# (M19-E29) la revérifie : ici, on évite d'ouvrir une MR vouée à l'échec.
if ! cosign verify --key "$CLE" --insecure-ignore-tlog=true "$IMAGE@$digest" >/dev/null 2>&1; then
  erreur "$IMAGE@$digest n'est pas signée par la clé MédiSphère : promotion refusée"
  exit 1
fi

branche="promotion/$cible-$version"
if git ls-remote --exit-code --heads origin "$branche" >/dev/null 2>&1; then
  erreur "la branche $branche existe déjà sur origin : une MR de promotion est sans doute ouverte"
  exit 1
fi
git switch --quiet -c "$branche"
# En cas d'échec : on jette les modifications de la branche de promotion (la copie de travail était
# propre au départ, vérifié plus haut), on revient sur main et on supprime la branche locale.
annuler() {
  git reset --quiet --hard
  git switch --quiet main
  git branch --quiet -D "$branche" 2>/dev/null || true
}
trap 'erreur "échec : branche locale $branche supprimée"; annuler' ERR

# yq plutôt que « kustomize edit set image », qui réécrit tout le fichier (ordre, commentaires) :
# la MR ne montre ainsi que les deux lignes qui changent.
IMG="$IMAGE" V="$version" D="$digest" yq -i \
  '.images = (((.images // []) | map(select(.name != strenv(IMG)))) + [{"name": strenv(IMG), "newTag": strenv(V), "digest": strenv(D)}])' \
  "overlays/$cible/kustomization.yaml"
V="$version" yq -i '.data.version = strenv(V)' "overlays/$cible/livraison.yaml"

# Contrôle du rendu : l'API et le Job de migration portent le digest promu, la version suit.
rendu="$(kubectl kustomize "overlays/$cible")"
if [[ -x outils/verifier-livraison.sh ]]; then
  outils/verifier-livraison.sh "overlays/$cible" >/dev/null || { erreur "garde-fou verifier-livraison en échec sur overlays/$cible"; false; }
fi
images="$(yq -r 'select(.kind == "Deployment" or .kind == "Job") | .spec.template.spec.containers[].image' <<<"$rendu" \
  | grep -F "$IMAGE" | sort -u)"
[[ "$images" == "$IMAGE:$version@$digest" ]] || { erreur "rendu de overlays/$cible : images « $images » au lieu de $version@$digest"; false; }
grep -q "value: $version\$" <<<"$rendu" || { erreur "rendu de overlays/$cible : MEDIAGENDA_VERSION ≠ $version"; false; }

titre="promotion($cible): mediagenda-api $version depuis $source_env"
git add "overlays/$cible/kustomization.yaml" "overlays/$cible/livraison.yaml"
git commit --quiet -m "$titre" -m "Digest : $digest
Source : overlays/$source_env (même artefact, signature MédiSphère vérifiée).
Retour arrière : git revert de la fusion de cette MR."
trap - ERR

if ((pousser == 0)); then
  echo "branche $branche prête (non poussée) : git show, puis git push -u origin $branche"
  exit 0
fi
git push --quiet -u origin "$branche" \
  -o merge_request.create \
  -o merge_request.target=main \
  -o merge_request.remove_source_branch \
  -o "merge_request.title=$titre"
git switch --quiet main
echo "MR ouverte : $titre ($branche). Fusion par un Maintainer, puis :"
if [[ "$cible" == prod ]]; then
  echo "  argocd app diff mediagenda-prod ; argocd app sync mediagenda-prod"
else
  echo "  argocd app get mediagenda-$cible --refresh   (synchronisation automatique)"
fi
