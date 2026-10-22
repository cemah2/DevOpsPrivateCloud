# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c entre apostrophes
# check-E24.sh — M22-E24 « Sous le capot » : livrable sous-le-capot.md publié, qui décrit le chemin
# d'écriture et de lecture et cite des objets RÉELS du compartiment (une clé de chunk et une table
# d'index qui existent bien dans loki-k8s-par1). Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E24 — Sous le capot : ingestion, chunks et index TSDB"
require_cmd jq

_m22_e24_fichier="$(_m22p_arbre plateforme/medisphere docs/observabilite/journaux | grep -E '/sous-le-capot[^/]*\.md$' | head -n 1 || true)"
check_cmd "sous-le-capot.md publié (main, docs/observabilite/journaux/)" bash -c '[[ -n "$1" ]]' _ "$_m22_e24_fichier"
if [[ -n "$_m22_e24_fichier" ]]; then
  check_cmd "chemin d'écriture : distributeur, ingester, WAL, vidage des chunks" \
    _m22p_fichier_contient plateforme/medisphere "$_m22_e24_fichier" 'distribut' 'ingester' 'WAL' 'chunk'
  check_cmd "index TSDB, compactor et chemin de lecture (requêteur)" \
    _m22p_fichier_contient plateforme/medisphere "$_m22_e24_fichier" 'TSDB' 'compactor' 'requ[êe]teur|querier'
  _m22_e24_texte="$(_m22p_fichier_main plateforme/medisphere "$_m22_e24_fichier" 2>/dev/null || true)"
  _m22_e24_chunk="$(grep -Eo '(plateforme|mediagenda|medidoc|audit|essai)/[0-9a-f]{6,16}/[0-9a-f]+:[0-9a-f]+:[0-9a-f]+' <<<"$_m22_e24_texte" | head -n 1 || true)"
  _m22_e24_index="$(grep -Eo 'index/loki_index_[0-9]+/' <<<"$_m22_e24_texte" | head -n 1 || true)"
  check_cmd "une clé de chunk (locataire/empreinte/début:fin:somme) est citée" bash -c '[[ -n "$1" ]]' _ "$_m22_e24_chunk"
  check_cmd "une table d'index (index/loki_index_N/) est citée" bash -c '[[ -n "$1" ]]' _ "$_m22_e24_index"
  if [[ -r "$_m22p_s3_env" ]] && command -v aws >/dev/null 2>&1; then
    if [[ -n "$_m22_e24_chunk" ]]; then
      # La clé existe encore, ou a existé (versions conservées depuis M22-E16 : supprimée par la rétention).
      _m22_e24_cle_connue() {
        _m22p_s3 head-object --bucket "$_m22p_compartiment" --key "$1" | jq -e '.ContentLength > 0' >/dev/null 2>&1 ||
          _m22p_s3 list-object-versions --bucket "$_m22p_compartiment" --prefix "$1" | jq -e '(.Versions // []) | length > 0' >/dev/null 2>&1
      }
      check_cmd "la clé de chunk citée existe (ou a existé) dans loki-k8s-par1" _m22_e24_cle_connue "$_m22_e24_chunk"
    fi
  else
    skip "existence de la clé de chunk citée" "aws ou $_m22p_s3_env absent sur ce poste"
  fi
fi
