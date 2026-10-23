# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M27-E07 : Valkey 9 (montée de version, ACL, TLS, éviction)
# À lancer depuis adm01. Lecture seule : StatefulSet, ConfigMap de configuration, Certificate et
# ExternalSecrets de Valkey dans mediagenda-recette et mediagenda-prod (jamais les Secrets : le fichier
# ACL n'est pas lu), variable de l'API, métriques de l'exportateur (Prometheus), documentation.

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E07 — Valkey ${_M27O_VALKEY} : montée de version, ACL, TLS et éviction"
require_cmd jq kubectl curl awk

for _m27o_e07_env in "$_M27D_ENV_RECETTE" "$_M27D_ENV_PROD"; do
  _m27o_e07_ns="mediagenda-${_m27o_e07_env}"
  _m27o_e07_sts="$(_m27d_k get statefulset valkey -n "$_m27o_e07_ns" -o json)"
  if [[ -z "$_m27o_e07_sts" ]]; then
    _ko "$_m27o_e07_env : StatefulSet valkey introuvable dans $_m27o_e07_ns"
    continue
  fi
  check_cmd "$_m27o_e07_env : StatefulSet valkey géré par l'Application mediagenda-${_m27o_e07_env}" \
    _m27o_geree_par "$_m27o_e07_sts" "mediagenda-${_m27o_e07_env}"
  check_cmd "$_m27o_e07_env : conteneur Valkey ${_M27O_VALKEY} du cache Harbor, pod prêt" _m27d_json "$_m27o_e07_sts" \
    '(.status.readyReplicas // 0) >= 1 and any(.spec.template.spec.containers[];
       .image | test("^registry\\.par1\\.medisphere\\.internal/dockerhub/valkey/valkey:" + $v + "\\.[0-9]+"))' --arg v "$_M27O_VALKEY_RE"
  check_cmd "$_m27o_e07_env : conteneur annexe « exportateur » (redis_exporter)" _m27d_json "$_m27o_e07_sts" \
    'any(.spec.template.spec.containers[]; .name == "exportateur" and (.image | test("redis_exporter")))'
  if [[ "$_m27o_e07_env" == "$_M27D_ENV_PROD" ]]; then
    check_cmd "$_m27o_e07_env : toutes les images du pod par empreinte" _m27d_json "$_m27o_e07_sts" \
      'all(.spec.template.spec.containers[]; .image | test("@sha256:[0-9a-f]{64}$"))'
  fi
  # Configuration : la ConfigMap montée sur /etc/valkey/valkey.conf (nom suffixé par Kustomize).
  _m27o_e07_cm="$(jq -r '[.spec.template.spec.containers[] | select(.name == "valkey") | .volumeMounts[]?
      | select(.mountPath | startswith("/etc/valkey/valkey.conf") or . == "/etc/valkey") | .name] as $v
      | [.spec.template.spec.volumes[]? | select(.name as $n | $v | index($n)) | .configMap.name // empty] | first // empty' \
      <<<"$_m27o_e07_sts" 2>/dev/null || true)"
  _m27o_e07_conf="$( [[ -n "$_m27o_e07_cm" ]] && _m27d_k get configmap "$_m27o_e07_cm" -n "$_m27o_e07_ns" -o json |
      jq -r '[.data[]] | join("\n")' 2>/dev/null || true)"
  check_cmd "$_m27o_e07_env : configuration — port en clair fermé (port 0), TLS sur 6379" bash -c \
    'grep -Eq "^port[[:space:]]+0[[:space:]]*$" <<<"$1" && grep -Eq "^tls-port[[:space:]]+6379" <<<"$1"' _ "$_m27o_e07_conf"
  check_cmd "$_m27o_e07_env : configuration — fichier ACL (aclfile)" bash -c 'grep -Eq "^aclfile[[:space:]]+/" <<<"$1"' _ "$_m27o_e07_conf"
  check_cmd "$_m27o_e07_env : configuration — maxmemory bornée et allkeys-lru" bash -c \
    'grep -Eq "^maxmemory[[:space:]]+[1-9]" <<<"$1" && grep -Eq "^maxmemory-policy[[:space:]]+allkeys-lru" <<<"$1"' _ "$_m27o_e07_conf"
  check_cmd "$_m27o_e07_env : certificat valkey-tls prêt, émis par openbao-services" _m27d_json \
    "$(_m27d_k get certificates.cert-manager.io valkey-tls -n "$_m27o_e07_ns" -o json)" \
    '.spec.issuerRef.name == "openbao-services" and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
  check_cmd "$_m27o_e07_env : comptes de Valkey lus dans OpenBao (ExternalSecrets valkey-comptes, mediagenda-valkey prêts)" _m27d_json \
    "$(_m27d_k get externalsecrets.external-secrets.io -n "$_m27o_e07_ns" -o json)" \
    '[.items[] | select(.metadata.name == "valkey-comptes" or .metadata.name == "mediagenda-valkey")
       | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 2'
  check_cmd "$_m27o_e07_env : l'API lit MEDIAGENDA_VALKEY_URL dans le Secret mediagenda-valkey" _m27d_json \
    "$(_m27d_k get deployment mediagenda -n "$_m27o_e07_ns" -o json)" \
    'any(.spec.template.spec.containers[].env[]?; .name == "MEDIAGENDA_VALKEY_URL" and .valueFrom.secretKeyRef.name == "mediagenda-valkey")'
  _m27o_e07_up="$(_m27d_prom "max(redis_up{namespace=\"${_m27o_e07_ns}\"})")"
  check_cmd "$_m27o_e07_env : l'exportateur joint Valkey en TLS (redis_up = ${_m27o_e07_up})" _m27d_positif "$_m27o_e07_up"
  _m27o_e07_info="$(_m27d_prom "count(redis_instance_info{namespace=\"${_m27o_e07_ns}\",valkey_version=~\"${_M27O_VALKEY_PROM}\\\\..*\",maxmemory_policy=\"allkeys-lru\"})")"
  check_cmd "$_m27o_e07_env : Prometheus voit Valkey ${_M27O_VALKEY} en allkeys-lru (redis_instance_info)" _m27d_positif "$_m27o_e07_info"
done

check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/valkey.md (configuration, comptes, sauvegarde)" \
  _m27d_doc_contient "${_M27D_DOC}/valkey.md" 'allkeys-lru'
check_cmd "valkey.md : réponse sur Sentinel" _m27d_doc_contient "${_M27D_DOC}/valkey.md" 'sentinel'
