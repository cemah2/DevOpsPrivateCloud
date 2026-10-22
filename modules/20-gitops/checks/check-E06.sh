# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E06.sh — M20-E06 : Le dépôt plateforme/gitops et l'application racine
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API d'Argo CD en GET (jeton
# ci-lecture), API GitLab en GET (jetons de déploiement : métadonnées seulement, jamais leur valeur).

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E06 — Le dépôt plateforme/gitops et l'application racine"
require_cmd jq kubectl curl

if ! _m20d_peut_lire_argo; then
  skip "Contrôles des Applications" "wb-checks ne lit pas encore les objets d'Argo CD : termine M20-E03"
  return 0
fi

# --- 1. Le dépôt plateforme/gitops ------------------------------------------------------------------
for _m20d_e06_f in README.md racine/racine.yaml racine/applications.yaml applications/labo.yaml; do
  check_cmd "plateforme/gitops (main) : $_m20d_e06_f" _m20d_fichier_main plateforme/gitops "$_m20d_e06_f"
done
check_cmd "plateforme/gitops : main protégée, poussée directe interdite" _m20d_json \
  "$(gitlab_api "projects/plateforme%2Fgitops/protected_branches/main" 2>/dev/null || true)" \
  '[.push_access_levels[]?.access_level] | length > 0 and all(. == 0)'

# --- 2. La racine et sa descendance -----------------------------------------------------------------
_m20d_e06_racine="$(_m20d_app racine)"
_m20d_e06_source() {
  _m20d_meme_depot "$(jq -r '.spec.source.repoURL // ""' <<<"$1")" plateforme/gitops &&
    _m20d_json "$1" '.spec.source.path == $p and .spec.source.targetRevision == "main"' --arg p "$2"
}
check_cmd "Application racine : source plateforme/gitops, main, dossier racine" _m20d_e06_source "$_m20d_e06_racine" racine
check_cmd "racine : Synced et Healthy" _m20d_json "$_m20d_e06_racine" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
check_cmd "racine : synchronisation automatique (prune, selfHeal)" _m20d_json "$_m20d_e06_racine" \
  '.spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true'
check_cmd "racine : AUCUN finaliseur de suppression en cascade" _m20d_json "$_m20d_e06_racine" \
  '(.metadata.finalizers // []) | index("resources-finalizer.argocd.argoproj.io") | not'
_m20d_e06_suivi() { [[ "$(_m20d_suivi "$1")" == "$2" ]]; }
check_cmd "racine se gère elle-même (annotation de suivi racine:…/racine)" \
  _m20d_e06_suivi "$_m20d_e06_racine" "racine:argoproj.io/Application:argocd/racine"
_m20d_e06_apps="$(_m20d_app applications)"
check_cmd "Application applications : source plateforme/gitops, dossier applications" _m20d_e06_source "$_m20d_e06_apps" applications
check_cmd "applications est gérée par la racine" \
  _m20d_e06_suivi "$_m20d_e06_apps" "racine:argoproj.io/Application:argocd/applications"
check_cmd "applications : Synced et Healthy" _m20d_json "$_m20d_e06_apps" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
_m20d_e06_labo="$(_m20d_app labo)"
check_cmd "labo est gérée depuis Git (suivie par applications, elle-même suivie par racine)" \
  _m20d_e06_suivi "$_m20d_e06_labo" "applications:argoproj.io/Application:argocd/labo"
check_cmd "labo : toujours Synced et Healthy après la reprise" _m20d_json "$_m20d_e06_labo" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'

# --- 3. Accès aux dépôts ---------------------------------------------------------------------------
check_cmd "argocd-tls-certs-cm : racine MédiSphère pour git01" _m20d_json \
  "$(_m20d_k -n "$_M20D_NS" get configmap argocd-tls-certs-cm -o json)" \
  '.data["git01.par1.medisphere.internal"] // "" | test("BEGIN CERTIFICATE")'
if [[ -r "$_M20D_JETON" ]]; then
  _m20d_e06_creds="$(_m20d_argocd_api repocreds || true)"
  for _m20d_e06_g in plateforme mediagenda medidoc formation; do
    check_cmd "Modèle d'identifiants (repo-creds) pour $_M20D_GITLAB/$_m20d_e06_g/" _m20d_json "$_m20d_e06_creds" \
      '[.items[]? | select((.url | rtrimstr("/")) == $u)] | length == 1' --arg u "$_M20D_GITLAB/$_m20d_e06_g"
  done
  check_cmd "Plus de dépôt enregistré à la main avec ses propres identifiants (E04)" _m20d_json \
    "$(_m20d_argocd_api repositories || echo '{"items":[]}')" \
    '[.items[]? | select((.username // "") != "" and (.inheritedCreds // false) == false)] | length == 0'
else
  skip "Modèles d'identifiants des dépôts (API d'Argo CD)" "jeton $_M20D_JETON absent (M20-E03)"
fi
for _m20d_e06_g in plateforme mediagenda medidoc formation; do
  check_cmd "Groupe $_m20d_e06_g : jeton de déploiement argocd-lecture actif, read_repository seul, avec expiration" \
    _m20d_json "$(_m20d_jetons_deploiement "$_m20d_e06_g")" \
    '[.[] | select(.name == "argocd-lecture" and (.revoked | not) and (.expired | not))]
     | length >= 1 and all(.scopes == ["read_repository"] and .expires_at != null)'
done
