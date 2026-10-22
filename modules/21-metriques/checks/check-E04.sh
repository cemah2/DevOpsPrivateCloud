# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E04.sh — M21-E04 : PromQL : sélecteurs, taux et agrégations
# À lancer depuis adm01. Lecture seule : API GitLab (fichier sur main), API de Prometheus.
# Chaque requête de requetes/E04.promql doit s'évaluer sans erreur ET renvoyer des données : si
# MédiAgenda ne reçoit aucun trafic, relance ressources/E04-trafic/trafic-mediagenda.sh.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E04 — PromQL : sélecteurs, taux et agrégations"
require_cmd jq curl

check_cmd "Prérequis : MédiAgenda est collecté (up{job=\"mediagenda\"}, M21-E07)" \
  _m21d_au_moins 'count(up{job="mediagenda"} == 1)' 1
check_cmd "Prérequis : MédiAgenda reçoit du trafic en recette (débit > 0 sur 5 min)" \
  _m21d_au_moins 'sum(rate(mediagenda_http_requests_total{namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"}[5m]))' 0.01

_m21d_e04="$(_m21d_contenu_main plateforme/observabilite requetes/E04.promql)"
# Les notions demandées sont présentes (lecture du fichier sans ses commentaires).
_m21d_e04_q="$(_m21d_requetes "$_m21d_e04")"
check_output "Un quantile calculé sur un histogramme agrégé en gardant « le »" \
  'histogram_quantile\([^,]+, *sum by \([^)]*\ble\b' printf '%s' "$_m21d_e04_q"
check_output "Une jointure on(…) group_left(…) avec kube_pod_info" 'group_left *\([^)]*\).*kube_pod_info' printf '%s' "$_m21d_e04_q"
check_output "Un décalage dans le temps (offset)" '\boffset +[0-9]+[smhd]' printf '%s' "$_m21d_e04_q"
check_output "Une sous-requête ([fenêtre:pas])" '\[[0-9]+[smhd]:[0-9]*[smhd]?\]' printf '%s' "$_m21d_e04_q"
check_output "Une détection d'absence (absent)" '\babsent\(' printf '%s' "$_m21d_e04_q"
check_output "increase() sur un compteur" '\bincrease\(' printf '%s' "$_m21d_e04_q"

_m21d_controler_fichier_promql plateforme/observabilite requetes/E04.promql 15
