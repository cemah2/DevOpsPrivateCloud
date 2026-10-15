# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E20.sh — M17-E20 « Panne : le rendu du chart échoue » : la branche courante de
# ~/src/mediagenda-chart et toute branche locale lucas/* passent lint strict et rendus avec les valeurs
# du pipeline ; le rendu courant est accepté par le serveur (simulation). Lecture seule : chaque
# branche est exportée (git archive) dans un dossier temporaire ; la copie de travail n'est pas touchée.

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E20 — Rendu du chart"
require_cmd git helm kubectl

_E20_CH="charts/mediagenda"

# _e20_controler RÉF — 0 si le chart de RÉF passe lint --strict et se rend (recette + ci/*-values.yaml).
_e20_controler() {
  local d rc=0 f
  d="$(mktemp -d)" || return 1
  if _m17p_exporter "$_m17p_chart" "$1" "$d" && [[ -d "$d/$_E20_CH" ]]; then
    # Dépendances déjà construites dans la copie de travail (charts/ ignoré par Git).
    [[ -d "$_m17p_chart/$_E20_CH/charts" ]] && cp -r "$_m17p_chart/$_E20_CH/charts" "$d/$_E20_CH/"
    helm lint --strict "$d/$_E20_CH" --set medisphere.environnement=recette >/dev/null 2>&1 || rc=1
    helm template mediagenda "$d/$_E20_CH" -n mediagenda-recette --set medisphere.environnement=recette >/dev/null 2>&1 || rc=1
    for f in "$d/$_E20_CH"/ci/*-values.yaml; do
      [[ -e "$f" ]] || continue
      helm template mediagenda "$d/$_E20_CH" -n wb-ct -f "$f" >/dev/null 2>&1 || rc=1
    done
  else
    rc=1
  fi
  rm -rf -- "$d"
  return "$rc"
}

# _e20_serveur — le rendu de HEAD est accepté par le serveur d'API (simulation : --dry-run=server).
_e20_serveur() {
  helm template mediagenda "$_m17p_chart/$_E20_CH" -n mediagenda-dev --set medisphere.environnement=dev --no-hooks --skip-tests 2>/dev/null \
    | _m17p_kadmin apply --dry-run=server --server-side --force-conflicts --field-manager=wb-checks -n mediagenda-dev -f - >/dev/null
}

if git -C "$_m17p_chart" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _e20_courante="$(git -C "$_m17p_chart" symbolic-ref --quiet --short HEAD 2>/dev/null)" || _e20_courante="HEAD"
  check_cmd "branche courante ($_e20_courante) : lint strict et rendus du pipeline" _e20_controler HEAD
  check_cmd "branche courante : rendu accepté par le serveur d'API (simulation)" _e20_serveur
  for _e20_b in $(git -C "$_m17p_chart" for-each-ref --format='%(refname:short)' 'refs/heads/lucas/*' 2>/dev/null); do
    check_cmd "branche $_e20_b : lint strict et rendus du pipeline" _e20_controler "$_e20_b"
  done
else
  check_cmd "copie de travail $_m17p_chart présente" false
fi
check_cmd "panne M17-E20 close (lab/bin/break 17 20 --annuler après réparation)" _m17p_panne_close E20
