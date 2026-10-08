#!/usr/bin/env bash
# Les arguments des commandes ssh sont développés côté adm01 À DESSEIN (valeurs connues ici).
# shellcheck disable=SC2029
# outils/certificat-externe.sh — certificat de la VIP externe d'OpenStack (M10-E04, PLAT-1104).
#
# Produit etc/kolla/certificates/haproxy.pem (chaîne + clé, le format attendu par le HAProxy de
# Kolla), CHIFFRÉ par Ansible Vault (identité « critique »). La clé privée n'existe jamais en
# clair sur adm01 : elle passe par un tube jusqu'à « ansible-vault encrypt ».
#
#   emettre     première émission, AVANT le premier déploiement (la VIP n'existe pas encore) :
#               osctl01 porte 10.10.50.201 le temps du défi ACME HTTP-01 (client step en mode
#               autonome, port 80), puis la retire. Refuse si l'adresse répond déjà.
#   renouveler  avant l'échéance, cloud en service : « step ca renew » sur adm01 (authentification
#               par le certificat en cours, pas de défi ACME), dans un dossier en mémoire (700),
#               puis rechiffrement. Ensuite : kolla-ansible reconfigure -t loadbalancer.
#   afficher    sujet, SAN, émetteur, échéance du certificat du dépôt (sans afficher la clé).
#
# Le renouvellement AUTOMATIQUE (client ACME de Kolla vers ca01) est l'objet de M10-E27.
# Prérequis : step sur adm01 et osctl01 (rôle step_ca, point d'entrée client) ; flux
# osctl01 → ca01:443 et ca01 → 10.10.50.201:80 (matrice des flux, M10-E04).
# Usage (depuis la racine de plateforme/openstack) : outils/certificat-externe.sh emettre|renouveler|afficher
set -euo pipefail

NOM="openstack.par1.medisphere.internal"
VIP="10.10.50.201"
IFACE="ens18"
NOEUD="${NOEUD_VIP:-osctl01}"
CA_URL="https://ca01.par1.medisphere.internal"
RACINE="/usr/local/share/ca-certificates/medisphere-root-ca.crt"
PEM="etc/kolla/certificates/haproxy.pem"
CA_DIR="etc/kolla/certificates/ca"

racine_depot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine_depot"

usage() { echo "Usage : $0 emettre|renouveler|afficher" >&2; exit 2; }

vault_chiffrer() {  # lit le PEM sur l'entrée standard, écrit $PEM chiffré
  install -d -m 0755 "$(dirname "$PEM")"
  uv run --quiet ansible-vault encrypt --encrypt-vault-id critique --output "$PEM" -
}

# nb_certificats — nombre de blocs CERTIFICATE lus sur l'entrée standard.
nb_certificats() { grep -c -- '-----BEGIN CERTIFICATE-----' || true; }

copier_racine() {
  install -d -m 0755 "$CA_DIR"
  install -m 0644 "$RACINE" "$CA_DIR/medisphere-root-ca.crt"
}

afficher() {
  [[ -s "$PEM" ]] || { echo "Pas de $PEM : lance d'abord « $0 emettre »." >&2; exit 1; }
  # Seul le PREMIER bloc (certificat feuille) est lu par openssl x509 ; la clé n'est pas affichée.
  uv run --quiet ansible-vault view "$PEM" \
    | openssl x509 -noout -subject -issuer -enddate -ext subjectAltName -nameopt utf8,sep_comma_plus_space
}

emettre() {
  local d
  echo "1/6 La VIP $VIP doit être LIBRE sur le VLAN 50 (détection d'adresse en double depuis $NOEUD)…"
  if ! ssh "$NOEUD" sudo arping -q -D -c 3 -I "$IFACE" "$VIP"; then
    echo "REFUS : $VIP répond déjà (keepalived de Kolla déjà en place, ou autre machine)." >&2
    echo "        Cloud déjà déployé ? Utilise « $0 renouveler »." >&2
    exit 1
  fi

  echo "2/6 $NOEUD porte $VIP le temps du défi (retirée en sortie, même en cas d'erreur)."
  ssh "$NOEUD" sudo ip addr add "$VIP/24" dev "$IFACE"
  d="$(ssh "$NOEUD" mktemp -d)"
  # shellcheck disable=SC2064  # $d et la VIP sont figés à la pose du piège, c'est voulu
  trap "ssh '$NOEUD' sudo ip addr del '$VIP/24' dev '$IFACE' || true; ssh '$NOEUD' sudo rm -rf '$d' || true" EXIT

  echo "3/6 Défi ACME HTTP-01 sur $NOEUD:80 (provisioner acme de ca01)…"
  ssh "$NOEUD" sudo step ca certificate "$NOM" "$d/crt" "$d/key" \
    --provisioner acme --standalone --ca-url "$CA_URL" --root "$RACINE" --force

  echo "4/6 Contrôle : chaîne complète (feuille + intermédiaire) ?"
  local n
  n="$(ssh "$NOEUD" sudo cat "$d/crt" | nb_certificats)"
  ((n >= 2)) || { echo "Le certificat obtenu ne contient pas l'intermédiaire ($n bloc)." >&2; exit 1; }

  echo "5/6 Chiffrement de la chaîne et de la clé dans $PEM (Vault « critique »)…"
  { ssh "$NOEUD" sudo cat "$d/crt"; ssh "$NOEUD" sudo cat "$d/key"; } | vault_chiffrer
  copier_racine

  echo "6/6 Nettoyage de $NOEUD (VIP retirée, dossier supprimé)."
  ssh "$NOEUD" sudo ip addr del "$VIP/24" dev "$IFACE"
  ssh "$NOEUD" sudo rm -rf "$d"
  trap - EXIT
  afficher
  echo "Suite : vérifie $PEM (git diff : un en-tête \$ANSIBLE_VAULT), commit, puis déploiement."
}

renouveler() {
  [[ -s "$PEM" ]] || { echo "Pas de $PEM à renouveler." >&2; exit 1; }
  local d
  # Dossier en MÉMOIRE (tmpfs), lisible par toi seul, effacé en sortie quoi qu'il arrive.
  d="$(mktemp -d -p /dev/shm)"
  chmod 700 "$d"
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  (
    umask 077
    uv run --quiet ansible-vault view "$PEM" >"$d/tout.pem"
    # Feuille + intermédiaire → crt ; clé → key.
    awk -v d="$d" '
      /-----BEGIN CERTIFICATE-----/ {f = d "/crt"}
      /-----BEGIN [A-Z ]*PRIVATE KEY-----/ {f = d "/key"}
      f {print > f}
      /-----END/ {f = ""}
    ' "$d/tout.pem"
  )
  echo "Renouvellement auprès de $CA_URL (authentification par le certificat en cours)…"
  step ca renew --force --ca-url "$CA_URL" --root "$RACINE" "$d/crt" "$d/key"
  cat "$d/crt" "$d/key" | vault_chiffrer
  copier_racine
  afficher
  echo "Suite : commit, puis « uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t loadbalancer »."
}

case "${1:-}" in
  emettre) emettre ;;
  renouveler) renouveler ;;
  afficher) afficher ;;
  *) usage ;;
esac
