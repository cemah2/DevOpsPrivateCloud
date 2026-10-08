#!/usr/bin/env bash
# outils/verifier-specs.sh — règles maison sur les spécifications cephadm (M08-E23, issues de la
# revue M08-E21). Hors ligne : ne contacte pas le cluster. Code 0 si tout passe, 1 sinon.
# Usage : outils/verifier-specs.sh [DOSSIER_SPECS]        (défaut : specs/)
# Chaque règle a un cas fautif dans tests/cas-fautifs/regleN/ (tests/tester-regles.sh).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DOSSIER="${1:-$MS_RACINE/specs}"
RESEAU_PUBLIC_REGEX='^10\.10\.30\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'
MEMOIRE_MAX_OSD=1610612736      # 1,5 Gio : 3 OSD par nœud de 6 Go, avec MON, MGR, MDS…
echecs=0

ko() { printf 'KO  règle %s : %s\n' "$1" "$2"; echecs=$((echecs + 1)); }
ok() { printf 'OK  règle %s : %s\n' "$1" "$2"; }

shopt -s nullglob
fichiers=("$DOSSIER"/*.yaml)
(( ${#fichiers[@]} > 0 )) || { ms_erreur "aucune spécification dans $DOSSIER"; exit 1; }

# Tous les documents de tous les fichiers, en un flux JSON (un objet par ligne).
docs="$(ms_yq eval-all -o=json -I=0 '.' "${fichiers[@]}" | grep -v '^null$' || true)"
type_de() { jq -c --arg t "$1" 'select(.service_type == $t)' <<<"$docs"; }

# --- Règle 1 : moniteurs en nombre impair, au moins 3 ---------------------------------------
# Nombre de moniteurs : placement.count s'il est écrit, sinon le nombre d'hôtes portant l'étiquette
# du placement (cephadm place un moniteur par hôte étiqueté).
n_mon="$(jq -s '
  (map(select(.service_type == "host"))) as $h
  | [.[] | select(.service_type == "mon") | .placement
     | if .count then .count
       elif .label then (.label as $l | [$h[] | select((.labels // []) | index($l))] | length)
       elif .hosts then (.hosts | length)
       else 0 end] | max // 0' <<<"$docs")"
if (( n_mon >= 3 && n_mon % 2 == 1 )); then ok 1 "moniteurs : $n_mon"; else ko 1 "nombre de moniteurs pair ou < 3 ($n_mon)"; fi

# --- Règle 2 : adresses des hôtes sur le réseau public (VLAN 30) -----------------------------
mauvaises="$(type_de host | jq -r '"\(.hostname) \(.addr // "")"' | while read -r h a; do
  [[ "$a" =~ $RESEAU_PUBLIC_REGEX ]] || printf '%s(%s) ' "$h" "$a"; done)"
if [[ -z "$mauvaises" ]]; then ok 2 "adresses d'hôtes sur 10.10.30.0/24"; else ko 2 "adresse hors du réseau public : $mauvaises"; fi

# --- Règle 3 : _admin sur trois hôtes au plus, tous des nœuds du cluster (ceph0N) ---------------
n_admin="$(type_de host | jq -s '[.[] | select((.labels // []) | index("_admin"))] | length')"
etrangers="$(type_de host | jq -r 'select(.hostname | test("^ceph0[0-9]$") | not) | .hostname' | tr '\n' ' ')"
if (( n_admin >= 1 && n_admin <= 3 )) && [[ -z "$etrangers" ]]; then
  ok 3 "_admin sur $n_admin hôte(s), aucun hôte étranger"
else
  ko 3 "_admin sur $n_admin hôte(s) (1 à 3 attendus) ; hôtes hors cluster : ${etrangers:-aucun}"
fi

# --- Règle 4 : ingress — VIP avec masque /24, ni certificat, ni clé, ni mot de passe ----------
mauvais_ingress="$(type_de ingress | jq -r '
  select(((.spec.virtual_ip // "") | test("/24$") | not)
         or (.spec | has("ssl_cert") or has("ssl_key") or has("monitor_password") or has("keepalived_password")))
  | .service_id')"
if [[ -z "$mauvais_ingress" ]]; then ok 4 "ingress : VIP en /24, aucun secret"; else ko 4 "ingress à corriger (VIP sans /24 ou secret dans le fichier) : $mauvais_ingress"; fi

# --- Règle 5 : aucun bloc de clé privée dans le dépôt -----------------------------------------
if grep -rlE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' "$DOSSIER" "$MS_RACINE/config" >/dev/null 2>&1; then
  ko 5 "clé privée trouvée : $(grep -rlE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' "$DOSSIER" "$MS_RACINE/config" | tr '\n' ' ')"
else
  ok 5 "aucune clé privée"
fi

# --- Règle 6 : le port d'un ingress n'est pas celui de son service RGW -------------------------
conflits=""
while read -r ing; do
  [[ -n "$ing" ]] || continue
  dorsal="$(jq -r '.spec.backend_service' <<<"$ing")"
  port_ing="$(jq -r '.spec.frontend_port' <<<"$ing")"
  port_rgw="$(type_de rgw | jq -r --arg s "$dorsal" 'select("rgw." + .service_id == $s) | .spec.rgw_frontend_port // 80')"
  [[ "$port_rgw" == "$port_ing" ]] && conflits+="$dorsal:$port_rgw "
done < <(type_de ingress)
if [[ -z "$conflits" ]]; then ok 6 "ports RGW et ingress distincts"; else ko 6 "RGW et ingress sur le même port : $conflits"; fi

# --- Règle 7 : OSD filtrés par classe, jamais « all », mémoire raisonnable ----------------------
mauvais_osd="$(type_de osd | jq -r --argjson max "$MEMOIRE_MAX_OSD" '
  select((.spec.data_devices.all // false)
         or (.spec.data_devices | has("rotational") | not)
         or (((.config.osd_memory_target // 0) | tonumber) > $max))
  | .service_id')"
if [[ -n "$(type_de osd)" && -z "$mauvais_osd" ]]; then ok 7 "OSD filtrés par classe"; else ko 7 "spécification OSD trop large ou trop gourmande : ${mauvais_osd:-aucune spécification OSD}"; fi

# --- Règle 8 : au moins deux MDS par volume ------------------------------------------------------
mds_seuls="$(type_de mds | jq -r 'select((.placement.count // 1) < 2) | .service_id')"
if [[ -z "$mds_seuls" ]]; then ok 8 "MDS redondants"; else ko 8 "un seul MDS pour : $mds_seuls"; fi

echo
if (( echecs > 0 )); then echo "$echecs règle(s) en échec."; exit 1; fi
echo "Toutes les règles passent."
