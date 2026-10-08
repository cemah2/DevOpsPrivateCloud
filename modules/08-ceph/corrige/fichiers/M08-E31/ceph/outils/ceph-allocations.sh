#!/usr/bin/env bash
# =============================================================================
# outils/ceph-allocations.sh — allocations de ceph-par1 aux équipes et aux consommateurs (plateforme/ceph)
# M08-E31 (DEV-957), étendu en M08-E34 (MédiNotif) et M08-E46 (OpenStack, Kubernetes).
#
# Lit allocations.yaml (identités des consommateurs, équipes) et confronte le cluster :
#   identites[] : entite, caps {mon, osd, mgr, mds}
#   equipes[]   : nom, identite, bloc {pool, plafond_gio},
#                 fichier {volume, plafond_gio, sous_volumes[{nom, taille_gio}]}, objet {compte, quota_gio}
# Les POOLS ne sont pas gérés ici : ils sont dans config/cluster.yaml (règle, application, quota),
# créés par outils/pool-repliquee.sh (geste humain, fiche de changement) et réglés par
# outils/config-cluster.sh (M08-E23). Cet outil vérifie seulement que le quota d'un pool partagé
# couvre la somme des plafonds bloc des équipes qui l'utilisent.
#
# Modes :
#   verifier  [FICHIER]             lecture seule : écarts de droits, d'espaces de noms, de sous-volumes,
#                                   de quotas, et PLAFONDS BLOC des équipes (Ceph n'a pas de quota par
#                                   espace de noms RBD : c'est ce contrôle qui le compense) ; code 1 si écart
#   appliquer [--simuler] [--oui] [FICHIER]  crée ce qui manque, aligne droits et plafonds (idempotent) ;
#                                   --simuler affiche sans agir ; « oui » demandé avant d'agir (sauf --oui)
# Usage, sur adm01 : CEPH_ADMIN=ceph01 outils/ceph-allocations.sh verifier allocations.yaml
# Accès au cluster : outils/lib.sh (ssh vers l'hôte _admin, sudo, aucune clé copiée).
# Ne SUPPRIME jamais rien (une allocation retirée du fichier est signalée, la suppression reste
# humaine) et ne crée PAS d'identifiants S3 ni n'affiche de clé cephx (secrets : registre, Vault).
# Codes retour : 0 conforme ou appliqué ; 1 écart ou échec ; 2 usage.
# =============================================================================
set -Eeuo pipefail
# lib.sh : bibliothèque de plateforme/ceph (M08-E23). Le second source-path ne sert qu'à ShellCheck
# dans le dépôt du workbook.
# shellcheck source-path=SCRIPTDIR source-path=SCRIPTDIR/../../../M08-E23/ceph/outils source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CEPH_ADMIN="${CEPH_ADMIN:-ceph01}"

usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; }

MODE="${1:-}"
shift || true
SIMULER=0
OUI=0
FICHIER="$MS_RACINE/allocations.yaml"
for a in "$@"; do
  case "$a" in
    --simuler) SIMULER=1 ;;
    --oui) OUI=1 ;;
    -*) usage >&2; exit 2 ;;
    *) FICHIER="$a" ;;
  esac
done
case "$MODE" in
  verifier | appliquer) ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
command -v jq >/dev/null || { ms_erreur "jq absent"; exit 2; }
[[ -r "$FICHIER" ]] || { ms_erreur "fichier illisible : $FICHIER"; exit 2; }
DESC="$(ms_yq -o json '.' "$FICHIER")"
jq -e 'type == "object"' >/dev/null <<<"$DESC" || { ms_erreur "description invalide : $FICHIER"; exit 2; }

GIO=1073741824
ECARTS=0
ACTIONS=()

ecart() {
  ECARTS=$((ECARTS + 1))
  printf 'ÉCART  %s\n' "$*"
}
# prevoir DESCRIPTION COMMANDE… — en mode verifier : écart ; en mode appliquer : action à faire.
prevoir() {
  local d="$1"
  shift
  if [[ "$MODE" == verifier ]]; then
    ecart "$d"
  else
    printf 'À FAIRE  %s\n' "$d"
    ACTIONS+=("$(printf '%q ' "$@")")
  fi
}

ceph_json() { ms_ceph "$@" --format json 2>/dev/null; }
rbd_() { ms_outil rbd "$@"; }
rgw_() { ms_outil radosgw-admin "$@"; }

# --- Identités ----------------------------------------------------------------------------------------
# identite ENTITÉ CAPS_JSON — l'identité existe avec exactement ces droits (« ceph auth caps » remplace TOUT).
identite() {
  local ent="$1" caps="$2" actuel args=() k
  caps="$(jq -c 'with_entries(select(.value | length > 0))' <<<"$caps")"
  for k in mon osd mgr mds; do
    if jq -e --arg k "$k" 'has($k)' >/dev/null <<<"$caps"; then
      args+=("$k" "$(jq -r --arg k "$k" '.[$k]' <<<"$caps")")
    fi
  done
  ((${#args[@]} > 0)) || { ms_erreur "$ent : aucun droit décrit"; exit 1; }
  if ! actuel="$(ceph_json auth get "$ent" | jq -ce '.[0].caps')"; then
    # Création sans afficher la clé : la procédure du registre la lit ensuite pour Vault.
    prevoir "identité $ent absente" ms_ceph auth get-or-create "$ent" "${args[@]}" -o /dev/null
    return
  fi
  if ! jq -e --argjson v "$caps" '. == $v' >/dev/null <<<"$actuel"; then
    prevoir "identité $ent : droits $actuel au lieu de $caps" ms_ceph auth caps "$ent" "${args[@]}"
  fi
}

identites() {
  local i n
  n="$(jq '.identites // [] | length' <<<"$DESC")"
  for ((i = 0; i < n; i++)); do
    identite "$(jq -r ".identites[$i].entite" <<<"$DESC")" "$(jq -c ".identites[$i].caps" <<<"$DESC")"
  done
}

# --- Équipes --------------------------------------------------------------------------------------------
equipe() {
  local e="$1" nom ent pool vol plafond provisionne info espaces_fs="" j nsv sv taille
  nom="$(jq -r '.nom' <<<"$e")"
  ent="$(jq -r '.identite // ("client." + .nom)' <<<"$e")"

  # Bloc : espace de noms RBD ; plafond contrôlé ici (aucun quota natif par espace de noms).
  pool="$(jq -r '.bloc.pool // empty' <<<"$e")"
  if [[ -n "$pool" ]]; then
    if ! rbd_ namespace ls "$pool" --format json | jq -e --arg n "$nom" 'any(.[]; .name == $n)' >/dev/null; then
      prevoir "espace de noms $pool/$nom absent" ms_outil rbd namespace create --pool "$pool" --namespace "$nom"
    else
      plafond=$(($(jq -r '.bloc.plafond_gio' <<<"$e") * GIO))
      provisionne="$(rbd_ du --pool "$pool" --namespace "$nom" --format json 2>/dev/null | jq -r '.total_provisioned_size // 0')"
      if ((provisionne > plafond)); then
        ecart "équipe $nom : $((provisionne / GIO)) Gio provisionnés en bloc pour un plafond de $((plafond / GIO)) Gio"
      fi
    fi
  fi

  # Fichier : groupe plafonné, sous-volumes isolés dans leur propre espace de noms RADOS.
  vol="$(jq -r '.fichier.volume // empty' <<<"$e")"
  if [[ -n "$vol" ]]; then
    plafond=$(($(jq -r '.fichier.plafond_gio' <<<"$e") * GIO))
    if ! ceph_json fs subvolumegroup ls "$vol" | jq -e --arg n "$nom" 'any(.[]; .name == $n)' >/dev/null; then
      prevoir "groupe de sous-volumes $vol/$nom absent" ms_ceph fs subvolumegroup create "$vol" "$nom" --size "$plafond"
    else
      info="$(ceph_json fs subvolumegroup info "$vol" "$nom" || echo '{}')"
      if [[ "$(jq -r '.bytes_quota // 0' <<<"$info")" != "$plafond" ]]; then
        prevoir "groupe $vol/$nom : plafond différent de $((plafond / GIO)) Gio" \
          ms_ceph fs subvolumegroup resize "$vol" "$nom" "$plafond" --no_shrink
      fi
    fi
    nsv="$(jq '.fichier.sous_volumes // [] | length' <<<"$e")"
    for ((j = 0; j < nsv; j++)); do
      sv="$(jq -r ".fichier.sous_volumes[$j].nom" <<<"$e")"
      taille=$(($(jq -r ".fichier.sous_volumes[$j].taille_gio" <<<"$e") * GIO))
      if ! info="$(ceph_json fs subvolume info "$vol" "$sv" --group_name "$nom")" || [[ -z "$info" ]]; then
        prevoir "sous-volume $vol/$nom/$sv absent" \
          ms_ceph fs subvolume create "$vol" "$sv" --group_name "$nom" --size "$taille" --namespace-isolated
        continue
      fi
      [[ "$(jq -r '.bytes_quota // 0' <<<"$info")" == "$taille" ]] \
        || prevoir "sous-volume $vol/$nom/$sv : taille différente de $((taille / GIO)) Gio" \
          ms_ceph fs subvolume resize "$vol" "$sv" "$taille" --group_name "$nom" --no_shrink
      espaces_fs+=", allow rw pool=$(jq -r '.data_pool' <<<"$info") namespace=$(jq -r '.pool_namespace' <<<"$info")"
    done
  fi

  # Identité de l'équipe : droits CALCULÉS, jamais écrits à la main. Si un sous-volume vient d'être
  # créé, ses droits OSD seront ajoutés au passage suivant (son espace de noms n'existait pas).
  local caps
  caps="$(jq -n --arg nom "$nom" --arg pool "$pool" --arg vol "$vol" --arg fs "$espaces_fs" '{
      mon: ("profile rbd" + (if $vol != "" then ", allow r fsname=" + $vol else "" end)),
      osd: ((if $pool != "" then "profile rbd pool=" + $pool + " namespace=" + $nom else "" end) + $fs | ltrimstr(", ")),
      mds: (if $vol != "" then "allow rw fsname=" + $vol + " path=/volumes/" + $nom else "" end)
    }')"
  identite "$ent" "$caps"

  # Objet : compte RGW et quota (identifiants S3 : procédure du registre, hors de cet outil).
  local compte quota id cpt
  compte="$(jq -r '.objet.compte // empty' <<<"$e")"
  [[ -n "$compte" ]] || return 0
  quota=$(($(jq -r '.objet.quota_gio' <<<"$e") * GIO))
  if ! cpt="$(rgw_ account get --account-name="$compte" 2>/dev/null)" || ! id="$(jq -er '.id' <<<"$cpt")"; then
    prevoir "compte RGW $compte absent" ms_outil radosgw-admin account create --account-name="$compte"
    return 0
  fi
  if ! jq -e --argjson q "$quota" '.quota.enabled == true and .quota.max_size == $q' >/dev/null <<<"$cpt"; then
    prevoir "compte RGW $compte : quota différent de $((quota / GIO)) Gio" \
      ms_outil radosgw-admin quota set --quota-scope=account --account-id="$id" --max-size="$quota"
    prevoir "compte RGW $compte : activer le quota" \
      ms_outil radosgw-admin quota enable --quota-scope=account --account-id="$id"
  fi
}

equipes() {
  local i n p somme q
  n="$(jq '.equipes // [] | length' <<<"$DESC")"
  for ((i = 0; i < n; i++)); do equipe "$(jq -c ".equipes[$i]" <<<"$DESC")"; done
  # Le quota d'un pool partagé (config/cluster.yaml) doit couvrir la somme des plafonds bloc.
  for p in $(jq -r '[.equipes[]?.bloc.pool // empty] | unique[]' <<<"$DESC"); do
    somme=$(($(jq --arg p "$p" '[.equipes[] | select(.bloc.pool == $p) | .bloc.plafond_gio] | add' <<<"$DESC") * GIO))
    q="$(ceph_json osd pool get-quota "$p" | jq -r '.quota_max_bytes // 0')" || q=0
    ((q >= somme)) || ecart "pool $p : quota $((q / GIO)) Gio < somme des plafonds $((somme / GIO)) Gio (config/cluster.yaml)"
  done
}

identites
equipes

if [[ "$MODE" == verifier ]]; then
  if ((ECARTS > 0)); then
    ms_info "$ECARTS écart(s)"
    exit 1
  fi
  ms_info "conforme à $FICHIER"
  exit 0
fi

if ((${#ACTIONS[@]} == 0)); then
  ms_info "rien à faire"
  exit $((ECARTS > 0))
fi
if ((SIMULER)); then
  ms_info "${#ACTIONS[@]} action(s) prévue(s), rien n'a été modifié (--simuler)"
  exit 0
fi
((OUI)) || ms_confirmer "Appliquer ${#ACTIONS[@]} action(s) sur ceph-par1 ?" || exit 1
for c in "${ACTIONS[@]}"; do
  ms_info "→ $c"
  # Commandes construites par printf %q à partir de la description : eval les relit telles quelles.
  eval "$c"
done
ms_info "appliqué ; relance « verifier » (et « appliquer » si un sous-volume vient d'être créé)"
exit $((ECARTS > 0))
