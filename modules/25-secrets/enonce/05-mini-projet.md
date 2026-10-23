# Module 25 — Palier 5 : Mini-projet

Le coffre existe, il est en grappe, il redémarre seul, il est sauvegardé, supervisé, durci, et tu sais le diagnostiquer quand il se ferme. Mais le registre de Sophie Laurent n'a pas encore bougé : tant qu'un seul secret applicatif vit encore dans un script, une variable de CI ou un Secret posé à la main, la question « qui a lu ce secret ? » n'a toujours pas de réponse complète. Il reste à **livrer** « les secrets de MédiSphère v1 » comme une brique de la plateforme : plus aucun secret applicatif hors du coffre, chaque exception écrite et justifiée, la preuve qu'on sait tourner un secret sans coupure **devant témoins**, et ce que le module 26 viendra consommer. C'est l'étiquette `secrets-v1` sur `plateforme/medisphere`.

---

### M25-E46 — Mini-projet : les secrets de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2646** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette des secrets v1 dans deux semaines. Je veux un contrôle global sans un seul rouge et **rien de provisoire** : aucune panne ouverte, aucune VM d'essai, aucun jeton racine vivant, aucun secret applicatif hors du coffre sauf ceux que tu auras inscrits comme amorçage avec une raison. Et je veux le voir marcher.
> Pendant la revue : **Sophie** te donne un secret « fuité » (elle choisira sur place parmi les secrets de la recette et de la prod) et tu le tournes **en direct, sans coupure**, en lui montrant ensuite dans l'audit qui l'a lu depuis une semaine ; **Karim** relit `plateforme/secrets` et demande un `tofu plan` vide ; **Nadia** veut savoir ce qui la réveille et ce qu'elle fait si le coffre se ferme à 3 h ; **Julien** vérifie qu'aucune équipe n'a plus de mot de passe durable dans ses variables de CI ni dans ses dépôts. Format habituel : 10 minutes de présentation, la démonstration, nos questions.

**Objectifs pédagogiques**
- Consolider le module en une brique cohérente, entièrement en code (OpenTofu, Ansible, Argo CD), sans dette provisoire.
- Prouver ce qui a été construit : inventaire à jour avec l'état de chaque secret, identités vérifiées partout, secrets courts là où c'est possible, rotation sans coupure, audit qui répond, sauvegarde restaurée, alertes, runbooks.
- Livrer l'état `secrets-v1` : documentation, étiquette, et ce que le module 26 et les finaux consommeront.

**Prérequis** : M25-E01 à M25-E45 (au minimum tous les `LAB`, `LIBRE`, `BF`, `REV`, `RED`, `Q` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Périmètre et adresses figés (PLAN §4.12) : OpenBao 2.7.1 sur `vault01-03` (VIP 10.10.20.200 `openbao.par1.medisphere.internal:8200`), `kms01` (seal `transit`), ESO 2.13 (espace `external-secrets`, ClusterSecretStore `openbao`, un SecretStore `openbao` par espace applicatif), moteurs `kv/`, `db-mediagenda/`, `transit/`, `pki-services/`, méthodes `oidc/`, `gitlab/`, `k8s-par1/`, `approle/`.
- Dépôts : `plateforme/secrets` (OpenTofu : politiques, méthodes, rôles, moteurs ; CI avec le test des politiques), `plateforme/ansible` (rôles `openbao`, `openbao_kms`, `openbao_instantane`, lookups), `plateforme/k8s` (couche de base Helmfile, `outils/`), `plateforme/gitops` (ExternalSecret de plateforme), dépôts de déploiement de MédiAgenda et MédiDoc (ExternalSecret et générateurs des applications), `plateforme/ci-templates` (composant `securite`), `plateforme/observabilite` (règles, tableau), `plateforme/medisphere` (documentation `docs/securite/secrets/`).
- **Amorçage** : ce qui doit exister **avant** le coffre, ou quand il est fermé, reste hors de lui (Vault Ansible `critique`, parts et clés de récupération, clés `age` de restauration, racine PKI hors ligne, identité initiale d'ESO, `admin.conf`, comptes de bris de glace). Chaque élément est inscrit à l'inventaire avec sa raison et sa garde.
- Promesses de modules antérieurs à tenir ici : les Secrets de la **couche de base** sous Helmfile (identités S3 de Velero et des sauvegardes CNPG, clés cephx de ceph-csi, clé TSIG et compte ACME de cert-manager et ExternalDNS) passent eux aussi par ESO, comme les Secrets de plateforme en M25-E13 ; celles que tu ne tiens pas sont écrites, avec leur raison, dans la fiche de livraison.
- Le contrôle global `lab/bin/check 25 46` vérifie, dans l'ordre : rien de provisoire, la grappe, les identités, l'absence de secrets hors du coffre qu'il sait voir, les secrets dynamiques, la PKI, la sauvegarde, la supervision, la documentation et l'étiquette. Il prend quelques minutes.

**État livré `secrets-v1`** — ce que le module 26, le bloc G et les finaux trouveront. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Coffre | Grappe Raft de trois nœuds (un actif, autopilot sain, tolérance ≥ 1), VIP sur le nœud actif, seal `transit` par `kms01` (descellé, jeton du seal **renouvelé**), unité durcie, TLS 1.3, audit déclaré identique sur les trois nœuds et acheminé vers Loki (`audit`) ; aucun jeton racine vivant ; trousseau tourné au moins une fois (E44) |
| Configuration en code | `plateforme/secrets` : `tofu plan` **vide** sur `main`, pipeline vert avec le test des politiques (E40) ; aucune dérive (politiques, groupes, rôles, PKI) |
| Identités | Personnes par OIDC (groupes externes) ; CI par JWT (`gitlab/`, `ref_protected`), **aucune variable de CI durable** contenant un secret dans les projets migrés ; pods par `k8s-par1` avec audience ; machines par AppRole (`secret_id` enveloppés, CIDR liés) |
| Secrets dans Kubernetes | Tous les Secrets de `secrets-k8s.conf` migrés en ExternalSecret (plateforme et applications), **couche de base comprise** ; `secrets-k8s.sh` **retiré** (seule la racine publique d'amorçage reste, par un autre moyen écrit) ; aucun ExternalSecret en erreur |
| Secrets courts | Identifiants PostgreSQL **dynamiques** pour MédiAgenda en recette **et** en prod (générateur `VaultDynamicSecret`, Reloader) ; certificats de service de 48 h par la PKI (`openbao-services`), CRL fraîche ; signature Cosign par `transit` |
| Rotation et réponse | `politique-rotation.md` et rotations planifiées (E33) ; RB-250 (fuite), RB-254 (rotation) éprouvés en démonstration |
| Sauvegarde et reprise | Instantanés horaires chiffrés dans `openbao-instantanes` (dernier < 2 h), restauration éprouvée avec RPO/RTO mesurés (RB-252) ; RB-251 (descellement), RB-253 (montée de version), RB-255 (coffre fermé) |
| Supervision | Règles `regles/secrets.yaml` chargées (scellé, sans leader, audit en échec, baux, certificats, instantanés, tolérance), essai quotidien de l'auto-descellement (E42), tableau `plateforme-openbao` |
| Documentation | `docs/securite/secrets/` : `inventaire-secrets.md` **avec l'état de chaque secret** (cible atteinte, ou amorçage justifié, ou reste à faire daté), ADR-0250 et ADR-0251, runbooks RB-250 à RB-255, `politique-rotation.md`, `analyses/sous-le-capot-openbao.md`, **`secrets-v1.md`** (fiche de livraison : architecture, couverture, limites assumées, ce que consomment le M26 et les finaux) ; matrice des flux à jour ; étiquette **`secrets-v1`** sur `plateforme/medisphere` |
| Pour le M26 | Clé **publique** Cosign de `transit/keys/cosign-medisphere` publiée dans `docs/registre/cosign.pub` (l'ancienne gardée en `cosign-m13.pub` ; Kyverno vérifiera les deux), secret de lecture Harbor de Kyverno dans `kv/plateforme/kyverno/harbor`, audit d'OpenBao dans Loki `audit` (Falco et l'auditeur s'y ajouteront) |

**Travail demandé**
1. **Rien de provisoire.** Aucune panne `M25` ouverte, aucune VM d'essai (`bao-essai` 2251, `bao-restauration` 2252), aucun flux temporaire vers `kms01`, aucun jeton racine vivant (grappe **et** `kms01`), aucun montage, rôle ou politique d'essai (`tofu/essais-m25.tf` retiré), aucun espace d'essai (`sealed-secrets`, `essai-csi`).
2. **Plus aucun secret applicatif hors du coffre.** Mets l'inventaire d'E02 à jour : pour chaque ligne, l'état atteint et la preuve (chemin du coffre, ExternalSecret, rôle dynamique) ; les amorçages avec leur raison et leur garde ; ce qui reste à faire, daté, avec le module qui le fera. Migre la couche de base. Retire `secrets-k8s.sh`.
3. **La CI n'a plus de secret durable.** Recense les variables de CI des projets de MédiAgenda, MédiDoc et de la plateforme : aucune ne contient un mot de passe, un jeton ou une clé que le coffre délivre désormais.
4. **Les secrets courts sont partout où c'est possible** : identifiants dynamiques en prod, certificats de service, signature par `transit`.
5. **La reprise est prouvée** : instantané récent, restauration mesurée, runbooks, alertes ; `kms01` et sa garde documentés.
6. **La démonstration de Sophie** (préparée, répétée) : un secret désigné sur place (statique de recette ou de prod, ou identifiants dynamiques) est tourné en direct, **sans coupure** de l'application, puis l'audit montre qui l'a lu depuis sept jours. Prépare un scénario par type de secret.
7. **Documentation et livraison.** `secrets-v1.md` (architecture, couverture, **limites assumées**, ce que consomment le M26 et les finaux, promesses non tenues avec leur raison), ADR à jour, runbooks, matrice des flux ; tout fusionné, pipelines de `main` verts, `tofu plan` vide, étiquette **`secrets-v1`**.
8. **La revue** : 10 minutes de présentation (architecture, choix et compromis, limites), la démonstration de Sophie, les questions de Karim, Nadia et Julien.

**Contraintes**
- Tout passe par le code ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un ticket, une capture, la documentation ou la présentation : des **emplacements**, jamais des valeurs ; pendant la démonstration, aucune valeur ne s'affiche à l'écran.
- On ne retire jamais un accès sans un accès de secours testé ; la démonstration ne coupe ni MédiAgenda ni MédiDoc.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 25 46` est entièrement vert.
- [ ] La démonstration de Sophie est réussie : secret tourné en direct, application sans coupure (requêtes continues pendant la rotation), ancienne valeur inutilisable, lectures des sept derniers jours montrées par l'audit.
- [ ] `inventaire-secrets.md` donne l'état de **chaque** secret ; aucun secret applicatif n'est hors du coffre sans être inscrit comme amorçage justifié ou reste daté.
- [ ] `secrets-v1.md` dit ce qui n'est **pas** couvert (et quel module ou final le traitera) ; la revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 25 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 25 46` dès le début : la liste des points rouges est ton plan de travail. `lab/bin/check 25 43` rejoue d'un coup les contrôles du palier 4, qui sont aussi des contrôles de santé du coffre.
</details>

<details><summary>Indice 2</summary>

Pour trouver ce qui reste hors du coffre, croise trois sources : les Secrets du cluster **sans** propriétaire ExternalSecret, Helm, CNPG ou cert-manager (étiquettes et `ownerReferences`), les variables de CI des groupes et projets (API de GitLab, en lecture), et l'inventaire d'E02 ligne par ligne. Ce qui n'apparaît dans aucune colonne « maintenant » est ton reste à faire.
</details>

<details><summary>Indice 3</summary>

Répète la démonstration pour chaque **type** de secret, car Sophie choisit sur place : un secret statique (KV → ESO → Reloader), un identifiant dynamique (révocation du bail, nouveau rôle PostgreSQL), un secret de client OIDC (Keycloak puis KV). Pour chaque scénario : la commande de rotation, la preuve que l'application n'a pas coupé, la preuve que l'ancienne valeur est refusée, la requête d'audit.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord Grafana « hygiène des secrets » (âge de la dernière version de chaque secret de `kv/` par rapport à sa période de rotation, baux actifs par rôle, certificats proches de l'échéance, lectures de production par identité) ; une revue trimestrielle automatique de l'inventaire (script qui signale les secrets dont la rotation est en retard), publiée dans `docs/securite/secrets/revues/`.
