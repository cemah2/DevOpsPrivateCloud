# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# check-S11.sh — F1-S11 « Remettre les données ».
# Lecture seule : objets CNPG (Cluster, Backup, ScheduledBackup ; wb-checks-services), statuts des
# ExternalSecrets, API de gestion de RabbitMQ (compte monitoring), Jobs d'export, Applications Argo CD,
# poignée de main TLS depuis vault01 vers les bases (openssl s_client : aucune connexion à la base,
# aucune lecture de donnée), document de comparaison sur main.
#
# Variable : WB_F1_SERVEURS_ANCIENS (« mediagenda-db mediagenda-db-prod portail-db ») : noms sous
# lesquels les anciennes bases archivaient ; aucune base reconstruite ne doit y écrire.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S11 — Remettre les données"
require_cmd kubectl jq curl ssh

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi

read -r -a _f1_s11_anciens <<<"${WB_F1_SERVEURS_ANCIENS:-mediagenda-db mediagenda-db-prod portail-db}"
_f1_s11_ne="$(_f1c_naissance_iso)"

# _f1_s11_archive_neuve JSON — le cluster archive (plugin, isWALArchiver) sous un serverName qui n'est
#   aucun des anciens (défaut du plugin = nom du cluster, qui est un ancien nom ici).
_f1_s11_archive_neuve() {
  local j="$1" sn a
  jq -e 'any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and (.isWALArchiver // false))' <<<"$j" >/dev/null 2>&1 || return 1
  sn="$(_f1c_cnpg_server_name "$j")"
  [[ -n "$sn" ]] || sn="$(jq -r '.metadata.name' <<<"$j")"
  for a in "${_f1_s11_anciens[@]}"; do [[ "$sn" != "$a" ]] || return 1; done
}

# _f1c_kq ne passe pas d'options à jq : variante locale qui en accepte.
_f1_s11_kq() {
  local opts=() f j
  while [[ "${1:-}" == --arg ]]; do opts+=("$1" "$2" "$3"); shift 3; done
  f="$1"; shift
  j="$(_f1c_kj "$@")"
  [[ -n "$j" ]] && jq -e "${opts[@]}" "$f" >/dev/null 2>&1 <<<"$j"
}
# _f1_s11_sauvegarde_neuve ESPACE CLUSTER — une sauvegarde « completed » postérieure à la naissance
#   du cluster Kubernetes (donc prise sur la base reconstruite).
_f1_s11_sauvegarde_neuve() {
  _f1_s11_kq --arg c "$2" --arg n "${_f1_s11_ne:-9999}" \
    'any(.items[]; .spec.cluster.name == $c and (.status.phase // "") == "completed" and (.status.stoppedAt // "") > $n)' \
    -n "$1" backups.postgresql.cnpg.io
}

# --- Les trois bases -----------------------------------------------------------------------------------
for _f1_s11_c in mediagenda-recette/mediagenda-db mediagenda-prod/mediagenda-db portail/portail-db; do
  _f1_s11_ns="${_f1_s11_c%/*}"
  _f1_s11_nom="${_f1_s11_c#*/}"
  _f1_s11_j="$(_f1c_cnpg "$_f1_s11_ns" "$_f1_s11_nom")"
  [[ -n "$_f1_s11_j" ]] || _f1_s11_j='{}'
  check_cmd "$_f1_s11_c : Cluster sain (Cluster in healthy state)" \
    jq -e '.status.phase == "Cluster in healthy state"' <<<"$_f1_s11_j"
  check_cmd "$_f1_s11_c : issu d'une récupération (bootstrap.recovery depuis un externalCluster du plugin Barman Cloud)" \
    jq -e '.spec.bootstrap.recovery.source as $s | $s != null
           and any(.spec.externalClusters[]?; .name == $s and .plugin.name == "barman-cloud.cloudnative-pg.io")' <<<"$_f1_s11_j"
  check_cmd "$_f1_s11_c : archive sous un serverName NOUVEAU (« $(_f1c_cnpg_server_name "$_f1_s11_j") »)" \
    _f1_s11_archive_neuve "$_f1_s11_j"
  check_cmd "$_f1_s11_c : archivage continu actif (condition ContinuousArchiving)" \
    jq -e 'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' <<<"$_f1_s11_j"
  check_cmd "$_f1_s11_c : sauvegarde « completed » prise sur la base reconstruite" \
    _f1_s11_sauvegarde_neuve "$_f1_s11_ns" "$_f1_s11_nom"
  check_cmd "$_f1_s11_c : sauvegarde planifiée (ScheduledBackup)" \
    _f1_s11_kq --arg c "$_f1_s11_nom" 'any(.items[]; .spec.cluster.name == $c)' -n "$_f1_s11_ns" scheduledbackups.postgresql.cnpg.io
done

# --- Réplica de secours ------------------------------------------------------------------------------------
_f1_s11_prod="$(_f1c_cnpg mediagenda-prod mediagenda-db)"
[[ -n "$_f1_s11_prod" ]] || _f1_s11_prod='{}'
_f1_s11_sn_prod="$(_f1c_cnpg_server_name "$_f1_s11_prod")"
_f1_s11_sec="$(_f1c_cnpg mediagenda-secours mediagenda-db-secours)"
[[ -n "$_f1_s11_sec" ]] || _f1_s11_sec='{}'
check_cmd "mediagenda-db-secours : sain et en réplica" \
  jq -e '.status.phase == "Cluster in healthy state" and .spec.replica.enabled == true' <<<"$_f1_s11_sec"
check_cmd "mediagenda-db-secours suit le serverName actuel de la production (${_f1_s11_sn_prod:-?})" \
  jq -e --arg s "${_f1_s11_sn_prod:-//}" '.spec.replica.source as $r
    | any(.spec.externalClusters[]?; .name == $r and .plugin.parameters.serverName == $s)' <<<"$_f1_s11_sec"

# --- OpenBao et les bases --------------------------------------------------------------------------------------
check_cmd "identifiants dynamiques de production prêts (ExternalSecrets de mediagenda-prod)" _f1c_kq \
  '(.items | length > 0) and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
  -n mediagenda-prod externalsecrets.external-secrets.io
for _f1_s11_env in recette:10.10.41.64 prod:10.10.41.65; do
  _f1_s11_e="${_f1_s11_env%%:*}"
  _f1_s11_ip="${_f1_s11_env#*:}"
  check_cmd "vault01 : certificat de la base de $_f1_s11_e ($_f1_s11_ip) vérifié par l'autorité copiée (mediagenda-$_f1_s11_e-ca.crt)" \
    _f1c_hote vault01 "timeout 10 openssl s_client -starttls postgres -connect $_f1_s11_ip:5432 \
      -CAfile /etc/openbao/postgresql/mediagenda-$_f1_s11_e-ca.crt -verify_return_error </dev/null 2>&1 | grep -q 'Verify return code: 0'"
done

# --- Messagerie ----------------------------------------------------------------------------------------------------
for _f1_s11_v in medinotif-recette medinotif-prod; do
  check_cmd "RabbitMQ : file quorum notifications du vhost $_f1_s11_v" \
    bash -c 'jq -e ".type == \"quorum\"" <<<"$1" >/dev/null' _ "$(rabbitmq_api "queues/$_f1_s11_v/notifications" 2>/dev/null || echo '{}')"
done
check_cmd "export des définitions RabbitMQ réussi sur le nouveau cluster (Job de messagerie/export-definitions)" \
  _f1_s11_kq --arg n "${_f1_s11_ne:-9999}" \
  'any(.items[]; (.metadata.name | startswith("export-")) and (.status.succeeded // 0) >= 1 and (.status.completionTime // "") > $n)' \
  -n messagerie jobs

# --- Argo CD et comparaison --------------------------------------------------------------------------------------------
_f1_s11_ko="$(_f1c_apps_non_saines "" | head -n 6 | paste -sd ' ' -)"
_f1_s11_nb="$(_f1c_nb applications.argoproj.io -n argocd)"
check_cmd "toutes les Applications Synced/Healthy, production comprise${_f1_s11_ko:+ — $_f1_s11_ko}" \
  test -z "$_f1_s11_ko" -a "$_f1_s11_nb" -gt 0

# _f1_s11_comparaison ENV — dans donnees-apres.md, la ligne « rendez-vous … ENV » porte deux nombres égaux.
_f1_s11_doc="$(_f1c_doc_texte '^donnees-apres\.md$')"
_f1_s11_comparaison() {
  local l
  l="$(grep -Ei "rendez-vous.*\($1\)|rendez-vous.*\b$1\b" <<<"$_f1_s11_doc" | head -n 1)"
  [[ -n "$l" ]] || return 1
  # Deux premiers nombres de la ligne (espaces fines et séparateurs de milliers retirés).
  awk '{ gsub(/[  ]/, ""); n = 0; while (match($0, /[0-9]+/)) { v[++n] = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) }
         exit !(n >= 2 && v[1] == v[2]) }' <<<"$l"
}
check_cmd "docs/day0/donnees-apres.md publié" test -n "$_f1_s11_doc"
for _f1_s11_e in prod recette; do
  check_cmd "donnees-apres.md : rendez-vous ($_f1_s11_e) identiques au gel et après" _f1_s11_comparaison "$_f1_s11_e"
done

# Contre-vérification par l'API publique de production (sans conserver aucune donnée : seul le
# nombre d'éléments est lu), si la base a moins de 1000 rendez-vous (limite de la liste).
_f1_s11_api="$(curl -sf --max-time 10 "$_f1c_prod_url/api/v1/rendez-vous?limite=1000" 2>/dev/null | jq 'length' 2>/dev/null || true)"
_f1_s11_doc_prod="$(grep -Ei 'rendez-vous.*\(prod\)|rendez-vous.*\bprod\b' <<<"$_f1_s11_doc" | head -n 1 | tr -d '  ' | grep -oE '[0-9]+' | sed -n 2p || true)"
if [[ "$_f1_s11_api" =~ ^[0-9]+$ ]] && ((_f1_s11_api < 1000)); then
  check_cmd "production : l'API compte $_f1_s11_api rendez-vous, comme donnees-apres.md (${_f1_s11_doc_prod:-?})" \
    test "$_f1_s11_api" = "${_f1_s11_doc_prod:-x}"
else
  skip "comptage par l'API de production" "API injoignable ou 1000 rendez-vous et plus (limite de la liste)"
fi
