# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes exécutées DANS les VMs (expansion côté invité, voulue)
# check-S13.sh — F4-S13 « La bascule de Legacy-RDV ». Lecture seule : HTTP en GET (une requête marquée
# par une valeur aléatoire, cherchée ensuite dans le journal d'accès de legacy-rdv01 par l'agent),
# comptes lus en SELECT sur la VM (root par socket, dans l'invité), pret.php de la production, témoins
# de l'export lus sur pve01, fiche CHG-3413 en GET.

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"
# Mesure de la sonde de continuité (contrat de F4-S02 : en-tête YAML des fiches, _f4m_mesurer).
# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S13 — La bascule de Legacy-RDV"
require_cmd kubectl jq curl ssh

# --- Qui sert le nom des cabinets ? ---------------------------------------------------------------------
_f4_s13_marque="wbcheck$(date +%s)$RANDOM"
check_output "$_f4g_rdv/ répond (page des rendez-vous)" 'Rendez-vous' _f4g_get "$_f4g_rdv/index.php?$_f4_s13_marque=1"
if _f4g_api; then
  check_cmd "legacy-rdv-prod : deux pods Legacy-RDV prêts" _f4g_pods_legacy legacy-rdv-prod 2
fi
if _f4g_vm_filtre 3401 '.status == "running"' && _f4g_agent 3401; then
  sleep 1
  check_cmd "$_f4g_rdv n'est plus servi par legacy-rdv01 (requête de contrôle absente de son journal d'accès)" _f4g_invite 3401 \
    "! grep -rqs '$_f4_s13_marque' /var/log/apache2/"
  # Gel : plus d'écriture possible pour l'application (droits retirés, base en lecture seule, ou web arrêté).
  check_cmd "legacy-rdv01 : Legacy-RDV ne peut plus écrire dans sa base (gel)" _f4g_invite 3401 \
    '! mariadb -N -B -e "SHOW GRANTS FOR legacy_rdv@localhost" 2>/dev/null | grep -Eq "INSERT|UPDATE|DELETE|ALL PRIVILEGES" || [ "$(mariadb -N -B -e "SELECT @@global.read_only" 2>/dev/null)" = 1 ] || ! systemctl is-active --quiet apache2'
  _f4_s13_n_vm="$(_f4g_invite 3401 'mariadb -N -B -e "SELECT COUNT(*) FROM legacy_rdv.rendez_vous"' 2>/dev/null | tr -dc '0-9' || true)"
else
  skip "contrôles sur legacy-rdv01 (journal d'accès, gel, nombre de rendez-vous)" "VM 3401 arrêtée ou agent injoignable"
  _f4_s13_n_vm=""
fi

# --- Référence, comptes ---------------------------------------------------------------------------------
_f4_s13_ref="$(_f4g_doc_texte "$_f4g_doc_dir/fiches" '^CHG-3413' 2>/dev/null \
  | sed -nE 's/.*[Rr](é|e)f(é|e)rence rendez-vous[^0-9]*([0-9]+).*/\3/p' | head -n 1 || true)"
check_cmd "fiche CHG-3413 sur main avec la ligne « Référence rendez-vous : <nombre> »" test -n "$_f4_s13_ref"
if [[ -n "$_f4_s13_ref" && -n "$_f4_s13_n_vm" ]]; then
  check_cmd "legacy-rdv01 gelée : nombre de rendez-vous égal à la référence ($_f4_s13_ref)" test "$_f4_s13_n_vm" -eq "$_f4_s13_ref"
fi
_f4_s13_n_prod="$(_f4g_get "$_f4g_prod/pret.php" 2>/dev/null | jq -r '.rendez_vous // empty' 2>/dev/null || true)"
check_cmd "production : pret.php répond et compte les rendez-vous" test -n "$_f4_s13_n_prod"
if [[ -n "$_f4_s13_ref" && -n "$_f4_s13_n_prod" ]]; then
  check_cmd "production : au moins autant de rendez-vous que la référence" test "$_f4_s13_n_prod" -ge "$_f4_s13_ref"
fi

# --- Témoins ------------------------------------------------------------------------------------------
check_cmd "production : les rendez-vous témoins s'affichent aux mêmes date et heure que dans l'export" _f4g_temoins_affiches "$_f4g_prod"
check_cmd "production : la pièce jointe témoin se télécharge à l'identique" _f4g_piece_temoin "$_f4g_prod"
check_cmd "par le nom des cabinets : les rendez-vous témoins s'affichent à l'identique" _f4g_temoins_affiches "$_f4g_rdv"

# --- Mesure de la fenêtre (sonde de continuité, en-tête de CHG-3413) ----------------------------------
_f4m_controles_mesure CHG-3413
_f4_s13_objectif_15min() { [[ "${_F4M_M_OBJECTIF:-}" =~ ^[0-9]+$ ]] && ((_F4M_M_OBJECTIF <= 900)); }
check_cmd "CHG-3413 : objectif d'interruption fixé à 15 min au plus (mesure-objectif-s ≤ 900)" _f4_s13_objectif_15min

# --- Documentation ------------------------------------------------------------------------------------
check_cmd "fiche CHG-3413 : mesures de la sonde et retour arrière" \
  _f4g_doc "$_f4g_doc_dir/fiches" '^CHG-3413' 'sonde|mesur' 'retour arri' 'gel'
check_cmd "runbook RB-346 sur main (bascule et retour arrière)" \
  _f4g_doc "$_f4g_doc_dir/runbooks" '^RB-346' 'retour arri' 'gel|maintenance'
