# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S09.sh — F6-S09 « Vulnérabilités et exceptions sous contrôle » (LIBRE, ferme ECA-3602/ECA-3603) :
# politique de délais sur main, mécanisme d'exception auto-expirant (contrôle CI + type EXC-V au
# registre), tableau de suivi, phrase du dépôt Kopia de Velero tirée d'OpenBao par ESO, écarts clos.
# Lecture seule (GitLab, Kubernetes par kube — jamais un Secret —, Grafana).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S09 — Vulnérabilités et exceptions sous contrôle (ECA-3602, ECA-3603)"
require_cmd curl jq

# --- Politique et mécanisme d'exception (ECA-3602) --------------------------------------------------
check_cmd "vulnerabilites.md (main) : délais par criticité, circuit d'exception, chiffrement et restauration" \
  _f6c_doc . '^vulnerabilites\.md$' 'critique' '(é|e)lev(é|e)e' 'd(é|e)lai' 'exception' 'restaur'
check_cmd "plateforme/politiques (main) : contrôle CI outils/exceptions-vuln-echues.sh" \
  _f6i_existe plateforme/politiques outils/exceptions-vuln-echues.sh
_s09_registre() {
  _f6c_fichier "$_f6c_doc_projet" docs/securite/durcissement/exceptions.md 2>/dev/null | grep -Eq 'EXC-V-[0-9]{3}'
}
check_cmd "registre des exceptions (docs/securite/durcissement/exceptions.md) : exceptions de vulnérabilité EXC-V-nnn" _s09_registre

# --- Tableau de suivi -------------------------------------------------------------------------------
_s09_tableau() { grafana_api "dashboards/uid/f6-vulnerabilites" >/dev/null 2>&1; }
check_cmd "Grafana : tableau de suivi des vulnérabilités publié (UID f6-vulnerabilites)" _s09_tableau

# --- Chiffrement de Velero (ECA-3603) ---------------------------------------------------------------
# Velero range la phrase du dépôt Kopia dans le Secret velero/velero-repo-credentials (clé
# repository-password ; défaut : une phrase connue). La correction la fait fournir par ESO depuis OpenBao :
# un ExternalSecret de l'espace velero a pour cible ce Secret. Le Secret lui-même n'est jamais lu.
if ! _f6c_api_repond; then
  skip "Velero : phrase du dépôt Kopia" "l'API ne répond pas au compte des checks"
else
  check_cmd "velero : un ExternalSecret (OpenBao) produit le Secret velero-repo-credentials (phrase du dépôt Kopia)" \
    _f6c_kq 'any(.items[]?; (.spec.target.name // .metadata.name) == "velero-repo-credentials"
                and ((.status.conditions // []) | any(.type == "Ready" and .status == "True")))' \
    -n velero externalsecrets.external-secrets.io
fi
_s09_velero_code() { _f6c_arbre plateforme/k8s composants/velero | grep -q 'externalsecret'; }
check_cmd "plateforme/k8s (main) : l'ExternalSecret de Velero est versionné (composants/velero/)" _s09_velero_code

# --- Écarts clos ------------------------------------------------------------------------------------
check_cmd "ECA-3602 clos sur main (statut, date de clôture, lot de preuve antérieur à la clôture)" _f6c_ecart_clos 3602
check_cmd "ECA-3603 clos sur main (statut, date de clôture, lot de preuve antérieur à la clôture)" _f6c_ecart_clos 3603
