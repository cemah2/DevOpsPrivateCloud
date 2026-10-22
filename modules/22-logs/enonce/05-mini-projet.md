# Module 22 — Journaux : palier 5 — Mini-projet

Le module a centralisé, structuré, cloisonné, protégé, cassé et réparé les journaux de MédiSphère. Il reste à les **livrer** comme une brique de la plateforme : tout le lab journalisé (pods, nœuds, audit de l'API, événements, VMs du socle), chaque équipe dans son locataire, des durées de conservation écrites et appliquées, aucune donnée de santé dans Loki, des alertes tirées des journaux, des accès maîtrisés, des essais retirés, et une documentation qui dit à l'astreinte comment s'en servir et aux modules suivants ce qu'ils trouvent. C'est ce que Claire Morel présentera au comité et à l'auditeur HDS comme « Journaux MédiSphère v1 ».

---

### M22-E25 — Mini-projet : les journaux de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2325** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette des journaux dans deux semaines. Je veux un contrôle global sans un seul rouge et **rien de provisoire** : plus d'essai Fluent Bit ni OpenSearch, plus de panne ouverte, plus de témoin qui traîne. Pendant la revue : Sophie choisira au hasard une heure d'hier et te demandera qui a fait quoi sur l'API à cette heure-là, puis vérifiera qu'aucun numéro de sécurité sociale n'est dans Loki et qu'un compte d'équipe ne voit pas l'audit ; Nadia arrêtera Alloy sur un travailleur pendant ta présentation et regardera combien de temps il faut pour qu'une alerte parte et ce qui manque ensuite ; Julien demandera les journaux d'une requête précise de MédiAgenda en recette à partir de son identifiant ; Karim relira `plateforme/observabilite` et te demandera d'ajouter **devant lui** une règle de rétention plus courte pour un flux d'essai, en expliquant chaque étape. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider la brique des journaux en un ensemble cohérent, piloté par le code (Argo CD, Ansible, OpenTofu), sans dette provisoire.
- Prouver ce qui a été construit : couverture de la collecte, cloisonnement, masquage, rétention, alertes, enquête.
- Livrer l'état `journaux-v1` : documentation, flux, runbooks, étiquette de version, et ce que le M23 (traces) et les blocs suivants trouveront.

**Prérequis** : M22-E01 à M22-E24 (au minimum tous les `LAB`, `LIBRE` et `BF`) ; `metriques-v1` (M21-E46).
**Durée indicative** : 4 à 6 h, plus 30 min de revue.

**Contexte technique**
- Ce que les exercices du module ont posé : Loki 3.7 (`journaux`, Application `loki`, compartiment `loki-k8s-par1`, Service 10.10.41.62), Alloy 1.21 (DaemonSet, Application `alloy`, rôle Ansible `alloy` sur les VMs), locataires `plateforme`, `mediagenda`, `medidoc`, `audit` (et `essai`), sources Grafana par locataire et organisation Sécurité, règles du *ruler*, politiques réseau, versionnage du compartiment, documentation `docs/observabilite/journaux/`.
- Le contrôle global `lab/bin/check 22 25` rejoue les vérifications clés des exercices E02, E03, E05 à E09, E13, E14 et E16, puis vérifie la livraison (Applications, essais retirés, pannes closes, rétentions, documentation, pipeline, étiquette). Il prend 3 à 5 minutes ; chaque partie a son titre.

**État livré `journaux-v1`** — ce que le M23 et les modules suivants trouveront. Rien ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Loki | 3.7.x (chart `grafana-community/loki` 19.0.x recopié et signé dans Harbor `charts/`), mode `Monolithic`, un réplica, schéma TSDB v13, compartiment `loki-k8s-par1` (versionné, versions non courantes expirées à 7 jours), Application `loki` `Synced/Healthy`, Service `loki-externe` 10.10.41.62:3100, politiques `loki-entree` et `loki-sortie` |
| Locataires | `plateforme` (14 j), `mediagenda` et `medidoc` (30 j, effacement possible), `audit` (1 an, jamais effaçable), `essai` (24 h) ; limites d'ingestion et de flux par locataire ; compactor actif |
| Collecte | Alloy sur les six nœuds (pods, journald, audit de l'API, événements), rôle `alloy` sur toutes les VMs du socle ; liste fermée d'étiquettes ; métadonnées structurées (`request_id`, prêtes pour `trace_id` au M23) ; masquage des données personnelles en dernière étape |
| Consultation | sources Grafana « Loki — plateforme / mediagenda / medidoc » (organisation principale) et « Loki — audit » (organisation Sécurité), déclarées par code ; `logcli` sur `adm01` |
| Alertes | règles du *ruler* par locataire (MédiAgenda, audit, plateforme) routées par `equipe` ; règles Prometheus de capacité de Loki ; alerte « Alloy absent d'un nœud » |
| Essais | `journaux-essai` et `opensearch-essai` supprimés, aucune Application, aucun PVC ni PV d'essai, aucun témoin de panne (`journal-temoin`) |
| Documentation | `docs/observabilite/journaux/` : `loki.md`, `politique-journaux.md` (sections 1 à 4), `performance.md`, `comparatif-collecteurs.md`, `comparatif-opensearch.md`, `sous-le-capot.md`, ADR-0220, runbooks RB-220 à RB-224 ; matrice des flux (socle et cluster) à jour ; journaux de diagnostic et post-mortem INC-4923 |
| Livraison | MR fusionnées, pipeline de `main` de `plateforme/observabilite` vert, étiquette **`journaux-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Essais retirés (espaces, Applications, volumes, entrées du miroir des charts devenues inutiles), aucune panne `M22` ouverte, aucun témoin ni compte de service de panne, aucune règle réseau provisoire.
2. **Tout le lab journalisé.** Chaque nœud, chaque VM du socle, chaque espace applicatif produit des lignes dans le bon locataire ; aucune étiquette hors de la liste fermée ; le journal d'audit et les événements arrivent.
3. **Données de santé.** Le masquage est vérifié avec le témoin de E09 (puis le témoin est retiré) ; aucune ligne correspondant aux motifs sur 24 h dans aucun locataire.
4. **Règles appliquées.** Rétentions, limites et droit d'effacement conformes à la politique ; une demande d'effacement d'essai traitée de bout en bout (statut `processed`) avant la revue ; le compactor tourne.
5. **Alertes éprouvées.** Une alerte de chaque locataire déclenchée volontairement avant la revue (par un moyen réversible) et reçue par la bonne équipe dans Mailpit ; l'alerte « Alloy absent d'un nœud » éprouvée.
6. **Accès.** Politiques réseau de `journaux` en place, l'audit invisible des comptes d'équipe, décision de transport et de sauvegarde écrite.
7. **Documentation et passage de relais.** Tout ce qui est listé dans l'état livré, plus une note de livraison qui dit au M23 ce qu'il trouve (où ajouter `trace_id`, comment Alloy recevra l'OTLP) et ce qui reste à traiter (authentification de Loki au M24, copie hors site de l'audit en F5, haute disponibilité de Loki).
8. **Livraison.** Pipelines verts, étiquette `journaux-v1`.
9. **La revue.** Répète les quatre démonstrations **avant** la revue et chronomètre-les.

**Contraintes**
- Aucune donnée détruite pour « faire propre » : ni objets du compartiment, ni journaux de journald ; les seules suppressions de journaux passent par l'API d'effacement, sur `essai`.
- Aucun secret dans un dépôt, un ticket, un post-mortem ou un tableau de bord : des **emplacements**, jamais des valeurs.
- Tout passe par le code (Argo CD, Ansible, OpenTofu) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.

**Critères de réussite**
- [ ] `lab/bin/check 22 25` est entièrement vert.
- [ ] Démonstration de Sophie : l'auteur d'un geste choisi au hasard est retrouvé en moins de 5 minutes depuis Grafana (organisation Sécurité) ; un compte d'équipe ne voit pas l'audit ; aucun motif de donnée de santé sur 24 h.
- [ ] Démonstration de Nadia : l'arrêt d'Alloy sur un travailleur déclenche une alerte en moins de 10 minutes ; après le retour, tu sais dire ce qui a été rattrapé et ce qui ne l'a pas été.
- [ ] Démonstration de Julien : les lignes d'une requête de MédiAgenda sont retrouvées à partir de son `request_id`, sans étiquette à forte cardinalité.
- [ ] Démonstration de Karim : la nouvelle règle de rétention d'un flux d'essai est expliquée étape par étape (MR, synchronisation, rechargement, compactor, délai de suppression) et vérifiée.

**Vérification** : `lab/bin/check 22 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 22 25` dès le début : la liste des points rouges est ton plan de travail. Chaque partie porte le titre de l'exercice qu'elle rejoue : reprends son corrigé si besoin.
</details>

<details><summary>Indice 2</summary>

Pour éprouver une alerte sans fabriquer de faux incident sur une application, utilise ce que les règles surveillent réellement (un échec d'authentification sur l'API pour l'audit, une rafale de réponses 5xx sur `mediagenda-dev`) et note l'heure : c'est aussi une preuve pour Sophie.
</details>

**Pour aller plus loin** : mesure la consommation réelle de la brique (mémoire et CPU de Loki et d'Alloy, volume quotidien par locataire, taille du compartiment à l'équilibre) et ajoute-la à l'ADR-0220 comme référence de dimensionnement pour les finaux.
