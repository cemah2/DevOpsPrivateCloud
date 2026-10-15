# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués à distance
#
# check-E14.sh — M12-E14 : Pods Podman et Quadlet : des conteneurs gérés par systemd
# À lancer depuis adm01. Lecture seule : systemctl --user is-active, podman pod/inspect et lecture des
# fichiers du compte app sur ctr02 et ctr03 ; requête HTTP vers ctr02:8000.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E14 — Pods Podman et Quadlet : des conteneurs gérés par systemd"
require_cmd jq curl

# --- 1. Les services de ctr02 ------------------------------------------------------------------------------
for _m12o_e14_u in mediagenda-pg mediagenda-valkey mediagenda-api; do
  check_output "ctr02 (app) : $_m12o_e14_u.service actif" '^active$' \
    _m12o_app "$_M12O_CTR02" "systemctl --user is-active $_m12o_e14_u.service"
done
check_output "ctr02 (app) : pod mediagenda en marche" '^mediagenda Running' \
  _m12o_app "$_M12O_CTR02" "podman pod ps --format '{{.Name}} {{.Status}}'"
check_http "Depuis adm01 : /pret de l'API sur ctr02:8000 répond 200" "http://$_M12O_NOM02:8000/pret" 200
check_output "ctr02 : linger actif pour app" '^Linger=yes$' _m12o_ssh "$_M12O_CTR02" 'loginctl show-user app -p Linger'

# --- 2. Les fichiers Quadlet ----------------------------------------------------------------------------------
_m12o_e14_q="$(_m12o_ssh "$_M12O_CTR02" 'sudo -n sh -c "cd /home/app/.config/containers/systemd 2>/dev/null && for f in *; do echo \"== \$f\"; cat \"\$f\"; done"')"
for _m12o_e14_t in pod network volume build; do
  check_cmd "ctr02 : un fichier Quadlet .$_m12o_e14_t dans ~app/.config/containers/systemd/" \
    _m12o_correspond "$_m12o_e14_q" "^== .*\\.$_m12o_e14_t$"
done
check_cmd "Fichiers Quadlet : aucun mot de passe en clair (POSTGRES_PASSWORD=, URL avec mot de passe)" \
  _m12o_absent "$_m12o_e14_q" 'POSTGRES_PASSWORD=|postgres(ql)?://[^:/@ ]+:[^@ ]+@'
_m12o_e14_env="$(_m12o_app "$_M12O_CTR02" "podman inspect --format '{{json .Config.Env}}' mediagenda-api mediagenda-pg")"
check_cmd "podman inspect : aucun mot de passe dans l'environnement de l'API et de la base" \
  _m12o_absent "$_m12o_e14_env" '"POSTGRES_PASSWORD=|postgres(ql)?://[^:/@"]+:[^@"]+@'
check_ssh "ctr02 : ~app/m12/e14/mediagenda-pod.yaml décrit un Pod Kubernetes" "$_M12O_CTR02" \
  'sudo -n grep -Eq "^kind: *Pod" /home/app/m12/e14/mediagenda-pod.yaml'

# --- 3. ctr03 : podman quadlet install ---------------------------------------------------------------------------
check_output "ctr03 (app) : m12-e14-essai installé par podman quadlet (podman quadlet list)" 'm12-e14-essai' \
  _m12o_app "$_M12O_CTR03" 'podman quadlet list'
check_output "ctr03 (app) : m12-e14-essai.service actif" '^active$' \
  _m12o_app "$_M12O_CTR03" 'systemctl --user is-active m12-e14-essai.service'
