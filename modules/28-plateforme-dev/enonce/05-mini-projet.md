# Module 28 — Palier 5 : Mini-projet

Le module a fait suivre la charge aux applications, partagé le cluster entre les équipes, ouvert un portail qui crée des services par MR, puis l'a cassé et réparé. Il reste à le **livrer** comme une brique de la plateforme : chaque application autoscalée comme l'ADR-0280 l'a décidé, chaque équipe dans un locataire défini en Git, un portail à jour dont le catalogue est complet et documenté, un chemin balisé éprouvé de bout en bout, rien de provisoire. C'est ce que Claire Morel présentera au comité comme « Plateforme développeurs v1 ».

---

### M28-E25 — Mini-projet : la plateforme développeurs de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2925** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette de la plateforme développeurs dans deux semaines. Je veux un contrôle global sans un seul rouge et **rien de provisoire** : plus de panne ouverte, plus de compte d'essai, plus d'espace d'essai. Pendant la revue : Julien créera devant nous un service fictif par le portail et nous montrera qu'il se construit, se déploie en dev et apparaît au catalogue avec sa documentation — puis tu le retireras proprement ; Nadia lancera une mini-campagne en recette et regardera MédiNotif se réveiller depuis zéro ; Sophie te demandera de rejouer trois essais d'isolation de ton choix avec le compte d'essai réactivé ; Karim relira les locataires et te demandera d'expliquer devant lui ce qui se passe si une équipe dépasse son budget. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider la plateforme développeurs en un ensemble cohérent, piloté par le code (Argo CD, MR), sans dette provisoire.
- Prouver ce qui a été construit : autoscaling, isolation, capacité, portail, chemin balisé.
- Livrer l'état `plateforme-dev-v1` : documentation, runbooks, étiquette de version, et ce que le M29 (tests et résilience) et les finaux trouveront.

**Prérequis** : M28-E01 à M28-E24 (au minimum tous les `LAB`, `LIBRE` et `BF`) ; `donnees-v1` (M27-E25).
**Durée indicative** : 4 à 6 h, plus 30 min de revue.

**Contexte technique**
- Le contrôle global `lab/bin/check 28 25` rejoue les vérifications clés des exercices E02 à E07, E10, E13 à E16 et E24, puis vérifie la livraison (Applications, essais retirés, pannes closes, documentation, étiquette). Il prend 3 à 5 minutes.
- Le service fictif de l'essai du chemin balisé s'appelle **`medidoc-chemin-balise`** (locataire `medidoc`) : il doit **ne plus exister** à la livraison (projets, MR ouvertes, Application, espace, entité du catalogue), et son essai doit être raconté dans `docs/plateforme-dev/chemin-balise-essai.md`.

**État livré `plateforme-dev-v1`** — ce que le M29 et les finaux trouveront. Rien ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Autoscaling | HPA `mediagenda` (recette, prod) ; `ScaledObject` `medinotif` en recette (minimum 0) et en prod (minimum ≥ 1), `Ready`, sans pause ; VPA en `Off` sur toutes les charges ; aucun VPA actif hors `wb-essais` ; alertes de KEDA chargées |
| Capacité | `medisphere-critique`, `-standard`, `-lot` (+ `-ci`) ; production en `critique` avec PDB ; budget global par locataire ; tableau « Capacité et locataires » ; rapport VPA mensuel en MR |
| Locataires | `mediagenda`, `medidoc`, `medinotif` dans `plateforme/k8s/locataires/`, `Ready`, gérés par l'Application `locataires` ; cloison réseau par locataire ; politiques `locataires-placement` et `locataires-pod-security` ; Capsule ≥ 0.15.0 |
| Portail | dernière version promue, deux réplicas, sauvegarde de `portail-db` < 26 h, métriques et alertes ; catalogue : chaque Component a un propriétaire valide et sa documentation TechDocs ; modèle `nouveau-service` fonctionnel |
| Essais | `vc-essai`, `medidoc-essai-isolation`, compte `essai-medidoc` (désactivé), service `medidoc-chemin-balise` : plus rien ; aucune panne `M28` ouverte |
| Documentation | `docs/plateforme-dev/` : `autoscaling.md`, `capacite.md`, `essais-isolation.md`, `portail-exploitation.md`, `sous-le-capot.md`, `chemin-balise-essai.md`, `etat-plateforme-dev-v1.md` (note de livraison), ADR-0280, runbooks RB-280 et RB-284 à RB-289 ; post-mortem INC-5523 |
| Livraison | MR fusionnées, étiquette **`plateforme-dev-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Essais retirés, pannes closes, compte d'essai désactivé, aucune politique ni objet posé à la main.
2. **Autoscaling conforme à l'ADR.** Chaque application et chaque environnement comme décidé, chiffres de `autoscaling.md` à jour.
3. **Locataires en Git.** Aucun écart entre Git et le cluster (Applications `locataires`, `capsule`, `politiques` synchronisées) ; essais d'isolation rejoués après la dernière modification.
4. **Portail à jour.** Version, sauvegarde, supervision ; catalogue complet (propriétaires, systèmes, documentation) ; le modèle crée un service qui se construit et se déploie en dev.
5. **Chemin balisé éprouvé.** Crée `medidoc-chemin-balise` par le portail, suis-le jusqu'au déploiement en dev et au catalogue, mesure le temps total, puis retire-le proprement (dans quel ordre, et pourquoi) ; raconte l'essai dans `chemin-balise-essai.md`.
6. **Note de livraison** `etat-plateforme-dev-v1.md` : ce que trouvent le M29 (classe `medisphere-lot` pour les essais de charge, espaces `wb-essais`, chaos jamais sur `*-prod`) et les finaux ; ce qui reste à traiter (classe de priorité de la plateforme, niveau PSA par défaut du cluster, migration des champs dépréciés de Capsule).
7. **Livraison.** Étiquette `plateforme-dev-v1`.
8. **La revue.** Répète les quatre démonstrations **avant** la revue et chronomètre-les.

**Contraintes**
- Tout passe par le code (MR, Argo CD) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un ticket ou un document : des **emplacements**, jamais des valeurs.
- Aucun essai sur la production.

**Critères de réussite**
- [ ] `lab/bin/check 28 25` est entièrement vert.
- [ ] Démonstration de Julien : service fictif créé, construit, déployé en dev, visible au catalogue avec sa documentation, puis retiré sans reste.
- [ ] Démonstration de Nadia : MédiNotif de recette passe de 0 à au moins 1 pod en moins d'une minute après la publication.
- [ ] Démonstration de Sophie : trois essais d'isolation rejoués, résultats identiques au rapport.
- [ ] Démonstration de Karim : le dépassement d'un budget est expliqué (moment du refus, message, objet qui le porte).

**Vérification** : `lab/bin/check 28 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 28 25` dès le début : la liste des points rouges est ton plan de travail. Chaque partie porte le titre de l'exercice qu'elle rejoue.
</details>

<details><summary>Indice 2</summary>

Pour retirer un service créé par le modèle, pense à l'ordre inverse de la création : ce qui consomme (Application, espace) avant ce qui est consommé (projets) ; et au catalogue, qui garde une entité tant que son emplacement est enregistré.
</details>

**Pour aller plus loin** (facultatif) : mesure la consommation réelle de la brique (mémoire et CPU de KEDA, VPA, Capsule, du portail et de sa base) et ajoute-la à l'ADR-0280 comme référence de dimensionnement pour les finaux.
