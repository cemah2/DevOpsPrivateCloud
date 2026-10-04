# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E06.sh — M02-E06 : yq : modifier du YAML sans le casser
# À lancer depuis adm01. Lit les fichiers produits dans ~/m02/e06/. Lecture seule.

title "M02-E06 — yq : modifier du YAML sans le casser"
require_cmd yq

_m02_d="$HOME/m02/e06"

# _m02_yq FICHIER EXPRESSION — évalue une expression yq (avertissements écartés)
_m02_yq() { yq -r "$2" "$1" 2>/dev/null; }

check_output "yq de mikefarah, version 4.54 ou plus récente" \
  'mikefarah.*v4\.(5[4-9]|[6-9][0-9])' yq --version

# --- 1. Hôtes et NTP effectif ------------------------------------------------------------
check_cmd "hotes.tsv : une ligne par hôte, valeurs effectives selon la spécification YAML" \
  diff -q <(printf 'gw01\t10.10.10.1\tpool.ntp.org\nadm01\t10.10.10.10\t10.10.10.1\ndns01\t10.10.20.10\t10.10.20.1\nsbx01\t10.10.99.20\t10.10.20.1\n') \
  "$_m02_d/hotes.tsv"

# --- 2. Inventaire corrigé ------------------------------------------------------------------
_m02_i="$_m02_d/inventaire-corrige.yml"
check_cmd "inventaire-corrige.yml présent" test -s "$_m02_i"
check_output "sauvegarde : un vrai booléen (true) dans les valeurs communes" '^!!bool true$' \
  _m02_yq "$_m02_i" '.all.vars.defaut.sauvegarde | tag + " " + (. | tostring)'
check_output "sauvegarde de sbx01 : un vrai booléen (false)" '^!!bool false$' \
  _m02_yq "$_m02_i" '.all.children.sandbox.hosts.sbx01.sauvegarde | tag + " " + (. | tostring)'
check_output "version_python : la chaîne « 3.10 », plus un nombre" '^!!str 3\.10$' \
  _m02_yq "$_m02_i" '.all.vars.defaut.version_python | tag + " " + .'
check_output "mode_cles : la chaîne « 0600 », plus un entier" '^!!str 0600$' \
  _m02_yq "$_m02_i" '.all.vars.defaut.mode_cles | tag + " " + .'
check_output "ancre &defaut toujours définie et utilisée par les 4 hôtes" '^4$' \
  bash -c 'grep -c "<<: \*defaut" "$1"' _ "$_m02_i"
check_cmd "commentaires d'origine conservés" \
  bash -c 'grep -q "Ne pas réordonner" "$1" && grep -q "VM jetable" "$1"' _ "$_m02_i"
# Sans l'option de conformité à la spécification, yq 4.54 lit encore la clé de fusion
# « à l'ancienne » : le fichier ne doit plus dépendre de ce comportement.
check_output "gw01 : NTP pool.ntp.org quel que soit le mode de lecture des clés de fusion" '^pool\.ntp\.org$' \
  _m02_yq "$_m02_i" 'explode(.) | .all.children.socle.hosts.gw01.ntp_serveur'

# --- 3. user-data ---------------------------------------------------------------------------
_m02_u="$_m02_d/user-data-sandbox.yaml"
check_output "user-data : la première ligne est toujours #cloud-config" '^#cloud-config$' head -n 1 "$_m02_u"
check_output "user-data : NTP sur la passerelle du VLAN 99 uniquement" '^\["10\.10\.99\.1"\]$' \
  _m02_yq "$_m02_u" '.ntp.servers | to_json(0)'
if [[ -r "$HOME/.ssh/id_ed25519.pub" ]]; then
  _m02_cle="$(awk '{print $2}' "$HOME/.ssh/id_ed25519.pub")"
  check_output "user-data : la clé publique d'adm01 est autorisée pour admin" '^true$' \
    _m02_yq "$_m02_u" ".users[] | select(.name == \"admin\") | .ssh_authorized_keys | any_c(contains(\"$_m02_cle\"))"
else
  skip "user-data : clé publique d'adm01 autorisée" "clé publique id_ed25519.pub illisible"
fi
check_output "user-data : mise à jour des paquets au premier démarrage" '^true$' _m02_yq "$_m02_u" '.package_upgrade'
check_output "user-data : les droits de write_files restent des chaînes" '^!!str,!!str$' \
  _m02_yq "$_m02_u" '[.write_files[].permissions | tag] | join(",")'
check_cmd "user-data : commentaire d'avertissement de l'en-tête conservé" grep -q 'NE PAS SUPPRIMER' "$_m02_u"
if command -v cloud-init >/dev/null 2>&1; then
  check_cmd "user-data : schéma cloud-init valide" cloud-init schema -c "$_m02_u"
else
  skip "user-data : schéma cloud-init valide" "cloud-init absent de ce poste"
fi

# --- 4. Paramètres effectifs de PAR2 ----------------------------------------------------------
_m02_p="$_m02_d/parametres-effectifs-par2.yml"
check_output "PAR2 : domaine par2.medisphere.internal" '^par2\.medisphere\.internal$' _m02_yq "$_m02_p" '.dns.domaine'
check_output "PAR2 : résolveurs hérités des valeurs par défaut" '^\["10\.10\.20\.10"\]$' \
  _m02_yq "$_m02_p" '.dns.resolveurs | to_json(0)'
check_output "PAR2 : la liste des serveurs NTP de PAR2 remplace celle par défaut" '^\["10\.20\.20\.1"\]$' \
  _m02_yq "$_m02_p" '.ntp.serveurs | to_json(0)'
check_output "PAR2 : rétention fusionnée clé par clé (14 j, 4 sem., 6 mois)" '^14 4 6$' \
  _m02_yq "$_m02_p" '.sauvegarde.retention | [.jours, .semaines, .mois] | join(" ")'
check_output "PAR2 : contacts de supervision de PAR2 uniquement" '^\["astreinte@medisphere\.internal"\]$' \
  _m02_yq "$_m02_p" '.supervision.contacts | to_json(0)'

# --- 5. JSON → YAML -------------------------------------------------------------------------------
_m02_v="$_m02_d/vms-lab.yml"
check_output "vms-lab.yml : les 8 VMs QEMU du pool lab, triées par VMID" '^1000,1001,1002,1004,1007,2021,2022,5003$' \
  _m02_yq "$_m02_v" '[.[].vmid] | join(",")'
check_output "vms-lab.yml : étiquettes en liste (runner01)" '^\["role-runner","socle"\]$' \
  _m02_yq "$_m02_v" '.[] | select(.vmid == 1007) | .etiquettes | to_json(0)'
check_output "vms-lab.yml : liste vide pour une VM sans étiquette (2022)" '^\[\]$' \
  _m02_yq "$_m02_v" '.[] | select(.vmid == 2022) | .etiquettes | to_json(0)'
