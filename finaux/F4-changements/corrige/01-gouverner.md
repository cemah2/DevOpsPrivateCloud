# Final F4 — Phase 1 : Gouverner — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence : il en existe d'autres, jugées sur les mêmes critères.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- scripts (`sonde-continuite.sh`, `mesurer-interruption.sh`) : `bash -n` et `shellcheck` ; manifestes et règles : YAML valide ; tableau : JSON valide ;
- fonctions de lecture de l'en-tête des fiches et de calcul de la mesure (`checks/_f4-montees.sh`) rejouées sur des fiches d'exemple ;
- `TestRun` : mêmes champs et réglages que celui du M29-E14 (k6-operator 1.7, `restricted`, écriture distante vers un réplica).

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- règles d'enregistrement et leurs tests `promtool` : non exécutés à la rédaction (outil indisponible dans l'environnement de rédaction) — lance `promtool check rules` et `promtool test rules` avant la MR, comme ta CI le fait ;
- présence de l'étiquette `expected_response` dans les séries `k6_http_reqs_total` envoyées par l'écriture distante de k6 1.8 ; si elle manque, remplace le filtre par `status=~"0|5.."` (et documente-le) ;
- code de la réponse anonyme du RGW et de l'interface de RabbitMQ à une sonde `https_2xx` (redirections, page de connexion) ;
- seuils et durées de la mesure : ceux d'un lab de référence imaginé.

**Fichiers** : [`fichiers/S01/`](fichiers/S01/) et [`fichiers/S02/`](fichiers/S02/), en extraits des projets : `medisphere/…` = `plateforme/medisphere`, `resilience/…` = `plateforme/resilience`, `observabilite/…`, `ansible/…`. Les `*.extrait*` sont à fusionner dans le fichier existant (l'emplacement est en tête).

---

### F4-S01 — Le processus de changement de MédiSphère

**Solution**

Documents de référence : [`processus.md`](fichiers/S01/medisphere/docs/changements/processus.md) et [`fiches/modele.md`](fichiers/S01/medisphere/docs/changements/fiches/modele.md).

Ce qu'un bon processus contient, et pourquoi :

1. **Une définition** qui exclut explicitement la livraison applicative par GitOps (M19-M20) : elle a déjà ses garde-fous (CI, signature, promotion par MR, canary). Sans cette exclusion, le processus devient un frein que tout le monde contourne.
2. **Trois catégories**, chacune avec des exemples **de notre plateforme** :
   - *standard* : répété, runbook éprouvé, mesure passée connue (correctif Kubernetes dans la mineure par RB-142, images Kolla dans une série par RB-101, corrective Ceph par RB-082) ; pré-approuvé une fois, il perd ce statut dès qu'une exécution dépasse son objectif ;
   - *normal* : tout le reste, approuvé par Claire, plus Sophie si la sécurité ou les données de santé sont en jeu ;
   - *urgent* : approuvé par écrit même brièvement, fiche rédigée après, revue obligatoire.
3. **Le go/no-go** comme moment réel (10 minutes, juste avant, critères écrits), et le **no-go comme résultat normal** : CHG-3403 en est l'exemple.
4. **Les fenêtres et le gel**, avec la règle qui rend la mesure exploitable : un seul changement par domaine et par fenêtre.
5. **La mesure** : objectif fixé avant, relevé après, avant/pendant/après dans la fiche.
6. **La revue après mise en œuvre**, qui alimente la revue du trimestre (S14).

Le **calendrier** se construit à rebours depuis la fin du contrat d'InfoGér (six semaines) : processus et sonde la semaine 1 (rien ne se mesure sans eux), montées semaines 2 et 3 (la plateforme est stable avant d'accueillir Legacy-RDV), OpenStack en fin de semaine 3 (cluster arrêté : seul changement de la fenêtre), migration des VMs semaine 4 (la mémoire rendue par OpenStack), Legacy-RDV en recette semaine 5, bascule semaine 6 avec un gel de 48 h, décommissionnement ensuite.

Le **modèle de fiche** porte un en-tête YAML : c'est ce qui permet aux outils (checks, revue du trimestre, éventuel tableau de bord des changements) de lire catégorie, statut, décision, fenêtre et mesure sans analyser de prose.

**Explications**

Un processus de changement ne réduit pas le risque par la paperasse : il le réduit en forçant trois choses **avant** d'agir — savoir ce qu'on va voir si ça se passe bien (mesure et objectif), savoir quand on s'arrête (critères d'abandon), savoir comment on revient (retour arrière **testé**). Le reste (approbation, communication) sert à ce que ces trois réponses aient été relues par quelqu'un d'autre.

**Alternatives**
- ITIL 4 « change enablement » avec un comité (CAB) hebdomadaire : adapté à une grande DSI, trop lent pour une équipe de cinq ; la relecture de MR joue ce rôle.
- Changements entièrement automatisés (déploiement progressif, retour automatique sur SLO) : l'idéal pour les applications (Argo Rollouts, M20) ; pas encore pour Ceph ou OpenStack.
- Un outil de gestion de tickets dédié : la fiche Markdown dans Git, relue par MR, a l'avantage d'être versionnée avec le code qu'elle décrit.

**Pièges classiques**
- Un modèle sans critère d'abandon chiffré : on décide de « continuer encore un peu » à 22 h 50.
- Un « retour arrière » qui n'a jamais été joué, ou qui n'existe pas (moniteurs Ceph, plan de contrôle Kubernetes) sans que la fiche le dise.
- Un objectif d'interruption écrit après la mesure.
- Deux changements dans la même fenêtre : l'interruption ne s'attribue plus.
- Un calendrier qui ignore la mémoire du lab (OpenStack et le cluster ne tournent pas ensemble).

**En production chez MédiSphère**
Les fiches sont relues par MR ; un job de CI vérifie l'en-tête (clés présentes, dates cohérentes) et publie un calendrier des changements à venir pour le support ; la revue du trimestre est présentée à la direction et à l'auditeur HDS.

---

### F4-S02 — La sonde de continuité

**Solution** (une solution de référence ; ce `LIBRE` s'évalue sur la mesure obtenue et sa justesse)

*1. Charge constante.* [`continuite/sonde-continuite.js`](fichiers/S02/resilience/continuite/sonde-continuite.js) : deux scénarios `constant-arrival-rate` (débit fixe même quand les réponses ralentissent : pas d'omission coordonnée), `prod_lecture` à 2 itérations/s plafonnées sur la **seule** route `GET /api/v1/creneaux` pour un praticien fictif (`dr-sonde-<n>` : aucune donnée de patient lue), `recette_ecriture` à 1 itération/s (création puis annulation, J+90 et au-delà) ; délai de 5 s par requête (une coupure doit se voir, pas s'étirer) ; seuils avec `abortOnFail: false` (une sonde ne s'arrête pas au premier incident). [`continuite/testrun.yaml`](fichiers/S02/resilience/continuite/testrun.yaml) : un seul exécuteur (charge faible, compteurs cohérents), mêmes réglages que le M29-E14 (Harbor, `restricted`, `/tmp` en `emptyDir`, écriture distante vers `prometheus-kps-prometheus-0`, autorisée par la CNP `prometheus-ecriture-k6` qui vise déjà les exécuteurs `runner: "true"`), envoi toutes les 5 s. [`outils/sonde-continuite.sh`](fichiers/S02/resilience/outils/sonde-continuite.sh) la démarre pour un CHG donné (`testid=sonde-continuite-CHG-34xx`), affiche son état, l'arrête. Décision écrite : créée depuis `adm01`, pas par Argo CD (un instrument lancé pour une fenêtre n'est pas un état désiré ; même exception que les expériences de chaos, ADR-0290).

```
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh demarrer CHG-3402 30m
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh etat
NOM                ETAPE     ARGUMENTS
sonde-continuite   started   --tag testid=sonde-continuite-CHG-3402 --out experimental-prometheus-rw
```

*2. Sondes externes.* [`supervision_temoin.yml.extrait-F4`](fichiers/S02/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-F4) : un groupe par service (`continuite-mediagenda`, `-medidoc`, `-rabbitmq`, `-portail`), étiquette `service`, module `https_2xx` du M21 ; groupes `continuite-openstack*` préparés en commentaire pour S08, `continuite-legacy-rdv` pour S10. Groupes **distincts** de ceux du M21 : la mesure d'un changement et l'alerte permanente n'ont pas le même cycle de vie.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/supervision-temoin.yml --diff
admin@adm01:~$ curl -s -G http://mon01.par1.medisphere.internal:9090/api/v1/query \
    --data-urlencode 'query=count by (service) (probe_success{groupe=~"continuite-.+"})' | jq -c '.data.result[].metric'
```

*3. La mesure.* Sur le témoin, [`files/regles/continuite.yml`](fichiers/S02/ansible/roles/supervision_temoin/files/regles/continuite.yml) (+ [tests](fichiers/S02/ansible/roles/supervision_temoin/files/regles/continuite.test.yml)) : `continuite:sonde_en_erreur` (1 − `probe_success`) et `continuite:sondes_en_erreur:max` (`max by (job)` : garde `job="blackbox"`, donc **fédérée** sans toucher à `federation-mon01`). Dans le cluster, [`regles/continuite.yaml`](fichiers/S02/observabilite/regles/continuite.yaml) (+ [tests](fichiers/S02/observabilite/tests/continuite.test.yaml), [kustomization](fichiers/S02/observabilite/regles/kustomization.extrait-F4.yaml)) :

```promql
continuite:en_erreur = clamp_max(
    (max(continuite:sondes_en_erreur:max) or vector(0))
  + (continuite:charge_erreurs:taux30s > bool 0)
  + (continuite:prod_5xx:taux1m > bool 0), 1)
```

Secondes d'erreur d'une fenêtre de *D* secondes finissant à *FIN* : `avg_over_time(max(continuite:en_erreur)[Ds:15s]) * D` évaluée à *FIN*. Outil : [`outils/mesurer-interruption.sh`](fichiers/S02/observabilite/outils/mesurer-interruption.sh) (secondes d'erreur, couverture, requêtes envoyées et en erreur, 5xx et p95 de la prod, détail par sonde ; source `temoin` et groupes pour S08). Les checks du final font **exactement** ce calcul.

*4. Tableau.* [`plateforme-changement-en-cours.json`](fichiers/S02/observabilite/tableaux/plateforme/plateforme-changement-en-cours.json) (UID `f4-changement-en-cours`, [kustomization](fichiers/S02/observabilite/tableaux/kustomization.extrait-F4.yaml)) : en haut, quatre chiffres (secondes d'erreur de la période affichée, requêtes en erreur, budget Pyrra restant, charge active) ; puis la série d'interruption et ses trois composantes, une frise d'état par sonde, les taux d'erreurs, la latence p95/p99 serveur et la vitesse de consommation du budget.

*5. Documentation.* [`sonde-continuite.md`](fichiers/S02/medisphere/docs/changements/sonde-continuite.md) et [RB-340](fichiers/S02/medisphere/docs/changements/runbooks/RB-340-sonde-continuite.md).

*6. Répétition.* En recette, une réplique de l'API supprimée ne doit **rien** donner (deux répliques, Service, sondes de prod) : c'est déjà une information. Une erreur visible : NetworkChaos de partition API ↔ base de 60 s en `mediagenda-recette` (bibliothèque du M29) pendant la sonde ; la partie « recette » de la charge échoue 60 s, `continuite:charge_erreurs:taux30s` > 0 pendant 60 à 90 s, l'outil donne 60 à 90 s. Une mesure qui donne 0 ici est fausse.

**Explications**
- **Une série 0/1 à pas fixe** rend comparables des signaux de résolutions différentes (5 s, 30 s) et rend la mesure indépendante de l'opérateur : la même requête, sur la même fenêtre, donne le même nombre, à toi comme au check.
- **Pessimiste par construction** : un échantillon en erreur vaut tout son pas, un taux sur 1 min étale une rafale. C'est assumé : la mesure sert à comparer à un objectif et entre changements, pas à facturer des pénalités.
- **Témoin et cluster** : le témoin survit à l'arrêt du cluster (S08) et à une panne de Prometheus du cluster ; le cluster ajoute la charge et les métriques de l'application.
- **Lecture en production** : c'est la seule façon de voir ce que voient les cabinets ; elle est plafonnée, limitée à une route sans donnée de santé, approuvée et écrite.

**Alternatives**
- Mesurer côté serveur seulement (5xx de MédiAgenda) : ne voit pas une coupure de la Gateway, du DNS ou du réseau (aucune requête n'arrive).
- Mesurer avec des sondes seulement : résolution de 30 s, aucune vue des écritures.
- SLO de Pyrra comme seule mesure : fenêtres de 5 min à 28 j, pas faites pour une fenêtre de deux heures ; utile en contexte (budget consommé par le changement).
- Charge depuis `adm01` (k6 CLI) : plus simple, mais dépend d'une session ouverte, et `adm01` voit le lab depuis MGMT, pas depuis le cluster.

**Pièges classiques**
- `rate(…[30s])` sur des compteurs collectés toutes les 30 s : souvent un seul point dans la fenêtre, série vide, « 0 erreur » faux. D'où `[1m]` pour l'application.
- Oublier `or vector(0)` : sans erreur, la série n'existe pas ; avec `+`, toute l'expression devient vide.
- Une sonde qui suit les redirections vers une page de connexion : elle reste verte quand le service est cassé derrière.
- Un exécuteur `ramping-vus` ou `constant-vus` : quand le service ralentit, la charge baisse d'elle-même et masque la dégradation.
- Écrire vers le Service `kps-prometheus` (deux réplicas) : moitié des points par réplica (M29-E14).
- Laisser la sonde tourner hors fenêtre sans le dire : les mesures « avant » et « après » se mélangent.

**En production chez MédiSphère**
La sonde tourne en permanence à très faible débit (une requête toutes les 10 s), et passe à son débit de mesure pendant les fenêtres ; ses résultats alimentent un SLO « parcours utilisateur » distinct des SLO de service ; une sonde externe depuis PAR2 complète la vue.
