# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M12-E41 « Panne : le conteneur est tué sans prévenir » : l'API de recette est saine
# et le reste (aucun arrêt, redémarrage ni OOM pendant une minute, ni dans les événements des trois
# dernières minutes), sa sonde de santé réussit, ses limites sont réalistes mais présentes.
# Lecture seule (docker events en lecture). Durée : un peu plus d'une minute.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E41 — L'API de recette n'est plus tuée"
require_cmd jq curl ssh

_m12_e41_evenements() {
  local n
  n="$(_m12x_root "$_m12x_ctr01" <<'EOF'
timeout 10 docker events --since 3m --until 0s --filter container=recette-api-1 \
  --filter event=die --filter event=kill --filter event=oom --filter event=restart --format '{{.Action}}' 2>/dev/null | wc -l
EOF
)" || return 1
  [[ "$n" == 0 ]]
}

if _m12x_recette_repond; then
  check_cmd "API : conteneur démarré et sain" _m12x_sain api
  check_cmd "API : dernière exécution de la sonde de santé réussie" _m12x_jq '.services.api.sante_derniere == 0'
  check_cmd "API : pas tuée par manque de mémoire (OOMKilled)" _m12x_jq '.services.api.oom == false'
  check_cmd "API : limite mémoire présente et d'au moins 128 Mio" \
    _m12x_jq '.services.api.memoire >= 134217728'
  check_cmd "API : limite de processus présente et d'au moins 64" \
    _m12x_jq '.services.api.pids >= 64'
  check_cmd "API : aucun arrêt, kill, OOM ni redémarrage dans les trois dernières minutes" _m12_e41_evenements
  check_cmd "API : aucun redémarrage pendant 60 s" _m12x_stable api 60
else
  skip "API de recette" "Docker ne répond pas sur $_m12x_ctr01, ou la pile « recette » n'existe pas"
fi
check_http "API : /pret répond 200" "$_m12x_url_api/pret" 200
check_cmd "panne M12-E41 close (lab/bin/break 12 41 --annuler après réparation)" _m12x_aucune_panne_active E41
