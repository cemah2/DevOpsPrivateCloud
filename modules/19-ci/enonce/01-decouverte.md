# Module 19 — Palier 1 : Découverte

Avant de factoriser des pipelines ou de les sécuriser, il faut un endroit où les faire tourner et une lecture exacte de ce qui s'y passe. Ce palier prépare `k8s-par1` à recevoir des jobs (mémoire des travailleurs, espaces, quotas, compte des vérifications), crée `mon01` et sa messagerie Mailpit pour que GitLab puisse enfin envoyer des courriels, installe le runner `k8s-par1` par Helmfile avec un jeton créé par l'API, puis te fait lire un pod de job pièce par pièce. Tu pratiques ensuite la syntaxe de GitLab CI en profondeur sur un projet d'essai, `formation/ci-labo` (`needs`, `rules`, `workflow`, variables, artefacts, cache S3, environnements), et tu termines par un démon BuildKit *rootless* partagé, en TLS mutuel, qui construit la première image de MédiAgenda dans le cluster. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : modules 17 et 14 verts (`lab/bin/check 17 25`, `lab/bin/check 14 46`) ; module 01 (GitLab, MR, gabarits CI), module 12 (BuildKit sans privilège, `runner02`), module 13 (Harbor, caches, Cosign, chaîne `supply-chain.yml`), module 15 (cert-manager, CiliumNetworkPolicy), module 16 (`s3-01` vu des travailleurs, identités SeaweedFS). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M19-E01 — Test de positionnement : intégration continue  `Q` `★★`

> **Ticket PLAT-2001** — *De : Karim Benali*
> Une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Tu as écrit des pipelines au module 01 et au module 13 ; je veux savoir ce que tu en as **compris**, pas ce que tu sais recopier. Réponds même là où tu hésites : je lis le raisonnement.

**Objectifs pédagogiques**
- Évaluer ce que tu sais de GitLab CI avant de le pousser dans ses retranchements.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Structure d'un pipeline*

1. Trois stages `lint`, `test`, `build`. Le job `build-image` (stage `build`) n'a besoin que du job `lint-dockerfile` (stage `lint`). Les tests durent 12 minutes. Combien de temps attend `build-image` sans `needs`, et avec `needs: [lint-dockerfile]` ? Que change `needs: []` ?

2. *(QCM)* Un job porte `rules: - if: $CI_COMMIT_BRANCH == "main"` et `only: [tags]`. Que se passe-t-il ?
   - A. Le job tourne sur `main` et sur les étiquettes
   - B. Le job tourne seulement quand les deux conditions sont vraies
   - C. Le pipeline est refusé : `rules` et `only` ne se combinent pas dans un même job
   - D. `only` est ignoré, `rules` gagne

3. Explique la différence entre les `rules` d'un job et `workflow:rules`. Lequel des deux évite qu'un même commit poussé sur une branche avec une MR ouverte crée deux pipelines ?

4. Que fait `rules: - changes: [src/**/*]` dans un pipeline de **branche** dont c'est le premier commit poussé ? Et dans un pipeline de MR ?

5. À quoi servent `interruptible: true` et le réglage d'annulation automatique des pipelines redondants ? Pourquoi ne met-on jamais `interruptible: true` sur un job de déploiement ?

*Variables et secrets*

6. Une variable `DB_PASSWORD` est déclarée **protégée** et **masquée** au niveau du projet. Un développeur pousse une branche `essai` (non protégée) dont le job fait `echo $DB_PASSWORD`. Que voit-il dans le journal, et pourquoi ?

7. *(QCM)* La même variable `NIVEAU` est définie dans le `.gitlab-ci.yml` (au niveau global), dans les réglages CI/CD du projet, et dans les variables d'un job. Laquelle gagne dans ce job ?
   - A. Celle du `.gitlab-ci.yml` global
   - B. Celle des réglages du projet
   - C. Celle du job
   - D. La première définie dans l'ordre alphabétique des sources

8. Qu'est-ce qu'une variable de type **fichier** ? Donne un cas où elle est préférable à une variable ordinaire.

9. Qu'est-ce que le `CI_JOB_TOKEN` ? Combien de temps vit-il, et avec les droits de qui ?

*Artefacts, cache, environnements*

10. Artefacts ou cache ? Pour chacun, choisis et justifie : (a) le rapport JUnit des tests, (b) le dossier `.venv` téléchargé par `uv sync`, (c) le binaire compilé que le job suivant doit tester, (d) la base de vulnérabilités de Trivy.

11. Pourquoi un cache **local** au runner ne sert presque à rien avec un exécuteur Kubernetes, alors qu'il était efficace sur `runner01` (exécuteur `shell`) ?

12. Que garantit `resource_group: prod` ? Et que ne garantit-il **pas** (pense à l'ordre des déploiements) ?

13. GitLab CE ne propose pas les environnements protégés (Premium). Avec quels moyens de l'édition gratuite empêches-tu qu'un développeur déploie en production depuis sa branche ?

*Runners et exécution*

14. Le runner `runner02` a les étiquettes `docker` et `socle`, et « ne prend pas les jobs sans étiquette ». Un job sans `tags:` reste « en attente ». Pourquoi ? Donne deux corrections et dis laquelle tu préfères.

15. *(QCM)* Qui ouvre la connexion entre GitLab et un runner ?
    - A. GitLab, qui pousse le job vers le runner sur son port 8093
    - B. Le runner, qui interroge GitLab et attend une réponse (*long polling*)
    - C. Un webhook de GitLab vers le runner
    - D. Le runner ouvre un tunnel permanent dans lequel GitLab pousse les jobs

16. Depuis GitLab 16, l'ancien « jeton d'enregistrement » est déconseillé au profit d'un **jeton d'authentification** créé dans GitLab. Qu'est-ce que ce changement améliore pour un administrateur ?

17. Cite trois exécuteurs de GitLab Runner et, pour chacun, un avantage et un risque.

18. Pourquoi Docker-in-Docker (`services: [docker:dind]`) exige-t-il un conteneur privilégié ? Que peut faire un job malveillant dans un conteneur privilégié ?

*Pipelines de MR et de branche*

19. Quelle est la différence entre un pipeline de **branche** et un pipeline de **MR** (variables disponibles, code testé, résultat affiché dans la MR) ? Qu'est-ce qu'un pipeline de « résultat fusionné » (*merged results*), et est-il disponible dans l'édition gratuite ?

20. Un collègue propose : « Pour aller plus vite, on lance tous les jobs sur un seul gros runner avec `concurrent = 50`. » Donne deux raisons de ne pas le faire, et ce que tu proposes à la place.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions sur `rules` et `workflow`, distingue deux moments : la **création** du pipeline (le pipeline existe-t-il ?) et la **composition** du pipeline (quels jobs contient-il ?).
</details>

<details><summary>Indice 2</summary>

Pour les questions sur le cache, demande-toi **où** vivent les fichiers entre deux jobs : sur un disque de la machine qui a exécuté le premier job, ou dans un stockage que tous les exécutants voient.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M19-E46), sans relire le corrigé, et compare.

---

### M19-E02 — Préparer `k8s-par1` pour la CI  `LAB` `★★`

> **Ticket PLAT-2002** — *De : Karim Benali* — *Copie : Claire Morel*
> Avant d'y mettre un runner, je veux un cluster qui sait **dire non**. Les travailleurs sont à 8 Go et déjà bien remplis : passe-les à 10 Go, par le code, un nœud à la fois, sans jamais perdre MédiAgenda. Ajoute aussi le réglage noyau dont SonarQube (et OpenSearch au M22) auront besoin, par le rôle des travailleurs. Puis trois espaces : un pour le gestionnaire des runners, un pour les jobs, un pour le démon de construction. Les jobs ont un **quota** et des valeurs par défaut : un job sans demandes de ressources ne doit ni être refusé, ni pouvoir prendre tout un nœud. Et les vérifications du workbook doivent pouvoir lire tout ça.

**Objectifs pédagogiques**
- Modifier la mémoire de nœuds Kubernetes par OpenTofu sans interruption de service : drain, arrêt, changement, redémarrage, remise en service.
- Ajouter un paramètre noyau à un rôle Ansible existant, de façon variable et vérifiable.
- Concevoir les espaces d'une CI dans Kubernetes : Pod Security, quota, LimitRange, compte de service sans droit.
- Étendre la ClusterRole agrégée des vérifications sans toucher à la base.

**Prérequis** : M14-E46 (cluster, `plateforme/k8s`, `wb-checks`), M14-E17 (drain et retour d'un nœud), M16-E05 (modifier les travailleurs un par un), M14-E18 (VAP `medisphere-images`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Mémoire | travailleurs `k8s-w01..03` (2144-2146) : 8192 → **10240 Mo**, dans l'état `envs/k8s` de `plateforme/infra` ; nœuds de contrôle inchangés (4 Go) |
| Noyau | `vm.max_map_count = 524288` sur les **travailleurs** seulement, par le rôle `k8s_travailleur` (variable, fichier `/etc/sysctl.d/`) |
| Espaces | `gitlab-runner` (gestionnaire), `ci-jobs` (pods de job), `buildkit` (démon, E08) ; fichiers `espaces/<espace>/` de `plateforme/k8s`, comme `medidoc-dev` (M14-E33) |
| Pod Security | `gitlab-runner` : `restricted` ; `ci-jobs` : `baseline` appliqué, `restricted` en avertissement et en audit (passage en `restricted` au palier 3, E24) ; `buildkit` : à décider et à justifier (indice : E08) |
| `ci-jobs` | étiquette `medisphere.internal/equipe: plateforme` (la VAP `medisphere-images` s'y applique) ; ResourceQuota `quota-ci` : requests 6 CPU / 12 Gi, limits 16 CPU / 24 Gi, 20 pods, aucun Service `LoadBalancer`/`NodePort`, aucun PVC ; LimitRange `limites-ci` : par défaut 1 CPU / 1 Gi (limites) et 100m / 128 Mi (demandes), maximum 4 CPU / 4 Gi par conteneur ; ServiceAccount **`ci-job`** sans jeton monté, sans aucune liaison |
| Vérifications | ClusterRole **`wb-checks-livraison`** (fichier `rbac/wb-checks-livraison.yaml`), étiquetée `workbook.medisphere.internal/checks: "true"` : lecture des pods, deployments, configmaps, resourcequotas, limitranges, networkpolicies, ciliumnetworkpolicies, serviceaccounts, rolebindings dans tout le cluster ; **jamais** les Secrets |

**Travail demandé**

*A. La mémoire des travailleurs*

1. Mesure l'existant : `kubectl top nodes`, `kubectl describe node k8s-w01 | sed -n '/Allocated resources/,/Events/p'`, et sur `pve01` `free -g`. Combien de mémoire demandée (*requests*) reste-t-il sur chaque travailleur ? Combien la CI va-t-elle en consommer au pire avec le quota prévu ?
2. Dans `envs/k8s`, rends la mémoire des travailleurs **réglable nœud par nœud** (une table, sur le modèle de la carte de stockage du M16-E05). Lis le plan d'un changement qui ne touche que `k8s-w01` : qu'est-ce qui change, et que fera le fournisseur `bpg/proxmox` sur une VM **démarrée** dont la mémoire change (relis M05-E06) ?
3. Pour **chaque** travailleur, l'un après l'autre :
   > ⚠️ **Attention** : un seul travailleur hors service à la fois. Avant le suivant, le nœud doit être `Ready`, non cordonné, et les pods de MédiAgenda revenus `Running` dans `mediagenda-dev`, `mediagenda-recette` et `mediagenda-prod`. Retour arrière : remettre 8192 dans la table et repasser par la même procédure.
   - `kubectl drain` (avec les options qu'il faut pour les DaemonSets et les volumes `emptyDir`), en vérifiant que les PodDisruptionBudgets sont respectés ;
   - arrêt propre de la VM ;
   - MR qui ne change que ce nœud, `apply` par le pipeline de `plateforme/infra` ;
   - démarrage, `Ready`, `uncordon`, contrôle des pods.
   Note dans ton journal la durée d'indisponibilité du nœud et ce qui a bougé.
4. Dans le nœud, `free -m` et `kubectl describe node` : la capacité et l'allouable (*allocatable*) ont-ils changé ? Pourquoi l'allouable est-il inférieur à la capacité ?

*B. Le paramètre noyau*

5. Étends le rôle `k8s_travailleur` : une variable (dictionnaire de paramètres noyau propres aux travailleurs), une tâche qui les écrit dans un fichier de `/etc/sysctl.d/` distinct de celui de `k8s_noeud`, un contrôle qui lit la valeur **effective**. Mets à jour `argument_specs`. Applique au seul groupe des travailleurs, un nœud à la fois ; second passage : `changed=0`.
6. Pourquoi ce paramètre est-il au niveau du **nœud** et pas du pod ? Que ferait un conteneur d'initialisation privilégié qui le règle lui-même (c'est ce que proposent certains charts) ?

*C. Les espaces de la CI*

7. Écris les trois espaces dans `plateforme/k8s/espaces/` : `Namespace` (étiquettes PSA versionnées comme au M14-E33, étiquettes `medisphere.internal/*`), puis pour `ci-jobs` le quota, le LimitRange et le compte de service `ci-job`. Pour `buildkit`, choisis le niveau de Pod Security après avoir lu la section « Rootless mode » de la documentation BuildKit et le manifeste `deployment+service.rootless.yaml` amont : justifie en commentaire.
8. Pourquoi un LimitRange est-il **indispensable** dès qu'un ResourceQuota porte sur `limits.memory` ? Que se passerait-il pour un pod de job sans ressources déclarées ?
9. Écris `rbac/wb-checks-livraison.yaml`. Plusieurs de ces ressources sont déjà lisibles par `wb-checks-base` (M14-E06) : pourquoi les déclarer quand même ici ?
10. MR, relecture, `task diff` puis `task appliquer`. Contrôle :
    ```
    admin@adm01:~$ kubectl --context k8s-par1 get ns gitlab-runner ci-jobs buildkit --show-labels
    admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs describe quota,limitrange
    admin@adm01:~$ kubectl --context k8s-par1 auth can-i --list --as=system:serviceaccount:ci-jobs:ci-job -n ci-jobs
    ```
11. Essaie, dans `ci-jobs`, de créer un pod `alpine:latest` (`kubectl run --image=…`) puis un pod de l'image `debian` du cache Harbor **épinglée** sans ressources déclarées. Lis les deux réponses et les ressources du second pod. Supprime-le.

**Critères de réussite**
- [ ] Les trois travailleurs ont 10240 Mo dans Proxmox et ≈ 10 Gio de capacité dans Kubernetes ; ils sont `Ready` et non cordonnés ; les nœuds de contrôle sont inchangés.
- [ ] `vm.max_map_count` vaut 524288 sur chaque travailleur, persistant (fichier de `/etc/sysctl.d/`), par le rôle `k8s_travailleur`.
- [ ] Les espaces `gitlab-runner`, `ci-jobs` et `buildkit` existent avec leurs étiquettes de Pod Security ; `ci-jobs` porte l'étiquette d'équipe, le quota `quota-ci`, le LimitRange `limites-ci` et le compte de service `ci-job` (jeton non monté, aucune liaison).
- [ ] La ClusterRole `wb-checks-livraison` existe, étiquetée pour l'agrégation, sans accès aux Secrets.
- [ ] `envs/k8s`, le rôle et les manifestes sont sur `main` ; une image `latest` est refusée dans `ci-jobs`.

**Vérification** : `lab/bin/check 19 02`

<details><summary>Indice 1</summary>

`kubectl drain` refuse de partir tant qu'un pod de DaemonSet ou un pod avec un volume `emptyDir` est là : lis son message, il cite les options. Un PDB qui interdit toute éviction bloque le drain indéfiniment : `kubectl get pdb -A` avant de commencer. Côté OpenTofu, le M16-E05 avait une table `stockage_actif` par travailleur : même idée.
</details>

<details><summary>Indice 2</summary>

`baseline` interdit explicitement un profil seccomp `Unconfined` et un profil AppArmor autre que celui du runtime ou un profil local : lis la page « Pod Security Standards ». Pour le quota, tout pod soumis à un quota sur `limits.*` doit déclarer des limites pour **chaque** conteneur, conteneurs d'initialisation compris : c'est le LimitRange qui les complète.
</details>

<details><summary>Indice 3</summary>

Une ClusterRole agrégée réunit les règles de **toutes** les ClusterRoles étiquetées : si quelqu'un réduit un jour `wb-checks-base`, les vérifications de ce module doivent continuer à fonctionner. `kubectl auth can-i --list --as=…` ne donne pas toujours la vérité sur ce qui est refusé : préfère `kubectl auth can-i get secrets -n ci-jobs --as=…`.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Node-pressure Eviction » et calcule, pour un travailleur à 10 Go, la mémoire à partir de laquelle le kubelet évince des pods avec la configuration de M14-E04 (`evictionHard`, `systemReserved`, `kubeReserved` s'ils sont posés).

---

### M19-E03 — `mon01` et Mailpit : la messagerie du lab  `LAB` `★★`

> **Ticket PLAT-2003** — *De : Claire Morel* — *Copie : Nadia Roussel, Sophie Laurent*
> GitLab n'envoie aucun courriel depuis le module 01 : ni notification de pipeline, ni réinitialisation de mot de passe, ni avis d'expiration de jeton. Et au M21, les alertes devront partir **quelque part**. On ne relaie rien vers Internet : je veux un serveur de messagerie **de lab**, qui reçoit tout et ne livre rien, consultable par l'équipe. Une nouvelle VM du socle, `mon01` : elle portera aussi la supervision « témoin » au M21, alors traite-la comme un hôte permanent dès le premier jour.
>
> **Ticket SEC-2003** — *De : Sophie Laurent*
> Un serveur SMTP, même de lab, reçoit des données (noms, adresses, extraits de tickets). Chiffrement de bout en bout du lab (STARTTLS avec un certificat de notre PKI, que GitLab **vérifie**), interface protégée par mot de passe et limitée au réseau d'administration, service sans privilège, binaire vérifié par empreinte. Et rien qui ressemble à un relais ouvert.

**Objectifs pédagogiques**
- Ajouter un hôte permanent au socle par le chemin standard : OpenTofu (`socle`), NetBox, DNS, Ansible, sauvegarde, matrice des flux.
- Écrire un rôle Ansible de service : binaire épinglé par empreinte, utilisateur dédié, unité systemd durcie, certificat ACME renouvelé.
- Configurer l'envoi de courriels de GitLab (paquet Linux) vers un serveur SMTP interne avec STARTTLS vérifié.
- Tester un serveur SMTP au niveau du protocole.

**Prérequis** : M13-E02 (`reg01` : même chemin pour un hôte du socle), M06-E18 (rôle `certificats_acme`), M06-E30 (rôle `pare_feu_local`), M07-E30 (matrice des flux de la bordure), M04-E46 (rôle `gitlab_hote`), M00-E22 (travaux de sauvegarde PBS).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `mon01`, VMID **1014**, **10.10.20.19/24** (VNet `vinfra`), Debian 13 (image dorée `current`), 2 vCPU, **3 Go**, 32 Gio `local-nvme`, étiquettes `socle`, `role-supervision` ; `socle/mon01.tf` de `plateforme/infra`, module `vm-debian` ; démarrage avec `pve01` (ordre 5, après `git01`) |
| DNS | A et PTR `mon01.par1.medisphere.internal` (module `enregistrement-dns`) ; **CNAME** `smtp.par1.medisphere.internal` → `mon01` (comme `registry` → `reg01` au M13) |
| Mailpit | **1.31.6**, binaire amont `mailpit-linux-amd64.tar.gz` (releases GitHub du projet `axllent/mailpit`), empreinte SHA-256 relevée et écrite dans l'inventaire ; utilisateur système `mailpit` ; base `/var/lib/mailpit/mailpit.db`, 5000 messages au plus |
| Écoutes | SMTP **0.0.0.0:25** avec STARTTLS (certificat portant `mon01…` et `smtp…`) ; interface et API **0.0.0.0:8025** en HTTPS, authentification basique (fichier de mots de passe : comptes `<MOI>` et `wb-checks`) ; aucun relais, aucune authentification SMTP demandée |
| Certificat | rôle `certificats_acme` (id `mailpit`), noms `mon01.par1.medisphere.internal` et `smtp.par1.medisphere.internal`, renouvellement `cert-renewer@mailpit` qui redémarre Mailpit |
| Flux | GitLab (`git01`, VLAN 20) → `mon01:25` ; nœuds K8s (`K8S_CP`, `K8S_TRAV`) → `mon01:25` (alertes du M20-M21) ; MGMT et VPN → `mon01:8025` ; `ca01` → `mon01:80` (défi ACME) ; SSH depuis `adm01` et `runner01` |
| GitLab | `smtp.par1.medisphere.internal:25`, STARTTLS, certificat vérifié contre la racine MédiSphère, sans authentification ; expéditeur `gitlab@medisphere.internal`, réponse `plateforme@medisphere.internal` ; configuration par un fragment de `/etc/gitlab/` inclus dans `gitlab.rb`, posé par le rôle `gitlab_hote` |
| Sauvegarde | travail PBS du socle (stockage `pbs-par2`) qui inclut 1014 ; la base de Mailpit n'est **pas** précieuse (messages de lab), la VM l'est |

**Travail demandé**

*A. La VM*

1. Écris `socle/mon01.tf` sur le modèle de `reg01.tf` (sans disque de données) : VM, NetBox, A et PTR, CNAME `smtp`. Plan : une seule VM ajoutée, rien d'autre ne bouge. `apply` par le pipeline ; ordre de démarrage posé sur `pve01`.
2. Contrôle : `dig +short mon01.par1.medisphere.internal`, `dig +short -x 10.10.20.19`, `dig +short smtp.par1.medisphere.internal`, la VM dans NetBox (étiquettes, IP primaire), l'inventaire Ansible (`uv run ansible-inventory --graph role_supervision`).
3. Applique les rôles communs du socle à `mon01` (`site.yml --limit mon01`, comme pour `reg01`). Ajoute `mon01` au travail de sauvegarde PBS du socle et lance une première sauvegarde.

*B. Le rôle `mailpit`*

4. Lis l'aide de Mailpit (`mailpit --help`, sur une copie téléchargée dans `~/m19/e03/`) : repère les options d'écoute, de TLS (SMTP et interface), d'authentification de l'interface, de base de données et de rétention. Relève ce qui se passe par défaut (ports, adresses d'écoute, relais).
5. Écris le rôle **`mailpit`**. Exigences :
   - refus de tout autre système que Debian 13 ;
   - archive téléchargée dans un dossier versionné (`/opt/mailpit/<version>/`), **vérifiée par son empreinte SHA-256** (variable de l'inventaire), lien `/usr/local/bin/mailpit` ; changer de version = changer deux variables ;
   - utilisateur système `mailpit` sans shell ; dossiers de données et de configuration avec des droits minimaux ;
   - fichier de mots de passe de l'interface (format `htpasswd`, hachage bcrypt) construit depuis Ansible Vault (`critique`), jamais affiché ;
   - unité systemd **durcie** : service sans privilège qui écoute pourtant sur le port 25 (comment ?), système de fichiers en lecture seule sauf ses données, pas de nouveaux privilèges, appels système restreints ; options passées par un fichier d'environnement ou la ligne de commande, **sans** secret en argument ;
   - un contrôle final : le service répond sur 25 (bannière SMTP, `STARTTLS` annoncé) et sur 8025 (`/readyz`, HTTPS vérifié).
   Lis `systemd-analyze security mailpit` : quel score obtiens-tu ? Note les trois lignes qui le dégradent le plus et dis si tu peux les corriger.
6. Écris `playbooks/supervision.yml` (groupe `role_supervision`, qui recevra aussi Prometheus « témoin » au M21) : le certificat (rôle `certificats_acme`, `host_vars/mon01/certificats.yml`), le filtrage local (`pare_feu_local`, `host_vars/mon01/pare_feu_local.yml`), puis Mailpit. Applique-le par le pipeline protégé ; second passage `changed=0`.

*C. Les flux*

7. Ajoute à la matrice de la bordure (`group_vars/role_routeur/pare_feu.yml`) ce qui traverse une passerelle, et **seulement** cela. Pourquoi le flux `git01` → `mon01:25` n'a-t-il rien à faire sur la bordure, et où est-il filtré ?
   > ⚠️ **Attention** : une passerelle à la fois (`--limit gw01`, contrôle, puis `gw02`), `--check --diff` d'abord ; retour arrière : `git revert` de la MR et même playbook. Ne touche jamais à la passerelle active pendant qu'elle est en cours de modification.
8. Mets à jour `docs/socle/matrice-flux.md`.

*D. Tester Mailpit au niveau du protocole*

9. Depuis `adm01` :
   ```
   admin@adm01:~$ swaks --server smtp.par1.medisphere.internal:25 --tls \
                    --tls-ca-path /usr/local/share/ca-certificates/medisphere-root-ca.crt \
                    --from plateforme@medisphere.internal --to astreinte@medisphere.internal \
                    --header "Subject: M19-E03 essai swaks"
   admin@adm01:~$ openssl s_client -starttls smtp -connect smtp.par1.medisphere.internal:25 \
                    -servername smtp.par1.medisphere.internal -verify_return_error </dev/null 2>&1 | grep -E 'Verify|subject|issuer'
   ```
   Lis le dialogue SMTP de `swaks` : où le client bascule-t-il en TLS ? Que se passe-t-il si tu envoies sans `--tls` ? Et vers une adresse `@exemple.com` ?
10. Crée le fichier des vérifications `~/.config/workbook/mailpit-checks.env` (600 : `MAILPIT_USER=wb-checks`, `MAILPIT_PASSWORD=…`) et lis l'API : `GET /api/v1/info`, `GET /api/v1/search?query=subject:"M19-E03"`. Le compte `wb-checks` peut-il **supprimer** des messages ? Écris ta réponse et ce qu'elle implique dans `docs/socle/messagerie.md`.

*E. GitLab envoie ses courriels*

11. Étends le rôle `gitlab_hote` pour qu'il dépose des **fragments** de configuration (`/etc/gitlab/medisphere.d/<nom>.rb`, 600) et une ligne `from_file` par fragment dans `gitlab.rb`, puis déclenche `gitlab-ctl reconfigure` seulement si un fragment change. Écris le fragment `smtp` (adresse, port, STARTTLS, vérification du certificat, domaine HELO, expéditeur et adresse de réponse). Vérifie aussi que la racine MédiSphère est connue de GitLab (`/etc/gitlab/trusted-certs/`).
    > ⚠️ **Attention** : `gitlab-ctl reconfigure` redémarre des services de GitLab (quelques secondes d'indisponibilité de l'interface et de l'API, les pipelines en cours continuent). Fais-le hors d'un moment où tu as des pipelines importants en cours ; sauvegarde `/etc/gitlab/gitlab.rb` avant (`cp -a`), retour arrière : retirer la ligne `from_file` et relancer `reconfigure`.
12. Envoie un courriel de test depuis la console de GitLab, avec un sujet contenant **`M19-E03`**, à `plateforme@medisphere.internal` :
    ```
    root@git01:~# gitlab-rails runner "Notify.test_email('plateforme@medisphere.internal', 'M19-E03 test GitLab', 'Envoi depuis git01').deliver_now"
    ```
    Retrouve-le dans l'interface de Mailpit, lis ses en-têtes (`Received`, `From`). Puis provoque un vrai courriel : renseigne l'adresse `<MOI>@medisphere.internal` sur ton compte GitLab (confirmation reçue dans Mailpit), et active les notifications d'échec de pipeline.
13. Documente `docs/socle/messagerie.md` : rôle de `mon01`, adresses du lab, comptes, ce que Mailpit ne fait pas (relais, rétention longue), procédure de test, et ajoute `mon01` à la fiche des hôtes du socle et au registre des secrets (mots de passe de l'interface).

**Critères de réussite**
- [ ] `mon01` (1014) existe par OpenTofu : 2 vCPU, 3 Go, étiquettes `socle` et `role-supervision`, pool `lab`, démarrage avec `pve01` ; A, PTR et CNAME `smtp` résolus ; une sauvegarde PBS de 1014 existe.
- [ ] Mailpit 1.31.6 tourne sous l'utilisateur `mailpit`, sans privilège (pas de `root`, `NoNewPrivileges`), écoute 25 et 8025 ; le binaire correspond à l'empreinte de l'inventaire.
- [ ] Le certificat présenté sur 25 (STARTTLS) et 8025 est émis par la racine MédiSphère, porte `smtp.par1.medisphere.internal`, et se vérifie depuis `adm01` ; l'API refuse une requête sans mot de passe.
- [ ] Un message dont le sujet contient `M19-E03`, envoyé par GitLab (`gitlab@medisphere.internal`), est présent dans Mailpit ; GitLab est configuré en STARTTLS vérifié (pas de `openssl_verify_mode` à `none`).
- [ ] Le code est sur `main` (`socle/mon01.tf`, rôle `mailpit`, playbook, `host_vars/mon01/`, extension de `gitlab_hote`, matrice de la bordure) ; `docs/socle/messagerie.md` et la matrice des flux sont à jour.

**Vérification** : `lab/bin/check 19 03`

<details><summary>Indice 1</summary>

Pour le port 25 sans root : regarde `AmbientCapabilities=` et `CapabilityBoundingSet=` dans `man systemd.exec`. Le rôle `certificats_acme` pose ses fichiers avec un **groupe** propriétaire de la clé : celui de l'utilisateur du service. Pour la CNAME, relis `registry` dans `reg01.tf`.
</details>

<details><summary>Indice 2</summary>

Mailpit lit ses options aussi dans des variables d'environnement `MP_…` (voir sa documentation « Runtime options ») : un fichier `EnvironmentFile=` en 640 évite des arguments longs, mais aucune de ces options n'est secrète (le mot de passe est dans le fichier `htpasswd`). Pour GitLab, la page « SMTP settings » du paquet Linux a un exemple « serveur interne sans authentification » : pars de là et **remets** la vérification du certificat.
</details>

<details><summary>Indice 3</summary>

`gitlab.rb` est du Ruby : la documentation des paquets Linux décrit `from_file "/chemin"` pour inclure un fichier. Le module Ansible `lineinfile` avec `insertafter: EOF` suffit pour la ligne ; un gestionnaire (`handler`) lance `reconfigure`. Pour savoir ce que GitLab a réellement retenu, lis le fichier de réglages SMTP qu'il génère sous `/var/opt/gitlab/gitlab-rails/etc/`.
</details>

**Pour aller plus loin** (facultatif) : active les métriques Prometheus de Mailpit (option `--enable-prometheus`) sur une adresse locale : le M21 les collectera. Et lis la page « Chaos » de Mailpit : elle permet de simuler des erreurs SMTP, utile pour tester le comportement de GitLab ou d'Alertmanager quand la messagerie refuse.

---

### M19-E04 — Un runner GitLab dans Kubernetes  `LAB` `★★`

> **Ticket PLAT-2004** — *De : Karim Benali* — *Copie : Julien Petit*
> Premier runner dans le cluster : `k8s-par1`, runner d'instance, étiquettes `k8s` et `kubernetes`, il ne prend **que** les jobs qui le demandent. Le jeton se crée par l'API et va au coffre, pas dans un fichier de valeurs. Installation par notre Helmfile, toutes les images par Harbor (y compris celles de GitLab : il faut un cache de plus), les jobs dans `ci-jobs` avec le compte `ci-job`, des ressources par défaut raisonnables et des maximums. Pour l'essayer : un projet `formation/ci-labo` avec un premier pipeline.
>
> **Ticket SEC-2004** — *De : Sophie Laurent*
> Le jeton d'un runner, c'est la possibilité de recevoir les jobs de toute l'instance, variables protégées comprises. Je veux savoir où il est, qui peut le lire, et comment on le change.

**Objectifs pédagogiques**
- Créer un runner par l'API avec un jeton `glrt-` et comprendre ce qui a changé par rapport aux jetons d'enregistrement.
- Installer GitLab Runner par Helmfile avec l'exécuteur Kubernetes : gestionnaire et jobs dans deux espaces, RBAC, confiance TLS, images par Harbor.
- Écrire la configuration TOML de l'exécuteur Kubernetes (`[runners.kubernetes]`) en connaissant chaque clé.
- Créer un Secret Kubernetes depuis Ansible Vault par un outil réutilisable.

**Prérequis** : M19-E02 ; M13-E04 (caches de Harbor, état `registre`) ; M17-E10 (Helmfile de `plateforme/k8s`) ; M16-E06 (`outils/ceph-csi-secrets.sh`, modèle de l'outil de Secrets) ; M01-E20 (jetons GitLab, registre des secrets).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Harbor | nouveau cache **`gitlab`** : point d'accès `registry.gitlab.com` (type « Docker Registry »), projet public, quota 10 Gio, dans `registre/caches.tf` |
| Runner (GitLab) | runner d'**instance**, description **`k8s-par1`**, `tag_list` `k8s,kubernetes`, `run_untagged` faux, non verrouillé, `access_level` `not_protected`, délai maximal 3600 s ; créé par `POST /api/v4/user/runners` avec un jeton personnel à courte durée de portée `create_runner` (+ `admin_mode`) |
| Secret | Vault `critique` : `secrets/gitlab-runner.yml` de `plateforme/k8s` (`gitlab_runner_jeton`) ; Secret **`gitlab-runner/gitlab-runner`** (clés `runner-token` et `runner-registration-token` vide) et **`gitlab-runner/gitlab-runner-certs`** (racine MédiSphère, fichier `git01.par1.medisphere.internal.crt`) créés par **`outils/secrets-k8s.sh`** |
| Release | **`gitlab-runner`** (espace `gitlab-runner`), chart `gitlab/gitlab-runner` **0.93.0** (dépôt `https://charts.gitlab.io`), fichier `releases/50-ci.yaml.gotmpl`, valeurs `composants/gitlab-runner/values.yaml` ; image du gestionnaire `registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner:alpine-v19.4.0@sha256:<EMPREINTE>` |
| Exécuteur | `namespace = "ci-jobs"`, `service_account = "ci-job"`, jeton non monté ; image par défaut `registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim@sha256:<EMPREINTE>` ; *helper* `registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0` ; demandes/limites du conteneur `build` 250m/512 Mi et 2/2 Gi, surchargeables jusqu'à 4/4 Gi, *helper* 100m/128 Mi et 1/512 Mi ; `poll_timeout` 600 s ; `concurrent` 6 ; étiquette de pod `medisphere.internal/ci: job` |
| Flux | travailleurs (`K8S_TRAV`) → `git01:443` (gestionnaire et *helper*), nouveau sur la bordure ; travailleurs → `reg01:443` existant (M13) |
| Projet | **`formation/ci-labo`** (groupe `formation`, `main` protégée, fusion par MR) ; contenu de départ : [`ressources/E04-ci-labo/`](../ressources/E04-ci-labo/) ; pipeline de E04 : un job `bonjour` sur l'étiquette `k8s` qui affiche l'identité du pod |

**Travail demandé**

*A. Les images de GitLab dans Harbor*

1. Ajoute le cache `gitlab` à l'état `registre` (MR, plan : un point d'accès et un projet, rien d'autre). Puis relève les empreintes à travers Harbor :
   ```
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' \
       docker://registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner:alpine-v19.4.0
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' \
       docker://registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0
   ```
   Pourquoi le chart, laissé à ses valeurs par défaut, irait-il chercher ces images directement sur `registry.gitlab.com` ? Qu'est-ce qui l'en empêcherait dans `ci-jobs`, et pas dans `gitlab-runner` ?

*B. Le runner et son jeton*

2. Crée un jeton personnel **dédié** (portées `create_runner` et `admin_mode`, expiration le lendemain) et crée le runner par l'API. La réponse contient le jeton une seule fois : il va **directement** dans le Vault, sans passer par un fichier en clair ni par l'historique du shell.
   ```
   admin@adm01:~$ curl -sf --request POST "https://git01.par1.medisphere.internal/api/v4/user/runners" \
       -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-create-runner.token)") \
       --data runner_type=instance_type --data description=k8s-par1 --data tag_list=k8s,kubernetes \
       --data run_untagged=false … | jq -r '.id, .token' | …
   ```
   Termine la commande (où va l'identifiant ? où va le jeton ?), puis révoque le jeton personnel dédié. Dans l'interface (*Admin → CI/CD → Runners*), que vois-tu du runner avant son premier contact ?
3. Écris **`outils/secrets-k8s.sh`** dans `plateforme/k8s`, sur le modèle de `outils/ceph-csi-secrets.sh` (M16-E06), mais **générique** : une table « composant → Secrets à créer », chaque clé venant d'une variable de `secrets/<composant>.yml` (Vault `critique`) ou d'un fichier public (la racine MédiSphère) ; modes `appliquer` et `verifier` (par empreinte, sans jamais afficher de valeur) ; refus d'un fichier non chiffré ou chiffré sous une autre identité. Il servira à tout le bloc (agent GitLab, SonarQube, Jenkins…). Crée `secrets/gitlab-runner.yml`, puis applique.

*C. La release*

4. Lis le `values.yaml` du chart 0.93.0 (`helm show values gitlab/gitlab-runner --version 0.93.0`) : repère `gitlabUrl`, `certsSecretName`, `runners.secret`, `runners.config`, `runners.jobNamespace`, `rbac`, `serviceAccount`, `securityContext`, `podSecurityContext`, `image`, `concurrent`, `unregisterRunners`. Puis la référence de `[runners.kubernetes]` dans la documentation de l'exécuteur Kubernetes.
5. Écris `composants/gitlab-runner/values.yaml` et la release dans `releases/50-ci.yaml.gotmpl` (avec le dépôt `gitlab` dans `_communs.yaml`). Exigences :
   - aucun secret dans les valeurs ; jeton par `runners.secret`, racine par `certsSecretName` ;
   - gestionnaire en `restricted` (contexte de sécurité du pod et du conteneur explicites), ressources déclarées ;
   - RBAC créé par le chart, **limité à `ci-jobs`**, avec la liste minimale de droits de la documentation (pods, attach, exec, log, Secrets, compte de service, services) : pas de jeu de règles par défaut ;
   - `[runners.kubernetes]` : espace, compte de service, jeton non monté, images par Harbor (*helper* compris), `allowed_images` limité à Harbor, ressources par défaut et maximums de surcharge, `poll_timeout`, étiquettes de pod.
   Rends le tout avant d'appliquer : `helmfile -e par1 -l composant=gitlab-runner template | less` ; lis le ConfigMap rendu (`config.template.toml`) et le Role.
6. Ouvre le flux de la bordure (matrice, une passerelle à la fois, avec l'avertissement habituel), puis `helmfile -e par1 -l composant=gitlab-runner diff` et `apply`. Contrôle :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n gitlab-runner get pods,role,rolebinding
   admin@adm01:~$ kubectl --context k8s-par1 -n gitlab-runner logs deploy/gitlab-runner | head -30
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get role,rolebinding
   ```
   Dans l'interface, le runner est-il « en ligne » ? Combien a-t-il de **gestionnaires** (*runner managers*), et comment s'appelle celui-ci ?

*D. Premier pipeline*

7. Crée `formation/ci-labo` (groupe `formation` existant depuis le M01, `main` protégée, fusion par MR seulement) et pousse le contenu de [`ressources/E04-ci-labo/`](../ressources/E04-ci-labo/). Écris un premier `.gitlab-ci.yml` : un seul job `bonjour`, étiqueté `k8s`, qui affiche le nom d'hôte (c'est le nom du pod), l'utilisateur (`id`), `CI_RUNNER_DESCRIPTION`, `CI_RUNNER_TAGS`, et qui **prouve** qu'aucun jeton de compte de service n'est monté (le job doit réussir dans ce cas, échouer sinon).
8. Pendant que le job tourne, regarde le pod :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get pods -w
   ```
   Lis le journal du job dans GitLab : quelles lignes viennent du runner, lesquelles de ton script ?
9. Pousse un second commit qui ajoute un job **sans** étiquette. Que devient-il ? Corrige comme tu l'as décidé à la question 14 du test de positionnement.
10. Mets à jour le registre des secrets (jeton `glrt-` de `k8s-par1` : où, qui le lit, comment le changer) et la matrice des flux.

**Critères de réussite**
- [ ] Le cache Harbor `gitlab` existe (état `registre`) ; l'image du gestionnaire et le *helper* sont tirés par Harbor.
- [ ] Le runner d'instance `k8s-par1` (étiquettes `k8s`, `kubernetes`, sans jobs non étiquetés) est **en ligne**, avec au moins un gestionnaire ; son jeton n'apparaît dans aucun dépôt.
- [ ] Le Deployment `gitlab-runner` est prêt dans `gitlab-runner` ; sa configuration place les jobs dans `ci-jobs` avec le compte `ci-job` et des images de Harbor ; le Role du gestionnaire est dans `ci-jobs`.
- [ ] Le dernier pipeline de `formation/ci-labo` a réussi et au moins un de ses jobs a été exécuté par le runner `k8s-par1`.
- [ ] Les travailleurs joignent `git01:443` ; `outils/secrets-k8s.sh`, `secrets/gitlab-runner.yml` (chiffré), la release et les valeurs sont sur `main` de `plateforme/k8s`.

**Vérification** : `lab/bin/check 19 04`

<details><summary>Indice 1</summary>

Le chart construit l'image du gestionnaire à partir de `image.registry`, `image.image` et `image.tag` ; le *helper* se règle dans le TOML (`helper_image`). Le jeton créé par `POST /user/runners` n'a plus besoin de `gitlab-runner register` « classique » : le chart l'utilise tel quel (il appelle `register` avec ce jeton, qui ne fait que l'écrire dans `config.toml`). Les étiquettes et `run_untagged` sont alors des propriétés **du runner dans GitLab**, plus du gestionnaire.
</details>

<details><summary>Indice 2</summary>

Le chart crée le Role dans `coalesce(runners.jobNamespace, namespace, Release.Namespace)` : si tu laisses `runners.jobNamespace` vide, il est créé au mauvais endroit. Lis `templates/role.yaml`. Pour `rbac.rules`, chaque entrée a `apiGroups`, `resources`, `verbs` ; une liste vide donne… tout (lis le gabarit). Le jeton d'un compte de service, quand il est monté, est sous `/var/run/secrets/kubernetes.io/serviceaccount/` : un `test ! -e …` suffit à la preuve.
</details>

<details><summary>Indice 3</summary>

Le fichier `gitlab-runner-certs` doit s'appeler **`<nom d'hôte de GitLab>.crt`** : le gestionnaire y cherche la CA de ce serveur, puis la transmet au *helper* (`CI_SERVER_TLS_CA_FILE`). Pour ne pas laisser le jeton dans l'historique : `HISTCONTROL=ignorespace` et une commande commençant par une espace ne suffisent pas pour la sortie ; dirige la sortie de `jq` vers `ansible-vault encrypt_string --stdin-name` ou vers `ansible-vault edit`.
</details>

**Pour aller plus loin** (facultatif) : lis la section « Configure runner API permissions » de l'exécuteur Kubernetes et repère les droits qui n'existent que pour des fonctions que tu n'utilises pas (espace par job, environnements suspendables, PDB par job) : ce sont ceux qu'on retire en premier (palier 3, E24).

---

### M19-E05 — Anatomie d'un job dans Kubernetes  `LAB` `★★`

> **Ticket PLAT-2005** — *De : Nadia Roussel*
> Quand un job plantera à 3 h du matin, mes collègues d'astreinte ouvriront le journal du job et ne comprendront rien de ce qui se passe **avant** le script. Je veux une page qui explique un pod de job : ce qu'il contient, qui fait quoi, dans quel ordre, combien de temps il vit, où regarder quand ça casse. Avec un vrai pod disséqué, pas un schéma recopié.

**Objectifs pédagogiques**
- Identifier les conteneurs d'un pod de job (`init-permissions`, `build`, `helper`, services) et le rôle de chacun.
- Comprendre la stratégie d'exécution *attach* et ce qu'elle implique (journaux, signaux, fin de job).
- Surcharger les ressources d'un job par les variables `KUBERNETES_*`, dans les limites du runner.
- Corréler un job GitLab et un pod Kubernetes (étiquettes, annotations, événements).

**Prérequis** : M19-E04.
**Durée indicative** : 2 h.

**Contexte technique** : le runner `k8s-par1` autorise la surcharge des ressources du conteneur `build` jusqu'à 4 CPU et 4 Gi (E04). Les pods de job portent des étiquettes `project.runner.gitlab.com/…`, des annotations `job.runner.gitlab.com/…` et l'étiquette `medisphere.internal/ci: job`.

**Travail demandé**

1. Ajoute à `ci-labo` un job **`anatomie`** (étiquette `k8s`) qui :
   - déclare un service (une image de Harbor, par exemple `valkey`) et le joint ;
   - demande, par des variables de job, 500m CPU et 1 Gi de mémoire pour le conteneur `build` ;
   - attend assez longtemps (`sleep 120`) pour que tu puisses observer le pod ;
   - écrit dans un fichier `anatomie.txt` : le nom du pod, l'utilisateur et ses groupes (`id`), la liste des montages (`/proc/self/mounts` filtré), les variables `CI_`/`KUBERNETES_` sans aucun secret, le contenu de `/etc/resolv.conf`, la limite mémoire vue par le conteneur (`/sys/fs/cgroup/memory.max`) ;
   - publie `anatomie.txt` comme **artefact** (une semaine).
2. Pendant le `sleep`, dissèque le pod :
   ```
   admin@adm01:~$ P=$(kubectl --context k8s-par1 -n ci-jobs get pods -l medisphere.internal/ci=job -o name | head -1)
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get $P -o yaml | less
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs describe $P
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get events --field-selector involvedObject.name=${P#pod/}
   ```
   Relève : les conteneurs d'initialisation et les conteneurs, leur image, leur commande, leurs ressources, leur contexte de sécurité ; les volumes (lesquels sont partagés entre `build` et `helper`, et pourquoi) ; le compte de service et `automountServiceAccountToken` ; la classe QoS ; les étiquettes et annotations du runner ; le nœud.
3. Explique la stratégie *attach* : quel processus tourne dans le conteneur `build` avant que ton script commence, et comment le gestionnaire lui envoie-t-il les étapes du job ? Que verrais-tu avec `kubectl -n ci-jobs logs $P -c build` ? Avec `-c helper` ?
4. Mesure le cycle de vie : dans le journal du job, repère les lignes « Preparing environment », « Getting source from Git repository », « Executing step_script », « Uploading artifacts », « Cleaning up » ; relève leurs horodatages (journal téléchargé avec horodatage, ou chronomètre). Combien de temps pour obtenir un pod prêt ? Combien de temps le pod survit-il après la fin du job ?
5. Essaie de surcharger la mémoire à 8 Gi : que dit le job ? Que se passerait-il si le quota de `ci-jobs` était épuisé, et en quoi est-ce différent d'un nœud sans place libre (lis le `poll_timeout` du runner : dans lequel des deux cas sert-il) ? Ne provoque pas la panne : le palier 4 s'en charge.
6. Rédige **`docs/livraison/ci/anatomie-job.md`** dans `plateforme/medisphere` : schéma du pod, rôle de chaque conteneur, chronologie d'un job, correspondance « ligne du journal ↔ phase ↔ conteneur », où regarder (événements, `kubectl describe`, journal du gestionnaire) selon le symptôme, et les limites (ce qu'un job peut et ne peut pas faire). MR, relecture par Nadia (simulée), fusion.

**Critères de réussite**
- [ ] Le dernier pipeline de `ci-labo` contient un job `anatomie` réussi, exécuté par `k8s-par1`, avec un artefact `anatomie.txt` (expiration d'une semaine au plus).
- [ ] `anatomie.txt` montre une limite mémoire de 1 Gi (1073741824) pour le conteneur `build`, et aucun jeton de compte de service monté.
- [ ] `docs/livraison/ci/anatomie-job.md` est sur `main` de `plateforme/medisphere` et décrit `init-permissions`, `build`, `helper`, les services et la stratégie *attach*.

**Vérification** : `lab/bin/check 19 05`

<details><summary>Indice 1</summary>

Les variables de surcharge des ressources s'appellent comme les clés du TOML, en majuscules, préfixées par `KUBERNETES_` : `memory_limit` ↔ `KUBERNETES_MEMORY_LIMIT`. Elles ne sont acceptées que si le runner déclare le maximum correspondant (`…_overwrite_max_allowed`). Un service se joint par `localhost` dans un pod : pourquoi ?
</details>

<details><summary>Indice 2</summary>

Le compte de service n'a pas de jeton monté : `ls /var/run/secrets/kubernetes.io/` doit échouer. Les montages partagés entre `build` et `helper` sont des volumes `emptyDir` : le dépôt cloné, les scripts générés, les journaux. `kubectl get pod -o jsonpath='{.status.qosClass}'` donne la classe QoS.
</details>

**Pour aller plus loin** (facultatif) : active `FF_PRINT_POD_EVENTS` dans un job (variable) et compare le journal du job avec et sans : quelles lignes apparaissent ? Quel droit RBAC cette option demande-t-elle au gestionnaire (relis la table « Configure runner API permissions ») ? Ton Role de E04 le donne-t-il déjà, et pour quelle autre fonction ?

---

### M19-E06 — Pipelines : stages, `needs`, `rules` et `workflow`  `LAB` `★★`

> **Ticket DEV-2006** — *De : Julien Petit*
> Nos pipelines font tout, tout le temps, dans l'ordre des stages : un changement de README relance les tests, chaque push sur une branche avec une MR ouverte crée **deux** pipelines, et quand on pousse trois commits de suite, trois pipelines complets tournent pour rien. Fais-moi un pipeline d'exemple dans `ci-labo` qui ne lance que ce qui est utile, le plus tôt possible, une seule fois. On copiera la recette.

**Objectifs pédagogiques**
- Construire un pipeline en graphe (`needs`) et mesurer le gain sur un pipeline en stages.
- Écrire des `rules` (`if`, `changes`, `when`) et des `workflow:rules` qui évitent les doublons branche + MR.
- Utiliser `interruptible` et `workflow:auto_cancel` pour annuler le travail devenu inutile.
- Lire un pipeline par l'API (jobs, sources, horodatages).

**Prérequis** : M19-E05.
**Durée indicative** : 2 h 30.

**Contexte technique**

Pipeline cible de `ci-labo` (tous les jobs sur l'étiquette `k8s`, image `uv` de Harbor épinglée par empreinte, celle de `mediagenda/api` au M13) :

| Stage | Job | Rôle | Contraintes |
|---|---|---|---|
| `lint` | `ruff` | `uv run --with ruff ruff check` | sur tout changement de `src/**`, `tests/**`, `pyproject.toml`, `uv.lock` |
| `lint` | `docs` | vérifie que `docs/` est du Markdown lisible (une commande simple) | seulement si `docs/**` change |
| `test` | `tests` | `uv run pytest` | mêmes fichiers que `ruff` ; démarre **sans attendre** `docs` |
| `build` | `paquet` | `uv build`, artefact `dist/` | après `tests` seulement |
| `rapport` | `resume` | affiche un résumé du pipeline | toujours, même si un job a échoué ; ne bloque rien |

Règles du pipeline : pipelines de **MR**, de **`main`** et des **étiquettes** seulement ; jamais deux pipelines pour un même commit (branche + MR) ; pipelines **planifiés** et déclenchés **à la main** (interface « Run pipeline ») autorisés ; jobs interruptibles sauf ceux qui publient ; annulation automatique des pipelines redondants sur une même branche.

**Travail demandé**

1. Écris d'abord la version **en stages** (sans `needs`, sans `rules`) ; pousse sur une branche, ouvre une MR. Compte les pipelines créés pour ce commit, relève la durée et l'ordre de démarrage des jobs (`started_at`) par l'API :
   ```
   admin@adm01:~$ api() { curl -sf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") \
                     "https://git01.par1.medisphere.internal/api/v4/$1"; }
   admin@adm01:~$ P=$(api "projects?search=ci-labo" | jq '.[0].id')
   admin@adm01:~$ api "projects/$P/pipelines?per_page=5" | jq -r '.[] | [.id, .source, .ref, .sha[0:8], .status] | @tsv'
   admin@adm01:~$ api "projects/$P/pipelines/<ID>/jobs" | jq -r '.[] | [.name, .stage, .started_at, .finished_at] | @tsv'
   ```
2. Passe en **graphe** : `needs` pour que `tests` et `ruff` démarrent ensemble, que `paquet` n'attende que `tests`, que `resume` tourne en dernier sans dépendre du succès des autres. Mesure de nouveau. Dans l'interface, compare la vue « Jobs dependencies » et la vue par stages.
3. Écris les **`rules`** de chaque job selon le tableau. Teste quatre cas sur une branche avec MR ouverte : changement de `docs/` seul, de `src/` seul, des deux, de `README.md` seul. Pour chacun, quels jobs apparaissent ? Explique le cas `README.md`.
4. Écris les **`workflow:rules`** : MR, `main`, étiquettes, planification et lancement manuel, mais pas de pipeline de branche quand une MR est ouverte. Pousse un commit sur une branche **sans** MR, puis ouvre la MR, puis pousse encore : combien de pipelines, de quelle source, à chaque fois ?
5. Ajoute `interruptible: true` (par défaut, avec une exception justifiée) et `workflow:auto_cancel` (`on_new_commit`). Pousse trois commits rapprochés sur la branche de la MR : que deviennent les deux premiers pipelines ?
6. Piège à comprendre : sur `main`, `rules: changes:` compare avec quoi ? Que se passe-t-il pour un pipeline planifié ou lancé à la main ? Corrige si besoin pour qu'un pipeline planifié exécute **tous** les jobs.
7. Fusionne la MR. Écris dans `~/m19/e06/` le tableau des gains (durée en stages vs en graphe, nombre de pipelines évités) : il servira à E23.

**Critères de réussite**
- [ ] Le `.gitlab-ci.yml` de `main` a des `workflow:rules`, `workflow:auto_cancel`, au moins un job avec `needs` et des `rules` avec `changes` et `if` sur `CI_PIPELINE_SOURCE`.
- [ ] Le dernier pipeline de `main` a réussi ; au moins un job y a démarré avant la fin d'un job d'un stage précédent (graphe effectif).
- [ ] Parmi les 30 derniers pipelines de `ci-labo`, aucun commit n'a à la fois un pipeline de branche (hors `main`) et un pipeline de MR.

**Vérification** : `lab/bin/check 19 06`

<details><summary>Indice 1</summary>

La documentation de `workflow` donne un exemple « Switch between branch pipelines and merge request pipelines » qui utilise `$CI_OPEN_MERGE_REQUESTS`. `CI_PIPELINE_SOURCE` vaut `push`, `merge_request_event`, `schedule`, `web`, `api`, `trigger`, `pipeline`… : lis la liste.
</details>

<details><summary>Indice 2</summary>

Sur un pipeline de **branche**, `changes` compare avec le commit précédent de la branche (et vaut « vrai » pour une nouvelle branche ou quand GitLab ne sait pas comparer) ; sur un pipeline de **MR**, avec la branche cible. Pour un pipeline planifié, `changes` est toujours vrai… ou toujours faux ? Lis « `rules:changes` » dans la référence. `needs: [{job: x, optional: true}]` permet de dépendre d'un job qui peut ne pas exister dans le pipeline.
</details>

<details><summary>Indice 3</summary>

Un job qui doit tourner même après un échec : `when: always` (dans ses `rules` ou au niveau du job). Avec `needs`, ce sont les jobs **cités** (et non plus les stages précédents) dont le statut compte : un job en `on_success` qui dépend d'un job échoué ou **sauté** est sauté, un job en `always` démarre quand même. Réfléchis à ce dont `resume` a besoin : de **tous** les jobs, ou seulement de quelques-uns ?
</details>

**Pour aller plus loin** (facultatif) : `gitlab-ci-local` (4.76, facultatif) exécute un `.gitlab-ci.yml` sur ton poste : essaie-le sur `ci-labo` et note ce qu'il ne sait pas simuler (`rules:changes` d'une MR, variables protégées, exécuteur Kubernetes).

---

### M19-E07 — Variables, artefacts, caches et environnements  `LAB` `★★`

> **Ticket PLAT-2007** — *De : Karim Benali* — *Copie : Julien Petit*
> Les runners Kubernetes ne gardent rien d'un job à l'autre : chaque pipeline retélécharge toutes les dépendances. Il nous faut un **cache partagé** sur `s3-01`, avec une identité à lui. Profites-en pour montrer dans `ci-labo` comment on passe une valeur d'un job à l'autre, comment on garde un résultat, et comment on déclare des déploiements `dev`, `recette`, `prod` dans GitLab sans pouvoir en lancer deux en même temps sur la même cible.

**Objectifs pédagogiques**
- Maîtriser l'ordre de priorité des variables, les variables de type fichier et le contrôle du développement (`expand`).
- Distinguer artefacts et cache ; produire un rapport `dotenv` ; régler les durées de vie.
- Configurer un cache distribué S3 pour l'exécuteur Kubernetes, avec une identité dédiée et une clé de cache par fichier de verrou.
- Déclarer des environnements (`environment:name`, `url`, `deployment_tier`) et sérialiser des déploiements (`resource_group`).

**Prérequis** : M19-E06 ; M16-E16 (identités et compartiments SeaweedFS de `s3-01`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| S3 | `s3-01` (`https://s3-01.par1.medisphere.internal:8333`), compartiment **`ci-cache`** sans versionnage, identité **`ci-cache`** (Read, Write, List sur `ci-cache` seulement), clés en Vault `lab` (`host_vars/s3-01/vault.yml`) et dans `~/.config/workbook/s3-ci-cache.env` (600 : `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) |
| Runner | `[runners.cache]` : `Type = "s3"`, `Path = "k8s-par1"`, `Shared = false`, `[runners.cache.s3]` `ServerAddress`, `BucketName`, `BucketLocation = "us-east-1"`, `PathStyle`, sans clé dans le TOML ; clés par le Secret **`gitlab-runner/ci-cache-s3`** (`accesskey`, `secretkey`, par `outils/secrets-k8s.sh`, variables `ci_cache_cle_acces`, `ci_cache_cle_secrete` de `secrets/gitlab-runner.yml`) et `runners.cache.secretName` |
| Confiance TLS des jobs | la racine MédiSphère (ConfigMap **`medisphere-racine`** de `ci-jobs`) montée dans les conteneurs du job sous `/etc/medisphere/ca/`, et ajoutée aux autorités du *helper* par la variable d'environnement `SSL_CERT_DIR` posée par le runner : c'est le *helper* qui parle à `s3-01` |
| Flux | travailleurs → `s3-01:8333` déjà ouvert (M15-E34) |
| `ci-labo` | job `version` (rapport `dotenv` : `VERSION`), cache `uv` clé par `uv.lock`, jobs `deployer-dev`, `deployer-recette`, `deployer-prod` (simulés : ils écrivent un fichier) sur les environnements `dev`, `recette`, `prod`, tiers `development`, `staging`, `production`, URL de l'artefact publié, `resource_group` par environnement |

**Travail demandé**

*A. Les variables*

1. Dans `ci-labo`, définis `NIVEAU` à quatre endroits (global dans le fichier, job, projet, lancement manuel) et vérifie l'ordre de priorité avec un job qui l'affiche. Puis :
   - une variable de projet de **type fichier** `LABO_CONFIG` (un petit fichier INI) : que contient la variable dans le job ? Lis le fichier ;
   - une variable de projet `LABO_CHEMIN` dont la valeur est `$CI_PROJECT_DIR/labo` : comment empêcher son **développement** (*expand*) ? Montre les deux comportements, et dis pourquoi c'est important pour un mot de passe qui contient un `$`.
   Range ces observations dans `~/m19/e07/variables.md`.
2. Ajoute une variable **protégée et masquée** `LABO_SECRET`. Lance un pipeline de MR (branche non protégée) et un pipeline de `main` : où existe-t-elle ? Que montre le journal quand le script fait `echo "$LABO_SECRET" | base64` ? Qu'en conclus-tu sur le masquage ?

*B. Artefacts*

3. Ajoute le job `version` (premier job du pipeline, stage `lint`) qui calcule une version (`0.1.0-<sha court>` sauf sur une étiquette `vX.Y.Z`) et la transmet par un rapport **`dotenv`**. `paquet` doit l'utiliser (nom du fichier produit). Règle `expire_in` partout : quelle durée pour `dist/`, pour `anatomie.txt`, pour le rapport `dotenv` ? Et `artifacts:when` pour `tests` (rapport JUnit) ?
4. Dans l'interface, regarde les artefacts d'un job : que se passe-t-il pour ceux du **dernier** pipeline réussi d'une branche quand ils expirent (réglage « Keep artifacts from most recent successful jobs ») ?

*C. Le cache S3*

5. Crée l'identité et le compartiment dans le rôle `seaweedfs` (`host_vars/s3-01/seaweedfs.yml` et `vault.yml`, comme au M16-E16), le fichier `s3-ci-cache.env`, et vérifie l'accès depuis `adm01` :
   ```
   admin@adm01:~$ source ~/.config/workbook/s3-ci-cache.env
   admin@adm01:~$ curl -sf --aws-sigv4 "aws:amz:us-east-1:s3" -K <(printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY") \
                    "https://s3-01.par1.medisphere.internal:8333/ci-cache?list-type=2" | head -c 400; echo
   ```
   Essaie la même requête sur un autre compartiment (`tofu-state`) : que répond `s3-01` ?
6. Ajoute les clés à `secrets/gitlab-runner.yml` et la table de `outils/secrets-k8s.sh` (Secret `ci-cache-s3`), la ConfigMap `medisphere-racine` dans `espaces/ci-jobs/`, puis `[runners.cache]`, `runners.cache.secretName` et le montage de la racine dans les valeurs du runner. `helmfile diff`, `apply`. Le gestionnaire redémarre-t-il ? Pourquoi est-ce sans danger pour les jobs en cours (relis `terminationGracePeriodSeconds`) ?
7. Dans `ci-labo`, mets `tests` et `ruff` en cache de **`uv`** (`UV_CACHE_DIR` dans le projet), clé calculée **à partir de `uv.lock`** (`cache:key:files`), politique `pull-push` pour un seul job et `pull` pour l'autre. Lance deux pipelines de suite : dans le journal, trouve « Checking cache for … », la clé, et la ligne qui prouve que le second a **réutilisé** le cache. Quelle durée gagnes-tu sur `uv sync` ?
8. Modifie `uv.lock` (ajoute une dépendance de développement) : la clé change-t-elle ? Que deviennent les anciens objets dans `ci-cache` ? Note la question du ménage (le runner ne supprime rien).

*D. Environnements et `resource_group`*

9. Ajoute `deployer-dev` (automatique sur `main`), `deployer-recette` (manuel sur `main`) et `deployer-prod` (manuel, seulement sur une étiquette `vX.Y.Z`) : chacun écrit `deploiement.txt` (version, environnement, date) en artefact, déclare son environnement (`name`, `url` vers l'artefact publié, `deployment_tier`) et un `resource_group` par environnement. Aucun n'est interruptible.
10. Lance deux fois `deployer-recette` à quelques secondes d'intervalle (deux pipelines) : que montre le second job (« waiting for resource ») ? Puis regarde *Operate → Environments* : historique des déploiements, bouton de retour (*re-deploy*). Qu'est-ce qui empêche ici un développeur de lancer `deployer-prod` ? Et que manque-t-il, que l'édition Premium apporterait ?
11. Pose une étiquette `v0.1.0` sur `main` (par l'interface), lance `deployer-prod`. Ajoute au registre des secrets l'identité `ci-cache` et à la matrice des flux une note « cache des runners » sur la ligne `K8S_TRAV` → `s3-01:8333`.

**Critères de réussite**
- [ ] L'identité `ci-cache` lit et liste le compartiment `ci-cache` de `s3-01` (avec `s3-ci-cache.env`, en 600) et **ne lit pas** un autre compartiment.
- [ ] La configuration du runner déclare un cache S3 vers `s3-01`, compartiment `ci-cache`, sans clé écrite dans le TOML ni dans les valeurs (Secret `ci-cache-s3`) ; des objets de cache de `ci-labo` existent dans `ci-cache`.
- [ ] Dans les pipelines récents de `ci-labo`, un job a **réutilisé** un cache dont la clé est calculée à partir d'un fichier.
- [ ] Les environnements `dev`, `recette` et `prod` de `ci-labo` existent avec leurs tiers (`development`, `staging`, `production`) et une URL ; au moins `dev` a un déploiement réussi.

**Vérification** : `lab/bin/check 19 07`

<details><summary>Indice 1</summary>

La page « CI/CD variable precedence » de la documentation donne l'ordre. Pour le développement : case « Expand variable reference » de la variable (API : `raw: true`). Le masquage remplace la **valeur exacte** dans le journal : une transformation de la valeur échappe au masque.
</details>

<details><summary>Indice 2</summary>

Les clés S3 du cache ne vont jamais dans le TOML : le chart les exporte depuis un Secret (`accesskey`, `secretkey`) en variables `CACHE_S3_ACCESS_KEY`/`CACHE_S3_SECRET_KEY` du gestionnaire. Le *helper* télécharge et téléverse par des **URL présignées** que le gestionnaire calcule : c'est donc le *helper*, dans le pod du job, qui parle à `s3-01`, et c'est lui qui doit faire confiance à la racine MédiSphère. La page « Self-signed certificates or custom Certification Authorities » de GitLab Runner décrit un fichier `/etc/gitlab-runner/certs/ca.crt` installé par le script d'entrée de l'image *helper* : regarde la commande du conteneur `helper` dans ton pod de E05 (`kubectl get pod -o yaml`) avant de compter dessus. Le *helper* est un programme Go : lis ce que Go fait de `SSL_CERT_DIR` (paquet `crypto/x509`).
</details>

<details><summary>Indice 3</summary>

Le cache d'un job se décrit par `key`, `paths`, `policy`, `when`, `fallback_keys`. Les fichiers mis en cache doivent être **dans** le dossier du projet (`$CI_PROJECT_DIR`) : `UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv`. Un seul job en `pull-push` évite que deux jobs parallèles téléversent le même cache. Le message de réussite d'extraction contient « Successfully extracted cache ».
</details>

**Pour aller plus loin** (facultatif) : le cache est par clé **et** par runner (`Shared = false`). Que changerait `Shared = true` quand le runner protégé arrivera (E24) ? Lis aussi `cache:unprotect` : pourquoi GitLab sépare-t-il par défaut le cache des branches protégées de celui des autres ?

---

### M19-E08 — Construire des images dans le cluster : BuildKit *rootless* partagé  `LAB` `★★★`

> **Ticket PLAT-2008** — *De : Karim Benali* — *Copie : Sophie Laurent, Julien Petit*
> Sur `runner02`, chaque job de construction lance son propre BuildKit avec seccomp et AppArmor non confinés (ADR-0120). Dans le cluster, je ne veux **pas** de cette exception dans chaque pod de job. Un seul démon BuildKit *rootless*, partagé, dans son espace, en TLS mutuel ; seuls les jobs y accèdent ; il ne sort que vers ce dont une construction a besoin ; son cache est dans Harbor. Notre gabarit de construction doit savoir s'en servir quand il tourne sur `k8s`, sans changer pour `runner02`. Première cible : une image de MédiAgenda construite par ce chemin.
>
> **Ticket SEC-2008** — *De : Sophie Laurent*
> Un démon de construction partagé, c'est une cible : qui peut lui parler, avec quel certificat, signé par qui, et que se passe-t-il si un job malveillant lui envoie un Dockerfile ? Je veux la réponse écrite.

**Objectifs pédagogiques**
- Déployer BuildKit en mode *rootless* dans Kubernetes, en connaissant chaque exception de sécurité et pourquoi elle est nécessaire.
- Mettre en place un TLS mutuel avec cert-manager : autorité dédiée, certificats serveur et client, distribution du certificat client aux pods de job.
- Restreindre les flux d'un démon partagé par CiliumNetworkPolicy (entrée et sortie).
- Utiliser un cache de construction en registre (`type=registry`) et adapter un gabarit CI à un constructeur distant.

**Prérequis** : M19-E04, M19-E05 ; M12-E21 (BuildKit sans privilège, `.image-construction`) ; M13-E09 (`supply-chain.yml`, `sc:construction`) ; M15-E13 (cert-manager) ; M15 (CiliumNetworkPolicy, `matrice-flux-cluster.md`) ; M17-E16 (chart local dans le Helmfile).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Image | `registry.par1.medisphere.internal/dockerhub/moby/buildkit:v0.34.1-rootless@sha256:<EMPREINTE>` (UID/GID 1000) |
| Chart | local **`charts/buildkitd`** de `plateforme/k8s`, release **`buildkitd`** (espace `buildkit`) dans `releases/50-ci.yaml.gotmpl`, valeurs `composants/buildkitd/values.yaml` ; Deployment **`buildkitd`** (1 réplica, stratégie `Recreate`), Service **`buildkitd`** port **1234**, PVC `buildkitd-donnees` (30 Gi, `ceph-rbd`), configuration `buildkitd.toml` en ConfigMap |
| TLS | cert-manager : ClusterIssuer auto-signé `buildkit-amorce` → certificat d'autorité `buildkit-ca` (Secret dans `cert-manager`) → ClusterIssuer **`buildkit-ca`** ; certificat serveur `buildkitd-serveur` (espace `buildkit`, noms du Service), certificat client **`buildkit-client`** (Secret `buildkit-client` dans `ci-jobs`) ; buildkitd exige un certificat client signé par `buildkit-ca` |
| Jobs | le runner monte le Secret `buildkit-client` en lecture dans les pods de job (`/etc/buildkit/client`) et leur donne `BUILDKIT_HOST=tcp://buildkitd.buildkit.svc.cluster.local:1234` et `BUILDKIT_TLS_DIR=/etc/buildkit/client` |
| Réseau | CiliumNetworkPolicy `buildkitd` : entrée sur 1234 depuis les pods de job de `ci-jobs` seulement (le runner protégé de E24 ne construit rien : son espace n'y a pas accès) ; sortie DNS (CoreDNS), Harbor (`reg01`, 10.10.20.18:443), et Internet en 443 pour les index de paquets des `RUN` (PyPI…), rien d'autre du lab ni du cluster |
| Cache | registre `registry.par1.medisphere.internal/plateforme/cache-buildkit:<projet>` (mode `max`) ; robot Harbor `robot$plateforme+cache-buildkit` (push et pull sur `plateforme`) ; variables d'instance de GitLab **protégées** `BUILDKIT_CACHE_UTILISATEUR` et `BUILDKIT_CACHE_JETON` (masquée) |
| Gabarits | `plateforme/ci-templates` v1 (nouvelle mineure) : `.image-construction` (`templates/image.yml`) et `sc:construction` (`templates/supply-chain.yml`) utilisent le démon distant quand `BUILDKIT_HOST` est défini, et le démon éphémère sinon (`runner02`) |
| MédiAgenda | `mediagenda/api` : `sc:construction` sur l'étiquette `k8s` (le reste de la chaîne reste sur `docker`) |

**Travail demandé**

*A. Comprendre le mode rootless*

1. Lis `docs/rootless.md` de BuildKit (version 0.34) et le manifeste `examples/kubernetes/deployment+service.rootless.yaml`. Réponds dans ton journal : pourquoi seccomp et AppArmor doivent-ils être `Unconfined` ? Que fait `--oci-worker-no-process-sandbox`, et quel risque accepte-t-on ? Le conteneur est-il privilégié ? Que se passe-t-il avec `allowPrivilegeEscalation: false` et pourquoi ?
2. Compare avec le job éphémère de `runner02` (M12-E21) : où est l'exception de sécurité dans chaque cas, combien de pods la portent, qui peut envoyer un Dockerfile au démon ?

*B. Le chart et le TLS*

3. Écris le chart local `charts/buildkitd` : `Chart.yaml`, `values.yaml` (image, ressources, stockage, noms DNS, espaces clients), gabarits `configmap.yaml` (`buildkitd.toml` : écoutes TCP avec TLS et socket local, *worker* OCI rootless sans bac à sable de processus, ramasse-miettes borné, registre Harbor avec la racine MédiSphère), `deployment.yaml`, `service.yaml`, `pvc.yaml`, `certificats.yaml` (les deux ClusterIssuers, l'autorité, le certificat serveur, un certificat client par espace client). Sondes : `buildctl debug workers` contre le socket local.
4. Pourquoi une **ClusterIssuer** et non une Issuer d'espace pour `buildkit-ca` ? Qui d'autre pourrait demander un certificat client à cette autorité, et qu'est-ce qui le limiterait ?
5. Ajoute la release `buildkitd` à `releases/50-ci.yaml.gotmpl` ; elle a besoin de cert-manager : pourquoi un `needs: [cert-manager/cert-manager]` serait-il refusé ici (relis la structure du Helmfile du M17) ? Rends (`helmfile template`), passe `kubeconform` sur le rendu (schémas de cert-manager et de Cilium si tu les as), puis `diff` et `apply`. Contrôle :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n buildkit get deploy,pod,svc,pvc,certificate
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get certificate,secret buildkit-client
   admin@adm01:~$ kubectl --context k8s-par1 -n buildkit logs deploy/buildkitd | head
   ```

*C. Le réseau*

6. Écris la CiliumNetworkPolicy `buildkitd` (dans le chart ou dans `espaces/buildkit/`) et ajoute la ligne à `docs/kubernetes/reseau/matrice-flux-cluster.md`. Vérifie avec Hubble qu'un pod de `wb-essais` ne joint pas `buildkitd:1234` et qu'un pod de `ci-jobs` le joint.

*D. Les jobs utilisent le démon*

7. Ajoute aux valeurs du runner le montage du Secret `buildkit-client` et les deux variables d'environnement. `apply`.
8. Dans `ci-labo`, un job `buildctl` (image `moby/buildkit:v0.34.0-rootless` de Harbor, `entrypoint: [""]`) lance `buildctl --addr "$BUILDKIT_HOST" --tlsdir "$BUILDKIT_TLS_DIR" debug workers`. Puis enlève `--tlsdir` : que répond le démon ?
9. Crée le dépôt de cache (robot `cache-buildkit` dans l'état `registre`, variables d'instance protégées) et publie une nouvelle mineure de `plateforme/ci-templates` : `.image-construction` et `sc:construction` utilisent `buildctl --addr … --tlsdir …` quand `BUILDKIT_HOST` est défini, avec `--import-cache` et (pipelines protégés seulement) `--export-cache` vers `plateforme/cache-buildkit:<slug du projet>` ; sinon, comportement inchangé (`buildctl-daemonless.sh`). Le job qui construit doit continuer à fonctionner sur `runner02` : vérifie-le.
10. Dans `mediagenda/api` : monte la référence des gabarits à cette version, place `sc:construction` sur l'étiquette `k8s`. Pipeline de `main` : la construction se fait par `buildkitd`, la suite de la chaîne (analyse, publication, signature) reste sur `runner02`. Relance le pipeline : le cache de `plateforme/cache-buildkit` est-il utilisé (lignes `CACHED` dans le journal) ?
11. Réponds au ticket SEC-2008 dans `~/m19/e08/reponse-sec-2008.md` : surface d'attaque du démon partagé (un `RUN` malveillant, un cache empoisonné, un secret de construction d'un autre projet), ce qui la réduit (TLS, réseau, rootless, rien de monté depuis le nœud) et ce qui reste (un seul démon pour tous les projets, cache local partagé). Ce texte nourrira l'ADR-0190 (E30).

**Critères de réussite**
- [ ] Le Deployment `buildkitd` est prêt dans `buildkit` avec l'image *rootless* de Harbor ; aucun conteneur privilégié dans `buildkit` ni dans `ci-jobs` ; le Service écoute 1234.
- [ ] Les certificats `buildkitd-serveur` et `buildkit-client` sont prêts (`Ready`), émis par la ClusterIssuer `buildkit-ca` ; le Secret client est dans `ci-jobs`.
- [ ] La CiliumNetworkPolicy `buildkitd` existe et n'admet en entrée que les pods des espaces de jobs.
- [ ] Le dépôt `plateforme/cache-buildkit` existe dans Harbor et contient au moins un artefact.
- [ ] Le dernier pipeline de `main` de `mediagenda/api` contient un job de construction réussi exécuté par le runner `k8s-par1`.

**Vérification** : `lab/bin/check 19 08`

<details><summary>Indice 1</summary>

`buildctl` accepte `--tlsdir` : un dossier qui contient `ca.crt`, `tls.crt`, `tls.key`, exactement les clés d'un Secret de cert-manager. Côté démon, la section `[grpc.tls]` de `buildkitd.toml` (`cert`, `key`, `ca`) : avec `ca`, il **exige** un certificat client. Les secrets de cert-manager sont dans l'espace du `Certificate` : un certificat client par espace de jobs.
</details>

<details><summary>Indice 2</summary>

Pour monter un Secret dans les pods de job : `[[runners.kubernetes.volumes.secret]]` (`name`, `mount_path`, `read_only`). Pour les variables : `environment = [...]` au niveau du `[[runners]]`. Le cache en registre s'écrit `--export-cache type=registry,ref=…,mode=max` ; les identifiants viennent du client (`$DOCKER_CONFIG/config.json` du job), pas du démon : le démon reçoit des jetons d'accès par la session gRPC.
</details>

<details><summary>Indice 3</summary>

Dans une CiliumNetworkPolicy, un pod d'un autre espace se sélectionne par l'étiquette `k8s:io.kubernetes.pod.namespace`. Pour « Internet en 443 sauf le lab », `toCIDRSet` avec `cidr: 0.0.0.0/0` et `except` ; pour Harbor, `toCIDR` de `reg01`. N'oublie pas la règle DNS (`toEndpoints` de CoreDNS, `rules: dns`), sans laquelle plus rien ne se résout.
</details>

**Pour aller plus loin** (facultatif) : BuildKit sait répartir les constructions sur plusieurs démons avec un hachage cohérent (exemple `consistenthash` amont, StatefulSet). Calcule ce que coûterait en mémoire et en stockage un démon par équipe, et ce qu'on y gagnerait en isolation (cache, secrets) : la question reviendra dans l'ADR-0190.

---

### M19-E09 — Questions : le modèle d'exécution de GitLab CI  `Q` `★★`

> **Ticket PLAT-2009** — *De : Karim Benali*
> Tu as fait tourner des jobs sous toutes les coutures. Avant de passer aux composants, je veux être sûr que tu sais expliquer à Nadia ce qui se passe entre un `git push` et la première ligne du script, et où ça peut casser. Par écrit, sans relire tes notes.

**Objectifs pédagogiques**
- Décrire précisément le chemin d'un job : création du pipeline, file d'attente, attribution, exécution, retour des résultats.
- Raisonner sur l'isolation et les jetons d'un job.

**Prérequis** : M19-E02 à M19-E08.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 12 questions.

1. Décris dans l'ordre ce qui se passe entre `git push origin ma-branche` et la création des jobs d'un pipeline : qui lit le `.gitlab-ci.yml`, de quel commit, et à quel moment les `workflow:rules` puis les `rules` des jobs sont-elles évaluées ? Qu'est-ce qui se passe si le fichier est invalide ?

2. Un job est créé à l'état `created`, puis passe `pending`. Qu'est-ce qui le fait passer `pending`, et qu'est-ce qui le fait passer `running` ?

3. Le gestionnaire `k8s-par1` envoie `POST /api/v4/jobs/request`. Que contient sa requête ? Que répond GitLab quand aucun job ne correspond, et combien de temps GitLab garde-t-il la requête ouverte ? Pourquoi ce modèle convient-il à notre réseau (relis la matrice des flux) ?

4. Deux gestionnaires du **même** runner (deux réplicas du chart) interrogent GitLab. Comment GitLab garantit-il qu'un job n'est donné qu'à un seul ? Comment les distingue-t-il dans l'interface ?

5. *(QCM)* Un job a les étiquettes `k8s` et `gpu`. Le runner `k8s-par1` a les étiquettes `k8s` et `kubernetes`. Que se passe-t-il ?
   - A. `k8s-par1` prend le job, l'étiquette `gpu` est ignorée
   - B. Le job reste en attente : un runner doit avoir **toutes** les étiquettes du job
   - C. Le job échoue immédiatement avec « no runner »
   - D. GitLab choisit le runner qui a le plus d'étiquettes en commun

6. Dans la réponse à la demande de job, le gestionnaire reçoit un **jeton de job**. À quoi sert-il pendant l'exécution (cite au moins trois usages) ? Que vaut-il après la fin du job ?

7. Où sont évaluées les variables `$VARIABLE` de ton script : par GitLab au moment de la création du job, par le gestionnaire, ou par le shell du conteneur `build` ? Donne un exemple où la différence compte (`rules:if`, `image:`, `script:`).

8. Le pod d'un job est créé par le gestionnaire avec **son** compte de service (`gitlab-runner`). Avec quelle identité tourne le job dans le cluster ? Que peut-il faire avec l'API Kubernetes ? Qu'est-ce qui changerait si `automount_service_account_token` était vrai et que `ci-job` avait le rôle `edit` sur `ci-jobs` ?

9. Ce que voit un job : cite cinq choses auxquelles le script du conteneur `build` a accès (fichiers, variables, réseau) et deux auxquelles il n'a pas accès alors que le gestionnaire, lui, y a accès.

10. *(QCM)* Le gestionnaire redémarre (nouvelle version du chart) pendant qu'un job tourne depuis 10 minutes. Avec les valeurs de E04, que devient le job ?
    - A. Il est tué immédiatement et marqué en échec
    - B. Le gestionnaire attend la fin des jobs en cours (jusqu'au délai de grâce) avant de s'arrêter, et n'en prend plus de nouveaux
    - C. Le job continue sans gestionnaire et son résultat est perdu
    - D. GitLab relance le job sur un autre runner

11. Un job attend « Waiting for pod … to be running » puis échoue au bout de 10 minutes. Donne trois causes possibles et, pour chacune, la commande qui la confirme.

12. Un job réussit, mais l'artefact n'apparaît pas dans GitLab. À quel moment et par quel conteneur l'artefact est-il téléversé ? Cite deux causes possibles de cet écart.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2) et calculé ton score sur 24.
- [ ] Tu as noté les points à revoir et les exercices concernés (E04, E05, E44 au palier 4).

<details><summary>Indice 1</summary>

Pense aux trois acteurs et à leurs messages : GitLab (Rails et Sidekiq, la base), le gestionnaire (une boucle de requêtes HTTP), le pod (un `build` et un `helper` qui parlent tous deux à GitLab).
</details>

<details><summary>Indice 2</summary>

Pour la question 8, relis l'en-tête « Configure runner API permissions » de l'exécuteur Kubernetes et le `kubectl auth can-i --list` de E02 : l'identité qui **crée** un pod n'est pas celle avec laquelle le pod **tourne**.
</details>

**Pour aller plus loin** (facultatif) : M19-E44 (palier 4) suit un job de bout en bout dans les journaux de GitLab, l'audit de l'API Kubernetes et le journal du gestionnaire : garde tes réponses pour comparer.
