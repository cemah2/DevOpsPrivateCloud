# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués par docker ou bash -c
#
# check-E07.sh — M12-E07 : Volumes, montages et réseaux
# À lancer depuis adm01. Lecture seule : docker inspect / network inspect / exec getent sur ctr01
# (SSH), requêtes HTTP vers le conteneur publié.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E07 — Volumes, montages et réseaux"
require_cmd jq curl

# --- 1. Le serveur web et ses données ---------------------------------------------------------------
_m12d_e07_web="$(_m12d_inspect m12-e07-web '{{json .}}')"
check_cmd "m12-e07-web tourne (nginx 1.30)" _m12d_json "$_m12d_e07_web" \
  '.State.Status == "running" and (.Config.Image | test("^(docker\\.io/library/)?nginx:1\\.30"))'
check_cmd "m12-e07-web : volume nommé m12-e07-pages sur /usr/share/nginx/html" _m12d_json "$_m12d_e07_web" \
  '[.Mounts[] | select(.Type == "volume" and .Name == "m12-e07-pages" and .Destination == "/usr/share/nginx/html")] | length == 1'
check_cmd "m12-e07-web : dossier ~/m12/e07/nginx monté en lecture seule sur /etc/nginx/conf.d" _m12d_json "$_m12d_e07_web" \
  '[.Mounts[] | select(.Type == "bind" and (.Source | test("/m12/e07/nginx/?$")) and .Destination == "/etc/nginx/conf.d" and .RW == false)] | length == 1'
check_cmd "m12-e07-web : tmpfs sur /var/cache/nginx" _m12d_json "$_m12d_e07_web" \
  '((.HostConfig.Tmpfs // {}) | has("/var/cache/nginx")) or ([.Mounts[] | select(.Type == "tmpfs" and .Destination == "/var/cache/nginx")] | length == 1)'
check_cmd "m12-e07-web : sur le réseau m12-e07-front" _m12d_json "$_m12d_e07_web" \
  '.NetworkSettings.Networks | has("m12-e07-front")'
check_cmd "m12-e07-web : port 80 publié sur le port 8081 de l'hôte" _m12d_json "$_m12d_e07_web" \
  '[.HostConfig.PortBindings["80/tcp"][]?.HostPort] | index("8081") != null'
check_output "Depuis adm01 : la page d'accueil (servie depuis le volume) contient M12-E07" 'M12-E07' \
  _m12d_http "http://$(_m12d_fqdn ctr01):8081/"
check_http "Depuis adm01 : /sante répond 200" "http://$(_m12d_fqdn ctr01):8081/sante" 200

# --- 2. Les réseaux ---------------------------------------------------------------------------------
check_output "Réseau m12-e07-front : bridge défini, sous-réseau pris dans 172.20.0.0/14" \
  '^bridge false .*"Subnet":"172\.(2[0-3])\.[0-9]+\.[0-9]+/' \
  _m12d_docker "network inspect --format '{{.Driver}} {{.Internal}} {{json .IPAM.Config}}' m12-e07-front"
check_output "m12-e07-client tourne sur m12-e07-front" '^running .*m12-e07-front' \
  _m12d_inspect m12-e07-client '{{.State.Status}} {{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}'
check_output "m12-e07-client résout m12-e07-web par son nom (DNS intégré)" '^[0-9]+(\.[0-9]+){3} +m12-e07-web' \
  _m12d_docker "exec m12-e07-client getent hosts m12-e07-web"
check_output "Réseau m12-e07-arriere : interne (aucune route vers l'extérieur)" '^true$' \
  _m12d_docker "network inspect --format '{{.Internal}}' m12-e07-arriere"
check_output "m12-e07-isole tourne, attaché au seul réseau m12-e07-arriere" '^running m12-e07-arriere $' \
  _m12d_inspect m12-e07-isole '{{.State.Status}} {{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}'
