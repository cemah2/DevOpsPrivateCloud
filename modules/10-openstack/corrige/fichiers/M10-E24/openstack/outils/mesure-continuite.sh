#!/usr/bin/env bash
# mesure-continuite.sh — mesures de continuité horodatées pendant une panne ou un changement
# (M10-E24 ; resservi en E28 et E29). À lancer depuis adm01. Lecture seule sur le cloud.
#
# Trois sondes, une ligne « <epoch> ok|ko » par essai, dans un fichier chacune :
#   nord-sud.log   ping (1/s) de l'IP flottante d'une instance            → plan de données, passerelle
#   est-ouest.log  ping (1/s) de l'adresse PRIVÉE d'une seconde instance, lancé DANS la première
#                  (nohup : survit à la coupure de la session SSH ; rapatrié par « analyser »)
#   api.log        « openstack token issue » toutes les 5 s                 → plan de contrôle
#
# Usage :
#   mesure-continuite.sh lancer   -d DOSSIER -f IP_FLOTTANTE [-p IP_PRIVEE] [-u UTILISATEUR] [-c CLOUD]
#   mesure-continuite.sh arreter  -d DOSSIER
#   mesure-continuite.sh analyser -d DOSSIER
# UTILISATEUR : compte de l'image (debian par défaut) ; CLOUD : cloud de clouds.yaml
# (medisphere-plateforme par défaut). L'horloge de l'instance doit être synchronisée (chrony).
set -euo pipefail

usage() {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2
  exit 2
}

action="${1:-}"; [[ -n "$action" ]] || usage; shift
dossier="" ip_fip="" ip_privee="" utilisateur=debian cloud=medisphere-plateforme
while getopts ':d:f:p:u:c:' o; do
  case "$o" in
    d) dossier="$OPTARG" ;;
    f) ip_fip="$OPTARG" ;;
    p) ip_privee="$OPTARG" ;;
    u) utilisateur="$OPTARG" ;;
    c) cloud="$OPTARG" ;;
    *) usage ;;
  esac
done
[[ -n "$dossier" ]] || usage
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5)

sonde_ping() {   # sonde_ping IP FICHIER
  while :; do
    if ping -n -c 1 -W 1 "$1" >/dev/null 2>&1; then echo "$(date +%s) ok"; else echo "$(date +%s) ko"; fi
    sleep 1
  done >>"$2"
}

sonde_api() {    # sonde_api CLOUD FICHIER
  while :; do
    if timeout 10 openstack --os-cloud "$1" token issue -f value -c id >/dev/null 2>&1; then
      echo "$(date +%s) ok"
    else
      echo "$(date +%s) ko"
    fi
    sleep 5
  done >>"$2"
}

lancer() {
  [[ -n "$ip_fip" ]] || usage
  mkdir -p "$dossier"
  [[ ! -e "$dossier/pids" ]] || { echo "mesure déjà en cours dans $dossier (arrête-la d'abord)" >&2; exit 1; }
  printf 'fip=%s\nprivee=%s\nutilisateur=%s\ndebut=%s\n' "$ip_fip" "$ip_privee" "$utilisateur" "$(date -Is)" >"$dossier/parametres"
  sonde_ping "$ip_fip" "$dossier/nord-sud.log" & echo $! >>"$dossier/pids"
  sonde_api "$cloud" "$dossier/api.log" & echo $! >>"$dossier/pids"
  if [[ -n "$ip_privee" ]]; then
    # shellcheck disable=SC2016  # boucle évaluée sur l'instance
    "${SSH[@]}" "$utilisateur@$ip_fip" "nohup bash -c 'while :; do if ping -n -c 1 -W 1 $ip_privee >/dev/null 2>&1; then echo \"\$(date +%s) ok\"; else echo \"\$(date +%s) ko\"; fi; sleep 1; done' >/tmp/est-ouest.log 2>&1 & echo \$! >/tmp/est-ouest.pid"
  fi
  echo "mesures lancées ($(wc -l <"$dossier/pids") locales$([[ -n "$ip_privee" ]] && echo ', 1 dans l'"'"'instance')) : $dossier"
}

param() { sed -n "s/^$1=//p" "$dossier/parametres"; }

arreter() {
  if [[ -r "$dossier/pids" ]]; then xargs -r kill <"$dossier/pids" 2>/dev/null || true; fi
  rm -f "$dossier/pids"
  if [[ -n "$(param privee)" ]]; then
    # shellcheck disable=SC2016  # évalué sur l'instance
    "${SSH[@]}" "$(param utilisateur)@$(param fip)" 'kill "$(cat /tmp/est-ouest.pid)" 2>/dev/null; true' || \
      echo "instance injoignable : arrête la sonde est-ouest plus tard (kill \$(cat /tmp/est-ouest.pid))" >&2
  fi
  echo "mesures arrêtées"
}

# Intervalles « ko » consécutifs d'un fichier : début, fin (epoch, 0 = en cours).
intervalles() {
  local d f n=0 total=0
  while read -r d f; do
    if [[ "$f" == 0 ]]; then
      printf '  %s → (en cours)\n' "$(date -d "@$d" +%T)"
    else
      printf '  %s → %s  %4d s\n' "$(date -d "@$d" +%T)" "$(date -d "@$f" +%T)" $((f - d))
      total=$((total + f - d)); n=$((n + 1))
    fi
  done < <(awk '$2 == "ko" && !p { d = $1; p = 1 } $2 == "ok" && p { print d, $1; p = 0 } END { if (p) print d, 0 }' "$1")
  printf '  %d coupure(s) terminée(s), %d s au total, %d essai(s)\n' "$n" "$total" "$(wc -l <"$1")"
}

analyser() {
  if [[ -n "$(param privee)" ]]; then
    "${SSH[@]}" "$(param utilisateur)@$(param fip)" 'cat /tmp/est-ouest.log' >"$dossier/est-ouest.log" 2>/dev/null || \
      echo "est-ouest.log non rapatrié (instance injoignable ?)" >&2
  fi
  local f
  for f in nord-sud est-ouest api; do
    [[ -s "$dossier/$f.log" ]] || continue
    echo "$f :"
    intervalles "$dossier/$f.log"
  done
}

case "$action" in
  lancer) lancer ;;
  arreter) arreter ;;
  analyser) analyser ;;
  *) usage ;;
esac
