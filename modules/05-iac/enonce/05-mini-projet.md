# Module 05 — Palier 5 : Mini-projet

Fin du cinquième chantier. Au début du module, les machines du socle étaient créées à la main ou par des scripts, et personne ne pouvait dire, en lisant un dépôt, ce qui devait exister. Elles sont maintenant **déclarées** : `plateforme/infra` décrit le socle et les environnements, `plateforme/tofu-modules` publie des modules versionnés, l'état vit sur `s3-01`, chiffré, verrouillé, versionné et sauvegardé, chaque changement passe par un plan relu et un apply protégé, et la dérive est surveillée. Il reste à le **livrer** : que le socle entier soit décrit sans exception assumée, que ce code soit la seule façon de le faire évoluer, et que l'équipe sache le reprendre sans toi, y compris quand l'état ou la chaîne tombent en panne. Le module 06 s'appuie dessus : NetBox deviendra la source des adresses et des noms, PowerDNS sera piloté par un provider OpenTofu, step-ca remplacera la CA provisoire de `s3-01`. Ce mini-projet est ce que Claire Morel présentera à l'auditeur HDS comme « l'infrastructure est en code ».

---

### M05-E46 — Mini-projet : l'infrastructure MédiSphère déclarée  `LIBRE` `★★★`

> **Ticket PLAT-690** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel*
> Recette de l'infrastructure as code vendredi. Ce que je veux montrer à l'auditeur : **chaque** VM permanente du socle est soit décrite par `plateforme/infra` (plan vide), soit volontairement hors IaC avec une décision écrite ; aucune VM ne naît ni ne change sans MR, plan relu et apply tracé ; l'état est protégé (chiffré, verrouillé, versionné, sauvegardé) et on sait le restaurer ; on saurait dès le lendemain si quelqu'un modifiait une VM à la main ; le code est analysé comme du code applicatif. Karim fera la revue du code, des modules et du pipeline, Sophie celle des secrets, des droits et de l'analyse de sécurité, Nadia testera elle-même la restauration de l'état avec le runbook. Format habituel : 10 minutes de présentation, une démonstration, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module (provider, modules versionnés, backend S3 sur `s3-01`, verrou, chiffrement, import, refactoring, pipeline, analyse de sécurité, dérive, sauvegarde de l'état) en une chaîne cohérente, sans dette cachée.
- Livrer `s3-01` comme hôte permanent du socle, créé par le code et configuré par Ansible, avec tout ce qu'implique un nouvel hôte (DNS, flux, sauvegarde, inventaire, documentation).
- Préparer le module 06 : ce qui viendra de NetBox, ce qui sera piloté par provider (DNS), ce qui changera pour la PKI.

**Prérequis** : M05-E01 à M05-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 10 à 14 h, plus 30 min de revue.

**Contexte technique**
- Projets : `plateforme/infra` (clone `~/src/infra`), `plateforme/tofu-modules` (clone `~/src/tofu-modules`), `plateforme/ansible` (clone `~/src/ansible`) ; documentation `plateforme/medisphere` (clone `~/medisphere`, variable `WB_DEPOT`). Arborescence de référence de `plateforme/infra` : [`00-introduction.md`](00-introduction.md).
- Socle à décrire : `adm01` (1001), `dns01` (1002), `git01` (1004), `s3-01` (1006), `runner01` (1007), dans l'état `socle` (clé `socle/terraform.tfstate`). `gw01` (1000) est le cas particulier décidé en M05-E16 : hors IaC ou importé en lecture seule, la décision est écrite (ADR ou section de `docs/socle/iac.md`) et le contrôle global ne l'impose pas.
- `s3-01` : VMID 1006, 10.10.20.14, VNet `vinfra`, 2 vCPU, 2 Go, disque système 20 Go, disque de données 100 Go sur `hdd-bulk`, étiquettes `socle` et `role-s3`, SeaweedFS configuré par le rôle Ansible `seaweedfs` (Molecule compris), passerelle S3 HTTPS sur 8333, compartiment `tofu-state` versionné.
- Les VMs d'environnement 2050-2059 sont **détruites** à la fin du module (par `tofu destroy` dans `envs/lab-m05`, plan relu) ; l'objet d'état `envs/lab-m05/terraform.tfstate` reste (vide, chiffré, versionné).
- Le contrôle global `lab/bin/check 05 46` lance un plan complet du socle (sans verrou), lit l'état et le compartiment en lecture seule et interroge GitLab (protections, pipelines, planification, versions). Il exige aussi qu'aucune panne `M05-*` ne soit active.

**Travail demandé**
1. **Le socle en code.** L'état `socle` contient les cinq VMs permanentes, toutes à des adresses décrites par le code (modules versionnés de `plateforme/tofu-modules` pour ce qui est créé par le code, ressources importées pour l'existant), avec `prevent_destroy`, la protection Proxmox et des `ignore_changes` **justifiés un par un** (commentaire). Le plan est vide. Les décisions d'exclusion (au moins `gw01`) sont écrites.
2. **`s3-01` livrée.** Créée par le code, configurée par Ansible (rôle `seaweedfs` testé par Molecule, appliqué par la chaîne de M04), déclarée dans le DNS, dans l'inventaire, dans la matrice des flux, sauvegardée par `lab-nuit` (pool `lab`), supervisable (au moins un contrôle de santé documenté). Ses identités S3 suivent le moindre privilège (`tofu-etat` limité au compartiment `tofu-state`, `admin-s3` réservée au bris de glace).
3. **L'état protégé.** Backend S3 sur `s3-01` avec verrou natif, chiffrement OpenTofu (`state` et `plan`) avec phrase hors du code, compartiment versionné, sauvegarde hors de `s3-01` (M05-E29). **Démonstration** : Nadia restaure seule une version antérieure de l'état `socle` avec le runbook (sur une copie ou une clé d'essai si tu préfères ne pas toucher à la vraie), et prouve que le plan est vide ensuite.
4. **La chaîne de livraison.** Pipeline de `plateforme/infra` : qualité (`fmt`, `validate`, `tflint`, `terraform-docs` vérifié, pre-commit), sécurité (Checkov et Trivy, Trivy **épinglé par empreinte**, exceptions justifiées), `plan` visible dans la MR, `apply` manuel, protégé, sur `main` seulement, sérialisé, qui applique **le plan sauvegardé** du pipeline. Les modules sont consommés par étiquette de version (`?ref=vX.Y.Z`) et publiés par semantic-release.
5. **La dérive.** Le contrôle planifié tourne chaque nuit sur le socle, échoue (et alerte) s'il trouve un écart, et son dernier passage est vert. Démontre-le : modifie à la main un réglage géré d'une VM du socle (annonce-le), constate l'alerte, corrige par la chaîne (en choisissant et en justifiant : défaire la modification ou l'adopter dans le code).
6. **Les secrets et les droits.** Le jeton `wb-tofu@pve!tofu` a des privilèges minimaux, vérifiés (M05-E38) ; les identifiants S3 et la phrase de chiffrement sont dans `~/.config/workbook/` (600) et en variables CI protégées et masquées ; tout est inscrit au registre des secrets (emplacement, portée, propriétaire, rotation, copie de secours de la phrase). Aucun secret dans les dépôts, les journaux CI ni la documentation.
7. **La documentation.** `docs/socle/iac.md` : organisation des projets, états et leur périmètre (rayon d'impact), modules et versions, chaîne de livraison, gestion de l'état (verrou, chiffrement, versionnage, sauvegarde, restauration), import et refactoring, dérive, ce qui n'est **pas** en code et pourquoi, conventions de l'équipe tirées du palier 4. ADR-0050 fusionné ; RB-050 (verrou bloqué) et un runbook de restauration de l'état testés ; inventaire du socle et matrice des flux à jour.
8. **Hygiène.** Aucune panne `M05` active ; VMs 2050-2059 détruites ; copies de travail propres et à jour de `main` ; aucune copie d'état en clair ni journal de trace sur `adm01` ; une seule image dorée Debian `current`.
9. **La revue.** Prépare 10 minutes de présentation (ce qui est en code, ce qui ne l'est pas et pourquoi, les risques restants, ce que le module 06 changera) et la démonstration : une MR qui modifie une VM du socle (une étiquette ou une description), du plan en MR jusqu'à l'apply protégé, puis la restauration de l'état par Nadia.

**Contraintes**
- Aucune VM permanente recréée pendant le mini-projet (même VMID **et** même date de création dans Proxmox) ; aucune interruption de `git01`, `runner01` ni de l'état au-delà d'un redémarrage annoncé de `s3-01`.
- Aucun apply du socle hors du job protégé, sauf l'apply initial de `s3-01` s'il précède le pipeline (tracé dans le journal).
- Aucun secret en clair dans les dépôts, les artefacts CI (plans compris : ils sont chiffrés), les sorties de pipeline ou la documentation (cite des **emplacements**, jamais des valeurs).
- Les choix qui s'écartent de l'énoncé d'un exercice sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 05 46` est entièrement vert.
- [ ] Le plan du socle est vide ; chaque VM permanente est en code ou exclue par une décision écrite.
- [ ] La restauration de l'état a été faite par un tiers avec le seul runbook (auto-évaluation avec la grille du corrigé si tu travailles seul).
- [ ] La démonstration de dérive a été faite : alerte reçue, correction par la chaîne, trace dans le journal.
- [ ] La documentation dit ce qu'OpenTofu **ne** gère **pas** encore et ce que le module 06 va changer.

**Vérification** : `lab/bin/check 05 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 05 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés de chaque exercice (`lab/bin/check 05 XX`) donnent le détail par brique, et ceux du palier 4 sont de bonnes sondes de santé de la chaîne.
</details>

<details><summary>Indice 2</summary>

Pour chaque `ignore_changes`, pose la question : « si quelqu'un changeait cet attribut à la main, voudrais-je le savoir ? ». Si oui, il ne doit pas être ignoré ; s'il est ignoré quand même (attribut que Proxmox réécrit seul, image qui change chaque semaine), le commentaire dit pourquoi et ce qui surveille l'attribut à la place.
</details>

<details><summary>Indice 3</summary>

Une restauration d'état testée par quelqu'un d'autre révèle toujours un manque dans le runbook : où sont les identifiants, comment lister les versions, comment savoir laquelle est saine, comment prouver que c'est fini. Fais-la faire (ou fais-la toi-même une semaine plus tard, sans autre document), et corrige le runbook après.
</details>

**Pour aller plus loin** (facultatif) : une étiquette `iac-v1` dans `plateforme/medisphere` sur le commit qui documente la livraison ; un tableau de bord (préparé pour le module 21) de la durée des plans et des écarts de dérive par VM ; la liste « ce qui n'est pas encore en code » transformée en tickets pour le module 06.
