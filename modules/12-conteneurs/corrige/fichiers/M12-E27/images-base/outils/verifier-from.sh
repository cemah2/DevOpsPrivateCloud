#!/usr/bin/env bash
# outils/verifier-from.sh — refuse les images non autorisées dans les Dockerfile et Containerfile
# (M12-E27, PLAT-1327). Lancé par le job « images-autorisees » de plateforme/ci-templates.
#
# Usage : verifier-from.sh LISTE [FICHIER...]    (sans fichier : tous les Dockerfile*/Containerfile*
#                                                  du dépôt, hors .git)
# Vérifie chaque FROM (étapes de construction comprises) et chaque COPY/RUN --mount « from= » qui
# désigne une IMAGE (pas une étape) ; résout les ARG déclarés avec une valeur par défaut, et les
# --build-arg passés par la variable ARGS_CONSTRUCTION (« NOM=valeur NOM2=valeur2 »).
# Codes retour : 0 tout est autorisé, 1 au moins une image refusée ou illisible, 2 usage.
set -euo pipefail

usage() { echo "Usage : $0 LISTE [FICHIER...]" >&2; exit 2; }
[[ $# -ge 1 && -r "$1" ]] || usage
liste="$1"; shift

motifs=() consignes=()
while IFS= read -r ligne || [[ -n "$ligne" ]]; do
  [[ "$ligne" =~ ^[[:space:]]*(#|$) ]] && continue
  motifs+=("$(sed -E 's/[[:space:]]*\|.*$//; s/^[[:space:]]+//' <<<"$ligne")")
  consignes+=("$(sed -nE 's/^[^|]*\|[[:space:]]*//p' <<<"$ligne")")
done <"$liste"
((${#motifs[@]} > 0)) || { echo "liste vide : $liste (rien n'est autorisé ne veut pas dire tout)" >&2; exit 1; }

if (($# == 0)); then
  mapfile -t fichiers < <(find . -path ./.git -prune -o -type f \( -name 'Dockerfile*' -o -name 'Containerfile*' \) -print | sort)
else
  fichiers=("$@")
fi
((${#fichiers[@]} > 0)) || { echo "aucun Dockerfile ni Containerfile trouvé" >&2; exit 1; }

autorisee() {
  local ref="$1" i
  for i in "${!motifs[@]}"; do
    # shellcheck disable=SC2053  # comparaison à un motif glob, voulue
    [[ "$ref" == ${motifs[$i]} ]] && return 0
  done
  return 1
}

erreurs=0
for f in "${fichiers[@]}"; do
  declare -A args=() etapes=()
  for a in ${ARGS_CONSTRUCTION:-}; do args["${a%%=*}"]="${a#*=}"; done
  # Lignes de continuation recollées, commentaires retirés.
  while IFS= read -r instr; do
    read -r -a mots <<<"$instr"
    ((${#mots[@]} > 0)) || continue
    cmd="${mots[0]^^}"
    case "$cmd" in
      ARG)
        for decl in "${mots[@]:1}"; do
          nom="${decl%%=*}"
          if [[ "$decl" == *=* && -z "${args[$nom]+x}" ]]; then args["$nom"]="${decl#*=}"; fi
        done
        continue ;;
      FROM)
        ref="" alias=""
        for ((i = 1; i < ${#mots[@]}; i++)); do
          case "${mots[$i]}" in
            --platform=*) ;;
            [Aa][Ss]) alias="${mots[$((i + 1))]:-}"; break ;;
            *) [[ -z "$ref" ]] && ref="${mots[$i]}" ;;
          esac
        done ;;
      COPY | RUN)
        ref=""
        for m in "${mots[@]:1}"; do
          case "$m" in
            --from=*) ref="${m#--from=}" ;;
            --mount=*from=*) ref="$(sed -nE 's/.*[=,]from=([^,]+).*/\1/p' <<<"$m")" ;;
          esac
        done
        [[ -n "$ref" ]] || continue ;;
      *) continue ;;
    esac
    # Résolution des ${VAR} et $VAR à partir des ARG connus.
    while [[ "$ref" =~ \$\{?([A-Za-z_][A-Za-z0-9_]*)\}? ]]; do
      v="${BASH_REMATCH[1]}"
      if [[ -z "${args[$v]+x}" ]]; then
        echo "REFUSÉ  $f : « $instr » — variable $v sans valeur connue (déclare un ARG par défaut)"
        erreurs=$((erreurs + 1)); ref=""; break
      fi
      ref="${ref//"${BASH_REMATCH[0]}"/${args[$v]}}"
    done
    [[ -n "$ref" ]] || continue
    if [[ -n "${etapes[$ref]+x}" || "$ref" =~ ^[0-9]+$ || "$ref" == scratch ]]; then
      : # étape précédente (nom ou numéro) ou image vide : rien à vérifier
    elif autorisee "$ref"; then
      echo "OK      $f : $ref"
    else
      erreurs=$((erreurs + 1))
      echo "REFUSÉ  $f : $ref"
      echo "        images autorisées (plateforme/images-base, images-autorisees.txt) :"
      for i in "${!motifs[@]}"; do echo "          ${motifs[$i]}   — ${consignes[$i]}"; done
    fi
    [[ "$cmd" == FROM && -n "$alias" ]] && etapes["$alias"]=1
  done < <(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$f" | sed -E 's/^[[:space:]]*#.*$//')
  unset args etapes
done

if ((erreurs > 0)); then
  echo "$erreurs référence(s) d'image refusée(s)."
  exit 1
fi
echo "Toutes les images de base sont autorisées."
