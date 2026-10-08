#!/usr/bin/env bash
# outils/appliquer.sh — LA procédure d'application des spécifications de plateforme/ceph (M08-E23).
# Depuis adm01, sur une copie à jour de main (après fusion de la MR) :
#   outils/appliquer.sh specs/rgw.yaml [specs/…]     les fichiers donnés
#   outils/appliquer.sh --tout                        toutes les spécifications, dans l'ordre
# Pour chaque fichier : règles maison, « ceph orch apply --dry-run », confirmation (« oui » en
# toutes lettres), application ; ingress.yaml passe par cert-ingress.sh (certificat injecté) ;
# hosts.yaml n'a pas de simulation (cephadm applique les hôtes même avec --dry-run) : on affiche
# l'état du cluster et le fichier avant de demander confirmation.
# Puis contrôle de dérive. Accès : CEPH_ADMIN (défaut ceph01), clé client.admin du nœud _admin.
# L'état hors spécifications (config/cluster.yaml) s'applique par outils/config-cluster.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CEPH_ADMIN="${CEPH_ADMIN:-ceph01}"
ORDRE=(hosts mon mgr osd mds rgw ingress nfs)

[[ $# -ge 1 ]] || { echo "Usage : $0 --tout | specs/<fichier>.yaml…" >&2; exit 2; }
if [[ "$1" == --tout ]]; then
  fichiers=(); for n in "${ORDRE[@]}"; do fichiers+=("$MS_RACINE/specs/$n.yaml"); done
else
  fichiers=("$@")
fi

# Le dépôt local est-il celui de main, propre et à jour ? (on n'applique que ce qui a été relu)
if git -C "$MS_RACINE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$MS_RACINE" fetch -q origin main || ms_erreur "fetch impossible : vérifie que ta copie est à jour"
  [[ -z "$(git -C "$MS_RACINE" status --porcelain -- specs config)" ]] \
    || { ms_erreur "modifications locales non versionnées dans specs/ ou config/ : on n'applique que main"; exit 1; }
  [[ "$(git -C "$MS_RACINE" rev-parse HEAD)" == "$(git -C "$MS_RACINE" rev-parse origin/main)" ]] \
    || { ms_erreur "ta copie n'est pas sur origin/main à jour (git switch main && git pull)"; exit 1; }
fi

"$MS_RACINE/outils/verifier-specs.sh" >/dev/null || { "$MS_RACINE/outils/verifier-specs.sh" || true; ms_erreur "règles maison en échec : rien n'est appliqué"; exit 1; }

for f in "${fichiers[@]}"; do
  [[ -f "$f" ]] || { ms_erreur "fichier introuvable : $f"; exit 1; }
  echo "=== $(basename "$f")"
  if [[ "$(basename "$f")" == ingress.yaml ]]; then
    "$MS_RACINE/outils/cert-ingress.sh" --verifier
    ms_confirmer "Appliquer ingress.yaml (certificat en cours injecté) ?" || { echo "ignoré"; continue; }
    "$MS_RACINE/outils/cert-ingress.sh" --appliquer
    continue
  fi
  if [[ "$(basename "$f")" == hosts.yaml ]]; then
    # PIÈGE : « ceph orch apply --dry-run » ne simule que les SERVICES. Une spécification d'HÔTE
    # est appliquée même avec --dry-run (code de l'orchestrateur, 20.2.3) : ajout d'hôte, étiquettes
    # et emplacement CRUSH changeraient AVANT la confirmation. On montre donc l'état du cluster et
    # celui du fichier, sans rien envoyer à « orch apply ».
    echo "--- hôtes du cluster :"
    ms_ceph orch host ls
    echo "--- hôtes du fichier (ce qui sera appliqué) :"
    ms_yq eval 'select(.service_type == "host") | [.hostname, .addr, ((.labels // []) | join(",")), (.location.rack // "")] | join("  ")' "$f"
    ms_confirmer "Appliquer hosts.yaml (pas de simulation possible pour les hôtes) ?" || { echo "ignoré"; continue; }
    ms_ceph orch apply -i - < "$f"
    continue
  fi
  ms_ceph orch apply -i - --dry-run < "$f"
  ms_confirmer "Appliquer $(basename "$f") ?" || { echo "ignoré"; continue; }
  ms_ceph orch apply -i - < "$f"
done

echo "=== Contrôle de dérive (les démons peuvent mettre quelques minutes à converger)"
sleep 30
"$MS_RACINE/outils/derive.sh" || ms_info "Écarts restants : relance outils/derive.sh dans quelques minutes, puis enquête."
