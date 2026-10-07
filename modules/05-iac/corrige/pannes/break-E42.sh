# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M05-E42 « Panne : l'état a disparu »
#
# « tofu plan » dans ~/src/infra/socle propose de tout créer (ou importer), voire de détruire des
# VMs d'environnement : pour OpenTofu, l'état du socle est vide ou n'est plus le bon. Variantes :
#   1. état distant : l'objet courant socle/terraform.tfstate est supprimé (copie faite avant ;
#      compartiment versionné : un marqueur de suppression devient la version courante) ;
#   2. état distant : l'objet socle/terraform.tfstate est écrasé par une copie de l'état de
#      envs/lab-m05 (« erreur de clé lors d'une migration de backend ») ;
#   3. copie de travail : la clé du backend devient socle/tofu.tfstate (« harmonisation des
#      noms ») et la configuration est réinitialisée (tofu init -reconfigure) : rien n'a disparu,
#      OpenTofu regarde ailleurs ;
#   4. copie de travail : un espace de travail « lucas-essai » est créé et sélectionné
#      (.terraform/environment) : l'état de cet espace est vide.
# Les variantes 1 et 2 exigent le versionnage du compartiment (refus sinon). Sauvegardes :
# /var/lib/workbook/M05-E42/ sur adm01 (objet et liste des versions, v1-v2),
# ~/.local/state/workbook/M05-E42/ (v3). Annulation : restauration seulement si l'état courant est
# encore celui posé par la panne ; en v4, retour à l'espace default et suppression de l'espace
# lucas-essai s'il est vide.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E42_ENV="$_M05_SOCLE/.terraform/environment"
_E42_CACHE="$_M05_SOCLE/.terraform/terraform.tfstate"
_E42_ESPACE=lucas-essai

# _e42_fichier_cle — fichier de socle/ qui porte la clé du backend.
_e42_fichier_cle() {
  grep -lE 'key[[:space:]]*=[[:space:]]*"socle/terraform\.tfstate"' \
    "$_M05_SOCLE"/*.tf "$_M05_SOCLE"/*.hcl "$_M05_SOCLE"/*.tfbackend 2>/dev/null | head -n 1
}

_e42_espace() { if [[ -f "$_E42_ENV" ]]; then cat "$_E42_ENV"; else echo default; fi; }

_m05E42_une() {
  local n="$1" f
  case "$n" in
    1)
      m05_s3_sauver E42 "$_M05_CLE_SOCLE" || return 1
      m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "$_M05_CLE_SOCLE" >/dev/null 2>&1 || return 1
      m05_s3_noter E42 "$_M05_CLE_SOCLE"
      [[ "$(m05_s3_dernier "$_M05_CLE_SOCLE")" == marqueur:* ]] || return 1
      m05_journal E42 "objet courant $_M05_CLE_SOCLE supprimé (marqueur de suppression)"
      ;;
    2)
      [[ "$(m05_s3_dernier "$_M05_CLE_ENVS")" == version:* ]] || return 10
      m05_s3_sauver E42 "$_M05_CLE_SOCLE" || return 1
      m05_aws s3api copy-object --bucket "$_M05_BUCKET" --key "$_M05_CLE_SOCLE" \
        --copy-source "$_M05_BUCKET/$_M05_CLE_ENVS" >/dev/null 2>&1 || return 1
      m05_s3_noter E42 "$_M05_CLE_SOCLE"
      m05_journal E42 "$_M05_CLE_SOCLE écrasé par une copie de $_M05_CLE_ENVS"
      ;;
    3)
      f="$(_e42_fichier_cle)"
      [[ -n "$f" && -f "$_E42_CACHE" ]] || return 10
      m05_sauver E42 "$f" || return 1
      m05_sauver E42 "$_E42_CACHE" || return 1
      sed -i 's#"socle/terraform\.tfstate"#"socle/tofu.tfstate"#' "$f" || return 1
      m05_ecrire E42 fichier "$f"
      if ! m05_tofu "$_M05_SOCLE" init -reconfigure -input=false -no-color >/dev/null 2>&1; then
        wb_avert "tofu init -reconfigure a échoué"
        return 1
      fi
      m05_noter E42 "$f"
      m05_noter E42 "$_E42_CACHE"
      m05_journal E42 "$f : clé du backend socle/tofu.tfstate, configuration réinitialisée"
      ;;
    4)
      [[ "$(_e42_espace)" == default ]] || return 10
      if ! m05_tofu "$_M05_SOCLE" workspace new -no-color "$_E42_ESPACE" >/dev/null 2>&1; then
        wb_avert "tofu workspace new a échoué"
        return 1
      fi
      m05_ecrire E42 espace "$_E42_ESPACE"
      m05_journal E42 "espace de travail $_E42_ESPACE créé et sélectionné dans socle"
      ;;
  esac
}

panne_E42_v1() { m05_prerequis socle envs && m05_essayer E42 4 1; }
panne_E42_v2() { m05_prerequis socle envs && m05_essayer E42 4 2; }
panne_E42_v3() { m05_prerequis socle envs && m05_essayer E42 4 3; }
panne_E42_v4() { m05_prerequis socle envs && m05_essayer E42 4 4; }

verifier_E42() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) [[ "$(m05_s3_dernier "$_M05_CLE_SOCLE")" == marqueur:* ]] ;;
    2) [[ "$(m05_s3_dernier "$_M05_CLE_SOCLE")" == "$(awk -F'\t' '{ v = $2 } END { print v }' "$(m05_etat E42)/s3-injecte" 2>/dev/null)" ]] ;;
    3) [[ -z "$(m05_tofu "$_M05_SOCLE" state list 2>/dev/null)" ]] && grep -q 'socle/tofu\.tfstate' "$(m05_lire E42 fichier)" ;;
    4) [[ "$(_e42_espace)" == "$_E42_ESPACE" ]] ;;
    *) return 1 ;;
  esac
}

annuler_E42() {
  m05_s3_restaurer E42 || true
  if [[ -n "$(m05_lire E42 fichier)" ]]; then
    m05_restaurer E42 || true
    rm -f -- "$(m05_etat E42)/fichier"
  fi
  if [[ -n "$(m05_lire E42 espace)" ]]; then
    if [[ "$(_e42_espace)" == "$_E42_ESPACE" ]]; then
      m05_tofu "$_M05_SOCLE" workspace select -no-color default >/dev/null 2>&1 \
        && m05_journal E42 "annulation : espace default resélectionné"
    fi
    if m05_tofu "$_M05_SOCLE" workspace list -no-color 2>/dev/null | grep -qw "$_E42_ESPACE"; then
      if [[ "$(_e42_espace)" == default ]] && m05_tofu "$_M05_SOCLE" workspace delete -no-color "$_E42_ESPACE" >/dev/null 2>&1; then
        m05_journal E42 "annulation : espace $_E42_ESPACE supprimé"
      else
        wb_avert "espace de travail $_E42_ESPACE conservé (non vide ou non supprimable) : à examiner"
      fi
    fi
    rm -f -- "$(m05_etat E42)/espace"
  fi
  rm -f -- "$(m05_etat E42)/variante"
}

resume_E42() {
  echo "Dans ~/src/infra/socle, « tofu plan » propose de tout créer ou importer : l'état du socle semble avoir disparu."
}

symptome_E42() {
  wb_symptome "Ticket INC-3245 — De : Nadia Roussel — priorité P1" \
    "Karim vient de lancer « tofu plan » dans ~/src/infra/socle pour une petite MR : OpenTofu" \
    "propose de CRÉER (ou d'importer) tout le socle, et peut-être pire. Comme si l'état n'existait" \
    "plus. Personne n'admet avoir touché à quoi que ce soit." \
    "Gel immédiat : aucun apply sur socle tant que ce n'est pas réglé (préviens l'équipe)." \
    "Retrouve l'état, restaure-le SANS perdre de version, prouve qu'il est complet, et dis-moi ce" \
    "qui aurait pu être perdu si le compartiment n'avait pas été versionné." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 05 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E42 4 "$@"; }
fi
