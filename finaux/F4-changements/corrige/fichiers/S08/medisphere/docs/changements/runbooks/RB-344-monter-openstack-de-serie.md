# RB-344 — Monter OpenStack d'une série à la suivante (Kolla-Ansible)

| | |
|---|---|
| Complète | RB-101 (mise à jour **dans** une série, M10-E28) ; §7 de RB-101 renvoie ici |
| Fiche type | CHG-3408 |
| Référence | « Operating Kolla », section *Upgrade procedure*, de la série **cible** ; notes de version (*Upgrade Notes*) de Kolla-Ansible et de chaque service |

## 1. Décider

- Kolla-Ansible de la série cible publié en **stable** (PyPI), pas seulement en rc ; sinon répétition seulement.
- Un seul saut de série à la fois, sauf montée SLURP (une série sur deux) : alors RabbitMQ d'abord vers une version intermédiaire (section SLURP de la documentation).
- Matrice de prise en charge : système des hôtes et base des images (`kolla_base_distro: debian`).

## 2. Préparer (sans rien interrompre)

```
admin@adm01:~/src/openstack$ git worktree add ~/src/openstack-2026.2 -b serie-2026.2
admin@adm01:~/src/openstack-2026.2$ $EDITOR pyproject.toml          # kolla-ansible 23.x, ansible-core de la plage
admin@adm01:~/src/openstack-2026.2$ uv lock && uv sync --frozen && uv run ansible --version | head -n 1
admin@adm01:~/src/openstack-2026.2$ uv run kolla-ansible install-deps
admin@adm01:~/src/openstack-2026.2$ diff -u inventaire/multinode "$(uv run python -c 'import sys;print(sys.prefix)')/share/kolla-ansible/ansible/inventory/multinode"
admin@adm01:~/src/openstack-2026.2$ outils/fusionner-mots-de-passe.sh       # kolla-genpwd sur l'exemple, puis kolla-mergepwd
admin@adm01:~/src/openstack-2026.2$ $EDITOR etc/kolla/globals.yml   # openstack_release: "2026.2" + notes de version
```

Contraintes : jamais `--limit` (bogues connus, documentation) ; pas d'`ansible-core` hors de la plage de la série ; chaque arbre de travail a son `.venv` : l'environnement 2026.1 reste intact pour le retour arrière. MR avec pipeline vert, **non fusionnée** avant la fenêtre.

## 3. Le jour J

1. Mémoire : `k8s-par1` arrêté (`pve01/profil-k8s.sh arreter`), profil openstack démarré ou reconstruit depuis le code (`tofu apply` de `envs/openstack`, puis `outils/deployer.sh deploy` en 2026.1).
2. Sauvegarde de la base (`kolla-ansible mariadb-backup … --full`), envoyée sur PBS `par1/openstack`, lisible.
3. Sonde : groupes `continuite-openstack*` de `mon01` (IP flottante d'une instance témoin), ligne de base.
4. `uv run kolla-ansible pull …` puis `uv run kolla-ansible prechecks …` (depuis l'arbre 2026.2).
5. Fusion de la MR ; `main` à jour ; `outils/deployer.sh upgrade` (déploiement tracé `deploye-*`). Les conteneurs sont recréés depuis les nouvelles images, les migrations de bases s'exécutent.
6. Vérifications : `openstack compute service list`, `network agent list`, `volume service list` ; instance neuve, volume attaché, répartiteur OVN, Horizon ; images des conteneurs en `2026.2`.

## 4. Après

Clôture de la fiche (mesure source `temoin`, `mesure-groupes`), `prune-images` seulement après la période de retour arrière, arbre de travail retiré (`git worktree remove`), `~/src/openstack` remis sur `main`. `lab/bin/check F4 8`.

## 5. Retour arrière

Avant `upgrade` : rien. Après : restauration de la base (M10, `sauvegarde-restauration.md` §3), images 2026.1 encore présentes, `deploy-containers` depuis l'arbre 2026.1, étiquette `deploye-*` de retour. Un retour de série est lourd : il se **répète** avant la fenêtre.
