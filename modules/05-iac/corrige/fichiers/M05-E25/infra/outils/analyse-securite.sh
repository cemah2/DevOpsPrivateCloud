#!/usr/bin/env bash
# analyse-securite.sh — Checkov et Trivy sur le code de plateforme/infra (M05-E25).
#
# Usage (depuis n'importe où dans le dépôt) :
#   outils/analyse-securite.sh            analyse socle/, envs/ et terragrunt/composants/
#   outils/analyse-securite.sh --tests    vérifie que chaque règle maison refuse son cas fautif
#                                         (politiques/tests/<cas>/main.tf.cas + ATTENDU)
#
# Garanties :
#   - Trivy n'est lancé que si le binaire installé a l'empreinte attendue (TRIVY_EMPREINTE,
#     au format « sha256:<hex> », fixée dans .gitlab-ci.yml ; à défaut TRIVY_BINAIRE_SHA256
#     de outils/versions-outils.env). Une empreinte différente = refus (code 3) ;
#   - aucun téléchargement de règles à l'exécution : Trivy utilise les règles embarquées dans
#     son binaire (--skip-check-update) ; Checkov n'a pas de mise à jour de règles à l'exécution
#     (elles sont dans le paquet PyPI dont la version est figée) ;
#   - rapports JUnit dans rapports/ (non versionné) pour la CI.
#
# Codes retour : 0 aucune alerte, 1 au moins une alerte (ou une règle maison qui ne se déclenche
# pas en mode --tests), 2 erreur d'utilisation ou outil absent, 3 refus d'un garde-fou.
set -euo pipefail

racine="$(git rev-parse --show-toplevel)"
cd "$racine"

# shellcheck source=SCRIPTDIR/versions-outils.env
. outils/versions-outils.env

die() { printf 'analyse-securite : %s\n' "$2" >&2; exit "$1"; }

for c in checkov trivy sha256sum; do
  command -v "$c" >/dev/null || die 2 "outil introuvable : $c"
done

# --- Garde-fous sur les outils --------------------------------------------------------------
binaire_trivy="$(readlink -f "$(command -v trivy)")"
attendu="${TRIVY_EMPREINTE:-sha256:$TRIVY_BINAIRE_SHA256}"
attendu="${attendu#sha256:}"
obtenu="$(sha256sum "$binaire_trivy" | cut -d' ' -f1)"
if [[ "$obtenu" != "$attendu" ]]; then
  die 3 "empreinte inattendue pour $binaire_trivy : sha256:$obtenu (attendu sha256:$attendu). Trivy n'est PAS lancé."
fi
version_trivy="$(trivy --version 2>/dev/null | sed -n 's/^Version: //p')"
[[ "$version_trivy" == "$TRIVY_VERSION" ]] || die 3 "Trivy $version_trivy installé, $TRIVY_VERSION attendu"
version_checkov="$(checkov --version 2>/dev/null)"
[[ "$version_checkov" == "$CHECKOV_VERSION" ]] || die 3 "Checkov $version_checkov installé, $CHECKOV_VERSION attendu"

modele_junit="$(dirname "$binaire_trivy")/contrib/junit.tpl"
[[ -r "$modele_junit" ]] || die 2 "modèle JUnit de Trivy introuvable : $modele_junit (archive complète extraite ?)"

mkdir -p rapports

# Options communes de Trivy : règles embarquées, règles maison Rego sur le code brut.
trivy_opts=(config --quiet --skip-check-update
  --raw-config-scanners terraform
  --config-check politiques/trivy --check-namespaces user
  --ignorefile .trivyignore)

# checkov_lancer RAPPORT DOSSIER... — Checkov avec la configuration du dépôt ; code de Checkov.
checkov_lancer() {
  local rapport="$1"
  shift
  local args=() d
  for d in "$@"; do args+=(-d "$d"); done
  checkov --config-file "$racine/.checkov.yaml" "${args[@]}" \
    --external-modules-download-path "$racine/rapports/modules-checkov" \
    --output cli --output junitxml --output-file-path "console,$rapport"
}

# trivy_lancer RAPPORT DOSSIER — Trivy en tableau (code 1 si alerte) puis en JUnit (rapport).
trivy_lancer() {
  local rapport="$1" dossier="$2" rc=0
  trivy "${trivy_opts[@]}" --exit-code 1 "$dossier" || rc=$?
  trivy "${trivy_opts[@]}" --exit-code 0 --format template --template "@$modele_junit" \
    --output "$rapport" "$dossier" >/dev/null
  return "$rc"
}

# --- Mode --tests : chaque règle maison doit refuser son cas --------------------------------
if [[ "${1:-}" == "--tests" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  echec=0
  for cas in politiques/tests/*/; do
    nom="$(basename "$cas")"
    attendu_id="$(tr -d '[:space:]' < "$cas/ATTENDU")"
    mkdir -p "$tmp/$nom"
    cp "$cas/main.tf.cas" "$tmp/$nom/main.tf"
    sortie="$( { checkov_lancer "$tmp/$nom.checkov.xml" "$tmp/$nom" || true; \
                 trivy_lancer "$tmp/$nom.trivy.xml" "$tmp/$nom" || true; } 2>&1 )"
    if grep -Eq "(Check: ${attendu_id}:|^${attendu_id} \()" <<<"$sortie"; then
      printf 'ok   %-12s refusé par %s\n' "$nom" "$attendu_id"
    else
      printf 'KO   %-12s %s ne s'"'"'est PAS déclenchée\n' "$nom" "$attendu_id" >&2
      echec=1
    fi
  done
  exit "$echec"
fi
[[ $# -eq 0 ]] || die 2 "usage : $0 [--tests]"

# --- Analyse du dépôt -------------------------------------------------------------------------
dossiers=()
for d in socle envs terragrunt/composants; do
  if [[ -d "$d" ]]; then dossiers+=("$d"); fi
done
[[ ${#dossiers[@]} -gt 0 ]] || die 2 "aucun dossier à analyser"

rc=0
echo "== Checkov ${CHECKOV_VERSION} : ${dossiers[*]}"
checkov_lancer rapports/checkov-junit.xml "${dossiers[@]}" || rc=1
for d in "${dossiers[@]}"; do
  echo "== Trivy ${TRIVY_VERSION} : $d"
  trivy_lancer "rapports/trivy-$(tr '/' '-' <<<"$d")-junit.xml" "$d" || rc=1
done

if [[ $rc -eq 0 ]]; then
  echo "Analyse de sécurité : aucune alerte."
else
  echo "Analyse de sécurité : alertes ci-dessus (rapports JUnit dans rapports/)." >&2
fi
exit "$rc"
