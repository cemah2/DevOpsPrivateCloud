#!/usr/bin/env bash
# rotation-images.sh — rotation et retrait des images dorées (M03-E16, ticket PLAT-458).
#
# Usage : outils/rotation-images.sh --famille debian13|rocky10|toutes [--garder N] [--appliquer] [--ssh-pve HÔTE]
#         outils/rotation-images.sh --retirer VMID [--appliquer] [--ssh-pve HÔTE]
#   Rotation : par famille, garde les N (défaut 3) versions les plus récentes non rejetées,
#   plus la version « current » où qu'elle soit ; supprime les autres (y compris les versions
#   étiquetées « rejete », sauf la plus récente, gardée pour analyse).
#   Retrait : supprime une version précise (image vulnérable, défectueuse…).
#   Sans --appliquer : simulation, rien n'est supprimé (le plan est affiché).
#   --ssh-pve HÔTE : sur LVM-thin, cherche aussi les clones liés avec « lvs » en root sur pve01
#   (depuis adm01 ; impossible en CI, où le jeton ne voit que l'API).
# Refus (code 3) : supprimer la version current ; supprimer un template dont des clones liés
#   sont détectés ; un VMID hors des plages des images dorées (9010-9049).
# Codes retour : 0 · 1 erreur · 2 usage · 3 refus d'un garde-fou (rien n'est supprimé pour ce VMID)
# Accès : outils/pve.sh (jeton wb-packer@pve!packer : VM.Audit, VM.Allocate sur le pool lab).
# shellcheck disable=SC2154  # PKR_VAR_proxmox_* : chargées par pve_charger_acces (outils/pve.sh)
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=pve.sh
. "$racine/outils/pve.sh"

usage() { sed -n '4,18s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }
famille="" retirer="" garder=3 appliquer=0 ssh_pve=""
while (($#)); do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --famille) famille="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --retirer) retirer="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --garder) garder="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --appliquer) appliquer=1; shift ;;
    --ssh-pve) ssh_pve="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [[ -n "$famille" && -n "$retirer" ]] || [[ -z "$famille$retirer" ]]; then usage >&2; exit 2; fi
[[ "$garder" =~ ^[1-9][0-9]*$ ]] || { echo "--garder : entier ≥ 1 attendu" >&2; exit 2; }
[[ -z "$retirer" || "$retirer" =~ ^[0-9]+$ ]] || { echo "--retirer : VMID attendu" >&2; exit 2; }
for c in curl jq; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done

pve_charger_acces
noeud="$PKR_VAR_proxmox_node"
mode="SIMULATION"; ((appliquer)) && mode="APPLICATION"
vms="$(pve_vms)"
refus_total=0

etiquettes() { jq -r --argjson v "$1" '.[] | select(.vmid == $v) | .tags // ""' <<<"$vms" | tr ',; ' '\n' | sed '/^$/d'; }

# clones_lies VMID — affiche les clones liés détectés (code 0 si au moins un).
clones_lies() {
  local tpl="$1" conf volumes sto type trouve="" id c
  conf="$(pve_api GET "/nodes/$noeud/qemu/$tpl/config")" || return 0
  # Disques du template : « stockage:base-<VMID>-disk-N » (et lecteur cloud-init, ignoré).
  volumes="$(jq -r 'to_entries[] | select(.key | test("^(scsi|virtio|sata|ide|efidisk|tpmstate)[0-9]+$"))
    | .value | split(",")[0] | select(test(":base-"))' <<<"$conf")"
  # 1. Références dans la configuration des VMs visibles (ZFS, répertoire, Ceph RBD… :
  #    le volume d'un clone lié s'y écrit « stockage:base-<VMID>-disk-N/vm-<ID>-disk-M »).
  for id in $(jq -r '.[] | select((.template // 0) == 0) | .vmid' <<<"$vms"); do
    c="$(pve_api GET "/nodes/$noeud/qemu/$id/config" 2>/dev/null)" || continue
    if jq -e --arg b "base-$tpl-" '[.[] | strings | select(contains(":" + $b) and contains("/"))] | length > 0' <<<"$c" >/dev/null; then
      trouve+="$id "
    fi
  done
  # 2. LVM-thin : un clone lié est un instantané thin nommé « vm-<ID>-disk-N », sans trace du
  #    template dans l'API. Seul « lvs » (root sur l'hôte) montre l'origine.
  local stockages=()
  mapfile -t stockages < <(cut -d: -f1 <<<"$volumes" | sed '/^$/d' | sort -u)
  for sto in "${stockages[@]}"; do
    type="$(pve_api GET "/nodes/$noeud/storage/$sto/status" | jq -r '.type')" || continue
    [[ "$type" == lvmthin ]] || continue
    if [[ -n "$ssh_pve" ]]; then
      c="$(ssh -o BatchMode=yes -o ControlPath=none "$ssh_pve" "lvs --noheadings -o lv_name,origin" \
        | awk -v b="base-$tpl-" 'index($2, b) == 1 {print $1}')" || { echo "lvs impossible sur $ssh_pve" >&2; trouve+="(lvs?) "; }
      [[ -n "$c" ]] && trouve+="$(sed -E 's/^vm-([0-9]+)-.*/\1/' <<<"$c" | sort -u | tr '\n' ' ')"
    else
      echo "  avertissement : $sto est en LVM-thin, les clones liés de $tpl n'y sont pas visibles par l'API" >&2
      echo "  (ils survivraient à la suppression : instantanés thin indépendants ; --ssh-pve pour vérifier)" >&2
    fi
  done
  [[ -n "$trouve" ]] || return 1
  echo "$trouve"
}

# supprimer VMID — après garde-fous ; code 3 si refus.
supprimer() {
  local id="$1" nom t cl upid
  nom="$(jq -r --argjson v "$id" '.[] | select(.vmid == $v) | .name' <<<"$vms")"
  [[ -n "$nom" ]] || { echo "  REFUS $id : invisible pour le jeton (hors pool lab ?)" >&2; return 3; }
  ((id >= 9010 && id <= 9049)) || { echo "  REFUS $id ($nom) : hors des plages des images dorées" >&2; return 3; }
  [[ "$(jq -r --argjson v "$id" '.[] | select(.vmid == $v) | .template // 0' <<<"$vms")" == 1 ]] \
    || { echo "  REFUS $id ($nom) : ce n'est pas un template" >&2; return 3; }
  t="$(etiquettes "$id")"
  if grep -qx current <<<"$t"; then
    echo "  REFUS $id ($nom) : version current — publie d'abord une autre version (outils/publier-image.sh)" >&2
    return 3
  fi
  if cl="$(clones_lies "$id")"; then
    echo "  REFUS $id ($nom) : clones liés détectés : $cl" >&2
    return 3
  fi
  if ((!appliquer)); then
    echo "  [simulation] suppression de $id ($nom)"
    return 0
  fi
  upid="$(pve_api DELETE "/nodes/$noeud/qemu/$id" purge=1 destroy-unreferenced-disks=1)" || return 1
  pve_attendre_tache "$(jq -r . <<<"$upid")" 300 || return 1
  echo "  supprimé : $id ($nom)"
}

traiter() { # traiter VMID — supprime et comptabilise les refus
  local rc=0
  supprimer "$1" || rc=$?
  ((rc == 3)) && refus_total=$((refus_total + 1))
  ((rc == 0 || rc == 3)) || exit 1
}

if [[ -n "$retirer" ]]; then
  echo "== $mode : retrait de $retirer"
  traiter "$retirer"
else
  [[ "$famille" == toutes ]] && familles="debian13 rocky10" || familles="$famille"
  for f in $familles; do
    plage="$(pve_famille "$f")" || { echo "famille inconnue : $f" >&2; exit 2; }
    read -r debut fin prefixe <<<"$plage"
    # Templates de la famille, du plus récent au plus ancien (date, puis N numérique).
    liste="$(jq -c --arg f "$f" --arg p "$prefixe-" --argjson a "$debut" --argjson b "$fin" '
      [.[] | select((.template // 0) == 1 and .vmid >= $a and .vmid <= $b)
       | select(((.tags // "") | split(";")) as $t | ($t | index("gold")) and ($t | index($f)))
       | select(.name | test("^" + $p + "[0-9]{8}-[0-9]+$"))
       | . + {cle: (.name | ltrimstr($p) | split("-") | [.[0], (.[1] | tonumber)]),
              etq: ((.tags // "") | split(";"))}]
      | sort_by(.cle) | reverse' <<<"$vms")"
    echo "== $mode : famille $f ($(jq length <<<"$liste") versions, garder $garder + current)"
    jq -r '.[] | "  \(.vmid) \(.name) [\(.etq | join(";"))]"' <<<"$liste"
    # Versions à garder : current, les N plus récentes non rejetées, la plus récente rejetée.
    garde="$(jq -r --argjson n "$garder" '
      ([.[] | select(.etq | index("current")) | .vmid]
       + ([.[] | select((.etq | index("rejete")) | not) | .vmid] | .[:$n])
       + ([.[] | select(.etq | index("rejete")) | .vmid] | .[:1])) | unique | .[]' <<<"$liste")"
    for id in $(jq -r '.[].vmid' <<<"$liste"); do
      grep -qx "$id" <<<"$garde" || traiter "$id"
    done
  done
fi

if ((refus_total)); then
  echo "== $refus_total refus : voir ci-dessus (rien n'a été supprimé pour ces versions)" >&2
  exit 3
fi
echo "== terminé ($mode)"
