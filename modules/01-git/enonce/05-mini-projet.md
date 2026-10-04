# Module 01 — Palier 5 : Mini-projet

La forge est construite, sauvegardée, mise à jour, supervisée, et tu as appris à la dépanner. Il reste à la **livrer** : au sens d'une équipe d'exploitation, un service n'est livré que s'il est vérifiable, documenté, restaurable et exploitable par quelqu'un d'autre que son auteur. À partir du module 02, tout ce que tu produiras (scripts, images, rôles Ansible, code OpenTofu) passera par cette forge : ses règles, sa CI et ses versions automatiques deviennent le cadre de travail de toute l'équipe. Ce mini-projet est ce que Claire Morel présentera comme « forge v1 ».

---

### M01-E47 — Mini-projet : la forge MédiSphère  `LIBRE` `★★★`

> **Ticket PLAT-290** — *De : Claire Morel*
> Recette de la forge vendredi. Je veux une forge qui passe le contrôle global sans un seul rouge, et un dossier qui permette à n'importe qui de l'équipe de l'exploiter, de la restaurer et de la faire évoluer sans t'appeler. Déroulé : 10 minutes de présentation, une démonstration que je choisirai sur place, puis nos questions. Sophie relira les jetons, les flux et l'historique des dépôts (aucun secret, jamais) ; Karim relira les règles des projets et la CI ; Nadia voudra voir le runbook d'incident.

**Objectifs pédagogiques**
- Consolider la forge construite dans le module en un service cohérent, vérifiable et sans dette cachée.
- Appliquer uniformément les règles de l'équipe à tous les projets de la plateforme, en les décrivant de façon reproductible.
- Produire la documentation d'exploitation d'un service : fiche de service, inventaire, matrice des flux, décisions, runbooks, preuves de restauration.
- Défendre ses choix en revue, avec des éléments mesurés.

**Prérequis** : M01-E01 à M01-E46 (au minimum tous les `LAB`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Projets concernés : tous les projets du groupe `plateforme` existant à la fin du module (au moins `plateforme/medisphere` et `plateforme/ci-templates`). Le groupe `formation` n'est pas concerné par les règles de livraison.
- Le dossier de livraison vit dans `plateforme/medisphere` (clone de travail `~/medisphere`, `WB_DEPOT`) et complète le dossier du socle livré au M00 (`docs/socle/`). Structure minimale ajoutée ou mise à jour par ce module :

  ```
  docs/socle/
  ├── forge.md               fiche de service de la forge (nouveau)
  ├── inventaire.md          + git01, runner01, comptes et jetons de la forge (emplacements)
  ├── matrice-flux.md        + flux de la forge (443, 22, 8007 vers PBS…)
  ├── adr/ADR-0010-*.md      organisation des dépôts (M01-E33) ; autres ADR du module à partir de 0011
  ├── runbooks/RB-010-*.md   restaurer GitLab (M01-E28)
  ├── runbooks/RB-011-*.md   mettre à jour GitLab (M01-E29)
  ├── runbooks/RB-012-*.md   diagnostiquer la forge : sonde, carte des composants (M01-E30)
  ├── runbooks/RB-013-*.md   la forge est en panne : diagnostic par symptôme (nouveau)
  ├── tests/restauration.md  + test de restauration de GitLab daté
  ├── post-mortems/          + INC-2788 (M01-E43)
  ├── journal/               journaux de diagnostic du palier 4
  └── analyses/              M01-E45
  CONTRIBUTING.md, .gitlab/merge_request_templates/Default.md   (M01-E22)
  forge/hooks/, forge/supervision/, forge/outils/                (M01-E26, E30, E43)
  ```
- Adresses, VMID et noms : `PLAN.md` §4.5 et §4.8. VMs jetables du module : 2010-2019.

**Travail demandé**
1. **Forge saine.** Fais passer `lab/bin/check 01 47` au vert, sans ignorer de contrôle. Corrige à la racine ce qui ne l'est pas, y compris l'hygiène : panne d'exercice encore active, VM jetable oubliée (2010-2019), projet temporaire, jeton inutile encore actif.
2. **Règles uniformes.** Tous les projets de `plateforme` ont les mêmes règles (branche protégée, méthode de fusion, pipeline et discussions résolues obligatoires, pre-commit, gabarits de CI de `plateforme/ci-templates` inclus en `ref: v1`, la branche majeure que fait avancer la chaîne de release (M01-E24, M01-E25), étiquettes `v*` protégées). Ces réglages sont appliqués **par un script versionné** et rejouable (tu peux partir de celui de M01-E11), pas cliqués projet par projet. Un projet ajouté demain doit pouvoir être mis en conformité en une commande.
3. **Versions automatiques** sur `plateforme/medisphere` et `plateforme/ci-templates` : au moins une Release `vX.Y.Z` publiée par semantic-release sur chacun, avec ses notes.
4. **Sauvegarde et restauration.** Sauvegarde applicative de moins de 48 h sur `git01` et dans PBS (`par1/git01`). Un test de restauration **réalisé pour cette livraison** sur la VM jetable 2010 (puis détruite), consigné en tête de la section GitLab de `tests/restauration.md` : version restaurée, durée de chaque étape, RTO mesuré, RPO constaté, écarts.
5. **Fiche de service** `docs/socle/forge.md` : ce que rend le service et pour qui, engagement (disponibilité visée, RTO, RPO), composants et versions, dépendances, accès (normal, administration, secours, bris de glace), règles des projets, sauvegarde, exploitation (mises à jour, supervision, incidents), risques connus et leur traitement.
6. **Inventaire et matrice des flux** mis à jour : `git01`, `runner01` (VMID, adresses, ressources, étiquettes Proxmox, démarrage), comptes et jetons de la forge avec leur **emplacement** et leur date d'expiration (jamais leur valeur) ; chaque flux de la forge relié à sa règle nftables sur `gw01`.
7. **Runbooks.** RB-010, RB-011 et RB-012 relus et à jour ; RB-013 « la forge est en panne » rédigé à partir de tes pannes du palier 4 (il renvoie à RB-012 pour la sonde et la carte des composants) : par symptôme (502, push refusé, SSH, jobs bloqués, release en échec), les commandes de diagnostic dans l'ordre, le résultat attendu de chacune, le correctif sûr et le retour arrière.
8. **Supervision minimale.** La sonde de M01-E30 tourne de façon planifiée, et tu sais montrer où on voit son dernier résultat.
9. **Secrets.** Aucun secret dans l'historique d'aucun projet de `plateforme` (jetons, clés privées, mots de passe) : démontre-le par un balayage de l'historique complet (Gitleaks, M01-E16), pas seulement du dernier commit. Les jetons d'automatisation (`bot-release`…) ont une date d'expiration notée dans l'inventaire.
10. **Livraison.** Tout passe par MR (pipeline vert). Une fois le dernier changement fusionné, pose sur `main` de `plateforme/medisphere` l'étiquette annotée **et signée** `forge-v1` (signature SSH, M01-E27), et pousse-la. Ton clone de travail est propre.
11. **Revue.** Prépare 10 minutes de présentation (architecture, état, règles, risques, prochaines étapes) et sois prêt à démontrer en direct, au choix de Claire, une des opérations de tes runbooks.

**Contraintes**
- Aucune information ne contredit `PLAN.md` (adresses, VMID, noms, projets). Tout écart est documenté dans un ADR.
- Toute valeur chiffrée (RTO, mémoire, durées, tailles) est datée et sa source indiquée.
- Le dossier est lisible sans le workbook : un nouvel arrivant comprend la forge sans avoir fait le module.
- Rien n'est exposé hors du lab ; aucun jeton à durée illimitée.

**Critères de réussite**
- [ ] `lab/bin/check 01 47` est entièrement vert.
- [ ] Les règles des projets de `plateforme` sont appliquées par un script versionné, rejoué avec succès pendant la revue.
- [ ] `plateforme/medisphere` et `plateforme/ci-templates` ont chacun au moins une Release publiée automatiquement.
- [ ] Le test de restauration de GitLab de cette livraison est consigné avec une durée mesurée ; la VM 2010 est détruite.
- [ ] `forge.md`, inventaire, matrice des flux, ADR-0010, RB-010 à RB-013 et le post-mortem INC-2788 sont sur `main`.
- [ ] Le balayage de l'historique complet ne trouve aucun secret ; l'étiquette signée `forge-v1` est publiée.
- [ ] La revue avec Claire est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 01 47`

<details><summary>Indice 1</summary>

Commence par le contrôle global et traite chaque KO à sa racine, en t'appuyant sur les checks détaillés des exercices concernés (`lab/bin/check 01 <XX>`). Un KO de « dernier pipeline de main » cache souvent un gabarit de CI à une référence qui a bougé, ou un job qui n'a jamais tourné depuis une mise à jour.
</details>

<details><summary>Indice 2</summary>

Pour les règles uniformes, liste d'abord les réglages réels de chaque projet par l'API (`GET /projects/:id`, `protected_branches`, `protected_tags`) et compare-les : les écarts que tu trouves sont la meilleure preuve que les réglages à la main dérivent. Ton script doit être idempotent : le relancer sur un projet conforme ne change rien.
</details>

<details><summary>Indice 3</summary>

Pour les secrets, `gitleaks git` analyse tout l'historique d'un dépôt cloné (toutes les branches avec l'option adéquate : vérifie `gitleaks git --help`). Un secret trouvé dans l'historique se traite comme en M01-E17 : révocation d'abord, nettoyage ensuite.
</details>

**Pour aller plus loin** (facultatif) : génère la section « Projets » de `forge.md` par un script à partir de l'API GitLab (tu le reprendras au module 02) ; ajoute à la CI de `plateforme/medisphere` un job planifié qui rejoue ton script de conformité des projets en mode « comparaison » et échoue s'il trouve une dérive.
