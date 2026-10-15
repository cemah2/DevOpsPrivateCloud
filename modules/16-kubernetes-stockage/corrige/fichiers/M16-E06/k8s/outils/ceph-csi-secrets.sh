#!/usr/bin/env bash
# =============================================================================
# outils/ceph-csi-secrets.sh (plateforme/k8s) — Secrets des identités cephx de ceph-csi, créés
# DEPUIS Ansible Vault. M16-E06 (RBD), M16-E07 (CephFS).
#
# Source unique : secrets/ceph-csi.yml, chiffré par l'identité Vault « critique » :
#   ceph_csi_rbd_cle: "<clé de client.k8s>"            (E06)
#   ceph_csi_cephfs_cle: "<clé de client.k8s-cephfs>"   (E07)
# Une variable absente = pilote pas encore installé : ignoré (signalé).
#
# Modes :
#   appliquer   crée ou met à jour ceph-csi/csi-rbd-secret et ceph-csi/csi-cephfs-secret
#               (userID, userKey), en server-side apply, sans écrire ni afficher de clé
#   verifier    lecture seule : compare, par empreinte SHA-256, la clé du Vault, celle du Secret et
#               celle que Ceph connaît (ssh $CEPH_ADMIN sudo ceph auth get-key) ; code 1 si écart
#
# Usage, sur adm01, depuis la racine de plateforme/k8s :
#   outils/ceph-csi-secrets.sh appliquer && outils/ceph-csi-secrets.sh verifier
# Variables :
#   MS_ANSIBLE_DIR  clone de plateforme/ansible (défaut ~/src/ansible : environnement uv d'ansible-vault)
#   MS_VAULT_ID     identité Vault (défaut critique@$MS_ANSIBLE_DIR/outils/vault-pass-client.sh)
#   CEPH_ADMIN      nœud _admin de ceph-par1 pour « verifier » (défaut ceph01)
# Ne jamais lancer avec « bash -x » : la trace afficherait les clés.
# Codes retour : 0 conforme ou appliqué ; 1 écart ou échec ; 2 usage ou préalable manquant.
# =============================================================================
set -Eeuo pipefail
umask 077

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FICHIER="${CEPH_CSI_VAULT_FICHIER:-$RACINE/secrets/ceph-csi.yml}"
ANSIBLE_DIR="${MS_ANSIBLE_DIR:-$HOME/src/ansible}"
VAULT_ID="${MS_VAULT_ID:-critique@$ANSIBLE_DIR/outils/vault-pass-client.sh}"
CEPH_ADMIN="${CEPH_ADMIN:-ceph01}"
ESPACE="ceph-csi"

# pilote | Secret Kubernetes | utilisateur cephx (sans « client. ») | variable du Vault
PILOTES=(
  "rbd|csi-rbd-secret|k8s|ceph_csi_rbd_cle"
  "cephfs|csi-cephfs-secret|k8s-cephfs|ceph_csi_cephfs_cle"
)

usage() { sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; }
info() { printf '%s\n' "$*"; }
erreur() { printf 'ceph-csi-secrets.sh : %s\n' "$*" >&2; }

MODE="${1:-}"
case "$MODE" in
  appliquer | verifier) ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for outil in kubectl yq sha256sum; do
  command -v "$outil" >/dev/null || { erreur "$outil absent"; exit 2; }
done
[[ -r "$FICHIER" ]] || { erreur "fichier Vault illisible : $FICHIER"; exit 2; }
# shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête Ansible Vault
head -n 1 "$FICHIER" | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique$' \
  || { erreur "$FICHIER n'est pas chiffré sous l'identité « critique »"; exit 2; }

# Déchiffrement en mémoire seulement (jamais de fichier en clair).
if ! CONTENU="$(cd "$ANSIBLE_DIR" && uv run ansible-vault view --vault-id "$VAULT_ID" "$FICHIER")"; then
  erreur "déchiffrement impossible (identité $VAULT_ID)"
  exit 1
fi

# empreinte : SHA-256 de son entrée, pour comparer sans afficher.
empreinte() { sha256sum | cut -c1-16; }

ECARTS=0
for entree in "${PILOTES[@]}"; do
  IFS='|' read -r pilote secret utilisateur variable <<<"$entree"
  cle="$(yq -r ".${variable} // \"\"" <<<"$CONTENU")"
  if [[ -z "$cle" || "$cle" == "null" ]]; then
    info "[--] $pilote : variable $variable absente du Vault, ignoré"
    continue
  fi
  # Une clé cephx est du base64 de 40 caractères : refuser une valeur manifestement fausse.
  [[ "$cle" =~ ^[A-Za-z0-9+/]{38}==$ ]] || { erreur "$pilote : $variable n'a pas la forme d'une clé cephx"; exit 1; }

  if [[ "$MODE" == appliquer ]]; then
    # --from-file sur une substitution de processus : la clé n'apparaît ni dans « ps » ni sur disque.
    # --server-side : pas d'annotation last-applied-configuration (qui recopierait le Secret).
    kubectl create secret generic "$secret" --namespace "$ESPACE" \
      --from-literal=userID="$utilisateur" \
      --from-file=userKey=<(printf '%s' "$cle") \
      --dry-run=client -o yaml \
      | kubectl label --local -f - -o yaml \
          medisphere.fr/composant=stockage medisphere.fr/source=ansible-vault \
      | kubectl apply --server-side --field-manager=ceph-csi-secrets -f - >/dev/null
    info "[OK] $pilote : Secret $ESPACE/$secret (userID=$utilisateur) à jour"
    continue
  fi

  # Mode verifier.
  e_vault="$(printf '%s' "$cle" | empreinte)"
  e_secret="$(kubectl get secret "$secret" --namespace "$ESPACE" -o jsonpath='{.data.userKey}' 2>/dev/null \
    | base64 -d 2>/dev/null | empreinte)" || e_secret=""
  u_secret="$(kubectl get secret "$secret" --namespace "$ESPACE" -o jsonpath='{.data.userID}' 2>/dev/null \
    | base64 -d 2>/dev/null)" || u_secret=""
  e_ceph="$(ssh -o BatchMode=yes "$CEPH_ADMIN" "sudo -n ceph auth get-key client.$utilisateur" 2>/dev/null \
    | empreinte)" || e_ceph=""
  vide="$(printf '' | empreinte)"
  if [[ "$e_secret" == "$vide" || -z "$e_secret" ]]; then
    info "[KO] $pilote : Secret $ESPACE/$secret absent ou sans userKey"
    ECARTS=$((ECARTS + 1))
  elif [[ "$e_secret" != "$e_vault" ]]; then
    info "[KO] $pilote : la clé du Secret diffère de celle du Vault"
    ECARTS=$((ECARTS + 1))
  else
    info "[OK] $pilote : Secret identique au Vault"
  fi
  if [[ "$u_secret" != "$utilisateur" ]]; then
    info "[KO] $pilote : userID du Secret = « $u_secret », attendu « $utilisateur » (sans « client. »)"
    ECARTS=$((ECARTS + 1))
  fi
  if [[ "$e_ceph" == "$vide" || -z "$e_ceph" ]]; then
    info "[KO] $pilote : client.$utilisateur illisible sur $CEPH_ADMIN (identité absente ? ssh ?)"
    ECARTS=$((ECARTS + 1))
  elif [[ "$e_ceph" != "$e_vault" ]]; then
    info "[KO] $pilote : la clé du Vault n'est plus celle de client.$utilisateur dans Ceph (rotation ?)"
    ECARTS=$((ECARTS + 1))
  else
    info "[OK] $pilote : Vault identique à Ceph (client.$utilisateur)"
  fi
done

if [[ "$MODE" == verifier ]] && ((ECARTS > 0)); then
  info "$ECARTS écart(s)"
  exit 1
fi
exit 0
