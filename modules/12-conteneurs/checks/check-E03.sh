# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués par docker ou bash -c
#
# check-E03.sh — M12-E03 : Premiers conteneurs avec Docker : cycle de vie
# À lancer depuis adm01. Lecture seule : docker inspect/diff sur ctr01 (SSH), requête HTTP.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E03 — Premiers conteneurs avec Docker : cycle de vie"
require_cmd curl

# --- 1. Le service web ---------------------------------------------------------------------------
_m12d_e03_web="$(_m12d_inspect m12-e03-web '{{.State.Status}}|{{.Config.Image}}|{{.HostConfig.RestartPolicy.Name}}|{{range $p, $b := .HostConfig.PortBindings}}{{$p}}={{range $b}}{{.HostPort}}{{end}} {{end}}')"
check_cmd "m12-e03-web existe et tourne" _m12d_correspond "$_m12d_e03_web" '^running\|'
check_cmd "m12-e03-web : image nginx 1.30" _m12d_correspond "$_m12d_e03_web" '^[^|]*\|(docker\.io/library/)?nginx:1\.30'
check_cmd "m12-e03-web : politique de redémarrage unless-stopped" _m12d_correspond "$_m12d_e03_web" '\|unless-stopped\|'
check_cmd "m12-e03-web : port 80 du conteneur publié sur le port 8080 de l'hôte" _m12d_correspond "$_m12d_e03_web" '80/tcp=8080( |$)'
check_output "m12-e03-web : la page d'accueil a été modifiée dans le conteneur (docker diff)" \
  '^C /usr/share/nginx/html/index\.html$' _m12d_docker "diff m12-e03-web"
check_output "Depuis adm01 : la page de m12-e03-web contient « MédiSphère »" 'MédiSphère' \
  _m12d_http "http://$(_m12d_fqdn ctr01):8080/"

# --- 2. Arrêt d'un PID 1 qui ignore SIGTERM -------------------------------------------------------
check_output "m12-e03-sommeil : arrêté, tué par SIGKILL après le délai de docker stop (code 137)" '^exited 137$' \
  _m12d_inspect m12-e03-sommeil '{{.State.Status}} {{.State.ExitCode}}'

# --- 3. Politique de redémarrage limitée ------------------------------------------------------------
check_output "m12-e03-crash : on-failure:3, trois redémarrages, arrêté avec son code 3" '^on-failure:3 3 exited 3$' \
  _m12d_inspect m12-e03-crash '{{.HostConfig.RestartPolicy.Name}}:{{.HostConfig.RestartPolicy.MaximumRetryCount}} {{.RestartCount}} {{.State.Status}} {{.State.ExitCode}}'
