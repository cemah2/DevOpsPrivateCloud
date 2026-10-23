# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E25.sh — M27-E25 « Mini-projet : les données et la messagerie de MédiSphère v1 » (étiquette donnees-v1).
# Contrôle global depuis adm01, lecture seule : rejoue les checks clés du module (ceux des paliers 1 et 2
# s'ils sont présents, puis E13, E14, E15) et ajoute les contrôles de livraison. 3 à 6 minutes.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E25 — Les données et la messagerie de MédiSphère v1 : contrôle global"
require_cmd kubectl jq curl dig

# --- 1. Production --------------------------------------------------------------------------------------
title "1/7 Production : pooler, publication, consommation"
check_cmd "mediagenda-db (prod) : instances prêtes, état sain" _m27p_cluster_sain "$_m27p_prod" mediagenda-db
check_cmd "MédiAgenda prod passe par le pooler (mediagenda-db-pooler-rw cité dans mediagenda/deploiement)" \
  _m27p_depot_contient mediagenda/deploiement "" 'mediagenda-db-pooler-rw'
check_cmd "pooler de prod : des clients connectés (cnpg_pgbouncer_pools_cl_active)" \
  _m27p_prom_positif "sum(cnpg_pgbouncer_pools_cl_active{namespace=\"$_m27p_prod\"})"
check_cmd "notifications ($_m27p_vhost_prod) : consommée, moins de 20 messages prêts" _m27x_file_saine "$_m27p_vhost_prod"
check_cmd "notifications ($_m27p_vhost_prod) : rebut et limite de livraison en place" _m27x_file_protegee "$_m27p_vhost_prod"
check_cmd "notifications.rebut ($_m27p_vhost_prod) : vide ou presque (≤ 5)" \
  _m27p_file "$_m27p_vhost_prod" notifications.rebut '(.messages // 0) <= 5'
check_cmd "MédiNotif (prod) disponible, sans redémarrage récent" _m27x_medinotif_sain medinotif-prod
check_cmd "notifications envoyées en production dans les dernières 24 h" \
  _m27p_prom_positif 'sum(increase(medinotif_messages_total{namespace="medinotif-prod", resultat="envoye"}[24h]))'
_m27_e25_publication_prod() {
  rabbitmq_api "exchanges/$_m27p_vhost_prod/notifications" 2>/dev/null | jq -e '(.message_stats.publish_in // 0) > 0' >/dev/null 2>&1
}
check_cmd "MédiAgenda prod a publié sur l'échange notifications ($_m27p_vhost_prod)" _m27_e25_publication_prod

# --- 2. Moindre privilège et images ----------------------------------------------------------------------
title "2/7 Identités et images"
_m27_e25_perm() {   # _m27_e25_perm UTILISATEUR 'filtre jq sur .spec.permissions'
  kube get permissions.rabbitmq.com -A -o json 2>/dev/null | jq -e --arg u "$1" "
    [.items[] | select((.spec.user // .spec.userReference.name // \"\") == \$u)] as \$p
    | (\$p | length) > 0 and all(\$p[]; .spec.permissions | $2)" >/dev/null 2>&1
}
check_cmd "mediagenda-prod publie seulement (ni lecture ni configuration)" \
  _m27_e25_perm mediagenda-prod '(.read // "") == "^$" and (.configure // "") == "^$" and ((.write // "^$") as $w | "notifications" | test($w))'
check_cmd "medinotif-prod consomme seulement (ni écriture sur notifications ni configuration)" \
  _m27_e25_perm medinotif-prod '(.configure // "") == "^$" and ((.write // "^$") as $w | "notifications" | test($w) | not) and ((.read // "^$") as $r | "notifications" | test($r))'
_m27_e25_bitnami() {
  local ns
  _m27p_cluster_joignable || return 1
  for ns in messagerie rabbitmq-system medinotif-recette medinotif-prod mediagenda-recette mediagenda-prod mediagenda-secours; do
    kube get namespace "$ns" >/dev/null 2>&1 || continue
    _m27p_kq '[.items[].spec | (.containers + (.initContainers // []))[] | .image | select(test("bitnami"; "i"))] | length == 0' -n "$ns" pods || return 1
  done
}
check_cmd "aucune image Bitnami dans les espaces des données et de la messagerie" _m27_e25_bitnami

# --- 3. Rejeu des checks clés -----------------------------------------------------------------------------
title "3/7 Rejeu des checks clés du module"
_m27_e25_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m27_e25_x in E02 E03 E04 E05 E07 E08; do
  if [[ -f "$_m27_e25_dir/check-$_m27_e25_x.sh" ]]; then
    # shellcheck disable=SC1090
    source "$_m27_e25_dir/check-$_m27_e25_x.sh"
  fi
done
# shellcheck source=check-E13.sh
source "$_m27_e25_dir/check-E13.sh"
# shellcheck source=check-E14.sh
source "$_m27_e25_dir/check-E14.sh"
# shellcheck source=check-E15.sh
source "$_m27_e25_dir/check-E15.sh"

# --- 4. Alertes vertes ------------------------------------------------------------------------------------
title "4/7 Alertes des données au vert"
check_cmd "aucune alerte critique active sur les espaces de données et de messagerie" \
  _m27p_prom_nul_ou_absent 'count(ALERTS{alertstate="firing", gravite="critique", namespace=~"mediagenda-(recette|prod|secours)|medinotif-.*|messagerie|rabbitmq-system"})'
check_cmd "aucune alerte active sur les files (vhosts medinotif-*)" \
  _m27p_prom_nul_ou_absent 'count(ALERTS{alertstate="firing", vhost=~"medinotif-.*"})'
check_cmd "aucune alarme de ressource RabbitMQ" \
  _m27p_prom_nul_ou_absent 'max(rabbitmq_alarms_memory_used_watermark) + max(rabbitmq_alarms_free_disk_space_watermark)'

# --- 5. Essais retirés ------------------------------------------------------------------------------------
title "5/7 Essais retirés"
_m27_e25_pas_ns() { kube get namespace default >/dev/null 2>&1 && ! kube get namespace "$1" >/dev/null 2>&1; }
check_cmd "Kafka : espace kafka-essai absent" _m27_e25_pas_ns kafka-essai
check_cmd "Kafka : aucune Application Argo CD kafka-essai" \
  _m27p_kq '[.items[] | select(.metadata.name | test("kafka"))] | length == 0' -n argocd applications.argoproj.io
check_cmd "Kafka : aucun PVC restant de kafka-essai" \
  _m27p_kq '[.items[] | select(.metadata.namespace == "kafka-essai")] | length == 0' persistentvolumeclaims -A
_m27_e25_pare_feu() {
  local c
  c="$(_m27p_fichier plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml 2>/dev/null)" || return 1
  [[ -n "$c" ]] && ! grep -Eq '10\.10\.99\.7[1-3]' <<<"$c"
}
check_cmd "Patroni : flux provisoires retirés du pare-feu de bordure (plus de 10.10.99.71-73)" \
  _m27_e25_pare_feu
check_cmd "wb-essais : aucun Pooler restant" _m27p_absent poolers.postgresql.cnpg.io wb-essais
check_cmd "aucune panne M27 encore marquée active (lab/bin/break)" _m27p_aucune_panne_active

# --- 6. Documentation -------------------------------------------------------------------------------------
title "6/7 Documentation"
check_cmd "README.md d'architecture de docs/donnees (composants, versions, flux, identités, runbooks)" \
  _m27p_doc "$_m27p_docs" README 'CloudNativePG|CNPG' 'RabbitMQ' 'Valkey' 'Flyway' 'OpenBao' 'RB-27[0-9]' 'KEDA'
check_cmd "ADR-0270 publié" _m27p_doc "$_m27p_docs/adr" ADR-0270 'RabbitMQ' 'outbox'
check_cmd "comparatifs publiés (messagerie, Patroni/CNPG)" _m27p_doc "$_m27p_docs" comparatif-messagerie 'Kafka'
check_cmd "dimensionnement et décision RabbitMQ 4.4 publiés" _m27p_doc "$_m27p_docs" dimensionnement 'pooler'
_m27_e25_runbooks() {
  local n liste
  liste="$(_m27p_arbre plateforme/medisphere "$_m27p_runbooks")" || return 1
  for n in 0 1 2 3 4 5 6 7 8 9; do
    grep -q "RB-27$n" <<<"$liste" || return 1
  done
}
check_cmd "runbooks RB-270 à RB-279 présents dans docs/donnees/runbooks/" _m27_e25_runbooks
check_cmd "demonstration.md : rendez-vous de test suivi en production, daté, identifiants à l'appui" \
  _m27p_doc "$_m27p_docs" demonstration '20[0-9]{2}-[01][0-9]-[0-3][0-9]' '[0-9]{2}:[0-9]{2}' 'medinotif|MédiNotif' 'notifications' 'annul'

# --- 7. Livraison -----------------------------------------------------------------------------------------
title "7/7 Livraison"
_m27_e25_pipeline() {
  gitlab_api "projects/plateforme%2Fdonnees/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "plateforme/donnees : dernier pipeline de main réussi" _m27_e25_pipeline
_m27_e25_etiquette() {
  gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/donnees-v1' 2>/dev/null | jq -e '.name == "donnees-v1"' >/dev/null 2>&1
}
check_cmd "étiquette donnees-v1 posée sur plateforme/medisphere" _m27_e25_etiquette
