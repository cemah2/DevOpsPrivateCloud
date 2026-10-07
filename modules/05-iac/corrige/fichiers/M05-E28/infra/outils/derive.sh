#!/usr/bin/env bash
# derive.sh — détection de dérive des configurations OpenTofu de plateforme/infra (M05-E28).
#
# Usage (depuis le dépôt, accès chargés : « . outils/charger-acces.sh » sur adm01) :
#   outils/derive.sh [-r DOSSIER_RAPPORTS] [CONFIGURATION…]
#   CONFIGURATION : socle, envs/lab-m05, envs/recette-m05 (par défaut : les trois)
#
# Pour chaque configuration, deux plans en lecture (rien n'est appliqué, aucun état écrit) :
#   1. plan -refresh-only : l'ÉTAT comparé à la RÉALITÉ  → DÉRIVE (on a touché hors d'OpenTofu)
#   2. plan ordinaire     : le CODE comparé à la RÉALITÉ → ÉCART DE CODE (fusionné, pas appliqué)
#      (seulement si aucune dérive : une dérive apparaît aussi dans ce plan, on ne la compte
#      pas deux fois)
# Les plans prennent le verrou de l'état (attente 10 min au plus) : jamais pendant un apply, et le
# verrou est rendu à la fin. Plans enregistrés dans un dossier temporaire (chiffrés, E27), effacés.
#
# Rapports (sans AUCUNE valeur : seulement des adresses et des NOMS d'attributs) :
#   <rapports>/derive.json   détail par configuration
#   <rapports>/derive.md     lisible (repris dans le ticket)
#   <rapports>/derive-junit.xml   un cas par configuration, en échec si non conforme
#
# Codes retour : 0 conforme · 2 dérive (au moins une configuration) · 3 écart de code seulement
#                1 erreur (plan impossible : backend, droits, réseau…) — l'erreur l'emporte.
set -euo pipefail

racine="$(git rev-parse --show-toplevel)"
rapports="$racine/rapports"
if [[ "${1:-}" == "-r" ]]; then rapports="$2"; shift 2; fi
configurations=("$@")
[[ ${#configurations[@]} -gt 0 ]] || configurations=(socle envs/lab-m05 envs/recette-m05)

for c in tofu jq; do command -v "$c" >/dev/null || { echo "derive : $c introuvable" >&2; exit 1; }; done
export TF_IN_AUTOMATION=1 TF_INPUT=0
mkdir -p "$rapports"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# Attributs qui diffèrent entre before et after (noms seulement, jamais les valeurs).
# shellcheck disable=SC2016  # programme jq, pas une expansion shell
jq_derives='[.resource_drift[]? | {adresse: .address,
  attributs: ([(.change.before // {}), (.change.after // {})] as [$a, $b]
              | [($a | keys_unsorted[]), ($b | keys_unsorted[])] | unique
              | map(select($a[.] != $b[.])))}]'
jq_ecarts='[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])
  | {adresse: .address, actions: .change.actions}]'

resultats="[]"
for conf in "${configurations[@]}"; do
  dossier="$racine/$conf"
  journal="$tmp/$(tr '/' '_' <<<"$conf").log"
  statut="conforme" derives="[]" ecarts="[]"

  if ! (cd "$dossier" && tofu init -input=false -lockfile=readonly -no-color) >"$journal" 2>&1; then
    statut="erreur"
  else
    rc=0
    (cd "$dossier" && tofu plan -refresh-only -input=false -no-color -lock-timeout=10m \
        -detailed-exitcode -out="$tmp/derive.tfplan") >>"$journal" 2>&1 || rc=$?
    case "$rc" in
      0) ;;
      2) statut="derive"
         derives="$(cd "$dossier" && tofu show -json "$tmp/derive.tfplan" | jq -c "$jq_derives")" ;;
      *) statut="erreur" ;;
    esac
    if [[ "$statut" == "conforme" ]]; then
      rc=0
      (cd "$dossier" && tofu plan -input=false -no-color -lock-timeout=10m \
          -detailed-exitcode -out="$tmp/plan.tfplan") >>"$journal" 2>&1 || rc=$?
      case "$rc" in
        0) ;;
        2) statut="ecart"
           ecarts="$(cd "$dossier" && tofu show -json "$tmp/plan.tfplan" | jq -c "$jq_ecarts")" ;;
        *) statut="erreur" ;;
      esac
    fi
    rm -f "$tmp/derive.tfplan" "$tmp/plan.tfplan"
  fi

  # En cas d'erreur, les dernières lignes du journal d'OpenTofu (messages d'erreur, sans état).
  erreur=""
  if [[ "$statut" == "erreur" ]]; then erreur="$(grep -E 'Error|Erreur' "$journal" | tail -n 5 || true)"; fi
  resultats="$(jq -c --arg c "$conf" --arg s "$statut" --argjson d "$derives" --argjson e "$ecarts" \
    --arg err "$erreur" '. + [{configuration: $c, statut: $s, derives: $d, ecarts: $e, erreur: $err}]' \
    <<<"$resultats")"
  printf '%-18s %s\n' "$conf" "$statut"
done

# --- Rapports -------------------------------------------------------------------------------
date_detection="$(date -Iseconds)"
jq --arg d "$date_detection" '{date: $d, configurations: .}' <<<"$resultats" > "$rapports/derive.json"

{
  echo "# Détection de dérive — $date_detection"
  echo
  echo "| Configuration | Résultat | Détail |"
  echo "|---|---|---|"
  jq -r '.[] | "| `\(.configuration)` | \(.statut) | " + (
      if .statut == "derive" then (.derives | map("`\(.adresse)` (\(.attributs | join(", ")))") | join("<br>"))
      elif .statut == "ecart" then (.ecarts | map("`\(.adresse)` : \(.actions | join("+"))") | join("<br>"))
      elif .statut == "erreur" then (.erreur | gsub("\n"; "<br>"))
      else "—" end) + " |"' <<<"$resultats"
  echo
  echo "dérive = modifiée hors d'OpenTofu (plan -refresh-only) ; écart = code fusionné non appliqué."
} > "$rapports/derive.md"

jq -r --arg d "$date_detection" '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;");
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
  "<testsuite name=\"derive\" timestamp=\"\($d)\" tests=\"\(length)\" failures=\"\(map(select(.statut != "conforme")) | length)\">",
  (.[] | "  <testcase classname=\"derive\" name=\"\(.configuration | esc)\">"
     + (if .statut == "conforme" then ""
        else "<failure message=\"\(.statut)\">\((.derives + .ecarts) | map(.adresse) | join(", ") | esc)\((.erreur // "") | esc)</failure>" end)
     + "</testcase>"),
  "</testsuite>"' <<<"$resultats" > "$rapports/derive-junit.xml"

# --- Code retour ------------------------------------------------------------------------------
if jq -e 'any(.[]; .statut == "erreur")' <<<"$resultats" >/dev/null; then exit 1; fi
if jq -e 'any(.[]; .statut == "derive")' <<<"$resultats" >/dev/null; then exit 2; fi
if jq -e 'any(.[]; .statut == "ecart")' <<<"$resultats" >/dev/null; then exit 3; fi
exit 0
