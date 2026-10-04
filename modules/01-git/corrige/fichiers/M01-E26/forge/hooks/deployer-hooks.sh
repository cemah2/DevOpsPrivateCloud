#!/usr/bin/env bash
# =============================================================================
# deployer-hooks.sh — déploie les hooks globaux pre-receive sur git01 (M01-E26)
#
# Usage (depuis adm01, à la racine du clone de plateforme/medisphere) :
#   forge/hooks/deployer-hooks.sh [HÔTE]          (HÔTE : alias SSH, défaut git01)
#
# 1. teste les hooks localement (tester-hooks.sh) : on ne déploie pas un hook cassé ;
# 2. les copie sur l'hôte et les installe (propriétaire git, 0755) dans
#    /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/, en remplaçant
#    atomiquement le contenu (les anciens hooks sont conservés dans un .bak daté) ;
# 3. rejoue les tests sur l'hôte, avec le git du serveur.
# Prérequis sur l'hôte : custom_hooks_dir configuré (gitlab.rb), sudo sans mot de passe.
# =============================================================================
set -euo pipefail

HOTE="${1:-git01}"
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=/var/opt/gitlab/gitaly/custom_hooks

echo "== Tests locaux"
"$ICI/tester-hooks.sh" "$ICI/pre-receive.d"

echo "== Copie vers $HOTE"
DISTANT_TMP="$(ssh "$HOTE" mktemp -d)"
scp -q "$ICI"/pre-receive.d/* "$ICI/tester-hooks.sh" "$HOTE:$DISTANT_TMP/"

echo "== Installation sur $HOTE"
# shellcheck disable=SC2087  # $DISTANT_TMP et $DEST sont développés localement, volontairement
ssh "$HOTE" sudo -n bash -s <<EOF
set -euo pipefail
grep -q 'custom_hooks_dir' /var/opt/gitlab/gitaly/config.toml \
  || { echo "custom_hooks_dir absent de la configuration de Gitaly : configure gitlab.rb d'abord" >&2; exit 1; }
install -d -o git -g git -m 0755 "$DEST"
neuf="$DEST/pre-receive.d.neuf"
rm -rf "\$neuf"
install -d -o git -g git -m 0755 "\$neuf"
for f in "$DISTANT_TMP"/*; do
  [ "\$(basename "\$f")" = tester-hooks.sh ] && continue
  install -o git -g git -m 0755 "\$f" "\$neuf/"
done
if [ -d "$DEST/pre-receive.d" ]; then
  mv "$DEST/pre-receive.d" "$DEST/pre-receive.d.bak-\$(date +%Y%m%d-%H%M%S)"
fi
mv "\$neuf" "$DEST/pre-receive.d"
ls -l "$DEST/pre-receive.d"
echo "== Tests sur l'hôte (utilisateur git)"
chmod 0755 "$DISTANT_TMP" "$DISTANT_TMP/tester-hooks.sh"
sudo -u git -H "$DISTANT_TMP/tester-hooks.sh" "$DEST/pre-receive.d"
rm -rf "$DISTANT_TMP"
EOF
echo "Hooks déployés sur $HOTE."
