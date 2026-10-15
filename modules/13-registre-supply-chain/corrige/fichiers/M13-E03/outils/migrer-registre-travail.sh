#!/usr/bin/env bash
# outils/migrer-registre-travail.sh — plateforme/outils (M13-E03, PLAT-1403).
#
# Copie TOUTES les étiquettes des dépôts du registre de travail (ctr01:5000, M12-E15) vers Harbor,
# toutes architectures (--all), empreintes PRÉSERVÉES (--preserve-digests : skopeo échoue plutôt
# que de convertir un manifeste), puis contrôle que l'empreinte cible égale l'empreinte source.
# Identifiants : fichiers d'authentification (--src-authfile / --dest-authfile), jamais en argument.
#
# Usage (adm01) :
#   admin@adm01:~$ ~/src/outils/migrer-registre-travail.sh            # tout
#   admin@adm01:~$ ~/src/outils/migrer-registre-travail.sh --essai    # affiche sans copier
set -euo pipefail

SRC="ctr01.par1.medisphere.internal:5000"
DST="${WB_HARBOR_URL:-https://registry.par1.medisphere.internal}"; DST="${DST#https://}"
CFG="$HOME/.config/workbook"
ESSAI=0; [[ "${1:-}" == "--essai" ]] && ESSAI=1

# dépôt source → dépôt cible (projet/dépôt dans Harbor)
declare -A CORRESPONDANCES=(
  [mediagenda/api]=medisphere/mediagenda-api
  [medidoc/medidoc]=medisphere/medidoc
  [medinotif/worker]=medisphere/medinotif
  [legacy/legacy-rdv]=medisphere/legacy-rdv
)

TMP="$(mktemp -d /dev/shm/migration.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
umask 077

# login_fichier FICHIER_ENV REGISTRE AUTHFILE VAR_UTILISATEUR VAR_SECRET
login_fichier() {
  local env="$1" reg="$2" af="$3" vu="$4" vs="$5"
  [[ -r "$env" ]] || { echo "identifiants illisibles : $env" >&2; exit 2; }
  ( set +u
    # shellcheck disable=SC1090
    . "$env"
    printf '%s' "${!vs}" | skopeo login --authfile "$af" --username "${!vu}" --password-stdin "$reg" >/dev/null )
}
# registre-travail.env (M12-E15) : REGISTRE_UTILISATEUR, REGISTRE_MOT_DE_PASSE (adapte si besoin)
login_fichier "$CFG/registre-travail.env" "$SRC" "$TMP/src.json" REGISTRE_UTILISATEUR REGISTRE_MOT_DE_PASSE
login_fichier "$CFG/harbor-moi.env" "$DST" "$TMP/dst.json" HARBOR_USER HARBOR_PASSWORD

# Images de base de M12-E27 : bibliotheque/<nom> → bibliotheque/<nom>
while read -r depot; do
  [[ "$depot" == bibliotheque/* ]] && CORRESPONDANCES[$depot]="$depot"
done < <(curl -sf --config <(printf 'user = "%s"\n' "$(jq -r --arg r "$SRC" '.auths[$r].auth' "$TMP/src.json" | base64 -d)") \
           "https://$SRC/v2/_catalog?n=1000" | jq -r '.repositories[]')

erreurs=0
for src_depot in "${!CORRESPONDANCES[@]}"; do
  dst_depot="${CORRESPONDANCES[$src_depot]}"
  mapfile -t etiquettes < <(skopeo list-tags --authfile "$TMP/src.json" "docker://$SRC/$src_depot" | jq -r '.Tags[]')
  for t in "${etiquettes[@]}"; do
    s="docker://$SRC/$src_depot:$t"; d="docker://$DST/$dst_depot:$t"
    if (( ESSAI )); then echo "copierait $s → $d"; continue; fi
    skopeo copy --all --preserve-digests --retry-times 3 \
      --src-authfile "$TMP/src.json" --dest-authfile "$TMP/dst.json" "$s" "$d"
    es="$(skopeo inspect --raw --authfile "$TMP/src.json" "$s" | sha256sum | cut -d' ' -f1)"
    ed="$(skopeo inspect --raw --authfile "$TMP/dst.json" "$d" | sha256sum | cut -d' ' -f1)"
    if [[ "$es" == "$ed" ]]; then
      echo "OK  $src_depot:$t → $dst_depot:$t (sha256:$es)"
    else
      echo "KO  $src_depot:$t : empreinte source sha256:$es ≠ cible sha256:$ed" >&2
      erreurs=$((erreurs + 1))
    fi
  done
done
(( erreurs == 0 )) || { echo "$erreurs image(s) en écart d'empreinte" >&2; exit 1; }
