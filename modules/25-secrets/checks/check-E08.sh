# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E08.sh — M25-E08 : OpenBao en code avec OpenTofu
# À lancer depuis adm01. Lecture seule : fichiers et pipelines de plateforme/secrets (GitLab),
# politiques du serveur comparées à celles du dépôt, jetons vivants par leurs accessors (on cherche
# un jeton racine oublié ; un accessor ne permet pas d'utiliser le jeton).

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E08 — OpenBao en code avec OpenTofu"
require_cmd jq curl

# _m25d_e08_etat CODE — bloc backend S3 du lab, clé secrets/terraform.tfstate, verrou natif.
_m25d_e08_etat() {
  grep -Eq 'backend +"s3"' <<<"$1" && grep -Eq 'bucket *= *"tofu-state"' <<<"$1" \
    && grep -Eq 'key *= *"secrets/terraform\.tfstate"' <<<"$1" && grep -Eq 'use_lockfile *= *true' <<<"$1"
}

# --- 1. Le code --------------------------------------------------------------------------------------
_m25d_e08_tf=""
for _m25d_e08_f in fournisseurs.tf chiffrement.tf montages.tf methodes.tf oidc.tf approle.tf politiques.tf; do
  _m25d_e08_c="$(_m25d_contenu_main plateforme/secrets "tofu/$_m25d_e08_f")"
  check_cmd "plateforme/secrets : tofu/$_m25d_e08_f présent sur main" _m25d_contient "$_m25d_e08_c" '[a-z]'
  _m25d_e08_tf+="$_m25d_e08_c"$'\n'
done
check_cmd "Fournisseur hashicorp/vault épinglé en ~> 5.13 (aucun fournisseur « openbao » n'existe)" \
  _m25d_contient "$_m25d_e08_tf" 'source *= *"hashicorp/vault"'
check_cmd "Contrainte de version ~> 5.13" _m25d_contient "$_m25d_e08_tf" 'version *= *"~> ?5\.13(\.[0-9]+)?"'
check_cmd "État distant : compartiment tofu-state, clé secrets/terraform.tfstate, verrou natif" \
  _m25d_e08_etat "$_m25d_e08_tf"
check_cmd "État et plans chiffrés côté client (enforced)" _m25d_contient "$_m25d_e08_tf" 'enforced *= *true'
check_cmd "Aucun jeton dans le code (token = …, skip_tls_verify)" \
  _m25d_aucun '^[[:space:]]*(token|skip_tls_verify)[[:space:]]*=' "$_m25d_e08_tf"
check_cmd "Secret du client OIDC en écriture seule, lu par une ressource éphémère (jamais dans l'état)" \
  _m25d_contient "$_m25d_e08_tf" 'oidc_client_secret_wo *='
check_cmd "Aucun oidc_client_secret en clair ni par variable ordinaire" \
  _m25d_aucun '^[[:space:]]*oidc_client_secret[[:space:]]*=' "$_m25d_e08_tf"
check_cmd "Le verrou des versions (.terraform.lock.hcl) est versionné" \
  _m25d_contient "$(_m25d_contenu_main plateforme/secrets tofu/.terraform.lock.hcl)" 'registry\.opentofu\.org/hashicorp/vault'
check_output "Dernier pipeline de main de plateforme/secrets réussi" '^success$' _m25d_pipeline_main plateforme/secrets

# --- 2. Le serveur suit le code ------------------------------------------------------------------------------
_m25d_annoncer_acces
_m25d_e08_fichiers="$(_m25d_arbre_main plateforme/secrets politiques | grep -E '\.hcl$' || true)"
if [[ -z "$_m25d_e08_fichiers" ]]; then
  _ko "plateforme/secrets : aucun fichier politiques/*.hcl sur main"
else
  for _m25d_e08_p in plateforme-admin plateforme-lecture securite-audit mediagenda-dev wb-checks medictl; do
    check_cmd "politiques/$_m25d_e08_p.hcl versionnée" grep -qx "politiques/$_m25d_e08_p.hcl" <<<"$_m25d_e08_fichiers"
  done
  _m25d_e08_ecarts=""
  while IFS= read -r _m25d_e08_f; do
    _m25d_e08_n="$(basename "$_m25d_e08_f" .hcl)"
    if [[ "$(_m25d_contenu_main plateforme/secrets "$_m25d_e08_f" | _m25d_normaliser)" \
          != "$(_m25d_politique "$_m25d_e08_n" | _m25d_normaliser)" ]]; then
      _m25d_e08_ecarts+="$_m25d_e08_n "
    fi
  done <<<"$_m25d_e08_fichiers"
  check_cmd "Les politiques du serveur sont celles du dépôt (écarts : ${_m25d_e08_ecarts:-aucun})" test -z "$_m25d_e08_ecarts"
  _m25d_e08_en_trop="$(comm -23 <(_m25d_liste sys/policies/acl | grep -Evx 'default|root' | sort) \
    <(sed 's|^politiques/||; s|\.hcl$||' <<<"$_m25d_e08_fichiers" | sort) | paste -sd' ' || true)"
  check_cmd "Aucune politique sur le serveur hors du dépôt, sauf default et root (en trop : ${_m25d_e08_en_trop:-aucune})" \
    test -z "$_m25d_e08_en_trop"
fi

# --- 3. Plus de jeton racine ----------------------------------------------------------------------------------
_m25d_e08_racines="$(_m25d_jetons_racine)"
if [[ -z "$_m25d_e08_racines" ]]; then
  _ko "Jetons vivants illisibles (liste des accessors) : jeton racine non contrôlé"
else
  check_cmd "Aucun jeton racine vivant (jeton initial révoqué ; nouveau jeton par generate-root si besoin)" \
    test "$_m25d_e08_racines" -eq 0
fi
