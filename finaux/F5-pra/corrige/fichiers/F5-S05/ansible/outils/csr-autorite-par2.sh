#!/usr/bin/env bash
# outils/csr-autorite-par2.sh — clé et CSR de « MédiSphère PAR2 Intermediate CA » (F5-S05, PLAT-3505).
# Projet plateforme/ansible. À lancer SUR adm02 (PAR2), jamais sur une machine de PAR1 : la clé de
# l'autorité de PAR2 ne doit jamais avoir existé à PAR1.
#
#   1. génère la clé (EC P-256) et la CSR dans un dossier en mémoire ($XDG_RUNTIME_DIR, tmpfs) ;
#   2. chiffre la clé dans le fichier Ansible Vault « critique » secrets/pki-par2.yml (clé
#      pki_par2_cle), relu par l'amorçage de k8s-par2 (S06) ;
#   3. efface la clé en clair ; laisse la CSR (publique) dans pki/medisphere-par2-intermediate-ca.csr.
# La CSR part à la cérémonie (ceremonie-pki.sh signer, M06) : la racine fixe la durée et pathlen 0.
set -Eeuo pipefail
umask 077

racine_depot="$(git rev-parse --show-toplevel)"
cd "$racine_depot"
[[ "$(hostname -s)" == "adm02" ]] || { echo "à lancer sur adm02 (PAR2) seulement" >&2; exit 1; }
command -v step >/dev/null || { echo "step (step-cli) introuvable" >&2; exit 1; }
[[ -d "${XDG_RUNTIME_DIR:-}" ]] || { echo "XDG_RUNTIME_DIR absent : session sans tmpfs" >&2; exit 1; }
[[ ! -e secrets/pki-par2.yml ]] || { echo "secrets/pki-par2.yml existe déjà : une autorité de PAR2 existe" >&2; exit 1; }

travail="$(mktemp -d "$XDG_RUNTIME_DIR/pki-par2.XXXXXX")"
trap 'shred -u "$travail"/* 2>/dev/null; rmdir "$travail"' EXIT

step certificate create "MédiSphère PAR2 Intermediate CA" "$travail/par2.csr" "$travail/par2.key" \
  --csr --kty EC --curve P-256 --no-password --insecure
step certificate inspect "$travail/par2.csr" --short

# Clé → Ansible Vault « critique » (identité critique : vault-pass-client.sh ou mot de passe de l'enveloppe).
{
  echo "---"
  echo "# Clé de « MédiSphère PAR2 Intermediate CA » (F5-S05). Créée sur adm02 le $(date -I). Ne jamais déchiffrer à PAR1."
  echo "pki_par2_cle: |"
  sed 's/^/  /' "$travail/par2.key"
} | uv run ansible-vault encrypt --vault-id critique@outils/vault-pass-client.sh --output secrets/pki-par2.yml -

install -d pki
cp "$travail/par2.csr" pki/medisphere-par2-intermediate-ca.csr
echo "CSR : pki/medisphere-par2-intermediate-ca.csr (sujet et clé publique ci-dessus, à relire en cérémonie)"
echo "Suite : MR (CSR + secrets/pki-par2.yml chiffré), cérémonie sur adm01 (ceremonie-pki.sh signer)."
