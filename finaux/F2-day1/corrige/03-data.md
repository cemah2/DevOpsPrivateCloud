# Phase 3 — L'équipe Data — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les solutions ci-dessous sont **des** solutions de référence : d'autres conceptions sont valables si elles tiennent les contraintes (aucun chemin de Data vers les données identifiantes, garanties imposées par le code, identifiants courts, rien à la main sur la production). Les fichiers complets sont dans [`fichiers/S07/`](fichiers/S07/), [`fichiers/S08/`](fichiers/S08/) et [`fichiers/S09/`](fichiers/S09/), rangés par dépôt (`mediagenda-api/` = `mediagenda/api`, `mediagenda-deploiement/` = `mediagenda/deploiement`, `data-statistiques-deploiement/` = `data/statistiques-deploiement`, `data-gitops/` = `data/gitops`, `k8s/` = `plateforme/k8s`, `equipes/` = `plateforme/equipes`, `secrets/`, `politiques/`, `observabilite/`, `ceph/`, `outils/`, `ansible/`, `medisphere/` = `plateforme/medisphere`).

**Validé hors du lab** : YAML et JSON relus (`yaml.safe_load_all`, `jq`) ; scripts embarqués des CronJobs passés à `bash -n` ; `ms-showback` exécuté contre un faux Prometheus (réponses figées) avec un `yq` de substitution : calculs, tri, mois partiel et refus d'un mois non terminé conformes ; `rgw-compartiment.sh` et `ms-showback` propres à `shellcheck`.

**Points non testés en conditions réelles** (signale tes retours) :
- noms exacts des métriques des requêtes personnalisées de CloudNativePG 1.30 (`cnpg_<requête>_<colonne>` d'après la documentation) ; le collecteur exécute les requêtes sous le rôle `cnpg_metrics_exporter`, membre de `pg_monitor` (documentation 1.30, « Custom query privileges ») : d'où `GRANT USAGE ON SCHEMA stats` et `GRANT SELECT ON stats.chargements` à `pg_monitor`, reçus par héritage (vérifie avec `\du cnpg_metrics_exporter` ; à défaut, donne ces droits au rôle lui-même) ;
- étiquette `cnpg.io/instanceRole=primary` des pods (sélecteur du Service d'OpenBao) : vérifie avec `kubectl get pods --show-labels` ; à défaut, `role=primary` (ancienne étiquette) ;
- conflits du rejeu sur `mediagenda-db-secours` pendant la lecture (valeur réelle de `max_standby_archive_delay` sur ce réplica, fréquence des annulations) ;
- règles de cycle de vie sur un compartiment de SeaweedFS (purge à 7 jours du sas) : selon ta version, une purge planifiée peut être nécessaire ;
- `psql` 18 : `\copy` dans un script lu par `-f -` avec `-1` (le chargement), variables `:'jour'` dans le SQL seulement (psql ne les interpole **pas** dans les arguments de `\copy` : l'export mensuel passe donc par `COPY … TO STDOUT` redirigé par le shell) ; image `amazon/aws-cli` lancée sous l'UID 65534 avec `HOME` sur un `emptyDir` ;
- règles d'enregistrement (aucun `promtool` dans l'environnement de rédaction) : rejoue-les avec `promtool check rules` et, mieux, un test unitaire (`regles/tests/`).

---

### F2-S07 — Des bases en libre-service pour l'équipe Data

**Solution de référence**

*0. La décision* — [`ADR-0327`](fichiers/S07/medisphere/docs/accueil/adr/ADR-0327-extraction-pseudonymisee.md). Option retenue : **MédiAgenda pousse**, l'équipe Data reçoit. Un CronJob de `mediagenda-secours` (espace de la plateforme, données de santé) lit une **vue pseudonymisée** sur le réplica de secours avec un rôle qui n'a que ce droit, et **dépose** un fichier dans un sas S3 (`s3://data-extractions` sur `s3-01`) ; l'équipe Data le charge avec une identité qui ne sait que lire le sas. Aucun flux, aucun rôle, aucun secret ne relie `data-traitements` à une base de MédiAgenda ; la cloison réseau entre locataires (M28-E15) reste intacte. Le tableau des options de l'ADR explique pourquoi « Data lit le réplica » (option B) a été écarté.

```
mediagenda-prod                 mediagenda-secours                    s3-01                 data-traitements
mediagenda-db (primaire)  WAL   mediagenda-db-secours (lecture)       data-extractions      statistiques-db
  V5 : extraction.*  ───────►   CronJob extraction-data  ── dépôt ──► rendez-vous/J.csv.gz ◄── CronJob chargement-extraction
  rôle extraction_data          (rôle extraction_data,                 + J.json (empreinte)      (lecture seule du sas,
  (managed.roles)                identité S3 « écriture seule »)                                 compte dynamique OpenBao)
```

*1. Stockage objet* — dans `plateforme/ansible`, [`host_vars/s3-01/seaweedfs.yml`](fichiers/S07/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) : compartiments `cnpg-data` (sauvegardes de la base Data, **jamais** `cnpg-k8s-par1`) et `data-extractions` (sas) ; identités `cnpg-data` (lecture, écriture, liste sur `cnpg-data`), `extraction-ecriture` (**écriture seule** sur le sas), `extraction-lecture` (lecture et liste). MR, puis le pipeline protégé qui rejoue le rôle de `s3-01` (M05, M16). Les clés vont dans OpenBao :

```
admin@adm01:~$ bao login -method=oidc
admin@adm01:~$ d=$(mktemp -d) && chmod 700 "$d"      # clés extraites du Vault « critique » dans $d (fichiers 600, sans retour à la ligne final)
admin@adm01:~$ bao kv put kv/mediagenda/secours/sas-extraction AWS_ACCESS_KEY_ID=@"$d/ecriture.id" AWS_SECRET_ACCESS_KEY=@"$d/ecriture.secret"
admin@adm01:~$ bao kv put kv/data/traitements/sas-extraction AWS_ACCESS_KEY_ID=@"$d/lecture.id" AWS_SECRET_ACCESS_KEY=@"$d/lecture.secret"
admin@adm01:~$ bao kv put kv/data/traitements/cnpg-s3 ACCESS_KEY_ID=@"$d/cnpg.id" ACCESS_SECRET_KEY=@"$d/cnpg.secret"
admin@adm01:~$ rm -rf "$d"
admin@adm01:~$ bao kv put kv/data/traitements/medisphere-ca ca.crt=@/usr/local/share/ca-certificates/medisphere-root-ca.crt
admin@adm01:~$ openssl rand -base64 33 | tr -d '\n' | bao kv put kv/mediagenda/prod/extraction-data password=-
```

> ⚠️ **Attention** : une clé d'accès écrite en clair sur la ligne de commande reste dans l'historique du shell et dans `ps`. Fais-la lire depuis un fichier 600 (`clé=@fichier`) ou l'entrée standard (`clé=-`, une seule par commande), puis efface les fichiers.

*2. La politique d'admission* — [`cnpg-sauvegarde-obligatoire.yaml`](fichiers/S07/politiques/kyverno/validation/cnpg-sauvegarde-obligatoire.yaml) dans `plateforme/politiques` : d'abord en `Audit`, puis inventaire des Cluster existants :

```
admin@adm01:~$ kubectl get clusters.postgresql.cnpg.io -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name,
    ([.spec.plugins[]? | select(.isWALArchiver)] | length), (.spec.replica.enabled // false)] | @tsv'
admin@adm01:~$ kubectl get policyreports -A | grep cnpg-sauvegarde
```

Les bases de recette et de production archivent déjà (M16, M27-E15), le réplica de secours est exclu par la condition `replica.enabled`, les bases de `*-dev` par le sélecteur d'espace. Puis `Deny`, et l'essai écrit dans l'ADR :

```
admin@adm01:~$ kubectl apply --dry-run=server -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: essai-sans-archive, namespace: data-traitements}
spec: {instances: 1, storage: {size: 1Gi}}
EOF
Error from server: admission webhook "…kyverno…" denied the request: … Une base de locataire archive ses WAL par le plugin Barman Cloud …
```

*3. L'exposition de la base à OpenBao, par l'équipe en code* — le quota rendu par S02 interdit tout `LoadBalancer` dans les espaces d'équipe. Plutôt que de modifier un fichier rendu (il serait écrasé), le **format** gagne un réglage d'environnement : [`schema`](fichiers/S07/equipes/schema/equipe.schema.extrait-F2-S07.json), [`gabarit`](fichiers/S07/equipes/gabarits/k8s/espace.extrait-F2-S07.yaml.j2), [`equipes/data.yaml`](fichiers/S07/equipes/equipes/data.extrait-F2-S07.yaml) (`base_openbao: true` → `services.loadbalancers: "1"`). Le Service, sa politique réseau, les générateurs d'ESO et la redirection de port des analystes restent à la plateforme : [`espaces/data-traitements/60-openbao.yaml`](fichiers/S07/k8s/espaces/data-traitements/60-openbao.yaml) dans `plateforme/k8s`, appliqué comme les autres fichiers de `espaces/` (exception écrite du M27). Côté coffre, ce que le rendu ne sait pas exprimer est déclaré à côté de lui : [`equipes.extrait-F2-S07.tf`](fichiers/S07/secrets/tofu/equipes.extrait-F2-S07.tf) (chemin d'identifiants dynamiques pour `eso-data-traitements`, politique [`data-analystes`](fichiers/S07/secrets/politiques/data-analystes.hcl) ajoutée au groupe `data`) et [`eso-espaces.tf`](fichiers/S07/secrets/tofu/eso-espaces.tf.extrait) pour l'espace de secours.

*4. La base de l'équipe* (avec Hugo, dans `data/statistiques-deploiement`) — [`base/`](fichiers/S07/data-statistiques-deploiement/base/) : [`statistiques-db.yaml`](fichiers/S07/data-statistiques-deploiement/base/statistiques-db.yaml) (une instance, `ceph-rbd`, requests et limites, superutilisateur désactivé, plugin Barman Cloud vers `cnpg-data`, requêtes personnalisées, rôle géré `openbao`), [`initialisation.yaml`](fichiers/S07/data-statistiques-deploiement/base/initialisation.yaml) (joué une fois par `postInitApplicationSQLRefs` : groupes `stats_lecture` et `stats_ecriture`, rôle `openbao` avec l'option `ADMIN`, schéma `stats`, tables `rendez_vous` et `chargements`), [`sauvegarde.yaml`](fichiers/S07/data-statistiques-deploiement/base/sauvegarde.yaml) (`ObjectStore` avec rétention de 14 jours, `ScheduledBackup` à 01:20), [`supervision.yaml`](fichiers/S07/data-statistiques-deploiement/base/supervision.yaml) (requêtes personnalisées du contrat, `PodMonitor`), [`reseau.yaml`](fichiers/S07/data-statistiques-deploiement/base/reseau.yaml) (refus par défaut ; aucune règle ne nomme MédiAgenda), [`externalsecrets.yaml`](fichiers/S07/data-statistiques-deploiement/base/externalsecrets.yaml), et l'[overlay `traitements`](fichiers/S07/data-statistiques-deploiement/overlays/traitements/kustomization.yaml). Le dépôt suit la convention du chemin balisé de S02 et S04 (`<groupe>/<service>-deploiement`, `overlays/<environnement>`) : Hugo déclare le service dans `data/gitops` ([`services/statistiques.yaml`](fichiers/S07/data-gitops/services/statistiques.yaml)) et l'ApplicationSet `data` crée l'Application `data-statistiques-traitements`, synchronisée automatiquement dans le cadre de l'AppProject `data`. Après synchronisation :

```
admin@adm01:~$ kubectl cnpg status statistiques-db -n data-traitements
admin@adm01:~$ kubectl -n data-traitements get backups.postgresql.cnpg.io
```

*5. Le moteur `db-data`* — même méthode qu'au M25-E14 : CA de la base copiée sur `vault01-03` ([extrait](fichiers/S07/ansible/inventories/lab/group_vars/role_coffre/openbao-postgresql.yml.extrait)), `tofu apply -target=vault_mount.db_data` dans `plateforme/secrets`, connexion créée une fois avec le mot de passe initial produit dans le cluster, puis `rotate-root` (plus personne ne connaît le mot de passe), import et `apply` complet de [`db-data.tf`](fichiers/S07/secrets/tofu/db-data.tf) :

```
admin@adm01:~$ kubectl -n data-traitements get secret openbao-pg-initial -o jsonpath='{.data.password}' | base64 -d \
  | bao write db-data/config/statistiques plugin_name=postgresql-database-plugin \
      allowed_roles=data-analyste,data-traitement username=openbao password=- \
      connection_url='postgresql://{{username}}:{{password}}@10.10.41.66:5432/statistiques?sslmode=verify-ca&sslrootcert=/etc/openbao/postgresql/statistiques-data-ca.crt&connect_timeout=5'
admin@adm01:~$ bao write -f db-data/rotate-root/statistiques
admin@adm01:~/src/secrets/tofu$ tofu import vault_database_secret_backend_connection.statistiques db-data/config/statistiques
admin@adm01:~/src/secrets/tofu$ tofu apply
admin@adm01:~$ bao read db-data/creds/data-analyste         # en tant que Hugo (OIDC) : compte de 8 h
```

Puis une MR retire le `passwordSecret` du rôle géré et le générateur `openbao-pg-initial`. Flux ajouté à la matrice : `vault01-03` → 10.10.41.66:5432 (même règle que pour 10.10.41.64-65).

*6. La vue, côté MédiAgenda* — MR de Julien sur `mediagenda/api` : [`V5__extraction_data.sql`](fichiers/S07/mediagenda-api/migrations/V5__extraction_data.sql) (migration *expand* : `pgcrypto`, schéma `extraction`, clé de 32 octets tirée **par la base**, vue `rendez_vous_pseudo`, droits conditionnels). MR sur `mediagenda/deploiement` : rôle géré `extraction_data` dans le correctif de prod ([extrait](fichiers/S07/mediagenda-deploiement/overlays/prod/base-openbao.extrait-F2-S07.yaml) — la liste `managed.roles` est remplacée en entier par Kustomize) et son mot de passe ([`extraction-data.yaml`](fichiers/S07/mediagenda-deploiement/overlays/prod/extraction-data.yaml)). **Ordre** : le rôle d'abord (sinon V5 saute ses `GRANT`), la migration ensuite, par le chemin normal (dev → recette → prod, fenêtre de synchronisation). Contrôles sans geste sur la prod :

```
admin@adm01:~$ kubectl -n mediagenda-prod get cluster mediagenda-db -o jsonpath='{.status.managedRolesStatus}' | jq
admin@adm01:~$ kubectl -n mediagenda-prod logs job/mediagenda-migrations | grep -E 'V5|extraction'
```

*7. L'extraction* — [`80-extraction-data.yaml`](fichiers/S07/k8s/espaces/mediagenda-secours/80-extraction-data.yaml) (`plateforme/k8s`, politique `eso-mediagenda-secours` étendue d'abord) et le chargement de l'équipe Data, [`chargement/cronjob.yaml`](fichiers/S07/data-statistiques-deploiement/chargement/cronjob.yaml). Premier passage à la main, puis on lit les métriques :

```
admin@adm01:~$ kubectl -n mediagenda-secours create job --from=cronjob/extraction-data extraction-essai-1
admin@adm01:~$ kubectl -n mediagenda-secours logs job/extraction-essai-1 -c lecture
{"jour":"2026-10-23","lignes":1342,"sha256":"…","source":"mediagenda-db-secours","vue":"extraction.rendez_vous_pseudo"}
admin@adm01:~$ kubectl -n data-traitements create job --from=cronjob/chargement-extraction chargement-essai-1
admin@adm01:~$ curl -s --data-urlencode 'query={__name__=~"cnpg_stats_extraction_.*", namespace="data-traitements"}' \
    http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query | jq -r '.data.result[] | [.metric.__name__, .metric.colonne // "", .value[1]] | @tsv'
```

*8. Alertes et procédure* — [`regles/alertes-data.yaml`](fichiers/S07/observabilite/regles/alertes-data.yaml) (`plateforme/observabilite`) : retard, lot vide, colonne identifiante apparue (critique, pour la plateforme), Job d'extraction en échec. [`RB-327`](fichiers/S07/medisphere/docs/accueil/runbooks/RB-327-extraction-nocturne.md).

*9. Preuve de l'absence de chemin* (à mettre dans l'ADR) : `kubectl get netpol,cnp -n data-traitements -o yaml | grep -c mediagenda` → 0 ; `hubble observe --from-namespace data-traitements --to-namespace mediagenda-secours` → rien ; `bao policy read data-equipe` et `data-analystes` sans `mediagenda` ; l'essai de connexion de Hugo à `mediagenda-db-secours-r` par redirection de port est refusé (aucun droit dans `mediagenda-secours`).

**Explications**

- **Pousser plutôt que tirer.** Le responsable d'une donnée de santé décide de ce qui sort et en porte la trace ; l'équipe qui reçoit n'a rien qui puisse, par erreur ou par malveillance, atteindre la source. Avec « Data lit le réplica », un `GRANT` de trop, un mot de passe copié ou une règle réseau élargie suffisent à exposer la table ; ici, il faudrait modifier la vue (migration relue par Julien et Sophie) ou le Job (dépôt de la plateforme).
- **Pourquoi le réplica marche.** Un réplica physique a le même catalogue que la production : la vue, la clé et le rôle créés sur le primaire (migration, `managed.roles`) arrivent par les WAL. On ne crée **rien** sur le réplica (il est en récupération : `cannot execute CREATE VIEW in a read-only transaction`).
- **Pourquoi un HMAC avec une clé interne.** Un simple `sha256(patient)` se renverse par dictionnaire (les noms sont peu nombreux) ; un HMAC avec 32 octets aléatoires que personne ne connaît ne se recalcule pas de l'extérieur, et donne des pseudonymes **stables** (patients distincts, suivi d'un praticien). Une vue classique s'exécute avec les droits de son propriétaire (`mediagenda`) : le lecteur n'a besoin ni de la table, ni de la clé. Les fonctions appelées, elles, le sont avec les droits du lecteur (`pgcrypto` dans `public`, exécutable par tous).
- **Pseudonymiser n'est pas anonymiser.** Le RGPD (considérant 26) traite les données pseudonymisées comme personnelles : la base Data a des accès nominatifs, une durée de conservation, une entrée au registre. Le tronquage des horodatages (jour et **demi-journée** : l'heure, avec l'index unique praticien + début de V2, désignerait un ou deux rendez-vous) et la règle des petits effectifs réduisent le risque de ré-identification par recoupement ; le *k*-anonymat se mesure (plus petit groupe praticien × jour × demi-journée) avant d'ajouter une colonne.
- **Identifiants.** Les comptes dynamiques d'OpenBao prennent leurs droits d'un groupe (`IN ROLE`) ; pour l'écriture, la session prend le rôle `stats_ecriture` (`ALTER ROLE … SET role`) : les tables créées par un traitement appartiennent au groupe, et `DROP ROLE` réussit à la fin du bail (piège du M25-E14).
- **Observer sans lire.** Les métriques du contrat lisent le catalogue (`pg_attribute`) et un journal de chargements, jamais une ligne de `stats.rendez_vous`. Le check et l'alerte « colonne identifiante » en dépendent : une régression de la vue se voit sans que personne ne regarde les données.
- **Imposer plutôt que demander.** L'admission refuse une base sans archivage dans un espace de locataire ; elle ne voit pas qu'une `ScheduledBackup` existe et réussit (objet distinct) : c'est le rôle du check et de l'alerte.

**Alternatives**
- *Data lit des vues sur le réplica* (option B de l'ADR) : moins de pièces ; à condition d'ouvrir une exception à la cloison de locataire (deux politiques Cilium découpées par `endpointSelector`, comme pour l'appel MédiAgenda → MédiDoc du M28-E15), une entrée réseau dans `mediagenda-secours` et un secret de base de santé dans l'espace Data.
- *Réplication logique* d'une publication vers la base Data : quasi temps réel, mais une publication ne transforme pas les colonnes (on publierait une **table** alimentée par déclencheur, et l'abonné serait la prod elle-même) : plus de couplage.
- *Identifiants statiques* (rôles gérés par CloudNativePG, mots de passe dans `kv/data/traitements/*`) : pas de `LoadBalancer` ni de moteur ; mais des mots de passe partagés dans l'équipe et sans expiration. Acceptable pour les traitements, pas pour les personnes.
- *PostgreSQL 18 et OAuth* (`oauth` dans `pg_hba.conf`, module de validation) : connexion des analystes avec leur jeton Keycloak, sans mot de passe de base ; il faut un module de validation dans l'image (absent des images de CloudNativePG) : piste à suivre.
- *Anonymisation par agrégats* faits côté MédiAgenda (seuls des comptages sortent) : le plus sûr, mais chaque nouvelle question de Hugo devient une migration de MédiAgenda.

**Pièges classiques**
- Créer la vue ou le rôle **sur le réplica** : refusé (lecture seule) ; ou, pire, les créer à la main sur la production.
- Lancer V5 **avant** que le rôle existe : migration verte, `GRANT` sautés (avis `RAISE NOTICE`), extraction en `permission denied`.
- Pseudonymiser par `md5(patient)` ou `sha256(patient)` sans clé ; ou mettre la clé dans la définition de la vue (lisible par `pg_get_viewdef` par tout utilisateur connecté).
- Vue `security_invoker = true` (PostgreSQL ≥ 15) : le lecteur devrait lire la table source, l'intérêt de la vue disparaît.
- Donner à l'équipe une identité en écriture sur `cnpg-k8s-par1` : elle peut effacer l'archive de la production.
- Un `LoadBalancer` ajouté à la main dans un espace rendu : refusé par le quota, ou effacé au rendu suivant.
- Dates en heure locale d'un côté, UTC de l'autre : le chargement de 03:30 cherche le fichier de la veille.
- Compter les lignes d'un CSV avec `wc -l` alors qu'un champ peut contenir un retour à la ligne : vrai ici seulement parce que l'extraction n'exporte aucun texte libre (c'est écrit dans le Job).

**En production chez MédiSphère**

Une **analyse d'impact** (AIPD) précède tout traitement de données de santé à grande échelle : le DPO la valide avant la mise en service, avec la fiche du registre (finalité, base légale, destinataires, durée). Le sas est chiffré côté serveur et ses accès journalisés vers le locataire `audit` de Loki ; la clé de pseudonymisation est sauvegardée avec la base (c'est une donnée de la base) et sa rotation est une décision conjointe. Les extractions vers des tiers (CNAM, chercheurs) suivent le même modèle, avec une vue par destinataire.

---

### F2-S08 — Traitements par lots et refacturation interne

**Solution de référence**

1. *Quota des lots* — [`espaces/data-traitements/20-quota-lots.yaml`](fichiers/S08/k8s/espaces/data-traitements/20-quota-lots.yaml) (`plateforme/k8s`) : `ResourceQuota` à portée `PriorityClass` `medisphere-lot` (1 CPU, 1 Gi, 6 pods). Il s'ajoute au quota de l'espace et au budget du locataire.
2. *Compartiment de résultats* — [`ceph/outils/rgw-compartiment.sh`](fichiers/S08/ceph/outils/rgw-compartiment.sh) et sa liste [`rgw-compartiments.yaml`](fichiers/S08/ceph/outils/rgw-compartiments.yaml) (`plateforme/ceph`), généralisation de `thanos-rgw.sh` du M21-E24 : utilisateur RGW à un seul compartiment, quota de 5 Gio, cycle de vie de 400 jours, clés envoyées **directement** dans `kv/data/traitements/s3-resultats` par un tube (jamais affichées) :
   ```
   admin@adm01:~/src/ceph$ bao login -method=oidc
   admin@adm01:~/src/ceph$ outils/rgw-compartiment.sh data-resultats data-resultats 5G data/traitements/s3-resultats
   utilisateur RGW data-resultats créé ; clés rangées dans kv/data/traitements/s3-resultats
   compartiment data-resultats créé
   contrôles : liste autorisée, second compartiment refusé
   ```
3. *Lots de l'équipe* — [`traitements/`](fichiers/S08/data-statistiques-deploiement/traitements/) de `data/statistiques-deploiement` (à ajouter aux `resources` de `base/`) : [`agregats.yaml`](fichiers/S08/data-statistiques-deploiement/traitements/agregats.yaml) (04:15, agrégats quotidiens et mensuels, tables créées au premier passage et possédées par `stats_ecriture`), [`export-mensuel.yaml`](fichiers/S08/data-statistiques-deploiement/traitements/export-mensuel.yaml) (le 2 du mois, seuil de 10 rendez-vous, dépôt dans `data-resultats`), [`externalsecret-resultats.yaml`](fichiers/S08/data-statistiques-deploiement/traitements/externalsecret-resultats.yaml). Tous en `medisphere-lot`, requests et limites déclarées.
4. *Mesure* — [`regles/enregistrement-locataires.yaml`](fichiers/S08/observabilite/regles/enregistrement-locataires.yaml) : correspondance espace → locataire, puis réservé, utilisé et facturé (CPU, mémoire), stockage demandé et utilisé, part du quota CPU. Tableau [`plateforme-consommation-locataires.json`](fichiers/S08/observabilite/tableaux/plateforme/plateforme-consommation-locataires.json) (dossier `plateforme`, provisionné par le *sidecar* de Grafana) : séries par locataire, efficacité *utilisé/réservé*, tableau du facturé moyen sur la période affichée.
   ```
   admin@adm01:~$ curl -s --data-urlencode 'query=locataire:cpu_facture:max' \
       http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query | jq -r '.data.result[] | [.metric.locataire, .value[1]] | @tsv'
   ```
5. *Rapport* — [`bin/ms-showback`](fichiers/S08/outils/bin/ms-showback) et [`showback/tarifs.yaml`](fichiers/S08/outils/showback/tarifs.yaml) (`plateforme/outils`) ; premier rapport en mois partiel :
   ```
   admin@adm01:~/src/outils$ bin/ms-showback --partiel --mois 2026-10 > ~/medisphere/docs/accueil/mesures/refacturation-2026-10.md
   ```
   Exemple de forme : [`refacturation-2026-10.md`](fichiers/S08/medisphere/docs/accueil/mesures/refacturation-2026-10.md) ; procédure : [`RB-328`](fichiers/S08/medisphere/docs/accueil/runbooks/RB-328-refacturation-interne.md). Un job planifié prépare le rapport chaque mois en artefact (S13, [extrait de CI](fichiers/S13/outils/.gitlab-ci.extrait-F2-S13.yml)) ; la MR reste humaine (commentaires, actions).

**Explications**
- `medisphere-lot` (priorité 100, `preemptionPolicy: Never`) : un lot n'expulse jamais personne et attend une place ; sous pression mémoire, le kubelet évince d'abord les pods qui dépassent leurs requests, et à égalité les moins prioritaires. Le quota à portée de classe borne ce que les lots peuvent **réserver**, sans toucher à la base de l'équipe (classe `medisphere-standard`).
- *Réservé* et *utilisé* racontent deux histoires : l'ordonnanceur place selon les requests (ce qu'on bloque pour les autres), la facture d'électricité suit l'usage. Facturer le maximum des deux est un compromis lisible ; le rapport *utilisé/réservé* montre où baisser les requests (VPA, M28).
- Les règles d'enregistrement fixent le calcul une fois (mêmes chiffres dans le tableau, le rapport et le check) et allègent Thanos sur 30 jours de données.

**Alternatives**
- **OpenCost** : coût par charge à partir d'un prix par nœud et par ressource ; utile quand les nœuds ont des prix différents (cloud public) ; ici, trois travailleurs identiques et un tarif interne suffisent.
- *Chargeback* (refacturation comptable) : exige une décision budgétaire et des règles de contestation ; à proposer en S14, pas à imposer.
- Quotas plus serrés pour forcer la sobriété : décourage l'accueil ; le *showback* rend la consommation visible sans bloquer.

**Pièges classiques**
- Additionner les requests de **tous** les pods (terminés compris) : les CronJobs gonflent le réservé.
- `kubelet_volume_stats_*` absents pour certains volumes : le stockage *utilisé* est partiel ; le *demandé* (PVC) est la base de calcul.
- Un rapport « du mois » calculé le 15 : moyenne sur des échantillons partiels, à dire.
- Un quota à portée de classe qui oublie `limits.memory` : un lot sans limite passe le quota et menace le nœud (le `max` de la LimitRange de l'espace limite le dégât).
- Clés RGW affichées à l'écran ou écrites dans un fichier du dépôt.

**En production chez MédiSphère**

Le tarif interne est construit avec le contrôle de gestion (amortissement, énergie, personnes) et revu chaque année ; le rapport mensuel est commenté en comité plateforme ; une équipe qui dépasse durablement son budget passe en revue de capacité (ajout d'un nœud contre baisse des requests).

---

### F2-S09 — Réponse à la demande d'accès à la production

**Réponse de référence** : [`DEV-3209-acces-production.md`](fichiers/S09/medisphere/docs/accueil/reponses/DEV-3209-acces-production.md).

**Ce qui la rend bonne**
- Elle commence par le **besoin** (« des données à jour dans une base à moi ») avant la demande (« un accès à la prod ») : le refus porte sur un moyen, pas sur l'objectif.
- Chaque motif est compréhensible par un analyste : HDS (accès justifiés et nominatifs), RGPD (finalité, minimisation, garanties de l'article 89), disponibilité de la production, principe de la plateforme (aucune équipe dans la base d'une autre).
- L'alternative est **disponible le jour même**, décrite concrètement (contenu, exclusions et pourquoi, accès, règles d'usage), avec une voie d'évolution (colonne dérivée par migration de MédiAgenda).
- Les conditions de l'exception sont vérifiables : double validation (RSSI, responsable de la donnée), réplica ou restauration plutôt que primaire, rôle à expiration automatique (`VALID UNTIL`, comme Lucas au M27-E02), journalisation des requêtes du rôle, clôture et revue.
- Le ton remercie la demande : une équipe qui pose la question plutôt que de contourner est le résultat recherché.

**Pièges classiques**
- Un « non » sec, ou un « oui, mais sur le réplica » (le réplica de secours **est** la production, avec quelques minutes de retard).
- Promettre une exception sans écrire qui la valide ni quand elle se termine.
- Citer le RGPD sans en tirer de conséquence concrète (ce qui sort, ce qui ne sort pas).

**En production chez MédiSphère**

La réponse devient un modèle (offre de service, S01) ; le DPO est en copie de toute demande d'accès à des données de santé ; les exceptions accordées sont listées dans la revue d'accès mensuelle avec leur date de fin.
