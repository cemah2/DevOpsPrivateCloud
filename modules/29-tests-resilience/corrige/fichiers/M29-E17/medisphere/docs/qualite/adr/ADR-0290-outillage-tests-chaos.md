# ADR-0290 — Outillage de tests et de chaos de la plateforme

| | |
|---|---|
| Statut | **Accepté** (<DATE>) — revue annuelle ou au déclencheur de révision |
| Décideurs | Claire Morel (responsable infrastructure), Karim Benali, Sophie Laurent (RSSI, pour l'exception GitOps) |
| Ticket | PLAT-3017 (M29-E17) |
| Remplace | — ; complète ADR-0190 (CI), ADR-0200 (GitOps), ADR-0260 (politiques) |

## Contexte

Avant l'audit et la mise en production générale, MédiSphère doit prouver que sa plateforme est **testée** à chaque étage et qu'elle **tient** charge et pannes. Contraintes : cloud privé sans service managé, mémoire du lab comptée (≈ 111 Go pour le bloc G), équipe de cinq personnes, conformité HDS (traçabilité de chaque changement), règle « tout passe par Git et Argo CD » (ADR-0200), aucune image ni chart Bitnami. Mesures du module citées entre crochets (lab de référence ; chiffres à remplacer par les tiens).

## Décision

### 1. Chaos : Chaos Mesh 2.8, pas LitmusChaos

**Chaos Mesh 2.8** (chart 2.8.x, Application `chaos-mesh`, espace `chaos-mesh`), filtre d'espaces actif : seuls `mediagenda-recette`, `medinotif-recette` et `wb-essais` sont visables.

- Ce qu'il nous apporte : des CRD simples (une expérience = un objet versionnable), `Schedule` et `Workflow` avec vérifications HTTP, un daemon unique par nœud, aucune base de données. [Coût mesuré au repos : contrôleur + 3 daemons ≈ 250 Mio.]
- **LitmusChaos 3** écarté (fiche `annexes/decouverte/litmuschaos.md`) : son ChaosCenter exige **MongoDB** (fourni par un sous-chart **Bitnami**, interdit chez nous depuis la fin du catalogue gratuit), un serveur GraphQL, une interface et un authentificateur : ≈ 4 composants de plus à exploiter, sauvegarder et durcir pour un usage de quelques heures par mois. Ce que nous perdons : le ChaosHub (expériences prêtes), les *probes* déclaratives riches (Prometheus, commande, Kubernetes), l'interface d'orchestration. Acceptable : nos expériences sont peu nombreuses, écrites et relues par nous ; les vérifications HTTP des `Workflow` et nos mesures PromQL couvrent le besoin. On rouvrira la question si une équipe applicative veut écrire ses propres expériences sans passer par la plateforme.

### 2. Charge : k6 + k6-operator

**k6 1.8** (CLI sur `adm01`) puis **k6-operator 1.7** (espace `k6`) pour la charge distribuée et la non-régression nocturne. Scripts en JavaScript versionnés dans `plateforme/resilience/charge/`, seuils alignés sur les SLO, résultats dans Prometheus.

- Écartés : **JMeter** (scénarios XML difficiles à relire en MR, JVM lourde), **Gatling** (Scala/Java, édition libre sans distribution de charge), **Locust** (Python, apprécié de l'équipe de Julien mais distribution maître/travailleurs à construire nous-mêmes, pas d'opérateur maintenu). Locust reste possible pour un test ponctuel de l'équipe MédiAgenda.
- Non-régression : verdict lu dans **Prometheus** sur la fenêtre de l'essai (histogramme de MédiAgenda + compteurs de k6 filtrés par `testid`), **jamais** dans les résumés des exécuteurs : chacun n'a vu qu'un quart de la charge et ses seuils ne valent que pour sa part ; une moyenne de p95 n'est pas un p95. [Essai de référence : 4 exécuteurs, 40 it/s, p95 serveur 112 ms ; job nocturne ≈ 9 min.]

### 3. Tests d'infrastructure : Testinfra en CI, Goss non retenu, Terratest manuel

- **Testinfra** (pytest-testinfra 10.2) : tests des rôles Ansible dans `plateforme/ansible/tests/infra/`, lancés par la CI sur `runner01` et chaque nuit sur tout le socle. Même langage que nos outils (Python), assertions riches, connexion par l'inventaire Ansible. [Suite complète du socle ≈ 4 min.]
- **Goss** : essayé (M29-E07) ; on **ne garde pas les deux**. Goss est excellent pour une sonde de santé locale rapide (`goss serve`) mais ferait doublon avec Testinfra en CI et avec node_exporter/blackbox pour la supervision ; deux formats de tests pour les mêmes rôles, c'est deux vérités. Révision si on industrialise des images dorées où un binaire autonome sans Python est un avantage.
- **Terratest** (1.0, Go 1.26) sur le module `vm-debian` : crée de vraies VMs (2290-2299), ≈ 9 min et 1 Go de mémoire par exécution [mesuré]. **Pipeline manuel** (avant une version du module), jamais à chaque MR ; filet : nettoyeur planifié (`outils/nettoyer-terratest.sh`, M29-E21). À chaque MR : `tofu validate`, `tofu test` avec fournisseurs simulés et conftest sur un plan.

### 4. Validation statique : kubeconform, conftest et Kyverno CLI

- **kubeconform 0.8** avec les schémas des CRD générés depuis le cluster (paquet `schemas-crd`) : syntaxe et schéma de tout manifeste rendu, sans `-ignore-missing-schemas` (qui masquerait les CRD).
- **conftest 0.71 / OPA 1.21 (Rego v1)** : règles sur les **plans OpenTofu** (`tofu show -json`) — rien d'autre ne lit un plan — et sur les manifestes rendus ; tests `opa test` et **cas de référence** (plan dangereux, M29-E19).
- **Kyverno CLI** : rejoue en CI les politiques CEL **qui s'appliquent à l'admission** (M26) sur les manifestes rendus. Pourquoi deux moteurs : Kyverno est la vérité de l'admission (pas de dérive entre CI et cluster), conftest couvre ce que Kyverno ne voit pas (plans, fichiers hors Kubernetes). On n'écrit pas la même règle dans les deux.
- Le tout dans le composant CI/CD **`validation`** (pyramide : statique à chaque MR, Testinfra et charge la nuit, Terratest à la demande). Aucun job de validation en `allow_failure` (M29-E19).

### 5. Exception GitOps : `chaos-experiences`

Les expériences de chaos sont créées **depuis `adm01`** dans l'espace `chaos-experiences`, **hors Argo CD**. Pourquoi : une expérience est un **geste daté** (« injecter 5 minutes de latence maintenant »), pas un état désiré. Sous Argo CD, une expérience terminée resterait « à l'état voulu » (désynchronisée, ou réappliquée à chaque synchronisation : la panne reviendrait), et la synchronisation automatique déclencherait des pannes au gré des fusions.

Garde-fous de l'exception :
1. **Fichiers versionnés avant usage** dans `plateforme/resilience/chaos/` ou `journees-de-jeu/<date>/`, relus en MR ; on n'applique jamais un YAML qui n'est pas sur `main`.
2. **Espace dédié** `chaos-experiences` ; RBAC : seuls les groupes OIDC de la plateforme y écrivent ; Chaos Mesh lui-même, ses valeurs, ses politiques réseau et **les annotations des espaces** restent sous Argo CD.
3. **Filtre d'espaces** de Chaos Mesh (`enableFilterNamespace`) : seules trois espaces non productifs sont visables ; une expérience vers `*-prod` ne sélectionne rien.
4. **Durée obligatoire** (ou `deadline` dans un `Workflow`), Schedules en pause hors observation (RB-294).
5. **Traçabilité** : journal de l'API (audit, M22) + `docs/qualite/journal/` + catalogue des résultats.
6. Exception inscrite au registre des exceptions de la plateforme (M26), revue annuelle par la RSSI.

## Options étudiées (résumé)

| Sujet | Retenu | Écarté | Raison principale de l'écart |
|---|---|---|---|
| Chaos | Chaos Mesh 2.8 | LitmusChaos 3, Chaos Toolkit | MongoDB/Bitnami et 4 composants de plus ; Chaos Toolkit : pas d'injection native dans les pods |
| Charge | k6 + k6-operator | JMeter, Gatling, Locust | lisibilité en MR, distribution intégrée, Prometheus |
| Infra | Testinfra | Goss (en double), InSpec (licence Chef) | une seule vérité, même langage que l'outillage |
| Modules | Terratest manuel | Terratest à chaque MR | 9 min et une VM par exécution |
| Statique | kubeconform + conftest + Kyverno CLI | kubeval (abandonné), Datree (fermé) | maintenu, schémas des CRD, Rego v1 |

## Conséquences

- Facile : prouver à l'auditeur qu'une MR dangereuse est arrêtée (cas de référence), qu'une version plus lente est vue la nuit même, qu'une panne de dépendance a été jouée et ses actions suivies.
- Difficile : maintenir les schémas des CRD à jour à chaque montée d'opérateur ; garder la recette assez proche de la prod pour que les mesures veuillent dire quelque chose ; ne pas laisser l'exception `chaos-experiences` devenir un passe-droit.
- Limites acceptées : pas de chaos en production ; pas de tests de contrat entre MédiAgenda et MédiDoc (à F7) ; la non-régression ne couvre que MédiAgenda.

**Déclencheur de révision** : première demande de chaos en production ; une équipe applicative qui veut ses propres expériences ; Chaos Mesh sans version compatible avec la mineure suivante de Kubernetes ; coût de la suite nocturne > 30 min.
