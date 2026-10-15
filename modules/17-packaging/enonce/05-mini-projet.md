# Module 17 — Palier 5 : Mini-projet

Le module a écrit, testé, publié, signé, livré, cassé et réparé. Il reste à le **livrer** comme une brique de la plateforme. MédiAgenda passe de dev à prod depuis **un seul artefact** signé, par des overlays relus en MR, sans état Helm pour l'application. La plateforme est décrite par Helmfile et ne dérive pas. Les pannes du palier 4 ont laissé leurs runbooks. Il ne reste aucune release d'essai. Ce mini-projet est ce que Claire Morel présentera comme « packaging MédiSphère v1 ». C'est aussi exactement ce qu'Argo CD consommera au module 20.

---

### M17-E25 — Mini-projet : packaging MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1825** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Revue du packaging v1 la semaine prochaine. Je veux un contrôle global sans un seul rouge, et **rien de provisoire** : plus de release Helm de banc d'essai en dev, plus de release d'essai dans `wb-essais`, plus de panne ouverte. MédiAgenda 1.1.0, validée en recette, passe en production pendant la revue, par une MR, sous les yeux du comité.
> Pendant la revue :
> - Karim fera une MR de test sur le chart et une autre sur l'overlay de prod qui ajoute un `images:` : il veut voir les deux pipelines refuser ;
> - Sophie relira l'ADR-0170 et le registre des secrets, et demandera la preuve que ce qui tourne en prod est signé ;
> - Nadia te demandera de débloquer une release qu'elle aura laissée en `pending-upgrade` ;
> - Julien veut une seule chose : que la prochaine version arrive en recette sans qu'il ait à te demander quoi que ce soit.

**Objectifs pédagogiques**
- Consolider le module en une chaîne cohérente : chart → artefact signé → rendu vérifié → overlays → cluster, et plateforme → Helmfile → cluster.
- Faire rentrer le dev dans la règle de l'ADR-0170 sans interruption ni perte de données.
- Livrer l'état `packaging-v1` : documentation, runbooks, étiquette.

**Prérequis** : M17-E01 à M17-E24 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; le mini-projet M16-E46 (`k8s-stockage-v1`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Projets :
  - `mediagenda/chart` (pipeline E13), `mediagenda/deploiement` (overlays, `chart.env`, `outils/rendre-base.sh`, garde-fou E21) ;
  - `plateforme/k8s` (`helmfile.yaml`, `releases/`, `charts/emetteurs`, `outils/`) ;
  - `plateforme/medisphere` (`docs/kubernetes/packaging/`).
- Environnements :
  - `mediagenda-dev`, aujourd'hui une release Helm, à faire passer sous l'overlay `dev` ;
  - `mediagenda-recette` (overlay ; base PostgreSQL et Valkey du M16) ;
  - `mediagenda-prod` (overlay ; components `dependances`, `haute-disponibilite`, `livraison`), publiée en `mediagenda.apps.par1.medisphere.internal`.
- La base de données du dev (`mediagenda-db`, créée par `ressources/E03-…`, reprise par la release Helm en E06, puis décrite par le component `dependances`) contient des données jetables. Valkey, lui, passe du sous-chart (`mediagenda-valkey`) au StatefulSet `valkey` du component. Celle de la prod est **à protéger** dès maintenant, comme si elle portait des données de santé.
- Le contrôle global `lab/bin/check 17 25` vérifie :
  - le chart et son pipeline ;
  - les trois environnements (rendu d'un chart publié et signé, version, variable d'environnement, aucun geste manuel, aucune release Helm applicative, `kubectl diff --server-side` vide) ;
  - la haute disponibilité de la prod ;
  - la plateforme (`helmfile -e par1 diff` vide, aucune release en échec ou en attente) ;
  - la documentation et l'étiquette.

  Il prend quelques minutes.

**Travail demandé**
1. **Rien de provisoire.**
   - Aucune panne `M17` active.
   - Aucune release Helm dans `wb-essais`, quel que soit le pilote de stockage.
   - Les branches locales `lucas/*` sont fusionnées par MR ou supprimées, avec la raison écrite dans le journal.
2. **Le dev rentre dans la règle.** `mediagenda-dev` passe de la release Helm `mediagenda` à l'overlay `dev`, **sans supprimer** le Deployment, la base ni le Service :
   - plus aucune release Helm `mediagenda` dans l'espace ;
   - plus aucun champ des objets possédé par le gestionnaire `helm` ;
   - plus d'annotations `meta.helm.sh/*` sur les objets repris ;
   - les objets que l'overlay ne décrit pas sont supprimés.

   Écris la procédure dans `docs/kubernetes/packaging/runbooks/` : c'est celle que suivra MédiDoc.
3. **La prod reçoit 1.1.0** par une MR sur `overlays/prod/livraison.yaml` :
   - même chart, même digest que la recette ;
   - garde-fou de livraison vert ;
   - sauvegarde de la base de prod faite et vérifiée avant ;
   - plan de retour arrière dans la MR.
   La prod tourne trois réplicas répartis, avec un budget de perturbation à 2.
4. **Les pipelines sont la seule voie.**
   - `mediagenda/chart` : MR → contrôles ; étiquette → paquet, poussée, signature.
   - `mediagenda/deploiement` : MR → rendu vérifié (`rendre-base.sh --verifier`), garde-fou de livraison, diff.
   - `plateforme/k8s` : MR → au moins `helmfile -e par1 lint` (ou `template`) et l'audit des valeurs (E15).

   Les trois pipelines de `main` sont verts.
5. **La plateforme.** `helmfile -e par1 diff` est vide. Aucune release en `failed` ni `pending-*`. Le tableau des versions (E16) est à jour dans `docs/kubernetes/packaging/`.
6. **Documentation** dans `docs/kubernetes/packaging/` de `plateforme/medisphere` :
   - `architecture.md` : le chemin d'un changement de bout en bout, du commit au pod, pour l'application et pour la plateforme ; ce qui est signé, vérifié, par qui et où ; ce qui n'est **pas** encore automatique et le module qui le traitera (M19, M20, M25, M26) ;
   - ADR-0170 (E17), le registre des secrets (E15), `derive.md` (E14) ;
   - RB-170, RB-171, RB-172 et la procédure du point 2.
7. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, et l'étiquette **`packaging-v1`** est posée sur `plateforme/medisphere`.
8. **La revue** : 10 minutes de présentation, puis les démonstrations de Karim (deux MR refusées), de Sophie (preuve de signature de ce qui tourne en prod) et de Nadia (release bloquée débloquée avec RB-170).

**Contraintes**
- Aucune interruption de service en recette ni en prod pendant le mini-projet. Pour le dev, tolérée, mais pas de perte de la base.
- Aucun `helm uninstall` de la release du dev qui supprimerait ses objets. Aucun objet recréé quand il peut être repris.
- Aucun secret dans un dépôt, une valeur Helm ou un journal de CI.
- Tout changement passe par une MR relue. Une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 17 25` est entièrement vert.
- [ ] Les deux MR de test de Karim ont un pipeline rouge pour la bonne raison (lien dans la présentation).
- [ ] La preuve de Sophie tient en trois commandes : le digest du chart rendu en prod (`chart.env`), sa vérification Cosign, et les digests d'image des pods de prod comparés à l'image signée.
- [ ] La release de Nadia est débloquée en moins de 15 minutes en suivant RB-170, sans perte d'historique.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 17 25`

<details><summary>Indice 1</summary>

Pour faire oublier une release à Helm sans toucher à ses objets, demande-toi où Helm range ce qu'il sait de la release (M17-E23). Pour que `kubectl` devienne le seul propriétaire des champs, relis M17-E14 et M17-E22 : forcer une fois, puis vérifier qu'aucun autre gestionnaire ne copossède les champs.
</details>

<details><summary>Indice 2</summary>

Avant la reprise du dev, compare ce que l'overlay `dev` rendra et ce qui tourne (`kubectl diff --server-side`), objet par objet. Le hook de migration, sa politique réseau et le pod de `helm test` de la release n'existent pas dans l'overlay. La base fournie en E03 n'a peut-être pas la même spécification que celle du component `dependances` : un changement de spécification d'un `Cluster` CloudNativePG n'est pas anodin.
</details>
