# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E08.sh — M03-E08 « Variables, fichiers de variables et secrets de build »
# Lecture seule. Exécute outils/construire.sh dans des cas qui doivent être REFUSÉS avant
# tout build (usage, fichier d'accès mal protégé : fichier temporaire factice).

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E08 — Variables, fichiers de variables et secrets de build"
require_cmd git shellcheck jq
_m03_e08_o="$_M03_SRC/outils/construire.sh"

title "Variables des images de base"
for _m03_e08_i in debian13-base rocky10-base; do
  _m03_e08_v="$_M03_SRC/$_m03_e08_i/variables.pkr.hcl"
  check_cmd "$_m03_e08_i : jeton marqué sensitive" \
    awk '/variable "proxmox_token"/ { d = 1 } d && /sensitive *= *true/ { ok = 1 } d && /^}/ { exit } END { exit !ok }' "$_m03_e08_v"
  check_cmd "$_m03_e08_i : vm_id contrôlé par une règle de validation" \
    awk '/variable "vm_id"/ { d = 1 } d && /validation/ { ok = 1 } d && /^}/ { exit } END { exit !ok }' "$_m03_e08_v"
  check_cmd "$_m03_e08_i : URL et identifiant du jeton contrôlés" \
    bash -c 'test "$(grep -c "validation *{" "$1")" -ge 3' _ "$_m03_e08_v"
  check_cmd "$_m03_e08_i : plus de variable build_password" \
    bash -c '! grep -q "variable \"build_password\"" "$1"' _ "$_m03_e08_v"
  check_cmd "$_m03_e08_i : mot de passe de build local, aléatoire et sensible" \
    bash -c 'grep -Eq "local \"build_password\"" "$1" && grep -Eq "uuidv4\(\)" "$1"' _ "$_M03_SRC/$_m03_e08_i/build.pkr.hcl"
done
check_cmd "vars/lab.pkrvars.hcl sans URL, jeton, identifiant ni nœud" \
  bash -c '! grep -Eq "^ *proxmox_(url|token|username|node) *=" "$1"' _ "$_M03_SRC/vars/lab.pkrvars.hcl"
check_cmd "vars/lab.pkrvars.hcl sur main" _m03_fichier_main vars/lab.pkrvars.hcl

title "Outil de construction"
check_cmd "outils/construire.sh exécutable" test -x "$_m03_e08_o"
check_cmd "sans remarque ShellCheck" shellcheck -x "$_m03_e08_o"
check_cmd "publié sur main" _m03_fichier_main outils/construire.sh
_m03_e08_code() { # CODE_ATTENDU commande… — le code de sortie vaut CODE_ATTENDU
  local attendu="$1" rc=0
  shift
  "$@" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "$attendu" ]]
}
check_cmd "image inconnue : refus d'usage (code 2)" _m03_e08_code 2 "$_m03_e08_o" image-inexistante
# Fichier d'accès factice lisible par tous : refus du garde-fou (code 3) avant tout build.
_m03_e08_tmp="$(mktemp -d)"
printf 'PKR_VAR_proxmox_url="https://controle.invalid:8006/api2/json"\nPKR_VAR_proxmox_username="controle@pve!controle"\nPKR_VAR_proxmox_token="controle-factice"\nPKR_VAR_proxmox_node="controle"\n' \
  >"$_m03_e08_tmp/acces.env"
chmod 644 "$_m03_e08_tmp/acces.env"
check_cmd "fichier d'accès lisible par d'autres : refus (code 3)" \
  _m03_e08_code 3 env -u PKR_VAR_proxmox_token PVE_PACKER_ENV="$_m03_e08_tmp/acces.env" "$_m03_e08_o" debian13-base
rm -rf "$_m03_e08_tmp"

# _m03_e08_notes VMID — champ « notes » (description) du template, texte brut (API, en root sur pve01).
_m03_e08_notes() {
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/qemu/$1/config --output-format json" 2>/dev/null \
    | jq -r '.description // ""'
}

title "Traçabilité et secrets"
_m03_e08_conf="$(_m03_e08_notes 9001)" || _m03_e08_conf=""
check_output "notes du template 9001 : commit du projet" 'commit [0-9a-f]{7,}' printf '%s\n' "$_m03_e08_conf"
check_output "notes du template 9001 : version du plugin" 'plugin proxmox v?[0-9]+\.[0-9]+\.[0-9]+' \
  printf '%s\n' "$_m03_e08_conf"
if command -v gitleaks >/dev/null 2>&1; then
  check_cmd "Gitleaks : aucun secret dans l'historique de plateforme/images" \
    gitleaks git --no-banner --redact --log-level error "$_M03_SRC"
else
  skip "balayage Gitleaks de l'historique" "gitleaks absent de ce poste"
fi
