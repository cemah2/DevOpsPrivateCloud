# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M03-E02 « Installer Packer et créer un compte Proxmox dédié »
# Lecture seule : Packer sur adm01, compte et droits sur pve01 (root, pveum), fichier
# d'accès (droits seulement : le secret n'est jamais lu), TLS, projet plateforme/images.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E02 — Installer Packer et créer un compte Proxmox dédié"
require_cmd jq curl git

_m03_e02_env="$HOME/.config/workbook/pve-packer.env"
# _m03_e02_non CMD… — réussit si la commande (ou fonction) échoue.
_m03_e02_non() { ! "$@"; }

title "Packer sur adm01"
check_output "packer 1.16.x installé" '^Packer v1\.16\.' packer version
check_output "paquet packer issu du dépôt apt.releases.hashicorp.com" 'apt\.releases\.hashicorp\.com' \
  apt-cache policy packer
# La clé HashiCorp ne doit être approuvée que pour son dépôt (Signed-By), pas globalement.
_m03_e02_cle_limitee() {
  grep -rlqs 'apt\.releases\.hashicorp\.com' /etc/apt/sources.list.d/ || return 1
  grep -rhs -A6 'apt\.releases\.hashicorp\.com' /etc/apt/sources.list.d/ | grep -Eqi 'signed-by'
}
check_cmd "dépôt HashiCorp déclaré avec une clé dédiée (Signed-By)" _m03_e02_cle_limitee
check_cmd "aucune clé HashiCorp approuvée pour tous les dépôts (/etc/apt/trusted.gpg.d)" \
  bash -c '! ls /etc/apt/trusted.gpg.d/ 2>/dev/null | grep -qi hashicorp'

title "Compte Proxmox wb-packer@pve (lu en root sur pve01)"
_m03_e02_role="$(remote "$WB_PVE_HOST" "pvesh get /access/roles/WBPacker --output-format json" 2>/dev/null)" \
  || _m03_e02_role="{}"
_m03_e02_a() { jq -e --arg p "$1" 'has($p) and (.[$p] == 1 or .[$p] == "1")' >/dev/null <<<"$_m03_e02_role"; }
check_cmd "rôle WBPacker présent" bash -c '[[ "$1" != "{}" ]]' _ "$_m03_e02_role"
for _m03_e02_p in VM.Allocate VM.Clone VM.Console VM.PowerMgmt VM.GuestAgent.Audit VM.Config.Cloudinit VM.Config.Options; do
  check_cmd "WBPacker contient $_m03_e02_p" _m03_e02_a "$_m03_e02_p"
done
_m03_e02_trop() {
  jq -e 'to_entries | map(select(.value == 1 or .value == "1") | .key)
    | any(.[]; test("^(Sys|Permissions|User|Realm|Group|Mapping)\\.")
              or . == "VM.GuestAgent.Unrestricted" or test("^VM\\.GuestAgent\\.File")
              or . == "Datastore.Allocate" or . == "Datastore.AllocateTemplate")' >/dev/null <<<"$_m03_e02_role"
}
check_cmd "WBPacker ne contient aucun privilège d'administration, d'exécution dans l'invité ni de téléversement" \
  _m03_e02_non _m03_e02_trop

_m03_e02_jetons="$(remote "$WB_PVE_HOST" "pvesh get /access/users/wb-packer@pve/token --output-format json" 2>/dev/null)" \
  || _m03_e02_jetons="[]"
check_cmd "jeton wb-packer@pve!packer présent" \
  jq -e 'any(.[]; .tokenid == "packer")' <<<"$_m03_e02_jetons"
check_cmd "jeton à privilèges séparés (privsep)" \
  jq -e 'any(.[]; .tokenid == "packer" and ((.privsep // 0) | tostring) == "1")' <<<"$_m03_e02_jetons"
check_cmd "jeton avec une date d'expiration (dans moins de 400 jours)" \
  jq -e --argjson n "$(date +%s)" 'any(.[]; .tokenid == "packer" and (.expire // 0) > $n and (.expire // 0) < ($n + 400*86400))' \
  <<<"$_m03_e02_jetons"

# Droits effectifs du JETON (intersection utilisateur/jeton) sur chaque chemin.
# (La valeur associée à un privilège est l'indicateur de propagation : seule la présence compte.)
_m03_e02_droit() { # CHEMIN PRIVILÈGE
  remote "$WB_PVE_HOST" "pveum user token permissions wb-packer@pve packer --path '$1' --output-format json" 2>/dev/null \
    | jq -e --arg c "$1" --arg p "$2" '(.[$c] // {}) | has($p)' >/dev/null
}
_m03_e02_nvme="${WB_STORAGE_NVME:-local-nvme}"
_m03_e02_bulk="${WB_STORAGE_BULK:-hdd-bulk}"
check_cmd "jeton : création de VM sur /pool/lab" _m03_e02_droit /pool/lab VM.Allocate
check_cmd "jeton : allocation d'espace sur /storage/$_m03_e02_nvme" _m03_e02_droit "/storage/$_m03_e02_nvme" Datastore.AllocateSpace
check_cmd "jeton : lecture de /storage/$_m03_e02_bulk (ISO)" _m03_e02_droit "/storage/$_m03_e02_bulk" Datastore.Audit
check_cmd "jeton : PAS d'allocation sur /storage/$_m03_e02_bulk" \
  _m03_e02_non _m03_e02_droit "/storage/$_m03_e02_bulk" Datastore.AllocateSpace
check_cmd "jeton : usage du VNet vsandbox" _m03_e02_droit /sdn/zones/lab/vsandbox SDN.Use
_m03_e02_racine() {
  remote "$WB_PVE_HOST" "pveum user token permissions wb-packer@pve packer --path / --output-format json" 2>/dev/null \
    | jq -e '(.["/"] // {}) | length == 0' >/dev/null
}
check_cmd "jeton : aucun droit sur / (nœud, configuration globale)" _m03_e02_racine

title "Fichier d'accès et TLS sur adm01"
check_output "dossier .config/workbook en mode 700" '^700$' stat -c %a "$HOME/.config/workbook"
check_output "pve-packer.env en mode 600" '^600$' stat -c %a "$_m03_e02_env"
for _m03_e02_v in PKR_VAR_proxmox_url PKR_VAR_proxmox_username PKR_VAR_proxmox_token PKR_VAR_proxmox_node; do
  check_cmd "pve-packer.env définit $_m03_e02_v" grep -Eq "^(export +)?$_m03_e02_v=" "$_m03_e02_env"
done
check_cmd "pve-packer.env hors de tout dépôt Git" \
  bash -c '! git -C "$(dirname "$1")" rev-parse --is-inside-work-tree >/dev/null 2>&1' _ "$_m03_e02_env"
# URL lue sans charger le secret. Sans jeton, l'API répond 401 : seule la poignée de main
# TLS est testée, avec le magasin système (pas de --cacert, pas de -k).
_m03_e02_url="$(sed -nE '0,/^(export +)?PKR_VAR_proxmox_url=/s/^(export +)?PKR_VAR_proxmox_url="?([^"]*)"?.*/\2/p' "$_m03_e02_env" 2>/dev/null)" \
  || _m03_e02_url=""
check_http "API de pve01 joignable avec certificat vérifié par le magasin système (401 sans jeton)" \
  "${_m03_e02_url%/}/version" 401

title "Projet plateforme/images"
check_cmd "projet plateforme/images présent" _m03_api_ok "$_M03_PROJET" '.default_branch == "main"'
check_cmd "fusion seulement si le pipeline réussit" _m03_api_ok "$_M03_PROJET" '.only_allow_merge_if_pipeline_succeeds'
check_cmd "main protégée : personne ne pousse" _m03_api_ok "$_M03_PROJET/protected_branches/main" \
  '[.push_access_levels[].access_level] | length > 0 and all(. == 0)'
check_cmd "main contient .pre-commit-config.yaml avec packer fmt" \
  _m03_fichier_main_contient .pre-commit-config.yaml 'packer fmt'
check_cmd "main contient le contrôle packer validate (-syntax-only)" \
  _m03_fichier_main_contient .pre-commit-config.yaml 'packer-validate|packer validate'
check_cmd ".gitlab-ci.yml inclut plateforme/ci-templates" \
  _m03_fichier_main_contient .gitlab-ci.yml 'plateforme/ci-templates'
check_cmd ".gitignore ignore les sorties de build (manifests/)" _m03_fichier_main_contient .gitignore '^/?manifests/?'
check_cmd "copie de travail ~/src/images" git -C "$_M03_SRC" rev-parse --is-inside-work-tree
check_cmd "registre des secrets : jeton wb-packer inscrit" \
  _m03_doc_contient "$_M03_DOC/registre-secrets.md" 'wb-packer'
