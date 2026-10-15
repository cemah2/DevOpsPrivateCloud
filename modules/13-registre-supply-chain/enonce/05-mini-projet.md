# Module 13 — Palier 5 : Mini-projet

Le module a installé, rempli, protégé, répliqué, sauvegardé, cassé et réparé le registre. Il reste à le **livrer** comme une brique du socle : toutes les images de MédiSphère dans Harbor, signées, accompagnées de leur SBOM et de leur provenance, construites par une chaîne qui refuse ce qui n'est pas conforme ; des caches qui évitent Docker Hub à chaque pipeline ; des dépendances tenues à jour par Renovate ; une politique de confiance écrite ; un registre qu'on sait restaurer. Le Harbor de test disparaît, les témoins et les comptes d'exercice aussi. C'est ce que Claire Morel présentera comme « registre MédiSphère v1 », et ce sur quoi le module 14 construira : les nœuds Kubernetes tireront tout de `reg01`.

---

### M13-E25 — Mini-projet : registre MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1425** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du registre v1 dans deux semaines, juste avant le démarrage de Kubernetes. Je veux un contrôle global sans un seul rouge et **rien de provisoire** : plus de `reg02`, plus de comptes ni de projets d'exercice, plus de flux temporaires.
> Pendant la revue : Sophie relira l'ADR-0130 et la politique de confiance, puis essaiera de tirer une image non signée de `medisphere` ; Julien poussera un correctif de MédiAgenda et suivra son pipeline jusqu'à l'image signée ; Nadia arrêtera Harbor pendant ta présentation et regardera ce que dit la sonde ; Karim choisira une image au hasard et te demandera d'où elle vient, ce qu'elle contient et qui l'a signée — en cinq minutes.

**Objectifs pédagogiques**
- Consolider la brique registre en un service du socle cohérent, piloté par le code, sans dette provisoire.
- Préparer le module 14 : robot de tirage des nœuds, caches publics prêts pour containerd, politique de confiance applicable à l'admission.
- Livrer l'état `registre-v1` : documentation, flux, sauvegardes, supervision, étiquette de version.

**Prérequis** : M13-E01 à M13-E24 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; le mini-projet M12-E46 (`conteneurs-v1`).
**Durée indicative** : 12 à 18 h, plus 30 min de revue.

**Contexte technique**
- `reg01` (1013, 10.10.20.18), Harbor 2.15 (dernière version corrective), `https://registry.par1.medisphere.internal` ; projets `medisphere`, `plateforme`, `bibliotheque`, `charts` (vide jusqu'au module 17) ; caches `dockerhub`, `quay`, `ghcr`, `k8s` ; robots `robot$medisphere+ci`, `robot$bibliotheque+ci`, `robot$plateforme+ci`, `robot$k8s-pull`, `robot$wb-checks`, `robot$renovate`, `robot$supervision` (PLAN §4.10 et E03, E09, E11, E16).
- Images applicatives attendues dans `medisphere` : `mediagenda-api`, `medidoc`, `medinotif`, `legacy-rdv`, chacune avec au moins une version `vX.Y.Z` publiée par la chaîne de livraison (gabarits `templates/supply-chain.yml`, E09, et `templates/verification.yml`, E14).
- Le contrôle global `lab/bin/check 13 25` vérifie Harbor et ses projets, les quatre images et leurs accessoires, les caches et leur usage par `runner02`, Renovate, la sauvegarde, la supervision, la documentation, et l'**absence** de `reg02`, des témoins et du compte `wb-pannes`. Il prend une à deux minutes.

**Travail demandé**
1. **Rien de provisoire.** `reg02` est détruite par OpenTofu (état `m13-registre` vide), son enregistrement DNS et ses flux temporaires retirés (Ansible et matrice documentaire), son endpoint et ses politiques de réplication retirés de `reg01` par le code, ses secrets retirés de Vault. Les témoins du palier 4 (projets `wb-sonde*`, robots `wb-sonde-*`, fichiers de `runner02`) et l'utilisateur `wb-pannes` sont supprimés ; aucune panne `M13` active ; aucun dépôt d'essai (`essai-*`) dans les projets. Écris dans `docs/registre/replication.md` ce qui remplacera `reg02` (réplication vers PAR2, finaux).
2. **Les images.** Les quatre applications sont construites par la chaîne de livraison (construction sans privilège, Trivy bloquant sur Critical corrigeable, SBOM, provenance, signature par digest, poussée par robot, étiquette immuable), et la dernière version `v*` de chacune est **signée**, porte une **attestation SBOM**, est **analysée** sans vulnérabilité critique ; les images de base viennent de `bibliotheque` ou des caches, épinglées par digest.
3. **Les politiques.** `medisphere` : privé, signature Cosign exigée, prévention des images Critical, analyse à la poussée, immuabilité `v*`, rétention et quota (E10). Le job `verifier-signature` du gabarit tourne dans les pipelines des quatre applications. Toute exception (liste blanche de CVE) est datée et rattachée à un ticket.
4. **Les caches.** `runner02` tire les images publiques **par les caches** (aucun tirage direct depuis Docker Hub, Quay, GHCR ou `registry.k8s.io` dans les pipelines) ; les caches contiennent ce qu'utilisent les pipelines ; la configuration pour containerd (`hosts.toml`, module 14) est écrite dans `docs/registre/caches.md`, prête à servir.
5. **Renovate.** Le pipeline planifié de `plateforme/renovate` réussit chaque nuit ; il a ouvert des MR sur les quatre applications ; la configuration partagée (`plateforme/renovate-config`) épingle les images par digest et limite la fusion automatique aux correctifs.
6. **Exploitation.** Sauvegarde nocturne vers `pbs01` (`par1/registre`) réussie, avec un test de restauration **réalisé pour cette livraison** (sur une VM jetable recréée par le code puis détruite, ou consigné depuis E15 s'il a moins de 30 jours) ; `ms-verif-registre` planifié et vert ; Harbor dans la dernière version corrective ; ramasse-miettes planifié ; RB-130 à RB-135 à jour.
7. **Préparer le module 14.** `robot$k8s-pull` existe (système, tirage seul sur `medisphere`, `plateforme`, `bibliotheque` et `charts` ; les caches sont publics, E03-E04), son secret est en Vault `critique` ; le flux VLAN 40 → `reg01` 443 est dans la matrice (PLAN §4.10) ; la politique de confiance dit ce que l'admission vérifiera au module 26.
8. **Documentation.** `docs/registre/` : `architecture.md` (composants, données, flux, ce qui se passe quand chaque composant tombe), `politiques.md` (E14), `replication.md`, `sauvegarde.md`, `caches.md`, ADR-0130 (E17), runbooks, `alertes/CS-2026-0412.md` (E18) ; inventaire NetBox (`reg01`, nom `registry`) et matrice des flux à jour ; registre des secrets complété (admin de Harbor, robots, clé Cosign, clé de chiffrement PBS : emplacements, jamais les valeurs).
9. **Livraison.** Tout est fusionné, les pipelines de `main` (`plateforme/ansible`, `plateforme/infra`, `plateforme/outils`, `plateforme/ci-templates`, `plateforme/renovate`, `plateforme/medisphere` et les quatre applications) sont verts, et l'étiquette **`registre-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (architecture, politique de confiance, ce qui n'est **pas** redondant : un seul registre, une seule clé, un seul site), puis les démonstrations de Sophie (tirage refusé), Julien (correctif jusqu'à l'image signée), Nadia (arrêt de Harbor et alerte) et Karim (traçabilité d'une image en cinq minutes).

**Contraintes**
- Aucun secret dans un dépôt, un journal de CI ou la documentation ; la clé privée Cosign n'existe qu'en Vault `critique` et en variable de CI protégée et masquée.
- Tout est créé par le code (OpenTofu, rôles, code de configuration de Harbor, gabarits de CI) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucune politique de `medisphere` n'est affaiblie pour faire passer une image : on corrige l'image.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 13 25` est entièrement vert.
- [ ] Les quatre démonstrations de la revue passent (tirage refusé avec le message de la politique ; image signée publiée par le pipeline de Julien ; alerte de la sonde dans les 5 minutes ; traçabilité complète d'une image tirée au hasard).
- [ ] La documentation dit ce qui n'est pas redondant et ce que les modules 14, 24, 25 et 26 devront traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 13 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 13 25` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 13 XX`) donnent le détail par brique ; `lab/bin/check 12 46` revérifie ce que le module 12 a livré.
</details>

<details><summary>Indice 2</summary>

Retire `reg02` dans le bon ordre : d'abord ce qui pointe vers elle (politique, endpoint sur `reg01`), ensuite les flux, enfin la VM et son nom. Dans l'autre sens, la réplication planifiée échouera chaque nuit et la sonde sera rouge, à raison.
</details>

<details><summary>Indice 3</summary>

Pour la démonstration de Karim, prépare la commande qui part d'une étiquette et donne : le digest, la signature vérifiée, le SBOM (composants), la provenance (dépôt, commit, pipeline), le résultat de l'analyse. C'est la même chaîne que E18, en une seule commande.
</details>

**Pour aller plus loin** (facultatif) : une démonstration « reconstruire `reg01` depuis le code et la sauvegarde » chronométrée sur une VM jetable ; un tableau de bord texte (préparé pour le module 21) des images en service, de leur âge et de leurs vulnérabilités.
