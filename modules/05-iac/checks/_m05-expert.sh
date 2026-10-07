# shellcheck shell=bash
# _m05-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du
# module 05 (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul.
# Lecture seule : OpenTofu n'est lancé qu'en lecture (state list, show -json, validate, plan
# -lock=false : rien n'est écrit, aucun verrou n'est pris), le S3 n'est interrogé qu'en lecture.
# Préfixe _m05x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks ;
# les résultats coûteux (plans, état) sont mis en cache pour la durée du contrôle.

_m05x_infra="${WB_SRC:-$HOME/src}/infra"
_m05x_socle="$_m05x_infra/socle"
_m05x_envs="$_m05x_infra/envs/lab-m05"
_m05x_cfg="$HOME/.config/workbook"
_m05x_s3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_m05x_bucket=tofu-state
_m05x_cle_socle=socle/terraform.tfstate
_m05x_cle_envs=envs/lab-m05/terraform.tfstate
# shellcheck disable=SC2034  # utilisé par les checks qui sourcent ce fichier
_m05x_depot="${WB_DEPOT:-$HOME/medisphere}"

# Caches conservés si le fichier est sourcé plusieurs fois (check-E43, check-E46).
if ! declare -p _m05x_cache_plan >/dev/null 2>&1; then declare -gA _m05x_cache_plan=(); fi
if ! declare -p _m05x_cache_show >/dev/null 2>&1; then declare -gA _m05x_cache_show=(); fi

# _m05x_env — à appeler dans un sous-shell : environnement OpenTofu/S3 standard de adm01.
_m05x_env() {
  local f
  set -a
  for f in "$_m05x_cfg/pve-tofu.env" "$_m05x_cfg/s3-tofu.env"; do
    # shellcheck source=/dev/null
    if [[ -r "$f" ]]; then source "$f"; fi
  done
  set +a
  if [[ -r "$_m05x_cfg/tofu-chiffrement.pass" ]]; then
    TF_VAR_phrase_chiffrement="$(<"$_m05x_cfg/tofu-chiffrement.pass")"
    export TF_VAR_phrase_chiffrement
  fi
  export AWS_CA_BUNDLE="${AWS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
  export AWS_RESPONSE_CHECKSUM_VALIDATION="${AWS_RESPONSE_CHECKSUM_VALIDATION:-when_required}"
  export TF_IN_AUTOMATION=1 TF_INPUT=0 NO_COLOR=1
}

# _m05x_tofu DOSSIER args… — OpenTofu comme l'apprenant, sans interaction.
_m05x_tofu() {
  local dir="$1"
  shift
  (
    cd "$dir" || exit 1
    _m05x_env
    exec tofu "$@" </dev/null
  )
}

# _m05x_aws args… — AWS CLI v2 vers s3-01 (lecture).
_m05x_aws() {
  (
    _m05x_env
    exec aws --endpoint-url "$_m05x_s3" --output json "$@" </dev/null
  )
}

# _m05x_plan_calc DOSSIER — lance (une seule fois par contrôle) « plan -detailed-exitcode » sans
# verrou et garde son code (0 vide, 2 changements, 1 erreur). À appeler hors de $(…), sinon le
# cache est perdu avec le sous-shell.
_m05x_plan_calc() {
  local d="$1" rc=0
  [[ -n "${_m05x_cache_plan[$d]:-}" ]] && return 0
  _m05x_tofu "$d" plan -lock=false -no-color -input=false -detailed-exitcode >/dev/null 2>&1 || rc=$?
  _m05x_cache_plan[$d]="$rc"
}
_m05x_plan_vide() { _m05x_plan_calc "$1"; [[ "${_m05x_cache_plan[$1]}" == 0 ]]; }
_m05x_plan_aboutit() { _m05x_plan_calc "$1"; [[ "${_m05x_cache_plan[$1]}" != 1 ]]; }

# _m05x_show_calc DOSSIER — état courant (tofu show -json), mis en cache (vide en cas d'échec).
_m05x_show_calc() {
  local d="$1"
  [[ -n "${_m05x_cache_show[$d]+x}" ]] && return 0
  _m05x_cache_show[$d]="$(_m05x_tofu "$d" show -json 2>/dev/null || true)"
}

# _m05x_vmids DOSSIER — VMID des VMs de l'état (un par ligne). Appeler _m05x_show_calc avant
# si le résultat est lu dans un $(…).
_m05x_vmids() {
  _m05x_show_calc "$1"
  jq -r '
    def res: (.resources // []) + ((.child_modules // []) | map(res) | add // []);
    (.values.root_module // {}) | res | .[]
    | select(.mode == "managed" and .type == "proxmox_virtual_environment_vm") | .values.vm_id' \
    <<<"${_m05x_cache_show[$1]}" 2>/dev/null | sort -n
}

# _m05x_etat_contient DOSSIER VMID… — toutes les VMs citées sont dans l'état.
_m05x_etat_contient() {
  local d="$1" ids id
  shift
  _m05x_show_calc "$d"
  ids="$(_m05x_vmids "$d")"
  [[ -n "$ids" ]] || return 1
  for id in "$@"; do grep -qx "$id" <<<"$ids" || return 1; done
}

# _m05x_aucune_ressource_tainted DOSSIER
_m05x_aucune_ressource_tainted() {
  local j
  _m05x_show_calc "$1"
  j="${_m05x_cache_show[$1]}"
  [[ -n "$j" ]] && ! jq -e '[.. | objects | select(.tainted? == true)] | length > 0' <<<"$j" >/dev/null 2>&1
}

# _m05x_s3_dernier CLÉ — « version:<id> », « marqueur:<id> » ou « absent ».
_m05x_s3_dernier() {
  _m05x_aws s3api list-object-versions --bucket "$_m05x_bucket" --prefix "$1" 2>/dev/null | jq -r --arg k "$1" '
    ([(.Versions // [])[] | select(.Key == $k and .IsLatest) | "version:\(.VersionId)"]
     + [(.DeleteMarkers // [])[] | select(.Key == $k and .IsLatest) | "marqueur:\(.VersionId)"])
    | if length == 0 then "absent" else .[0] end' 2>/dev/null
}

# _m05x_s3_nb_versions CLÉ — nombre de versions (hors marqueurs) de la clé exacte.
_m05x_s3_nb_versions() {
  _m05x_aws s3api list-object-versions --bucket "$_m05x_bucket" --prefix "$1" 2>/dev/null \
    | jq -r --arg k "$1" '[(.Versions // [])[] | select(.Key == $k)] | length' 2>/dev/null
}

_m05x_versionnage_actif() {
  _m05x_aws s3api get-bucket-versioning --bucket "$_m05x_bucket" 2>/dev/null | jq -e '.Status == "Enabled"' >/dev/null
}

# _m05x_verrou_absent CLÉ — aucun objet de verrou <clé>.tflock.
_m05x_verrou_absent() {
  local out
  out="$(_m05x_aws s3api head-object --bucket "$_m05x_bucket" --key "$1.tflock" 2>&1)" && return 1
  grep -Eq '404|Not ?Found|NoSuchKey' <<<"$out"
}

# _m05x_objet_chiffre CLÉ — l'objet d'état est chiffré par OpenTofu (enveloppe encrypted_data).
_m05x_objet_chiffre() {
  _m05x_aws s3 cp "s3://$_m05x_bucket/$1" - 2>/dev/null \
    | jq -e 'has("encrypted_data") and has("encryption_version") and (has("resources") | not)' >/dev/null 2>&1
}

# _m05x_nb_current — nombre de templates gold + debian13 + current.
_m05x_nb_current() {
  remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null | jq -r '
    [.[] | select(.template == 1)
     | ((.tags // "") | split(";")) as $t
     | select(($t | index("gold")) and ($t | index("debian13")) and ($t | index("current")))] | length' 2>/dev/null
}

# _m05x_vms_env_pve — « VMID statut » des VMs étiquetées env-m05 (Proxmox).
_m05x_vms_env_pve() {
  remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null | jq -r '
    .[] | select((.template // 0) == 0)
    | select((.tags // "") | split(";") | index("env-m05"))
    | "\(.vmid) \(.status)"' 2>/dev/null
}

# _m05x_ip_vm VMID — première IPv4 10.10.99.x rapportée par l'agent QEMU.
_m05x_ip_vm() {
  remote "$WB_PVE_HOST" "qm guest cmd $1 network-get-interfaces" 2>/dev/null | jq -r '
    (if type == "object" then .result else . end) // []
    | .[] | (."ip-addresses" // [])[] | ."ip-address" | select(startswith("10.10.99."))' 2>/dev/null | head -n 1
}

# _m05x_aucune_panne_active EXX — la panne de l'exercice n'est plus marquée active (close).
_m05x_aucune_panne_active() {
  [[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M05-$1" ]]
}

# _m05x_aucun_override — aucun fichier de surcharge (*_override.tf, override.tf) dans infra.
_m05x_aucun_override() {
  [[ -z "$(find "$_m05x_infra" -path '*/.terraform' -prune -o \( -name 'override.tf' -o -name '*_override.tf' -o -name 'override.tf.json' -o -name '*_override.tf.json' \) -print 2>/dev/null)" ]]
}

# _m05x_lock_suivi DOSSIER — .terraform.lock.hcl versionné et identique à celui du dépôt.
_m05x_lock_suivi() {
  local f="$1/.terraform.lock.hcl"
  [[ -f "$f" ]] && git -C "$1" ls-files --error-unmatch .terraform.lock.hcl >/dev/null 2>&1 \
    && git -C "$1" diff --quiet -- .terraform.lock.hcl
}
