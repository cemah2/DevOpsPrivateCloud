#!/usr/bin/env bash
# publier-image.sh — publie une image dorée : test, manifeste, étiquette « current » (M03-E10).
#
# Usage : outils/publier-image.sh [--dry-run] <VMID>
#   1. contrôle que <VMID> est un template étiqueté gold + debian13|rocky10 ;
#   2. lance tests/tester-image.sh <VMID> : AUCUNE publication si le test échoue ;
#   3. complète le champ « notes » du template (date de publication, test, empreinte
#      de la liste des paquets si manifests/<nom>-paquets.txt existe) ;
#   4. retire « current » de l'ancienne version de la famille, puis la pose sur <VMID>.
#   --dry-run : lance le test mais n'écrit rien (affiche les changements).
# Codes retour : 0 publiée · 1 erreur · 2 usage · 3 refus (pas un template doré, test en échec)
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=pve.sh
. "$racine/outils/pve.sh"

usage() { sed -n '4,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }
simulation=0
[[ "${1:-}" == "--dry-run" ]] && { simulation=1; shift; }
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "" | *[!0-9]*) usage >&2; exit 2 ;;
esac
vmid="$1"
pve_charger_acces
# shellcheck disable=SC2154  # chargée par pve_charger_acces
noeud="$PKR_VAR_proxmox_node"
refus() { echo "REFUS : $*" >&2; exit 3; }

# --- 1. Est-ce bien un template doré ? ---------------------------------------------------
conf="$(pve_api GET "/nodes/$noeud/qemu/$vmid/config")"
[[ "$(jq -r '.template // 0' <<<"$conf")" == 1 ]] || refus "$vmid n'est pas un template"
nom="$(jq -r '.name' <<<"$conf")"
etiquettes="$(jq -r '.tags // ""' <<<"$conf" | tr ',; ' '\n' | sed '/^$/d' | sort -u)"
grep -qx gold <<<"$etiquettes" || refus "$vmid ($nom) n'est pas étiqueté gold"
famille=""
for f in debian13 rocky10; do grep -qx "$f" <<<"$etiquettes" && famille="$f"; done
[[ -n "$famille" ]] || refus "$vmid ($nom) : famille inconnue (étiquette debian13 ou rocky10 attendue)"
grep -qx current <<<"$etiquettes" && { echo "$vmid ($nom) est déjà la version current"; exit 0; }

# --- 2. Test : la seule porte d'entrée vers « current » -----------------------------------
testeur="$racine/tests/tester-image.sh"
[[ -x "$testeur" ]] || refus "test introuvable : $testeur"
echo "== Test de $vmid ($nom)"
"$testeur" "$vmid" || refus "test en échec : $nom n'est PAS publiée"

# --- 3. Manifeste dans les notes -----------------------------------------------------------
manifeste="$racine/manifests/$nom-paquets.txt"
if [[ -s "$manifeste" ]]; then
  paquets="$(wc -l <"$manifeste") paquets, sha256 $(sha256sum "$manifeste" | cut -d' ' -f1)"
else
  paquets="liste des paquets non disponible sur ce poste"
fi
notes="$(jq -r '.description // ""' <<<"$conf")
Publiée le $(date '+%Y-%m-%d %H:%M %Z') par ${PKR_VAR_proxmox_username%%!*} après succès de tests/tester-image.sh.
Paquets : $paquets."

# --- 4. Déplacement de « current » ---------------------------------------------------------
ancien="$(pve_vms | jq -r --arg f "$famille" '.[] | select((.template // 0) == 1)
  | select(((.tags // "") | split(";")) as $t | ($t | index("gold")) and ($t | index($f)) and ($t | index("current")))
  | .vmid')"

maj_etiquettes() { # maj_etiquettes VMID ajouter|retirer ÉTIQUETTE
  local id="$1" action="$2" e="$3" c t
  c="$(pve_api GET "/nodes/$noeud/qemu/$id/config")"
  t="$(jq -r '.tags // ""' <<<"$c" | tr ',; ' '\n' | sed '/^$/d' | grep -vx "$e" || true)"
  [[ "$action" == ajouter ]] && t="$(printf '%s\n%s\n' "$t" "$e")"
  t="$(sed '/^$/d' <<<"$t" | sort -u | paste -sd ';')"
  if ((simulation)); then echo "[simulation] $id : tags=$t"; return 0; fi
  pve_api PUT "/nodes/$noeud/qemu/$id/config" "tags=$t" >/dev/null
}

if ((simulation)); then
  echo "[simulation] $vmid : notes complétées :"
  printf '%s\n' "$notes" | tail -n 2
else
  pve_api PUT "/nodes/$noeud/qemu/$vmid/config" "description=$notes" >/dev/null
fi
for id in $ancien; do
  echo "== Retrait de current sur $id"
  maj_etiquettes "$id" retirer current
done
echo "== Pose de current sur $vmid ($nom)"
maj_etiquettes "$vmid" ajouter current

# --- Contrôle final : exactement une version current dans la famille -----------------------
((simulation)) && exit 0
n="$(pve_vms | jq --arg f "$famille" '[.[] | select((.template // 0) == 1)
  | select(((.tags // "") | split(";")) as $t | ($t | index("gold")) and ($t | index($f)) and ($t | index("current")))] | length')"
[[ "$n" == 1 ]] || { echo "ANOMALIE : $n templates $famille portent current" >&2; exit 1; }
echo "$nom ($vmid) publiée : gold;$famille;current"
