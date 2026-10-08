# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes (hôte distant, jq)
# check-E40.sh — M08-E40 « Panne : le S3 de Ceph répond en erreur » : point d'entrée HTTPS joignable
# et vérifié, démons RGW et ingress en marche, utilisateur témoin actif, horloge du client juste,
# lecture signée de l'objet témoin réussie. Lecture seule (GET uniquement).

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E40 — Le S3 de Ceph répond"
require_cmd jq ssh curl

check_http "https://$_m08x_rgw/ répond 200 avec un certificat vérifié (depuis adm01)" "https://$_m08x_rgw/" 200
if _m08x_cluster_repond; then
  check_cmd "au moins deux démons RGW, tous en marche" \
    _m08x_jq '[.orch[] | select(.type == "rgw")] | length >= 2 and all(.etat == "running")'
  check_cmd "démons haproxy et keepalived du service ingress tous en marche" \
    _m08x_jq '[.orch[] | select(.type == "haproxy" or .type == "keepalived")] | length >= 2 and all(.etat == "running")'
  if _m08x_temoins; then
    check_cmd "utilisateur RGW sonde-s3 actif (non suspendu)" _m08x_jq '.rgw_sonde.suspended == 0'
  fi
else
  skip "démons RGW et ingress" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
for _m08_e40_h in "${_m08x_noeuds[@]}"; do
  check_ssh "$_m08_e40_h : aucune unité ceph masquée ou en échec" "$_m08_e40_h" "sudo -n bash -c $(printf '%q' "$_m08x_cmd_unites_saines")"
done
if _m08x_temoins; then
  check_ssh "$_m08x_client : horloge synchronisée (décalage < 1 s)" "$_m08x_client" \
    'chronyc -n tracking 2>/dev/null | awk '\''/^System time/ { t = $4 } /^Leap status/ { l = $4 } END { exit !(t != "" && t < 1 && l == "Normal") }'\'''
  check_ssh_output "$_m08x_client : lecture signée de s3://sonde/temoin (HTTP 200)" "$_m08x_client" '^200$' \
    "sudo -n curl -s -o /dev/null -w '%{http_code}' --max-time 15 -K /etc/workbook/sonde-s3.curl https://$_m08x_rgw/sonde/temoin"
else
  skip "lecture S3 signée depuis $_m08x_client" "témoins pas encore créés (créés à la première injection)"
fi
check_cmd "panne M08-E40 close (lab/bin/break 08 40 --annuler après réparation)" _m08x_aucune_panne_active E40
