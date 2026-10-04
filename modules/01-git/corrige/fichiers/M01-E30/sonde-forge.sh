#!/usr/bin/env bash
# =============================================================================
# sonde-forge.sh — sonde de santé de la forge MédiSphère (M01-E30, ticket PLAT-257)
# Emplacement : ~/lab-scripts/sonde-forge.sh sur adm01 (versionné dans
# plateforme/medisphere : forge/supervision/).
#
# Usage : sonde-forge.sh [-q]        -q : n'affiche que les lignes non OK
#
# Convention Nagios/Icinga (réutilisable telle quelle par un agent de supervision,
# puis remplacée par des alertes Prometheus au module 21) :
#   code 0 = tout est OK, 1 = au moins un avertissement, 2 = au moins un critique,
#   3 = la sonde elle-même ne peut pas s'exécuter.
# Une ligne par contrôle : « OK|WARN|CRIT  <contrôle> : <détail> ». Aucun secret affiché.
#
# Prérequis : adm01 dans gitlab_rails['monitoring_whitelist'] ; jeton des checks
# (read_api, + admin_mode si Admin Mode est actif) ; alias SSH git01 (sudo -n).
# =============================================================================
set -uo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_FICHIER="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
HOTE_SSH="${SONDE_HOTE_SSH:-git01}"
DELAI=10

# Seuils
CERT_WARN_J=30;   CERT_CRIT_J=7
DISQUE_WARN=80;   DISQUE_CRIT=90
MEM_WARN_MO=500
RUNNER_CRIT_S=300         # un runner sain contacte GitLab toutes les ~3 s
SAUVEGARDE_WARN_H=26

calme=0
[[ "${1:-}" == "-q" ]] && calme=1
code=0

res() {   # res NIVEAU CONTRÔLE DÉTAIL
  local niveau="$1" ctrl="$2" detail="$3"
  case "$niveau" in
    WARN) ((code < 1)) && code=1 ;;
    CRIT) code=2 ;;
  esac
  if ((calme == 0)) || [[ "$niveau" != OK ]]; then
    printf '%-5s %s : %s\n' "$niveau" "$ctrl" "$detail"
  fi
  return 0
}

for outil in curl jq openssl ssh; do
  command -v "$outil" >/dev/null || { echo "UNKNOWN outil manquant : $outil"; exit 3; }
done
[[ -r "$JETON_FICHIER" ]] || { echo "UNKNOWN jeton illisible : $JETON_FICHIER"; exit 3; }
api() { curl -sf --max-time "$DELAI" -H "PRIVATE-TOKEN: $(<"$JETON_FICHIER")" "$URL/api/v4/$1"; }
distant() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOTE_SSH" "$@"; }

# --- 1. Sondes applicatives -------------------------------------------------------
corps="$(curl -s --max-time "$DELAI" -w '\n%{http_code}' "$URL/-/readiness?all=1")"
http="${corps##*$'\n'}"; json="${corps%$'\n'*}"
if [[ "$http" == 200 ]]; then
  res OK "readiness" "toutes les dépendances répondent"
elif [[ "$http" == 503 ]]; then
  ko="$(jq -r 'to_entries[] | select(.value | type == "array") | select(any(.value[]; .status != "ok")) | .key' <<<"$json" 2>/dev/null | paste -sd, -)"
  res CRIT "readiness" "dépendance(s) en échec : ${ko:-inconnue}"
elif [[ "$http" == 404 || "$http" == 403 ]]; then
  res CRIT "readiness" "HTTP $http : adm01 absent de la liste d'adresses autorisées ?"
else
  res CRIT "readiness" "HTTP ${http:-aucune réponse}"
fi
http="$(curl -s -o /dev/null --max-time "$DELAI" -w '%{http_code}' "$URL/-/liveness")"
if [[ "$http" == 200 ]]; then res OK "liveness" "Rails répond"; else res CRIT "liveness" "HTTP ${http:-aucune réponse}"; fi

# --- 2. Certificat TLS --------------------------------------------------------------
hote="${URL#https://}"; hote="${hote%%/*}"
fin="$(openssl s_client -connect "$hote:443" -servername "$hote" </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
if [[ -z "$fin" ]]; then
  res CRIT "certificat" "illisible"
else
  jours=$(( ($(date -d "$fin" +%s) - $(date +%s)) / 86400 ))
  if ((jours < CERT_CRIT_J)); then res CRIT "certificat" "expire dans $jours j ($fin)"
  elif ((jours < CERT_WARN_J)); then res WARN "certificat" "expire dans $jours j ($fin)"
  else res OK "certificat" "valide encore $jours j"; fi
fi

# --- 3. Runners d'instance ----------------------------------------------------------
if runners="$(api "runners/all?type=instance_type&per_page=100")"; then
  n=0
  while read -r id; do
    [[ -n "$id" ]] || continue
    n=$((n + 1))
    detail="$(api "runners/$id")" || { res WARN "runner $id" "détails illisibles"; continue; }
    desc="$(jq -r '.description // "?"' <<<"$detail")"
    paused="$(jq -r '.paused' <<<"$detail")"
    contact="$(jq -r '.contacted_at // empty' <<<"$detail")"
    if [[ -z "$contact" ]]; then res CRIT "runner $desc" "jamais connecté"; continue; fi
    age=$(( $(date +%s) - $(date -d "$contact" +%s) ))
    if ((age > RUNNER_CRIT_S)); then res CRIT "runner $desc" "dernier contact il y a ${age} s"
    elif [[ "$paused" == true ]]; then res WARN "runner $desc" "en pause"
    else res OK "runner $desc" "contact il y a ${age} s"; fi
  done < <(jq -r '.[].id' <<<"$runners")
  ((n > 0)) || res CRIT "runners" "aucun runner d'instance"
else
  res WARN "runners" "API d'administration illisible (portée admin_mode du jeton ?)"
fi

# --- 4. Hôte git01 ------------------------------------------------------------------
# shellcheck disable=SC2016  # commande évaluée sur git01
if etat="$(distant 'df --output=pcent /var/opt/gitlab | tail -n 1; free -m | awk "/^Mem:/ {print \$7}"; sudo -n gitlab-ctl status 2>&1 | grep -c "^down:"; systemctl show -p Result --value wb-backup-gitlab.service; systemctl show -p ExecMainExitTimestamp --value wb-backup-gitlab.service' 2>/dev/null)"; then
  mapfile -t v <<<"$etat"
  disque="${v[0]//[^0-9]/}"; dispo="${v[1]}"; down="${v[2]}"; sauv_res="${v[3]}"; sauv_date="${v[4]:-}"
  if ((disque >= DISQUE_CRIT)); then res CRIT "disque /var/opt/gitlab" "${disque} %"
  elif ((disque >= DISQUE_WARN)); then res WARN "disque /var/opt/gitlab" "${disque} %"
  else res OK "disque /var/opt/gitlab" "${disque} %"; fi
  if ((dispo < MEM_WARN_MO)); then res WARN "mémoire git01" "${dispo} Mo disponibles"; else res OK "mémoire git01" "${dispo} Mo disponibles"; fi
  if ((down == 0)); then res OK "services GitLab" "tous démarrés"; else res CRIT "services GitLab" "$down service(s) arrêté(s) (gitlab-ctl status)"; fi
  if [[ "$sauv_res" != success ]]; then
    res CRIT "sauvegarde applicative" "dernier résultat : ${sauv_res:-inconnu}"
  elif [[ -z "$sauv_date" || "$sauv_date" == "n/a" ]]; then
    res WARN "sauvegarde applicative" "jamais exécutée depuis le démarrage"
  else
    h=$(( ($(date +%s) - $(date -d "$sauv_date" +%s)) / 3600 ))
    if ((h > SAUVEGARDE_WARN_H)); then res WARN "sauvegarde applicative" "dernière il y a ${h} h"; else res OK "sauvegarde applicative" "dernière il y a ${h} h"; fi
  fi
else
  res CRIT "hôte git01" "injoignable en SSH"
fi

exit "$code"
