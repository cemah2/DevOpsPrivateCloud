# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E19.sh — M26-E19 : règles Falco de MédiSphère et acheminement des alertes
# À lancer depuis adm01. Lecture seule : DaemonSet, ConfigMap des règles et Application (compte
# wb-checks), Loki (locataire audit), Mailpit, dépôts et jobs (GitLab).
# Ce qui est vérifié : Falco en service partout, nos six règles chargées (et aucune désactivée),
# l'Application qui les lit dans plateforme/politiques, la validation en CI, des événements de nos
# règles dans Loki, une alerte arrivée par courriel, le runbook.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E19 — Falco : règles de MédiSphère et acheminement des alertes"
require_cmd jq kubectl curl

check_cmd "DaemonSet falco prêt sur les $_M26C_NOEUDS nœuds" _m26c_ds_pret falco falco

_m26c_e19_regles="$(_m26c_k get configmap -n falco falco-rules -o json | jq -r '[.data // {} | .[]] | join("\n")' 2>/dev/null || true)"
check_output "ConfigMap falco-rules : six règles « MédiSphère — » chargées" '^6$' \
  bash -c 'grep -cE "^[[:space:]]*- rule: MédiSphère — " <<<"$1" || true' _ "$_m26c_e19_regles"
_m26c_e19_aucune_desactivee() {
  [[ -n "$_m26c_e19_regles" ]] && ! grep -qE '^[[:space:]]*(enabled:[[:space:]]*false|override:)' <<<"$_m26c_e19_regles"
}
check_cmd "aucune règle désactivée ni remplacée dans les règles MédiSphère (exceptions par listes et macros)" \
  _m26c_e19_aucune_desactivee

check_cmd "Application falco : lit plateforme/politiques et son fichier falco/regles-medisphere.yaml" \
  _m26c_json "$(_m26c_k get applications.argoproj.io -n argocd falco -o json)" '
    any(.spec.sources[]?; (.repoURL | test("plateforme/politiques")) and .ref == "politiques")
    and any(.spec.sources[]?.helm.valueFiles[]?; test("^\\$politiques/falco/regles-medisphere\\.yaml$"))
    and .status.sync.status == "Synced"'

check_cmd "plateforme/politiques : un job falco:valider a réussi sur main" \
  _m26c_job_reussi "$_M26C_P_POLITIQUES" "falco:valider"

# Événements : présents = OK ; Loki répond mais rien dans la fenêtre (check relancé longtemps après
# l'exercice, lab au repos) = IGNORÉ avec la marche à suivre pour en régénérer, jamais réussi ;
# Loki illisible = KO. Les règles elles-mêmes sont contrôlées plus haut (ConfigMap falco-rules).
_M26C_E19_REGEN="régénère : rejoue l'étape 6 d'E19 avec un pod d'essai de wb-essais (au moins le shell interactif : kubectl -n wb-essais exec -it <pod> -- sh), puis relance le check"
_m26c_e19_evenements() {
  local desc="$1" requete="$2" duree="$3" fenetre="$4"
  if _m26c_loki_present "$requete" audit "$duree"; then
    _ok "$desc"
  elif _m26c_loki_absent "$requete" audit "$duree"; then
    skip "$desc" "aucun événement dans $fenetre ; $_M26C_E19_REGEN"
  else
    _ko "$desc (Loki, locataire audit, ne répond pas)"
  fi
}
_m26c_e19_evenements "Loki (audit) : événements de règles MédiSphère dans les 30 derniers jours" \
  '{service="falco", rule=~"MédiSphère.*"}' 720h "les 30 derniers jours"
_m26c_e19_evenements "Loki (audit) : Falco envoie toujours (au moins un événement dans les dernières 24 h)" \
  '{service="falco"}' 24h "les dernières 24 h"

check_cmd "Mailpit : au moins une alerte AlerteFalco reçue" _m26c_json \
  "$(mailpit_api "search?query=AlerteFalco" 2>/dev/null || true)" '(.messages_count // 0) >= 1'

check_cmd "plateforme/medisphere : $_M26C_DOC/runbooks/RB-260-alerte-falco.md sur main" \
  _m26c_fichier "$_M26C_P_DOC" "$_M26C_DOC/runbooks/RB-260-alerte-falco.md"
