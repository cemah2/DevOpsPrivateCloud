# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E26.sh — M02-E26 : Contrôle planifié des sauvegardes PBS avec un timer systemd
# À lancer depuis adm01 (où vivent le timer et le service). Lecture seule : état systemd,
# droits des jetons sur pve01 et pbs01, et une exécution du contrôle (qui ne fait que lire).

title "M02-E26 — Contrôle planifié des sauvegardes PBS avec un timer systemd"
require_cmd systemctl jq ssh

_m02_svc=ms-verif-sauvegardes.service
_m02_tim=ms-verif-sauvegardes.timer
_m02_pve_env="$HOME/.config/workbook/pve-lecture.env"
_m02_pbs_env="$HOME/.config/workbook/pbs-lecture.env"
# _m02_var FICHIER NOM — valeur d'une variable d'un fichier .env (sans le charger dans ce shell)
# shellcheck source=/dev/null
_m02_var() { (set +u; source "$1" >/dev/null 2>&1 && printf '%s' "${!2:-}") 2>/dev/null || true; }

# --- Unités systemd ---------------------------------------------------------------
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type "$_m02_svc"
check_output "le service tourne en admin (pas en root)" '^User=admin$' systemctl show -p User "$_m02_svc"
check_output "le service déclenche une unité ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure "$_m02_svc"
check_output "le service exécute une copie installée (pas le clone ~/src)" 'path=/usr/local/' \
  systemctl show -p ExecStart "$_m02_svc"
check_cmd "le timer est activé" systemctl is-enabled --quiet "$_m02_tim"
check_cmd "le timer est actif" systemctl is-active --quiet "$_m02_tim"
check_output "le timer est planifié tous les jours à 07:30" 'OnCalendar=\*-\*-\* 07:30:00' \
  systemctl show -p TimersCalendar "$_m02_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' \
  systemctl show -p Persistent "$_m02_tim"
check_cmd "le service a déjà été exécuté par systemd" bash -c \
  '[[ "$(systemctl show -p ExecMainStartTimestampMonotonic --value "$1")" != 0 ]]' _ "$_m02_svc"
check_output "la chaîne d'alerte a été testée (journal de ms-alerte@$_m02_svc sur 30 jours)" 'ÉCHEC|ECHEC' \
  sudo -n journalctl -q --no-pager --since -30d -u "ms-alerte@$_m02_svc" -t ms-alerte

# --- Secrets et jetons en lecture seule ---------------------------------------------
for _m02_f in "$_m02_pve_env" "$_m02_pbs_env"; do
  check_output "$(basename "$_m02_f") existe, lisible par toi seul" '^[4-7]00$' stat -c '%a' "$_m02_f"
done
_m02_ptok="$(_m02_var "$_m02_pve_env" PVE_TOKEN_ID)"
check_output "pve-lecture.env désigne un jeton dédié (pas wb-automation@pve!lab)" '^[^!]+@[a-z]+![A-Za-z0-9_-]+$' \
  bash -c '[[ "$1" != "wb-automation@pve!lab" ]] && echo "$1"' _ "$_m02_ptok"
if [[ "$_m02_ptok" == *'!'* ]]; then
  _m02_perm="$(remote "$WB_PVE_HOST" "pveum user token permissions '${_m02_ptok%%!*}' '${_m02_ptok#*!}' --output-format json" 2>/dev/null)" || _m02_perm=""
  check_output "jeton Proxmox : VM.Audit sur le pool lab" '^true$' \
    jq -r '[.[] | keys[]] | index("VM.Audit") != null' <<<"$_m02_perm"
  check_output "jeton Proxmox : uniquement des privilèges de lecture (*.Audit)" '^0$' \
    jq -r '[.[] | keys[] | select(endswith(".Audit") | not)] | length' <<<"$_m02_perm"
else
  skip "droits du jeton Proxmox de lecture" "PVE_TOKEN_ID illisible dans $_m02_pve_env"
fi
_m02_btok="$(_m02_var "$_m02_pbs_env" PBS_TOKEN_ID)"
if [[ "$_m02_btok" == *'!'* ]]; then
  _m02_bperm="$(remote "$WB_PBS_HOST" "proxmox-backup-manager user permissions '$_m02_btok' --path /datastore/ds-lab/par1 --output-format json" 2>/dev/null)" || _m02_bperm=""
  check_output "jeton PBS : Datastore.Audit sur ds-lab/par1" 'Datastore\.Audit' printf '%s\n' "$_m02_bperm"
  check_cmd "jeton PBS : ni lecture des données, ni sauvegarde, ni modification, ni élagage" \
    bash -c '[[ -n "$1" ]] && ! grep -Eq "Datastore\.(Read|Backup|Modify|Prune|Allocate)" <<<"$1"' _ "$_m02_bperm"
else
  skip "droits du jeton PBS de lecture" "PBS_TOKEN_ID illisible dans $_m02_pbs_env"
fi
_m02_secret="$(_m02_var "$_m02_pbs_env" PBS_TOKEN_SECRET)"
check_cmd "le script installé ne contient pas le secret du jeton PBS" bash -c \
  '[[ -n "$1" ]] && ! grep -qF -- "$1" /usr/local/bin/ms-verif-sauvegardes' _ "$_m02_secret"

# --- Le contrôle, maintenant ---------------------------------------------------------
check_cmd "le contrôle conclut que le socle est sauvegardé (code 0)" \
  timeout 120 /usr/local/bin/ms-verif-sauvegardes
check_output "le contrôle refuse un seuil absurde (code 2)" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-sauvegardes --age-max abc >/dev/null 2>&1; echo $?'
