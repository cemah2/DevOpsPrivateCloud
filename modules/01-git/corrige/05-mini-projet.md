# Module 01 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M01-E47 — Mini-projet : la forge MédiSphère

**Solution**

Il n'y a pas « une » solution : il y a une forge saine et un dossier qui permet à quelqu'un d'autre de l'exploiter. Les pièces fournies en exemple :

| Fichier | Ce qu'il illustre |
|---|---|
| [`fichiers/M01-E47/forge.md`](fichiers/M01-E47/forge.md) | fiche de service : engagement, composants, dépendances, accès (dont secours), règles, sauvegarde, exploitation, **risques connus** |
| [`fichiers/M01-E47/RB-013-forge-en-panne.md`](fichiers/M01-E47/RB-013-forge-en-panne.md) | runbook d'incident par symptôme, issu des pannes E36 à E43 (complète RB-012, sonde et diagnostic de M01-E30) |
| [`fichiers/M01-E47/conformite-plateforme.sh`](fichiers/M01-E47/conformite-plateforme.sh) | règles uniformes : mode `--verifier` (comparaison, code 1 si dérive) et `--appliquer` (idempotent), en s'appuyant sur le script de M01-E11 |
| [`fichiers/M01-E43/triage-forge.sh`](fichiers/M01-E43/triage-forge.sh) | triage d'incident (une ligne par porte de la forge), à ranger dans `forge/outils/` |
| [`fichiers/M01-E04/docs-socle-extraits.md`](fichiers/M01-E04/docs-socle-extraits.md) | lignes d'inventaire et de matrice des flux pour `git01` (à compléter avec `runner01` de M01-E23 et le flux 8007 de M01-E28) |
| [`fichiers/M01-E28/RB-010-restaurer-gitlab.md`](fichiers/M01-E28/RB-010-restaurer-gitlab.md), [`RB-011`](fichiers/M01-E29/RB-011-mettre-a-jour-gitlab.md), [`RB-012`](fichiers/M01-E30/RB-012-diagnostiquer-la-forge.md) | runbooks de restauration, de mise à jour et de diagnostic (M01-E28 à E30) |
| [`fichiers/M01-E33/ADR-0010-organisation-des-depots.md`](fichiers/M01-E33/ADR-0010-organisation-des-depots.md) | ADR du module |
| [`fichiers/M01-E43/post-mortem-exemple.md`](fichiers/M01-E43/post-mortem-exemple.md) | post-mortem INC-2788 |
| [`fichiers/M01-E22/CONTRIBUTING.md`](fichiers/M01-E22/CONTRIBUTING.md) | règles de contribution |

**Démarche recommandée** (8 à 12 h) :

1. **Assainir d'abord** (1 à 2 h). `lab/bin/check 01 47`, puis chaque KO à la racine. KO typiques à ce stade :
   - une panne du palier 4 encore marquée active : si tu l'as réparée, clos-la par `lab/bin/break 01 XX --annuler` (sur un lab réparé, l'annulation ne défait pas ta correction : elle retire le marqueur et les sauvegardes) ; si elle est encore là, répare-la d'abord ;
   - la VM 2010 `git-restore` oubliée après M01-E28 (`qm destroy 2010 --purge` sur `pve01`, après avoir vérifié qu'il s'agit bien d'elle : `qm config 2010 | grep name`) ;
   - un dernier pipeline de `main` rouge sur `plateforme/ci-templates` (job jamais relancé après une mise à jour) ;
   - `formation/legacy-rdv-brut` de M01-E45 non supprimé (pas un KO du contrôle global, mais Sophie le trouvera) ;
   - des jetons de test encore actifs (jetons d'emprunt d'identité créés par les scripts, jetons personnels « pour essayer ») : **Admin > Users > <utilisateur> > Impersonation tokens**, **User settings > Access tokens**.
2. **Règles uniformes** (1 h). `forge/outils/conformite-plateforme.sh --verifier` montre les écarts entre projets (on en trouve presque toujours : un projet créé avant E24 sans « pipeline obligatoire », une protection d'étiquettes oubliée sur `ci-templates`). `--appliquer`, puis `--verifier` doit sortir avec 0. Le script et celui de M01-E11 sont versionnés dans `forge/outils/` de `plateforme/medisphere`.
3. **Restauration** (1 à 2 h). Rejoue RB-010 sur la VM 2010 **pour cette livraison**, chronomètre chaque étape, consigne en tête de la section GitLab de `tests/restauration.md`, détruis la VM. Le RTO mesuré alimente `forge.md`.
4. **Documentation** (3 h). `forge.md` à partir de la réalité (sorties de `gitlab-rake gitlab:env:info`, `qm config 1004`, `qm config 1007`, API) ; inventaire et matrice des flux confrontés à `nft list ruleset` sur `gw01` (règles commentées de M01-E28) ; RB-013 à partir de tes journaux du palier 4 ; relecture de RB-010, RB-011, RB-012, ADR-0010.
5. **Secrets** (30 min). Pour chaque projet de `plateforme` :
   ```
   admin@adm01:~$ for p in medisphere ci-templates; do
                    git clone -q --mirror git@git01.par1.medisphere.internal:plateforme/$p.git /tmp/scan-$p.git
                    gitleaks git --no-banner --redact /tmp/scan-$p.git && echo "$p : aucun secret"
                  done; rm -rf /tmp/scan-*.git
   ```
   Un clone miroir contient toutes les références (branches, étiquettes, références de MR `refs/merge-requests/*`) : c'est l'historique **complet** que GitLab sert. Vérifie avec `gitleaks git --help` les options de ta version (sélection des journaux, `--log-opts`). `--redact` évite d'afficher un secret trouvé dans ton terminal.
6. **Livraison** (30 min). Dernière MR fusionnée, pipeline vert ; puis, sur `main` à jour :
   ```
   admin@adm01:~/medisphere$ git switch main && git pull --ff-only
   admin@adm01:~/medisphere$ git tag -s forge-v1 -m "Forge MédiSphère v1 — recette AAAA-MM-JJ"
   admin@adm01:~/medisphere$ git tag -v forge-v1            # vérification de la signature SSH (allowedSignersFile, M01-E27)
   admin@adm01:~/medisphere$ git push origin forge-v1
   ```
   `forge-v1` ne correspond pas au motif `v*` des étiquettes protégées ni au `tagFormat` de semantic-release (`v${version}`) : elle ne perturbe pas les versions automatiques. Si tu veux la protéger aussi, ajoute une protection `forge-*` (création : Maintainers).
7. **Relecture croisée** (30 min) : lis le dossier comme un nouvel arrivant ; chaque fois que tu dois deviner, il manque une phrase.

> ⚠️ **Attention** : si le balayage trouve un secret dans l'historique, la procédure est celle de M01-E17 (révocation **d'abord**, réécriture de l'historique ensuite, purge côté GitLab, communication). Ne pose pas `forge-v1` avant : une étiquette sur un historique qui va être réécrit devient fausse.

**Grille d'évaluation de la revue** (Claire Morel ; à utiliser en auto-évaluation si tu travailles seul)

Barème sur 100. Seuil de recette : 70, **et** aucun critère éliminatoire.

*Critères éliminatoires* : contrôle global non vert ; secret présent dans l'historique d'un projet de `plateforme` ; aucune restauration testée pour cette livraison ; jeton sans date d'expiration ; poussée directe possible sur une branche `main` de `plateforme`.

| # | Axe | Points | Insuffisant (0-40 %) | Attendu (60-80 %) | Excellent (100 %) |
|---|---|---|---|---|---|
| 1 | Forge saine et hygiène | 10 | KO corrigés à chaud, sans cause | contrôle vert, causes des KO expliquées | idem + jetons et projets temporaires recensés et retirés |
| 2 | Règles uniformes | 15 | réglages cliqués projet par projet | script versionné, idempotent, appliqué à tous les projets | idem + mode comparaison démontré en revue, planifié en CI |
| 3 | CI et versions | 10 | release manuelle ou cassée | releases automatiques sur les deux projets, notes lisibles | idem + gabarits figés (`ref: v1`) et procédure de montée de version des gabarits |
| 4 | Sauvegarde et restauration | 15 | « la sauvegarde tourne » | restauration de cette livraison, feuille de temps, RTO, RPO | idem + écarts et actions, durée comparée à l'engagement de `forge.md` |
| 5 | Fiche de service | 10 | description technique seule | engagement, dépendances, accès de secours, risques | idem + chaque risque a un traitement et une échéance |
| 6 | Inventaire et flux | 10 | liste d'hôtes | chaque flux relié à sa règle, jetons avec emplacement et expiration | idem + rapprochement matrice/règles démontré |
| 7 | Runbooks | 15 | procédures narratives | RB-010 à RB-013 au format de l'équipe, testés | idem + RB-013 rejoué par quelqu'un d'autre (ou en revue sur une panne tirée au hasard) |
| 8 | Présentation et défense | 15 | lecture du dossier | 10 min structurées, démonstration réussie | idem + limites assumées (CE, mémoire, absence de HA), prochaines étapes reliées aux modules suivants |

**Démonstrations que Claire peut demander** (une seule, tirée sur place) :
- injecter une panne du palier 4 (`lab/bin/break 01 3X`, variante tirée) et la résoudre avec RB-013 ;
- montrer qu'un push direct sur `main` est refusé, puis qu'une MR non conforme (message hors Conventional Commits) est bloquée par pre-commit, par le hook serveur **et** par la CI ;
- lancer `conformite-plateforme.sh --verifier` après qu'elle a modifié un réglage d'un projet dans l'interface ;
- retrouver une archive de sauvegarde dans PBS et dire combien de temps prendrait une restauration ;
- renouveler le jeton `bot-release` sans interrompre les releases.

**Questions de revue typiques**

| Question | Ce qu'une bonne réponse contient |
|---|---|
| « Si `git01` tombe maintenant, combien de temps sans forge ? » | restauration de VM depuis `pbs-par2` (le plus rapide si la sauvegarde de la nuit est bonne), sinon RB-010 avec le RTO mesuré ; ce qui est perdu depuis la dernière sauvegarde (RPO) ; les postes ont encore leurs clones |
| « Qu'est-ce qui empêche quelqu'un de fusionner sans relecture ? » | en CE : rien d'absolu (pas d'approbations obligatoires, Premium) ; discussions résolues + pipeline obligatoire + protection de `main` + hooks ; décision consignée (ADR) ; contrôle *a posteriori* (audit) |
| « Pourquoi un seul runner ? » | budget mémoire (PLAN §3.3), charge actuelle faible ; risque assumé et documenté ; runners Kubernetes au M19 |
| « Où sont les jetons et quand expirent-ils ? » | inventaire : emplacement, portée, expiration de chaque jeton (checks, administration, `bot-release` par projet, runner) ; procédure de rotation |
| « Que se passe-t-il au M06 pour les certificats ? » | remplacement de la CA provisoire par step-ca : nouveau certificat de `git01`, nouvelle racine sur `adm01`, `git01`, `runner01` et dans `NODE_EXTRA_CA_CERTS` (le gabarit pointe déjà sur le magasin du système) |

**Explications**

Le contrôle global vérifie la **présence** et quelques marqueurs ; la revue vérifie la **justesse** et l'**utilité**. Deux idées structurent ce mini-projet. D'abord, les règles d'une forge doivent être du code : un réglage cliqué dérive (on l'a vu au palier 4), un réglage scripté se vérifie et se rejoue. Ensuite, la forge est maintenant une dépendance de tout le reste : sa fiche de service, son RTO mesuré et son runbook d'incident sont aussi importants que ses fonctionnalités.

**Alternatives**
- Réglages de GitLab en code : provider GitLab pour OpenTofu (module 05) plutôt qu'un script ; ou l'outil communautaire `gitlabform`. Le script du module reste un bon premier pas, lisible et sans dépendance.
- Fiche de service : format libre, ou un catalogue de services (Backstage au module 28).

**Pièges classiques**
- Documenter la forge **voulue** au lieu de la forge **réelle** (réglages divergents entre projets).
- Un test de restauration ancien présenté comme preuve.
- Oublier les références de MR (`refs/merge-requests/*`) dans le balayage des secrets : un secret poussé sur une branche supprimée reste servi par la forge.
- Poser `forge-v1` avant la dernière fusion, ou sur un clone pas à jour.
- Laisser des jetons d'exercice actifs (emprunt d'identité, jetons personnels de test).

**En production chez MédiSphère**

La forge v1 devient le point de passage obligé : à partir du module 02, chaque projet (`plateforme/outils`, `images`, `ansible`, `tofu-modules`, `infra`) est créé puis mis en conformité par `conformite-plateforme.sh`, inclut `plateforme/ci-templates`, et publie ses versions automatiquement. `git01` sera repris par Ansible au M04 et ses réglages GitLab par OpenTofu au M05 ; ses certificats par step-ca au M06 ; sa supervision rejoindra Prometheus au M21.
