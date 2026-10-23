#!/usr/bin/env bash
# verifier-kit-forensique.sh — contrôle que le kit de réponse à incident est PRÊT (F6-S10, ECA-3605).
#
# plateforme/outils — bin/verifier-kit-forensique.sh. Lancé par un pipeline planifié et avant un
# exercice. « Prêt » est une propriété vérifiable, pas une déclaration : ce script la prouve.
# Il n'EFFACE jamais rien du compartiment de preuves (il éprouve que la suppression ÉCHOUE).
#
# Contrôles :
#   1. image d'outils forensiques présente dans Harbor et signée (Cosign vérifie) ;
#   2. identité de dépôt des preuves : écrit un fichier d'essai ET échoue à le supprimer (verrouillage) ;
#   3. modèles présents (chronologie, manifeste) ;
#   4. comptes de bris de glace lisibles (réponse en LECTURE, jamais d'écriture).
# Sortie 0 si tout est prêt, 1 sinon.
#
# Variables (défauts) :
#   WB_F6_OUTILS_IMAGE   image d'outils (registry…/dockerhub/nicolaka/netshoot:v0.16)
#   WB_F6_RGW_URL        https://rgw.par1.medisphere.internal
#   WB_F6_PREUVES_BUCKET preuves-conformite
#   WB_F6_PREUVES_DEPOT_ENV  identité de dépôt (~/.config/workbook/s3-preuves-conformite-depot.env)
#   WB_F6_MODELES_DIR    dossier des modèles (docs/securite/incidents/modeles)
#   WB_F6_BRIS_KUBECONFIG  admin.conf de bris de glace (lecture seule)
set -euo pipefail

IMAGE="${WB_F6_OUTILS_IMAGE:-registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16}"
RGW="${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}"
BUCKET="${WB_F6_PREUVES_BUCKET:-preuves-conformite}"
DEPOT_ENV="${WB_F6_PREUVES_DEPOT_ENV:-$HOME/.config/workbook/s3-preuves-conformite-depot.env}"
MODELES="${WB_F6_MODELES_DIR:-docs/securite/incidents/modeles}"
BRIS_KCFG="${WB_F6_BRIS_KUBECONFIG:-$HOME/.config/workbook/bris-de-glace/admin.conf}"

for c in cosign aws jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done

echec=0
ok()  { echo "OK : $1"; }
ko()  { echo "KO : $1"; echec=1; }

# 1. Image d'outils signée.
if cosign verify "$IMAGE" --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*' >/dev/null 2>&1 \
   || cosign verify --key "${WB_F6_COSIGN_CLE:-k8s://cosign-system/cosign-pub}" "$IMAGE" >/dev/null 2>&1; then
  ok "image d'outils signée : $IMAGE"
else
  ko "image d'outils absente ou signature invalide : $IMAGE"
fi

# 2. Dépôt des preuves : écriture OK, suppression refusée (verrouillage).
if [[ ! -r "$DEPOT_ENV" ]]; then
  ko "identité de dépôt des preuves illisible : $DEPOT_ENV"
else
  s3() {
    (
      set -a
      # shellcheck disable=SC1090
      source "$DEPOT_ENV"
      set +a
      aws --endpoint-url "$RGW" "$@"
    )
  }
  cle="verif-kit/$(date -u +%FT%TZ).txt"
  if printf 'verif-kit %s\n' "$(date -u +%FT%TZ)" | s3 s3 cp - "s3://$BUCKET/$cle" >/dev/null 2>&1; then
    ok "dépôt des preuves : écriture possible ($cle)"
    if s3 s3 rm "s3://$BUCKET/$cle" >/dev/null 2>&1; then
      ko "le verrouillage ne protège pas : un objet a pu être SUPPRIMÉ ($cle)"
    else
      ok "dépôt des preuves : suppression refusée (verrouillage d'objets actif)"
    fi
  else
    ko "dépôt des preuves : écriture impossible (identité ou compartiment $BUCKET)"
  fi
fi

# 3. Modèles présents.
for m in chronologie manifeste; do
  if ls "$MODELES"/*"$m"* >/dev/null 2>&1; then
    ok "modèle présent : $m"
  else
    ko "modèle manquant dans $MODELES : $m"
  fi
done

# 4. Comptes de bris de glace lisibles (lecture seule).
if [[ -r "$BRIS_KCFG" ]] && kubectl --kubeconfig "$BRIS_KCFG" --request-timeout=10s get nodes >/dev/null 2>&1; then
  ok "bris de glace Kubernetes (admin.conf) répond en lecture"
else
  ko "bris de glace Kubernetes (admin.conf) illisible ou injoignable : $BRIS_KCFG"
fi

if (( echec )); then
  echo "== Kit forensique NON prêt =="
  exit 1
fi
echo "== Kit forensique prêt =="
