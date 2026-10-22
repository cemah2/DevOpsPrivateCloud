# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E04.sh — M26-E04 : OpenSCAP et ComplianceAsCode : évaluer une VM contre CIS et ANSSI
# À lancer depuis adm01. Lecture seule : « qm config » sur pve01, SSH en consultation sur durci-deb et
# durci-rocky (sudo -n en lecture des résultats), fichiers des dépôts par l'API de GitLab.
# Après M26-E14 (VMs d'essai détruites, RB-263 écrit), seuls la documentation et le code sont contrôlés.

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E04 — OpenSCAP et ComplianceAsCode : évaluer une VM contre CIS et ANSSI"
require_cmd jq curl

_m26d_e04_essais=/var/lib/conformite/essais

# --- 1. Code et documentation ---------------------------------------------------------------------------
check_cmd "plateforme/infra : environnement envs/m26 décrit sur main (fichiers .tf)" \
  _m26d_contient "$(_m26d_arbre_main plateforme/infra envs/m26)" '\.tf$'
_m26d_e04_ref="$(_m26d_doc referentiels.md)"
if [[ -z "$_m26d_e04_ref" ]]; then
  _ko "plateforme/medisphere : $_M26D_DOC/referentiels.md absent de main"
else
  check_cmd "referentiels.md : profil CIS niveau 1 serveur de Debian 13 (cis_level1_server)" \
    _m26d_contient "$_m26d_e04_ref" 'cis_level1_server'
  check_cmd "referentiels.md : profil CIS niveau 1 serveur de Rocky 10 (cis_server_l1)" \
    _m26d_contient "$_m26d_e04_ref" 'cis_server_l1'
  check_cmd "referentiels.md : profil ANSSI-BP-028 intermédiaire (anssi_bp28_intermediary)" \
    _m26d_contient "$_m26d_e04_ref" 'anssi_bp28_intermediary'
  check_cmd "referentiels.md : datastream de Debian 13 (ssg-debian13-ds.xml)" \
    _m26d_contient "$_m26d_e04_ref" 'ssg-debian13-ds\.xml'
  check_cmd "referentiels.md : datastream de Rocky 10 (ssg-rl10-ds.xml, pas celui de RHEL 10)" \
    _m26d_contient "$_m26d_e04_ref" 'ssg-rl10-ds\.xml'
fi

# --- 2. Les VMs d'essai (jusqu'à la fin d'E14) -----------------------------------------------------------
if ! remote "$WB_PVE_HOST" "qm config 2261" >/dev/null 2>&1 && ! remote "$WB_PVE_HOST" "qm config 2262" >/dev/null 2>&1; then
  if [[ -n "$(_m26d_contenu_main "$_M26D_DEPOT_DOC" "$_M26D_DOC/runbooks/RB-263-durcissement-par-vagues.md")" ]]; then
    skip "VMs d'essai durci-deb et durci-rocky" "détruites à la fin d'E14 comme prévu : seuls le code et la documentation sont contrôlés"
    return 0
  fi
  _ko "pve01 : ni la VM 2261 (durci-deb) ni la VM 2262 (durci-rocky) n'existent"
  return 0
fi

# _m26d_e04_vm VMID NOM MAC — la VM existe, porte son nom, l'étiquette env-m26, 2 Go, la carte vsandbox à MAC imposée.
_m26d_e04_vm() {
  local conf
  conf="$(remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null | tr '[:upper:]' '[:lower:]')" || true
  grep -q "^name: $2\$" <<<"$conf" && grep -Eq '^tags:.*env-m26' <<<"$conf" \
    && grep -q '^memory: 2048$' <<<"$conf" && grep -Eq "^net0: .*$3.*bridge=vsandbox" <<<"$conf"
}
check_cmd "pve01 : VM 2261 durci-deb (env-m26, 2 Go, vsandbox, MAC bc:24:11:99:26:01)" \
  _m26d_e04_vm 2261 durci-deb 'bc:24:11:99:26:01'
check_cmd "pve01 : VM 2262 durci-rocky (env-m26, 2 Go, vsandbox, MAC bc:24:11:99:26:02)" \
  _m26d_e04_vm 2262 durci-rocky 'bc:24:11:99:26:02'

# _m26d_e04_arf HÔTE PROFIL MARQUEUR_DS — dernier résultat ARF du profil : il existe, contient des règles
# évaluées « pass » ET « fail » (une évaluation où tout est notapplicable ne mesure rien) et vient du
# bon datastream (identifiant du flux dans l'ARF).
_m26d_e04_arf() {
  remote "$1" "f=\$(sudo -n find $_m26d_e04_essais -maxdepth 1 -name '*$2-[0-9]*.arf.xml' 2>/dev/null | sort | tail -n 1);
    [ -n \"\$f\" ] && sudo -n grep -q '<result>pass</result>' \"\$f\" && sudo -n grep -q '<result>fail</result>' \"\$f\" \
      && sudo -n grep -q '$3' \"\$f\"" >/dev/null 2>&1
}
# _m26d_e04_html HÔTE PROFIL… — un rapport HTML de chaque profil existe à côté des ARF.
_m26d_e04_html() {
  local hote="$1" p
  shift
  for p in "$@"; do
    remote "$hote" "sudo -n find $_m26d_e04_essais -maxdepth 1 -name '*$p-[0-9]*.html' 2>/dev/null | grep -q ." \
      >/dev/null 2>&1 || return 1
  done
}

# --- 3. durci-deb : contenu amont 0.1.82 et évaluations -------------------------------------------------
if ! remote "$_M26D_DEB" true >/dev/null 2>&1; then
  _ko "$_M26D_DEB ne répond pas en SSH (VM arrêtée ? nom inconnu de Kea ?)"
else
  check_ssh_output "$_M26D_DEB : OpenSCAP 1.4 installé" "$_M26D_DEB" '\(oscap\) 1\.4\.' "oscap --version | head -n 1"
  check_ssh "$_M26D_DEB : contenu ComplianceAsCode 0.1.82 dans /usr/local/share/scap/ssg-0.1.82/ (ssg-debian13-ds.xml)" "$_M26D_DEB" \
    "test -r /usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml"
  check_cmd "$_M26D_DEB : évaluation CIS niveau 1 serveur (ARF avec règles pass et fail, datastream debian13)" \
    _m26d_e04_arf "$_M26D_DEB" cis_level1_server 'ssg-debian13'
  check_cmd "$_M26D_DEB : évaluation ANSSI-BP-028 intermédiaire (ARF avec règles pass et fail)" \
    _m26d_e04_arf "$_M26D_DEB" anssi_bp28_intermediary 'ssg-debian13'
  check_cmd "$_M26D_DEB : rapports HTML des deux profils dans $_m26d_e04_essais" \
    _m26d_e04_html "$_M26D_DEB" cis_level1_server anssi_bp28_intermediary
fi

# --- 4. durci-rocky : paquet d'AppStream, datastream rl10 ----------------------------------------------
if ! remote "$_M26D_ROCKY" true >/dev/null 2>&1; then
  _ko "$_M26D_ROCKY ne répond pas en SSH (VM arrêtée ? nom inconnu de Kea ?)"
else
  check_ssh_output "$_M26D_ROCKY : OpenSCAP 1.4 installé" "$_M26D_ROCKY" '\(oscap\) 1\.4\.' "oscap --version | head -n 1"
  check_ssh_output "$_M26D_ROCKY : paquet scap-security-guide 0.1.82 (AppStream)" "$_M26D_ROCKY" \
    '^0\.1\.82$' "rpm -q --qf '%{VERSION}\n' scap-security-guide"
  check_cmd "$_M26D_ROCKY : évaluation CIS niveau 1 serveur avec le datastream ssg-rl10 (règles pass et fail)" \
    _m26d_e04_arf "$_M26D_ROCKY" cis_server_l1 'ssg-rl10'
  check_cmd "$_M26D_ROCKY : évaluation ANSSI-BP-028 intermédiaire avec le datastream ssg-rl10" \
    _m26d_e04_arf "$_M26D_ROCKY" anssi_bp28_intermediary 'ssg-rl10'
fi
