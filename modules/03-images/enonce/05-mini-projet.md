# Module 03 — Palier 5 : Mini-projet

Fin du troisième chantier. Le template fait à la main du module 00 a des successeurs : des images construites par du code, durcies, testées, versionnées, publiées par la forge et retirées quand elles vieillissent, et tu sais les dépanner. Il reste à **livrer le catalogue** : les deux familles promises à Sophie et à Julien, au même niveau d'exigence, une chaîne qui tourne sans toi, et une documentation qui permet aux consommateurs de s'en servir sans te demander. Les modules suivants en dépendent directement : Molecule (module 04) crée ses instances de test par clones liés de `gold` + `debian13` + `current` ; OpenTofu (module 05) crée les VMs durables par clones complets de la même sélection ; la PKI du module 06 changera l'autorité embarquée et déclenchera une reconstruction. Ce mini-projet est ce que Claire Morel présentera comme « catalogue d'images MédiSphère v1 ».

---

### M03-E25 — Mini-projet : catalogue d'images MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-490** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel*
> Recette du catalogue vendredi. Je veux les deux familles, Debian 13 et Rocky Linux 10, de base et dorées, construites par la forge, testées, publiées, avec une rotation qui tourne ; un catalogue documenté que l'équipe de Julien sait utiliser seule ; et un lab propre. Karim fera la revue du code, Sophie vérifiera le durcissement et les secrets, Julien créera une VM de chaque famille avec la seule documentation, Nadia tirera une panne au sort. Format habituel : 10 minutes de présentation, une démonstration, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module (Packer, images de base et dorées, cloud-init, préparation, durcissement, tests, CI, publication, rotation) en un produit cohérent et documenté.
- Étendre la chaîne à une seconde famille d'OS sans dupliquer la logique, et en tenant compte de ses différences (gestionnaire de paquets, SELinux, CPU, services).
- Défendre une livraison en revue : ce qui est livré, ce qui ne l'est pas, les risques.

**Prérequis** : M03-E01 à M03-E24 (au minimum tous les `LAB`, `LIBRE` et `BF`).
**Durée indicative** : 8 à 12 h (dont beaucoup d'attente de builds), plus 30 min de revue.

**Contexte technique**
- Projet : `plateforme/images` (`~/src/images`) ; documentation : `plateforme/medisphere` (`~/medisphere`). Arborescence de référence : [`00-introduction.md`](00-introduction.md).
- Image dorée Rocky : `rocky10-gold/`, clone de 9002, VMID 9030-9049, nom `rocky10-gold-AAAAMMJJ-N`, étiquettes `gold` + `rocky10`. CPU `x86-64-v3` minimum. Contenu équivalent à l'image Debian : agent, cloud-init, chrony sur la passerelle du VLAN, CA provisoire dans le magasin du système, sshd de base et durci, journal persistant, correctifs de sécurité automatiques (équivalent Rocky d'`unattended-upgrades`), SELinux en mode *enforcing*, durcissement SEC-450.
- Catalogue documentaire : `docs/socle/images.md` (nouveau). Runbooks attendus : RB-037 (retrait, E16) et RB-038 « Diagnostiquer un build ou un premier démarrage » (à partir de tes journaux du palier 4).
- Le contrôle global vérifie notamment : bases 9001 et 9002, une seule version `current` par famille (moins de 8 jours), rotation appliquée, manifeste dans les notes, CPU de l'image Rocky, pipeline planifié réussi dans les 8 derniers jours, secret protégé, fichiers clés sur `main`, documentation, hygiène.

**Travail demandé**
1. **La seconde famille.** Ajoute l'image dorée Rocky Linux 10 : build, script de contenu, durcissement (ton `durcir.sh` gère les deux familles, sans copie), test (`tests/tester-image.sh` connaît les différences de la famille RHEL). Fais-la construire, tester et publier **par la CI**.
2. **La chaîne.** Les deux familles sont reconstruites chaque semaine par le même pipeline planifié, testées, publiées, puis la rotation s'applique. Laisse tourner au moins **une** exécution planifiée complète avant la recette.
3. **Le catalogue.** `docs/socle/images.md` : familles et templates, étiquettes, comment consommer une image (sélection, type de clone, paramètres cloud-init à fournir, particularités Rocky), contenu de chaque famille, cycle de vie, responsabilités, registre des versions publiées. ADR-0030 fusionné et cohérent avec ce document.
4. **L'exploitation.** RB-037 et RB-038 fusionnés ; inventaire (`docs/socle/inventaire.md`) et matrice des flux à jour ; jeton `wb-packer` et variables CI inscrits au registre des secrets (propriétaire, expiration, rotation).
5. **La preuve d'usage.** Avec la seule documentation, crée une VM de chaque famille (VMID 2030 et 2031, clones **complets** de `current`), vérifie que tout ce que promet le catalogue est vrai sur elles (connexion, nom, heure, CA, durcissement), puis détruis-les.
6. **L'hygiène.** Aucune panne `M03` active (clos-les avec `--annuler`), aucune VM 2030-2039, aucun template 9090-9099, aucun secret dans les dépôts, fichiers de `~/.config/workbook/` en 600.
7. **La revue.** 10 minutes de présentation (ce qui est livré, ce qui ne l'est pas, les risques), démonstration (un pipeline, une VM de chaque famille, un retrait d'image en simulation), puis Nadia tire une panne de M03-E19 à M03-E22 que tu résous avec RB-038.

**Contraintes**
- Aucune image n'est publiée depuis un poste : seule la CI pose `current` (sauf retrait d'urgence documenté par RB-037).
- Aucun secret dans les dépôts, les images, les notes des templates, les journaux de CI ou la documentation (des **emplacements**, jamais des valeurs).
- La logique commune aux deux familles n'est pas dupliquée (scripts, tests, pipeline) ; les différences sont explicites et commentées.
- Tout changement passe par une MR relue avec pipeline vert ; les écarts aux exercices sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 03 25` est entièrement vert.
- [ ] Une VM de chaque famille, créée avec la seule documentation, tient toutes les promesses du catalogue.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul), sans critère éliminatoire.

**Vérification** : `lab/bin/check 03 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 03 25` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 03 13` à `03 16`) donnent le détail par brique.
</details>

<details><summary>Indice 2</summary>

Les différences Rocky à prévoir : emplacement et commande du magasin de certificats, nom du service chrony et de son fichier de configuration, contextes SELinux des fichiers déposés (`restorecon`), outil de correctifs automatiques, initramfs à régénérer quand `modprobe.d` change. Écris-les une fois, dans un `case` sur la famille.
</details>

<details><summary>Indice 3</summary>

Un pipeline planifié se déclenche à la demande (*Run pipeline schedule*) sans attendre la semaine : pratique pour vérifier avant la recette. Mais le contrôle regarde aussi la **fraîcheur** de la version `current` : une semaine sans pipeline réussi, et il passe au rouge.
</details>

**Pour aller plus loin** (facultatif) : signature du manifeste de chaque image (clé de l'équipe, vérifiée par les consommateurs) ; un SBOM des paquets (Syft, module 13) en artefact ; une étiquette `images-v1` dans `plateforme/medisphere` sur le commit qui documente la livraison.
