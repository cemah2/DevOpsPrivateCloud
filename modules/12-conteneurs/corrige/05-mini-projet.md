# Module 12 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M12-E46 — Mini-projet : conteneurs MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des trois démonstrations et la **grille de revue**. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont le rôle [`pile_recette`](fichiers/M12-E46/ansible/roles/pile_recette/) (avec son [playbook](fichiers/M12-E46/ansible/playbooks/pile-recette.yml) et ses [variables de `ctr02`](fichiers/M12-E46/ansible/inventories/lab/host_vars/ctr02/)), le modèle d'[`architecture.md`](fichiers/M12-E46/medisphere/docs/conteneurs/architecture.md) et celui du [procès-verbal `recette-v1.md`](fichiers/M12-E46/medisphere/docs/conteneurs/recette-v1.md).

**Solution**

*Plan de travail recommandé* (dans cet ordre : chaque étape alimente la suivante)

1. **État des lieux** (1 h) : `lab/bin/check 12 46`, puis les contrôles détaillés en rouge (`12 05`, `12 10`, `12 17`, `12 19`, `12 20`, `12 21`, `12 28`). Aucune panne active (`ls ~/.local/state/workbook/pannes-actives/`).
2. **Les images** (3 à 5 h) : reprendre les Dockerfile de E05/E10/E17/E19 avec les normes (E33) et la politique d'images de base (E27) : base autorisée épinglée par empreinte, multi-étapes, `USER` numérique, sonde, aucune donnée ni secret, `.dockerignore`. Hadolint sans dérogation non justifiée (chaque `ignored` du `.hadolint.yaml` porte un commentaire). Dive au-dessus du seuil (E16). Le point qui coince souvent : Legacy-RDV (journaux sur stderr, `LEGACY_RDV_*`, pièces jointes et sessions en volumes, Apache non-root sur 8080, E19).
3. **La CI** (2 à 3 h) : les quatre `.gitlab-ci.yml` incluent `image.yml` ; publication `X.Y.Z` seulement depuis une étiquette Git ; MédiAgenda en `--platform linux/amd64,linux/arm64` (E12) ; le job de construction porte l'étiquette `docker`. Vérifier sur une MR : Hadolint en job, construction sans `privileged`, test de fumée, poussée. Contrôle : `lab/bin/check 12 46` section 1, et `skopeo inspect --raw docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:<X.Y.Z> | jq '.manifests[].platform'`.
4. **La pile de recette** (4 à 6 h) : le rôle `pile_recette` (Quadlet du compte `app`, choix de l'ADR-0120), variables dans `host_vars/ctr02/`, secrets en Vault `lab` puis secrets Podman. Ordre de mise au point : réseau et dépendances (PostgreSQL, Valkey, MariaDB, RabbitMQ, SeaweedFS), migrations, puis les quatre applications une par une, en relançant le playbook (`--diff`) plutôt qu'en éditant sur l'hôte. Le rôle échoue si le générateur Quadlet refuse un fichier (leçon de E40) et finit par l'appel des quatre points d'accès.
   - Legacy-RDV : charger le schéma une fois (`podman exec -i legacy-mariadb mariadb -u legacy_rdv -p… legacy_rdv < schema.sql`, mot de passe lu dans le secret, pas tapé) ou importer le vidage de `legacy01` (E19) ; noter la manière dans `recette-v1.md`.
   - MédiDoc : avec SeaweedFS de recette, le compartiment est créé par le rôle (`weed shell`, `s3.bucket.create`, **à vérifier sur ta version**) ; avec `s3-01`, ouvrir le flux `ctr02` → `s3-01:8333` dans `group_vars/role_routeur/pare_feu.yml` (réservation Kea pour une adresse fixe de `ctr02`) et le reporter dans la matrice.
   - Vérifier le retour au démarrage : `sudo reboot` de `ctr02`, puis les quatre points d'accès sans intervention.
5. **runner02 dans le socle** (1 à 2 h) : `qm config 1012` (étiquette `socle`), NetBox et DNS, travail de sauvegarde PBS qui inclut 1012 (comme les autres VMs du socle), ajout dans `ms-verif-conteneurs.conf` (E28 : `runner02` dans `MS_CONTENEURS_HOTES`, conteneur `gitlab-runner` ou contrôle du service) et dans la sonde du socle, minuterie de ménage `docker-menage.timer` (E39), `privileged = false` vérifié.
6. **Documentation** (2 à 3 h) : `architecture.md` ([modèle](fichiers/M12-E46/medisphere/docs/conteneurs/architecture.md)), `normes.md` mis à jour des leçons du palier 4 (options de journaux interdites, sondes exécutables dans l'image, alias réseau commentés, ménage planifié), ADR-0120, RB-120 (complété en E35) à RB-125, inventaire, matrice des flux, registre des secrets (comptes `ci` et `plateforme` du registre, jeton `glrt-` du runner, secrets de la pile : **emplacements**).
7. **Retrait des témoins** (15 min) : `/srv/recette` sur `ctr01` (`sudo docker compose -f /srv/recette/compose.yaml down -v` — le volume `recette_pgdata` ne contient que des données de test du palier 4 —, puis `sudo rm -rf /srv/recette /srv/recette-archives`, images `recette/*`) ; `recette-cache` sur `ctr02` et `ctr03` (`systemctl --user stop`, fichiers Quadlet supprimés, `daemon-reload`, `podman unshare rm -rf ~/recette`) ; conteneur `capot` (`runc delete`) et cgroups de E44. Sur `ctr02`, les essais des paliers 1 à 3 occupent les ports de la recette : `m12-e06-web` (port 8080, `podman rm -f` sous `app`) et la pile d'essai de E14/E30 (pod `mediagenda` sur le port 8000), que le rôle `pile_recette` arrête et dont il retire les fichiers propres (`mediagenda.pod`, `mediagenda.network`, `mediagenda-api.build`, variable `pile_recette_unites_retirees`) ; ses fichiers `.container` portent les mêmes noms et sont remplacés.
8. **Recette** (la revue) puis **procès-verbal** `recette-v1.md` ([modèle](fichiers/M12-E46/medisphere/docs/conteneurs/recette-v1.md)), MR, étiquette `conteneurs-v1`.
9. **Destruction de l'environnement** (30 min) : `tofu -chdir=envs/m12 plan -destroy` relu, puis `tofu destroy` (ou suppression des VMs du code et `apply`, selon la convention de `plateforme/infra`) ; si `ctr01` est gardée pour M13 (jusqu'à la fin de M13-E03), la sortir du code de destruction et poser `WB_M12_CTR01_CONSERVE=1` dans `lab/lab.env`. Objets NetBox et DNS retirés par le même code (module `vm-noeud`). Relancer `lab/bin/check 12 46` : il passe en phase « clôture ».

*Démonstration de Julien — du commit à la recette* : MR d'une ligne (par exemple le texte d'une réponse de `/sante`), fusion, étiquette `vX.Y.Z+1` posée par semantic-release, pipeline : Hadolint, construction multi-architecture, test de fumée, poussée de `X.Y.Z+1`, puis un petit job du projet (sur les étiquettes de version, après `image`) qui recopie `X.Y.Z+1` sous l'étiquette mobile `recette` (`skopeo copy`, comme à la main en E30 ; le gabarit `image.yml` ne le fait pas) ; sur `ctr02`, `podman auto-update` (minuterie `podman-auto-update.timer` du compte, ou lancé à la main pour la démonstration, seul geste documenté) tire la nouvelle image et redémarre l'unité ; `curl …:8000/sante` montre la nouvelle version. Mesures : durée du pipeline, délai de la mise à jour, durée totale.

*Démonstration de Sophie — évasion* : depuis `podman exec -it mediagenda-api python` (pas de shell nécessaire) : `os.getuid()` (10001 dans le conteneur), lecture de `/proc/self/status` (`CapEff: 0000000000000000`), tentative d'écriture dans `/` (lecture seule), de `os.setuid(0)` (refusée) ; vu de l'hôte, `ps -o user,pid,cmd -C python` montre l'UID 534288 (plage de `app`) : même une évasion donnerait un compte sans privilège et sans `sudo`.

*Démonstration de Nadia — arrêt brutal de la base* : `podman kill mediagenda-pg` (SIGKILL) : `systemctl --user status mediagenda-pg` passe `failed` puis `Restart=always` la relance ; `/pret` répond 503 quelques secondes (PostgreSQL rejoue son journal), puis 200 ; `/sante` reste à 200 (pas de redémarrage inutile de l'API) ; `ms-verif-conteneurs` signale le redémarrage au passage suivant (seuil de redémarrages, E28).

**Grille de revue**

| Critère | Attendu | Qui |
|---|---|---|
| `lab/bin/check 12 46` | vert en recette, puis vert en clôture | tous |
| Dockerfile | base autorisée par empreinte, multi-étapes, `USER` numérique, sonde, `.dockerignore`, aucun secret (`docker history`) | Karim |
| CI | gabarit inclus, Hadolint en job, aucun `privileged`, publication sur étiquette, multi-architecture de MédiAgenda | Karim |
| Rôle `pile_recette` | idempotent (second passage sans changement), essai à blanc du générateur, secrets `no_log`, aucune édition à la main sur `ctr02` | Karim |
| Sécurité d'exécution | sans privilège, `NoNewPrivileges`, capacités retirées, racine en lecture seule où possible, limites, montages sans fichier sensible | Sophie |
| Secrets | Vault → secrets Podman ; registre des secrets à jour (emplacements) ; mots de passe du registre en variables protégées et masquées | Sophie |
| Exploitation | sondes correctes (`/sante` vivacité, `/pret` disponibilité), supervision de `runner02` et de la pile, ménage planifié, runbooks RB-120 à RB-125 | Nadia |
| Livraison | MR fusionnées, pipelines verts, `conteneurs-v1`, procès-verbal, environnement détruit par le code | Claire |

**Explications**
Le mini-projet ne demande presque rien de neuf : il oblige à faire tenir ensemble des pièces écrites séparément, sous trois contraintes qui révèlent les raccourcis (tout par le code, rien de privilégié, rien de provisoire). La pile de recette sur Quadlet est délibérément proche de ce que fera Kubernetes au M14 : un processus par conteneur, configuration par l'environnement, secrets montés, sondes séparées, redémarrage par l'orchestrateur, données en volumes.

**Alternatives**
- Pile de recette en Docker Compose (sous Podman, `podman compose` ou `docker compose` avec le socket Podman du compte) : acceptable si l'ADR-0120 le permet ; on perd la mise à jour automatique avec retour arrière de Quadlet et l'intégration systemd.
- Pods Podman (`.pod`) par application, comme en E14 : le réseau de l'application devient `localhost`, ce qui ressemble davantage à un pod Kubernetes ; au prix d'unités plus nombreuses.
- MédiDoc sur `s3-01` plutôt que SeaweedFS de recette : plus proche de la production, mais un flux de plus et des données de recette dans le stockage du socle.

**Pièges classiques**
- Secrets dans `Environment=` (visibles par `podman inspect` et dans le fichier Quadlet) au lieu de `Secret=`.
- Une URL de connexion contenant un mot de passe avec `/` ou `+` non encodés : générer des mots de passe hexadécimaux.
- Volumes des pièces jointes de Legacy-RDV créés par l'hôte (propriétaire `app`, donc root du conteneur) : `www-data` (33) ne peut pas écrire ; un volume nommé hérite des droits de l'image.
- `ctr01` détruite avant d'avoir décidé du sort des images : M13-E03 devra alors tout reconstruire par la CI (possible, mais à prévoir).
- `ms-verif-conteneurs` qui continue de chercher les conteneurs de `ctr01`/`ctr02` après leur destruction : mettre la configuration à jour dans la même MR que la destruction.

**En production chez MédiSphère**
La recette ne vivrait pas sur une VM unique : elle tournerait sur Kubernetes (M14), avec des images signées et analysées (M13), des déploiements GitOps (M20) et des secrets externes (M25). Ce qui reste de la v1 : les images, les normes, la CI sans privilège, les runbooks, et l'habitude de tout prouver par une vérification.

**Points non testés en conditions réelles** : le rôle `pile_recette` est validé par `ansible-lint` (profil `production`) et `yamllint`, ses modèles Quadlet rendus sans erreur ; il n'a pas été exécuté contre un `ctr02` réel. À vérifier sur ta version : la commande `s3.bucket.create` de `weed shell`, l'étiquette exacte de l'image SeaweedFS, le chemin `/usr/libexec/podman/quadlet` sur Rocky, `podman secret create --replace`, et le fonctionnement de MédiNotif et MédiAgenda avec `ReadOnly=true` (ajouter un `Tmpfs=` si une bibliothèque écrit dans `/tmp`).
