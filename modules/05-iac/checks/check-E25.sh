# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E25.sh — M05-E25 « Analyse de sécurité du code : Checkov et Trivy »
# Outils installés à la version et à l'empreinte attendues sur adm01, configuration, règles maison
# et cas de test sur main, hook pre-push installé. Les analyseurs ne sont PAS relancés ici
# (ils écrivent dans rapports/ : un contrôle est en lecture seule) ; la CI le fait (E26).

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E25 — Checkov et Trivy"
require_cmd jq curl sha256sum

# _m05_e25_valeur CLÉ — valeur de CLÉ dans outils/versions-outils.env de main (vide si absente).
_m05_e25_valeur() { _m05p_contenu_main outils/versions-outils.env | sed -n "s/^$1=//p" | head -n 1; }

# _m05_e25_trivy_empreinte — le binaire trivy installé a l'empreinte de versions-outils.env.
_m05_e25_trivy_empreinte() {
  local attendu bin
  attendu="$(_m05_e25_valeur TRIVY_BINAIRE_SHA256)"
  [[ "$attendu" =~ ^[0-9a-f]{64}$ ]] || return 1
  bin="$(readlink -f "$(command -v trivy)")" || return 1
  [[ "$(sha256sum "$bin" | cut -d' ' -f1)" == "$attendu" ]]
}

# _m05_e25_checkov_version — checkov --version égale CHECKOV_VERSION de versions-outils.env.
_m05_e25_checkov_version() {
  local attendu
  attendu="$(_m05_e25_valeur CHECKOV_VERSION)"
  [[ "$attendu" =~ ^3\.3\. ]] && [[ "$(checkov --version 2>/dev/null)" == "$attendu" ]]
}

title "Outils sur adm01"
check_output "trivy 0.75.0 installé" '^Version: 0\.75\.0$' trivy --version
check_cmd "trivy : empreinte du binaire = TRIVY_BINAIRE_SHA256 de outils/versions-outils.env" _m05_e25_trivy_empreinte
check_cmd "checkov : version 3.3.x = CHECKOV_VERSION de outils/versions-outils.env" _m05_e25_checkov_version
check_cmd "trivy : modèle JUnit présent à côté du binaire (archive complète extraite)" \
  bash -c 'test -r "$(dirname "$(readlink -f "$(command -v trivy)")")/contrib/junit.tpl"'

title "Configuration et règles (branche main)"
check_cmd "outils/versions-outils.env : version et empreintes de Trivy" \
  _m05p_main_contient outils/versions-outils.env '^TRIVY_VERSION=0\.75\.0' '^TRIVY_ARCHIVE_SHA256=[0-9a-f]{64}' '^TRIVY_BINAIRE_SHA256=[0-9a-f]{64}'
check_cmd ".checkov.yaml : règles maison chargées" _m05p_main_contient .checkov.yaml 'external-checks-dir'
_m05_e25_exceptions_justifiees() {
  local c
  c="$(_m05p_contenu_main .checkov.yaml)"
  [[ -n "$c" ]] || return 1
  # Aucune exception, ou chaque ligne « - CKV… » de skip-check est précédée d'un commentaire.
  awk '/^skip-check:/ {dans=1; next} dans && /^[^[:space:]#-]/ {dans=0}
       dans && /^[[:space:]]*-[[:space:]]*CKV/ { if (!comm) { exit 1 } ; comm=0; next }
       dans && /^[[:space:]]*#/ {comm=1}' <<<"$c"
}
check_cmd ".checkov.yaml : chaque règle ignorée est précédée de sa justification" _m05_e25_exceptions_justifiees
check_cmd "outils/analyse-securite.sh présent" _m05p_fichier_main outils/analyse-securite.sh
check_cmd ".gitignore : rapports/ ignoré par Git" _m05p_main_contient .gitignore '^/?rapports/?'
check_cmd "analyse-securite.sh : contrôle d'empreinte de Trivy, aucune mise à jour de règles" \
  _m05p_main_contient outils/analyse-securite.sh 'sha256sum' '--skip-check-update'
check_cmd "au moins 4 règles Checkov maison (politiques/checkov/)" _m05p_nb_fichiers_main politiques/checkov '\.ya?ml$' 4
check_cmd "au moins 2 règles Trivy maison (politiques/trivy/)" _m05p_nb_fichiers_main politiques/trivy '\.rego$' 2
check_cmd "au moins 6 cas de test qui doivent échouer (politiques/tests/*/ATTENDU)" _m05p_nb_fichiers_main politiques/tests '^ATTENDU$' 6
_m05_e25_trivyignore() {
  local c
  # Pas de .trivyignore : aucune exception, c'est conforme.
  _m05p_fichier_main .trivyignore || return 0
  c="$(_m05p_contenu_main .trivyignore | grep -Ev '^[[:space:]]*(#|$)' || true)"
  [[ -z "$c" ]] || ! grep -Evq '[[:space:]]exp:[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$c"
}
check_cmd ".trivyignore : chaque exception a une date d'expiration" _m05_e25_trivyignore

title "Poste"
check_cmd "hook pre-push installé dans ~/src/infra" test -x "$_M05P_INFRA/.git/hooks/pre-push"
check_cmd ".pre-commit-config.yaml : analyse de sécurité à l'étape pre-push" \
  _m05p_main_contient .pre-commit-config.yaml 'analyse-securite' 'pre-push'
