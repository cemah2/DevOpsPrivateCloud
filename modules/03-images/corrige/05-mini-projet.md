# Module 03 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M03-E25 — Mini-projet : catalogue d'images MédiSphère v1

**Solution**

Il n'y a pas « une » solution : il y a un catalogue qui passe ses contrôles et des équipes qui s'en servent sans toi. Les fichiers de référence sont répartis dans les exercices ; ce mini-projet les assemble.

| Élément | Fichiers de référence |
|---|---|
| Images de base Debian et Rocky (ISO, preseed, kickstart, préparation, variables) | [`M03-E05`](fichiers/M03-E05/images/), [`M03-E06`](fichiers/M03-E06/images/), [`M03-E07`](fichiers/M03-E07/images/), [`M03-E08`](fichiers/M03-E08/images/) |
| Image dorée Debian, contenu, manifeste, version, publication, `outils/pve.sh` | [`M03-E09`](fichiers/M03-E09/images/), [`M03-E10`](fichiers/M03-E10/images/) |
| Durcissement (Debian et RHEL), `docs/durcissement.md`, build Debian durci | [`M03-E13`](fichiers/M03-E13/images/) |
| Test complet (deux clones, JUnit, familles Debian et Rocky) | [`M03-E14`](fichiers/M03-E14/images/tests/tester-image.sh) |
| Pipeline (deux familles), installation de `runner01`, règles `gw01` | [`M03-E15`](fichiers/M03-E15/) |
| Rotation, RB-037 | [`M03-E16`](fichiers/M03-E16/) |
| ADR-0030 | [`M03-E17`](fichiers/M03-E17/ADR-0030-strategie-images.md) |
| **Image dorée Rocky** : `rocky10-gold/build.pkr.hcl`, `variables.pkr.hcl`, `scripts/gold-rocky10.sh`, `fichiers/dnf/automatic.conf` | [`M03-E25/images/`](fichiers/M03-E25/images/) |
| Catalogue `docs/socle/images.md`, RB-038 | [`M03-E25/medisphere/`](fichiers/M03-E25/medisphere/docs/socle/) |

**Démarche recommandée** (8 à 12 h, dont beaucoup d'attente)

1. **Assainir** (1 h) : `lab/bin/check 03 25`, puis les contrôles détaillés. KO typiques : une panne du palier 4 non close (`lab/bin/break 03 2X --annuler`), une VM 2036-2039 ou un template 9095 oublié, un template d'essai 9090/9091, la dette de E02 encore dans `.gitlab-ci.yml`, une version `current` de plus de 8 jours parce que la planification était inactive.
2. **La famille Rocky** (3 à 4 h) : par MR, `rocky10-gold/` (même structure que `debian13-gold/` : seules changent la source 9002, la plage 9030-9049, les étiquettes, le CPU **imposé par variable validée** et le script de contenu), `scripts/gold-rocky10.sh`, `fichiers/dnf/automatic.conf`. `durcir.sh` (E13) et `tester-image.sh` (E14) gèrent déjà les deux familles par un `case` sur `/etc/os-release` : pas de copie. Différences à traiter, et où :

   | Sujet | Debian 13 | Rocky Linux 10 |
   |---|---|---|
   | Paquets | `apt-get` | `dnf` |
   | Magasin de certificats | `/usr/local/share/ca-certificates/` + `update-ca-certificates` | `/etc/pki/ca-trust/source/anchors/` + `update-ca-trust extract` |
   | chrony | `chrony.service`, `/etc/chrony/chrony.conf` | `chronyd.service`, `/etc/chrony.conf` (+ `sourcedir` ajouté) |
   | Correctifs automatiques | `unattended-upgrades` (origine `-security`) | `dnf-automatic`, `upgrade_type = security`, `dnf-automatic.timer` |
   | Contrôle d'accès obligatoire | AppArmor (défaut) | SELinux *enforcing* : `restorecon` sur chaque fichier déposé |
   | `modprobe.d` | effet immédiat | aussi copié dans l'initramfs : `dracut -f --regenerate-all` |
   | CPU | `x86-64-v2-AES` | `x86-64-v3` minimum (validation de la variable) |
   | Réseau | netplan + networkd | NetworkManager (cloud-init le configure) |

   ⚠️ À vérifier sur ta version : le format de `/etc/dnf/automatic.conf` (dnf 4 sur Rocky 10 ; un passage à dnf 5 changerait le nom du service et de la configuration).
3. **La chaîne** (1 h + attente) : le pipeline de E15 prend en charge `rocky10-gold` dès que le dossier existe (`rules:exists`). Build manuel d'abord, puis une exécution planifiée complète (*Run pipeline schedule* pour ne pas attendre lundi), avec test et publication des deux familles, puis rotation.
4. **Le catalogue et l'exploitation** (2 h) : `docs/socle/images.md`, RB-038 (synthèse des pannes E19 à E22), ADR-0030 relu, inventaire (section « Templates » : VMID, nom, rôle, étiquettes), matrice des flux, registre des secrets (`wb-packer@pve!packer` : emplacement sur `adm01`, variables CI protégées et masquées, propriétaire, expiration, procédure de rotation de E02).
5. **La preuve d'usage** (30 min) : en suivant **uniquement** `images.md`, clone complet de chaque `current` en 2030 et 2031, connexion, nom, heure (`chronyc -n sources`), CA (`openssl verify`), durcissement (`sshd -T`), SELinux sur Rocky ; chaque écart entre la promesse et la réalité est corrigé dans l'image **ou** dans le document. Puis destruction.
6. **Hygiène** (30 min) :
   ```
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null
   admin@adm01:~$ ssh pve01 "qm list | awk 'NR>1 && ((\$1>=2030 && \$1<=2039) || (\$1>=9090 && \$1<=9099))'"
   admin@adm01:~/src/images$ gitleaks git --no-banner --redact .
   admin@adm01:~$ find ~/.config/workbook -type f ! -perm 600
   ```

**Grille d'évaluation de la revue** (Claire, Karim, Sophie, Julien, Nadia ; en auto-évaluation si tu travailles seul)

Barème sur 100. Seuil de recette : 70, **et** aucun critère éliminatoire.

*Critères éliminatoires* : contrôle global non vert ; un secret dans un dépôt, une image, des notes de template ou un journal CI ; une version `current` posée hors CI sans procédure de retrait d'urgence ; une identité (machine-id, clés d'hôte) partagée entre deux clones de test.

| # | Axe | Points | Insuffisant (0-40 %) | Attendu (60-80 %) | Excellent (100 %) |
|---|---|---|---|---|---|
| 1 | Images | 20 | une famille, ou Rocky copiée-collée de Debian | deux familles, contenu équivalent, différences explicites | logique commune factorisée, différences dans un seul `case`, manifeste complet |
| 2 | Qualité et tests | 20 | test minimal de E10 | test complet, deux clones, JUnit, test du test documenté | chaque promesse du catalogue a son contrôle ; chaque incident du palier 4 a ajouté le sien |
| 3 | Chaîne | 20 | builds lancés depuis un poste | pipeline planifié, sérialisé, publication après test, rotation | pré-vol, alerte sur absence de succès, artefacts d'audit conservés |
| 4 | Sécurité | 15 | durcissement non documenté | SEC-450 vérifié, exceptions justifiées, secrets inventoriés | mesure avant/après, revue avec la RSSI, droits du jeton discutés (pool unique) |
| 5 | Documentation | 15 | README du projet seul | catalogue, ADR, RB-037, RB-038, inventaire et flux à jour | Julien crée une VM de chaque famille avec la seule documentation, sans question |
| 6 | Présentation et défense | 10 | lecture des fichiers | 10 min structurées, démonstration réussie | limites, risques et dette assumés, préparation des modules 04-06 |

**Questions de revue typiques et éléments de réponse attendus**

| Question | Ce qu'une bonne réponse contient |
|---|---|
| (Sophie) « Le jeton de construction peut-il détruire `gw01` ? » | oui (`VM.Allocate` sur le pool `lab`, qui contient le socle) ; atténuations : variable protégée, masquée, runner dédié aux projets de la plateforme ; amélioration proposée : pool séparé pour les templates et les VMs de build (décision à porter dans PLAN.md) |
| (Julien) « Mon éditeur demande Rocky 10.1 précisément, pas 10.2. » | le catalogue suit la dernière mineure ; une image figée est une nouvelle famille (ADR) avec sa propre politique de correctifs, ou une VM durable créée depuis une version précise conservée (archivage avant rotation) |
| (Karim) « Pourquoi le test tourne-t-il deux fois dans le pipeline ? » | le job de test produit le rapport et bloque ; `publier-image.sh` rejoue le test parce que la règle « pas de `current` sans test » doit tenir aussi hors CI ; coût ~3 min assumé, ou option explicite à ajouter avec preuve du test (rapport du même pipeline) |
| (Nadia) « Le pipeline planifié n'a pas tourné depuis 10 jours : qui le voit ? » | le contrôle de fraîcheur de `current` (8 jours) ; alerte à mettre en place (module 21) ; cause probable : propriétaire de la planification parti ou bloqué → *Take ownership* |
| (Claire) « Qu'est-ce qui change pour ces images dans les trois prochains modules ? » | M04 : Molecule sur clones liés de `current`, rôles Ansible qui reprennent le durcissement pour le parc ; M05 : OpenTofu sélectionne par étiquettes, clones complets, référence enregistrée ; M06 : nouvelle racine step-ca dans `fichiers/ca/`, reconstruction des deux familles |

**Explications**

Un catalogue d'images devient un produit quand quelqu'un d'autre que son auteur peut **consommer** une image sans lui, et que la chaîne qui la produit tourne **sans** lui. Le contrôle global vérifie la forme (familles, `current`, fraîcheur, pipeline, documents, hygiène) ; la revue vérifie l'usage : Julien qui crée deux VMs avec la seule documentation est le test qui compte. La seconde famille est l'épreuve de la conception : si l'ajouter a demandé de copier des scripts, la logique n'était pas au bon endroit.

**Alternatives**
- Une seule famille (Debian) et une VM Rocky construite à la main pour l'éditeur : moins de maintenance, mais une VM hors chaîne de confiance, non testée, non reconstruite ; à éviter dès qu'elle est en production.
- Images de base construites aussi par la planification (mensuelle) : détecte plus tôt une rupture des ISO ou des miroirs, au prix de builds longs.

**Pièges classiques**
- Recopier `debian13-gold/` en changeant les noms et oublier le CPU, `restorecon` ou `dracut` : l'image Rocky se construit… et un clone ne démarre pas, ou SELinux bloque chrony.
- Publier la première image Rocky à la main « pour la démo ».
- Laisser une panne du palier 4 marquée active (réparée mais non close) : le contrôle global le voit.
- Un catalogue qui décrit les outils au lieu de dire comment consommer une image.
- Une documentation vraie le jour de la recette et fausse le lundi suivant : le registre des versions doit être mis à jour par la publication (piste : job CI qui ouvre une MR sur `plateforme/medisphere`).

**En production chez MédiSphère**
Le catalogue a un propriétaire (l'équipe Plateforme), une feuille de route (familles, fréquences), un engagement de service (une image corrigée publiée dans les 48 h d'une vulnérabilité critique), et ses indicateurs (âge de `current`, durée de build, temps de mise à disposition, taux d'échec des tests) sont suivis dans les tableaux de bord de la plateforme (module 21). Les images de conteneurs (module 13) suivent la même discipline : construction par la CI, tests, signature, rétention.
