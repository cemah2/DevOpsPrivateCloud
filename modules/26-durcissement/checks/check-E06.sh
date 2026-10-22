# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E06.sh — M26-E06 : Pod Security Admission : auditer puis imposer restricted
# À lancer depuis adm01. Lecture seule : espaces du cluster (étiquettes et annotations) par le compte des
# checks ; outil et registre par l'API de GitLab. Aucun essai « --dry-run=server » ici : il exige le droit
# de modifier les espaces, que le compte des checks n'a pas (et ne doit pas avoir).

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E06 — Pod Security Admission : auditer puis imposer restricted"
require_cmd jq curl kubectl

_m26d_e06_ns="$(_m26d_k get namespaces -o json)"
if [[ -z "$_m26d_e06_ns" ]]; then
  _ko "Espaces du cluster illisibles par le compte des checks (kubeconfig wb-checks, API joignable ?)"
  return 0
fi

# Espaces contrôlés : tous sauf ceux du cluster lui-même.
_m26d_e06_filtre='[.items[] | select(.metadata.name | test("^(kube-system|kube-public|kube-node-lease)$") | not)]'
_m26d_e06_p='pod-security.kubernetes.io'

# _m26d_e06_liste FILTRE_SUR_UN_ESPACE — noms des espaces contrôlés pour lesquels le filtre est vrai.
_m26d_e06_liste() {
  jq -r --arg p "$_m26d_e06_p" "$_m26d_e06_filtre | .[] | select($1) | .metadata.name" <<<"$_m26d_e06_ns" 2>/dev/null | paste -sd' ' -
}

# --- 1. Toutes les étiquettes, partout ------------------------------------------------------------------
_m26d_e06_sans="$(_m26d_e06_liste '(.metadata.labels // {}) as $l | ($l[$p + "/enforce"] == null or $l[$p + "/audit"] == null or $l[$p + "/warn"] == null)')"
if [[ -z "$_m26d_e06_sans" ]]; then
  _ok "Tous les espaces (hors kube-system, kube-public, kube-node-lease) portent enforce, audit et warn"
else
  _ko "Espaces sans les trois étiquettes Pod Security (enforce, audit, warn) : $_m26d_e06_sans"
fi

# --- 2. restricted en version figée -----------------------------------------------------------------
_m26d_e06_version="$(_m26d_e06_liste '(.metadata.labels // {}) as $l | $l[$p + "/enforce"] == "restricted" and $l[$p + "/enforce-version"] != "v1.36"')"
if [[ -z "$_m26d_e06_version" ]]; then
  _ok "Espaces en restricted : version d'application figée à v1.36"
else
  _ko "Espaces en restricted sans enforce-version v1.36 (absente, latest ou ancienne) : $_m26d_e06_version"
fi

# --- 3. Les exceptions sont écrites ---------------------------------------------------------------------
_m26d_e06_exc="$(_m26d_e06_liste '(.metadata.labels // {})[$p + "/enforce"] as $e | $e != null and $e != "restricted"')"
_m26d_e06_exc_sans="$(_m26d_e06_liste '(.metadata.labels // {}) as $l | ($l[$p + "/enforce"] // "restricted") != "restricted"
   and ((((.metadata.annotations // {})["medisphere.internal/exception-psa"] // "") | length) == 0
        or $l[$p + "/audit"] != "restricted" or $l[$p + "/warn"] != "restricted")')"
if [[ -z "$_m26d_e06_exc_sans" ]]; then
  _ok "Exceptions (${_m26d_e06_exc:-aucune}) : annotation medisphere.internal/exception-psa, audit et warn en restricted"
else
  _ko "Exceptions non écrites (annotation exception-psa absente, ou audit/warn pas en restricted) : $_m26d_e06_exc_sans"
fi

# --- 4. Les espaces des équipes n'ont jamais d'exception -------------------------------------------------
_m26d_e06_equipes="$(_m26d_e06_liste '.metadata.name | test("^(mediagenda|medidoc)-")')"
if [[ -z "$_m26d_e06_equipes" ]]; then
  _ko "Aucun espace mediagenda-* ni medidoc-* trouvé (compte des checks limité ?)"
else
  check_cmd "Espaces des équipes ($_m26d_e06_equipes) : tous en enforce restricted" \
    _m26d_json "$_m26d_e06_ns" "[.items[] | select(.metadata.name | test(\"^(mediagenda|medidoc)-\"))
      | .metadata.labels[\"$_m26d_e06_p/enforce\"]] | all(. == \"restricted\")"
fi
check_cmd "Espace default verrouillé en restricted" \
  _m26d_json "$_m26d_e06_ns" "[.items[] | select(.metadata.name == \"default\") | .metadata.labels[\"$_m26d_e06_p/enforce\"]] == [\"restricted\"]"

# --- 5. Outil et registre -----------------------------------------------------------------------------
check_cmd "plateforme/k8s : outils/psa-inventaire.sh sur main (avec l'option --essai)" \
  _m26d_contient "$(_m26d_contenu_main plateforme/k8s outils/psa-inventaire.sh)" 'dry-run=server'
_m26d_e06_doc="$(_m26d_doc pod-security.md)"
if [[ -z "$_m26d_e06_doc" ]]; then
  _ko "plateforme/medisphere : $_M26D_DOC/pod-security.md absent de main"
else
  _ok "plateforme/medisphere : $_M26D_DOC/pod-security.md présent sur main"
  _m26d_e06_absents=""
  for _m26d_e06_e in $_m26d_e06_exc; do
    grep -qF -- "$_m26d_e06_e" <<<"$_m26d_e06_doc" || _m26d_e06_absents+=" $_m26d_e06_e"
  done
  if [[ -z "$_m26d_e06_absents" ]]; then
    _ok "pod-security.md : chaque espace en exception figure au registre"
  else
    _ko "pod-security.md : espaces en exception absents du registre :$_m26d_e06_absents"
  fi
fi
