# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E06.sh — M12-E06 : Podman sans privilège
# À lancer depuis adm01. Lecture seule : podman inspect en tant que app (sudo -n -u app) et ps
# sur ctr02 (SSH), requête HTTP vers le conteneur publié.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E06 — Podman sans privilège"
require_cmd curl

_m12d_e06_fin=$((_M12D_SUBID_DEBUT + _M12D_SUBID_NOMBRE - 1))

check_output "ctr02 : m12-e06-web tourne dans le Podman de app (nginx 1.30)" '^running (docker\.io/library/)?nginx:1\.30' \
  _m12d_podman ctr02 "inspect m12-e06-web --format '{{.State.Status}} {{.ImageName}}'"
check_output "ctr02 : m12-e06-web publie le port 80 du conteneur sur le port 8080 de l'hôte" '^80/tcp -> .*:8080$' \
  _m12d_podman ctr02 "port m12-e06-web"
check_http "Depuis adm01 : http://ctr02…:8080/ répond" "http://$(_m12d_fqdn ctr02):8080/" 200

# Les processus nginx vus de l'HÔTE (ps en admin) : maître sous l'UID de app, travailleurs dans
# la plage subordonnée de app (UID 101 de l'image → 524288 + 100).
check_ssh "Vu de l'hôte : le processus maître de nginx tourne sous l'UID de app ($_M12D_APP_UID)" ctr02 \
  "ps -o uid=,args= -C nginx | awk '\$1 == $_M12D_APP_UID && /master process/ {t=1} END {exit !t}'"
check_ssh "Vu de l'hôte : les processus de travail tournent sous un UID de la plage $_M12D_SUBID_DEBUT-$_m12d_e06_fin" ctr02 \
  "ps -o uid=,args= -C nginx | awk '/worker process/ { n++; if (\$1 >= $_M12D_SUBID_DEBUT && \$1 <= $_m12d_e06_fin) ok++ } END {exit !(n > 0 && n == ok)}'"
check_ssh "Vu de l'hôte : aucun processus nginx de ctr02 ne tourne en root" ctr02 \
  "! ps -o uid=,args= -C nginx | awk '\$1 == 0 {t=1} END {exit !t}'"
check_ssh "Vu de l'hôte : le réseau sans privilège est porté par pasta, processus de app" ctr02 \
  "pgrep -u $_M12D_APP -f '(^|/)pasta' >/dev/null"
check_ssh "ctr02 : les images de app sont dans son stockage personnel" ctr02 \
  "sudo -n test -d /home/$_M12D_APP/.local/share/containers/storage/overlay-images"
