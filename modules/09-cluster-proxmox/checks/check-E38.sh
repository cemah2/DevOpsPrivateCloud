# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E38.sh — M09-E38 « Panne : la migration à chaud échoue » : réseau de migration joignable en SSH
# entre tous les nœuds, limite de bande passante raisonnable, et (tant que la VM de test existe) aucun
# obstacle local à sa migration. Lecture seule (seul le contrôle préalable de l'API est appelé).

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E38 — Les migrations à chaud sont possibles"
require_cmd ssh jq

# Réseau de migration : « migration: …network=CIDR » de datacenter.cfg (M09-E27), sinon MGMT.
_m09_e38_reseau="$(_m09x_hv hv01 "sed -nE 's/^migration:.*network=([0-9./]+).*/\\1/p' /etc/pve/datacenter.cfg" 2>/dev/null)"
for _m09_e38_n in "${_m09x_noeuds[@]}"; do
  for _m09_e38_d in "${_m09x_noeuds[@]}"; do
    [[ "$_m09_e38_n" != "$_m09_e38_d" ]] || continue
    _m09_e38_ip="${_m09x_ip[$_m09_e38_d]}"
    [[ "$_m09_e38_reseau" == 10.10.30.* ]] && _m09_e38_ip="${_m09x_stopub[$_m09_e38_d]}"
    check_ssh "$_m09_e38_n → $_m09_e38_d : SSH root sur le réseau de migration ($_m09_e38_ip)" "$(_m09x_cible "$_m09_e38_n")" \
      "ssh -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=$_m09_e38_d root@$_m09_e38_ip true"
  done
  check_cmd "$_m09_e38_n : aucun filtrage parasite (table $_m09x_table absente)" _m09x_pas_de_table "$_m09_e38_n"
done
check_ssh "datacenter.cfg : pas de limite de migration inférieure à 10 Mio/s" "$(_m09x_cible hv01)" '
  v=$(sed -nE "s/^bwlimit:.*migration=([0-9]+).*/\1/p" /etc/pve/datacenter.cfg)
  [ -z "$v" ] || [ "$v" -ge 10240 ]'
_m09_e38_noeud="$(_m09x_json "$(_m09x_un_noeud)" /cluster/resources --type vm | jq -r '.[] | select(.vmid == 194) | .node' 2>/dev/null)"
if [[ -n "$_m09_e38_noeud" ]]; then
  _m09_e38_dest=hv02
  [[ "$_m09_e38_noeud" != hv02 ]] || _m09_e38_dest=hv01
  check_output "VM de test 194 : aucun disque ni périphérique local qui bloque la migration vers $_m09_e38_dest" '^ok$' \
    bash -c 'jq -r "if ((.local_disks // []) | length) == 0 and ((.local_resources // []) | length) == 0 then \"ok\" else \"bloquant\" end" <<<"$1"' _ \
    "$(_m09x_json "$_m09_e38_noeud" "/nodes/$_m09_e38_noeud/qemu/194/migrate" --target "$_m09_e38_dest")"
else
  skip "VM de test 194 : obstacles locaux à la migration" "VM absente (panne close)"
fi
check_output "hv01 : une migration à chaud de la VM 194 a réussi (tâche qmigrate, 7 derniers jours)" '^[1-9][0-9]*$' \
  bash -c 'jq --argjson t "$(( $(date +%s) - 604800 ))" "[.[] | select(.type == \"qmigrate\" and (.id // \"\") == \"194\" and .status == \"OK\" and (.starttime // 0) > \$t)] | length" <<<"$1" 2>/dev/null' _ \
  "$(_m09x_json hv01 /nodes/hv01/tasks --typefilter qmigrate --vmid 194 --source all --limit 200)"
check_cmd "panne M09-E38 close (lab/bin/break 09 38 --annuler après réparation)" _m09x_aucune_panne_active E38
