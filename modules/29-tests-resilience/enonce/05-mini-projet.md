# Module 29 — Palier 5 : Mini-projet

Le module a mis des tests à chaque étage de la plateforme, de la syntaxe des manifestes à la machine réelle, mesuré la tenue en charge de MédiAgenda, provoqué des pannes exprès et appris à s'en remettre, y compris quand l'outillage de test était lui-même en cause. Il reste à le **livrer** : une stratégie de tests appliquée partout, des tests nocturnes qui tournent seuls et restent verts, une journée de jeu dont les actions sont **closes**, aucune ressource de test qui traîne, et une documentation qui dit aux finaux ce qu'ils trouvent. C'est ce que Claire Morel présentera à l'auditeur comme « Résilience MédiSphère v1 », dernière brique avant les workbooks finaux.

---

### M29-E25 — Mini-projet : tests et résilience de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-3025** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette de la brique « tests et résilience » dans deux semaines, et c'est la dernière avant les finaux. Je veux un contrôle global sans rouge et rien de provisoire : plus de VM de test, plus d'expérience qui traîne, plus de panne ouverte. Pendant la revue : Sophie te demandera de prouver, **devant elle**, que le plan dangereux de référence est refusé par la CI de `plateforme/infra` et qu'aucune expérience ne peut viser la prod ; Karim ouvrira une MR qui casse un manifeste avec une CRD et regardera où elle s'arrête ; Julien voudra le résultat de la non-régression de cette nuit et son écart à la référence ; Nadia choisira une action de la journée de jeu et te demandera la preuve qu'elle est close. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider la stratégie de tests de la plateforme en un ensemble cohérent, piloté par le code, sans dette provisoire.
- Prouver ce qui a été construit : validation en CI partout, tests nocturnes verts, non-régression de performance, chaos encadré, journée de jeu suivie d'effets.
- Livrer l'état `resilience-v1` : documentation, étiquette, et ce que les workbooks finaux trouveront.

**Prérequis** : M29-E01 à M29-E24 (au minimum tous les `LAB`, `LIBRE` et `BF`) ; `plateforme-dev-v1` (M28-E25).
**Durée indicative** : 4 à 6 h, plus 30 min de revue.

**Contexte technique**
- Le contrôle global `lab/bin/check 29 25` rejoue les vérifications des exercices E02 à E10, E13, E14 et E19 à E22 (en sautant ce qui n'avait de sens que pendant l'exercice : traces de charge des 7 derniers jours, sondes Goss si l'essai a été retiré par décision écrite, objets de chaos supprimés depuis), puis vérifie la livraison : composant `validation` consommé, pipelines nocturnes verts, Chaos Mesh et son filtre d'espaces, aucune expérience active, aucune VM de test, pannes closes, documentation, étiquette. Il prend 3 à 5 minutes ; chaque partie a son titre.
- Les tickets d'actions de la journée de jeu (E16) sont des issues de `plateforme/resilience` étiquetées `journee-de-jeu`.

**État livré `resilience-v1`** — ce que les workbooks finaux trouveront. Rien ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Validation statique | composant **`validation`** de `plateforme/ci-templates` consommé (`@vX.Y.Z`) par `plateforme/k8s`, `plateforme/gitops`, `plateforme/infra` et `plateforme/ansible` ; kubeconform avec le paquet `schemas-crd` ; conftest sur les plans et les manifestes rendus ; aucun job de validation en `allow_failure` |
| Politiques | `plateforme/politiques/rego/{tofu,kubernetes}/` en Rego v1, tests `opa test` **et** test de non-régression sur le plan de référence (E19) |
| Tests nocturnes | pipelines planifiés **verts** : Testinfra (`plateforme/ansible`, toutes les VMs du socle), non-régression de performance (`plateforme/resilience`, référence à jour), nettoyeur Terratest (`plateforme/tofu-modules`) |
| Terratest | pipeline manuel de `vm-debian` vert ; **aucune** VM dans 2290-2299 ; aucun état orphelin |
| Charge | k6-operator 1.7 (Application `k6-operator`, espace `k6`), tableau `m29-charge-k6`, écriture distante restreinte aux exécuteurs de `k6` |
| Chaos | Chaos Mesh 2.8 (Application `chaos-mesh`, filtre d'espaces actif) ; espaces annotés : `mediagenda-recette`, `medinotif-recette`, `wb-essais` **seulement** ; aucune expérience active, aucun `Schedule` hors pause ; bibliothèque `plateforme/resilience/chaos/` ; politique réseau du port gRPC du daemon |
| Journée de jeu | au moins un rapport dans `docs/qualite/journees-de-jeu/` ; **toutes** ses actions closes (issues fermées avec la preuve) ou reportées par décision écrite (issue laissée ouverte, décision datée en commentaire, étiquette `reportee`) |
| Documentation | `docs/qualite/` : `strategie-tests.md` (mise à jour de ce qui a été livré depuis E12), ADR-0290, runbooks RB-290 à RB-297, rapport `rapports/*-resilience-donnees.md`, post-mortem INC-5623, `sous-le-capot-chaos-mesh.md`, note de livraison `livraison-resilience-v1.md` |
| Livraison | pipelines de `main` verts dans `plateforme/resilience`, `plateforme/politiques`, `plateforme/ci-templates` ; étiquette **`resilience-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Aucune VM de test, aucune expérience ni `Schedule` actif, aucun `TestRun` en cours ni pod de test oublié dans `k6` ou `wb-essais`, aucune panne `M29` ouverte, aucune dérive laissée sur les VMs du socle.
2. **Validation partout.** Les quatre projets consomment la même version du composant `validation` ; aucun job de validation autorisé à échouer ; le plan dangereux de référence et un manifeste invalide de référence sont refusés en CI (prouve-le par une MR de démonstration, fermée ensuite).
3. **Tests nocturnes verts** depuis au moins deux nuits : Testinfra sur le socle, non-régression de performance, nettoyeur Terratest (en simulation, sans rien trouver).
4. **Chaos encadré.** Le filtre d'espaces est actif ; aucun espace `*-prod` ni de plateforme n'est annoté ; RB-294 et RB-297 relus ; politique réseau du daemon en place.
5. **Journée de jeu suivie d'effets.** Chaque action de la journée de jeu est close avec sa preuve (MR, alerte, test) ou reportée par une décision écrite et datée (commentaire de l'issue, étiquette `reportee` ajoutée) ; au moins une action concerne la faiblesse de `/pret` révélée par les expériences (correctif proposé à l'équipe de Julien, ou décision écrite de l'équipe).
6. **Documentation et passage de relais.** Mets à jour `docs/qualite/strategie-tests.md` (M29-E12) avec ce qui a réellement été livré depuis : k6-operator et la non-régression nocturne (E14), les journées de jeu (E16), le test de non-régression des politiques sur le plan de référence (E19), le nettoyeur Terratest planifié (E21), les runbooks RB-290 à RB-297 ; corrige ce qui, dans la version d'E12, ne correspond plus à ce qui tourne. Puis tout ce qui est listé dans l'état livré, plus `livraison-resilience-v1.md` : ce que les finaux trouvent (F1 à F7 : où sont les tests, comment lancer une journée de jeu, ce qui n'est jamais fait en prod), ce qui reste à traiter (chaos en production, tests de contrat entre MédiAgenda et MédiDoc, non-régression de MédiDoc).
7. **Livraison.** Pipelines verts, étiquette `resilience-v1`.
8. **La revue.** Répète les quatre démonstrations **avant** la revue et chronomètre-les.

**Contraintes**
- Aucune expérience hors des espaces de recette et de `wb-essais` ; aucune modification de l'annotation des espaces pour la démonstration.
- Aucun secret dans un dépôt, un rapport, une issue ou un tableau de bord.
- Tout passe par le code (Argo CD, Ansible, OpenTofu, CI) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.

**Critères de réussite**
- [ ] `lab/bin/check 29 25` est entièrement vert.
- [ ] Démonstration de Sophie : le plan de référence est refusé par la CI de `plateforme/infra` ; une `NetworkChaos` visant `mediagenda-prod` est refusée ou ne sélectionne rien, et tu sais dire pourquoi.
- [ ] Démonstration de Karim : la MR cassée s'arrête à l'étage attendu de la pyramide, avec un message lisible.
- [ ] Démonstration de Julien : le résultat chiffré de la non-régression de la nuit, son écart à la référence, et la procédure pour mettre à jour la référence.
- [ ] Démonstration de Nadia : une action de journée de jeu tirée au hasard est close avec sa preuve.

**Vérification** : `lab/bin/check 29 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 29 25` dès le début : la liste des points rouges est ton plan de travail. Chaque partie porte le titre de l'exercice qu'elle rejoue.
</details>

<details><summary>Indice 2</summary>

Pour la démonstration de Sophie sur la prod, deux barrières se succèdent : la politique d'admission `medisphere-chaos-espaces` (M29-E09) refuse à la création une expérience dont `selector.namespaces` sort de la liste ; si elle laissait passer (liaison en `Warn`, par exemple), le filtre d'espaces de Chaos Mesh ne sélectionnerait aucun pod d'un espace non annoté. Essaie-le **avant** la revue, avec `--dry-run=server` d'abord, puis sache dire ce que tu verrais dans le statut de l'objet si la première barrière tombait.
</details>

**Pour aller plus loin** (facultatif) : mesure le coût réel de la brique (mémoire de Chaos Mesh et de k6-operator au repos, durée et ressources des pipelines nocturnes, minutes de recette dégradée par mois) et ajoute-le à l'ADR-0290 comme référence pour les finaux.
