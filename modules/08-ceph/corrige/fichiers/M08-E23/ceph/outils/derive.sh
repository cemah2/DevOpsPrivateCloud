#!/usr/bin/env bash
# outils/derive.sh — le cluster s'est-il écarté du dépôt ? (M08-E23). LECTURE SEULE.
# Compare :
#   - chaque service mon, mgr, osd.*, mds.*, rgw.*, ingress.*, nfs.* de « ceph orch ls --export »
#     aux spécifications de specs/ : services présents d'un seul côté, et toute valeur ÉCRITE
#     dans le dépôt qui diffère dans le cluster (comparaison « le dépôt fait foi pour ce qu'il dit » :
#     les valeurs par défaut que cephadm ajoute à l'export ne sont pas des écarts) ;
#   - les hôtes (adresse, étiquettes) à specs/hosts.yaml ;
#   - l'état déclaratif de config/cluster.yaml (outils/config-cluster.sh --verifier).
# Accès : voir lib.sh. En CI (runner01) : CEPH_ID=ci-lecture, CEPH_KEYRING=<fichier de la variable
# protégée>, CEPH_CONF=config/ceph-client.conf ; sur adm01 : CEPH_ADMIN=ceph01.
# Code 0 : aucun écart ; 1 : écart(s) ; 2 : erreur d'accès.
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($t, $d… sont des variables jq)
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TYPES='["mon","mgr","osd","mds","rgw","ingress","nfs"]'
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ecarts=0
ecart() { printf 'ÉCART  %s\n' "$*"; ecarts=$((ecarts + 1)); }

# --- Services ---------------------------------------------------------------------------------
normaliser='select(. != null) | select(.service_type as $t | '"$TYPES"' | index($t))
  | del(.status, .events, .spec.ssl_cert, .spec.ssl_key)
  | {nom: (if .service_id then .service_type + "." + .service_id else .service_type end), spec: .}'

ms_ceph orch ls --export > "$tmp/cluster.yaml" || { ms_erreur "export des services impossible"; exit 2; }
[[ -s "$tmp/cluster.yaml" ]] || { ms_erreur "export des services vide (droits mgr ?)"; exit 2; }
ms_yq eval-all -o=json -I=0 '.' "$tmp/cluster.yaml" | jq -c "$normaliser" > "$tmp/cluster.jsonl"
ms_yq eval-all -o=json -I=0 '.' "$MS_RACINE"/specs/*.yaml | jq -c "$normaliser" > "$tmp/depot.jsonl"

jq -r .nom "$tmp/cluster.jsonl" | sort -u > "$tmp/noms-cluster"
jq -r .nom "$tmp/depot.jsonl" | sort -u > "$tmp/noms-depot"
while read -r n; do ecart "service $n : dans le cluster, absent de specs/"; done < <(comm -23 "$tmp/noms-cluster" "$tmp/noms-depot")
while read -r n; do ecart "service $n : dans specs/, absent du cluster"; done < <(comm -13 "$tmp/noms-cluster" "$tmp/noms-depot")

while read -r n; do
  depot="$(jq -c --arg n "$n" 'select(.nom == $n) | .spec' "$tmp/depot.jsonl")"
  cluster="$(jq -c --arg n "$n" 'select(.nom == $n) | .spec' "$tmp/cluster.jsonl")"
  # Chaque valeur scalaire écrite dans le dépôt doit se retrouver, au même chemin, dans le cluster.
  diff_valeurs="$(jq -rn --argjson d "$depot" --argjson c "$cluster" '
    [$d | paths(scalars)] as $chemins
    | $chemins[] as $p
    | select(($c | getpath($p)) != ($d | getpath($p)))
    | "\($p | map(tostring) | join(".")) : dépôt=\($d | getpath($p)) cluster=\($c | getpath($p))"')"
  while read -r l; do [[ -n "$l" ]] && ecart "service $n : $l"; done <<<"$diff_valeurs"
done < <(comm -12 "$tmp/noms-cluster" "$tmp/noms-depot")

# --- Hôtes ------------------------------------------------------------------------------------
ms_ceph orch host ls --format json > "$tmp/hotes.json" || { ms_erreur "liste des hôtes impossible"; exit 2; }
ms_yq eval-all -o=json -I=0 'select(.service_type == "host")' "$MS_RACINE/specs/hosts.yaml" \
  | jq -s 'map({hostname, addr, labels: ((.labels // []) | sort)})' > "$tmp/hotes-depot.json"
jq 'map({hostname, addr, labels: ((.labels // []) | sort)})' "$tmp/hotes.json" > "$tmp/hotes-cluster.json"
while read -r l; do [[ -n "$l" ]] && ecart "$l"; done < <(jq -rn \
  --slurpfile d "$tmp/hotes-depot.json" --slurpfile c "$tmp/hotes-cluster.json" '
  ($d[0] | map({key: .hostname, value: .}) | from_entries) as $D
  | ($c[0] | map({key: .hostname, value: .}) | from_entries) as $C
  | (($D | keys) + ($C | keys) | unique)[] as $h
  | if ($C[$h] == null) then "hôte \($h) : dans specs/hosts.yaml, absent du cluster"
    elif ($D[$h] == null) then "hôte \($h) : dans le cluster, absent de specs/hosts.yaml"
    elif ($D[$h] != $C[$h]) then "hôte \($h) : dépôt \($D[$h] | {addr, labels} | tojson) cluster \($C[$h] | {addr, labels} | tojson)"
    else empty end')

# --- État déclaratif hors spécifications ---------------------------------------------------------
if ! "$MS_RACINE/outils/config-cluster.sh" --verifier; then
  ecart "état déclaratif (config/cluster.yaml) : voir ci-dessus"
fi

echo
if (( ecarts > 0 )); then echo "$ecarts écart(s) entre le cluster et le dépôt."; exit 1; fi
echo "Aucun écart : le cluster est conforme au dépôt."
