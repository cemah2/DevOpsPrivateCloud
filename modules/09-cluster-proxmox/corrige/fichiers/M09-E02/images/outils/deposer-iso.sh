#!/usr/bin/env bash
# deposer-iso.sh — télécharge une ISO d'installation, vérifie la SIGNATURE du fichier de
# sommes puis la somme de l'ISO, et la dépose dans le contenu « iso » d'un stockage Proxmox
# (M03-E05, M03-E06). Famille « proxmox-ve » ajoutée en M09-E02 : Proxmox signe l'ISO
# elle-même (signature détachée .asc), pas un fichier de sommes.
#
# Usage (root sur pve01) :  deposer-iso.sh debian13|rocky10|proxmox-ve [STOCKAGE] [VERSION]
#                           (défauts : hdd-bulk ; VERSION, pour proxmox-ve seulement : 9.2-1)
# Depuis adm01 :            ssh pve01 'bash -s' -- proxmox-ve < outils/deposer-iso.sh
#
# Affiche à la fin le nom de l'ISO et son SHA-256, à reporter dans variables.pkr.hcl
# (iso_name, iso_sha256). Code 0 si l'ISO est déposée et vérifiée, 1 sinon.
# Rien n'est déposé tant que la signature ET la somme ne sont pas vérifiées.
set -euo pipefail

famille="${1:-}"
stockage="${2:-hdd-bulk}"
version_pve="${3:-9.2-1}"

case "$famille" in
  debian13)
    base="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
    sommes="SHA256SUMS"
    signature="SHA256SUMS.sign"
    # « Debian CD signing key » — https://www.debian.org/CD/verify
    empreinte="DF9B9C49EAA9298432589D76DA87E80D6294BE9B"
    cle_url=""
    motif='debian-13\.[0-9]+\.[0-9]+-amd64-netinst\.iso'
    ;;
  rocky10)
    base="https://download.rockylinux.org/pub/rocky/10/isos/x86_64"
    sommes="CHECKSUM"
    signature="CHECKSUM.asc"
    # « Release Engineering (Rocky Linux 10) » — https://rockylinux.org/resources/gpg-key-info
    empreinte="FC226859C0860BF0DDB95B085B106C736FEDFC85"
    cle_url="https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-10"
    motif='Rocky-10\.[0-9]+-x86_64-boot\.iso'
    ;;
  proxmox-ve)
    base="https://enterprise.proxmox.com/iso"
    # Clés de publication de Proxmox (https://pve.proxmox.com/wiki/Downloads) : l'ISO 9.x
    # porte deux signatures, clé « trixie » et clé « bookworm » ; l'une des deux suffit.
    # Elles sont déjà dans le trousseau APT de pve01 (paquet proxmox-archive-keyring) :
    # on vérifie avec ce trousseau, sans rien importer depuis Internet.
    empreintes_pve="24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E F4E136C67CDCE41AE6DE6FC81140AF8F639E0C39"
    nom="proxmox-ve_${version_pve}.iso"
    [[ "$version_pve" =~ ^[0-9]+\.[0-9]+-[0-9]+$ ]] || { echo "version invalide : $version_pve" >&2; exit 2; }
    ;;
  *)
    echo "Usage : $0 debian13|rocky10|proxmox-ve [STOCKAGE] [VERSION]" >&2
    exit 2
    ;;
esac

for c in curl gpg gpgv sha256sum pvesm; do
  command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }
done
[[ $EUID -eq 0 ]] || { echo "à lancer en root sur pve01" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GNUPGHOME="$tmp/gnupg"
install -d -m 700 "$GNUPGHOME"

if [[ "$famille" == proxmox-ve ]]; then
  # Trousseau APT de Proxmox présent sur pve01 (PVE 9 : proxmox-archive-keyring ; PVE 8 :
  # fichier de la clé bookworm dans trusted.gpg.d).
  trousseau=""
  for t in /usr/share/keyrings/proxmox-archive-keyring.gpg \
           /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg \
           /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg; do
    [[ -s "$t" ]] && { trousseau="$t"; break; }
  done
  [[ -n "$trousseau" ]] || { echo "ÉCHEC : aucun trousseau Proxmox sur cet hôte" >&2; exit 1; }
  echo "== Trousseau : $trousseau"

  dest="$(pvesm path "$stockage:iso/$nom")"
  dossier="$(dirname "$dest")"
  install -d "$dossier"
  curl -fsSL -o "$tmp/$nom.asc" "$base/$nom.asc"
  if [[ -f "$dest" ]]; then
    echo "== $nom déjà présente : vérification de sa signature"
    candidat="$dest"
  else
    echo "== Téléchargement de $nom vers $dossier"
    curl -fL --retry 3 -o "$dest.partiel" "$base/$nom"
    candidat="$dest.partiel"
  fi
  # gpgv : vérification sans base de confiance, avec ce seul trousseau. On exige une signature
  # VALIDE (VALIDSIG) faite par l'une des clés attendues (empreinte complète).
  etat="$(gpgv --keyring "$trousseau" --status-fd 1 "$tmp/$nom.asc" "$candidat" 2>/dev/null)" || true
  valide=""
  for e in $empreintes_pve; do
    # VALIDSIG <clé signataire> … <clé primaire> : l'empreinte attendue est l'une des deux.
    grep -Eq "^\[GNUPG:\] VALIDSIG ([^ ]+ )*$e( |$)" <<<"$etat" && valide="$e"
  done
  if [[ -z "$valide" ]]; then
    [[ "$candidat" == "$dest.partiel" ]] && rm -f "$candidat"
    echo "ÉCHEC : signature de $nom absente, invalide ou faite par une clé inattendue" >&2
    exit 1
  fi
  [[ "$candidat" == "$dest.partiel" ]] && mv -f "$candidat" "$dest"
  echo "signature valide ($valide)"
  echo
  echo "ISO vérifiée et déposée : $stockage:iso/$nom"
  printf 'iso_name   = "%s"\niso_sha256 = "%s"\n' "$nom" "$(sha256sum "$dest" | cut -d' ' -f1)"
  exit 0
fi

echo "== Clé de signature attendue : $empreinte"
if [[ -n "$cle_url" ]]; then
  curl -fsSL -o "$tmp/cle.asc" "$cle_url"
  gpg --batch --quiet --import "$tmp/cle.asc"
else
  gpg --batch --quiet --keyserver hkps://keyring.debian.org --recv-keys "$empreinte"
fi
# La clé importée doit être EXACTEMENT celle attendue (empreinte complète, pas l'ID court).
# (Sorties capturées avant le grep : avec pipefail, « grep -q » qui sort tôt ferait échouer le tube.)
empreintes="$(gpg --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" { print $10 }')"
grep -qx "$empreinte" <<<"$empreintes" \
  || { echo "ÉCHEC : la clé importée n'a pas l'empreinte attendue" >&2; exit 1; }

echo "== Fichier de sommes et signature"
curl -fsSL -o "$tmp/$sommes" "$base/$sommes"
curl -fsSL -o "$tmp/$signature" "$base/$signature"
etat="$(gpg --batch --status-fd 1 --verify "$tmp/$signature" "$tmp/$sommes" 2>/dev/null)" || true
grep -q "^\[GNUPG:\] VALIDSIG $empreinte " <<<"$etat" \
  || { echo "ÉCHEC : signature de $sommes invalide ou faite par une autre clé" >&2; exit 1; }
echo "signature de $sommes valide ($empreinte)"

# Nom et somme de l'ISO, selon le format du fichier :
#   Debian : « <sha256>  <nom> »      Rocky : « SHA256 (<nom>) = <sha256> »
ligne="$(grep -E "$motif" "$tmp/$sommes" | grep -v '^#' | sed -n 1p)" \
  || { echo "ÉCHEC : aucune ISO correspondant à $motif dans $sommes" >&2; exit 1; }
if [[ "$famille" == debian13 ]]; then
  attendu="${ligne%% *}"
  nom="${ligne##* }"
else
  attendu="${ligne##* = }"
  nom="$(sed -E 's/^SHA256 \(([^)]+)\).*/\1/' <<<"$ligne")"
fi
[[ "$attendu" =~ ^[0-9a-f]{64}$ && "$nom" =~ ^$motif$ ]] \
  || { echo "ÉCHEC : ligne de $sommes illisible : $ligne" >&2; exit 1; }

dest="$(pvesm path "$stockage:iso/$nom")"
dossier="$(dirname "$dest")"
if [[ -f "$dest" ]] && [[ "$(sha256sum "$dest" | cut -d' ' -f1)" == "$attendu" ]]; then
  echo "déjà présente et conforme : $stockage:iso/$nom"
else
  echo "== Téléchargement de $nom vers $dossier"
  install -d "$dossier"
  # Fichier partiel dans le même dossier (renommage atomique), jamais visible sous son nom final.
  curl -fL --retry 3 -o "$dest.partiel" "$base/$nom"
  obtenu="$(sha256sum "$dest.partiel" | cut -d' ' -f1)"
  if [[ "$obtenu" != "$attendu" ]]; then
    rm -f "$dest.partiel"
    echo "ÉCHEC : somme de l'ISO incorrecte (obtenu $obtenu, attendu $attendu)" >&2
    exit 1
  fi
  mv -f "$dest.partiel" "$dest"
fi

echo
echo "ISO vérifiée et déposée : $stockage:iso/$nom"
printf 'iso_name   = "%s"\niso_sha256 = "%s"\n' "$nom" "$attendu"
