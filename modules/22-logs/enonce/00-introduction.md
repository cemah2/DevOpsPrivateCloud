# Module 22 — Introduction : les journaux

## « Envoie-moi les logs »

Mardi, 10 h 40. MédiAgenda a renvoyé des erreurs 500 en recette pendant vingt minutes, la nuit dernière. Julien Petit a demandé « les logs » ; Karim a lancé un `kubectl logs` sur un pod… qui avait été remplacé à 4 h par un déploiement : plus rien. Sur `git01`, quelqu'un se souvient d'un `journalctl` qui montrait « un truc bizarre » vers minuit, mais ne sait plus sur quelle VM. Sophie Laurent, elle, a reçu la grille de l'auditeur HDS : « Démontrez qui a modifié quoi sur la plateforme de production au cours des six derniers mois. » Claire Morel écrit à l'équipe.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Journaux — un seul endroit, des règles écrites
>
> Bonjour,
>
> Les métriques nous disent **que** quelque chose ne va pas ; il nous manque le **pourquoi**, et il est dans les journaux. Aujourd'hui ils sont éparpillés sur six nœuds, quinze VMs et des pods qui disparaissent avec leurs fichiers. Ce que je veux à la fin du module :
> 1. **tous** les journaux du lab au même endroit : pods, nœuds, VMs du socle, journal d'audit de l'API Kubernetes, événements du cluster ; interrogeables à côté des métriques, dans Grafana ;
> 2. **cloisonnés** : l'équipe MédiAgenda voit ses journaux, pas ceux de MédiDoc ; l'audit n'est lisible que par nous et par Sophie ;
> 3. des **règles écrites** : ce qu'on garde, combien de temps, ce qui n'a pas le droit d'entrer (les données de santé), qui a accès ;
> 4. des **alertes** quand un journal dit quelque chose que les métriques ne disent pas ;
> 5. un choix **argumenté** : on part sur Loki et Alloy (la pile Grafana qu'on a déjà), mais on compare honnêtement avec Fluent Bit et OpenSearch avant de l'écrire dans l'ADR.
>
> Contraintes : tout par le code et par Argo CD, comme au M21 ; données sur le RGW de `ceph-par1` ; Promtail, qu'on voit dans tous les tutoriels, est **en fin de vie** depuis mars : on ne l'installe pas. Nadia veut un runbook « chercher dans les journaux » utilisable à 3 h du matin. Karim te fait passer le test habituel avant de commencer.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 22, MédiSphère a sa journalisation **v1** (étiquette `journaux-v1` du dépôt `plateforme/medisphere`), que le module 23 étend aux traces (`trace_id` dans les journaux, corrélation Loki ↔ Tempo) :

- **Loki 3.7** en mode monolithique dans l'espace **`journaux`**, multi-locataire (`plateforme`, `mediagenda`, `medidoc`, `audit`), données dans le compartiment **`loki-k8s-par1`** du RGW de `ceph-par1`, joignable hors cluster par **10.10.41.62:3100** ;
- **Grafana Alloy 1.21** : un DaemonSet qui lit les journaux des pods, le journal systemd des nœuds, le journal d'audit de l'API et les événements Kubernetes ; un rôle Ansible **`alloy`** sur les VMs du socle ;
- des journaux **structurés** exploités (champs en métadonnées structurées, `request_id`), des **alertes** sur les journaux (ruler de Loki → Alertmanager du M21), un **masquage** des données de santé ;
- des rétentions par locataire, des limites, la sécurité et la sauvegarde (palier 3) ; des comparaisons avec **Fluent Bit 5.1** et **OpenSearch 3.9**, installés puis **retirés** ;
- la documentation : `docs/observabilite/journaux/` (fiche de Loki, `politique-journaux.md`, comparatifs), ADR-0220, runbooks RB-220 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) installe Loki et Alloy, apprend LogQL et branche les VMs. Le **palier 2** (`02-operationnel.md`) traite les tickets du quotidien : journaux JSON de MédiAgenda, audit de l'API, alertes, données de santé, essai de Fluent Bit, revue, runbook. Le **palier 3** (`03-production.md`) fixe les rétentions, les limites et l'effacement, mesure la performance et la cardinalité, compare avec OpenSearch, verrouille les accès et la sauvegarde, et écrit l'ADR-0220. Le **palier 4** (`04-expert.md`) casse et répare la chaîne des journaux (cinq pannes, dont une astreinte) et descend sous le capot de Loki. Le **mini-projet** (`05-mini-projet.md`) livre l'état `journaux-v1`.

## Architecture du module

```
                      adm01 (MGMT 10.10.10.10) : logcli 3.7, lab/bin/check 22 …
                                  │  HTTP 3100 (lecture ; X-Scope-OrgID = locataire)
  VMs du socle (VLAN 20, 70, gw01/gw02)                         │
  dns01 … mon01, lb01/lb02, gw01/gw02 : rôle Ansible « alloy »  │
  journald ──► Alloy ── POST /loki/api/v1/push (plateforme) ────┤  par la bordure (gw01/gw02, TCP 3100)
                                                                ▼
  ═══════════════════════════ k8s-par1 ════════ 10.10.41.62:3100 (Service LoadBalancer loki-externe,
  │                                                              externalTrafficPolicy: Local, BGP)
  │  espace journaux                                             │
  │  ┌─────────────────────────────────────────────┐  ┌──────────▼───────────────────────────────────┐
  │  │ DaemonSet Alloy (un pod par nœud, 6 nœuds)  │  │ StatefulSet loki (1 réplica, -target=all)    │
  │  │  /var/log/pods/…        → pods              │  │  distributeur → ingester (WAL sur PVC)       │
  │  │  /var/log/journal       → journald du nœud  │──►  requêteur, compactor, ruler (palier 2)      │
  │  │  /var/log/kubernetes/audit (contrôle) → audit│  │  CNP loki-entree : qui écrit, qui lit        │
  │  │  API : événements (un seul pod, clustering) │  └───────┬───────────────────────┬──────────────┘
  │  │  locataire d'après l'espace ; masquage      │          │ chunks + index TSDB   │ alertes
  │  └─────────────────────────────────────────────┘          ▼                       ▼
  │                                           RGW ceph-par1 (10.10.30.200,   Alertmanager du cluster
  │  espace supervision                       eth1 des travailleurs)         (supervision, M21)
  │  Grafana : sources « Loki — <locataire> » compartiment loki-k8s-par1      → Mailpit (mon01)
  ════════════════════════════════════════════════════════════════════════════════════════════════
```

Points structurants :

- **Un index d'étiquettes, pas un index plein texte.** Loki n'indexe que les **étiquettes** d'un flux (`{namespace="mediagenda-prod", container="api"}`) ; le contenu des lignes est compressé en *chunks* dans le stockage objet et parcouru à la requête. C'est ce qui le rend économe… à condition de garder **peu de flux** : chaque combinaison de valeurs d'étiquettes est un flux. D'où une **liste fermée** d'étiquettes, et tout le reste en **métadonnées structurées** (attachées à chaque ligne, non indexées) ou dans la ligne.
- **Multi-locataire.** Chaque écriture et chaque lecture porte l'en-tête `X-Scope-OrgID` ; Loki range et cherche séparément par locataire. C'est le cloisonnement entre équipes, et le support des rétentions différentes (l'audit gardé un an).
- **Un agent par nœud, qui lit les fichiers.** Le runtime (containerd) écrit la sortie standard de chaque conteneur dans `/var/log/pods/…` au format CRI ; Alloy lit ces fichiers sur **son** nœud, y ajoute les étiquettes tirées de l'API Kubernetes, choisit le locataire, et envoie à Loki. Les positions de lecture sont gardées sur le disque du nœud.
- **Tout par le code.** Comme au M21 : charts recopiés dans Harbor par `plateforme/charts-miroir`, valeurs et configuration dans **`plateforme/observabilite`** (dossiers `loki/`, `alloy/`, `requetes/`), Applications Argo CD dans **`plateforme/gitops`** (projet `plateforme`), secrets hors Git par `plateforme/k8s/outils/secrets-k8s.sh`, agent des VMs par Ansible.

### Composants du module

| Composant | Où | Version | Exercice |
|---|---|---|---|
| Loki | espace `journaux`, Application `loki`, StatefulSet `loki` | 3.7.9 (chart `grafana-community/loki` 19.0.3) | E02 |
| Alloy (cluster) | espace `journaux`, Application `alloy`, DaemonSet `alloy` | 1.21.1 (chart `grafana/alloy` 1.14.1) | E03, E06, E07, E09 |
| Alloy (VMs) | VMs Debian 13 du socle, rôle Ansible `alloy` | 1.21.1 (binaire amont vérifié par empreinte) | E05 |
| logcli | `adm01`, rôle `outils_k8s` | 3.7.9 | E04 |
| Ruler de Loki | dans le binaire Loki, règles `loki/regles/<locataire>/` | — | E08 |
| Fluent Bit (essai) | espace `journaux-essai`, **retiré** | 5.1.3 (chart `fluent/fluent-bit` 0.58.3) | E10 |
| OpenSearch (essai) | espace `opensearch-essai`, **retiré** | 3.9.0 (chart `opensearch/opensearch` 3.9.0) | E15 |

### Flux réseau du module

| Flux | Port | Exercice | Où c'est appliqué |
|---|---|---|---|
| pods Alloy → Loki (dans le cluster) | TCP 3100 | E03 | CNP `journaux/loki-entree` (limité à `POST /loki/api/v1/push` en E16) |
| Grafana, Prometheus (`supervision`) → Loki | TCP 3100 | E02 | CNP `loki-entree` (chemins de lecture et `/metrics` en E16) |
| Loki → RGW 10.10.30.200 (par `eth1` des travailleurs) | TCP 443 | E02 | existant (M16) ; CNP `loki-sortie` en E16 |
| MGMT (`adm01`, son agent et les vérifications) → 10.10.41.62 | TCP 3100 | E02, E05 | bordure : existant ; CNP `loki-entree` (tout l'HTTP) |
| INFRA (VLAN 20) et DMZ (VLAN 70) → 10.10.41.62 (agents des VMs) | TCP 3100 | E05 | **nouveau** : `pare_feu.yml` (`gw01`/`gw02`) + CNP (`POST /loki/api/v1/push` seulement) |
| `gw01`/`gw02` eux-mêmes (10.10.40.2/.3) → 10.10.41.62 | TCP 3100 | E05 | chaîne `output` des passerelles (ouverte) + CNP (`push` seulement) |
| ruler de Loki → Alertmanager (`supervision`) | TCP 9093 | E08 | CNP de `supervision` si elle filtre (M21-E29) ; CNP `loki-sortie` en E16 |
| Loki → DNS du cluster, API Kubernetes (sidecar des règles) | UDP/TCP 53, TCP 6443 | E16 | CNP `loki-sortie` |

Les VMs qui envoient leur journal sont celles du groupe d'inventaire `socle` (liste en E05 : `adm01` sur MGMT, les passerelles, les VMs d'INFRA et de DMZ) : ces réseaux couvrent toutes les VMs visées par le rôle `alloy`. Les VMs de `ceph-par1` (VLAN 30) et les VMs d'environnement (VLAN 99) ne sont **pas** branchées dans ce module ; les ajouter demande une règle de la bordure **et** une ligne de la CNP (piste de M22-E05, « Pour aller plus loin »).

---

## Le chemin imposé

1. **Charts** : recopiés et signés dans Harbor `charts/` par `plateforme/charts-miroir` (M20-E13) ; jamais tirés d'Internet par Argo CD.
2. **`plateforme/observabilite`** (M21) : `loki/` (valeurs, manifestes, règles), `alloy/` (valeurs, `config.alloy`), `requetes/` (LogQL) ; la CI valide (`alloy fmt --test`, `alloy validate`).
3. **`plateforme/gitops`** : une Application par composant dans `plateforme/` (projet `plateforme`), sous l'application racine.
4. **Secrets** : identifiants S3 de Loki en Vault `critique` (`plateforme/k8s` : `secrets/loki.yml`), Secret `loki-objstore` créé par `outils/secrets-k8s.sh` ; sur `adm01`, `~/.config/workbook/s3-loki.env` (600).
5. **VMs** : rôle Ansible `alloy` dans `plateforme/ansible`, pipeline protégé (ADR-0040) ; flux de la bordure dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`.
6. **Documentation** : `plateforme/medisphere`, dossier `docs/observabilite/journaux/`.

Aucun `kubectl apply` sur les espaces applicatifs (`mediagenda-*`, `medidoc-*`) : on passe par leurs dépôts `…/deploiement` (M20-E30). `wb-essais` reste l'espace jetable des essais.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Journal, métrique, trace.** Une **métrique** est un nombre agrégé dans le temps (combien de 500 par seconde) : bon marché, idéale pour alerter. Un **journal** est un événement discret avec son contexte (quelle requête, quelle erreur, quel utilisateur) : riche, coûteux, indispensable pour comprendre. Une **trace** (M23) suit une requête à travers les services. On alerte sur les métriques, on enquête dans les journaux et les traces.

**Flux, étiquettes, chunks.** Un **flux** (*stream*) est l'ensemble des lignes qui portent exactement les mêmes étiquettes. Loki indexe les étiquettes des flux (index **TSDB**, schéma **v13**), et range les lignes de chaque flux dans des **chunks** compressés envoyés au stockage objet. Une requête choisit des flux par leurs étiquettes, puis lit leurs chunks. Beaucoup de flux = beaucoup de petits chunks, un index qui gonfle, des requêtes lentes : c'est la **cardinalité**, l'ennemi n° 1.

**Métadonnées structurées.** Depuis Loki 3 (schéma v13), une ligne peut porter des paires clé-valeur **non indexées** (`pod`, `request_id`, `trace_id`) : filtrables après le sélecteur (`| request_id="…"`) sans analyser la ligne et sans créer de flux.

**LogQL.** Une requête de journaux = un **sélecteur** de flux (`{namespace="journaux"}`), puis un **pipeline** : filtres de ligne (`|=`, `!=`, `|~`), analyseurs (`json`, `logfmt`, `pattern`, `regexp`), filtres d'étiquettes extraites (`| code >= 500`), mise en forme (`line_format`). Une requête **métrique** enveloppe le tout dans une fonction sur une fenêtre (`count_over_time`, `rate`, `quantile_over_time` avec `unwrap`).

**Multi-locataire.** Loki ne sait rien des « équipes » : il range par **locataire** (en-tête `X-Scope-OrgID`). L'en-tête n'est pas authentifié par Loki : c'est le réseau (CNP), le collecteur et, plus tard, un mandataire authentifiant (M24) qui garantissent qui écrit où et qui lit quoi.

**Collecteur.** Lit les sources (fichiers, journald, API), étiquette, transforme (analyse, filtrage, masquage), et envoie avec reprise sur erreur. **Grafana Alloy** est la distribution de Grafana du Collector OpenTelemetry et de l'ancien Grafana Agent, configurée en composants reliés (`discovery.*`, `loki.source.*`, `loki.process`, `loki.write`). **Promtail** (l'ancien agent de Loki) est en fin de vie depuis le 2 mars 2026 : `alloy convert --source-format=promtail` aide à migrer une configuration existante.

**Rétention et RGPD.** Garder des journaux, c'est garder des données : il faut une durée (par locataire), une base légale, et savoir **effacer**. La meilleure donnée personnelle est celle qu'on n'a jamais collectée.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Loki **3.7.9** (chart `grafana-community/loki` **19.0.3**) ; Alloy **1.21.1** (chart `grafana/alloy` **1.14.1**) ; logcli 3.7.9 ; Fluent Bit **5.1.3** (chart `fluent/fluent-bit` 0.58.3) ; OpenSearch 3.9 ; Grafana 13.2, kube-prometheus-stack 92 (M21) |
| Changements de version | [`annexes/versions-bloc-DE.md`](../../../annexes/versions-bloc-DE.md), section « Journaux » : chart Loki déménagé chez `grafana-community`, mode `Monolithic` (ancien `SingleBinary`), SimpleScalable déprécié, Promtail en fin de vie, WAL de `loki.write` expérimental en Alloy 1.21 |
| Espace | `journaux` (Pod Security : `privileged` appliqué — Alloy lit `/var/log` du nœud —, `restricted` en avertissement et en audit) |
| Loki | StatefulSet `loki` (conteneur `loki`), Services `loki` (ClusterIP 3100, 9095) et **`loki-externe`** (LoadBalancer **10.10.41.62**, `loki.apps.par1.medisphere.internal:3100`) ; PVC `ceph-rbd` 20 Gio (WAL) ; PriorityClass `medisphere-critique` |
| Stockage objet | RGW `https://rgw.par1.medisphere.internal` (VIP 10.10.30.200), utilisateur RGW **`loki`**, compartiment **`loki-k8s-par1`** ; Secret `loki-objstore` (clés `LOKI_S3_ACCESS_KEY_ID`, `LOKI_S3_SECRET_ACCESS_KEY`) ; racine MédiSphère dans la ConfigMap `racine-medisphere` |
| Locataires | `plateforme` (cluster, nœuds, VMs, plateforme), `mediagenda` (espaces `mediagenda-*`), `medidoc` (`medidoc-*`), `audit` (journal d'audit de l'API) ; `essai` pour les comparaisons |
| Étiquettes Loki | liste **fermée** : `cluster`, `namespace`, `app`, `container`, `node`, `job` ; pour les VMs `host`, `role`, `site` ; valeurs de `job` : `pods`, `journald`, `kubernetes-audit`, `kubernetes-events` |
| Métadonnées structurées | `pod`, `stream` (pods) ; `unite`, `niveau` (journald) ; `niveau`, `request_id` (MédiAgenda, E06) ; `verb`, `user`, `code`, `resource`, `object_ns`, `object_name` (audit, E07) |
| Grafana | sources `Loki — plateforme`, `Loki — mediagenda`, `Loki — medidoc`, `Loki — audit` (UID `loki-<locataire>`), ConfigMap `supervision/sources-loki` (fichier `grafana/sources-loki.yaml`) ; à partir de M22-E16, `Loki — audit` (même UID `loki-audit`) n'est plus dans ce fichier : elle est créée par OpenTofu (état `observabilite-grafana`) dans l'organisation Grafana **Sécurité** |
| Projets | `plateforme/observabilite` (`loki/`, `alloy/`, `requetes/`) ; `plateforme/gitops` (`plateforme/loki.yaml`, `plateforme/alloy.yaml`) ; `plateforme/charts-miroir` ; `plateforme/k8s` (`secrets/loki.yml`) ; `plateforme/ansible` (rôle `alloy`, playbook `journaux-vms.yml`) ; `mediagenda/api` et `mediagenda/deploiement` (E06) |
| Documentation | `docs/observabilite/journaux/` : `loki.md` (E02), `politique-journaux.md` (section 1 en E09, section 2 en E13, sections 3 et 4 en E16), `comparatif-collecteurs.md` (E10), `performance.md` (E14), `comparatif-opensearch.md` (E15), `sous-le-capot.md` (E24), `adr/ADR-0220-architecture-journaux.md` (E17), `runbooks/RB-220-…` (E12), `RB-221-…` (E13), `RB-222-…` (E19, E22), `RB-223-…` (E20), `RB-224-…` (E21) ; post-mortem INC-4923 dans `docs/kubernetes/post-mortems/` (E23) |
| Brouillons | `~/m22/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte (GitLab, cluster, Argo CD) |
| `<URL-MEDIAGENDA-DEV>` | Adresse de MédiAgenda en dev : son nom publié (M15) s'il existe, sinon `http://127.0.0.1:18000` derrière `kubectl port-forward` (E06) |

### Variables de `lab/lab.env`

`WB_LOKI_URL` (défaut : `http://loki.apps.par1.medisphere.internal:3100`) sert à `loki_api` et `loki_requete`. Le module en ajoute huit, toutes facultatives (les valeurs ci-dessous sont les défauts) :

```
#WB_M22_VMS_SOCLE="gw01 gw02 adm01 dns01 dns02 ca01 git01 runner01 runner02 nbx01 s3-01 reg01 mon01 lb01 lb02"  # VMs qui envoient leur journal (E05)
#WB_M22_MEDIAGENDA_URL="https://mediagenda-recette.apps.par1.medisphere.internal"   # cible de ressources/E04-trafic/trafic.sh
#WB_M22_S3_LOKI_ENV="$HOME/.config/workbook/s3-loki.env"                              # identifiants S3 de Loki (E02)
#WB_M22_RGW_URL="https://rgw.par1.medisphere.internal"                                 # point d'accès du RGW (E02, E13, E16, E24)
#WB_M22_FICHIER_LOKI="loki/values.yaml"                     # fichiers de plateforme/observabilite que modifient
#WB_M22_FICHIER_ALLOY="alloy/values.yaml"                   # les pannes du palier 4, si ton dépôt les range
#WB_M22_FICHIER_ALLOY_CONFIG="alloy/config.alloy"           # ailleurs
#WB_M22_FICHIER_SOURCES="grafana/sources-loki.yaml"
```

Le check de E07 utilise aussi `WB_MOI` (ton compte, bloc A) ; ceux du palier 4 utilisent `WB_K8S_CP` et `WB_K8S_WORKERS` (M14), et les pannes `WB_GITLAB_ADMIN_TOKEN_FILE` (M01). Fichiers de `~/.config/workbook/` : `s3-loki.env` (E02, 600), et ceux du M21 (`grafana-checks.token`, `mailpit-checks.env`, `k8s-checks.kubeconfig`).

---

## Règles du module

1. **Les journaux sont des données de production.** Ils contiennent des adresses, des identifiants, parfois pire. Pas de copie de journaux dans un ticket, un dépôt ou un canal de discussion ; des identifiants techniques seulement (`request_id`).
2. **Jamais de donnée réelle de patient**, même pour un essai : le pod témoin de E09 écrit des valeurs **factices** (domaines `example.org`, NIR de test).
3. **On ne supprime pas de données pour réparer.** Ni objets du compartiment `loki-k8s-par1`, ni PVC de Loki, ni rétention raccourcie « pour voir ». Les seules suppressions de journaux passent par l'API de suppression de Loki, avec un ticket (M22-E13).
4. **La cardinalité se décide avant l'écriture.** Une étiquette ajoutée à la légère ne se retire pas des données déjà écrites. Toute nouvelle étiquette passe par une MR relue (et par la liste fermée).
5. **Mémoire.** Profil des blocs D et E : socle v4 + `ceph-par1` + `k8s-par1` ≈ **100 Go**. Loki demande 1 Gio (limite 2 Gio), Alloy ≈ 130 Mio par nœud. Les essais (Fluent Bit en E10, OpenSearch en E15) sont **temporaires** et jamais deux à la fois ; avant OpenSearch (≈ 3 Go), vérifie la mémoire libre de `pve01`.
6. **Pas de vérification TLS désactivée** (`curl -k`, `insecure_skip_verify`) ; le Service 10.10.41.62 parle HTTP **en clair** : il ne transporte que des journaux déjà masqués, sur les réseaux du lab, et la question de son chiffrement est posée en M22-E16.

---

## Préparer `adm01`

Vérifie l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 21 46          # métriques-v1 : Grafana, Alertmanager, plateforme/observabilite
admin@adm01:~$ lab/bin/check 20 46          # gitops-v1 : Argo CD, charts-miroir, projet plateforme
admin@adm01:~$ kubectl --context k8s-par1 get nodes
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
admin@adm01:~$ aws --version                 # AWS CLI (M16) : liste du compartiment de Loki
```

Les deux premiers contrôles doivent être verts. Le cluster doit avoir ses six nœuds `Ready` ; Argo CD doit montrer `kube-prometheus-stack` et `observabilite` synchronisées. Il te faut une dizaine de Go libres sur `pve01` en plus du profil.

Retrouve le chemin du journal d'audit de l'API sur les nœuds de contrôle (M14-E27) : tu en auras besoin en E07.

```
admin@adm01:~$ ssh k8s-cp01 'sudo ls -l /var/log/kubernetes/audit/'
```

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 22 <XX>`. Elles sont en lecture seule : API de Loki (requêtes LogQL en GET, avec l'en-tête du locataire), objets du cluster par le compte `wb-checks`, Applications d'Argo CD, fichiers sur `main` par l'API de GitLab, liste (et seulement liste) du compartiment de Loki, Mailpit en lecture.
- Beaucoup de contrôles portent sur **ce qui est arrivé dans Loki** dans les 15 dernières minutes ou la dernière heure : si un contrôle est rouge juste après une modification, attends quelques minutes ou génère du trafic (`ressources/E04-trafic/trafic.sh`) avant de chercher plus loin.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M22-EXX/` : `observabilite/` reproduit `plateforme/observabilite`, `gitops/` `plateforme/gitops`, `ansible/` `plateforme/ansible`, `k8s/` `plateforme/k8s`, `charts-miroir/`, `mediagenda-api/` et `mediagenda-deploiement/` les dépôts de MédiAgenda, `medisphere/` la documentation.

## Ordre conseillé

```
Palier 1 :  E01 ─ E02 ─ E03 ─ E04 ─ E05
Palier 2 :  E06 ─ E07 ─ E08 ─ E09 ─ E10 ─ E11 ─ E12
Palier 3 :  E13 ─ E14 ─ E15 ─ E16 ─ E17 ─ E18
Palier 4 :  E19 ─ E20 ─ E21 ─ E22 ─ E23 ─ E24
Palier 5 :  E25 (mini-projet)
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — dans l'ordre strict : Loki, puis l'agent du cluster.
3. **E04** — LogQL, dès que des journaux arrivent ; **E05** — les VMs (peut se faire avant E04).
4. **E06 → E09** — dans l'ordre : chaque exercice modifie `alloy/config.alloy` (E06 et E07 l'étendent, E09 y ajoute le masquage) ; E08 a besoin de l'audit (E07).
5. **E10** — à faire d'une traite (l'essai est retiré à la fin) ; **E11** et **E12** en dernier.
6. **E13 → E14** — rétentions et limites avant les mesures de performance ; **E15** (OpenSearch, ≈ 3 Go, retiré à la fin) jamais en même temps qu'un autre essai ; **E16** avant l'ADR (**E17**) ; **E18** pour finir le palier.
7. **E19 → E22** — une panne à la fois, chacune close (`--annuler`) avant la suivante ; **E23** enchaîne une de ces pannes ; **E24** quand tu veux après E16.
8. **E25** — en dernier : le contrôle global rejoue les vérifications clés des paliers 1 à 3.

Durée indicative : palier 1, 7 à 9 heures ; palier 2, 10 à 13 heures ; palier 3, 9 à 11 heures ; palier 4, 6 à 8 heures ; mini-projet, 4 à 6 heures.

## Pour aller plus loin

- Loki, architecture et concepts : <https://grafana.com/docs/loki/latest/get-started/> · étiquettes et cardinalité : <https://grafana.com/docs/loki/latest/get-started/labels/> · métadonnées structurées : <https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/>
- Installer Loki en monolithique avec Helm : <https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/> · référence de configuration : <https://grafana.com/docs/loki/latest/configure/>
- LogQL : <https://grafana.com/docs/loki/latest/query/>
- Multi-locataire : <https://grafana.com/docs/loki/latest/operations/multi-tenancy/>
- Grafana Alloy, composants : <https://grafana.com/docs/alloy/latest/reference/components/> · collecter les journaux Kubernetes : <https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/>
- Migrer de Promtail : <https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/>
