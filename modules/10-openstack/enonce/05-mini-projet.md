# Module 10 — Palier 5 : Mini-projet

Le cloud existe. Il a été déployé, branché sur Ceph, ouvert aux équipes, sécurisé, sauvegardé, supervisé, mis à jour, et l'astreinte a appris à le dépanner. Il reste à le **livrer** : un service que Claire Morel peut présenter à la direction et à l'auditeur HDS comme « cloud MédiSphère v1 », que Julien utilise sans ticket, que Nadia exploite avec les runbooks, et que quelqu'un d'autre que toi pourrait reconstruire depuis le dépôt. Les modules suivants s'en serviront comme d'une brique : clusters Kubernetes sur des instances (M18), observabilité branchée sur ses journaux et ses métriques (M21-M22), fédération d'identité (M24), montée de série (F4) et reprise après sinistre (F5).

---

### M10-E46 — Mini-projet : cloud MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1190** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du cloud dans trois semaines. Je veux un cloud qui passe le contrôle global sans un rouge, déployé **depuis le dépôt** et rien d'autre, qu'on sache restaurer, qu'on voie quand il souffre, et que les équipes utilisent seules.
> Pendant la revue : Julien créera la recette de MédiAgenda **de zéro** avec son pipeline et le guide utilisateur, sans nous ; Nadia fera vider un calcul avec RB-102 ; Sophie relira la sécurité (flux, secrets, certificats, ce qui reste en clair) ; Karim fera la revue du code et demandera qu'on reconstruise un détail de configuration depuis le dépôt. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module en un service cohérent, entièrement décrit par le code, sans geste manuel non consigné.
- Démontrer le libre-service de bout en bout et l'exploitabilité (sauvegarde, supervision, runbooks) par d'autres que toi.
- Livrer l'état `cloud-v1` : documentation pour les équipes et l'exploitation, limites connues, et ce que les modules suivants consommeront.

**Prérequis** : M10-E01 à M10-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; mini-projet M08-E46 (`ceph-par1`, pools et clés d'OpenStack).
**Durée indicative** : 12 à 18 h, plus 30 min de revue.

**Contexte technique**
- Nœuds : `osctl01` (2101), `oscmp01` (2102), `oscmp02` (2103), créés par OpenTofu (état `envs/openstack` de `plateforme/infra`, module `vm-noeud`), étiquette `env-m10`. Ceph : `ceph01-03` démarrées.
- Configuration : projet `plateforme/openstack` (`etc/kolla/globals.yml`, `globals.d/`, `config/`, `inventaire/multinode`, `passwords.yml` chiffré par l'identité `critique`, `certificates/` sans clé privée) ; déploiement par Kolla-Ansible 22.x depuis l'hôte de déploiement `adm01`.
- Faits figés (PLAN §4.9) : VIP interne 10.10.50.200 (`openstack-int.par1.medisphere.internal`), externe 10.10.50.201 (`openstack.par1.medisphere.internal`), VRID 150, OVN, Octavia fournisseur OVN, Ceph pour Glance, Cinder (et sauvegardes) et Nova, TLS des deux VIP par step-ca, domaine `medisphere` et projets `plateforme`, `mediagenda-dev`, `mediagenda-prod`.
- Documentation : `plateforme/medisphere`, dossier `docs/cloud/` (runbooks RB-100 à RB-102 et ceux du palier 4, ADR-0100 et ADR-0101, `haute-disponibilite.md`, `sauvegarde-restauration.md`, `securite.md`, `libre-service.md`, rapports de capacité), matrice des flux `docs/socle/matrice-flux.md`, registre des secrets.
- Le contrôle global `lab/bin/check 10 46` vérifie les nœuds, la configuration en code (valeurs figées, `passwords.yml` chiffré, aucune clé privée, pipeline vert, déploiement tracé depuis le dépôt), les services, **revérifie l'acquis du M08** (`ceph-par1` en `HEALTH_OK`, pools d'OpenStack), le TLS, les projets et quotas, Octavia OVN, la recette de MédiAgenda, la sauvegarde et la supervision, la sécurité, la documentation, l'étiquette `cloud-v1` et l'hygiène (instances et projets d'essai retirés, aucune panne active). Il prend quelques minutes.

**Travail demandé**
1. **Le dépôt fait foi.** Tout ce qui tourne doit pouvoir être reconstruit depuis `plateforme/openstack`, `plateforme/infra`, `plateforme/ansible` et les secrets en Vault. Décide comment un déploiement part **du dépôt** : par le pipeline (et alors sur quel exécuteur, avec quels accès, protégé comment) ou depuis `adm01` (et alors comment tu prouves que seul le commit validé de `main` est déployé, et comment chaque déploiement est tracé). Justifie le choix (sécurité des accès root aux nœuds et de l'identité `critique`, durée des jobs, runner partagé) et mets-le en œuvre. La CI de `plateforme/openstack` refuse au minimum : un `passwords.yml` en clair, une clé privée, une valeur figée du PLAN modifiée sans le dire.
2. **Le cloud.** Toutes les briques du module en service et vérifiées : Ceph, TLS interne et externe avec renouvellement automatique, OVN et `ext-net`, Octavia OVN, Heat, Horizon, domaines, projets, groupes et quotas (aucun quota par défaut de Nova laissé sur les projets des équipes), politiques et rôles de lecture, durcissement de Keystone et d'Horizon, matrice des flux.
3. **Le libre-service.** Le module `openstack-env-app` étiqueté, le dépôt `mediagenda/recette-infra` et son pipeline ; la recette de MédiAgenda en service. Prépare la démonstration de Julien : destruction puis recréation complète **par lui**, avec le seul guide utilisateur et le pipeline de son dépôt, chronométrée.
4. **L'exploitation.** Sauvegarde quotidienne de la base (Mariabackup → PBS, `par1/openstack`) et un test de restauration **réalisé pour cette livraison**, chronométré et réconcilié (ajouté en tête de `docs/cloud/tests/restauration.md`) ; sonde `ms-verif-openstack` planifiée avec alerte ; runbooks RB-100 à RB-102 et ceux du palier 4 relus après les exercices ; rapport de capacité du mois.
5. **La sécurité.** Registre des secrets complet pour le cloud (application credentials, jetons PBS, clés de chiffrement, `passwords.yml`, comptes de service, identité de la sonde : emplacement, portée, propriétaire, échéance — jamais la valeur) ; ce qui reste en clair et les risques acceptés, signés ; aucun secret dans un dépôt, un journal de CI ou la documentation.
6. **La documentation.** `docs/cloud/guide-utilisateur.md` pour les équipes (accès, projets et rôles, catalogue, premiers pas, limites — notamment celles du répartiteur OVN —, dépannage rapide, à qui s'adresser) ; une page d'entrée `docs/cloud/README.md` pour l'exploitation (architecture, décisions et ADR, runbooks, points uniques de défaillance restants, ce que les modules suivants consommeront).
7. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, aucune panne `M10` n'est active, les instances et projets d'essai du module sont retirés, et l'étiquette `cloud-v1` est posée sur `plateforme/medisphere` (commit qui documente la livraison).
8. **La revue.** 10 minutes de présentation (ce qui est livré, ce qui ne l'est pas encore, points uniques de défaillance, capacité, risques), puis les démonstrations de Julien (recette de zéro) et de Nadia (RB-102), et la reconstruction d'un détail demandée par Karim.

**Contraintes**
- Aucune interruption des instances des équipes pendant les derniers changements (les interruptions d'API sont annoncées et mesurées).
- Tout est créé par le code (OpenTofu, Kolla-Ansible depuis le dépôt, Ansible) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun identifiant `admin` dans un pipeline d'équipe ; aucun secret hors Vault, variables masquées et protégées, ou fichiers 600 de `adm01`.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 10 46` est entièrement vert.
- [ ] Julien recrée la recette de MédiAgenda de zéro avec le seul guide utilisateur et son pipeline, sans intervention de la plateforme (temps mesuré).
- [ ] Le test de restauration de la livraison est chronométré, réconcilié et consigné (RTO, RPO, orphelins).
- [ ] La documentation dit ce qui n'est **pas** encore redondant ou automatisé, et ce que les modules suivants devront traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 10 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 10 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 10 XX`) donnent le détail par brique, et ceux du M08 (`lab/bin/check 08 46`) celui de Ceph.
</details>

<details><summary>Indice 2</summary>

Pour prouver que « le dépôt fait foi », fais faire par quelqu'un d'autre (ou par toi, en suivant **seulement** la documentation) un `reconfigure` d'un service à partir d'un clone neuf de `plateforme/openstack` sur `adm01` : chaque fichier manquant, chaque variable d'environnement implicite, chaque secret posé à la main est un défaut à corriger.
</details>

<details><summary>Indice 3</summary>

Pour la démonstration de Julien, répète-la toi-même avec un compte qui n'a que les droits de son équipe (GitLab *Maintainer* de `mediagenda/recette-infra`, rien sur `plateforme/*`) : c'est là qu'apparaissent les accès oubliés (liste d'accès par jeton de job du dépôt des modules, variables protégées, quotas).
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord texte (préparé pour le module 21) qui résume, pour chaque projet, quotas, usage et coût estimé ; un exercice de reprise : `osctl01` arrêté 30 minutes pendant que Julien travaille, compte rendu de ce qu'il a vu.
