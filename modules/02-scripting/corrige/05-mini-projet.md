# Module 02 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M02-E46 — Mini-projet : outillage MédiSphère v1

**Solution**

Il n'y a pas « une » solution : il y a un projet qui passe ses contrôles et une équipe qui peut s'en servir sans toi. Les fichiers de référence sont répartis dans les exercices ; ce mini-projet les assemble.

| Élément | Fichiers de référence |
|---|---|
| Projet complet en fin de palier 2 (bibliothèque, `ms-snapshot`, `medictl`, tests, Taskfile, Makefile) | [`fichiers/M02-E20/outils/`](fichiers/M02-E20/outils/) |
| CI (lint, tests, rapports, couverture, construction) et publication du paquet | [`fichiers/M02-E24/`](fichiers/M02-E24/), [`fichiers/M02-E25/`](fichiers/M02-E25/) |
| Contrôle des sauvegardes, alerte, unités systemd | [`fichiers/M02-E26/`](fichiers/M02-E26/) |
| `ms-snapshot` idempotent, `ms-etat-hotes`, `ms-diag`, `ms-attendre` | [`M02-E27`](fichiers/M02-E27/), [`M02-E28`](fichiers/M02-E28/), [`M02-E29`](fichiers/M02-E29/), [`M02-E30`](fichiers/M02-E30/) |
| README, ADR-0020 | [`fichiers/M02-E31/README.md`](fichiers/M02-E31/README.md), [`fichiers/M02-E32/`](fichiers/M02-E32/) |
| Scripts corrigés du palier 4 et leurs tests | [`M02-E37`](fichiers/M02-E37/), [`M02-E39`](fichiers/M02-E39/), [`M02-E40`](fichiers/M02-E40/), chien de garde [`M02-E41`](fichiers/M02-E41/) |
| Spécification exécutable de Bash | [`fichiers/M02-E44/`](fichiers/M02-E44/) |
| Guide d'astreinte v1 (palier 4 intégré) | [`fichiers/M02-E46/docs/astreinte.md`](fichiers/M02-E46/docs/astreinte.md) |
| Tests de `ms-alerte` (script qui n'en avait pas) | [`fichiers/M02-E46/tests/bats/ms-alerte.bats`](fichiers/M02-E46/tests/bats/ms-alerte.bats) |

**Démarche recommandée** (8 à 12 h)

1. **Assainir d'abord** (1 h) : `lab/bin/check 02 46`, puis les contrôles détaillés. KO typiques à ce stade : un script de `bin/` sans test (`ms-alerte`, `ms-verif-fraicheur`), une remarque ShellCheck dans un script ajouté au palier 4, une VM 2027 ou 2020 oubliée, une panne d'exercice encore marquée active, un timer arrêté lors d'un essai, l'inventaire qui ne contient pas `runner01`.
2. **Intégrer** (2 à 3 h) : une MR par lot cohérent, chacune avec ses tests. Exemple de découpage et de messages (ils font la release) :
   - `feat(purge): ms-purge-rapports conforme à la politique PLAT-384` ;
   - `feat(journaux): ms-archiver-journaux sans échec silencieux` ;
   - `feat(systemd): chien de garde ms-verif-fraicheur` ;
   - `test: spécification exécutable de Bash` et `test(alerte): tests de ms-alerte` ;
   - `docs: guide d'astreinte v1, grille de revue`.
3. **Mesurer** (30 min) : le dernier pipeline de `main` (onglet *Tests* : suites `bats` et `pytest`, zéro échec ; couverture affichée sur le job `pytest`). Une couverture de 80 à 90 % sur `medictl` est réaliste ; ce qui reste non couvert est en général le client HTTP réel et le point d'entrée : le dire dans le README plutôt que viser 100 % avec des tests qui ne testent rien.
4. **Publier** (30 min) : la fusion du dernier `feat:` déclenche la release (version mineure), puis `publier-pypi`. Vérifier dans *Deploy → Package registry* : roue et archive source de la version.
5. **Installer** (30 min) :
   ```
   admin@adm01:~$ uv tool upgrade medictl && medictl --version
   admin@adm01:~/src/outils$ git switch main && git pull && task install:systeme
   admin@adm01:~/src/outils$ sudo install -m 0644 systemd/* /etc/systemd/system/ && sudo systemctl daemon-reload
   admin@adm01:~$ sudo systemctl enable --now ms-verif-sauvegardes.timer ms-verif-fraicheur.timer
   admin@adm01:~$ sudo systemctl start ms-verif-sauvegardes.service ms-verif-fraicheur.service
   ```
   `install:systeme` (M02-E26) copie seulement `bin/` et `lib/` dans `/usr/local` : la tâche `install` de M02-E20 réinstalle aussi `medictl` **depuis le clone** (`uv tool install --from .`), ce qui remplacerait la version du registre par une installation de développement (le contrôle le détecte). Après M02-E25, garde `install` pour le poste de développement et sépare clairement les deux usages dans le Taskfile et le README.
   Retour arrière documenté et testé : `uv tool install --force medictl==<VERSION-PRÉCÉDENTE> --index outils=<URL-REGISTRE>` pour la CLI ; pour les scripts, `git switch --detach v<VERSION-PRÉCÉDENTE> && task install:systeme`, puis `systemctl start` des services et lecture du résultat ; retour sur `main` ensuite.
6. **Documenter** (2 h) : README, guide d'astreinte, CONTRIBUTING, ADR-0020 ; puis l'inventaire (`medictl inventaire --format markdown` entre les repères de M02-E21) et sa section « comptes et jetons » :

   | Identité | Rôle / périmètre | Usage | Secret (emplacement) | Expiration | Propriétaire |
   |---|---|---|---|---|---|
   | `wb-automation@pve!lab` | `WBAutomation` sur `/pool/lab` (+ SDN) | `medictl`, `ms-snapshot` | `adm01:~admin/.config/workbook/pve-api.env` (600) | AAAA-MM-JJ | Plateforme |
   | `wb-automation@pve!lecture` | `PVEAuditor` sur `/pool/lab` | contrôle des sauvegardes | `adm01:~admin/.config/workbook/pve-lecture.env` (600) | AAAA-MM-JJ | Plateforme |
   | `wb-verif@pbs!lecture` | `DatastoreAudit` sur `/datastore/ds-lab/par1` | contrôle des sauvegardes | `adm01:~admin/.config/workbook/pbs-lecture.env` (600) | AAAA-MM-JJ | Plateforme |
   | jeton de déploiement du registre | `read_package_registry` | installation de `medictl` | magasin `uv auth` de `admin` (600) | AAAA-MM-JJ | Plateforme |
   | `bot-release` (jeton de projet) | Maintainer, `api`, `write_repository` | semantic-release | variable CI protégée et masquée | AAAA-MM-JJ | Karim Benali |

   Rappel de M02-E36 : avec la séparation des privilèges, l'ACL de l'**utilisateur** `wb-automation@pve` sur `/pool/lab` est indispensable ; l'inventaire le dit, pour que la prochaine revue des accès ne la retire pas.
7. **Hygiène et secrets** (30 min) :
   ```
   admin@adm01:~$ ssh pve01 "qm list | awk 'NR>1 && \$1 >= 2020 && \$1 <= 2029'"
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null
   admin@adm01:~/src/outils$ gitleaks git --no-banner --redact .
   admin@adm01:~$ find ~/.config/workbook -type f ! -perm 600
   ```
   Les zones `/opt/workbook/m02/eXX*` ne contiennent que des données fictives : supprime-les quand tu n'en as plus l'usage (`sudo rm -rf /opt/workbook/m02/e37*` après vérification du chemin).

**Grille d'évaluation de la revue** (Claire, Karim, Sophie, Nadia ; en auto-évaluation si tu travailles seul)

Barème sur 100. Seuil de recette : 70, **et** aucun critère éliminatoire.

*Critères éliminatoires* : contrôle global non vert ; un secret dans un dépôt, un journal CI ou la documentation (même dans l'historique) ; paquet publié depuis un poste ; jeton d'automatisation aux droits élargis « pour que ça marche ».

| # | Axe | Points | Insuffisant (0-40 %) | Attendu (60-80 %) | Excellent (100 %) |
|---|---|---|---|---|---|
| 1 | Code et tests | 20 | scripts sans tests, remarques ShellCheck désactivées en masse | chaque script testé, CI verte, rapports et couverture publiés | tests qui reproduisent les pannes du palier 4 ; spécification de Bash en CI ; ce qui n'est pas testé est dit |
| 2 | Livraison | 15 | installation manuelle depuis le clone | release, paquet, installation depuis le registre, tâche `install` | notes de version utiles, retour arrière testé et chronométré |
| 3 | Exploitation | 15 | timer actif | contrôle + alerte + chien de garde, testés sous systemd | limites du chien de garde écrites, proposition pour le module 21 |
| 4 | Sécurité | 15 | jetons et secrets non inventoriés | jetons en lecture seule, secrets en 600, inventaire sans secret | dates d'expiration suivies, propriétaires, procédure de rotation |
| 5 | Documentation | 20 | README minimal | README, guide d'astreinte v1, CONTRIBUTING, ADR | guide validé par un tiers sur une panne tirée au sort, sans aide |
| 6 | Présentation et défense | 15 | lecture des fichiers | 10 min structurées, démonstration réussie | limites, risques et dette assumés, préparation des modules 03-06 |

**Questions de revue typiques et éléments de réponse attendus**

| Question | Ce qu'une bonne réponse contient |
|---|---|
| (Karim) « Pourquoi ce script est-il en Bash et pas en Python ? » | les critères de l'ADR-0020 appliqués au script : taille, nature des données, API, parallélisme ; et le seuil au-delà duquel on le réécrira |
| (Sophie) « Si `adm01` est compromis, qu'obtient l'attaquant ? » | les jetons de `~/.config/workbook` : création, modification et destruction de **toute** VM du pool `lab`, socle compris (les garde-fous de `medictl` sont côté client : un attaquant appelle l'API directement), lecture des métadonnées de sauvegarde, lecture du registre de paquets ; d'où : droits minimaux, expiration, rotation, module 25 (Vault) |
| (Nadia) « Le contrôle ne tourne plus depuis trois jours : qui le voit ? » | le chien de garde (dans l'heure) ; ses limites (même machine) ; la proposition d'observateur externe (module 21) |
| (Claire) « Qu'est-ce qui va changer pour ces outils dans les trois prochains modules ? » | images dorées testées avec `ms-attendre`/`medictl` (M03) ; installation par Ansible des outils et unités (M04) ; VMs durables créées par OpenTofu, `medictl` réservé au jetable (M05) ; inventaire repris par NetBox (M06) |
| (Karim) « Ton taux de couverture est de 85 % : que contiennent les 15 % ? » | le client HTTP réel, le point d'entrée, les branches d'erreur réseau rares ; pourquoi c'est acceptable ; ce qui le remplace (tests de bout en bout manuels documentés, `lab/bin/check`) |

**Explications**

Un outil interne devient un produit quand quelqu'un d'autre que son auteur peut l'installer, s'en servir, le dépanner et le faire évoluer sans lui. Le contrôle global vérifie la **forme** (version, paquet, tests, timers, documents) ; la revue vérifie l'**usage** : la démonstration de Nadia avec le seul guide est le test qui compte. Les pannes du palier 4 ont montré que l'outillage casse surtout par son environnement (systemd, droits, Python, CI) : la v1 se juge donc autant sur ses contrôles planifiés, son inventaire des jetons et son guide que sur son code.

**Alternatives**
- Distribuer les scripts Bash aussi par le registre (paquet Debian `.deb` construit en CI, ou archive versionnée) au lieu de `task install` depuis un clone : plus propre pour un parc de postes ; c'est ce que fera Ansible (module 04) à partir de l'étiquette.
- Un seul langage (tout Python, avec `click`/`typer` pour les gestes système) : défendable, c'est un des choix examinés par l'ADR-0020.

**Pièges classiques**
- Fusionner des MR en `chore:` ou `docs:` seulement : aucune nouvelle version n'est publiée, et l'installation reste sur l'ancienne.
- Désactiver une règle ShellCheck pour tout le projet afin de passer le contrôle.
- Un guide d'astreinte qui décrit les outils au lieu de partir des alertes.
- Un inventaire régénéré mais non fusionné (le contrôle lit le clone **et** son état Git).
- Laisser les zones de test du palier 4 et des VMs jetables : l'hygiène fait partie de la livraison.

**En production chez MédiSphère**
L'outillage est un produit avec un propriétaire (l'équipe Plateforme), une feuille de route, des versions et une politique de support (la version N et N-1 sont supportées sur les postes). Son installation est automatisée (module 04), ses contrôles planifiés sont supervisés de l'extérieur (module 21), ses jetons sont émis et renouvelés par Vault (module 25), et le guide d'astreinte est relu après chaque incident.
