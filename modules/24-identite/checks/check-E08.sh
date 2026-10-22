# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E08.sh — M24-E08 : Keycloak en code avec OpenTofu
# À lancer depuis adm01. Lecture seule : fichiers et pipelines de plateforme/identite (GitLab),
# API d'administration du royaume medisphere (wb-checks).

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E08 — Keycloak en code avec OpenTofu"
require_cmd jq curl

# _m24d_e08_aucun REGEX TEXTE — le texte est NON VIDE et aucune de ses lignes ne correspond.
_m24d_e08_aucun() { [[ -n "${2//[[:space:]]/}" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# _m24d_e08_etat CODE — bloc backend S3 du lab, clé identite/terraform.tfstate, verrou natif.
_m24d_e08_etat() {
  grep -Eq 'backend +"s3"' <<<"$1" && grep -Eq 'bucket *= *"tofu-state"' <<<"$1" \
    && grep -Eq 'key *= *"identite/terraform\.tfstate"' <<<"$1" && grep -Eq 'use_lockfile *= *true' <<<"$1"
}

# _m24d_e08_ci_ok CI — un plan sur les MR, un apply manuel limité à main.
_m24d_e08_ci_ok() {
  grep -q 'merge_request_event' <<<"$1" && grep -Eq 'tofu +(-chdir=[^ ]+ +)?plan' <<<"$1" \
    && grep -Eq 'tofu +(-chdir=[^ ]+ +)?apply' <<<"$1" && grep -q 'when: manual' <<<"$1" \
    && grep -q 'CI_DEFAULT_BRANCH' <<<"$1"
}

# _m24d_e08_deux_non_vides A B — les deux valeurs sont non vides.
_m24d_e08_deux_non_vides() { [[ -n "$1" && -n "$2" ]]; }

# --- 1. Le code ----------------------------------------------------------------------------------------
_m24d_e08_tf=""
for _m24d_e08_f in fournisseurs.tf royaume.tf federation-ldap.tf portees.tf comptes-service.tf chiffrement.tf; do
  _m24d_e08_c="$(_m24d_contenu_main plateforme/identite "tofu/$_m24d_e08_f")"
  check_cmd "plateforme/identite : tofu/$_m24d_e08_f présent sur main" _m24d_contient "$_m24d_e08_c" '[a-z]'
  _m24d_e08_tf+="$_m24d_e08_c"$'\n'
done
check_cmd "Fournisseur keycloak/keycloak épinglé en ~> 5.10 (plus mrparkers/keycloak)" \
  _m24d_contient "$_m24d_e08_tf" 'source *= *"keycloak/keycloak"'
check_cmd "Contrainte de version ~> 5.10" _m24d_contient "$_m24d_e08_tf" 'version *= *"~> ?5\.10(\.[0-9]+)?"'
check_cmd "Aucune trace de l'ancien fournisseur mrparkers/keycloak" _m24d_e08_aucun 'mrparkers/keycloak' "$_m24d_e08_tf"
check_cmd "État distant : compartiment tofu-state, clé identite/terraform.tfstate, verrou natif" \
  _m24d_e08_etat "$_m24d_e08_tf"
check_cmd "État et plans chiffrés côté client (bloc encryption, enforced)" \
  _m24d_contient "$_m24d_e08_tf" 'enforced *= *true'
check_cmd "Mot de passe de svc-keycloak : argument en écriture seule (bind_credential_wo), jamais dans le code ni dans l'état" \
  _m24d_contient "$_m24d_e08_tf" 'bind_credential_wo *='
check_cmd "Aucun bind_credential en clair dans le code" _m24d_e08_aucun '^[[:space:]]*bind_credential[[:space:]]*=' "$_m24d_e08_tf"
check_cmd "Aucun secret de client écrit dans le code (client_secret littéral)" \
  _m24d_e08_aucun '^[[:space:]]*client_secret[[:space:]]*=[[:space:]]*"' "$_m24d_e08_tf"
check_cmd "Plus de client essai-oidc dans le code" _m24d_e08_aucun '"essai-oidc"' "$_m24d_e08_tf"
check_cmd "Le verrou des versions (.terraform.lock.hcl) est versionné" \
  _m24d_contient "$(_m24d_contenu_main plateforme/identite tofu/.terraform.lock.hcl)" 'registry\.opentofu\.org/keycloak/keycloak'

# --- 2. Le pipeline ---------------------------------------------------------------------------------------
_m24d_e08_ci="$(_m24d_contenu_main plateforme/identite .gitlab-ci.yml)"
check_cmd ".gitlab-ci.yml : plan sur les MR (merge_request_event) et apply manuel sur main" \
  _m24d_e08_ci_ok "$_m24d_e08_ci"
check_output "Dernier pipeline de main de plateforme/identite réussi" '^success$' _m24d_pipeline_main plateforme/identite

# --- 3. Le royaume après l'apply ----------------------------------------------------------------------------
if [[ -z "$(_m24d_kc "")" ]]; then
  _ko "API d'administration du royaume medisphere illisible avec wb-checks"
else
  check_cmd "Keycloak : le client essai-oidc n'existe plus (supprimé par le code, pas à la main)" \
    test -z "$(_m24d_kc_client essai-oidc)"
  check_cmd "Keycloak : la fédération ipa01 et la portée groupes sont toujours là après l'apply" _m24d_e08_deux_non_vides \
    "$(_m24d_kc "components?type=org.keycloak.storage.UserStorageProvider" | jq -r '.[] | select(.providerId == "ldap") | .id' 2>/dev/null || true)" \
    "$(_m24d_kc "client-scopes" | jq -r '.[] | select(.name == "groupes") | .id' 2>/dev/null || true)"
  check_cmd "Keycloak : aucun client d'administration d'OpenTofu dans medisphere (svc-tofu-keycloak vit dans master)" \
    test -z "$(_m24d_kc_client svc-tofu-keycloak)"
fi
check_output "keycloak-tofu.env en 600 (secret du client d'OpenTofu, jamais dans un dépôt)" '^600$' \
  stat -c %a "$HOME/.config/workbook/keycloak-tofu.env"
