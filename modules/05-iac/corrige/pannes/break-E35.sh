# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M05-E35 « Panne : le plan veut recréer une VM du socle »
#
# Le plan de ~/src/infra/socle, vide avant l'injection, détruit ou remplace une VM du socle (ou
# échoue sur prevent_destroy). Variantes (chacune n'est retenue que si le plan devient dangereux ;
# sinon elle est défaite et la suivante est essayée) :
#   1. copie de travail : fichier socle/lucas.auto.tfvars (« essai pour le futur cluster ») qui
#      redéfinit la variable noeud : les fichiers *.auto.tfvars sont chargés automatiquement APRÈS
#      terraform.tfvars ; node_name change, ce qui force le remplacement (migrate = false) ;
#   2. état distant socle : « tofu state mv » de la VM de s3-01 (ou, à défaut, d'une autre VM du
#      socle) vers une adresse sans configuration (refactoring abandonné à mi-chemin) : le plan
#      détruit l'ancienne adresse (prevent_destroy ne protège plus un bloc absent) et crée la VM ;
#   3. état distant socle : « tofu taint » de la VM de s3-01 (ou d'une autre VM du socle), comme
#      après un apply interrompu ou un « pour forcer la reconfiguration » : remplacement planifié ;
#   4. copie de travail : fichier socle/zz_lucas_override.tf (fichier de surcharge) qui change
#      node_name d'une ressource VM de la racine : node_name force le remplacement.
# Sauvegardes : ~/.local/state/workbook/M05-E35/ (copie de travail), /var/lib/workbook/M05-E35/
# sur adm01 (copie de l'objet d'état et de ses versions, v2 et v3). L'annulation ne défait que ce
# qui est encore dans l'état posé par la panne (état distant : seulement si la version courante
# est encore celle de la panne).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E35_OVERRIDE="$_M05_SOCLE/zz_lucas_override.tf"
_E35_AUTO="$_M05_SOCLE/lucas.auto.tfvars"
_E35_DEST="proxmox_virtual_environment_vm.s3_01_avant_refacto"

# --- variante 1 : fichier *.auto.tfvars qui redéfinit le nœud ------------------------------------
_e35_v1() {
  grep -Eqs '^[[:space:]]*variable[[:space:]]+"noeud"' "$_M05_SOCLE"/*.tf || return 10
  [[ -e "$_E35_AUTO" ]] && return 10
  m05_poser E35 "$_E35_AUTO" <<'HCL' || return 1
# Essai Lucas : préparation du futur cluster Proxmox (module 09), nœud de test.
# Fichier local, NE PAS COMMITER.
noeud = "pve02"
HCL
  m05_journal E35 "fichier $_E35_AUTO (noeud = pve02)"
}

# --- variante 2 : state mv vers une adresse orpheline -----------------------------------------
_e35_v2() {
  local j src
  j="$(m05_show_json "$_M05_SOCLE")"
  src="$(m05_vms_etat "$j" | awk '$2 == 1006 { print $1; exit }')"
  [[ -n "$src" ]] || src="$(m05_vms_etat "$j" | awk '$2 >= 1001 && $2 <= 1099 { print $1; exit }')"
  [[ -n "$src" ]] || return 10
  m05_vms_etat "$j" | awk -v d="$_E35_DEST" '$1 == d { f = 1 } END { exit f }' || return 10
  m05_s3_sauver E35 "$_M05_CLE_SOCLE" || return 1
  m05_ecrire E35 mv-source "$src"
  if ! m05_tofu "$_M05_SOCLE" state mv -lock-timeout=60s "$src" "$_E35_DEST" >/dev/null 2>&1; then
    wb_avert "tofu state mv a échoué"
    return 1
  fi
  m05_s3_noter E35 "$_M05_CLE_SOCLE"
  m05_journal E35 "état socle : $src déplacé vers $_E35_DEST"
}

# --- variante 3 : ressource marquée « tainted » ------------------------------------------------------
_e35_v3() {
  local j adr
  j="$(m05_show_json "$_M05_SOCLE")"
  adr="$(m05_vms_etat "$j" | awk '$2 == 1006 { print $1; exit }')"
  [[ -n "$adr" ]] || adr="$(m05_vms_etat "$j" | awk '$2 >= 1001 && $2 <= 1099 { print $1; exit }')"
  [[ -n "$adr" ]] || return 10
  m05_s3_sauver E35 "$_M05_CLE_SOCLE" || return 1
  if ! m05_tofu "$_M05_SOCLE" taint -lock-timeout=60s "$adr" >/dev/null 2>&1; then
    wb_avert "tofu taint a échoué"
    return 1
  fi
  m05_s3_noter E35 "$_M05_CLE_SOCLE"
  m05_ecrire E35 taint "$adr"
  m05_journal E35 "état socle : $adr marqué tainted"
}

# --- variante 4 : fichier de surcharge dans la copie de travail -----------------------------------
_e35_v4() {
  local j nom
  [[ -e "$_E35_OVERRIDE" ]] && return 10
  j="$(m05_show_json "$_M05_SOCLE")"
  nom="$(m05_vms_etat "$j" | awk '$4 == 1 && $2 >= 1001 && $2 <= 1099 { print $3; exit }')"
  [[ -n "$nom" ]] || return 10
  m05_poser E35 "$_E35_OVERRIDE" <<HCL || return 1
# Essai Lucas : préparation du futur cluster Proxmox (module 09).
# Fichier local, NE PAS COMMITER.
resource "proxmox_virtual_environment_vm" "$nom" {
  node_name = "pve02"
}
HCL
  m05_journal E35 "fichier de surcharge $_E35_OVERRIDE (bloc $nom)"
}

# --- injection : une variante, retenue seulement si le plan devient dangereux ---------------------
_m05E35_une() {
  local n="$1" rc=0
  case "$n" in
    1) _e35_v1 || rc=$? ;;
    2) _e35_v2 || rc=$? ;;
    3) _e35_v3 || rc=$? ;;
    4) _e35_v4 || rc=$? ;;
  esac
  if ((rc != 0)); then
    annuler_E35
    return "$rc"
  fi
  if ! m05_plan_dangereux "$_M05_SOCLE" "$(m05_etat E35)/plan-injection.txt"; then
    m05_journal E35 "variante $n sans effet sur le plan du socle : défaite"
    annuler_E35
    return 10
  fi
}

_e35_injecter() {
  m05_prerequis socle || return 1
  if ! m05_plan_vide "$_M05_SOCLE"; then
    wb_avert "le plan de $_M05_SOCLE n'est pas vide (ou échoue) : ramène-le à « No changes » avant d'injecter"
    return 1
  fi
  m05_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

# Contrôle rapide (le plan a déjà été constaté dangereux à l'injection).
verifier_E35() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) [[ -f "$_E35_AUTO" ]] ;;
    2) m05_vms_etat "$(m05_show_json "$_M05_SOCLE")" | awk -v a="$_E35_DEST" '$1 == a { f = 1 } END { exit !f }' ;;
    3) m05_show_json "$_M05_SOCLE" | jq -e --arg a "$(m05_lire E35 taint)" '[.. | objects | select(.address? == $a and .tainted? == true)] | length > 0' >/dev/null 2>&1 ;;
    4) [[ -f "$_E35_OVERRIDE" ]] ;;
    *) return 1 ;;
  esac
}

annuler_E35() {
  m05_s3_restaurer E35 || true
  m05_restaurer E35 || true
  rm -f -- "$(m05_etat E35)/mv-source" "$(m05_etat E35)/taint" "$(m05_etat E35)/variante"
}

resume_E35() {
  echo "Le plan du socle (~/src/infra/socle), vide hier, veut maintenant détruire ou remplacer une VM permanente."
}

symptome_E35() {
  wb_symptome "Ticket INC-3241 — De : Karim Benali" \
    "Je relisais le plan du socle avant la fusion d'une petite MR (une sortie en plus) et je n'en" \
    "crois pas mes yeux : « tofu plan » dans ~/src/infra/socle veut détruire (ou remplacer) une de nos" \
    "VMs permanentes, ou s'arrête sur une erreur de prevent_destroy. Hier soir, le même plan était" \
    "vide. Personne n'a fusionné quoi que ce soit dans main depuis." \
    "Ne lance AUCUN apply. Trouve ce qui a changé, ramène le plan à « No changes » sans recréer" \
    "aucune VM, et dis-moi quel garde-fou aurait dû nous prévenir." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 05 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E35 4 "$@"; }
fi
