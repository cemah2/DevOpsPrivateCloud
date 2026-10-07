# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E25.sh — M03-E25 « Mini-projet : catalogue d'images MédiSphère v1 »
# Contrôle global : catalogue Proxmox (bases, dorées Debian et Rocky, current, rotation),
# chaîne CI (runner, pipeline planifié réussi récemment), documentation et hygiène.
# Lecture seule. Le détail de chaque brique reste dans les checks des exercices.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E25 — Catalogue d'images MédiSphère v1 : contrôle global"
require_cmd jq ssh curl git
_m03_charger

title "1/5 Images de base"
_m03_tpl_nom() { _m03_conf "$1" | grep -q '^template: 1' && _m03_conf "$1" | grep -q "^name: $2\$"; }
check_cmd "9001 tpl-debian13-base : template présent" _m03_tpl_nom 9001 tpl-debian13-base
check_cmd "9002 tpl-rocky10-base : template présent" _m03_tpl_nom 9002 tpl-rocky10-base
check_cmd "9000 tpl-debian13 (M00) conservé" _m03_existe 9000

title "2/5 Images dorées"
for _m03_f in debian13 rocky10; do
  _m03_cur="$(_m03_current "$_m03_f" || true)"
  check_cmd "$_m03_f : une seule version étiquetée current" test -n "$_m03_cur"
  _m03_nb="$(_m03_gold "$_m03_f" | jq 'length' 2>/dev/null || echo 0)"
  check_cmd "$_m03_f : rotation appliquée (1 à 5 versions, dont au plus une rejetée)" \
    test "$_m03_nb" -ge 1 -a "$_m03_nb" -le 5
  if [[ -n "$_m03_cur" ]]; then
    _m03_notes="$(_m03_conf "$_m03_cur" || true)"
    check_cmd "$_m03_f : manifeste dans les notes de current (commit, Packer, publication)" \
      bash -c 'grep -q "commit" <<<"$1" && grep -qi "packer" <<<"$1" && grep -q "Publi" <<<"$1"' _ "$_m03_notes"
    check_cmd "$_m03_f : current publiée il y a moins de 8 jours (pipeline hebdomadaire)" \
      bash -c 'd=$(grep -Eo "[0-9]{8}-[0-9]+" <<<"$1" | head -n1 | cut -c1-8); [ -n "$d" ] && [ $(( ($(date +%s) - $(date -d "$d" +%s)) / 86400 )) -le 8 ]' \
      _ "$(_m03_vms | jq -r --argjson v "$_m03_cur" '.[] | select(.vmid == $v) | .name')"
  else
    skip "$_m03_f : manifeste et fraîcheur de current" "aucune version current"
  fi
done
_m03_e25_rocky_cpu() { local id; id="$(_m03_current rocky10)"; [[ -n "$id" ]] && _m03_conf "$id" | grep -Eq '^cpu: (x86-64-v[34]|host)([,]|$)'; }
check_cmd "rocky10 current : CPU x86-64-v3 ou host" _m03_e25_rocky_cpu
check_cmd "projet : rocky10-gold/build.pkr.hcl sur main" _m03_fichier_main rocky10-gold/build.pkr.hcl
check_cmd "projet : l'image Rocky est durcie (durcir.sh appelé)" \
  _m03_fichier_main_contient rocky10-gold/build.pkr.hcl 'durcir\.sh'

title "3/5 Chaîne de construction"
check_ssh_output "runner01 : Packer 1.16" runner01 '^Packer v1\.16\.' "packer version"
check_cmd "pipeline planifié actif sur main" _m03_api_ok "$_M03_PROJET/pipeline_schedules" \
  'any(.[]; .active and (.ref == "main" or .ref == "refs/heads/main"))'
_m03_e25_planifie_ok() {
  local depuis
  depuis="$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  gitlab_api "$_M03_PROJET/pipelines?ref=main&source=schedule&status=success&updated_after=$depuis&per_page=5" 2>/dev/null \
    | jq -e 'length > 0' >/dev/null
}
check_cmd "un pipeline PLANIFIÉ a réussi sur main ces 8 derniers jours" _m03_e25_planifie_ok
check_cmd "secret PKR_VAR_proxmox_token protégé et masqué" \
  _m03_api_ok "$_M03_PROJET/variables/PKR_VAR_proxmox_token" '.protected and (.masked or (.hidden // false))'
for _m03_f in tests/tester-image.sh outils/publier-image.sh outils/rotation-images.sh scripts/durcir.sh docs/durcissement.md; do
  check_cmd "projet : $_m03_f sur main" _m03_fichier_main "$_m03_f"
done

title "4/5 Documentation (plateforme/medisphere)"
check_cmd "catalogue docs/socle/images.md (familles, current, consommation, rotation)" \
  _m03_doc_contient "$_M03_DOC/images.md" 'rocky10' 'debian13' 'current' '(rotation|r[ée]tention)'
check_cmd "ADR-0030 présent" bash -c 'ls "$1"/adr/ADR-0030*.md >/dev/null 2>&1' _ "$_M03_DOC"
check_cmd "matrice des flux : flux de construction (8100-8199, 8006, runner01)" \
  _m03_doc_contient "$_M03_DOC/matrice-flux.md" '8100-8199' '8006' 'runner01|10\.10\.20\.15'
check_cmd "inventaire : templates du catalogue (9001, 9002, gold)" \
  _m03_doc_contient "$_M03_DOC/inventaire.md" '9001' '9002' 'gold'
check_cmd "registre des secrets : jeton wb-packer" _m03_doc_contient "$_M03_DOC/registre-secrets.md" 'wb-packer'
check_cmd "runbook de retrait d'une image (RB-03x)" bash -c 'grep -lqis "retrait" "$1"/runbooks/RB-03*.md' _ "$_M03_DOC"
check_output "dépôt ~/medisphere : aucune modification non commitée" '^$' git -C "${WB_DEPOT:-$HOME/medisphere}" status --porcelain

title "5/5 Hygiène"
check_cmd "aucune panne M03 encore active (lab/bin/break)" _m03_pas_de_panne
check_cmd "aucune VM de test ou d'exercice restante (2030-2039)" _m03_aucune_vm 2030 2039
check_cmd "aucun template d'essai restant (9090-9099)" _m03_aucune_vm 9090 9099
check_cmd "pas de secret dans le clone ~/src/images (gitleaks)" \
  bash -c '! command -v gitleaks >/dev/null || gitleaks git --no-banner --redact "$1" >/dev/null 2>&1' _ "$_M03_SRC"
check_cmd "fichiers de ~/.config/workbook en 600" \
  bash -c '[ -z "$(find "$HOME/.config/workbook" -type f ! -perm 600 2>/dev/null)" ]'
