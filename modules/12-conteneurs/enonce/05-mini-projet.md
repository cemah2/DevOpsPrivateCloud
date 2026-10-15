# Module 12 — Palier 5 : Mini-projet

Le module a installé les moteurs, écrit les images, construit en CI sans privilège, durci, supervisé, cassé et réparé. Il reste à **livrer** : les quatre applications de MédiSphère en images de qualité, construites et publiées par la CI, une pile de recette complète qui démarre d'une commande sur un hôte sans privilège, et une documentation qui permette à Harbor (M13) puis à Kubernetes (M14) de reprendre le flambeau sans rien redécouvrir. Les VMs d'environnement disparaissent ensuite par le code ; `runner02` reste, comme un membre à part entière du socle. Ce mini-projet est ce que Claire Morel présentera aux équipes comme « conteneurs MédiSphère v1 ».

---

### M12-E46 — Mini-projet : conteneurs MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1346** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette des conteneurs v1 dans deux semaines. Je veux les quatre applications livrées en images construites par la CI, sans privilège, publiées dans le registre de travail, et une pile de recette qui les fait tourner ensemble sur `ctr02` comme elles tourneront demain sur Kubernetes. Le contrôle global doit être vert, et **rien de provisoire** ne doit survivre à la recette : les VMs du module disparaissent par le code, sauf ce qui est explicitement gardé pour le module suivant.
> Pendant la revue : Karim fera la revue des Dockerfile, des pipelines et du rôle de déploiement ; Sophie relira les normes, l'ADR-0120, le registre des secrets et la matrice des flux, et tentera d'obtenir un shell root sur `ctr02` depuis un conteneur ; Julien poussera une modification d'une ligne de MédiAgenda et chronométrera son arrivée en recette ; Nadia arrêtera brutalement la base de la recette pendant ta présentation et regardera ce qui se passe. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le module en une brique cohérente : images, CI, registre, exécution sans privilège, exploitation.
- Préparer le passage à Harbor (M13) et à Kubernetes (M14) : conventions de nommage et de versions, images non-root, sondes, configuration par l'environnement, documentation.
- Livrer l'état `conteneurs-v1` : documentation, flux, sauvegarde et supervision de `runner02`, étiquette de version, environnement détruit par le code.

**Prérequis** : M12-E01 à M12-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; aucune panne du module active.
**Durée indicative** : 14 à 20 h, plus 30 min de revue.

**Contexte technique**
- Hôtes : `ctr01` (2121, Docker 29, registre de travail `https://ctr01.par1.medisphere.internal:5000`), `ctr02` (2122, Podman 5.4, compte `app` UID 1001), `ctr03` (2123), `legacy01` (2124) dans l'état OpenTofu `m12-conteneurs` ; `runner02` (1012, 10.10.20.17) dans l'état `socle`.
- Projets des applications : `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv` ; gabarit de construction `plateforme/ci-templates` (`image.yml`, M12-E21) ; identifiants du registre pour les contrôles : `~/.config/workbook/registre-travail.env` sur `adm01` (variables `REGISTRE_UTILISATEUR` et `REGISTRE_MOT_DE_PASSE`, compte `plateforme` de l'équipe : les contrôles ne font que lire, mais le compte peut aussi pousser).
- Pile de recette attendue sur `ctr02`, sous le compte `app`, joignable depuis `adm01` :

  | Application | Point de contrôle | Dépendances dans la pile |
  |---|---|---|
  | MédiAgenda | `http://ctr02.par1.medisphere.internal:8000/pret` | PostgreSQL 18, Valkey 8 (migrations par un service ponctuel) |
  | MédiDoc | `http://ctr02.par1.medisphere.internal:8080/readyz` | un S3 : compartiment `medidoc-recette` sur `s3-01` (flux à ouvrir et documenter) **ou** un SeaweedFS de recette dans la pile |
  | Legacy-RDV | `http://ctr02.par1.medisphere.internal:8081/` | MariaDB 11.8, volume des pièces jointes |
  | MédiNotif | `http://ctr02.par1.medisphere.internal:9100/metrics` | RabbitMQ 4 |

- Sur `ctr02`, les essais des paliers précédents occupent encore des ports de la recette (`m12-e06-web` sur 8080, la pile Quadlet de M12-E14/E30 sur 8000) : la pile de recette les remplace, par le code.
- Le contrôle global `lab/bin/check 12 46` a deux moments. **Pendant la recette** (`ctr02` existe) : CI, images du registre (versions, utilisateur, multi-architecture de MédiAgenda), pile de `ctr02`, `runner02`, documentation. **Après la recette** (`ctr02` détruite) : CI, `runner02`, documentation, et la disparition des VMs du module ; `ctr01` peut être gardée jusqu'à la fin de M13-E03 (variable `WB_M12_CTR01_CONSERVE=1` dans `lab/lab.env`, choix écrit dans `recette-v1.md`). Il prend deux à quatre minutes.

**Travail demandé**
1. **Les images.** Chaque application a son Dockerfile (ou Containerfile) sur `main`, multi-étapes quand c'est utile, sur une image de base de la liste autorisée (M12-E27), non-root, sans secret, avec une sonde de santé adaptée, configurée par l'environnement uniquement ; Hadolint passe sans dérogation non justifiée ; Dive au-dessus du seuil de l'équipe (M12-E16). Les versions suivent `X.Y.Z` (semantic-release ou étiquette Git) ; MédiAgenda est publiée en `linux/amd64` et `linux/arm64`.
2. **La CI.** Les quatre pipelines incluent le gabarit `image.yml` de `plateforme/ci-templates`, construisent **sans mode privilégié** sur `runner02` (étiquette `docker`), lancent Hadolint en job, publient dans le registre de travail avec des identifiants protégés et masqués, et ne publient une version que depuis une étiquette. Pas de signature au M12 (Cosign arrive au M13) : écris-le dans la description de la MR du gabarit.
3. **La pile de recette.** Sur `ctr02`, sous `app`, par le code (rôle Ansible de `plateforme/ansible`, fichiers Quadlet ou Compose générés depuis l'inventaire, choix conforme à l'ADR-0120) : les quatre applications et leurs dépendances, images des applications tirées du registre de travail par empreinte ou version, aucune exécution privilégiée, secrets hors dépôt (Ansible Vault vers secrets Podman ou fichiers 600), volumes nommés pour les données, redémarrage automatique, retour au démarrage de `ctr02`, mise à jour par `podman auto-update` ou équivalent (M12-E30).
4. **runner02 dans le socle.** Décrit dans l'état `socle` d'OpenTofu, configuré par les rôles `docker_engine` et `gitlab_runner`, inventorié dans NetBox et le DNS, sauvegardé par PBS (comme les autres VMs du socle), supervisé (`ms-verif-conteneurs` ou la sonde du socle le connaît), nettoyé régulièrement (images et cache de construction), jamais privilégié.
5. **La documentation.** Dans `docs/conteneurs/` : `architecture.md` (hôtes, registre de travail, runner, chaîne de construction, pile de recette, flux, ce qui change avec Harbor et Kubernetes), `normes.md` (M12-E33) à jour des leçons du palier 4, l'ADR-0120 (M12-E31), les runbooks RB-120 à RB-125, `recette-v1.md` (procès-verbal : date, résultat de `lab/bin/check 12 46`, démonstrations, réserves) ; matrice des flux, inventaire et registre des secrets du socle à jour (emplacements, jamais les valeurs).
6. **Rien de provisoire.** Aucune panne `M12` active ; les témoins du palier 4 retirés (`/srv/recette` de `ctr01`, `recette-cache` de `ctr02` et `ctr03`, conteneur `capot`) ; après la revue, `ctr02`, `ctr03` et `legacy01` (et `ctr01` sauf choix écrit) détruites par OpenTofu (état `m12-conteneurs`), objets NetBox et DNS retirés par le même code.
   > ⚠️ **Attention** : la destruction de l'état `m12-conteneurs` est sans retour : relis le plan de destruction avant de l'appliquer, vérifie que `recette-v1.md` est commité et décide d'abord du sort de `ctr01` (les images du registre de travail ne sont copiées dans Harbor qu'au M13 ; si tu détruis `ctr01`, elles devront être reconstruites par la CI).
7. **La livraison.** Tout est fusionné, les pipelines de `main` des projets touchés sont verts, l'étiquette **`conteneurs-v1`** est posée sur `plateforme/medisphere`.
8. **La revue.** 10 minutes de présentation (choix, compromis, ce qui reste fragile : un seul registre sans réplication, une seule machine de recette, pas encore de signature ni d'analyse de vulnérabilités), puis les démonstrations de Julien (chronomètre du commit à la recette), de Sophie (évasion depuis un conteneur) et de Nadia (arrêt brutal de la base).

**Contraintes**
- Aucun secret dans un dépôt, un journal de CI, une image (`docker history`) ou la documentation.
- Aucun `privileged`, `--cap-add SYS_ADMIN` ou `seccomp=unconfined` en exécution sur `ctr02` ; sur `runner02`, seules les exceptions justifiées dans l'ADR-0120 pour la construction sans démon.
- Tout ce qui est créé l'est par le code (OpenTofu, Ansible, pipelines) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 12 46` est entièrement vert pendant la recette, puis de nouveau après la destruction de l'environnement.
- [ ] La démonstration de Julien : une modification d'une ligne de MédiAgenda arrive en recette par la CI, sans geste manuel sur `ctr02` (ou avec un seul geste documenté), en un temps mesuré et écrit dans `recette-v1.md`.
- [ ] La démonstration de Sophie échoue : depuis un conteneur de la pile, pas de root sur l'hôte (UID vus de l'hôte, capacités, montages).
- [ ] La démonstration de Nadia : l'arrêt brutal de la base est détecté (sondes, `ms-verif-conteneurs`), la base revient seule, MédiAgenda redevient prête sans intervention.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 12 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 12 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 12 XX`) donnent le détail par brique.
</details>

<details><summary>Indice 2</summary>

Commence par la CI (sans images publiées, pas de pile de recette), puis la pile service par service en commençant par les dépendances. La destruction de l'environnement vient **en dernier**, après la revue et après avoir écrit `recette-v1.md` : une fois `ctr02` détruite, la recette ne se rejoue qu'en recréant tout par le code (ce qui est aussi une bonne démonstration).
</details>

<details><summary>Indice 3</summary>

Pour Legacy-RDV et MédiNotif, relis les écarts aux « 12 facteurs » de M12-E19 et le comportement d'arrêt de M12-E17 : ce qui marchait en démonstration doit marcher sous systemd, après un redémarrage de `ctr02`, avec des volumes qui appartiennent au bon UID.
</details>

**Pour aller plus loin** (facultatif) : un test de bout en bout dans le pipeline de `mediagenda/api` qui déploie l'image candidate sur la pile de recette et appelle l'API (prise de rendez-vous, lecture, annulation) avant de marquer la version ; un tableau de bord texte des tailles d'images et de leur évolution par version (préparé pour M21).
