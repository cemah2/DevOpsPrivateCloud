#!/usr/bin/env bash
# =============================================================================
# outils/secrets-k8s.sh (plateforme/k8s) — Secrets Kubernetes créés DEPUIS Ansible Vault, hors Git.
# M19-E04 (PLAT-2004 / SEC-2004), généralisation de outils/ceph-csi-secrets.sh (M16-E06).
#
# Table des Secrets : outils/secrets-k8s.conf (une ligne par Secret, voir son en-tête).
# Valeurs : secrets/<composant>.yml, chiffré par l'identité Vault « critique » ; ou fichier public.
#
# Modes :
#   appliquer <composant>   crée ou met à jour les Secrets du composant, en server-side apply
#                           (gestionnaire de champs secrets-k8s), sans écrire ni afficher de valeur
#   verifier  <composant>   lecture seule : compare, par empreinte SHA-256 tronquée, chaque clé du
#                           Secret et sa source ; code 1 si un écart
#   lister                  composants et Secrets connus (sans valeur)
#
# Usage, sur adm01, depuis la racine de plateforme/k8s :
#   outils/secrets-k8s.sh appliquer gitlab-runner && outils/secrets-k8s.sh verifier gitlab-runner
# Variables :
#   MS_ANSIBLE_DIR  clone de plateforme/ansible (défaut ~/src/ansible : environnement uv d'ansible-vault)
#   MS_VAULT_ID     identité Vault (défaut critique@$MS_ANSIBLE_DIR/outils/vault-pass-client.sh)
#   KUBE_CONTEXTE   contexte kubectl (défaut k8s-par1 ; jamais le contexte courant par accident)
# Ne jamais lancer avec « bash -x » : la trace afficherait les valeurs.
# Codes retour : 0 conforme ou appliqué ; 1 écart ou échec ; 2 usage ou préalable manquant.
# =============================================================================
set -Eeuo pipefail
umask 077

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TABLE="${SECRETS_K8S_TABLE:-$RACINE/outils/secrets-k8s.conf}"
ANSIBLE_DIR="${MS_ANSIBLE_DIR:-$HOME/src/ansible}"
VAULT_ID="${MS_VAULT_ID:-critique@$ANSIBLE_DIR/outils/vault-pass-client.sh}"
CONTEXTE="${KUBE_CONTEXTE:-k8s-par1}"

usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; }
info() { printf '%s\n' "$*"; }
erreur() { printf 'secrets-k8s.sh : %s\n' "$*" >&2; }
k() { kubectl --context "$CONTEXTE" "$@"; }
# empreinte : SHA-256 tronqué de l'entrée, pour comparer sans afficher.
empreinte() { sha256sum | cut -c1-16; }

MODE="${1:-}"
COMPOSANT="${2:-}"
case "$MODE" in
  appliquer | verifier) [[ "$COMPOSANT" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { usage >&2; exit 2; } ;;
  lister) ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for outil in kubectl yq sha256sum; do
  command -v "$outil" >/dev/null || { erreur "$outil absent"; exit 2; }
done
[[ -r "$TABLE" ]] || { erreur "table illisible : $TABLE"; exit 2; }

# Lignes utiles de la table (sans commentaires ni lignes vides).
mapfile -t LIGNES < <(grep -Ev '^[[:space:]]*(#|$)' "$TABLE")

if [[ "$MODE" == lister ]]; then
  for ligne in "${LIGNES[@]}"; do
    read -r composant espace secret cles <<<"$ligne"
    info "$composant : $espace/$secret (clés : $(tr ' ' '\n' <<<"$cles" | cut -d= -f1 | paste -sd ' '))"
  done
  exit 0
fi

# Lignes du composant demandé.
SELECTION=()
for ligne in "${LIGNES[@]}"; do
  read -r composant _ <<<"$ligne"
  [[ "$composant" == "$COMPOSANT" ]] && SELECTION+=("$ligne")
done
((${#SELECTION[@]} > 0)) || { erreur "composant inconnu dans $TABLE : $COMPOSANT"; exit 2; }

# Le Vault n'est déchiffré que si une source « vault: » est utilisée ; en mémoire seulement.
CONTENU=""
if printf '%s\n' "${SELECTION[@]}" | grep -q '=vault:'; then
  FICHIER="$RACINE/secrets/$COMPOSANT.yml"
  [[ -r "$FICHIER" ]] || { erreur "fichier Vault illisible : $FICHIER"; exit 2; }
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête Ansible Vault
  head -n 1 "$FICHIER" | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique$' \
    || { erreur "$FICHIER n'est pas chiffré sous l'identité « critique »"; exit 2; }
  if ! CONTENU="$(cd "$ANSIBLE_DIR" && uv run ansible-vault view --vault-id "$VAULT_ID" "$FICHIER")"; then
    erreur "déchiffrement impossible (identité $VAULT_ID)"
    exit 1
  fi
fi

# valeur SOURCE — écrit la valeur d'une source sur la sortie standard (jamais à l'écran : appelée
# seulement dans une substitution de processus ou un tube).
valeur() {
  local source="$1" v
  case "$source" in
    vault:*)
      v="$(yq -r ".${source#vault:} // \"\"" <<<"$CONTENU")"
      [[ -n "$v" && "$v" != null ]] || { erreur "variable ${source#vault:} absente de secrets/$COMPOSANT.yml"; return 1; }
      printf '%s' "$v"
      ;;
    fichier:*)
      [[ -r "${source#fichier:}" ]] || { erreur "fichier illisible : ${source#fichier:}"; return 1; }
      cat -- "${source#fichier:}"
      ;;
    vide:) printf '' ;;
    *) erreur "source inconnue : $source (vault:, fichier:, vide:)"; return 1 ;;
  esac
}

ECARTS=0
for ligne in "${SELECTION[@]}"; do
  read -r _ espace secret cles <<<"$ligne"
  read -r -a paires <<<"$cles"

  if [[ "$MODE" == appliquer ]]; then
    # Contrôle préalable : toutes les sources sont lisibles (sinon on n'applique rien).
    for paire in "${paires[@]}"; do
      valeur "${paire#*=}" >/dev/null || exit 1
    done
    args=()
    for paire in "${paires[@]}"; do
      # Chaque valeur passe par un fichier temporaire 600 effacé aussitôt : elle n'apparaît ni dans
      # « ps », ni dans l'historique, ni dans une annotation last-applied-configuration.
      f="$(mktemp)"
      valeur "${paire#*=}" >"$f"
      args+=("--from-file=${paire%%=*}=$f")
    done
    k create secret generic "$secret" --namespace "$espace" "${args[@]}" --dry-run=client -o yaml \
      | k label --local -f - -o yaml \
          medisphere.internal/source=ansible-vault "medisphere.internal/composant=$COMPOSANT" \
      | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
    for a in "${args[@]}"; do shred -u "${a##*=}" 2>/dev/null || rm -f "${a##*=}"; done
    info "[OK] $espace/$secret à jour ($(printf '%s\n' "${paires[@]}" | cut -d= -f1 | paste -sd ' '))"
    continue
  fi

  # Mode verifier : empreintes seulement.
  json="$(k get secret "$secret" --namespace "$espace" -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] $espace/$secret absent"
    ECARTS=$((ECARTS + 1))
    continue
  fi
  for paire in "${paires[@]}"; do
    cle="${paire%%=*}"
    source_cle="${paire#*=}"
    e_source="$(valeur "${paire#*=}" | empreinte)" || { ECARTS=$((ECARTS + 1)); continue; }
    e_secret="$(yq -r ".data[\"$cle\"] // \"\"" <<<"$json" | base64 -d 2>/dev/null | empreinte)"
    if yq -e ".data | has(\"$cle\")" <<<"$json" >/dev/null 2>&1 && [[ "$e_secret" == "$e_source" ]]; then
      info "[OK] $espace/$secret : $cle identique à sa source"
    else
      info "[KO] $espace/$secret : $cle absente ou différente de sa source (source ${source_cle%%:*})"
      ECARTS=$((ECARTS + 1))
    fi
  done
done

if [[ "$MODE" == verifier ]] && ((ECARTS > 0)); then
  info "$ECARTS écart(s)"
  exit 1
fi
exit 0
