#!/usr/bin/env bash
# outils/config-cluster.sh — état déclaratif de ceph-par1 hors spécifications (config/cluster.yaml).
# Usage : outils/config-cluster.sh --verifier        lecture seule, code 1 si écart
#         outils/config-cluster.sh --appliquer [--oui] crée règles et profils manquants, règle
#                                                     seuils, options, paramètres des pools EXISTANTS
# Ne crée ni ne supprime jamais de pool ; ne déplace jamais d'hôte (hiérarchie : vérifiée seulement).
# Un changement de règle CRUSH d'un pool déplace des données : un pool à la fois, HEALTH_OK entre deux.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-}"; OUI="${2:-}"
[[ "$MODE" == --verifier || "$MODE" == --appliquer ]] || { echo "Usage : $0 --verifier | --appliquer [--oui]" >&2; exit 2; }
CONF="$MS_RACINE/config/cluster.yaml"
cfg() { ms_yq -o=json -I=0 "$1" "$CONF"; }
ecarts=0
ecart() { printf '  écart : %s\n' "$*"; ecarts=$((ecarts + 1)); }
agir() {   # agir DESCRIPTION COMMANDE… — en mode --appliquer seulement, après confirmation
  [[ "$MODE" == --appliquer ]] || return 0
  if [[ "$OUI" == --oui ]] || ms_confirmer "  → $1 ?"; then "${@:2}"; fi
}
attendre_sante() {
  local i
  for i in $(seq 1 120); do
    ms_ceph health 2>/dev/null | grep -q '^HEALTH_OK' && return 0
    (( i % 6 == 0 )) && ms_info "  … attente de HEALTH_OK ($((i * 10)) s)"
    sleep 10
  done
  ms_erreur "HEALTH_OK non atteint en 20 minutes : arrêt"; return 1
}

regles="$(ms_ceph osd crush rule dump --format json)"
dump="$(ms_ceph osd dump --format json)"
id_regle() { jq -r --arg r "$1" '.[] | select(.rule_name == $r) | .rule_id' <<<"$regles"; }

echo "== Seuils"
for s in nearfull backfillfull full; do
  voulu="$(cfg ".seuils.$s")"; reel="$(jq -r ".${s}_ratio" <<<"$dump")"
  if awk -v a="$voulu" -v b="$reel" 'BEGIN { exit !((a - b) < 0.001 && (b - a) < 0.001) }'; then :; else
    ecart "${s}_ratio = $reel (voulu $voulu)"
    agir "ceph osd set-${s}-ratio $voulu" ms_ceph osd "set-${s}-ratio" "$voulu"
  fi
done

echo "== Règles CRUSH"
while read -r r; do
  nom="$(jq -r .nom <<<"$r")"; racine="$(jq -r .racine <<<"$r")"; dom="$(jq -r .domaine <<<"$r")"; cl="$(jq -r .classe <<<"$r")"
  existante="$(jq -c --arg r "$nom" '.[] | select(.rule_name == $r)' <<<"$regles")"
  if [[ -z "$existante" ]]; then
    ecart "règle $nom absente"
    agir "créer la règle $nom ($racine, $dom, $cl)" ms_ceph osd crush rule create-replicated "$nom" "$racine" "$dom" "$cl"
  elif ! jq -e --arg t "$racine~$cl" --arg d "$dom" \
      '(.steps | map(select(.op == "take")) | .[0].item_name == $t) and (.steps | map(select(.op | test("chooseleaf"))) | .[0].type == $d)' \
      <<<"$existante" >/dev/null; then
    ecart "règle $nom : étapes différentes de ($racine, $dom, $cl) — correction manuelle (fiche de changement)"
  fi
done < <(cfg '.crush.regles[]')

echo "== Hiérarchie (vérifiée seulement)"
arbre="$(ms_ceph osd tree --format json)"
while read -r b; do
  nom="$(jq -r .nom <<<"$b")"; parent="$(jq -r .parent <<<"$b")"
  reel="$(jq -r --arg n "$nom" '. as $t | ($t.nodes[] | select(.name == $n) | .id) as $id
          | [$t.nodes[] | select((.children // []) | index($id)) | .name][0] // "aucun"' <<<"$arbre")"
  [[ "$reel" == "$parent" ]] || ecart "bucket $nom : parent $reel (voulu $parent)"
done < <(cfg '.crush.hierarchie[]')

echo "== Profils EC"
while read -r p; do
  nom="$(jq -r .nom <<<"$p")"; params="$(jq -r .parametres <<<"$p")"
  reel="$(ms_ceph osd erasure-code-profile get "$nom" --format json 2>/dev/null || true)"
  if [[ -z "$reel" ]]; then
    ecart "profil $nom absent"
    # shellcheck disable=SC2086  # les paramètres « k=2 m=1 … » sont des mots distincts
    agir "créer le profil $nom" ms_ceph osd erasure-code-profile set "$nom" $params
  else
    for kv in $params; do
      k="${kv%%=*}"; v="${kv#*=}"
      [[ "$(jq -r --arg k "$k" '.[$k] // ""' <<<"$reel")" == "$v" ]] || ecart "profil $nom : $k différent de $v (un profil ne se modifie pas : nouveau profil et migration)"
    done
  fi
done < <(cfg '.profils_ec[]')

echo "== Pools"
pools="$(ms_ceph osd pool ls detail --format json)"
regles="$(ms_ceph osd crush rule dump --format json)"
while read -r p; do
  nom="$(jq -r .nom <<<"$p")"
  reel="$(jq -c --arg n "$nom" '.[] | select(.pool_name == $n)' <<<"$pools")"
  [[ -n "$reel" ]] || { ecart "pool $nom absent (création = geste humain)"; continue; }
  regle="$(jq -r '.regle // empty' <<<"$p")"
  if [[ -n "$regle" ]]; then
    id="$(id_regle "$regle")"
    if [[ "$(jq -r .crush_rule <<<"$reel")" != "$id" ]]; then
      ecart "pool $nom : règle $(jq -r .crush_rule <<<"$reel") (voulu $regle = ${id:-?})"
      if [[ "$MODE" == --appliquer ]] && { [[ "$OUI" == --oui ]] || ms_confirmer "  → pool $nom → règle $regle (déplace des données) ?"; }; then
        ms_ceph osd pool set "$nom" crush_rule "$regle"
        attendre_sante
      fi
    fi
  fi
  app="$(jq -r '.application // empty' <<<"$p")"
  if [[ -n "$app" ]] && ! jq -e --arg a "$app" '.application_metadata | has($a)' <<<"$reel" >/dev/null; then
    ecart "pool $nom : application $app absente"
    agir "pool $nom : application $app" ms_ceph osd pool application enable "$nom" "$app"
  fi
  quota="$(jq -r '.quota_octets // empty' <<<"$p")"
  if [[ -n "$quota" && "$(jq -r '.quota_max_bytes // 0' <<<"$reel")" != "$quota" ]]; then
    ecart "pool $nom : quota $(jq -r '.quota_max_bytes // 0' <<<"$reel") (voulu $quota)"
    agir "pool $nom : quota $quota" ms_ceph osd pool set-quota "$nom" max_bytes "$quota"
  fi
  ratio="$(jq -r '.target_size_ratio // empty' <<<"$p")"
  if [[ -n "$ratio" ]] && ! awk -v a="$ratio" -v b="$(jq -r '.options.target_size_ratio // 0' <<<"$reel")" 'BEGIN { exit !((a - b) < 0.001 && (b - a) < 0.001) }'; then
    ecart "pool $nom : target_size_ratio (voulu $ratio)"
    agir "pool $nom : target_size_ratio $ratio" ms_ceph osd pool set "$nom" target_size_ratio "$ratio"
  fi
  if [[ "$(jq -r '.ec_overwrites // false' <<<"$p")" == true ]] && ! jq -e '.flags_names | test("ec_overwrites")' <<<"$reel" >/dev/null; then
    ecart "pool $nom : allow_ec_overwrites absent"
    agir "pool $nom : allow_ec_overwrites" ms_ceph osd pool set "$nom" allow_ec_overwrites true
  fi
done < <(cfg '.pools[]')

echo "== Options (ceph config)"
while read -r o; do
  qui="$(jq -r .qui <<<"$o")"; opt="$(jq -r .option <<<"$o")"; val="$(jq -r .valeur <<<"$o")"
  [[ "$val" == regle:* ]] && val="$(id_regle "${val#regle:}")"
  reel="$(ms_ceph config get "$qui" "$opt" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$reel" != "$val" ]]; then
    ecart "$qui/$opt = ${reel:-?} (voulu $val)"
    agir "ceph config set $qui $opt $val" ms_ceph config set "$qui" "$opt" "$val"
  fi
done < <(cfg '.options[]')

echo
if (( ecarts > 0 )); then
  echo "$ecarts écart(s) avec config/cluster.yaml."
  [[ "$MODE" == --verifier ]] && exit 1
  echo "Relance « $0 --verifier » pour contrôler le résultat."
else
  echo "Conforme à config/cluster.yaml."
fi
