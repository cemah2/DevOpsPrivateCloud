# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts de « bash -c » entre apostrophes (arguments en $1)
# check-E18.sh — M13-E18 « Alerte CVE critique » (après les 60 minutes)
# Lecture seule : compte-rendu (API GitLab) ; pour chaque digest cité dans le compte-rendu, artefact,
# signature et analyse (API Harbor) et SBOM attesté (cosign verify-attestation avec le robot des checks).
# Le contrôle ne juge pas l'inventaire (auto-évaluation avec le corrigé) : il vérifie les preuves.

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E18 — Alerte CS-2026-0412"
require_cmd jq curl cosign

_m13_e18_cr="$(_m13p_fichier_main plateforme/medisphere docs/registre/alertes/CS-2026-0412.md 2>/dev/null)" || _m13_e18_cr=""
check_cmd "docs/registre/alertes/CS-2026-0412.md publié sur main" test -n "$_m13_e18_cr"
check_cmd "le compte-rendu a ses sections (inventaire, décisions, images corrigées, reste à faire)" \
  bash -c 'grep -Eqi "inventaire" <<<"$1" && grep -Eqi "d.cision" <<<"$1" && grep -Eqi "corrig" <<<"$1" && grep -Eqi "reste" <<<"$1"' _ "$_m13_e18_cr"
check_cmd "il nomme le composant (prometheus-client) et le faux ami Go (client_golang)" \
  bash -c 'grep -Eqi "prometheus[-_]client" <<<"$1" && grep -Eqi "client_golang" <<<"$1"' _ "$_m13_e18_cr"

# Une image corrigée : un dépôt applicatif dont la dernière version v* est citée (digest) dans le
# compte-rendu, signée, analysée sans critique, et dont le SBOM attesté ne contient plus
# prometheus-client >= 0.26.
_m13_e18_corrigee() {
  local app a d img paquets v
  for app in mediagenda-api medinotif; do
    a="$(_m13p_derniere_version medisphere "$app")" || continue
    d="$(jq -r '.digest // empty' <<<"$a")"
    if [[ -z "$d" ]] || ! grep -qF "$d" <<<"$_m13_e18_cr"; then continue; fi
    if ! _m13p_signee "$a" || ! _m13p_sans_critique "$a"; then continue; fi
    img="$_M13P_REGISTRE_NOM/medisphere/$app@$d"
    paquets="$(_m13p_attestation_sbom "$img")" || continue
    v="$(awk '$1 == "prometheus-client" || $1 == "prometheus_client" { print $2; exit }' <<<"$paquets")"
    # Absent du SBOM, ou version 0.25.x et antérieure.
    if [[ -z "$v" ]] || [[ "$(printf '%s\n0.26.0\n' "$v" | sort -V | head -n 1)" == "$v" && "$v" != 0.26.0 ]]; then
      echo "$app"
      return 0
    fi
  done
  return 1
}
check_cmd "une image corrigée (mediagenda-api ou medinotif) : digest dans le compte-rendu, signée, analysée, SBOM attesté sans prometheus-client >= 0.26" \
  _m13_e18_corrigee
