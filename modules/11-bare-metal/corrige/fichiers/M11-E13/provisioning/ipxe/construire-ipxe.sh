#!/usr/bin/env bash
# construire-ipxe.sh — construit les chargeurs iPXE de la chaîne de provisioning MédiSphère
# (M11-E13) : undionly.kpxe (BIOS, pilote UNDI de la carte) et ipxe.efi (UEFI x86-64), avec
# HTTPS et la racine MédiSphère comme SEULE racine de confiance.
#
# À lancer dans la VM jetable 2117 « m11-build » (jamais sur adm01 ni sur pxe01) :
#   admin@m11-build:~$ ./construire-ipxe.sh /chemin/medisphere-root-ca.crt
# Versionné : ce script et ipxe/version.env (étiquette et commit de l'amont). Le binaire,
# lui, n'est PAS versionné : il est publié dans le registre de paquets génériques du projet
# (voir RB-110) et déposé sur pxe01 par le rôle Ansible pxe, qui vérifie son empreinte.
#
# Prérequis (Debian 13) : git, gcc, make, binutils, perl, liblzma-dev, openssl.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

usage() {
  echo "Usage : $0 <racine.crt> [dossier de sortie]" >&2
  echo "  <racine.crt> : racine MédiSphère (PEM), comparée à l'empreinte de version.env" >&2
  exit 2
}
[[ $# -ge 1 && $# -le 2 ]] || usage

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
racine="$(realpath "$1")"
sortie="$(realpath -m "${2:-$PWD/sortie-ipxe}")"
[[ -r "$racine" ]] || { echo "Racine illisible : $racine" >&2; exit 1; }

# version.env : IPXE_DEPOT, IPXE_ETIQUETTE, IPXE_COMMIT, RACINE_SHA256 (toutes obligatoires).
# shellcheck source=version.env
source "$ici/version.env"
for v in IPXE_DEPOT IPXE_ETIQUETTE IPXE_COMMIT RACINE_SHA256; do
  [[ -n "${!v:-}" && "${!v}" != "<"* ]] || { echo "Variable $v vide ou non renseignée dans version.env" >&2; exit 1; }
done

# 1. La racine fournie est bien LA racine MédiSphère (empreinte notée dans la politique de
#    certification, M06-E33) : on n'intègre pas au binaire un certificat pris au hasard.
empreinte="$(openssl x509 -in "$racine" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
if [[ "$empreinte" != "${RACINE_SHA256,,}" ]]; then
  echo "Empreinte de la racine inattendue : $empreinte" >&2
  echo "Attendue (version.env)         : ${RACINE_SHA256,,}" >&2
  exit 1
fi
openssl x509 -in "$racine" -noout -subject -enddate

# 2. Source de l'amont, à une étiquette précise, et vérification du commit (une étiquette se
#    déplace ; un identifiant de commit, non).
travail="$(mktemp -d)"
trap 'rm -rf -- "$travail"' EXIT
git clone --quiet --depth 1 --branch "$IPXE_ETIQUETTE" "$IPXE_DEPOT" "$travail/ipxe"
commit="$(git -C "$travail/ipxe" rev-parse HEAD)"
if [[ "$commit" != "$IPXE_COMMIT" ]]; then
  echo "Commit inattendu pour $IPXE_ETIQUETTE : $commit (attendu $IPXE_COMMIT)" >&2
  exit 1
fi
src="$travail/ipxe/src"

# 3. Le binaire doit savoir vérifier des signatures ECDSA : la PKI MédiSphère (step-ca) est
#    en P-256. Une version qui ne sait pas le faire produirait un binaire qui refuse pxe01.
if ! grep -rqil 'ecdsa' "$src/crypto/"; then
  echo "Cette version d'iPXE ne contient pas de code ECDSA : choisis une version plus récente." >&2
  exit 1
fi

# 4. Options : fichiers « local » (jamais écrasés par l'amont). On active HTTPS et quelques
#    commandes de diagnostic ; rien de plus (surface minimale).
mkdir -p "$src/config/local"
cat >"$src/config/local/general.h" <<'EOF'
/* config/local/general.h — options MédiSphère (M11-E13), voir ipxe.org/buildcfg */
#define DOWNLOAD_PROTO_HTTPS   /* HTTPS */
#undef  DOWNLOAD_PROTO_FTP     /* inutile */
#define NSLOOKUP_CMD           /* diagnostic DNS */
#define PING_CMD               /* diagnostic réseau */
#define CERT_CMD               /* certstat : voir les certificats connus */
#define IMAGE_TRUST_CMD        /* imgtrust / imgverify (pour aller plus loin) */
#define TIME_CMD               /* afficher l'heure : la validité TLS en dépend */
EOF

# 5. Construction. TRUST= : racines de confiance (remplace la racine du projet iPXE).
#    -j : parallélisme ; NO_WERROR non utilisé (on veut voir les erreurs de compilation).
make -C "$src" -j"$(nproc)" bin/undionly.kpxe TRUST="$racine"
make -C "$src" -j"$(nproc)" bin-x86_64-efi/ipxe.efi TRUST="$racine"

mkdir -p "$sortie"
install -m 0644 "$src/bin/undionly.kpxe" "$sortie/undionly.kpxe"
install -m 0644 "$src/bin-x86_64-efi/ipxe.efi" "$sortie/ipxe.efi"
{
  echo "# iPXE $IPXE_ETIQUETTE ($IPXE_COMMIT), racine $empreinte"
  (cd "$sortie" && sha256sum undionly.kpxe ipxe.efi)
} | tee "$sortie/SHA256SUMS"
echo "Binaires dans $sortie. Reporte les empreintes dans host_vars/pxe01/pxe.yml (pxe_chargeurs)."
