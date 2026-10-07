#!/usr/bin/env bash
# semer-heritage-infoger.sh — reproduit sur le lab l'héritage de l'ancien infogérant (M04-E14).
#
# À lancer UNE fois depuis adm01, avant l'exercice :
#   admin@adm01:~$ ~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E14/semer-heritage-infoger.sh
#
# Sur chaque hôte visé (défaut : dns01 et git01, alias SSH de adm01) :
#   - crée le compte local « infoger » (sans mot de passe utilisable) avec une clé autorisée ;
#   - ajoute une clé « infoger@legacy » aux clés autorisées du compte admin.
# Les clés sont générées pour l'occasion et leur partie PRIVÉE est détruite aussitôt :
# personne ne peut s'en servir. C'est au rôle base (M04-E14) de faire le ménage.
# Rejouable : un hôte déjà « semé » est laissé tel quel.
set -euo pipefail

hotes=("$@")
[[ ${#hotes[@]} -gt 0 ]] || hotes=(dns01 git01)

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
ssh-keygen -q -t ed25519 -N '' -C "infoger@legacy" -f "$tmp/infoger"
rm -f -- "$tmp/infoger"                     # clé privée détruite : seule la publique sert
cle="$(<"$tmp/infoger.pub")"

for h in "${hotes[@]}"; do
  printf '%s : ' "$h"
  # shellcheck disable=SC2029  # la clé publique est volontairement développée ici
  ssh -o BatchMode=yes "$h" "sudo -n bash -s -- '$cle'" <<'DISTANT'
set -euo pipefail
cle="$1"
if id infoger >/dev/null 2>&1; then
  echo "déjà semé, rien à faire"
  exit 0
fi
useradd --create-home --shell /bin/bash --comment "InfoGer - astreinte N2" infoger
install -d -o infoger -g infoger -m 700 ~infoger/.ssh
printf '%s\n' "$cle" > ~infoger/.ssh/authorized_keys
chown infoger:infoger ~infoger/.ssh/authorized_keys
chmod 600 ~infoger/.ssh/authorized_keys
printf '%s\n' "$cle" >> ~admin/.ssh/authorized_keys
echo "compte infoger créé, clé infoger@legacy ajoutée à admin"
DISTANT
done
