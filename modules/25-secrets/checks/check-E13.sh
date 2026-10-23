# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E13.sh — M25-E13 « Migrer les Secrets hors Git vers des ExternalSecret ».
# Vérifie : Application secrets-plateforme saine, un ExternalSecret Ready pour chaque Secret de
# plateforme migré (liste de référence ci-dessous, adaptable par WB_M25_E13_SECRETS), SecretStore
# et ExternalSecret des espaces applicatifs, rôles eso-<espace> cloisonnés, secrets-k8s.conf réduit à
# l'amorçage, preuves sans valeur, Applications de plateforme et de recette saines.
# Lecture seule : bao_api, kube (wb-checks : jamais les Secrets), gitlab_api, ~/m25/e13/.
#
# WB_M25_E13_SECRETS (lab.env, facultatif) : liste « espace/nom » des Secrets de plateforme à
# vérifier, séparés par des espaces, si ton inventaire diffère de la liste de référence.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E13 — Migrer les Secrets hors Git vers des ExternalSecret"
require_cmd jq kubectl curl

_m25o_e13_reference="argocd/repo-creds-plateforme argocd/repo-creds-mediagenda argocd/repo-creds-medidoc
argocd/repo-creds-formation argocd/depot-harbor-charts argocd/argocd-webhook-gitlab argocd/argocd-sauvegardes-s3
argocd/argocd-oidc supervision/grafana-admin supervision/grafana-oidc supervision/thanos-objstore
journaux/loki-objstore traces/tempo-objstore traces/pyroscope-objstore traces/otlp-jetons
gitlab-runner/gitlab-runner gitlab-runner/ci-cache-s3 gitlab-runner/gitlab-runner-protege-jeton
gitlab-agent/gitlab-agent-jeton oauth2-proxy/oauth2-proxy-oidc"
read -r -a _m25o_e13_liste <<<"$(tr '\n' ' ' <<<"${WB_M25_E13_SECRETS:-$_m25o_e13_reference}")"

check_cmd "Application secrets-plateforme : Synced et Healthy" _m25o_app_ok secrets-plateforme

_m25o_e13_es="$(_m25o_k get externalsecrets.external-secrets.io -A -o json)"
_m25o_e13_manquants=""
for _m25o_e13_s in "${_m25o_e13_liste[@]}"; do
  if ! _m25o_json "$_m25o_e13_es" --arg ns "${_m25o_e13_s%%/*}" --arg n "${_m25o_e13_s#*/}" '
       any(.items[]; .metadata.namespace == $ns and (.spec.target.name // .metadata.name) == $n
           and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) > 0)'; then
    _m25o_e13_manquants+=" ${_m25o_e13_s}"
  fi
done
check_cmd "chaque Secret de plateforme de la liste a un ExternalSecret Ready (manquants :${_m25o_e13_manquants:- aucun})" \
  test -z "$_m25o_e13_manquants"
check_cmd "les ExternalSecret de plateforme utilisent le ClusterSecretStore openbao" _m25o_json "$_m25o_e13_es" '
  [.items[] | select(.metadata.namespace | test("^(argocd|supervision|journaux|traces|gitlab-runner|gitlab-agent|oauth2-proxy)$"))
   | .spec.secretStoreRef | select(.kind == "ClusterSecretStore" and .name == "openbao")] | length > 0'
check_cmd "argocd : les Secrets de dépôt gardent l'étiquette argocd.argoproj.io/secret-type (modèle de l'ExternalSecret)" \
  _m25o_json "$_m25o_e13_es" '
  [.items[] | select(.metadata.namespace == "argocd" and ((.spec.target.name // .metadata.name) | startswith("repo-creds-")))]
  | length > 0 and all(.spec.target.template.metadata.labels["argocd.argoproj.io/secret-type"] == "repo-creds"
                       and .spec.target.template.mergePolicy == "Merge")'

# --- Espaces applicatifs ---------------------------------------------------------------------------
for _m25o_e13_ns in mediagenda-dev mediagenda-recette mediagenda-prod medidoc-dev medidoc-recette; do
  check_cmd "$_m25o_e13_ns : SecretStore openbao Ready" _m25o_objet_pret secretstores.external-secrets.io openbao "$_m25o_e13_ns"
  check_cmd "$_m25o_e13_ns : ExternalSecret harbor-pull Ready, de type dockerconfigjson" _m25o_json "$_m25o_e13_es" \
    --arg ns "$_m25o_e13_ns" '
    any(.items[]; .metadata.namespace == $ns and (.spec.target.name // .metadata.name) == "harbor-pull"
        and .spec.secretStoreRef.kind == "SecretStore" and .spec.target.template.type == "kubernetes.io/dockerconfigjson"
        and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) > 0)'
  check_cmd "rôle eso-$_m25o_e13_ns : compte eso de $_m25o_e13_ns seulement, audience exigée" \
    _m25o_json "$(_m25o_bao "auth/k8s-par1/role/eso-$_m25o_e13_ns")" --arg e "$_m25o_e13_ns" '
    .data.audience == "openbao.medisphere.internal" and .data.bound_service_account_names == ["eso"]
    and .data.bound_service_account_namespaces == [$e]'
done
check_cmd "medidoc-recette : ExternalSecret medidoc-s3 Ready" _m25o_es_pret medidoc-recette medidoc-s3
check_cmd "politique eso-mediagenda-recette : rien hors de mediagenda/recette (ni medidoc, ni plateforme)" \
  _m25o_politique_exclut eso-mediagenda-recette 'medidoc|plateforme|"kv/data/\*"|mediagenda/(dev|prod)'
check_cmd "politique eso-plateforme : chemins de composants listés, sans ansible-vault ni harbor/robot-ci" \
  _m25o_politique_exclut eso-plateforme 'ansible-vault|robot-ci|"kv/data/plateforme/\*"|"kv/data/\*"'

# --- Dépôt plateforme/k8s : script réduit à l'amorçage ----------------------------------------------
_m25o_e13_conf() {
  local c n
  c="$(_m25o_contenu "$_M25O_P_K8S" outils/secrets-k8s.conf)"
  [[ -n "$c" ]] || return 1
  # Tolérés : l'amorçage (racine MédiSphère publique) et la clé Cosign, hors périmètre (retirée en M25-E20,
  # vérifié par check-E20).
  n="$(grep -Ev '^[[:space:]]*(#|$)' <<<"$c" | grep -Ev '^[[:space:]]*cosign-ci[[:space:]]' \
    | grep -Evc 'gitlab-runner-certs|medisphere-root-ca')" || true
  [[ "$n" -eq 0 ]]
}
check_cmd "secrets-k8s.conf (main) : plus aucune ligne active hors amorçage (racine MédiSphère ; clé Cosign jusqu'à E20)" _m25o_e13_conf

# --- Santé après migration -------------------------------------------------------------------------
for _m25o_e13_app in kube-prometheus-stack loki tempo mediagenda-recette medidoc-recette; do
  check_cmd "Application $_m25o_e13_app : Synced et Healthy après la migration" _m25o_app_ok "$_m25o_e13_app"
done

# --- Preuves ---------------------------------------------------------------------------------------
check_cmd "m25/e13/inventaire.md : chemins KV et dates de migration, sans valeur" _m25o_local e13/inventaire.md 'kv/plateforme/'
check_cmd "m25/e13/comparaison.md : comparaison par empreinte ou verifier, sans valeur" \
  _m25o_local e13/comparaison.md 'empreinte|sha256|verifier|\[OK\]'
