#!/usr/bin/env bash
# check-lib.sh — Bibliothèque commune des scripts de vérification du workbook.
#
# Usage : sourcée par lab/bin/check, jamais exécutée directement.
# Toutes les fonctions sont en LECTURE SEULE : elles observent le lab, ne le modifient pas.
#
# Variables d'environnement (définies dans lab/lab.env, voir lab/lab.env.example) :
#   WB_PVE_HOST   hôte SSH de l'hyperviseur principal (défaut : pve01)
#   WB_PBS_HOST   hôte SSH du Proxmox Backup Server  (défaut : pbs01)
#   WB_SSH_OPTS   options SSH supplémentaires
#   WB_TIMEOUT    délai max (s) pour les tests réseau (défaut : 5)

# shellcheck disable=SC2034  # variables utilisées par les scripts qui sourcent la lib
WB_PVE_HOST="${WB_PVE_HOST:-pve01}"
WB_PBS_HOST="${WB_PBS_HOST:-pbs01}"
WB_SSH_OPTS="${WB_SSH_OPTS:-}"
WB_TIMEOUT="${WB_TIMEOUT:-5}"

_WB_OK=0
_WB_KO=0
_WB_SKIP=0

if [[ -t 1 ]]; then
  _C_OK=$'\e[32m'; _C_KO=$'\e[31m'; _C_SKIP=$'\e[33m'; _C_TITLE=$'\e[1m'; _C_RST=$'\e[0m'
else
  _C_OK=""; _C_KO=""; _C_SKIP=""; _C_TITLE=""; _C_RST=""
fi

# title "texte" — affiche le titre de l'exercice vérifié
title() {
  printf '%s== %s ==%s\n' "$_C_TITLE" "$1" "$_C_RST"
}

_ok()   { _WB_OK=$((_WB_OK + 1));     printf '  %s[OK]%s   %s\n' "$_C_OK" "$_C_RST" "$1"; }
_ko()   { _WB_KO=$((_WB_KO + 1));     printf '  %s[KO]%s   %s\n' "$_C_KO" "$_C_RST" "$1"; }

# skip "description" "raison" — contrôle non applicable (ex. option non choisie)
skip() {
  _WB_SKIP=$((_WB_SKIP + 1))
  printf '  %s[--]%s   %s (%s)\n' "$_C_SKIP" "$_C_RST" "$1" "${2:-ignoré}"
}

# check_cmd "description" commande [args...]
#   OK si la commande renvoie 0 (exécutée localement sur adm01).
check_cmd() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_output "description" "regex étendue" commande [args...]
#   OK si la sortie (stdout+stderr) de la commande correspond à la regex.
check_output() {
  local desc="$1" regex="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# remote hôte commande — exécute une commande en SSH (sans interaction), renvoie son code.
#   Si hôte vaut « localhost » ou le nom court de la machine courante, la commande est
#   exécutée localement (utile avant que adm01 n'existe : les checks tournent alors sur pve01).
remote() {
  local host="$1"; shift
  if [[ "$host" == "localhost" || "$host" == "$(hostname -s)" ]]; then
    bash -c "$*"
    return
  fi
  # shellcheck disable=SC2086  # WB_SSH_OPTS doit être découpé en mots
  ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" $WB_SSH_OPTS "$host" -- "$@"
}

# check_ssh "description" hôte "commande distante"
#   OK si la commande distante renvoie 0.
check_ssh() {
  local desc="$1" host="$2" cmd="$3"
  if remote "$host" "$cmd" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_ssh_output "description" hôte "regex" "commande distante"
check_ssh_output() {
  local desc="$1" host="$2" regex="$3" cmd="$4"
  local out
  out="$(remote "$host" "$cmd" 2>&1)" || true
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# check_ping "description" ip
check_ping() {
  local desc="$1" ip="$2"
  if ping -c 2 -W "$WB_TIMEOUT" "$ip" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_port "description" hôte port
#   OK si une connexion TCP aboutit.
check_port() {
  local desc="$1" host="$2" port="$3"
  if timeout "$WB_TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    _ok "$desc"
  else
    _ko "$desc"
  fi
}

# check_http "description" url [code_attendu=200] [options curl supplémentaires...]
check_http() {
  local desc="$1" url="$2" expected="${3:-200}"
  shift $(( $# < 3 ? $# : 3 ))
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$@" "$url" 2>/dev/null)" || true
  if [[ "$code" == "$expected" ]]; then _ok "$desc"; else _ko "$desc (HTTP ${code:-aucune réponse})"; fi
}

# check_dns "description" nom type "regex attendue" [serveur]
check_dns() {
  local desc="$1" name="$2" type="$3" regex="$4" server="${5:-}"
  local out
  if [[ -n "$server" ]]; then
    out="$(dig +short +time="$WB_TIMEOUT" "@$server" "$name" "$type" 2>&1)" || true
  else
    out="$(dig +short +time="$WB_TIMEOUT" "$name" "$type" 2>&1)" || true
  fi
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# require_cmd outil... — vérifie la présence d'outils sur adm01 avant les contrôles
require_cmd() {
  local c missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      printf '  %s[!!]%s   outil manquant sur ce poste : %s\n' "$_C_KO" "$_C_RST" "$c"
      missing=1
    fi
  done
  if (( missing )); then
    echo "Installe les outils manquants puis relance la vérification."
    exit 2
  fi
}

# summary — affiche le bilan et renvoie 0 si aucun KO
summary() {
  echo
  printf 'Bilan : %s%d OK%s, %s%d KO%s, %d ignoré(s)\n' \
    "$_C_OK" "$_WB_OK" "$_C_RST" "$_C_KO" "$_WB_KO" "$_C_RST" "$_WB_SKIP"
  if (( _WB_KO == 0 )); then
    echo "Exercice validé."
    return 0
  fi
  echo "Exercice non validé : corrige les points en KO puis relance."
  return 1
}
