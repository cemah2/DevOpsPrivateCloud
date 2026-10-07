# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E03.sh — M05-E03 : Compte Proxmox wb-tofu, provider épinglé, premier plan
# À lancer depuis adm01. Lecture seule : comptes, rôles et droits lus en root sur pve01
# (pveum, pvesh), fichier d'accès lu sans afficher le secret, appel GET /version avec le
# jeton (TLS vérifié par le magasin système), copie de travail ~/src/infra, état local lu
# par jq, « tofu validate ».

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E03 — Compte Proxmox wb-tofu, provider épinglé, premier plan"
require_cmd git jq curl tofu

# --- Compte, jeton, rôle (pve01, root) -----------------------------------------------------------
_m05_users="$(_m05_pve "pveum user list --output-format json")"
check_output "Proxmox : l'utilisateur wb-tofu@pve existe" '^true$' \
  _m05_val "$_m05_users" 'any(.[]; .userid == "wb-tofu@pve")'
_m05_jetons="$(_m05_pve "pveum user token list wb-tofu@pve --output-format json")"
check_output "jeton wb-tofu@pve!tofu présent, à privilèges séparés (privsep)" '^1$' \
  _m05_val "$_m05_jetons" '[.[] | select(.tokenid == "tofu")][0].privsep // empty'
_m05_maintenant="$(date +%s)"
check_output "le jeton expire, dans un an au plus" '^ok$' \
  _m05_val "$_m05_jetons" "[.[] | select(.tokenid == \"tofu\")][0].expire // 0
    | if . > $_m05_maintenant and . <= ($_m05_maintenant + 367 * 86400) then \"ok\" else \"non\" end"

_m05_roles="$(_m05_pve "pveum role list --output-format json")"
_m05_privs="$(_m05_val "$_m05_roles" '[.[] | select(.roleid == "WBTofu")][0].privs // empty' | tr -s ', ;' '\n')"
check_cmd "le rôle WBTofu existe" test -n "$_m05_privs"
_m05_manquants=""
for _m05_p in VM.Audit VM.Clone VM.Allocate VM.Config.CPU VM.Config.Memory VM.Config.Disk \
  VM.Config.Network VM.Config.HWType VM.Config.Options VM.Config.Cloudinit VM.PowerMgmt VM.GuestAgent.Audit; do
  grep -qx "$_m05_p" <<<"$_m05_privs" || _m05_manquants+=" $_m05_p"
done
check_cmd "WBTofu permet de cloner, configurer, démarrer, détruire, lire l'agent${_m05_manquants:+ (manque :$_m05_manquants)}" \
  test -z "$_m05_manquants"
_m05_interdits="$(grep -Ex 'Sys\..*|Permissions\..*|User\..*|Realm\..*|Group\..*|Pool\.Allocate|Datastore\.Allocate|Datastore\.AllocateTemplate|VM\.Console|VM\.GuestAgent\.Unrestricted|VM\.GuestAgent\.File.*|SDN\.Allocate|Mapping\.Modify' \
  <<<"$_m05_privs" | tr '\n' ' ' || true)"
check_cmd "WBTofu ne contient aucun privilège d'administration ni d'accès à l'intérieur des invités${_m05_interdits:+ (trouvé : $_m05_interdits)}" \
  test -z "$_m05_interdits"

# --- Droits EFFECTIFS du jeton (intersection utilisateur / jeton) ----------------------------------
# _m05_droits CHEMIN — privilèges effectifs du jeton sur le chemin, un par ligne.
_m05_droits() {
  local j
  j="$(_m05_pve "pvesh get /access/permissions --userid 'wb-tofu@pve!tofu' --path '$1' --output-format json")"
  # Réponse : { chemin: { privilège: drapeau de propagation } } ; la présence de la clé suffit.
  jq -r --arg p "$1" '.[$p] // {} | keys[]' <<<"$j" 2>/dev/null || true
}
check_output "jeton : VM.Clone et VM.Allocate sur /pool/lab" '^2$' \
  bash -c 'grep -cEx "VM\.(Clone|Allocate)" <<<"$1"' _ "$(_m05_droits /pool/lab)"
check_output "jeton : allocation d'espace sur le stockage $_M05_STOCKAGE" '^Datastore\.AllocateSpace$' \
  _m05_droits "/storage/$_M05_STOCKAGE"
check_output "jeton : usage du VNet vsandbox" '^SDN\.Use$' _m05_droits /sdn/zones/lab/vsandbox
check_cmd "jeton : aucun privilège sur « / » (rien hors des chemins accordés)" \
  bash -c '[ -z "$1" ]' _ "$(_m05_droits /)"

# --- Fichier d'accès sur adm01 ---------------------------------------------------------------------
check_output "dossier des secrets .config/workbook en mode 700" '^700$' stat -c '%a' "$HOME/.config/workbook"
check_output "pve-tofu.env en mode 600" '^600$' stat -c '%a' "$_M05_ACCES"
check_cmd "pve-tofu.env : PROXMOX_VE_ENDPOINT en https sur le port 8006, sans /api2/json" \
  grep -Eq '^(export +)?PROXMOX_VE_ENDPOINT=["'\'']?https://[^/"'\'' ]+:8006/?["'\'']?[[:space:]]*$' "$_M05_ACCES"
check_cmd "pve-tofu.env : PROXMOX_VE_API_TOKEN au format wb-tofu@pve!tofu=<secret>" \
  grep -Eq '^(export +)?PROXMOX_VE_API_TOKEN=["'\'']?wb-tofu@pve!tofu=[0-9a-f-]{36}["'\'']?[[:space:]]*$' "$_M05_ACCES"
check_cmd "pve-tofu.env : la vérification TLS n'est pas désactivée" \
  bash -c '! grep -Eiq "^(export +)?PROXMOX_VE_INSECURE=[\"'\'']?(true|1)" "$1"' _ "$_M05_ACCES"
# Le secret ne quitte pas le sous-shell : en-tête passé par un descripteur, jamais en argument.
_m05_version_api() {
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M05_ACCES" 2>/dev/null || exit 1
    set +a
    curl -sS -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" \
      -H @<(printf 'Authorization: PVEAPIToken=%s\n' "$PROXMOX_VE_API_TOKEN") \
      "${PROXMOX_VE_ENDPOINT%/}/api2/json/version"
  ) 2>/dev/null || true
}
check_output "le jeton joint l'API de pve01, certificat vérifié par le magasin système (GET /version)" \
  '^200$' _m05_version_api

# --- Code et provider -------------------------------------------------------------------------------
check_cmd "envs/lab-m05/versions.tf : required_version limité à la série 1.13" \
  grep -Eq 'required_version[[:space:]]*=[[:space:]]*"(~>[[:space:]]*1\.13\.[0-9]+|>=[[:space:]]*1\.13[^"]*<[[:space:]]*1\.14[^"]*)"' \
  "$_M05_ENV/versions.tf"
check_cmd "envs/lab-m05/versions.tf : provider bpg/proxmox contraint à ~> 0.115.0" \
  bash -c 'grep -Eq "source[[:space:]]*=[[:space:]]*\"bpg/proxmox\"" "$1" \
    && grep -Eq "version[[:space:]]*=[[:space:]]*\"~>[[:space:]]*0\.115\.[0-9]+\"" "$1"' _ "$_M05_ENV/versions.tf"
check_output ".terraform.lock.hcl : bpg/proxmox 0.115.x du registre OpenTofu" '^0\.115\.[0-9]+$' \
  bash -c 'sed -n "/registry\.opentofu\.org\/bpg\/proxmox/,/^}/ s/^[[:space:]]*version[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$1"' \
  _ "$_M05_ENV/.terraform.lock.hcl"
check_cmd "main contient envs/lab-m05/.terraform.lock.hcl (versions et empreintes partagées)" \
  _m05_fichier_main envs/lab-m05/.terraform.lock.hcl
for _m05_f in versions.tf providers.tf; do
  check_cmd "main contient envs/lab-m05/$_m05_f" _m05_fichier_main "envs/lab-m05/$_m05_f"
done
check_cmd "aucun secret ni désactivation du TLS dans le code (api_token, password, insecure = true)" \
  bash -c '! grep -Eqs "^[^#]*(api_token|password)[[:space:]]*=|^[^#]*insecure[[:space:]]*=[[:space:]]*true" \
    "$1"/*.tf "$1"/*.tfvars' _ "$_M05_ENV"
check_cmd "tofu validate : la configuration est valide (providers installés par tofu init)" \
  _m05_tofu validate -no-color

# --- Premier plan appliqué -----------------------------------------------------------------------------
if _m05_backend_distant; then
  skip "état local : sortie version_pve" "état de envs/lab-m05 sur un backend distant : voir lab/bin/check 05 11"
else
  check_output "état local : la sortie version_pve contient une version de Proxmox VE 9" '^9\.' \
    _m05_etat '.outputs.version_pve.value // empty'
fi

# --- Registre des secrets -------------------------------------------------------------------------------
_m05_registre="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Fregistre-secrets.md/raw?ref=main" \
  2>/dev/null)" || _m05_registre=""
check_output "registre des secrets (plateforme/medisphere, main) : le jeton wb-tofu@pve!tofu y figure" \
  'wb-tofu@pve!tofu' printf '%s\n' "$_m05_registre"
_m05_registre=""
