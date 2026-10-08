#!/usr/bin/env bash
# photographier-images.sh — M10-E28 : photographie des conteneurs Kolla et de leurs images, avant
# et après une mise à jour. Lecture seule. À lancer depuis adm01.
#
# Usage : photographier-images.sh [-n "osctl01 oscmp01 oscmp02"] FICHIER.tsv
#         photographier-images.sh --comparer AVANT.tsv APRES.tsv
#         photographier-images.sh --perimes [-n "…"]   conteneurs qui ne tournent PAS sur l'image
#                                                       actuellement désignée par leur étiquette
#
# Colonnes : nœud, conteneur, image (dépôt:étiquette), identifiant de l'image du conteneur,
# empreinte de dépôt (RepoDigest) de cette image, identifiant actuellement désigné par l'étiquette.
set -euo pipefail

noeuds="osctl01 oscmp01 oscmp02"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5)

# Sur un nœud : une ligne par conteneur (la boucle tourne sur le nœud).
# shellcheck disable=SC2016  # évalué sur le nœud
DISTANT='for c in $(sudo -n docker ps -a --format "{{.Names}}" | sort); do
  img=$(sudo -n docker inspect -f "{{.Config.Image}}" "$c")
  id=$(sudo -n docker inspect -f "{{.Image}}" "$c")
  dig=$(sudo -n docker image inspect -f "{{index .RepoDigests 0}}" "$id" 2>/dev/null || echo "-")
  cour=$(sudo -n docker image inspect -f "{{.Id}}" "$img" 2>/dev/null || echo "-")
  printf "%s\t%s\t%s\t%s\t%s\n" "$c" "$img" "$id" "$dig" "$cour"
done'

photographier() {
  local n
  for n in $noeuds; do
    "${SSH[@]}" "$n" "$DISTANT" | sed "s/^/$n\t/"
  done
}

if [[ "${1:-}" == "-n" ]]; then noeuds="$2"; shift 2; fi
case "${1:-}" in
  --comparer)
    [[ $# -eq 3 ]] || { echo "Usage : $0 --comparer AVANT.tsv APRES.tsv" >&2; exit 2; }
    # Clé nœud+conteneur ; on compare l'identifiant d'image.
    join -t $'\t' -a 1 -a 2 -e '(absent)' -o 0,1.5,2.5 \
      <(awk -F'\t' '{print $1"/"$2"\t"$0}' "$2" | sort) <(awk -F'\t' '{print $1"/"$2"\t"$0}' "$3" | sort) \
      | awk -F'\t' '$2 != $3 { n++; printf "%-40s %.19s → %.19s\n", $1, $2, $3 } END { printf "%d conteneur(s) changé(s)\n", n }'
    ;;
  --perimes)
    photographier | awk -F'\t' '$4 != $6 { n++; printf "%s/%s : tourne sur %.19s, étiquette → %.19s\n", $1, $2, $4, $6 }
                                END { printf "%d conteneur(s) sur une image périmée\n", n; exit (n > 0) }'
    ;;
  "" | -*) echo "Usage : $0 [-n NŒUDS] FICHIER.tsv | --comparer A B | --perimes" >&2; exit 2 ;;
  *)
    { printf 'noeud\tconteneur\timage\tid_conteneur\tempreinte\tid_etiquette\n'; photographier; } >"$1"
    echo "$(($(wc -l <"$1") - 1)) conteneur(s) photographié(s) dans $1"
    ;;
esac
