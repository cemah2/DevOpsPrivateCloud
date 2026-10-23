# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S03.sh — F3-S03 « Lundi : MédiAgenda rame » (production) : consultations rapides vues de
# l'extérieur, aucune session en attente de verrou ni transaction interminable, pooler sans clients en
# attente, cache Valkey utilisable, pods de l'API conformes à leur gabarit, santé du lab, trace INC-5903.
# Lecture seule (GET de créneaux d'un praticien fictif : rien n'est écrit en base).

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S03 — MédiAgenda (production) répond de nouveau normalement"
require_cmd kubectl jq curl ssh

if _f3d_latence_ok "$_f3d_url_prod"; then
  _ok "consultation des créneaux (cache manqué) : médiane ${_f3d_derniere_latence} s (≤ ${WB_F3_LATENCE_MAX:-1.0} s)"
else
  _ko "consultation des créneaux (cache manqué) : médiane ${_f3d_derniere_latence} s, au-delà de ${WB_F3_LATENCE_MAX:-1.0} s"
fi

_f3d_s03_v="$(_f3d_prom "sum(cnpg_backends_waiting_total{namespace=\"$_f3d_prod\"})")"
if [[ -z "$_f3d_s03_v" ]]; then
  skip "sessions PostgreSQL en attente de verrou" "métrique cnpg_backends_waiting_total absente"
elif [[ "${_f3d_s03_v%.*}" == 0 ]]; then
  _ok "aucune session de mediagenda-db (prod) n'attend un verrou"
else
  _ko "$_f3d_s03_v session(s) de mediagenda-db (prod) attendent un verrou"
fi
_f3d_s03_v="$(_f3d_prom "max(cnpg_backends_max_tx_duration_seconds{namespace=\"$_f3d_prod\", datname=\"mediagenda\"})")"
if [[ -z "$_f3d_s03_v" ]]; then
  skip "durée des transactions" "métrique cnpg_backends_max_tx_duration_seconds absente"
elif _f3d_inferieur "$_f3d_s03_v" 300; then
  _ok "aucune transaction ouverte depuis plus de 5 min sur la base mediagenda (prod)"
else
  _ko "une transaction est ouverte depuis ${_f3d_s03_v%.*} s sur la base mediagenda (prod)"
fi
_f3d_s03_v="$(_f3d_prom "sum(cnpg_pgbouncer_pools_cl_waiting{namespace=\"$_f3d_prod\"})")"
if [[ -z "$_f3d_s03_v" ]]; then
  skip "clients en attente du pooler" "métrique cnpg_pgbouncer_pools_cl_waiting absente"
elif [[ "${_f3d_s03_v%.*}" == 0 ]]; then
  _ok "aucun client en attente dans le pooler mediagenda-db-pooler-rw (prod)"
else
  _ko "$_f3d_s03_v client(s) en attente dans le pooler (prod)"
fi

_f3d_s03_v="$(_f3d_prom "max(redis_config_maxmemory{namespace=\"$_f3d_prod\"})")"
if [[ -z "$_f3d_s03_v" ]]; then
  skip "mémoire de Valkey (prod)" "métrique redis_config_maxmemory absente"
elif [[ "${_f3d_s03_v%.*}" == 0 ]] || ! _f3d_inferieur "$_f3d_s03_v" "${WB_F3_VALKEY_MAXMEMORY_MIN:-16777216}"; then
  _ok "Valkey (prod) dispose de sa mémoire de cache"
else
  _ko "Valkey (prod) n'a que ${_f3d_s03_v%.*} octets de mémoire de cache"
fi
_f3d_s03_v="$(_f3d_prom "sum(rate(redis_evicted_keys_total{namespace=\"$_f3d_prod\"}[5m]))")"
if [[ -n "$_f3d_s03_v" ]] && ! _f3d_inferieur "$_f3d_s03_v" 1; then
  _ko "Valkey (prod) évince des clés en continu ($_f3d_s03_v/s)"
else
  _ok "Valkey (prod) n'évince pas de clés en continu"
fi

check_cmd "les pods de l'API (prod) ont les ressources CPU de leur gabarit" _f3d_api_ressources_conformes

check_cmd "RB-330 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-330
_f3s_sante
_f3s_trace INC-5903 1
