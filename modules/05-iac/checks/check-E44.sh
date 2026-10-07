# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
# check-E44.sh — M05-E44 « Sous le capot : graphe, providers et état » : compte rendu et graphe
# publiés dans le dépôt de documentation, aucune copie d'état en clair ni journal de trace laissé
# derrière soi. Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E44 — Sous le capot : graphe, providers et état"
require_cmd git

_m05_e44_dir="$_m05x_depot/docs/socle/analyses"
_m05_e44_cr="$_m05_e44_dir/opentofu-sous-le-capot.md"

# Copies d'état en clair hors des endroits prévus (le bac à sable ~/m05/e44 est permis).
_m05_e44_pas_detat() {
  [[ -z "$(find "$_m05x_infra" "$_m05x_depot" "$HOME" -maxdepth 4 \
    \( -path "$HOME/m05/e44" -o -name .terraform -o -name .git \) -prune -o \
    -type f \( -name '*.tfstate' -o -name '*.tfstate.backup' -o -name '*.tfstate.json' \) -print 2>/dev/null)" ]]
}
_m05_e44_pas_de_trace() {
  ! grep -lqs -m1 '\[TRACE\] provider' "$HOME"/*.log "$HOME"/*/*.log /tmp/*.log 2>/dev/null
}

check_cmd "compte rendu docs/socle/analyses/opentofu-sous-le-capot.md présent" test -s "$_m05_e44_cr"
check_output "compte rendu : section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m05_e44_cr"
check_cmd "compte rendu : graphe, protocole des providers, état (serial, lineage) et lock traités" \
  bash -c 'for m in "graph" "gRPC" "serial" "lineage" "zh:" "h1:"; do grep -qiF -- "$m" "$1" || exit 1; done' _ "$_m05_e44_cr"
check_cmd "compte rendu : au moins 10 réponses numérotées" \
  bash -c '[ "$(sed -n "/^## Réponses aux questions/,\$p" "$1" | grep -cE "^(#+ *)?(Q ?)?[0-9]+[.)]")" -ge 10 ]' _ "$_m05_e44_cr"
check_cmd "graphe du socle publié (graphe-socle.svg ou .dot)" \
  bash -c 'ls "$1"/graphe-socle.svg "$1"/graphe-socle.dot >/dev/null 2>&1 || ls "$1"/graphe-socle.* >/dev/null 2>&1' _ "$_m05_e44_dir"
check_cmd "compte rendu et graphe commités" \
  bash -c 'cd "$1" && git ls-files --error-unmatch opentofu-sous-le-capot.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- .)" ]' _ "$_m05_e44_dir"
check_cmd "aucune copie d'état en clair laissée dans ~ , ~/src/infra ou ~/medisphere" _m05_e44_pas_detat
check_cmd "aucun journal de trace OpenTofu (TF_LOG=trace) laissé dans ~ ou /tmp" _m05_e44_pas_de_trace
check_cmd "le dépôt de documentation ne contient aucun état OpenTofu (« lineage »)" \
  bash -c '! git -C "$1" grep -qI "\"lineage\"" 2>/dev/null' _ "$_m05x_depot"
