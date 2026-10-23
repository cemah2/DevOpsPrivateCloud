# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S09.sh — F6-S09 « Vulnérabilités et exceptions sous contrôle » (LIBRE, ferme ECA-3602/ECA-3603) :
# politique de délais sur main, mécanisme d'exception auto-expirant (contrôle CI + type EXC-V au
# registre), tableau de suivi, Velero chiffré (dépôt Kopia alimenté par ESO), écarts clos.
# Lecture seule (GitLab, Kubernetes par kube, Grafana).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S09 — Vulnérabilités et exceptions sous contrôle (ECA-3602, ECA-3603)"
require_cmd curl jq kubectl

# --- Politique et mécanisme d'exception (ECA-3602) --------------------------------------------------
check_cmd "vulnerabilites.md (main) : délais par criticité et circuit d'exception" \
  _f6i_doc . '^vulnerabilites\.md$' 'critique' '(é|e)lev(é|e)e' 'd(é|e)lai' 'exception'
check_cmd "contrôle CI exceptions-vuln-echues.sh présent sur main (plateforme/politiques)" \
  _f6i_fichier_existe plateforme/politiques outils/exceptions-vuln-echues.sh
# Le type EXC-V (exception de vulnérabilité) est décrit dans le registre des exceptions (M26).
_s09_registre() {
  _f6i_fichier plateforme/medisphere docs/securite/durcissement/exceptions.md 2>/dev/null | grep -Eq 'EXC-V-'
}
check_cmd "registre des exceptions : type EXC-V (exception de vulnérabilité) introduit" _s09_registre

# --- Tableau de suivi -------------------------------------------------------------------------------
_s09_tableau() {
  grafana_api "search?query=vuln%C3%A9rabilit" 2>/dev/null | jq -e 'any(.[]?; (.uid // "") == "f6-vulnerabilites")' >/dev/null 2>&1 \
    || grafana_api "dashboards/uid/f6-vulnerabilites" >/dev/null 2>&1
}
check_cmd "tableau de suivi des vulnérabilités (UID f6-vulnerabilites) publié" _s09_tableau

# --- Chiffrement de Velero (ECA-3603) ---------------------------------------------------------------
# Le dépôt Kopia est chiffré : un ExternalSecret alimente la phrase de passe du dépôt depuis OpenBao.
_s09_velero_es="$(kube -n velero get externalsecrets.external-secrets.io -o json 2>/dev/null || echo '{}')"
check_cmd "espace velero : un ExternalSecret alimente la phrase de passe du dépôt (chiffrement Kopia)" \
  _f6i_json "$_s09_velero_es" 'any(.items[]?; (.spec.target.name // "" | test("repo|credential|depot"; "i"))
    or any(.spec.data[]?; (.secretKey // "" | test("password|phrase|passphrase"; "i"))))'
_s09_velero_code() { _f6i_arbre plateforme/k8s composants/velero | grep -q .; }
check_cmd "planifications Velero présentes sur main (plateforme/k8s/composants/velero)" _s09_velero_code
# Le secret de dépôt existe et n'est pas vide (ESO l'a bien rempli) — lecture des métadonnées seulement.
_s09_secret_depot() {
  kube -n velero get secret velero-repo-credentials -o json 2>/dev/null \
    | jq -e '(.data | length) > 0' >/dev/null 2>&1
}
check_cmd "secret du dépôt Velero présent (rempli par ESO)" _s09_secret_depot

# --- Écarts clos ------------------------------------------------------------------------------------
check_cmd "ECA-3602 clos sur main avec preuve" _f6i_doc ecarts '^ECA-3602' 'statut:\s*clos' 'preuve'
check_cmd "ECA-3603 clos sur main avec preuve" _f6i_doc ecarts '^ECA-3603' 'statut:\s*clos' 'preuve'
