#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/etcd-restaurer-membre — rôle etcd_instantane (M14-E24, RB-141) : restaurer UN membre etcd
# empilé (kubeadm) à partir d'un instantané. À lancer en root SUR CHAQUE nœud de contrôle, étape par
# étape, en suivant RB-141 : chaque étape doit être faite sur les TROIS nœuds avant la suivante.
#
#   arreter                retire les quatre manifestes statiques vers $SAUV (hors du répertoire lu
#                          par le kubelet) et attend l'arrêt des conteneurs du plan de contrôle
#   restaurer INSTANTANE   déplace /var/lib/etcd vers $ANCIEN, puis etcdutl snapshot restore avec la
#                          composition complète ($ETCD_CLUSTER), un jeton neuf ($ETCD_JETON), un saut
#                          de révision et les révisions marquées compactées
#   etcd                   remet le manifeste d'etcd (à faire sur les trois nœuds à la suite)
#   plan                   remet les manifestes du serveur d'API, du gestionnaire de contrôleurs et de
#                          l'ordonnanceur
#   annuler                retour arrière : arrête tout, remet l'ancien répertoire de données, remet
#                          les manifestes (à faire sur les trois nœuds)
#
# Variables : ETCD_CLUSTER (obligatoire pour restaurer), ex.
#   k8s-cp01=https://10.10.40.51:2380,k8s-cp02=https://10.10.40.52:2380,k8s-cp03=https://10.10.40.53:2380
#   ETCD_JETON (obligatoire pour restaurer, identique sur les trois nœuds, ex. k8s-par1-restau-20261020)
#   ETCD_SAUT (défaut 1000000000), RESTAU_DATE (défaut : date du jour, identique sur les trois nœuds)
# =============================================================================
set -Eeuo pipefail
umask 077

MANIF=/etc/kubernetes/manifests
DATE="${RESTAU_DATE:-$(date +%Y%m%d)}"
SAUV="/etc/kubernetes/manifests-arretes-$DATE"
DONNEES=/var/lib/etcd
ANCIEN="/var/lib/etcd.avant-restauration-$DATE"
SAUT="${ETCD_SAUT:-1000000000}"
COMPOSANTS=(kube-apiserver kube-controller-manager kube-scheduler)

log() { printf '[%s] %s\n' "$(hostname -s)" "$*"; }
die() { log "ERREUR : $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "à lancer en root"
command -v crictl >/dev/null || die "crictl absent"

# attendre_arret NOM… — plus aucun conteneur en cours portant ces noms (120 s au plus).
attendre_arret() {
  local n restants
  for _ in $(seq 1 60); do
    restants=0
    for n in "$@"; do
      if [[ -n "$(crictl ps --name "^${n}\$" -q 2>/dev/null)" ]]; then restants=1; fi
    done
    (( restants == 0 )) && return 0
    sleep 2
  done
  die "conteneurs encore actifs après 120 s : $*"
}

# option_manifeste NOM — valeur de --NOM= dans le manifeste d'etcd sauvegardé (ou en place).
option_manifeste() {
  local f="$SAUV/etcd.yaml"
  [[ -r "$f" ]] || f="$MANIF/etcd.yaml"
  [[ -r "$f" ]] || die "manifeste d'etcd introuvable"
  sed -nE "s/^ *- --$1=(.*)$/\1/p" "$f" | head -1
}

arreter() {
  if [[ ! -d "$SAUV" ]]; then
    install -d -m 0700 "$SAUV"
    # Copie de sécurité AVANT de vider le répertoire (jamais à l'intérieur de $MANIF).
    cp -a "$MANIF"/. "$SAUV"/
    log "manifestes copiés dans $SAUV"
  fi
  for f in etcd.yaml kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml; do
    [[ -r "$SAUV/$f" ]] || die "$SAUV/$f absent : la copie de sécurité est incomplète, vérifie à la main"
  done
  find "$MANIF" -maxdepth 1 -name '*.yaml' -delete
  log "attente de l'arrêt des conteneurs du plan de contrôle et d'etcd…"
  attendre_arret etcd "${COMPOSANTS[@]}"
  log "plan de contrôle et etcd arrêtés sur ce nœud"
}

restaurer() {
  local instantane="${1:?chemin du fichier instantané manquant}" nom pair
  : "${ETCD_CLUSTER:?ETCD_CLUSTER (composition complète) obligatoire}"
  : "${ETCD_JETON:?ETCD_JETON (jeton de cluster neuf, identique sur les trois nœuds) obligatoire}"
  [[ -r "$instantane" ]] || die "instantané illisible : $instantane"
  [[ -z "$(find "$MANIF" -maxdepth 1 -name 'etcd.yaml')" ]] || die "etcd.yaml est encore en place : lance d'abord « arreter »"
  attendre_arret etcd
  nom="$(option_manifeste name)"
  pair="$(option_manifeste initial-advertise-peer-urls)"
  [[ -n "$nom" && -n "$pair" ]] || die "nom ou URL de pair introuvables dans le manifeste d'etcd"
  [[ ",$ETCD_CLUSTER," == *",$nom=$pair,"* ]] || die "ETCD_CLUSTER ne contient pas « $nom=$pair »"
  log "membre $nom, pair $pair"
  etcdutl snapshot status "$instantane" -w table || die "instantané illisible par etcdutl"
  if [[ -d "$DONNEES" ]]; then
    [[ -e "$ANCIEN" ]] && die "$ANCIEN existe déjà : ne l'écrase jamais, c'est le retour arrière"
    mv "$DONNEES" "$ANCIEN"
    log "ancien répertoire déplacé vers $ANCIEN (retour arrière : « annuler »)"
  fi
  etcdutl snapshot restore "$instantane" \
    --name "$nom" \
    --initial-cluster "$ETCD_CLUSTER" \
    --initial-cluster-token "$ETCD_JETON" \
    --initial-advertise-peer-urls "$pair" \
    --bump-revision "$SAUT" \
    --mark-compacted \
    --data-dir "$DONNEES"
  chmod 0700 "$DONNEES"
  log "restauré dans $DONNEES"
}

remettre() { # remettre FICHIER…
  local f
  [[ -d "$SAUV" ]] || die "$SAUV absent : rien à remettre"
  for f in "$@"; do
    [[ -r "$SAUV/$f" ]] || die "$SAUV/$f absent"
    install -m 0600 "$SAUV/$f" "$MANIF/$f"
    log "remis : $MANIF/$f"
  done
}

annuler() {
  arreter
  [[ -d "$ANCIEN" ]] || die "$ANCIEN absent : pas de retour arrière possible ici"
  if [[ -d "$DONNEES" ]]; then mv "$DONNEES" "$DONNEES.restauration-abandonnee-$(date +%H%M%S)"; fi
  mv "$ANCIEN" "$DONNEES"
  remettre etcd.yaml kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml
  log "retour arrière fait sur ce nœud : ancien etcd remis (à faire sur les trois nœuds)"
}

case "${1:-}" in
  arreter) arreter ;;
  restaurer) shift; restaurer "$@" ;;
  etcd) remettre etcd.yaml ;;
  plan) remettre kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml ;;
  annuler) annuler ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
