# Module 10 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M10-E46 — Mini-projet : cloud MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail**, une décision de référence pour « déployer depuis le dépôt », les démonstrations, et la **grille de revue** de Claire, Karim, Sophie, Nadia et Julien. Les fichiers de référence sont ceux des exercices (`corrige/fichiers/M10-EXX/`) ; ce mini-projet ajoute : [`.gitlab-ci.yml` de `plateforme/openstack`](fichiers/M10-E46/openstack/.gitlab-ci.yml), [`outils/invariants-globals.sh`](fichiers/M10-E46/openstack/outils/invariants-globals.sh), [`outils/deployer.sh`](fichiers/M10-E46/openstack/outils/deployer.sh), [`docs/cloud/guide-utilisateur.md`](fichiers/M10-E46/medisphere/docs/cloud/guide-utilisateur.md) et [`docs/cloud/README.md`](fichiers/M10-E46/medisphere/docs/cloud/README.md).

**Points non testés en conditions réelles** : ceux du palier 3 (corrigé `03-production.md`), et le parcours de `deployer.sh` (vérification du pipeline par l'API GitLab avec le jeton des checks, étiquette poussée depuis `adm01` : le jeton SSH de `<MOI>` doit pouvoir pousser des étiquettes non protégées `deploye-*`).

**Solution**

*Décision : déployer depuis le dépôt, sans donner les clés du cloud au runner partagé*

| Option | Pour | Contre |
|---|---|---|
| Job de déploiement sur `runner01` (exécuteur shell partagé) | tout dans GitLab, traçabilité native | `runner01` exécute les jobs de **tous** les projets (dont ceux des équipes en E31) sous le même compte : y mettre l'accès root aux nœuds OpenStack et l'identité Vault `critique`, c'est les donner à quiconque peut pousser un pipeline ; jobs de 30 min qui bloquent le runner |
| Runner dédié sur `adm01`, verrouillé sur `plateforme/openstack`, branches protégées seulement | déploiement par le pipeline, secrets hors de `runner01` | un second compte sur `adm01` qui détient les mêmes accès que `admin` (duplication des secrets) ; à réévaluer avec les runners Kubernetes et Vault (modules 19 et 25) |
| **Depuis `adm01`, par `outils/deployer.sh`** (retenu) | aucun nouvel accès ; le script refuse tout autre état que le commit de `origin/main` dont le pipeline est vert ; chaque déploiement laisse une étiquette `deploye-AAAAMMJJ-HHMM` | geste humain (déclenché), discipline d'utiliser le script |

La CI (`controles-kolla`) vérifie : `passwords.yml` chiffré **avec l'identité `critique`** (en-tête `$ANSIBLE_VAULT;1.2;AES256;critique`), aucune clé privée, YAML valide, et les **invariants** du PLAN (`invariants-globals.sh` fusionne `globals.yml` et `globals.d/` comme Kolla et compare 17 valeurs figées). Une valeur figée modifiée volontairement passe par une MR qui modifie aussi l'invariant : la revue voit les deux.

*Plan de travail recommandé*

1. **État des lieux** (1 h) : `lab/bin/check 10 46` ; les checks détaillés en rouge ; `lab/bin/check 08 46` pour Ceph. Liste de ce qui a été fait à la main pendant le module (historique du shell de `adm01`, `git status` des clones, `docker ps -a` des nœuds pour des conteneurs non Kolla, fichiers sous `/etc/kolla/config` modifiés sur un nœud au lieu du dépôt).
2. **Le dépôt fait foi** (2 à 3 h) : clone neuf de `plateforme/openstack` dans un dossier temporaire de `adm01`, `uv sync --frozen`, puis `uv run kolla-ansible genconfig -i inventaire/multinode --configdir etc/kolla --check --diff` (mode vérification d'Ansible : affiche ce que la génération changerait dans `/etc/kolla/<service>/` des nœuds, sans rien écrire — à confirmer sur ton lab, toutes les tâches de Kolla ne respectent pas forcément ce mode ; sans `--check`, `genconfig` **écrit** la configuration sur les nœuds, sans redémarrer). Tout écart est soit une surcharge oubliée dans `config/`, soit une modification manuelle à reporter. Puis CI et `deployer.sh`, premier `deploy` tracé.
3. **Le cloud** (2 h) : les invariants passent ; quotas explicites sur les projets des équipes (pas les 20 vCPU / 50 Go de Nova par défaut) ; matrice des flux relue (VLAN 52 → VLAN 50 interdit, ACME, PBS) ; `ms-verif-openstack` vert.
4. **Libre-service** (2 h) : étiquette du module, répétition de la démonstration de Julien avec un compte d'équipe.
5. **Exploitation** (3 h) : restauration de la livraison (procédure de E25, chronométrée, réconciliée) ; RB relus ; rapport de capacité du mois (`ms-capacite-openstack`).
6. **Documentation et livraison** (2 à 3 h) : `README.md` et `guide-utilisateur.md` de `docs/cloud/`, registre des secrets, matrice des flux, MR, pipelines verts, retrait des essais, étiquette `cloud-v1`.

*Démonstration de Julien (recette de zéro)*

| Étape | Qui | Preuve |
|---|---|---|
| Pipeline lancé à la main sur `main` de `mediagenda/recette-infra` avec `DETRUIRE=agenda-recette`, job `detruire` | Julien | plus aucune ressource `agenda-recette-*` dans `mediagenda-dev` |
| MR triviale (titre de la page), plan visible dans la MR, fusion | Julien | plan : création de ~30 ressources |
| Job `appliquer` | Julien | sortie `url`, second plan vide |
| Navigation depuis le VPN | Julien | page servie, nom d'hôte alternant entre `app01` et `app02` |
| Lecture du guide en cas de doute | Julien | aucune question à la plateforme |

Durée typique : 15 à 20 minutes, dont 10 d'attente (instances, nginx, répartiteur).

*Démonstration de Nadia (RB-102)* : `oscmp02` vidé, retiré, réintégré pendant que la recette de Julien tourne ; mesure de continuité sur l'IP flottante du répartiteur (aucune coupure attendue : les deux membres sont sur des calculs différents, le répartiteur OVN est distribué).

*Reconstruction demandée par Karim* (exemple) : « supprime `/etc/kolla/horizon/_9999-custom-settings.py` sur `osctl01`, puis remets l'état voulu » → `outils/deployer.sh reconfigure -t horizon` depuis un `main` propre : le fichier revient, une étiquette `deploye-*` trace l'opération.

**Explications**

Ce mini-projet vérifie l'**intégration** et l'**exploitabilité par d'autres**. Chaque brique a été construite dans un exercice ; leur valeur vient de ce qu'un tiers (Julien, Nadia, Karim) peut s'en servir sans toi, et de ce que le dépôt suffit à reconstruire l'état. Le contrôle global revérifie Ceph (M08) parce que le cloud en dépend entièrement : une régression silencieuse du stockage est le risque principal d'un module qui y écrit chaque jour.

**Alternatives**
- Déploiement par le pipeline avec un runner Kubernetes éphémère et des secrets tirés de Vault au moment du job (modules 19 et 25) : la cible à terme.
- Kayobe (au-dessus de Kolla-Ansible) pour gérer aussi les hôtes, le réseau et le cycle de vie complet : pertinent sur du matériel réel.
- Pour le libre-service, un catalogue (Backstage, module 28) qui crée le dépôt de l'équipe à partir d'un modèle.

**Pièges classiques**
- Un déploiement « depuis le dépôt » lancé depuis une copie de travail modifiée : c'est exactement ce que `deployer.sh` refuse.
- Des surcharges posées directement sous `/etc/kolla/` d'un nœud : elles disparaissent au prochain `reconfigure`, et personne ne sait pourquoi le comportement a changé.
- Des quotas par défaut sur les projets des équipes : la somme des quotas promet des centaines de Go de mémoire sur un cloud qui en a moins de 12 d'allouables.
- Une démonstration de Julien répétée avec ton compte administrateur : elle marche, puis échoue le jour J (droits, liste d'accès par jeton de job, variables protégées).
- Laisser les instances d'essai du module (`ha-essai`, `maj-essai`…) : elles consomment la capacité et faussent le rapport.

**En production chez MédiSphère**
La recette ajoute un exercice de reprise : `osctl01` arrêté 30 minutes en heures ouvrées annoncées (les équipes constatent : API indisponibles, instances vivantes, IP flottantes coupées) ; le compte rendu complète `haute-disponibilite.md` et alimente la décision budgétaire sur les trois contrôleurs.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 10 46` entièrement vert, sans contrôle ignoré |
| Claire | Limites connues | points uniques de défaillance listés dans `docs/cloud/README.md` avec leur impact et l'échéance de traitement ; capacité du mois et projection |
| Karim | Code | dépôt suffisant (reconstruction d'un détail réussie), CI avec invariants, déploiement tracé (`deploye-*`), aucune surcharge hors dépôt, module `openstack-env-app` étiqueté et relu |
| Karim | Choix | décision « déployer depuis le dépôt » argumentée ; ADR-0100 et ADR-0101 à jour |
| Sophie | Sécurité | TLS interne et externe renouvelés automatiquement, verrouillage des comptes (comptes de service dispensés), matrice des flux (VLAN 52 → VLAN 50 interdit), ce qui reste en clair signé |
| Sophie | Secrets | registre complet (emplacements, portée, propriétaire, échéance), application credentials à droits minimaux et expirantes, aucun secret dans les dépôts ni les journaux |
| Nadia | Restauration | test de la livraison chronométré, réconcilié (orphelins traités), RTO et RPO |
| Nadia | Exploitation | sonde planifiée et alertes testées, RB-102 joué en démonstration, runbooks du palier 4 relus |
| Julien | Libre-service | recette recréée de zéro avec le seul guide et son pipeline, sans aide |
| Julien | Guide | limites du répartiteur OVN claires, dépannage rapide utile |
| Tous | Présentation | 10 minutes : ce qui est livré, ce qui ne l'est pas, risques, ce que les modules suivants consommeront |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le compte rendu de recette, jamais passé sous silence.
