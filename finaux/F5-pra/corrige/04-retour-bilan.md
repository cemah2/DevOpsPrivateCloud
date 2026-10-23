# Final F5 — Phase 4 : Retour et bilan — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les documents de référence prolongent l'exercice imaginé de la phase 3 (sinistre le 2026-12-15 à 10:07, retour le 2026-12-16) : remplace heures et chiffres par les tiens.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- CloudNativePG 1.30, « Replica clusters » : la rétrogradation archive le segment contenant le point de contrôle d'arrêt sous forme de fichier `.partial` (c'est ce qui permet une bascule par l'archive seule) ; l'ancien primaire attend ensuite les WAL du nouveau ; le promu attend d'avoir rejoué jusqu'au LSN du jeton ; `primary` et `promotionToken` dans la même modification ; sans jeton, l'ancien primaire est à reconstruire ;
- CloudNativePG, « Monitoring » : requêtes personnalisées par `spec.monitoring.customQueriesConfigMap` (clés `query`, `target_databases`, `metrics` avec `usage` et `description`), métriques préfixées `cnpg_` ; étiquette `cnpg.io/reload` ;
- PowerDNS : un secondaire ne transfère une zone que si la série du primaire est **supérieure** à la sienne ;
- scripts : `bash -n` et `shellcheck` ; YAML valides.

---

### F5-S12 — Le retour à PAR1

**Solution**

Runbook de référence : [`RB-351-retour-par1.md`](fichiers/F5-S12/medisphere/docs/pra/runbooks/RB-351-retour-par1.md) ; fiche : [`CHG-3512-retour-par1.md`](fichiers/F5-S12/medisphere/docs/pra/exercices/2026-exercice-1/CHG-3512-retour-par1.md) ; base : [`pra-retour-par1.extrait.yaml`](fichiers/F5-S12/mediagenda-deploiement/overlays/prod/pra-retour-par1.extrait.yaml) (`mediagenda/deploiement`), [`50-mediagenda-db-par2.retour.extrait.yaml`](fichiers/F5-S12/k8s/sites/par2/mediagenda-prod/50-mediagenda-db-par2.retour.extrait.yaml) (`plateforme/k8s`, fichier de site de S06), et l'`ObjectStore` `cnpg-s3-par2` de PAR1 déclaré dès S06 ([`objectstore-par2.yaml`](fichiers/F5-S06/mediagenda-deploiement/overlays/prod/objectstore-par2.yaml), identité `cnpg-par1-lecture` de `s3-02`) ; preuves (extraits) : [`temoins-par2.extrait.csv`](fichiers/F5-S12/medisphere/docs/pra/mesures/2026-exercice-1/temoins-par2.extrait.csv), [`medidoc-par2.extrait.csv`](fichiers/F5-S12/medisphere/docs/pra/mesures/2026-exercice-1/medidoc-par2.extrait.csv) (les vrais fichiers s'appellent `temoins-par2.csv` et `medidoc-par2.csv`).

*0. Cartographier les flux avant de toucher quoi que ce soit.* C'est le cœur du scénario :

| Flux de temps normal | Que fait-il quand le lien revient ? | Pendant le retour |
|---|---|---|
| `filer.sync` `s3-01` → `s3-02` | rejoue les événements de `s3-01` depuis T0 (archives de l'ancien PAR1) ; ne touche pas aux compartiments propres à PAR2 | arrêté avant la levée (A8), relancé en B2 après vérification : PAR2 en aura besoin pour suivre la **nouvelle** archive de PAR1 |
| Minuterie `rclone` RGW → `s3-02` (**synchronisation**) | **supprime** à `s3-02` tous les documents déposés pendant le PRA (absents du RGW) | arrêtée avant la levée (A8) ; sens inverse en **copie** (B5, C2) ; relancée seulement en D5 |
| *Push mirrors* GitLab → `adm02` | réécrit (ou refuse, selon l'option « garder les références divergentes ») les branches du miroir modifiées pendant le PRA | désactivés avant la levée (A7) ; commits du miroir versés dans GitLab (B1, D4), puis réactivés |
| Transfert de zones dns01 → dns03 | rien tant que les zones de dns03 sont natives ; un secondaire refuse une série plus petite | dns01 porté au-dessus de la série de dns03, puis dns03 repassé secondaire (C6) |
| Archive et base CNPG | deux primaires, deux lignes temporelles, deux archives | ancien primaire clôturé (A6), reconstruit en réplique de PAR2 (B3), bascule par jetons (C3-C4) |

*1. Neutraliser PAR1 (phase A, depuis `pve01`).*
```
root@pve01:~# ssh adm01
admin@adm01:~$ export KUBECONFIG=~/.kube/k8s-par1-bris-de-glace.config    # RB-240
admin@adm01:~$ argocd app set mediagenda-prod --sync-policy none             # nom de ton Application de prod
admin@adm01:~$ kubectl -n mediagenda-prod patch cronjob temoin-rpo -p '{"spec":{"suspend":true}}'
admin@adm01:~$ kubectl -n mediagenda-prod scale rollout mediagenda --replicas=0   # ou kubectl argo rollouts
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-prod -- -c 'SELECT pg_switch_wal()'
```
Export de la divergence (requêtes de RB-351 §A4, `T0_EPOCH` lu dans `/var/lib/workbook/f5-t0` de `gw01`) : le **vrai RPO** (dernier témoin écrit à PAR1 avant T0 : 09:06:03 UTC, soit **8 min 01 s** au lieu de la borne de 8 min 58 s), les témoins de la divergence (dans Git), les rendez-vous réels de la divergence (chiffrés, à Julien, **jamais** dans Git). Copie de sécurité, puis clôture :
```
admin@adm01:~$ kubectl -n mediagenda-prod get pvc -l cnpg.io/cluster=mediagenda-db
admin@adm01:~$ kubectl -n mediagenda-prod apply -f instantane-mediagenda-db-1.yaml     # VolumeSnapshot, classe ceph-rbd
admin@adm01:~$ kubectl cnpg fencing on mediagenda-db "*" -n mediagenda-prod
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-prod                  # instances clôturées
```
*Push mirrors* désactivés par l'API de GitLab (un `PUT` par miroir, `enabled=false`) ; depuis `adm02`, `filer.sync` et la minuterie `rclone` de `s3-02` arrêtés et désactivés. Sophie constate ; la levée :
```
root@pve01:~/DevOpsPrivateCloud# lab/bin/break F5 9 --annuler
```
Le script vérifie lui-même que `mediagenda-db` est clôturé avant de retirer la table `f5_sinistre` des deux passerelles.

*2. Resynchroniser (phase B).*
- **Code** : pour chaque projet miroité modifié pendant le PRA :
  ```
  admin@adm01:~/src/deploiement$ git fetch ssh://miroir@adm02.par2.medisphere.internal/srv/miroirs/mediagenda/deploiement.git main:pra/inc-6109
  admin@adm01:~/src/deploiement$ git push origin pra/inc-6109        # puis MR vers main (avance rapide)
  ```
  (la lecture du miroir se fait avec une clé autorisée en lecture sur `miroir`, celle de RB-350 ; GitLab n'a pas bougé pendant le PRA, la MR est en avance rapide).
- **Base** : flux `k8s-par1` → `s3-02:8333` ouvert ; `ObjectStore` `cnpg-s3-par2` (déclaré en S06, lu pour la première fois) ; MR de l'état « B3 » de `pra-retour-par1.extrait.yaml` ; `kubectl delete cluster mediagenda-db -n mediagenda-prod` (les instantanés restent) ; synchronisation de la seule base (`argocd app sync … --resource postgresql.cnpg.io:Cluster:mediagenda-db`). `kubectl cnpg status` : réplique, *designated primary* qui rattrape l'archive de PAR2. Puis l'autorité de la nouvelle base copiée pour OpenBao (F1-S11 : chaque `Cluster` neuf génère sa propre `mediagenda-db-ca`).
- **MédiDoc** : liste des documents déposés à PAR2 depuis T0 (clés `documents/<id>`), copie et contrôle :
  ```
  admin@adm02:~$ aws --profile s3-02 s3api list-objects-v2 --bucket medidoc-documents --prefix documents/ \
      --query "Contents[?LastModified>='2026-12-15T09:07:00Z'].Key" --output text | tr '\t' '\n' | sed 's#^documents/##'
  admin@adm02:~$ rclone copy s3-02:medidoc-documents/documents rgw:medidoc-documents/documents --max-age 30h
  admin@adm02:~$ rclone check --one-way s3-02:medidoc-documents/documents rgw:medidoc-documents/documents --max-age 30h
  ```
  (profils `rclone` : identité de lecture de `s3-02`, identité d'**écriture** du RGW limitée à `medidoc-documents` ; le versionnage du RGW garde l'historique.)
- **Témoins** : `outils/pra/mesures-pra.sh temoins-depuis <T0_EPOCH> > temoins-par2.csv` (relancé en C2 pour le dernier).

*3. Bascule (phase C, coupure).* Gel des écritures à PAR2, derniers deltas, puis :
```
admin@adm02:~$ kubectl get cluster mediagenda-db-par2 -n mediagenda-prod -o jsonpath='{.status.demotionToken}'
```
(vide tant que PAR2 n'a pas fini sa rétrogradation : on attend, on ne force pas). La rétrogradation elle-même (C3) se fait comme la promotion de S09 : fichier de site `sites/par2/mediagenda-prod/50-mediagenda-db-par2.yaml` modifié et commité dans le miroir de `plateforme/k8s`, puis `kubectl apply --server-side` depuis `adm02`. Le jeton va dans la MR de promotion de PAR1 (état « C4 » : `primary` **et** `promotionToken` dans le même commit). PAR1 attend d'avoir rejoué jusqu'au LSN du jeton — il lit le `.partial` de PAR2 dans `cnpg-k8s-par2`, d'où l'importance du flux ouvert en B3 — puis se promeut sur une nouvelle ligne temporelle. DNS :
```
admin@dns01:~$ sudo pdnsutil zone increase-serial medisphere.internal        # répéter jusqu'à dépasser la série de dns03
admin@dns03:~$ sudo pdnsutil zone set-kind medisphere.internal secondary
admin@dns03:~$ sudo pdns_control retrieve medisphere.internal
admin@dns03:~$ sudo rec_control wipe-cache 'medisphere.internal$'
admin@adm02:~$ dig +short @10.20.20.11 medisphere.internal SOA ; dig +short @10.10.20.10 medisphere.internal SOA
```
(idem pour `par1.medisphere.internal` et `par2.medisphere.internal`, passées en `native` en S09 ; `par1` est signée DNSSEC à PAR1 : dns03 retrouve les signatures de dns01 par le transfert.) Fin de coupure quand la sonde voit `par1` sur les trois noms : `outils/pra/mesures-pra.sh coupure mediagenda.medisphere.internal <LEVEE_EPOCH>`.

*4. Veille (phase D)* : jeton retiré de la spécification, `mediagenda-db-par2` qui suit la nouvelle archive de PAR1 (`mediagenda-db-prod-pra1`), fichiers de site de PAR2 en veille, miroirs alignés puis *push mirrors* réactivés, minuterie `rclone` relancée, `bao-par2` arrêté et 3501 détruite, sauvegarde complète de PAR1 sur PBS (aucune n'était passée pendant l'isolement), première sauvegarde de base sous le nouveau `serverName`, INC-6109 clos ; `lab/bin/check F5 12`.

**Explications**

- **Rien de ce qui a été écrit à PAR2 n'est perdu par la reconstruction** : la nouvelle `mediagenda-db` naît de l'archive de PAR2 (`bootstrap.recovery` depuis `cnpg-k8s-par2`, sauvegarde de base postérieure à T0 faite en S11, puis tous les WAL de la ligne temporelle de PAR2), et la bascule par jetons garantit qu'elle a rejoué jusqu'au dernier LSN de PAR2 avant d'être promue. Sans sauvegarde de base de PAR2 postérieure à la promotion, la récupération partirait d'une sauvegarde de la ligne temporelle de PAR1 (copie de veille) et devrait traverser le changement de ligne : faisable (cible `latest`), plus long et moins sûr — d'où la sauvegarde de base exigée en S11.
- **Pourquoi reconstruire PAR1** : après une promotion sans jeton, les deux bases ont des histoires différentes depuis le dernier WAL commun ; PostgreSQL ne fusionne pas deux lignées. CloudNativePG ne sait réintégrer un ancien primaire de topologie distribuée qu'en le reconstruisant (la documentation le dit pour la promotion sans jeton). Les écritures de PAR1 postérieures à la divergence ne sont pas perdues pour autant : elles sont **exportées** (A4) et jugées par le métier.
- **Pourquoi un nouveau `serverName`** : `mediagenda-db-prod-day0` contient l'histoire de l'ancien primaire divergent, jusqu'à la clôture ; y écrire une autre ligne mélangerait deux bases (le plugin refuse « Expected empty archive », F1-S11). PAR2, au retour en veille, doit lire la **nouvelle** archive : d'où le changement de `serverName` de sa source dans le même commit que sa rétrogradation.
- **Pourquoi des jetons au retour et pas au départ** : au départ, PAR1 était inaccessible : impossible de le rétrograder. Au retour, les deux sites sont joignables : la bascule contrôlée (rétrogradation, jeton, promotion à LSN garanti) est la seule qui ne perde **aucune** transaction écrite à PAR2.
- **La série DNS** : un secondaire PowerDNS compare les séries ; dns03 ayant incrémenté la sienne pendant le PRA, il refuserait silencieusement les données plus anciennes de dns01 et continuerait d'envoyer les patients à PAR2.
- **Le vrai RPO** n'existe que parce que la simulation a gardé PAR1 intact. Dans un vrai sinistre, la borne mesurée en S09 serait le seul chiffre : d'où l'intérêt de la mesurer bien (filtre `cree_le < T0`).

**Alternatives**
- *Réplication logique* (publication à PAR2, abonnement à PAR1) pour éviter la reconstruction : possible, mais séquences, schéma et objets à part ; hors du chemin outillé par CloudNativePG.
- *Rester à PAR2 plus longtemps* et reconstruire PAR1 tranquillement : légitime en vrai (PAR1 détruit) ; le RB-351 couvre les deux, la coupure n'a lieu que quand PAR1 est prêt.
- *DNS* : supprimer la zone de dns03 et la recréer en secondaire (transfert complet) au lieu de jouer sur les séries : plus brutal, mêmes effets ; évite d'incrémenter dns01 plusieurs fois.
- *MédiDoc* : `rclone sync` dans le sens PAR2 → RGW **pendant la coupure** seulement, quand les écritures sont gelées des deux côtés — plus exhaustif (suppressions comprises), plus risqué ; la copie + liste est plus sûre.

**Pièges classiques**
- Lever l'isolement en premier « pour avoir accès à tout » : la minuterie `rclone` efface les documents du PRA à `s3-02`, les miroirs sont réécrits, `filer.sync` déverse les archives de l'ancien PAR1.
- Promouvoir PAR1 sans jeton (oubli du champ, ou jeton d'une tentative précédente) : second basculement, PAR2 à reconstruire, transactions du gel perdues.
- Mettre le jeton dans un commit et `primary` dans un autre : la documentation exige les deux ensemble.
- Supprimer le `Cluster` clôturé de PAR1 sans instantané ni export : la seule source du vrai RPO disparaît.
- Recopier les identifiants des rendez-vous de la divergence dans la base par SQL : les identifiants se recouvrent (chaque site a continué sa séquence).
- Oublier la nouvelle autorité de la base pour OpenBao (F1-S11) : l'API de PAR1 redémarre sans identifiants au premier renouvellement.
- Réactiver les *push mirrors* avant d'avoir versé les commits du PRA dans GitLab.
- Oublier `par2.medisphere.internal` sur dns03 (restée native) : ses enregistrements divergent ensuite de ceux de dns01.

**En production chez MédiSphère**
Le retour d'un vrai sinistre prend des semaines (reconstruction de la salle, de `pve01`, du socle par F1) ; RB-351 commence alors à la phase B, PAR1 reconstruit étant d'emblée une réplique. La neutralisation (phase A) est indispensable dans les sinistres **partiels** — coupure réseau, salle inaccessible mais serveurs vivants — qui sont statistiquement les plus fréquents.

---

### F5-S13 — Le rapport d'exercice PRA

**Solution**

Rapport de référence : [`rapport.md`](fichiers/F5-S13/medisphere/docs/pra/exercices/2026-exercice-1/rapport.md) ; mesures exportées (extrait) : [`sonde-mesures.extrait.csv`](fichiers/F5-S13/medisphere/docs/pra/mesures/2026-exercice-1/sonde-mesures.extrait.csv) (le vrai fichier, `sonde-mesures.csv`, est la copie complète de `/var/lib/ms-sonde-pra/mesures.csv` sur la période de l'exercice).

```
admin@adm02:~$ awk -F, 'NR == 1 || ($1 >= "2026-12-15T08:30" && $1 <= "2026-12-16T11:00")' \
    /var/lib/ms-sonde-pra/mesures.csv > ~/medisphere/docs/pra/mesures/2026-exercice-1/sonde-mesures.csv
```

Points attendus, quelle que soit la forme :
- une **synthèse** en tête qui répond à la question de Claire (« à quelle heure, combien perdu ») en deux phrases, puis la faiblesse principale et ce qu'elle coûterait ;
- un tableau objectifs contre mesures, avec la **définition** de chaque mesure (RTO de sonde ou de création, RPO borné ou exact) ;
- la décomposition du RTO (décision, technique, service complet) : c'est elle qui dit où investir ;
- les écarts comme des mécanismes (runbook muet, configuration de site, dépendance invisible) et chaque action rattachée à un écart, avec un nom et une date ;
- les révisions de documents que le rapport rend obligatoires (`objectifs.md` : supervision de PAR2 dans le périmètre ; RB-350 : moteur de la base ; RB-351 : droits de l'identité de lecture).

**Explications**

Un rapport d'exercice sert trois lecteurs : la direction (tient-on nos engagements ?), l'auditeur HDS/ISO 27001 (mesure 5.30 « préparation des TIC à la continuité » : le plan est-il **testé** et amélioré ?) et l'équipe (que corrige-t-on ?). L'en-tête de mesures rend le rapport vérifiable par une machine — c'est ce que fait le check, en recalculant les RTO depuis les mesures brutes : un chiffre recopié à la main qui ne correspond pas aux mesures est le premier défaut qu'un auditeur cherche.

**Alternatives**
- Rapport en deux documents (synthèse de direction d'une page, annexe technique) : plus lisible pour la direction, mêmes chiffres.
- Mesurer le RTO au critère strict d'`objectifs.md` seulement (création confirmée) : plus juste pour le patient, moins automatisable ; le rapport de référence donne les deux.

**Pièges classiques**
- Annoncer le RPO borné de S09 alors que S12 a donné la valeur exacte (ou l'inverse sans le dire).
- Mesurer le RTO depuis la décision : on efface le temps d'organisation, que subissent pourtant les patients.
- « Erreur humaine » comme cause : ce n'est pas un mécanisme, et cela n'entraîne aucune action utile.
- Des actions sans responsable ni date, ou qui n'auraient pas empêché l'écart qu'elles prétendent traiter.

**En production chez MédiSphère**
Le rapport est présenté en comité de direction et versé au dossier de certification ; ses actions sont suivies jusqu'à la clôture, et le prochain exercice commence par la vérification qu'elles sont faites.

---

### F5-S14 — Recette `pra-v1` : une reprise qui se teste

**Solution**

*1. Alertes de préparation.* Requête personnalisée de CloudNativePG sur la réplique de PAR2 ([`temoin-metriques.yaml`](fichiers/F5-S14/k8s/sites/par2/supervision/temoin-metriques.yaml), branchée par `spec.monitoring.customQueriesConfigMap` dans le fichier de site du `Cluster` de PAR2) : `cnpg_pra_temoin_age_secondes` (RPO courant de bout en bout) et `cnpg_pra_temoin_derniere_heure`. Règles ([`regles-pra.yml`](fichiers/F5-S14/adm02/prometheus/regles-pra.yml), qui remplace celle de S11) : âge du témoin > 15 min, métrique absente, retard de réplication > 10 min, moins de 50 témoins par heure, contrôle de préparation en échec ou périmé. Essai de chacune : suspendre `temoin-rpo` à PAR1 20 min (l'âge monte, l'alerte part, puis se résout) ; arrêter `filer.sync` (retard) ; décordonner/cordonner, etc. Hors PRA, Alertmanager de `adm02` relaie vers `smtp.par1.medisphere.internal` ; le contrôle de préparation tourne chaque nuit par une minuterie de `adm02` qui écrit `pra-preparation.prom` dans le répertoire du textfile collector.
```
admin@adm02:~$ promtool check rules /etc/prometheus/regles-pra.yml
admin@adm02:~$ curl -s 'http://127.0.0.1:9090/api/v1/query?query=cnpg_pra_temoin_age_secondes' | jq '.data.result[0].value'
```

*2. Test trimestriel.* [`essai-reprise.sh`](fichiers/F5-S14/k8s/outils/pra/essai-reprise.sh) (restauration dans l'espace jetable `pra-essai` de `k8s-par2` depuis la copie de l'archive de PAR1 sur `s3-02`, mesures, invariants, nettoyage, verdict), espace, quota et compte limités ([`pra-essai.yaml`](fichiers/F5-S14/k8s/sites/par2/pra-essai.yaml)), job [`pra-essai.gitlab-ci.extrait.yml`](fichiers/F5-S14/k8s/ci/pra-essai.gitlab-ci.extrait.yml) sur le runner protégé. Planification (interface de `plateforme/k8s`, *Build › Pipeline schedules*, ou API) : description « PRA — essai de reprise trimestriel », cron `17 6 2 1,4,7,10 *`, fuseau `Europe/Paris`, branche `main`, variable `PRA_ESSAI=1`. Premier passage lancé à la main (« Run pipeline » sur la planification) ; un échec provoqué une fois (seuil de RPO abaissé à 60 s) pour vérifier qui est prévenu.

*3. Calendrier* : [`calendrier-tests.md`](fichiers/F5-S14/medisphere/docs/pra/calendrier-tests.md) — continu, quotidien, mensuel, trimestriel, semestriel, annuel ; prochain exercice complet le 2027-05-18 ; historique.

*4. Documentation* : index [`README.md`](fichiers/F5-S14/medisphere/docs/pra/README.md) de `docs/pra/`, documents révisés après le rapport (S13), relecture de RB-350 et RB-351 par quelqu'un qui n'a pas fait l'exercice (Lucas Martin : ses questions deviennent des précisions).

*5. Recette* : `WB_F5_SERVEUR_PROD=mediagenda-db-prod-pra1` dans `lab/lab.env` (la base de PAR1 archive sous ce nom depuis le retour), PAR2 en veille (`check F5 6` et `check F5 8` verts), `lab/bin/check F5 1` à `14` verts (ceux de S09 à S11 restent ceux du jour de l'exercice : ils décrivent un état de crise), puis :
```
admin@adm01:~/src/medisphere$ git tag -s pra-v1 -m "PRA v1 : site de repli PAR2 testé (exercice 2026-1, essai trimestriel)" && git push origin pra-v1
```
(ou l'étiquette par l'interface, selon ta convention des autres finaux).

**Explications**

L'exercice annuel prouve qu'on **a su** reprendre un jour ; il ne dit rien du lendemain. Trois niveaux complémentaires rendent la capacité de reprise observable : la **mesure continue** (le témoin à PAR2 dit, à la minute, quel serait le RPO d'un sinistre maintenant), l'**essai automatique** (la restauration réelle d'une base, seule preuve que l'archive est exploitable : une archive qui grossit peut être inutilisable), l'**exercice** (organisation, humains, ordre, décisions). Le témoin est la pièce maîtresse : une écriture applicative réelle, mesurée à l'arrivée — il couvre d'un coup l'archivage de PAR1, la copie `filer.sync`, la réplique et ses défaillances silencieuses (S08).

**Alternatives**
- Test trimestriel en **CronJob** dans `k8s-par2` plutôt qu'en pipeline : indépendant de PAR1 (il tournerait même PAR1 perdu), mais sans le suivi d'échec de GitLab ; dans ce cas, l'alerte se fait sur `kube_cronjob_status_last_successful_time` (il faut kube-state-metrics à PAR2).
- Test plus complet : démarrer aussi l'API de MédiAgenda (image de `reg02`) contre la base restaurée et créer un rendez-vous : plus probant, plus lourd pour le nœud de 5 Go.
- Chaos de PAR2 (arrêts provoqués de `s3-02` ou de `filer.sync`) pour vérifier les alertes : à faire dans les répétitions, pas en automatique.

**Pièges classiques**
- Un test qui restaure dans `mediagenda-prod` de PAR2 ou qui réutilise le nom `mediagenda-db-par2` : il écrase la base de veille.
- Un `Cluster` d'essai qui **archive** dans `cnpg-k8s-par2` ou sous un `serverName` existant.
- Oublier le nettoyage en cas d'échec (`trap`) : le nœud se remplit d'essais ratés.
- Des seuils si larges que le test ne peut pas échouer (§11.12 de nos conventions, appliqué à la plateforme).
- Alerter sur `cnpg_pg_replication_lag` seul : sans écriture à PAR1, le retard « de rejeu » grandit et l'alerte devient bruyante ; le témoin donne un signal régulier.
- Poser `pra-v1` avant que le premier essai trimestriel ait réussi.

**En production chez MédiSphère**
Le tableau de bord d'astreinte affiche le RPO courant de PAR2, la date du dernier essai réussi et la prochaine échéance ; l'essai trimestriel est une preuve d'audit (artefact gardé 400 jours) ; chaque version majeure de la plateforme (Kubernetes, CNPG, PostgreSQL) déclenche un essai hors calendrier.

---

## Points non testés en conditions réelles

- **Annulation du sinistre depuis `pve01`** : `lab/bin/break F5 9 --annuler` lit l'état du `Cluster` par `ssh adm01` et le compte des checks de `adm01` ; il retire le marqueur de `adm01` à distance. Le chemin SSH `pve01` → `gw02` (alias à créer dans `/root/.ssh/config` de `pve01` s'il n'existe pas) est vérifié par le contrôle préalable de S09.
- Comportement des *push mirrors* de GitLab au rétablissement du lien sur des branches modifiées dans le miroir (option « garder les références divergentes ») : le runbook les désactive avant la levée pour ne pas dépendre de ce comportement.
- `kubectl cnpg fencing on … "*"` sur toutes les instances, puis suppression du `Cluster` : conservation des `VolumeSnapshot` de ceph-csi après suppression des PVC sources.
- Reconstruction de `mediagenda-db` en réplique par `bootstrap.recovery` depuis l'archive de PAR2 **à travers `wg0`** (débit, délai) ; archivage par la réplique désignée sous `mediagenda-db-prod-pra1`.
- Contenu exact et durée d'apparition de `.status.demotionToken` ; nettoyage du `promotionToken` après promotion (sans effet attendu, à confirmer).
- `pdns_control retrieve` après passage de `native` à `secondary` sur dns03 (transfert immédiat ou au prochain contrôle de série) ; `pdnsutil zone set-kind` conserve les primaires de la zone (colonne `master`), à vérifier par `pdnsutil zone show` (anciennement `show-zone`).
- Garde de la panne S09 : retrait par l'annulation (`systemctl disable --now`, suppression des unités et du complément, `daemon-reload`) avant la suppression de la table ; le check de S12 vérifie l'absence de la table **et** du garde.
- Requêtes personnalisées de CloudNativePG sur une **réplique** de topologie distribuée (désignée primaire) et nom exact des métriques (`cnpg_pra_temoin_age_secondes`) ; `cnpg_pg_replication_in_recovery` et `cnpg_pg_replication_lag` des requêtes par défaut.
- `essai-reprise.sh` : restauration avec la classe de stockage locale `local-path` de `k8s-par2` (S06), droits du compte `pra-essai`, sortie de `kubectl wait --for=condition=Ready` sur un `Cluster` CNPG, flux du runner protégé vers `k8s-par2`.
- Champ `last_pipeline` de l'API `pipeline_schedules` lisible avec le jeton des checks (sinon le check l'ignore).
- Transfert de la base de Legacy-RDV de PAR2 vers PAR1 (objets `Backup`/`Restore` de mariadb-operator 26.6 entre deux sites) : décrit, non outillé dans le corrigé.
