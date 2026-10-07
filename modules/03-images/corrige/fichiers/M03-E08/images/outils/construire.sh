#!/usr/bin/env bash
# construire.sh — construit une image du projet plateforme/images avec Packer (M03-E08).
#
# Usage : outils/construire.sh [--brouillon] <image> [options packer…]
#   <image>       dossier du projet contenant build.pkr.hcl (debian13-base, rocky10-base…)
#   --brouillon   autorise un dépôt modifié non commité (le commit est alors marqué « -modifie »)
#   options       -var / -var-file supplémentaires, passées à validate et build (ex. -var vm_id=9010)
#
# Accès à Proxmox : variables PKR_VAR_proxmox_* déjà présentes dans l'environnement (CI),
# sinon lues dans $PVE_PACKER_ENV (défaut ~/.config/workbook/pve-packer.env, mode 600).
# Le secret n'est jamais passé en argument (visible dans « ps ») ni affiché.
#
# Codes retour : 0 succès · 1 échec du build ou de la validation · 2 usage · 3 refus d'un garde-fou
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fichier_env="${PVE_PACKER_ENV:-$HOME/.config/workbook/pve-packer.env}"

usage() { sed -n '4,7s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }
die() { echo "construire.sh : $1" >&2; exit "${2:-1}"; }

brouillon=0
if [[ "${1:-}" == "--brouillon" ]]; then brouillon=1; shift; fi
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "" | -*) usage >&2; exit 2 ;;
esac
image="${1%/}"
shift
[[ -f "$racine/$image/build.pkr.hcl" ]] || die "image inconnue : $image (pas de $image/build.pkr.hcl)" 2

for c in packer git; do command -v "$c" >/dev/null || die "outil manquant : $c"; done

# --- Secrets : de l'environnement (CI) ou du fichier protégé (poste d'administration) ---
if [[ -z "${PKR_VAR_proxmox_token:-}" ]]; then
  [[ -r "$fichier_env" ]] || die "fichier d'accès illisible : $fichier_env"
  droits="$(stat -c %a "$fichier_env")"
  [[ "$droits" == 600 ]] || die "$fichier_env doit être en mode 600 (actuellement $droits)" 3
  set -a
  # shellcheck source=/dev/null
  . "$fichier_env"
  set +a
fi
for v in PKR_VAR_proxmox_url PKR_VAR_proxmox_username PKR_VAR_proxmox_token PKR_VAR_proxmox_node; do
  [[ -n "${!v:-}" ]] || die "variable $v absente (fichier d'accès ou variables CI)"
done

# --- Traçabilité : quel code construit cette image ? ---------------------------------
commit="$(git -C "$racine" rev-parse --short=12 HEAD)"
if [[ -n "$(git -C "$racine" status --porcelain)" ]]; then
  ((brouillon)) || die "dépôt modifié non commité : commite, ou relance avec --brouillon" 3
  commit="$commit-modifie"
fi

export CHECKPOINT_DISABLE=1 # pas d'appel de Packer à HashiCorp pour vérifier les versions
mkdir -p "$racine/manifests"
journal="$racine/manifests/build-$image-$(date +%Y%m%d-%H%M%S).log"

cd "$racine/$image"
packer init .
version_plugin="$(packer plugins installed | sed -nE 's#.*packer-plugin-proxmox_(v[0-9.]+)_.*#\1#p' | sort -V | tail -n 1)"

args=(-var-file=../vars/lab.pkrvars.hcl -var "git_commit=$commit" -var "plugin_version=${version_plugin:-inconnue}")
packer validate "${args[@]}" "$@" . || die "configuration invalide"

# Un seul build à la fois par image sur cette machine (la CI a son propre « resource_group »).
exec 9>"$racine/manifests/.verrou-$image"
flock -n 9 || die "un build de $image est déjà en cours sur cette machine" 3

echo "== Construction de $image (commit $commit, plugin ${version_plugin:-?}) — journal : $journal"
# -force : le template précédent (même vm_id) est supprimé au début du build. Le vm_id
# est contrôlé par la validation des variables (plage 9001-9099 uniquement).
set +e
packer build -force -color=false "${args[@]}" "$@" . 2>&1 | tee "$journal"
rc=${PIPESTATUS[0]}
set -e
((rc == 0)) || die "échec du build de $image (code $rc) — voir $journal"
echo "== $image construite"
