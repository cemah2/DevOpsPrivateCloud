# shellcheck shell=bash
# _m05-operationnel.sh — fonctions partagées par les vérifications du palier 2 du module 05
# (check-E10 à check-E23). Sourcé par ces scripts, jamais lancé seul.
# Lecture seule : OpenTofu n'est lancé qu'en lecture (state list, show -json, output, validate,
# plan -lock=false : rien n'est écrit, aucun verrou n'est pris) ; S3 n'est lu qu'avec
# l'identité tofu-etat ; Proxmox est lu en root sur pve01 (qm config, pvesh get, pveum … list).
# Préfixe _m05o_ : pas de collision avec les fonctions des autres paliers.

_m05o_src="${WB_SRC:-$HOME/src}"
_m05o_infra="$_m05o_src/infra"
_m05o_socle="$_m05o_infra/socle"
_m05o_lab="$_m05o_infra/envs/lab-m05"
_m05o_recette="$_m05o_infra/envs/recette-m05"
_m05o_modules="$_m05o_src/tofu-modules"
_m05o_ansible="$_m05o_src/ansible"
_m05o_depot="${WB_DEPOT:-$HOME/medisphere}"
_m05o_cfg="$HOME/.config/workbook"
_m05o_s3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_m05o_bucket=tofu-state

if ! declare -p _m05o_cache_plan >/dev/null 2>&1; then declare -gA _m05o_cache_plan=(); fi
if ! declare -p _m05o_cache_show >/dev/null 2>&1; then declare -gA _m05o_cache_show=(); fi

# _m05o_env — à appeler dans un sous-shell : accès OpenTofu/S3 de l'apprenant sur adm01.
_m05o_env() {
  local f
  set -a
  for f in "$_m05o_cfg/pve-tofu.env" "$_m05o_cfg/s3-tofu.env"; do
    # shellcheck source=/dev/null
    if [[ -r "$f" ]]; then source "$f"; fi
  done
  set +a
  # Chiffrement de l'état (M05-E27) : TF_ENCRYPTION (fournisseur de clé « pbkdf2 etat »), jamais
  # une variable TF_VAR_ (recopiée en clair dans chaque plan). Source de référence : le chargeur
  # de l'apprenant, outils/charger-acces.sh (il suit une rotation de phrase) ; à défaut, la
  # phrase de tofu-chiffrement.pass. Une valeur héritée du shell appelant est ignorée.
  unset TF_ENCRYPTION
  if [[ -r "$_m05o_infra/outils/charger-acces.sh" ]]; then
    # shellcheck source=/dev/null
    . "$_m05o_infra/outils/charger-acces.sh" >/dev/null 2>&1 || unset TF_ENCRYPTION
  fi
  if [[ -z "${TF_ENCRYPTION:-}" && -r "$_m05o_cfg/tofu-chiffrement.pass" ]]; then
    # Guillemets voulus : le contenu est du HCL.
    # shellcheck disable=SC2089,SC2090
    printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$(tr -d '\n' < "$_m05o_cfg/tofu-chiffrement.pass")"
    # shellcheck disable=SC2090
    export TF_ENCRYPTION
  fi
  unset AWS_PROFILE
  export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt AWS_DEFAULT_REGION=us-east-1
  export TF_IN_AUTOMATION=1 TF_INPUT=0 NO_COLOR=1
}

# _m05o_tofu DOSSIER args… — OpenTofu comme l'apprenant, sans interaction.
_m05o_tofu() {
  local dir="$1"
  shift
  (
    cd "$dir" || exit 1
    _m05o_env
    exec tofu "$@" </dev/null
  )
}

# _m05o_aws args… — AWS CLI v2 vers s3-01, identité tofu-etat (lecture).
_m05o_aws() {
  (
    _m05o_env
    exec aws --endpoint-url "$_m05o_s3" --output json "$@" </dev/null
  )
}

# _m05o_plan_vide DOSSIER — « tofu plan » sans verrou ne propose AUCUN changement (code 0 de
# -detailed-exitcode ; 2 = changements, 1 = erreur). Résultat mis en cache par dossier.
_m05o_plan_vide() {
  local d="$1" rc=0
  if [[ -z "${_m05o_cache_plan[$d]:-}" ]]; then
    _m05o_tofu "$d" plan -lock=false -no-color -input=false -detailed-exitcode >/dev/null 2>&1 || rc=$?
    _m05o_cache_plan[$d]="$rc"
  fi
  [[ "${_m05o_cache_plan[$d]}" == 0 ]]
}

# _m05o_show DOSSIER — état courant en JSON (tofu show -json), mis en cache ; vide si échec.
# À appeler hors de $(…) avant _m05o_etat (sinon le cache est perdu avec le sous-shell).
_m05o_show() {
  local d="$1"
  [[ -n "${_m05o_cache_show[$d]+x}" ]] && return 0
  _m05o_cache_show[$d]="$(_m05o_tofu "$d" show -json 2>/dev/null || true)"
}

# _m05o_adresses DOSSIER — adresses des ressources gérées de l'état, avec leur vm_id :
#   « adresse vm_id » par ligne (vm_id vide pour les ressources sans VM).
_m05o_adresses() {
  _m05o_show "$1"
  jq -r '[.values.root_module | .. | objects | select(has("address") and .mode == "managed")]
         | .[] | "\(.address) \(.values.vm_id // "")"' <<<"${_m05o_cache_show[$1]}" 2>/dev/null || true
}

# _m05o_a_adresse DOSSIER REGEX — une adresse de l'état correspond à la regex étendue.
_m05o_a_adresse() { _m05o_adresses "$1" | awk '{print $1}' | grep -Eq -- "$2"; }

# _m05o_a_vmid DOSSIER VMID — une VM de l'état a ce VMID.
_m05o_a_vmid() { _m05o_adresses "$1" | awk '{print $2}' | grep -qx -- "$2"; }

# _m05o_qm VMID — configuration Proxmox de la VM (vide si elle n'existe pas).
_m05o_qm() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null || true; }

# _m05o_code DOSSIER REGEX — un fichier .tf du dossier (non récursif) contient la regex.
_m05o_code() { grep -Eqs -- "$2" "$1"/*.tf; }

# _m05o_objet CLE — l'objet courant de la clé existe dans le compartiment (HEAD).
_m05o_objet() { _m05o_aws s3api head-object --bucket "$_m05o_bucket" --key "$1" >/dev/null 2>&1; }

# _m05o_projet CHEMIN — identifiant encodé d'un projet GitLab (plateforme/infra → plateforme%2Finfra).
_m05o_projet() { printf 'projects/%s' "${1//\//%2F}"; }

# _m05o_ansible_env CMD… — commande du projet Ansible (uv run), accès Proxmox de M04 chargés.
_m05o_ansible() {
  (
    cd "$_m05o_ansible" || exit 1
    set -a
    # shellcheck source=/dev/null
    if [[ -r "$_m05o_cfg/pve-ansible.env" ]]; then source "$_m05o_cfg/pve-ansible.env"; fi
    set +a
    exec uv run "$@" </dev/null
  )
}

# _m05o_invite VMID COMMANDE… — commande en lecture DANS la VM par l'agent QEMU ; affiche
# sa sortie standard (vide si l'agent ne répond pas).
_m05o_invite() {
  local vmid="$1"
  shift
  remote "$WB_PVE_HOST" "qm guest exec $vmid --timeout 20 -- $*" 2>/dev/null \
    | jq -r '."out-data" // empty' 2>/dev/null || true
}

# _m05o_pas_objet CLE — aucun objet courant pour cette clé (absent, ou dernière version supprimée).
_m05o_pas_objet() { ! _m05o_objet "$1"; }
