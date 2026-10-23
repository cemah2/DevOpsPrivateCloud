#!/usr/bin/env bash
# plateforme/openstack — outils/fusionner-mots-de-passe.sh (F4-S08, CHG-3408, RB-344)
# Montée de série : ajoute à etc/kolla/passwords.yml (chiffré Ansible Vault, identité « critique »,
# M10-E03) les mots de passe des services nouveaux de la série cible, SANS changer les existants.
# Procédure de « Operating Kolla » (kolla-genpwd sur l'exemple de la nouvelle version, puis
# kolla-mergepwd), adaptée au fichier chiffré : le clair n'existe que dans un dossier 700 en mémoire
# (/dev/shm), effacé à la sortie quoi qu'il arrive.
#
#   cd ~/src/openstack-2026.2 && outils/fusionner-mots-de-passe.sh
set -euo pipefail
umask 077

racine="$(git rev-parse --show-toplevel)"
cd "$racine"
chiffre=etc/kolla/passwords.yml
exemple="$(uv run python -c 'import sys; print(sys.prefix)')/share/kolla-ansible/etc_examples/kolla/passwords.yml"
[[ -r "$exemple" ]] || { echo "exemple introuvable : $exemple (chemin à vérifier dans ton .venv)" >&2; exit 1; }

tmp="$(mktemp -d /dev/shm/kolla-mdp.XXXXXX)"
trap 'find "$tmp" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$tmp"' EXIT

uv run ansible-vault view "$chiffre" >"$tmp/ancien.yml"
cp "$exemple" "$tmp/nouveau.yml"
uv run kolla-genpwd --passwords "$tmp/nouveau.yml" >/dev/null
uv run kolla-mergepwd --old "$tmp/ancien.yml" --new "$tmp/nouveau.yml" --final "$tmp/final.yml"

# Contrôle : aucune valeur existante n'a changé ; seules des clés ont été ajoutées.
uv run python - "$tmp/ancien.yml" "$tmp/final.yml" <<'PY'
import sys, yaml
a = yaml.safe_load(open(sys.argv[1])) or {}
f = yaml.safe_load(open(sys.argv[2])) or {}
change = [k for k in a if k in f and a[k] != f[k]]
perdu = [k for k in a if k not in f]
nouveau = sorted(k for k in f if k not in a)
if change or perdu:
    sys.exit(f"refus : valeurs modifiées {change} ou clés perdues {perdu}")
print("clés ajoutées :", ", ".join(nouveau) if nouveau else "aucune")
PY

uv run ansible-vault encrypt --encrypt-vault-id critique --output "$chiffre" "$tmp/final.yml"
echo "passwords.yml mis à jour et rechiffré ; relis « git diff --stat » puis ouvre la MR."
