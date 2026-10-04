# Module 02 — Palier 5 : Mini-projet

Fin du deuxième chantier. Les scripts éparpillés du module 00 sont devenus un projet : `plateforme/outils`, relu, testé, versionné, distribué, supervisé, et tu as appris à le dépanner. Il reste à le **livrer** comme un produit interne : une version que toute l'équipe installe de la même façon, une documentation qui permet à Nadia de se débrouiller la nuit, des décisions écrites, et un inventaire du socle qui ne ment plus. Les modules suivants s'appuient dessus : les images dorées (module 03) seront construites et testées avec ces outils, Ansible (module 04) installera `medictl` et les unités de contrôle sur les postes d'administration, OpenTofu (module 05) remplacera `medictl vm create` pour l'infrastructure durable, et NetBox (module 06) reprendra l'inventaire. Ce mini-projet est ce que Claire Morel présentera comme « outillage MédiSphère v1 ».

---

### M02-E46 — Mini-projet : outillage MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-390** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel, Sophie Laurent*
> Recette de l'outillage v1 vendredi. Je veux une version publiée par la forge, installée sur `adm01` depuis le registre, des scripts qui passent tous leurs contrôles, un contrôle des sauvegardes qui tourne et dont on saurait s'il s'arrêtait, et une documentation qui permet à Nadia de travailler sans t'appeler. Karim fera la revue de code, Sophie vérifiera les jetons et les secrets, Nadia testera le guide d'astreinte sur une panne tirée au sort. Format habituel : 10 minutes de présentation, une démonstration, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module (scripts Bash, CLI Python, tests, CI, distribution, planification, documentation) en un produit cohérent, sans dette cachée.
- Livrer une version par la chaîne complète (MR, pipeline, release, paquet, installation) et la défendre en revue.
- Préparer les modules suivants : ce qui sera repris par Ansible, OpenTofu et NetBox.

**Prérequis** : M02-E01 à M02-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Projet : `plateforme/outils` (clone `~/src/outils`, variable `WB_SRC`) ; documentation : `plateforme/medisphere` (clone `~/medisphere`, variable `WB_DEPOT`). Arborescence de référence du projet : [`00-introduction.md`](00-introduction.md).
- La version publiée est celle de la **dernière release GitLab** du projet (étiquette `vX.Y.Z` posée par semantic-release, M02-E25) ; elle doit contenir tout ce qui est livré ici.
- Le contrôle global `lab/bin/check 02 46` vérifie notamment : release et paquet, installation de `medictl`, ShellCheck sur `bin/ms-*` et `lib/`, chaque `bin/ms-*` cité par au moins un test (bats, ou pytest pour un script piloté par `subprocess`), tâches `lint`, `test`, `build`, `install`, timer de contrôle, documentation, ADR-0020, inventaire, hygiène et secrets.

**Travail demandé**
1. **Le produit.** Intègre dans `plateforme/outils`, par MR, tout ce qui est resté en dehors : scripts corrigés du palier 4 (`ms-purge-rapports`, `ms-archiver-journaux`, le chien de garde de M02-E41), spécification de M02-E44, unités systemd du dossier `systemd/`. Chaque script de `bin/` a des tests ; ceux qui n'en avaient pas (par exemple `ms-alerte`) en reçoivent. `task lint` et `task test` sont verts sur `adm01` et en CI.
2. **La qualité mesurée.** Le dernier pipeline de `main` publie les rapports de tests (bats et pytest, aucun échec) et le taux de couverture de `medictl`. Note ce taux dans le README, et ce que les tests **ne** couvrent pas (les appels réels à Proxmox) et pourquoi c'est assumé.
3. **La version.** Fusionne les MR avec des messages conventionnels qui produisent une nouvelle version **mineure** au moins (nouvelles fonctions livrées), publiée par la CI : release GitLab, paquet `medictl` (roue et archive source) dans le registre du projet. Les notes de version doivent permettre à un lecteur de savoir ce qui change pour lui.
4. **L'installation.** Sur `adm01` : `medictl` de cette version installé depuis le registre par `uv tool`, scripts et bibliothèque de cette même version copiés dans `/usr/local` par une tâche du Taskfile (M02-E20, M02-E26) **sans** remplacer le `medictl` du registre, unités installées, timers `ms-verif-sauvegardes` et chien de garde actifs. Décris dans le README la procédure d'installation **et** de retour à la version précédente, testée.
5. **La documentation.** `README.md` (contenu du projet, contrat commun, installation, configuration et secrets, contribution) ; `docs/astreinte.md` complété avec ce que le palier 4 t'a appris (chaque panne vécue : symptôme, premiers gestes, vérification) ; `CONTRIBUTING.md` avec la grille de revue Bash et Python (dont tes règles de M02-E40, M02-E42 et M02-E44) ; ADR-0020 fusionné dans `plateforme/medisphere`.
6. **L'inventaire.** Régénère `docs/socle/inventaire.md` de `plateforme/medisphere` avec `medictl inventaire` (M02-E21) et fusionne-le : toutes les VMs étiquetées `socle` y figurent. Ajoute à l'inventaire la section « comptes et jetons d'automatisation » à jour (identité, rôle, périmètre, emplacement du secret, date d'expiration, propriétaire), sans aucun secret.
7. **L'hygiène.** Aucune panne `M02` active, aucune VM 2020-2029 restante, zones de test `/opt/workbook/m02/` nettoyées si tu n'en as plus besoin, aucun secret dans les dépôts, fichiers de `~/.config/workbook/` en 600.
8. **La revue.** Prépare 10 minutes de présentation (ce qui est livré, ce qui ne l'est pas, les risques) et la démonstration : Nadia tire une panne de M02-E35 à M02-E42 et la résout **avec le seul guide d'astreinte** pendant que tu observes.

**Contraintes**
- Aucun secret dans les dépôts, les journaux CI, les reçus d'installation, les tickets ou la documentation (cite des **emplacements** de secrets, jamais des valeurs).
- Tout changement passe par une MR relue (même par toi, le lendemain) avec pipeline vert ; rien n'est publié depuis un poste.
- Les choix techniques qui s'écartent de l'énoncé d'un exercice sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 02 46` est entièrement vert.
- [ ] La dernière release de `plateforme/outils` contient les livrables du palier 4 ; ses notes de version sont lisibles par un utilisateur.
- [ ] Le retour à la version précédente de `medictl` est documenté et a été testé.
- [ ] Le guide d'astreinte a permis de résoudre une panne tirée au sort sans autre aide (auto-évaluation avec la grille du corrigé si tu travailles seul).
- [ ] L'inventaire du socle (VMs, comptes et jetons) est généré, à jour, sans secret.

**Vérification** : `lab/bin/check 02 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 02 46` dès le début : la liste des points rouges est ton plan de travail. Puis relance les contrôles de chaque exercice concerné (`lab/bin/check 02 XX`) pour le détail.
</details>

<details><summary>Indice 2</summary>

Une nouvelle version **mineure** se déclenche par au moins un commit `feat:` fusionné dans `main` depuis la dernière étiquette (M01-E25). Regarde l'historique depuis cette étiquette (`git log --oneline vX.Y.Z..main`) avant de fusionner : que dira la release ?
</details>

<details><summary>Indice 3</summary>

Pour tester ton guide d'astreinte seul : laisse passer quelques jours, injecte une panne au hasard (`lab/bin/break 02 $((RANDOM % 8 + 35))`), et interdis-toi tout autre document que le guide. Chaque fois que tu dois deviner, il manque une ligne.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord de l'outillage (version installée par poste, dernier succès de chaque contrôle planifié) préparé pour le module 21 ; une étiquette `outillage-v1` dans `plateforme/medisphere` sur le commit qui documente la livraison.
