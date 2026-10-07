#!/usr/bin/env bash
# tofu-valider.sh — « tofu validate » sur chaque configuration du dépôt (M05-E20).
#
# Appelé par le hook pre-commit tofu-validate (et utilisable à la main, depuis la racine).
# Chaque dossier qui contient des .tf est validé dans un dossier de travail JETABLE
# (TF_DATA_DIR) : on n'abîme jamais le .terraform/ de ta copie de travail (backend configuré,
# modules téléchargés), et on n'a besoin d'aucun accès S3 ni Proxmox (-backend=false).
# -lockfile=readonly (si le dossier a un .terraform.lock.hcl) : la validation échoue si le
# fichier ne correspond plus aux contraintes de versions, au lieu de le réécrire en douce.
# Un module réutilisable n'a pas de fichier de verrouillage : c'est la racine qui épingle.
set -euo pipefail

racine="$(git rev-parse --show-toplevel)"
cache="${TF_PLUGIN_CACHE_DIR:-$HOME/.cache/tofu/plugins}"
mkdir -p "$cache"
export TF_PLUGIN_CACHE_DIR="$cache" TF_INPUT=0

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT

echec=0
while IFS= read -r dossier; do
  rel="${dossier#"$racine"/}"
  donnees="$travail/$(printf '%s' "$rel" | tr '/' '_')"
  verrou=()
  cree=0
  if [[ -f "$dossier/.terraform.lock.hcl" ]]; then verrou=(-lockfile=readonly); else cree=1; fi
  if ! sortie="$(cd "$dossier" && TF_DATA_DIR="$donnees" tofu init -backend=false "${verrou[@]}" -no-color 2>&1)"; then
    printf '%s : tofu init a échoué\n%s\n' "$rel" "$sortie" >&2
    echec=1
    if ((cree)); then rm -f "$dossier/.terraform.lock.hcl"; fi
    continue
  fi
  if (cd "$dossier" && TF_DATA_DIR="$donnees" tofu validate -no-color >/dev/null 2>"$travail/erreur"); then
    printf 'ok   %s\n' "$rel"
  else
    printf 'KO   %s\n' "$rel" >&2
    cat "$travail/erreur" >&2
    echec=1
  fi
  # tofu init a écrit un fichier de verrouillage là où il n'y en avait pas (module) : on
  # rend la copie de travail telle qu'on l'a trouvée.
  if ((cree)); then rm -f "$dossier/.terraform.lock.hcl"; fi
done < <(find "$racine" -name '*.tf' -not -path '*/.terraform/*' -not -path '*/.terragrunt-cache/*' \
           -printf '%h\n' | sort -u)

exit "$echec"
