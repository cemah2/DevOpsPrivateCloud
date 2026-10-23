# Final F1 — Phase 4 : Livrer et recetter — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Solutions de référence (il en existe d'autres). Fichiers dans [`fichiers/`](fichiers/) (même organisation que la phase 3) et, pour l'évolution de MédiAgenda, dans [`../ressources/S13/`](../ressources/S13/).

**Validé hors du lab** : l'évolution DEV-3113 contre le code de référence de `apps/mediagenda` (`git apply --check`, `uv run pytest` : 31 tests réussis, `ruff check`, `ruff format --check`) ; `bash -n` et `shellcheck -x` des checks ; YAML des fichiers.

**Points non testés en conditions réelles** : délais d'une livraison complète sur la plateforme reconstruite (caches de construction et d'images vides) ; durée du check S14 (il relance seize contrôles, dont les mini-projets des modules 24 à 29 : 20 à 40 minutes) ; lecture des accessoires de signature par l'API de Harbor pour une image désignée par condensé (`with_accessory=true`).

---

### F1-S13 — Première livraison en production

**Solution de référence**

*1. Le code.* Dans ta copie de `mediagenda/api`, sur une branche :
```
admin@adm01:~/src/mediagenda-api$ git switch -c feat/dev-3113
admin@adm01:~/src/mediagenda-api$ git apply --check ~/DevOpsPrivateCloud/finaux/F1-day0/ressources/S13/DEV-3113.patch && git apply ~/DevOpsPrivateCloud/finaux/F1-day0/ressources/S13/DEV-3113.patch
admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
admin@adm01:~/src/mediagenda-api$ git commit -am "feat(creneaux): nombre de créneaux libres (DEV-3113)" && git push -u origin HEAD
```
Si le correctif ne s'applique pas (ton `modeles.py` a évolué aux modules 23 et 27), reporte la classe de `modeles-Creneaux.extrait.py` et copie le fichier de tests. Le champ est **calculé** (`computed_field` de Pydantic) : il apparaît dans chaque réponse, n'est jamais lu en entrée, et une réponse mise en cache par la version précédente (sans le champ) est relue sans erreur, d'où la compatibilité N−1 que Julien demande (Valkey peut contenir des réponses de l'ancienne version pendant le canary).

*2. La chaîne*, dans l'ordre où elle casse typiquement après une reconstruction :

| Étape | Ce qui peut casser après le Day 0 | Où regarder | Correction |
|---|---|---|---|
| Pipeline de MR (`qualite`, `securite`, construction) | runner `k8s-par1` sans jeton, ou pods de jobs refusés (quotas, PSA de `ci-jobs`) | job « en attente » ou erreur de création de pod | ExternalSecret du runner (S09), espace `ci-jobs` appliqué (`espaces/`) |
| Construction | BuildKit sans certificat client (ClusterIssuer `buildkit-ca` neuve : les certificats des jobs sont réémis) | journal du job | rien si cert-manager a réémis ; sinon Certificate du client |
| Signature (`ci-signature`, runner protégé) | rôle JWT d'OpenBao intact (hors cluster), mais runner `k8s-par1-protege` absent ou sans jeton | job de signature « en attente » | `gitlab-runner-protege` (S08) |
| Promotion (`ci-promotion`) | jeton de projet expiré pendant la fenêtre ? | MR de promotion non ouverte | rotation du jeton (M25-E33) |
| Argo CD | webhook de GitLab vers Argo CD (`git01` → 10.10.41.10) : rien à refaire si la Gateway a la même adresse | délai de synchronisation de `dev`/`recette` | — |
| Kyverno | image non signée ou sans attestation SBOM : refus à l'admission | événements du ReplicaSet | la chaîne de signature, jamais une exception |
| Canary | `AnalysisRun` `Inconclusive` ou `Failed` faute de séries (Prometheus neuf, peu de trafic) | `kubectl argo rollouts get rollout mediagenda -n mediagenda-prod` | générer un trafic réaliste pendant l'analyse (k6 de `plateforme/resilience`, **sur la recette** d'abord) ; ne pas « promouvoir » à la main |

*3. Recette puis production.* La MR de promotion de `dev` est ouverte par `ci-promotion` ; `recette` puis `prod` par MR approuvée (Julien, Karim), image **par condensé** (`kustomize edit set image …@sha256:…`). Synchronisation manuelle de `mediagenda-prod` (SSO d'Argo CD, rôle `mediagenda-equipe` ou plateforme). Le Rollout fait son canary par le plugin Gateway API, les analyses Prometheus décident. Suivi :
```
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-prod --watch
admin@adm01:~$ curl -s https://mediagenda.apps.par1.medisphere.internal/sante
{"statut":"ok","version":"<X.Y.Z>"}
admin@adm01:~$ curl -s "https://mediagenda.apps.par1.medisphere.internal/api/v1/creneaux?date=$(date -d '+7 days' +%F)" | jq '{nombre, n: (.libres | length)}'
```
*4. SLO.* Tableau Pyrra `mediagenda-latence` et `mediagenda-disponibilite` pendant le canary et une heure après ; budget d'erreur consommé noté dans la chronologie (modèle : [`chronologie.extrait-S13.md`](fichiers/S13/medisphere/docs/day0/chronologie.extrait-S13.md)). `lab/bin/check F1 13`.

**Explications**

Une plateforme reconstruite qui « tourne » n'est pas une plateforme qui **livre** : la livraison traverse une douzaine d'identités et de confiances (jetons de runners, identité de la CI dans OpenBao, clé de signature, compte de promotion, identifiants de dépôts d'Argo CD, robot de Kyverno, analyses Prometheus) que la reconstruction a pu casser sans qu'aucun contrôle de santé ne le voie. Une petite évolution réelle est le meilleur test de bout en bout, et le plus tôt est le mieux : si quelque chose casse, la cause est encore fraîche.

**Alternatives**

- Livrer d'abord une version technique sans changement fonctionnel (`chore`, version corrective) : même test de chaîne, moins de risque ; mais Julien perd l'occasion de livrer, et le canary ne compare rien.
- `kubectl argo rollouts promote` pour accélérer une étape en pause manuelle : permis si le Rollout prévoit une pause manuelle, à noter ; jamais pour passer une analyse en échec.

**Pièges classiques**
- Livrer par étiquette mobile (`v1.4`) ou par étiquette sans condensé : Kyverno refuse (`verifyDigest`), et l'image servie n'est plus traçable.
- Modifier le Rollout à la main pour « débloquer » (`kubectl edit`, `kubectl scale`) : la prochaine synchronisation le défait, et le check le voit (gestionnaires de champs).
- Conclure à une régression de l'application devant une analyse `Inconclusive` alors que Prometheus n'a pas encore de séries.
- Oublier que semantic-release ne publie une **mineure** que pour un `feat` : un `fix` donnerait une corrective, un message libre aucune version.

**En production chez MédiSphère**

Le délai de bout en bout (fusion → 100 % du trafic) devient un indicateur DORA suivi ; une reconstruction ne doit pas le dégrader durablement (caches de construction et d'images à réchauffer). La première livraison après un Day 0 est systématique : c'est la dernière étape de RB-310 avant la recette.

---

### F1-S14 — Recette Day 0

**Solution de référence**

*1. Tri avant réparation.*
```
admin@adm01:~/DevOpsPrivateCloud$ for c in "29 25" "28 25" "27 25" "26 46" "25 46" "24 46" "F1 02" "F1 05" "F1 06" \
    "F1 07" "F1 08" "F1 09" "F1 10" "F1 11" "F1 12" "F1 13"; do echo "== $c"; lab/bin/check $c | grep -E '\[KO\]|Bilan'; done
admin@adm01:~$ /usr/local/bin/ms-verif-services --quiet; echo $?; /usr/local/bin/ms-verif-sauvegardes; echo $?
```
Trois tas :
- **perdu par la reconstruction** (à réparer par le code) : par exemple une ClusterRole `wb-checks-*` non réappliquée (un check « ne lit pas » quelque chose), un `ScheduledBackup` oublié, un tableau de bord manquant, une alerte `Watchdog` encore en silence sur `mon01`, une sauvegarde PBS des nouveaux nœuds jamais faite (la tâche `lab-nuit` les reprend : vérifier le lendemain) ;
- **légitimement changé** (à décider par écrit) : `serverName` des bases (`-day0`), dates de création des VMs et du cluster, identifiants de ressources ; un contrôle de module qui lit une de ces valeurs s'adapte par sa variable `WB_*` (raison dans `recette-day0.md`) ou par une correction du contrôle dans le workbook ;
- **déjà rouge avant** : à vérifier dans les comptes rendus des modules ; si c'est le cas, c'est une réserve, pas une régression.

*2. Ce qui doit être vrai de toute façon* : aucune panne marquée active (`ls ~/.local/state/workbook/pannes-actives/` vide), aucune VM 3100-3199 (`f1-usine-essai` détruite en S06), plus aucun Secret d'amorçage (`kubectl get secrets -A -l medisphere.internal/amorcage` vide), chaque `PolicyException` de Kyverno avec son `expiresAt`, `~/.kube/admin-k8s-par1.conf` supprimé, silence de `mon01` levé.

*3. Laisser passer une nuit* : les contrôles datés (sauvegardes PBS des nouveaux nœuds, pipelines planifiés, export nocturne des définitions RabbitMQ, analyse de conformité, non-régression de performance) ont besoin d'un cycle.

*4. Publier* `docs/day0/recette-day0.md` (modèle : [`recette-day0.md`](fichiers/S14/medisphere/docs/day0/recette-day0.md)) par MR approuvée par Claire, puis, **après** la fusion et un pipeline de `main` vert :
```
admin@adm01:~/medisphere$ git switch main && git pull --ff-only
admin@adm01:~/medisphere$ git tag -a day0-v1 -m "Day 0 : k8s-par1 reconstruit depuis le code (CHG-3107), recette PLAT-3114" && git push origin day0-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check F1 14
```

**Explications**

La recette d'une reconstruction n'est pas « tout est vert dans Argo CD » : c'est l'ensemble des exigences accumulées pendant des mois (sécurité, sauvegardes, supervision, données, livraison), exprimées par les contrôles des mini-projets, qui doivent tenir sur un cluster d'une semaine. Le check S14 les relance chacun dans son propre processus (mêmes variables de `lab/lab.env`) et ajoute ce qui n'appartient qu'à la clôture : rien d'ouvert, rien de provisoire, le document, l'étiquette posée après lui.

**Alternatives**

- Recetter par échantillonnage (les contrôles des modules 27 à 29 seulement) : plus court, mais les régressions les plus probables d'une reconstruction sont dans les couches basses (identité, secrets, sauvegardes : modules 24 à 26).
- Recette par une autre personne (Karim) : meilleure pratique, elle évite de « lire ce qu'on veut voir » ; sur le lab, tu joues ce rôle en suivant strictement la liste.

**Pièges classiques**
- Poser l'étiquette avant la publication du document de recette (le check vérifie que le document est **dans** l'étiquette).
- « Réparer » un contrôle en modifiant une variable `WB_*` sans raison écrite : c'est un contournement.
- Recetter le soir de la réouverture : la moitié des contrôles datés sont rouges pour une bonne raison.
- Oublier qu'un check rejoué peut lui-même avoir une panne marquée active d'un module (`lab/bin/break … --annuler` jamais lancé) : le contrôle « aucune panne active » le voit.

**En production chez MédiSphère**

La liste de recette est rejouée chaque semaine par un pipeline planifié de `plateforme/medisphere` (compte de lecture, `runner01`) : la recette devient une surveillance continue de l'état de livraison, et un rouge ouvre un ticket.

---

### F1-S15 — Rapport de reconstruction et runbook Day 0

**Solution de référence** (modèles complets, à remplir avec **tes** mesures)

- [`rapport-reconstruction.md`](fichiers/S15/medisphere/docs/day0/rapport-reconstruction.md) : résumé chiffré, tableau des durées comparées à la carte d'amorçage de S01 (écart en pourcentage et explication), dépendances circulaires prévues et rencontrées, **gestes manuels** avec statut (devenu code, assumé, dette avec responsable et échéance), ce qui a cassé et surpris (INC-5712), actions datées.
- [`RB-310-reconstruire-k8s-par1.md`](fichiers/S15/medisphere/docs/day0/runbooks/RB-310-reconstruire-k8s-par1.md) : quand l'utiliser (et les runbooks à préférer : RB-140, RB-141, RB-144, RB-275, restauration PBS), qui décide, préalables vérifiables, sept étapes appuyées sur `outils/day0/`, un point de contrôle par étape (commande et résultat attendu), le point de non-retour, le retour arrière avant et après lui, les durées de référence et la règle « au-delà de 1,5 × la durée de référence, c'est cassé ».
- [`ADR-0310-reduire-le-temps-de-reconstruction.md`](fichiers/S15/medisphere/docs/day0/adr/ADR-0310-reduire-le-temps-de-reconstruction.md) : quatre options chiffrées (statu quo outillé ; ESO avant la couche de base ; images préchargées et nœuds dorés ; récupérations en parallèle et `serverName` versionnés), un exemple de décision (B + D) et ce qu'on accepte de ne pas faire.

**Grille d'auto-évaluation** (ce que Sophie, Claire et Nadia regardent)

| Critère | Attendu | Manque fréquent |
|---|---|---|
| Chiffres | chaque phase mesurée, avec l'attente machine séparée ; estimation de S01 en regard ; écart expliqué | durées « environ », pas de comparaison à l'estimation |
| Données | nombre de rendez-vous au gel et après, méthode de comptage, messages, aucune perte (ou laquelle) | « tout est revenu » sans chiffre |
| Gestes manuels | liste complète issue de la chronologie, statut de chacun, dette avec responsable et date | gestes oubliés (clés SSH, CSR, Argo CD arrêté, admin.conf) |
| Sans recherche de coupable | faits, causes, décisions ; jamais « X a oublié » | ton accusateur dans le récit d'INC-5712 |
| Runbook exécutable | où lancer, quoi voir, quoi faire sinon ; un inconnu peut le suivre à 4 h du matin | commandes sans invite, sans résultat attendu |
| Retour arrière | avant et après le point de non-retour, conséquences pour les données | absent ou renvoyé « au cas par cas » |
| ADR | au moins deux options chiffrées **avec les mesures du Day 0**, décision, conséquences, ce qu'on ne fait pas | une seule option, ou des options sans coût |

**Explications**

Le rapport est la preuve que demandait Sophie au début du final : « on sait reconstruire, en tant de temps, avec ces limites ». Sa valeur tient à ce qu'il **compare** (estimation contre mesure) et à ce qu'il **avoue** (gestes manuels, surprises). Le runbook transforme une opération vécue par une personne en procédure pour une autre ; l'ADR transforme les constats en décision.

**Pièges classiques**
- Écrire le runbook comme un récit (« on a d'abord… ») au lieu d'une procédure à l'impératif avec points de contrôle.
- Recopier les durées de référence du corrigé au lieu des tiennes.
- Oublier les dates au format `AAAA-MM-JJ` dans les actions (le check les cherche ; l'auditeur aussi).
- Un ADR qui décide « tout » : une décision dit aussi ce qu'on ne fait pas, et pourquoi.

**En production chez MédiSphère**

Les trois documents entrent dans le dossier de preuves de l'audit HDS (continuité, sauvegarde, maîtrise des changements). RB-310 est rejoué à chaque exercice annuel et ses durées de référence mises à jour ; l'écart entre deux exercices mesure l'effet des décisions de l'ADR-0310.
