# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E25.sh — M28-E25 « Mini-projet : la plateforme développeurs de MédiSphère v1 » : contrôle global
# de la livraison plateforme-dev-v1 (depuis adm01). Rejoue les vérifications clés des exercices E02 à
# E07, E10, E13 à E16 et E24, puis vérifie la livraison : Applications saines, essais retirés, aucune
# panne ouverte, service fictif du chemin balisé retiré, catalogue, documentation, étiquette.
# Lecture seule. 3 à 5 minutes.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

_m28_e25_dir="$(dirname "${BASH_SOURCE[0]}")"

title "M28-E25 — Plateforme développeurs de MédiSphère v1 : contrôle global"
require_cmd kubectl jq curl

# --- 1. Vérifications clés des exercices (chacune affiche son propre titre) ----------------------------
for _m28_e25_ex in 02 03 04 05 06 07 10 13 14 15 16 24; do
  _m28_e25_f="$_m28_e25_dir/check-E$_m28_e25_ex.sh"
  if [[ -f "$_m28_e25_f" ]]; then
    # shellcheck disable=SC1090  # vérifications des exercices, chargées dynamiquement
    source "$_m28_e25_f"
  else
    skip "vérification de M28-E$_m28_e25_ex" "script absent de ce dépôt"
  fi
done

# --- 2. Livraison ------------------------------------------------------------------------------------
title "M28-E25 — Livraison plateforme-dev-v1"
_m28_e25_absent() { ! kube get "$@" >/dev/null 2>&1; }
if _m28p_api_repond; then
  for _m28_e25_app in keda vpa capsule locataires portail politiques; do
    check_cmd "Application Argo CD $_m28_e25_app : Synced et Healthy" _m28p_kq \
      '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$_m28_e25_app"
  done
  for _m28_e25_ns in medidoc-vc-essai medidoc-essai-isolation medidoc-chemin-balise-dev; do
    check_cmd "essai retiré : espace $_m28_e25_ns absent" _m28_e25_absent namespace "$_m28_e25_ns"
  done
  check_cmd "aucune Application Argo CD du service fictif medidoc-chemin-balise" _m28p_kq \
    '[.items[].metadata.name | select(test("chemin-balise"))] | length == 0' -n argocd applications.argoproj.io
  check_cmd "aucun VPA actif hors wb-essais" _m28p_kq \
    '[.items[] | select(.metadata.namespace != "wb-essais" and (.spec.updatePolicy.updateMode // "Auto") != "Off")] | length == 0' \
    verticalpodautoscalers.autoscaling.k8s.io -A
  for _m28_e25_t in mediagenda medidoc medinotif; do
    check_cmd "locataire $_m28_e25_t : prêt et géré par Argo CD (Application locataires)" _m28p_tenant "$_m28_e25_t" \
      'any(.status.conditions[]?; .type == "Ready" and .status == "True") and ((.metadata.annotations // {})["argocd.argoproj.io/tracking-id"] // "" | startswith("locataires:"))'
  done
else
  skip "Applications, essais, locataires" "l'API ne répond pas au compte des checks"
fi
check_cmd "aucune panne M28 encore marquée active (lab/bin/break)" _m28x_aucune_panne_active
_m28_e25_projet_absent() { gitlab_api "projects/medidoc%2Fmedidoc-chemin-balise" >/dev/null 2>&1 && return 1; return 0; }
check_cmd "projet GitLab du service fictif medidoc-chemin-balise supprimé" _m28_e25_projet_absent
check_cmd "catalogue : plus d'entité medidoc-chemin-balise" _m28x_catalogue \
  'catalog/entities?filter=metadata.name=medidoc-chemin-balise' 'length == 0'
check_cmd "catalogue : chaque Component a un propriétaire et sa documentation" _m28x_catalogue \
  'catalog/entities?filter=kind=component' \
  'length >= 1 and all(.[]; (.spec.owner // "") != "" and ((.metadata.annotations // {})["backstage.io/techdocs-ref"] // "") != "")'
check_cmd "modèle nouveau-service présent au catalogue" _m28x_catalogue \
  'catalog/entities/by-name/template/default/nouveau-service' '.kind == "Template"'

# --- 3. Documentation et étiquette ---------------------------------------------------------------------
for _m28_e25_doc in autoscaling capacite essais-isolation portail-exploitation sous-le-capot chemin-balise-essai etat-plateforme-dev-v1 ADR-0280; do
  check_cmd "document $_m28_e25_doc publié (main)" _m28p_doc "$_m28_e25_doc" '.'
done
for _m28_e25_rb in RB-280 RB-284 RB-285 RB-286 RB-287 RB-288 RB-289; do
  check_cmd "runbook $_m28_e25_rb publié (main)" _m28p_doc "$_m28_e25_rb" '.'
done
check_cmd "post-mortem INC-5523 publié (main)" _m28p_doc_k8s INC-5523 '.'
_m28_e25_etiquette() {
  gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/plateforme-dev-v1' 2>/dev/null | jq -e '.name == "plateforme-dev-v1"' >/dev/null 2>&1
}
check_cmd "étiquette plateforme-dev-v1 posée sur plateforme/medisphere" _m28_e25_etiquette
