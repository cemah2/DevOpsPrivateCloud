#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2329  # commandes évaluées à distance ; fonctions appelées via ligne()
# triage-forge.sh — sonde de triage de la forge MédiSphère, depuis adm01 (M01-E43, INC-2788).
#
# Teste chaque porte de la forge séparément, sans rien modifier, et affiche un tableau :
#   web (HTTPS), API (jeton en lecture), Git en SSH, sonde interne readiness (via l'alias
#   d'administration git01), services omnibus, runner (vu de GitLab et de runner01).
# Usage : triage-forge.sh            (lit WB_GITLAB_URL et WB_GITLAB_TOKEN_FILE si définis)
# Code de sortie : nombre de contrôles en échec (0 = tout va bien).
set -uo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
FQDN="${URL#https://}"
JETON_F="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
T=5
ko=0

ligne() {   # ligne "porte" commande...
  local porte="$1"; shift
  local debut fin
  debut=$(date +%s%N)
  if "$@" >/dev/null 2>&1; then
    fin=$(date +%s%N)
    printf '%-38s OK   %5d ms\n' "$porte" $(((fin - debut) / 1000000))
  else
    printf '%-38s KO\n' "$porte"
    ko=$((ko + 1))
  fi
}

runner_ok() {
  api 'runners/all?type=instance_type&tag_list=shell,socle' \
    | jq -e 'length == 1 and .[0].status == "online" and (.[0].paused | not)'
}
web_ok() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time "$T" "$URL/users/sign_in")" = 200 ]; }

api() { curl -sf --max-time "$T" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_F")") "$URL/api/v4/$1"; }

printf '%s — sonde de la forge (%s)\n\n' "$(date '+%F %T')" "$FQDN"
ligne "web : page de connexion (HTTP 200)" web_ok
ligne "API : /version (jeton des checks)" api version
ligne "Git en SSH : accueil de gitlab-shell" \
  bash -c 'ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout="$2" -T "git@$1" 2>&1 | grep -q "Welcome to GitLab"' _ "$FQDN" "$T"
ligne "Git en SSH : ls-remote plateforme/medisphere" \
  env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" git ls-remote --exit-code "git@$FQDN:plateforme/medisphere.git" HEAD
ligne "git01 : /-/readiness (interne)" \
  bash -c 'ssh -o BatchMode=yes git01 "curl -s --max-time 5 --resolve $1:443:127.0.0.1 https://$1/-/readiness" | grep -q "\"status\":\"ok\""' _ "$FQDN"
ligne "git01 : aucun service omnibus arrêté" \
  ssh -o BatchMode=yes git01 '! sudo -n gitlab-ctl status | grep -q "^down:"'
ligne "git01 : puma stable (> 60 s)" \
  ssh -o BatchMode=yes git01 's=$(sudo -n gitlab-ctl status puma | sed -nE "s/^run: puma: \(pid [0-9]+\) ([0-9]+)s.*/\1/p"); [ -n "$s" ] && [ "$s" -ge 60 ]'
ligne "GitLab : runner shell+socle en ligne, actif" runner_ok
ligne "runner01 : service gitlab-runner actif" \
  ssh -o BatchMode=yes runner01 'systemctl is-active -q gitlab-runner'
ligne "runner01 : forge résolue vers 10.10.20.12" \
  ssh -o BatchMode=yes runner01 "getent ahostsv4 $FQDN | awk '{print \$1}' | sort -u | grep -qx 10.10.20.12"
ligne "runner01 : jobs récents sans erreur d'accès" \
  ssh -o BatchMode=yes runner01 '! sudo -n journalctl -u gitlab-runner --since -5min --no-pager | grep -Eqi "forbidden|dial tcp|x509|no route"'

printf '\n%d contrôle(s) en échec.\n' "$ko"
exit "$ko"
