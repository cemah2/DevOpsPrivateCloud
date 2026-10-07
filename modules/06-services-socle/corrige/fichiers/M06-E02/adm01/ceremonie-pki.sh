#!/usr/bin/env bash
# ceremonie-pki.sh — racine hors ligne de la PKI MédiSphère (M06-E02), sur adm01.
#
# La racine ne vit QUE dans ~/pki-racine (700), clé chiffrée par une phrase de passe saisie
# au clavier (jamais écrite dans un fichier, jamais passée en argument). Elle ne sert qu'à
# signer des intermédiaires. À lancer en utilisateur admin, jamais en root.
#
#   ceremonie-pki.sh racine                 crée la racine (refuse d'écraser une racine existante)
#   ceremonie-pki.sh signer FICHIER.csr     signe la CSR d'un intermédiaire -> FICHIER.crt (5 ans)
#   ceremonie-pki.sh archiver               archive chiffrée (gpg symétrique) de ~/pki-racine
#   ceremonie-pki.sh verifier               contrôles de l'état de la racine et des archives
#
# Variables : PKI_RACINE (défaut ~/pki-racine), DUREE_RACINE (87600h = 10 ans),
#             DUREE_INTERMEDIAIRE (43800h = 5 ans).
set -euo pipefail

PKI_RACINE="${PKI_RACINE:-$HOME/pki-racine}"
DUREE_RACINE="${DUREE_RACINE:-87600h}"
DUREE_INTERMEDIAIRE="${DUREE_INTERMEDIAIRE:-43800h}"
CN_RACINE="MédiSphère Root CA"
CRT="$PKI_RACINE/medisphere-root-ca.crt"
CLE="$PKI_RACINE/medisphere-root-ca.key"
JOURNAL="$PKI_RACINE/journal-ceremonies.log"

umask 077

die() { echo "ceremonie-pki : $*" >&2; exit 1; }

prerequis() {
  [[ $EUID -ne 0 ]] || die "à lancer en utilisateur admin, pas en root."
  command -v step >/dev/null || die "step (paquet step-cli) introuvable."
  install -d -m 700 "$PKI_RACINE"
  [[ "$(stat -c %a "$PKI_RACINE")" == "700" ]] || die "$PKI_RACINE doit être en 700."
}

journaliser() {
  printf '%s %s %s\n' "$(date -Is)" "$(id -un)@$(hostname -s)" "$*" >>"$JOURNAL"
}

creer_racine() {
  prerequis
  [[ ! -e "$CLE" ]] || die "une racine existe déjà ($CLE). Une nouvelle racine invaliderait toute la PKI."
  echo "Phrase de passe de la racine : saisis-la deux fois ; range-la dans le gestionnaire de mots de passe."
  # Pas de --password-file : step la demande au terminal, elle ne touche jamais le disque.
  step certificate create "$CN_RACINE" "$CRT" "$CLE" \
    --profile root-ca --kty EC --curve P-384 --not-after "$DUREE_RACINE"
  chmod 600 "$CLE"
  chmod 644 "$CRT"
  grep -q 'ENCRYPTED' "$CLE" || die "la clé de la racine n'est pas chiffrée : la supprimer et recommencer."
  step certificate inspect "$CRT" --short
  echo "Empreinte SHA-256 : $(step certificate fingerprint "$CRT")"
  journaliser "racine créée, empreinte $(step certificate fingerprint "$CRT")"
}

signer() {
  prerequis
  local csr="${1:-}" sortie
  [[ -n "$csr" && -r "$csr" ]] || die "usage : $0 signer FICHIER.csr"
  [[ -r "$CLE" ]] || die "racine absente ($CLE) : lance d'abord « $0 racine »."
  sortie="${csr%.csr}.crt"
  [[ ! -e "$sortie" ]] || die "$sortie existe déjà : le déplacer avant de signer de nouveau."
  echo "CSR à signer :"
  step certificate inspect "$csr" --short
  read -r -p "Le sujet et la clé sont-ils ceux attendus (oui/non) ? " rep
  [[ "$rep" == "oui" ]] || die "signature annulée."
  # --path-len 0 : l'intermédiaire signe des certificats finaux, jamais une autre CA.
  step certificate sign --profile intermediate-ca --path-len 0 \
    --not-after "$DUREE_INTERMEDIAIRE" "$csr" "$CRT" "$CLE" >"$sortie"
  chmod 644 "$sortie"
  step certificate verify "$sortie" --roots "$CRT"
  step certificate inspect "$sortie" --short
  journaliser "intermédiaire signé : $(step certificate inspect "$sortie" --format json | jq -r '.serial_number') ($sortie)"
}

archiver() {
  prerequis
  [[ -r "$CLE" ]] || die "rien à archiver : racine absente."
  command -v gpg >/dev/null || die "gpg introuvable."
  local dest
  dest="$PKI_RACINE/archives/pki-racine-$(date +%Y%m%d-%H%M%S).tar.gpg"
  install -d -m 700 "$PKI_RACINE/archives"
  echo "Phrase de passe de l'ARCHIVE (différente de celle de la clé ; elle aussi au coffre) :"
  tar -C "$PKI_RACINE" --exclude=archives -cf - . | gpg --symmetric --cipher-algo AES256 --output "$dest"
  chmod 600 "$dest"
  sha256sum "$dest" | tee "$dest.sha256"
  journaliser "archive $dest"
  echo "Copie cette archive hors de adm01 (support amovible rangé au coffre). La sauvegarde PBS de adm01 en contient une autre."
}

verifier() {
  local ok=0
  # controle DESCRIPTION COMMANDE… — affiche OK ou KO, sans arrêter les contrôles suivants.
  controle() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "OK  $desc"; else echo "KO  $desc"; ok=1; fi
  }
  controle "$PKI_RACINE en 700" test "$(stat -c %a "$PKI_RACINE" 2>/dev/null)" = 700
  controle "clé de la racine présente et chiffrée" grep -q 'ENCRYPTED' "$CLE"
  controle "racine auto-signée valide" step certificate verify "$CRT" --roots "$CRT"
  controle "au moins une archive chiffrée" compgen -G "$PKI_RACINE/archives/*.tar.gpg"
  return "$ok"
}

case "${1:-}" in
  racine)   creer_racine ;;
  signer)   shift; signer "$@" ;;
  archiver) archiver ;;
  verifier) verifier ;;
  *) echo "Usage : $0 racine | signer FICHIER.csr | archiver | verifier" >&2; exit 2 ;;
esac
