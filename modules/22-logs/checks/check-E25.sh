# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c entre apostrophes
# check-E25.sh — M22-E25 « Mini-projet : les journaux de MédiSphère v1 » : contrôle global de la livraison
# journaux-v1 (depuis adm01). Rejoue les vérifications clés des paliers 1 à 3 (Loki, Alloy dans le
# cluster et sur les VMs, journaux structurés, audit, alertes, masquage, rétention, cardinalité, accès),
# puis vérifie ce qui n'appartient qu'à la livraison : Applications saines, essais retirés, aucune panne
# ouverte, documentation complète, pipeline vert, étiquette journaux-v1. Lecture seule. 3 à 5 minutes.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

_m22_e25_dir="$(dirname "${BASH_SOURCE[0]}")"

title "M22-E25 — Journaux de MédiSphère v1 : contrôle global"
require_cmd kubectl jq curl

# --- 1. Vérifications clés des exercices (chacune affiche son propre titre) ----------------------------
# _M22_MINI_PROJET : les checks rejoués adaptent ce qui n'a de sens que pendant l'exercice (E07 : trace
# de l'enquête de plus de 24 h ; E09 : témoin retiré, motifs cherchés sur 24 h).
_M22_MINI_PROJET=1
for _m22_e25_ex in 02 03 05 06 07 08 09 13 14 16; do
  _m22_e25_f="$_m22_e25_dir/check-E$_m22_e25_ex.sh"
  if [[ -f "$_m22_e25_f" ]]; then
    # shellcheck disable=SC1090  # vérifications des exercices, chargées dynamiquement
    source "$_m22_e25_f"
  else
    skip "vérification de M22-E$_m22_e25_ex" "script absent de ce dépôt"
  fi
done

# --- 2. Livraison ------------------------------------------------------------------------------------
title "M22-E25 — Livraison journaux-v1"
if _m22x_api_repond; then
  for _m22_e25_app in loki alloy; do
    check_cmd "Application Argo CD $_m22_e25_app : Synced et Healthy" _m22x_kq \
      '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$_m22_e25_app"
  done
  for _m22_e25_ns in journaux-essai opensearch-essai; do
    check_cmd "essai retiré : espace $_m22_e25_ns absent" bash -c '! "$@" >/dev/null 2>&1' _ kube get namespace "$_m22_e25_ns"
  done
  check_cmd "aucun DaemonSet Fluent Bit ni pod OpenSearch restant" _m22x_kq \
    '[.items[] | select(.metadata.name | test("fluent-bit|opensearch"))] | length == 0' daemonsets,statefulsets -A
  check_cmd "aucune ClusterRole de Fluent Bit restante (essais E10 et E15)" _m22x_kq \
    '[.items[] | select(.metadata.name | test("fluent-bit"))] | length == 0' clusterroles
  check_cmd "aucune Application d'essai (Fluent Bit, OpenSearch) dans Argo CD" _m22x_kq \
    '[.items[].metadata.name | select(test("essai|fluent-bit|opensearch"))] | length == 0' -n argocd applications.argoproj.io
  check_cmd "pas de pod témoin de panne journal-temoin restant" bash -c '! "$@" >/dev/null 2>&1' _ kube -n wb-pannes get deployment journal-temoin
else
  skip "Applications et essais" "l'API ne répond pas au compte des checks"
fi
check_cmd "aucune panne M22 encore marquée active (lab/bin/break)" _m22x_aucune_panne_active
_m22_e25_miroir="$(_m22p_fichier_main plateforme/charts-miroir charts.yaml 2>/dev/null || true)"
if [[ -n "$_m22_e25_miroir" ]]; then
  check_cmd "charts-miroir : plus de chart d'essai (fluent-bit, opensearch)" bash -c '! grep -Eq "nom: *(fluent-bit|opensearch)\b" <<<"$1"' _ "$_m22_e25_miroir"
else
  skip "charts d'essai retirés du miroir" "charts.yaml illisible sur main de plateforme/charts-miroir"
fi
_m22_e25_alerte_alloy() {
  prom_api rules 2>/dev/null |
    jq -e '[.data.groups[].rules[] | select(.type == "alerting")
            | select((.query | test("daemonset=\"alloy\"")) or (.name | test("^Alloy")))] | length >= 1' >/dev/null 2>&1
}
check_cmd "alerte « Alloy absent d'un nœud » chargée dans Prometheus (règle sur le DaemonSet alloy)" _m22_e25_alerte_alloy

for _m22_e25_t in plateforme mediagenda medidoc audit; do
  check_cmd "locataire $_m22_e25_t : rétention appliquée (non nulle)" bash -c '[[ "$1" -gt 0 ]]' _ "$(_m22p_heures "$(_m22p_limite "$_m22_e25_t" retention_period)")"
done

# --- 3. Documentation et livraison ---------------------------------------------------------------------
check_cmd "ADR-0220 publié (main)" _m22p_doc docs/observabilite/journaux ADR-0220 'Loki' 'Alloy' 'Promtail'
check_cmd "politique-journaux.md complète (durées, effacement, accès, sauvegarde)" \
  _m22p_doc docs/observabilite/journaux politique-journaux 'effacement' '^#+ .*Acc[eè]s' '^#+ .*Sauvegarde'
for _m22_e25_rb in RB-220 RB-221 RB-222 RB-223 RB-224; do
  check_cmd "runbook $_m22_e25_rb publié (main)" _m22p_doc docs/observabilite/journaux "$_m22_e25_rb" '.'
done
check_cmd "comparatifs publiés (collecteurs, OpenSearch)" bash -c \
  '[[ -n "$1" && -n "$2" ]]' _ \
  "$(_m22p_arbre plateforme/medisphere docs/observabilite/journaux | grep -E '/comparatif-collecteurs' | head -n 1)" \
  "$(_m22p_arbre plateforme/medisphere docs/observabilite/journaux | grep -E '/comparatif-opensearch' | head -n 1)"
check_cmd "matrice des flux : Loki 10.10.41.62:3100 décrit" \
  _m22p_fichier_contient plateforme/medisphere docs/socle/matrice-flux.md '10\.10\.41\.62' '3100'
_m22_e25_pipeline() {
  gitlab_api "projects/plateforme%2Fobservabilite/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "plateforme/observabilite : dernier pipeline de main réussi" _m22_e25_pipeline
_m22_e25_etiquette() {
  gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/journaux-v1' 2>/dev/null | jq -e '.name == "journaux-v1"' >/dev/null 2>&1
}
check_cmd "étiquette journaux-v1 posée sur plateforme/medisphere" _m22_e25_etiquette
