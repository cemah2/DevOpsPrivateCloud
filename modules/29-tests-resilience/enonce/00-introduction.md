# Module 29 — Introduction : tests et résilience

## Le lundi de la vaccination

Lundi, 8 h 40. Nadia Roussel ouvre la réunion d'équipe avec le post-mortem de la campagne de vaccination de l'an dernier, ressorti pour l'occasion : ce matin-là, 3 000 patients ont voulu réserver en même temps, MédiAgenda (encore chez InfoGér) a répondu en 9 secondes puis plus du tout, et personne n'avait la moindre idée du débit qu'il tenait. La campagne revient dans six semaines, et cette fois sur **notre** plateforme. Karim ajoute deux souvenirs plus récents : un rôle Ansible fusionné « parce qu'il passait » qui avait désactivé `auditd` sur trois VMs (M26), et un `tofu apply` qui a failli remplacer `dns02` parce que personne n'avait lu la ligne `-/+` du plan. Claire Morel écrit le soir même.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Tests et résilience — on arrête de croire, on vérifie
>
> Bonjour,
>
> La plateforme marche. Je ne sais pas **jusqu'où**, et je ne sais pas ce qu'elle fait quand quelque chose casse. Avant l'audit HDS et la mise en production générale, je veux :
> 1. des **tests automatiques à chaque MR**, du moins cher au plus cher : schémas des manifestes, règles sur les plans OpenTofu, tests des rôles Ansible et du module `vm-debian` sur de vraies machines ;
> 2. la **preuve chiffrée** que MédiAgenda tient la charge de la campagne en respectant ses SLO (M21), mesurée en **recette**, jamais en production ;
> 3. des **pannes provoquées exprès**, en heures ouvrées, dans un cadre que Sophie aura relu, plutôt que subies à 3 h du matin ;
> 4. une stratégie écrite : ce qu'on teste, quand, ce que ça coûte, et ce qu'on ne teste pas.
>
> Karim te fait d'abord passer le test habituel. Lucas a déjà commencé quelque chose sur les plans et sur la charge ; tu le reliras.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 29, MédiSphère a sa chaîne de tests et de résilience **v1** (étiquette `resilience-v1` de `plateforme/medisphere`, posée au mini-projet M29-E25). Les paliers 1 et 2 (ce fichier, `01-decouverte.md`, `02-operationnel.md`) en posent les briques :

| Brique | Où | Exercice |
|---|---|---|
| **kubeconform 0.8** sur `adm01` ; schémas des CRD générés depuis `k8s-par1` (`outils/schemas-crd.sh`, convertisseur officiel de kubeconform) et publiés comme paquet générique GitLab **`schemas-crd`** ; rendu des charts des Applications (`outils/rendre-charts.sh`) | `plateforme/k8s`, `plateforme/gitops` | E02 |
| Politiques **Rego v1** sur les plans OpenTofu (`tofu show -json`) avec leurs tests : VMID par état, pool, étiquettes, destruction du socle ; **conftest 0.71 / OPA 1.21** sur `adm01` | `plateforme/politiques/rego/tofu/`, `rego/donnees/` | E03 |
| **pytest-testinfra 10.2** : tests des rôles `durcissement`, `node_exporter`, `alloy` et du temps (chrony), lancés par la CI sur `runner01` | `plateforme/ansible/tests/infra/` | E04 |
| Projet **`plateforme/resilience`** (clone `~/src/resilience`) ; **k6 1.8** sur `adm01` ; premier test de charge de la recette | `plateforme/resilience/charge/` | E05 |
| Scénarios k6 par parcours, seuils = SLO (250 ms), résumés JSON versionnés, corrélation avec Prometheus, cache Valkey et HPA | `charge/parcours-recette.js`, `charge/resultats/` | E06 |
| **Goss 0.4** en comparaison : rôle `goss`, `goss serve` sur le port **8099** de `dns02` et `nbx01`, sondé par le blackbox de `mon01` ; décision écrite | `plateforme/ansible`, `mon01`, `docs/qualite/` | E07 |
| **Terratest 1.0** (Go 1.26) sur le module `vm-debian` : VMs `tt-<suffixe>`, VMID 2290-2299, sous-pool Proxmox `lab/terratest`, identité Proxmox dédiée, pipeline manuel | `plateforme/tofu-modules/vm-debian/test/` | E08 |
| **Chaos Mesh 2.8** : Application `chaos-mesh`, espace `chaos-mesh`, filtre d'espaces, espace des expériences `chaos-experiences`, politique d'admission, première expérience | `plateforme/gitops`, `plateforme/k8s`, `plateforme/resilience/chaos/` | E09 |
| Composant CI/CD **`validation`** (kubeconform, conftest, opa test, Testinfra), consommé par quatre projets | `plateforme/ci-templates` | E10 |
| Revue des MR de Lucas ; stratégie de tests et RB-290 | `docs/qualite/` | E11, E12 |

Le **palier 3** (`03-production.md`) se sert de ces outils là où ça peut faire mal : expériences de chaos réseau et ressources, **k6-operator** (espace `k6`) et non-régression de performance, bascule de la base et perte d'un nœud RabbitMQ sous charge, **journée de jeu**, ADR-0290. Le **palier 4** (`04-expert.md`) casse la CI, une expérience, Terratest et Testinfra, puis descend dans le `chaos-daemon`. Le **mini-projet** (`05-mini-projet.md`) livre l'ensemble.

---

## Les notions du module

### La pyramide des tests d'infrastructure

Un test coûte du temps (combien de minutes avant la réponse ?), des ressources (une VM, un cluster, de la charge sur la recette) et de l'entretien (un test fragile qu'on finit par ignorer est pire que pas de test). Il apporte une **confiance** qui dépend de ce qu'il touche de réel. La pyramide range les tests par coût croissant : beaucoup de tests bon marché en bas, qui tournent à chaque MR en quelques secondes ; quelques tests chers en haut, déclenchés exprès.

```
                       ▲ coût, durée, réalisme
                      ╱ ╲
                     ╱   ╲        chaos (Chaos Mesh) et journées de jeu ── planifiés, annoncés, en recette
                    ╱ E2E ╲       charge (k6, k6-operator) ── à la demande, en recette, seuils = SLO
                   ╱───────╲
                  ╱ intégr. ╲     Terratest : une vraie VM créée puis détruite ── manuel (≈ 10 min)
                 ╱  réelle   ╲    Testinfra / Goss : l'état réel des VMs du socle ── nuit + à la demande
                ╱─────────────╲
               ╱   unitaire    ╲  opa test : chaque règle Rego sur des plans d'exemple ── chaque MR (s)
              ╱─────────────────╲
             ╱     statique      ╲ kubeconform, conftest sur les manifestes rendus et sur le
            ╱                     ╲ plan (sans rien appliquer), lint ── chaque MR (secondes)
           ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
```

| Étage | Question posée | Outil du module | Ce qu'il **ne** voit **pas** | Coût |
|---|---|---|---|---|
| Statique | Le fichier est-il bien formé, conforme au schéma de l'API, conforme à nos règles ? | kubeconform, conftest (manifestes), `ansible-lint`, `tofu validate` (M04-M05) | le comportement : un manifeste valide peut ne jamais démarrer | secondes, aucun accès au lab |
| Statique sur le plan | Ce que **va faire** `tofu apply` respecte-t-il nos règles (plages, pool, étiquettes, destructions) ? | conftest sur `tofu show -json` | ce que le fournisseur fera vraiment ; ce qui n'est pas dans le plan | secondes, mais il faut un plan (accès en lecture à Proxmox et à l'état) |
| Unitaire | Chaque règle accepte-t-elle ce qu'elle doit accepter et refuse-t-elle ce qu'elle doit refuser ? | `opa test` | si la règle est **la bonne** règle | secondes |
| Intégration réelle | L'état des machines est-il celui que le rôle promet ? Le module crée-t-il une VM qui fonctionne ? | Testinfra, Goss, Terratest | la tenue en charge, les pannes | minutes, de vraies machines (Terratest en crée une) |
| Bout en bout / charge | Le service tient-il le débit attendu avec son SLO ? | k6, k6-operator | les pannes d'un composant | dizaines de minutes, de la charge sur la recette |
| Résilience | Le service reste-t-il dans son SLO quand un composant tombe ? | Chaos Mesh, journées de jeu | ce que l'hypothèse n'a pas prévu | heures de préparation, une équipe |

Trois règles en découlent : un test **qui ne peut pas échouer** ne vérifie rien (vérifie toujours qu'il passe au rouge sur un cas faux) ; un test cher qui tourne trop souvent finit désactivé (place chaque test à l'étage où il coûte le moins pour ce qu'il détecte) ; et ce qu'on décide de **ne pas** tester s'écrit (E12), sinon on croit que c'est couvert.

### Tests de charge : modèles, percentiles, seuils

**Deux modèles de charge.** Dans un modèle **fermé**, un nombre fixe d'utilisateurs virtuels (*VUs*) bouclent : chacun attend la réponse avant de recommencer. Si le serveur ralentit, les VUs envoient **moins** de requêtes : la charge baisse d'elle-même et le test sous-estime le problème (c'est l'*omission coordonnée*). Dans un modèle **ouvert**, les requêtes arrivent à un **taux** fixé (n itérations par seconde), que le serveur suive ou non, comme des patients qui ne se concertent pas : si le serveur ralentit, les requêtes en cours s'accumulent. Une campagne de vaccination est un modèle ouvert. Avec k6 : exécuteurs `constant-vus`/`ramping-vus` (fermé), `constant-arrival-rate`/`ramping-arrival-rate` (ouvert). Dans un modèle ouvert, si k6 n'a plus de VU libre pour lancer une itération, il la **perd** (`dropped_iterations`) : le débit demandé n'a pas été tenu, et le test ne prouve plus rien.

**Percentiles, pas moyennes.** Une moyenne de 120 ms peut cacher 8 % de requêtes à 2 s. Le p95 (95 % des requêtes sont plus rapides) et le p99 décrivent ce que vivent les patients. Le SLO de latence de MédiAgenda (M21) se lit ainsi : **95 % des requêtes en moins de 250 ms**, c'est-à-dire la **part** des requêtes sous 250 ms, calculée côté serveur sur l'histogramme `mediagenda_http_request_duration_seconds`.

**Seuils.** Un test de charge sans seuil n'échoue jamais : il produit des chiffres que quelqu'un doit lire. Dans k6, les `thresholds` (p95 < 250 ms, taux d'échec < 0,5 %) transforment la mesure en verdict et en code de sortie ; les `check()` comptent, mais **ne font jamais échouer** un test à eux seuls. Un seuil peut aussi **arrêter** le test (`abortOnFail`) avant de mettre la recette à genoux pour rien.

**Client et serveur.** k6 mesure ce que voit le client (réseau, passerelle, TLS compris) ; Prometheus mesure ce que voit l'application. Les deux doivent raconter la même histoire ; l'écart s'explique (E06).

### Ingénierie du chaos

Le chaos n'est pas « casser pour voir ». C'est une **expérience** au sens scientifique :

1. **État stable** : une grandeur mesurable qui dit que le service va bien, du point de vue de l'utilisateur. Chez MédiSphère : les SLO de MédiAgenda (part sous 250 ms, disponibilité 99,5 %), relevés sur Prometheus.
2. **Hypothèse** : « si un pod de l'API tombe pendant une charge de 20 requêtes/s, l'état stable se maintient (le Service retire le pod, les autres absorbent) ». Elle doit pouvoir être **fausse**.
3. **Injection** de la panne, bornée dans le temps (`duration`).
4. **Mesure** avant, pendant, après ; conclusion : hypothèse confirmée, ou faiblesse trouvée (c'est le but : mieux vaut la trouver un mardi à 14 h).

Le **rayon d'action** (*blast radius*) est ce que l'expérience peut toucher au pire. On le réduit par construction : un seul pod (`mode: one`), une durée courte, la **recette seulement**, un mécanisme d'arrêt préparé avant. Les **garde-fous** de ce module ne reposent pas sur la bonne volonté : le filtre d'espaces de Chaos Mesh (seuls les espaces annotés sont visables), une politique d'admission qui refuse tout objet de chaos hors de `chaos-experiences` et toute cible hors de la liste, un quota, un runbook d'arrêt d'urgence (RB-292). La production n'est **jamais** une cible : la confiance s'y gagne par des expériences répétées en recette et par des journées de jeu préparées (palier 3), pas par un essai sur les patients.

---

## Architecture du module

```
 adm01 (MGMT 10.10.10.10)                                     runner01 (CI)
   kubeconform · opa · conftest · k6 · go · tofu                 jobs du composant validation (image outils-validation)
   ~/src/resilience ── k6 run ──┐                                 testinfra (ansible://, clé de CI) ──SSH 22──▶ VMs du socle
   go test -tags integration ───┼──────────────▶ pve01:8006 (jeton wb-terratest@pve!terratest)
          │                     │                   └─ sous-pool lab/terratest : tt-xxxxxx (VMID 2290-2299, vsandbox)
          │                     │                                         └── NetBox (nbx01) : adresse allouée puis rendue
          │                     ▼
 ┌──────── k8s-par1 ───────────────────────────────────────────────────────────────────────────────────┐
 │  gw-par1 ──▶ mediagenda-recette : Rollout mediagenda (HPA M28) ──▶ Pooler PgBouncer ──▶ mediagenda-db │
 │                     ▲                       └──▶ valkey (cache des créneaux)                         │
 │                     │  pod-failure, … (chaos-daemon du nœud : conteneurs, réseau, processus)         │
 │  chaos-mesh  : chaos-controller-manager (filtre d'espaces, webhooks) · chaos-daemon (DaemonSet,       │
 │                privilégié : exception EXC-K-005) · pas de tableau de bord                            │
 │  chaos-experiences : PodChaos, … (quota, VAP medisphere-chaos-espaces)                               │
 │      visables : mediagenda-recette · medinotif-recette · wb-essais   (annotation chaos-mesh.org/inject)│
 │      JAMAIS  : *-prod · messagerie · espaces de plateforme                                            │
 │  supervision : kps (Prometheus, SLO Pyrra) ◀── corrélation des tests de charge                       │
 └──────────────────────────────────────────────────────────────────────────────────────────────────────┘
 mon01 (10.10.20.19) : blackbox ──HTTP 8099──▶ dns02, nbx01 (goss serve) ── alertes TestsGossEnEchec
 GitLab : plateforme/{k8s,gitops,infra,ansible,politiques,resilience,tofu-modules,ci-templates,medisphere}
          paquet générique schemas-crd (plateforme/k8s) · composant ci-templates/validation@v2.11.0
```

---

## Règles du module

1. **Jamais la production comme cible.** Ni test de charge, ni expérience de chaos, ni Terratest sur ce qui sert les patients. Les scripts k6 refusent par construction toute autre cible que la recette (liste d'autorisation, E05) ; Chaos Mesh ne peut viser que trois espaces (E09). Un garde-fou qui gêne se discute en revue, il ne se contourne pas.
2. **Données factices seulement.** Praticiens `dr-k6-…`, patients « Patient Charge … », motifs marqués. Aucun export de production, aucun NIR, jamais, même « juste pour le test » (E11).
3. **Tout test laisse le lab dans l'état où il l'a trouvé** : rendez-vous annulés, VMs de test détruites, expériences supprimées. Un test qui laisse des traces les cache dans le test suivant.
4. **Un test de charge ou une expérience de chaos s'annonce** (heure de début et de fin) : Julien et ses développeurs utilisent la recette. Ici, ton journal `docs/qualite/journal/` fait office de canal.
5. **Tout par Git**, comme depuis le M20 : composants par `plateforme/gitops`, espaces et droits par `plateforme/k8s`. Une seule exception écrite dans ce module : les objets de chaos, créés depuis `adm01` dans `chaos-experiences` (E09, ADR-0290 au palier 3).
6. **Mémoire.** Profil du bloc G ≈ 111 Go. Ce palier ajoute ≈ 0,5 Gi de `requests` dans le cluster (Chaos Mesh : contrôleur 256 Mi, un `chaos-daemon` de 64 Mi par nœud) et, le temps d'un test Terratest, **une** VM de 1 Go sur `pve01` (deux tests ne tournent jamais en même temps). Les tests de charge consomment surtout du CPU : regarde `kubectl top nodes` pendant E06.

---

## Préparer l'environnement

### État d'entrée : `plateforme-dev-v1`

Le mini-projet du M28 doit être vert : HPA de MédiAgenda, KEDA, locataires, portail.

```
admin@adm01:~$ lab/bin/check 28 25
admin@adm01:~$ git -C ~/medisphere fetch --tags && git -C ~/medisphere tag -l 'plateforme-dev-v1'
admin@adm01:~$ kubectl -n mediagenda-recette get rollout mediagenda && kubectl -n mediagenda-recette get hpa mediagenda
admin@adm01:~$ curl -fsS https://mediagenda-recette.apps.par1.medisphere.internal/pret
admin@adm01:~$ kubectl get crd | grep -c -E 'chaos-mesh.org|k6.io'
admin@adm01:~$ kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.chaos-mesh\.org/inject}{"\n"}{end}' | awk -F'\t' '$2!=""'
```

L'avant-dernière commande doit répondre **0** (aucune CRD de Chaos Mesh ni de k6-operator) et la dernière ne rien afficher (aucun espace annoté) : si ce n'est pas le cas, quelqu'un a déjà installé quelque chose ; trouve quoi et pourquoi avant E09.

Vérifie aussi les versions des outils déjà présents, que ce module réutilise :

```
admin@adm01:~$ tofu version && helm version --short && kustomize version && kubectl version --client
admin@adm01:~$ git -C ~/src/ci-templates fetch --tags && git -C ~/src/ci-templates tag -l 'v2.*' | sort -V | tail -3
```

Note la dernière étiquette publiée de `plateforme/ci-templates` : le composant `validation` d'E10 sortira dans la version **mineure suivante** (`v2.11.0` si la dernière est `v2.10.0` ; adapte sinon, et règle `WB_M29_VERSION_VALIDATION` dans `lab/lab.env`).

### Bilan de capacité

Comme aux M27 et M28, compare `requests` et allouable sur chaque travailleur, et note la marge dans `docs/qualite/capacite.md` :

```
admin@adm01:~$ kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | grep -A7 'Allocated resources'
admin@adm01:~$ kubectl top nodes
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Il faut ≈ 0,5 Gi de marge dans le cluster pour Chaos Mesh (E09) et 1,5 Go libres sur `pve01` pour la VM de Terratest (E08). Pendant un test de charge, la recette de MédiAgenda va monter en réplicas (HPA du M28) : la marge doit aussi les absorber.

### Outils de `adm01`

Chaque exercice installe ce dont il a besoin, toujours avec **vérification d'empreinte** (fichier de sommes publié par le projet), dans `/usr/local/bin` :

| Outil | Version | Installé en |
|---|---|---|
| kubeconform | 0.8.x | E02 |
| OPA, conftest | 1.21.x, 0.71.x | E03 |
| pytest-testinfra (environnement `uv` de `plateforme/ansible`) | 10.2.x | E04 |
| k6 | 1.8.x | E05 |
| Go | 1.26.x | E08 |

Versions de référence et liens : [`annexes/versions-bloc-G.md`](../../../annexes/versions-bloc-G.md).

### Variables de `lab/lab.env`

Facultatives (les valeurs par défaut conviennent au lab de référence) : `WB_M29_RECETTE_URL` (`https://mediagenda-recette.apps.par1.medisphere.internal`), `WB_M29_PROJET_RESILIENCE` (`plateforme/resilience`), `WB_M29_TEMOIN_URL` (Prometheus témoin de `mon01`, `http://mon01.par1.medisphere.internal:9090`), `WB_M29_CHAOS_NS` (`chaos-experiences`), `WB_M29_VERSION_VALIDATION` (`v2.11.0`), `WB_M29_GOSS_HOTES` (`dns02 nbx01`).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 29 <XX>`. Elles sont en **lecture seule** : elles lisent GitLab (jeton `read_api` des checks), le cluster (compte `wb-checks` ; la ClusterRole agrégée `wb-checks-services-m29` que tu poses en E09 couvre Chaos Mesh et k6-operator), Prometheus, le Prometheus témoin de `mon01`, NetBox et, en consultation, `pve01`. Elles ne lisent jamais un Secret. Quand elles rejouent un outil (kubeconform, opa, conftest, k6 `inspect`), c'est sur une **copie temporaire** des fichiers lus dans GitLab.
- Celles d'E05 et E06 regardent l'historique des métriques de la recette (7 jours) : lance les tests **avant** de vérifier.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M29-EXX/` : `k8s/` reproduit `plateforme/k8s`, `gitops/` `plateforme/gitops`, `charts-miroir/`, `politiques/`, `ansible/`, `tofu-modules/`, `infra/`, `ci-templates/`, `resilience/` `plateforme/resilience`, `medisphere/` la documentation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05                                (palier 1)
E06 (après E05) ─ E07 (après E04) ─ E08 ─ E09 ─ E10 ─ E11 ─ E12   (palier 2)
```

1. **E01** à froid.
2. **E02 → E05** dans l'ordre : chacun installe son outil et pose les fichiers que le composant d'E10 assemblera.
3. **E06** prolonge E05, **E07** compare Goss à Testinfra (E04). **E08** et **E09** sont indépendants (Proxmox d'un côté, cluster de l'autre). **E10** assemble E02, E03 et E04 : fais-le après eux. **E11** et **E12** à la fin.

Durée indicative : palier 1, 8 à 10 heures ; palier 2, 12 à 15 heures.

## Pour aller plus loin

- kubeconform : <https://github.com/yannh/kubeconform> · conftest : <https://www.conftest.dev/> · OPA et Rego v1 : <https://www.openpolicyagent.org/docs/> (*Policy Language*, *Policy Testing*, *OPA 1.0*)
- pytest-testinfra : <https://testinfra.readthedocs.io/> · Goss : <https://goss.readthedocs.io/> · Terratest : <https://terratest.gruntwork.io/docs/>
- k6 : <https://grafana.com/docs/k6/latest/> (*Scenarios*, *Thresholds*, *Open and closed models*, *End-of-test summary*)
- Chaos Mesh 2.8 : <https://chaos-mesh.org/docs/> · *Principles of Chaos Engineering* : <https://principlesofchaos.org/> · fiche [`litmuschaos.md`](../../../annexes/decouverte/litmuschaos.md)
- Gil Tene, *How NOT to Measure Latency* (omission coordonnée) ; Google SRE Workbook, chapitre *Implementing SLOs*.
