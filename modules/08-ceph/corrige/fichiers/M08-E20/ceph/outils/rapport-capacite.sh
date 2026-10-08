#!/usr/bin/env bash
# outils/rapport-capacite.sh — rapport de capacité de ceph-par1, lisible sans expertise (M08-E20).
# Lecture seule. Clé conseillée : client.rapport (mon 'allow r' mgr 'allow r').
#   sur ceph01 :  sudo CEPH_ID=rapport CEPH_KEYRING=/etc/ceph/ceph.client.rapport.keyring outils/rapport-capacite.sh
#   sur adm01  :  CEPH_ADMIN=ceph01 outils/rapport-capacite.sh            (clé admin du nœud _admin)
# Option --rbd : ajoute le surengagement RBD (rbd du : demande la lecture des pools, ex. --id rbd-lecture).
# Code 0 ; 1 si un seuil de planification ou un quota (> 80 %) est dépassé (utilisable en sonde).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AVEC_RBD="${1:-}"
osd_tree="$(ms_ceph osd df tree --format json)"
df="$(ms_ceph df detail --format json)"
dump="$(ms_ceph osd dump --format json)"
pools="$(ms_ceph osd pool ls detail --format json)"
alerte=0

printf '== Capacité ceph-par1 (%s) ==\n\n' "$(date '+%F %H:%M')"

# --- Par classe de disque : brut, utilisé, utile (une copie par baie), seuil de planification ---
# Utile = capacité de la plus petite baie (chaque PG a une copie par baie). Seuil de planification :
# remplissage max. des OSD de la baie qui en a le moins, pour qu'un OSD perdu soit absorbé par les
# autres OSD de SA baie sans atteindre backfillfull : backfillfull × (n − 1) / n.
classes="$(jq -r --argjson bf "$(jq '.backfillfull_ratio' <<<"$dump")" '
  def gio: . / 1048576 | floor;
  (.nodes | map({key: (.id | tostring), value: .}) | from_entries) as $n
  | [.nodes[] | select(.type == "rack") | . as $r
     | [$r.children[] | $n[tostring] | .children[]? | $n[tostring] | select(.type == "osd")] as $osds
     | ($osds | group_by(.device_class)[] | {baie: $r.name, classe: .[0].device_class,
         n: length, kb: (map(.kb) | add), kb_used: (map(.kb_used) | add), max_util: (map(.utilization) | max)})]
  | group_by(.classe)[]
  | {classe: .[0].classe, brut: (map(.kb) | add), utilise: (map(.kb_used) | add),
     utile: (map(.kb) | min), n_min: (map(.n) | min), util_petite_baie: (min_by(.n).max_util)}
  | . + {seuil: (if .n_min > 1 then $bf * (.n_min - 1) / .n_min * 100 else 0 end)}
  | "\(.classe)\t\(.brut | gio) Gio\t\(.utilise * 100 / .brut | floor) %\t\(.utile | gio) Gio\t\(if .n_min > 1 then "\(.seuil | floor) %" else "aucun (1 OSD/baie)" end)\t\(.util_petite_baie | floor) %\t\(if .n_min > 1 and .util_petite_baie >= .seuil then "À PLANIFIER" else "ok" end)"
' <<<"$osd_tree")"
{ printf 'Classe\tBrut\tUtilisé\tUtile (1 copie/baie)\tSeuil planif.\tOSD le + plein (petite baie)\tÉtat\n'; printf '%s\n' "$classes"; } | column -t -s $'\t'
grep -q 'À PLANIFIER' <<<"$classes" && alerte=1

# --- Par pool : stocké, quota, marge, MAX AVAIL -----------------------------------------------------
echo
pools_lignes="$(jq -r --argjson p "$pools" '
  def gio: . / 1073741824 * 10 | floor / 10;
  ($p | map({key: .pool_name, value: (.quota_max_bytes // 0)}) | from_entries) as $q
  | .pools[] | . as $x | ($q[$x.name] // 0) as $quota
  | "\($x.name)\t\($x.stats.stored | gio) Gio\t\(if $quota > 0 then "\($quota | gio) Gio" else "-" end)\t\(if $quota > 0 then "\(100 - ($x.stats.stored * 100 / $quota) | floor) %" else "-" end)\t\($x.stats.max_avail | gio) Gio\t\(if $quota > 0 and ($x.stats.stored / $quota) > 0.8 then "QUOTA > 80 %" else "ok" end)"
' <<<"$df")"
{ printf 'Pool\tStocké\tQuota\tMarge quota\tMAX AVAIL\tÉtat\n'; printf '%s\n' "$pools_lignes"; } | column -t -s $'\t'
grep -q 'QUOTA > 80' <<<"$pools_lignes" && alerte=1

# --- OSD le plus rempli, seuils ----------------------------------------------------------------------
echo
jq -r '[.nodes[] | select(.type == "osd")] | max_by(.utilization)
       | "OSD le plus rempli : \(.name) (\(.device_class)) \(.utilization | floor) %"' <<<"$osd_tree"
jq -r '"Seuils : nearfull \(.nearfull_ratio), backfillfull \(.backfillfull_ratio), full \(.full_ratio)"' <<<"$dump"
echo "Santé : $(ms_ceph health | head -n 1)"

# --- Surengagement RBD (facultatif) ------------------------------------------------------------------
if [[ "$AVEC_RBD" == --rbd ]]; then
  echo
  for p in $(jq -r '.[] | select(.application_metadata | has("rbd")) | select(.erasure_code_profile == "" or .erasure_code_profile == null) | .pool_name' <<<"$pools"); do
    ms_outil rbd du -p "$p" --format json 2>/dev/null \
      | jq -r --arg p "$p" '"RBD \($p) : promis \(.total_provisioned_size / 1073741824 | floor) Gio, utilisé \(.total_used_size / 1073741824 | floor) Gio"' || true
  done
fi
exit "$alerte"
