# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur un hôte distant ou par bash -c
#
# check-E46.sh — M05-E46 « Mini-projet : l'infrastructure MédiSphère déclarée »
# Contrôle global de la livraison (à lancer depuis adm01). Lecture seule : API GitLab en GET (jeton
# des checks), S3 en lecture, OpenTofu en lecture (plan sans verrou, show, state list), qm en lecture.
# Durée : quelques minutes (plan complet du socle).

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E46 — L'infrastructure MédiSphère déclarée : contrôle global"
require_cmd tofu aws jq git curl ssh dig

_m05_e46_infra="plateforme%2Finfra"
_m05_e46_mods="plateforme%2Ftofu-modules"
_m05_e46_doc="$_m05x_depot/docs/socle"

# --- 1. Forge ---------------------------------------------------------------------------------
title "1/8 Forge (plateforme/infra, plateforme/tofu-modules)"

_m05_e46_protegee() {
  gitlab_api "projects/$1/protected_branches/main" | jq -e '.push_access_levels | all(.access_level == 0)' >/dev/null
}
_m05_e46_mr_pipeline() {
  gitlab_api "projects/$_m05_e46_infra" | jq -e '.only_allow_merge_if_pipeline_succeeds == true' >/dev/null
}
_m05_e46_pipeline_main() {
  local id j
  id="$(gitlab_api "projects/$_m05_e46_infra/pipelines?ref=main&per_page=1" | jq -r '.[0] | select(.status == "success") | .id')" || return 1
  [[ -n "$id" ]] || return 1
  j="$(gitlab_api "projects/$_m05_e46_infra/pipelines/$id/jobs?per_page=100")" || return 1
  jq -e '[.[].name] as $n | ($n | any(test("plan"))) and ($n | any(test("apply")))' >/dev/null <<<"$j"
}
_m05_e46_apply_protege() {
  local j
  j="$(gitlab_api "projects/$_m05_e46_infra/jobs?per_page=100")" || return 1
  jq -e '[.[] | select(.name | test("apply"))] | length > 0 and all(.[]; .ref == "main")' >/dev/null <<<"$j"
}
_m05_e46_planif() {
  gitlab_api "projects/$_m05_e46_infra/pipeline_schedules?scope=active" | jq -e 'length > 0' >/dev/null
}
_m05_e46_planif_verte() {
  gitlab_api "projects/$_m05_e46_infra/pipelines?source=schedule&per_page=1" | jq -e '.[0].status == "success"' >/dev/null
}
_m05_e46_release_mods() {
  gitlab_api "projects/$_m05_e46_mods/releases?per_page=1" | jq -e '.[0].tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")' >/dev/null
}

check_cmd "plateforme/infra : main protégée (aucun push direct)" _m05_e46_protegee "$_m05_e46_infra"
check_cmd "plateforme/infra : fusion seulement si le pipeline réussit" _m05_e46_mr_pipeline
check_cmd "plateforme/infra : dernier pipeline de main réussi, avec plan et apply" _m05_e46_pipeline_main
check_cmd "plateforme/infra : les jobs apply ne tournent que sur main" _m05_e46_apply_protege
check_cmd "plateforme/infra : détection de dérive planifiée (planification active)" _m05_e46_planif
check_cmd "plateforme/infra : dernier pipeline planifié réussi" _m05_e46_planif_verte
check_cmd "plateforme/tofu-modules : main protégée" _m05_e46_protegee "$_m05_e46_mods"
check_cmd "plateforme/tofu-modules : version publiée (release vX.Y.Z)" _m05_e46_release_mods

# --- 2. Code ----------------------------------------------------------------------------------
title "2/8 Code ($_m05x_infra)"

_m05_e46_ref_module() {
  grep -rEqs 'tofu-modules\.git//[^"?]+\?ref=v[0-9]+\.[0-9]+\.[0-9]+' --include='*.tf' --include='*.hcl' "$_m05x_infra"
}
_m05_e46_ci() { cat "$_m05x_infra/.gitlab-ci.yml" "$_m05x_infra"/ci/*.yml 2>/dev/null; }
_m05_e46_trivy_empreinte() { _m05_e46_ci | grep -i 'trivy' | grep -Eq 'sha256[:=]?[0-9a-f]{12,}|@sha256:'; }
_m05_e46_a_jour() {
  local distant
  distant="$(gitlab_api "projects/$_m05_e46_infra/repository/branches/main" | jq -r '.commit.id // empty')" || return 1
  [[ -n "$distant" && "$(git -C "$_m05x_infra" rev-parse HEAD)" == "$distant" ]]
}

check_output "copie de travail propre" '^$' git -C "$_m05x_infra" status --porcelain
check_cmd "copie de travail sur le dernier commit de main (forge)" _m05_e46_a_jour
check_cmd "les modules sont consommés par étiquette de version (?ref=vX.Y.Z)" _m05_e46_ref_module
check_cmd "pipeline : analyse Checkov présente" bash -c '_c="$(cat "$1/.gitlab-ci.yml" "$1"/ci/*.yml 2>/dev/null)"; grep -qi checkov <<<"$_c"' _ "$_m05x_infra"
check_cmd "pipeline : Trivy épinglé par empreinte (sha256)" _m05_e46_trivy_empreinte
check_cmd "socle et envs : .terraform.lock.hcl versionnés et inchangés" \
  bash -c 'for d in "$@"; do git -C "$d" diff --quiet -- .terraform.lock.hcl && git -C "$d" ls-files --error-unmatch .terraform.lock.hcl >/dev/null 2>&1 || exit 1; done' _ "$_m05x_socle" "$_m05x_envs"
check_cmd "socle : VMs permanentes protégées par prevent_destroy" \
  grep -rEqs 'prevent_destroy[[:space:]]*=[[:space:]]*true' --include='*.tf' "$_m05x_socle"

# --- 3. État distant --------------------------------------------------------------------------
title "3/8 État distant (s3-01, compartiment tofu-state)"

_m05_e46_envs_chiffre() {
  [[ "$(_m05x_s3_dernier "$_m05x_cle_envs")" == version:* ]] || return 0
  _m05x_objet_chiffre "$_m05x_cle_envs"
}
check_cmd "versionnage actif" _m05x_versionnage_actif
check_cmd "état socle : objet courant présent, historique conservé" \
  bash -c '[[ "$1" == version:* ]] && [ "$2" -ge 2 ]' _ "$(_m05x_s3_dernier "$_m05x_cle_socle")" "$(_m05x_s3_nb_versions "$_m05x_cle_socle")"
check_cmd "état socle chiffré par OpenTofu (aucune ressource lisible en clair dans l'objet)" _m05x_objet_chiffre "$_m05x_cle_socle"
check_cmd "état envs/lab-m05 chiffré (s'il existe)" _m05_e46_envs_chiffre
_m05_e46_sans_verrou() { _m05x_verrou_absent "$_m05x_cle_socle" && _m05x_verrou_absent "$_m05x_cle_envs"; }
check_cmd "aucun verrou d'état oublié (socle, envs)" _m05_e46_sans_verrou

# --- 4. Socle déclaré -------------------------------------------------------------------------
title "4/8 Socle déclaré"
check_cmd "socle : l'état contient adm01, dns01, git01, s3-01 et runner01" \
  _m05x_etat_contient "$_m05x_socle" 1001 1002 1004 1006 1007
check_cmd "socle : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_socle"
check_output "pve01 : une et une seule image dorée Debian porte current" '^1$' _m05x_nb_current

# --- 5. s3-01 ---------------------------------------------------------------------------------
title "5/8 s3-01 (VMID 1006)"
check_ssh_output "s3-01 : démarrée" "$WB_PVE_HOST" '^status: running' "qm status 1006"
check_ssh "s3-01 : démarrage automatique, étiquettes socle et role-s3" "$WB_PVE_HOST" \
  'c=$(qm config 1006); echo "$c" | grep -q "^onboot: 1" && echo "$c" | grep -Eq "^tags:.*(^|[ ;])role-s3([;]|$)" && echo "$c" | grep -Eq "^tags:.*(^|[ ;])socle([;]|$)"'
check_ssh "s3-01 : disque de données sur ${WB_STORAGE_BULK:-hdd-bulk}" "$WB_PVE_HOST" \
  "qm config 1006 | grep -Eq '^(scsi|virtio|sata)[1-9]+: ${WB_STORAGE_BULK:-hdd-bulk}:'"
check_ssh "s3-01 : dans le pool lab (sauvegardée par lab-nuit)" "$WB_PVE_HOST" \
  'pvesh get /pools/lab --output-format json | grep -Eq "\"vmid\" *: *1006([^0-9]|$)"'
check_dns "DNS : s3-01.par1.medisphere.internal" s3-01.par1.medisphere.internal A '^10\.10\.20\.14$' 10.10.20.10
check_dns "DNS : inverse de 10.10.20.14" 14.20.10.10.in-addr.arpa PTR 's3-01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_cmd "S3 : TLS vérifié sur 8333" curl -s -o /dev/null --max-time "$WB_TIMEOUT" https://s3-01.par1.medisphere.internal:8333/
check_cmd "Ansible : rôle seaweedfs avec scénario Molecule" \
  bash -c 'test -f "$1/roles/seaweedfs/tasks/main.yml" && find "$1/roles/seaweedfs" "$1/molecule" -name molecule.yml 2>/dev/null | grep -q seaweedfs' _ "${WB_SRC:-$HOME/src}/ansible"

# --- 6. Documentation ---------------------------------------------------------------------------
title "6/8 Documentation (docs/socle/)"
check_cmd "docs/socle/iac.md présent" test -s "$_m05_e46_doc/iac.md"
check_cmd "iac.md : état, verrou, chiffrement, restauration, dérive et import traités" \
  bash -c 'for m in verrou chiffr restaur dérive import; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m05_e46_doc/iac.md"
check_cmd "ADR-0050 présent" bash -c 'ls "$1"/adr/ADR-0050*.md >/dev/null 2>&1' _ "$_m05_e46_doc"
check_cmd "RB-050 présent" bash -c 'ls "$1"/runbooks/RB-050*.md >/dev/null 2>&1' _ "$_m05_e46_doc"
check_cmd "inventaire : s3-01 (10.10.20.14) recensée" \
  bash -c 'grep -q "s3-01" "$1" && grep -q "10\.10\.20\.14" "$1"' _ "$_m05_e46_doc/inventaire.md"
check_cmd "matrice des flux : port 8333 cité" grep -Eq '(^|[^0-9])8333([^0-9]|$)' "$_m05_e46_doc/matrice-flux.md"
check_cmd "registre des secrets : jeton wb-tofu, identifiants S3 et phrase de chiffrement inscrits" \
  bash -c 'for m in wb-tofu s3-tofu tofu-chiffrement; do grep -q -- "$m" "$1" || exit 1; done' _ "$_m05_e46_doc/registre-secrets.md"
check_output "dépôt de documentation : aucune modification non commitée" '^$' git -C "$_m05x_depot" status --porcelain

# --- 7. Secrets -------------------------------------------------------------------------------
title "7/8 Secrets"
check_cmd "fichiers de secrets du module en 600 (pve-tofu.env, s3-tofu.env, tofu-chiffrement.pass)" \
  bash -c 'for f in pve-tofu.env s3-tofu.env tofu-chiffrement.pass; do [ "$(stat -c %a "$1/$f" 2>/dev/null)" = 600 ] || exit 1; done' _ "$_m05x_cfg"
check_cmd "aucun secret du module commité dans plateforme/infra" \
  bash -c 'p=$(cat "$1"/tofu-chiffrement.pass 2>/dev/null); s=$(sed -n "s/^AWS_SECRET_ACCESS_KEY=//p" "$1/s3-tofu.env" 2>/dev/null | tr -d "\"'"'"'"); t=$(sed -n "s/^PROXMOX_VE_API_TOKEN=.*=//p" "$1/pve-tofu.env" 2>/dev/null | tr -d "\"'"'"'"); for v in "$p" "$s" "$t"; do [ -n "$v" ] || continue; git -C "$2" grep -qF -- "$v" $(git -C "$2" rev-list --all) 2>/dev/null && exit 1; done; exit 0' _ "$_m05x_cfg" "$_m05x_infra"

# --- 8. Hygiène -------------------------------------------------------------------------------
title "8/8 Hygiène du lab"
check_cmd "aucune panne M05 encore active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M05-E* >/dev/null 2>&1'
check_ssh "pve01 : VMs d'environnement 2050-2059 détruites" "$WB_PVE_HOST" \
  '! qm list | awk "NR > 1 { print \$1 }" | grep -Eq "^205[0-9]$"'
check_cmd "aucune copie d'état en clair dans ~/src/infra ni ~/medisphere" \
  bash -c '[ -z "$(find "$1" "$2" \( -name .terraform -o -name .git \) -prune -o -type f -name "*.tfstate*" -print 2>/dev/null)" ]' _ "$_m05x_infra" "$_m05x_depot"
