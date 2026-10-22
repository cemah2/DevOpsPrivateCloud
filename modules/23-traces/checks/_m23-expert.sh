# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# _m23-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 23
# (check-E19 à check-E25). Sourcé, jamais lancé seul ; charge _m23-production.sh. Lecture seule.
# Préfixe _m23x_ : évite les collisions quand check-E23 et check-E25 chargent plusieurs checks.

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m23x_sel_agenda="{resource.service.name = \"mediagenda-api\" && $_m23p_attr_env = \"dev\"}"
  _m23x_sel_doc="{resource.service.name = \"medidoc\" && $_m23p_attr_env = \"dev\"}"
  _m23x_sel_dist="{resource.service.name = \"mediagenda-api\"} >> {resource.service.name = \"medidoc\" && $_m23p_attr_env = \"dev\"}"
  _m23x_sel_racine_doc="{trace:rootService = \"medidoc\" && $_m23p_attr_env = \"dev\"}"
  _m23x_runbooks=docs/observabilite/traces/runbooks
}

# _m23x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M23-* si aucune) n'est marquée active.
_m23x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M23-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M23-$e" ]] || return 1
  done
}

# _m23x_temoin — le témoin de trafic du palier 4 existe (créé à la première injection).
_m23x_temoin() { kube -n wb-pannes get deploy trafic-agenda >/dev/null 2>&1; }

# _m23x_env_pods ESPACE APP 'filtre jq sur la liste env du conteneur porteur d'OTEL_*' — tous les pods prêts
# de l'application satisfont le filtre (seules les valeurs littérales sont visibles : envFrom n'est pas lu).
_m23x_env_pods() {
  _m23p_kq "[.items[] | select(.metadata.labels[\"app.kubernetes.io/name\"] == \"$2\")
            | select(any(.status.conditions[]?; .type == \"Ready\" and .status == \"True\"))
            | .spec.containers[0].env // []] as \$e | (\$e | length) > 0 and all(\$e[]; $3)" -n "$1" pods
}

# _m23x_chaine_saine — les deux collectors sont prêts et des traces récentes de MédiAgenda (dev) arrivent.
_m23x_chaine_saine() {
  _m23p_collector_pret "$_m23p_passerelle" && _m23p_collector_pret "$_m23p_agent" && _m23p_traces 600 "$_m23x_sel_agenda"
}
