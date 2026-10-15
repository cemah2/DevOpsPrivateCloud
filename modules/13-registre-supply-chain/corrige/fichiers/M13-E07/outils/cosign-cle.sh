# shellcheck shell=bash
# outils/cosign-cle.sh — plateforme/outils (M13-E07). À SOURCER, ne s'exécute pas seul :
#   admin@adm01:~$ . ~/src/outils/cosign-cle.sh
# Charge la clé privée Cosign et sa phrase de passe depuis le Vault « critique » de
# plateforme/ansible dans COSIGN_KEY et COSIGN_PASSWORD (variables du shell courant, jamais sur
# disque), et définit MS_SIGNING_CONFIG (configuration de signature sans journal public).
# Oublier la clé ensuite : « cosign_oublier ».
_ms_ansible="${WB_SRC:-$HOME/src}/ansible"
_ms_doc="${WB_DEPOT:-$HOME/medisphere}"
if ! COSIGN_KEY="$(cd "$_ms_ansible" && uv run ansible-vault view --vault-id critique@outils/vault-pass-client.sh secrets/cosign/cosign.key)"; then
  echo "clé Cosign illisible (Vault critique)" >&2
  return 1
fi
COSIGN_PASSWORD="$(cd "$_ms_ansible" && uv run ansible-vault view --vault-id critique@outils/vault-pass-client.sh \
  inventories/lab/group_vars/all/vault-critique-cosign.yml | sed -n 's/^vault_cosign_mdp: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')"
export COSIGN_KEY COSIGN_PASSWORD
export MS_SIGNING_CONFIG="$_ms_doc/docs/registre/signing-config.json"
export MS_COSIGN_PUB="$_ms_doc/docs/registre/cosign.pub"
unset _ms_ansible _ms_doc
cosign_oublier() { unset COSIGN_KEY COSIGN_PASSWORD; }
echo "Clé Cosign chargée (COSIGN_KEY), configuration : $MS_SIGNING_CONFIG"
