# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S02.sh — F1-S02 « Chasse à la dérive ». Lecture seule : Argo CD par le compte wb-checks,
# pipelines et journaux de travaux GitLab (jeton read_api des checks), documentation sur main.
# Fraîcheur exigée des contrôles : WB_F1_JOURS jours (7 par défaut).

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S02 — Chasse à la dérive"
require_cmd curl jq kubectl

# --- Argo CD : tout ce qu'il gère est conforme au dépôt ----------------------------------------
if _f1p_api_repond; then
  _f1_s02_apps="$(kube get applications.argoproj.io -A -o json 2>/dev/null)" || _f1_s02_apps=""
  if [[ -n "$_f1_s02_apps" ]]; then
    _f1_s02_ko="$(jq -r '[.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
                    | "\(.metadata.namespace)/\(.metadata.name)"] | join(" ")' <<<"$_f1_s02_apps")"
    check_cmd "Argo CD gère des Applications (au moins une lue)" \
      jq -e '.items | length > 0' <<<"$_f1_s02_apps"
    check_cmd "toutes les Applications Argo CD sont Synced et Healthy${_f1_s02_ko:+ (écart : $_f1_s02_ko)}" test -z "$_f1_s02_ko"
  else
    check_cmd "lecture des Applications Argo CD par le compte des checks" false
  fi
else
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
fi

# --- Contrôles de dérive reproductibles (pipelines) ---------------------------------------------
check_cmd "plateforme/infra : dernière détection de dérive planifiée réussie sans écart, il y a moins de $_f1p_jours j" \
  _f1p_derive_ok plateforme/infra '^derive:'
_f1_s02_jobs_infra="$(_f1p_dernier_job plateforme/infra '^derive:' schedule 2>/dev/null)" || _f1_s02_jobs_infra="[]"
check_cmd "plateforme/infra : la détection de dérive couvre le socle et l'état du cluster (envs/k8s)" \
  jq -e '(map(.name) | any(test("socle"))) and (map(.name) | any(test("k8s")))' <<<"$_f1_s02_jobs_infra"
check_cmd "plateforme/ansible : dernière détection de dérive planifiée (--check --diff) réussie, il y a moins de $_f1p_jours j" \
  _f1p_derive_ok plateforme/ansible '^derive'
check_cmd "plateforme/identite : dernier plan OpenTofu du royaume réussi, récent et vide (No changes)" \
  _f1p_plan_vide plateforme/identite '^tofu:plan$'
check_cmd "plateforme/secrets : dernier plan OpenTofu du coffre réussi, récent et vide (No changes)" \
  _f1p_plan_vide plateforme/secrets '^tofu:plan$'

# --- Compte rendu ---------------------------------------------------------------------------------
_f1_s02_cr="$(_f1p_doc_chemin '^derive-[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$')" || _f1_s02_cr=""
check_cmd "compte rendu docs/day0/derive-<AAAA-MM-JJ>.md publié sur main" test -n "$_f1_s02_cr"
if [[ -n "$_f1_s02_cr" ]]; then
  _f1_s02_txt="$(_f1p_fichier "$_f1p_projet_doc" "$_f1_s02_cr" 2>/dev/null)" || _f1_s02_txt=""
  check_cmd "le compte rendu couvre chaque couche (OpenTofu, Ansible, Helmfile, Argo CD, Keycloak, OpenBao, Harbor, NetBox)" \
    _f1p_contient "$_f1_s02_txt" 'OpenTofu|tofu' 'Ansible' 'Helmfile' 'Argo ?CD' 'Keycloak|identite' 'OpenBao|secrets' 'Harbor|registre' 'NetBox'
  check_cmd "chaque écart porte une décision (corrigé ou codifié) et une référence de MR" \
    _f1p_contient "$_f1_s02_txt" 'corrig' 'codifi' '![0-9]+|merge_requests/[0-9]+|MR ?[0-9]+'
else
  skip "contenu du compte rendu de dérive" "document absent"
fi
