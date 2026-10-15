# Module 13 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- fournisseur OpenTofu `goharbor/harbor` 3.12 : attributs `ca_certificate` de `harbor_registry`, `filters { resource = "artifact" }`, `dest_namespace_replace`, `single_active_replication` de `harbor_replication` (lus dans la documentation 3.12.5, non appliqués sur un Harbor 2.15) ;
- réplication des **accessoires** au format *bundle* de Cosign 3 (référents OCI 1.1) par la réplication de Harbor 2.15 : attendue (Harbor 2.15.0 annonce la prise en charge du format bundle), à constater en E13 ;
- message exact du refus « non signée » de Harbor 2.15 (le code source consulté ne donne pas la phrase complète) ; les deux messages de vulnérabilité sont ceux du fichier `src/server/middleware/vulnerable/vulnerable.go` de la v2.15.3 ;
- noms de tables et colonnes de la base de Harbor utilisés par les scripts : `execution` (`vendor_type = 'GARBAGE_COLLECTION'`, `status = 'Running'`) et `replication_policy.enabled` ;
- `pg_restore --list` lu sur l'entrée standard (`docker exec -i … < vidage`) pour un vidage au format personnalisé ;
- `prepare migrate -i … -o … -t <version>` de l'image `goharbor/prepare` de la nouvelle version (options lues dans `make/photon/prepare/commands/migrate.py` de la v2.15.3) ;
- champs `systeminfo/volumes` (`storage[0].total`, `.free`) et `system/gc` (`job_status`, `creation_time`) de l'API 2.0 de Harbor 2.15 ; noms des métriques de l'exportateur (`harbor_up`, `harbor_health`, `harbor_project_quota_usage_byte`, `harbor_statistics_total_storage_consumption`…), déduits du code des collecteurs ;
- `cosign verify-attestation` : forme de la sortie (enveloppe DSSE, champ `payload` en base64) avec le format *bundle* de Cosign 3.

**Rappels** : les objets de Harbor sont décrits dans la configuration OpenTofu `registre` de `plateforme/infra` (M13-E03), le rôle `harbor` et le playbook `registre.yml` sont ceux de M13-E02. Nouveaux états : `m13-registre` (dossier `envs/m13`, clé `envs/m13-registre/terraform.tfstate` : VM `reg02`) et `registre-reg02` (dossier `registre-reg02/` : objets de `reg02`). Fichiers de solution : `corrige/fichiers/M13-E13/` à `M13-E18/`.

---

### M13-E13 — Répliquer vers un second registre

**Solution**

Fichiers : [`infra/envs/m13/`](fichiers/M13-E13/infra/envs/m13/) (VM `reg02`), [`host_vars/reg02/harbor.yml`](fichiers/M13-E13/ansible/inventories/lab/host_vars/reg02/harbor.yml) et [`certificats.yml`](fichiers/M13-E13/ansible/inventories/lab/host_vars/reg02/certificats.yml), [extrait de la matrice des flux](fichiers/M13-E13/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`infra/registre-reg02/`](fichiers/M13-E13/infra/registre-reg02/) (objets de `reg02`), [`infra/registre/replication.tf`](fichiers/M13-E13/infra/registre/replication.tf) (endpoint et politique sur `reg01`), [`docs/registre/replication.md`](fichiers/M13-E13/medisphere/docs/registre/replication.md).

*1. La VM.* `reg02.tf` reprend `socle/reg01.tf` (module `vm-debian`, disque de données avec numéro de série, `enregistrement-dns`) sur le VNet `vsandbox` avec `ipv4_imposee = "10.10.99.31"`. État séparé (`envs/m13-registre/terraform.tfstate`) : un `tofu destroy` de fin de module ne touche jamais `reg01`.

```
admin@adm01:~/src/infra/envs/m13$ tofu init && tofu plan -out plan && tofu apply plan     # par la MR et le pipeline
admin@adm01:~$ dig +short reg02.par1.medisphere.internal
10.10.99.31
```

*2. Les flux.* Trois règles **temporaires** (marquées comme telles, retirées en E25) : `reg01` → `reg02:443` (réplication en poussée), `ca01` → `reg02:80` (défi HTTP-01), `reg02` → `ca01:443` (commande et renouvellement ACME). Rien d'autre : la sortie Internet de `reg02` (installateur, base de Trivy) est couverte par la règle générale, `adm01` joint tout le lab, et la règle de M13-E02 (`[$V_K8S, $V_SANDBOX]` → `reg01:443`) existe déjà.

*3. Harbor sur `reg02`.* `reg02` entre dans le groupe `role_registre` par son étiquette NetBox `role-registre` : le playbook `registre.yml` s'applique tel quel.

```
admin@adm01:~/src/ansible$ ansible-playbook playbooks/registre.yml -l reg02
```

Ce que l'exercice révèle d'habitude (et qu'on écrit dans la MR) : le nom `harbor_nom` et le disque de données (`harbor_disque_donnees`, numéro de série) avaient une valeur de `reg01` en `group_vars` ; les secrets de Harbor étaient partagés par le groupe (à séparer par hôte : `vault_reg02_*`) ; le certificat `certificats.yml` n'existait qu'en `host_vars/reg01`. Le garde-fou du playbook (`inventory_hostname in ['reg01', 'reg02']`) était prévu.

*4. Côté `reg02`.* Configuration racine `registre-reg02`, avec les identifiants `admin` de `reg02` (variables du job propres à `reg02`) : projet `medisphere` privé et immuabilité `v*`, robot système `robot$replication` (sur `medisphere` : `repository:list`, `pull`, `push`, `artifact:read`, `tag:create`), robot `robot$wb-checks` en lecture. Les secrets sortent par les sorties sensibles (`tofu output -json robot_wb_checks`) et vont en Vault ; le fichier des checks :

```
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/harbor-reg02-checks.env
admin@adm01:~$ tofu -chdir=src/infra/registre-reg02 output -json robot_wb_checks \
    | jq -r '"HARBOR_USER='"'"'\(.nom)'"'"'\nHARBOR_PASSWORD='"'"'\(.secret)'"'"'"' > ~/.config/workbook/harbor-reg02-checks.env
```

(Les apostrophes autour du nom sont indispensables : le fichier est **chargé** par `harbor_api`, et le `$` de `robot$wb-checks` serait développé.)

*5. Côté `reg01`.* `replication.tf` : `harbor_registry.reg02` (type `harbor`, `insecure = false`, `ca_certificate` = racine MédiSphère) et `harbor_replication.medisphere_vers_reg02` (poussée, filtres `name = "medisphere/**"`, `tag = "v*"`, `resource = "artifact"`, cron `0 15 3 * * *`, `deletion = false`). Les deux ressources n'existent que si `TF_VAR_reg02_robot_secret` est fourni : retirer `reg02` en E25 revient à vider cette variable.

Le test de connexion de l'endpoint (interface, ou `POST /api/v2.0/registries/ping`) distingue les causes : `connection refused`/délai → la bordure ; `x509` → la CA de l'endpoint ; `401` → le robot. Puis exécution **manuelle** d'abord :

```
admin@adm01:~$ ID=$(curl -s -u "$U" https://registry.par1.medisphere.internal/api/v2.0/replication/policies?name=medisphere-vers-reg02 | jq '.[0].id')
admin@adm01:~$ curl -s -u "$U" -X POST -H 'Content-Type: application/json' -d "{\"policy_id\":$ID}" \
    https://registry.par1.medisphere.internal/api/v2.0/replication/executions
admin@adm01:~$ curl -s -u "$U" "https://registry.par1.medisphere.internal/api/v2.0/replication/executions?policy_id=$ID" | jq '.[0] | {status, total, succeed, failed}'
```

(`$U` : ton compte `<MOI>:…` lu depuis un fichier, jamais tapé.) Le détail des tâches liste chaque artefact **et** ses accessoires (type `signature.cosign`, attestations, SBOM de Harbor).

*6. Vérifier sur la copie.*

```
admin@adm01:~$ D1=$(skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/medisphere/mediagenda-api:vX.Y.Z)
admin@adm01:~$ D2=$(skopeo inspect --format '{{.Digest}}' docker://reg02.par1.medisphere.internal/medisphere/mediagenda-api:vX.Y.Z)
admin@adm01:~$ [ "$D1" = "$D2" ] && echo identiques
admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
    reg02.par1.medisphere.internal/medisphere/mediagenda-api@$D2
admin@adm01:~$ cosign tree reg02.par1.medisphere.internal/medisphere/mediagenda-api@$D2
```

(`skopeo` et `cosign` lisent ton fichier d'authentification Docker : `docker login reg02…` ou `cosign login` avec ton compte de `reg02`.) La signature se vérifie parce qu'elle porte sur le **digest**, identique des deux côtés ; le nom du registre n'entre pas dans ce qui est signé.

*7. Mesure et documentation* : voir `replication.md` (sens, filtres, ce qui n'est pas répliqué, RPO de 24 h avec le déclencheur planifié).

**Explications**

La réplication de Harbor est un travail du `jobservice` : pour chaque artefact sélectionné, il copie manifestes et blobs **par l'API Distribution** du registre de destination, avec l'identité de l'endpoint. Les filtres s'appliquent aux artefacts ; les accessoires (signatures, attestations) suivent leur sujet. En poussée, `reg01` n'a besoin d'aucun flux entrant ; en *pull*, c'est la destination qui lit la source (utile quand la source ne peut pas ouvrir de flux sortant, PAR2 aux finaux). `override` décide du sort d'un artefact qui existe déjà à destination avec un contenu différent ; `deletion` propage les suppressions — à proscrire pour une copie de secours (elle recopierait l'erreur). Les cron de Harbor ont six champs (bibliothèque `robfig/cron` avec secondes) : `0 15 3 * * *` = 03:15:00 chaque jour.

**Alternatives**
- Réplication sur événement (`event_based`) : RPO de quelques minutes, mais un pic de publications charge `reg01` au mauvais moment ; souvent combinée à une planification de rattrapage.
- `skopeo sync` / `oras cp -r` en tâche planifiée : indépendant de Harbor, mais à réécrire (filtres, accessoires, reprise) et sans traçabilité dans Harbor.
- Stockage objet partagé (S3 répliqué) sous deux Harbor : copie des blobs, pas de la base ; les deux instances ne peuvent pas écrire en même temps.

**Pièges classiques**
- Filtre `**` sans projet : les caches publics partent aussi (des dizaines de Go).
- `insecure = true` (défaut du fournisseur OpenTofu !) sur l'endpoint au lieu de la CA.
- Robot de destination sans `repository:push` sur le projet : la réplication échoue sur chaque tâche avec `denied`.
- Projet de destination inexistant : avec un robot, Harbor ne le crée pas.
- Oublier que la copie de secours doit avoir sa propre immuabilité : sinon une réplication avec `override` peut réécrire une version.

**En production chez MédiSphère**
Un Harbor à PAR2 (finaux) en cible permanente, déclencheur sur événement + planification, alerte de la sonde si la dernière exécution a plus de 26 h, test régulier d'un tirage **depuis** PAR2 (pas seulement de la réplication).

---

### M13-E14 — Politiques : signature obligatoire, vulnérabilités bloquantes

**Solution**

Fichiers : [extrait de `registre/projets.tf`](fichiers/M13-E14/infra/registre/projets.tf.extrait), gabarit [`ci-templates/templates/verification.yml`](fichiers/M13-E14/ci-templates/templates/verification.yml), [extrait du `.gitlab-ci.yml` de `mediagenda/api`](fichiers/M13-E14/mediagenda-api/.gitlab-ci.yml.extrait), [`docs/registre/politiques.md`](fichiers/M13-E14/medisphere/docs/registre/politiques.md).

*1. Inventaire.*

```
admin@adm01:~$ for r in $(curl -s -u "$U" 'https://registry.par1.medisphere.internal/api/v2.0/projects/medisphere/repositories?page_size=100' | jq -r '.[].name | sub("^medisphere/"; "")'); do
    curl -s -u "$U" "https://registry.par1.medisphere.internal/api/v2.0/projects/medisphere/repositories/$r/artifacts?with_tag=true&with_accessory=true&with_scan_overview=true&page_size=100" \
    | jq -r --arg r "$r" '.[] | [$r, ([.tags[]?.name] | join(",")), .digest[0:19],
        (if any(.accessories[]?; .type == "signature.cosign") then "signée" else "NON SIGNÉE" end),
        ((.scan_overview // {} | to_entries[0].value.severity) // "non analysée")] | @tsv'; done
```

Les artefacts non signés (étiquettes de suivi de `main`, essais du palier 2) sont signés s'ils servent encore, sinon supprimés (après simulation, règle n° 5 de l'introduction).

*2. Politiques.* Dans `harbor_project.projet` : `enable_content_trust_cosign`, `deployment_security = "critical"`, `vulnerability_scanning = true` (analyse à la poussée), pour `medisphere` seulement. Contrôle par l'API :

```
admin@adm01:~$ curl -s -u "$U" https://registry.par1.medisphere.internal/api/v2.0/projects/medisphere | jq .metadata
{ "auto_scan": "true", "enable_content_trust_cosign": "true", "prevent_vul": "true", "public": "false", "severity": "critical", … }
```

*3. Refus n° 1.*

```
admin@adm01:~$ skopeo copy docker://registry.par1.medisphere.internal/medisphere/mediagenda-api:vX.Y.Z \
    docker://registry.par1.medisphere.internal/medisphere/essai-politiques:non-signee
admin@adm01:~$ skopeo inspect docker://registry.par1.medisphere.internal/medisphere/essai-politiques:non-signee
FATA[0000] … reading manifest non-signee …: unknown: … The image is not signed by cosign.
```

Attention : `skopeo copy` d'une image signée ne copie **pas** la signature (référent) : la copie est donc une image non signée — c'est exactement l'essai voulu, et c'est aussi la panne de M13-E21 variante 3. Le registre répond `412 Precondition Failed` (code `PROJECTPOLICYVIOLATION`). Signer le digest (commande de E07, avec la configuration de signature MédiSphère) rend l'image tirable.

*4. Refus n° 2.* Une image ancienne : `skopeo copy docker://registry.par1.medisphere.internal/dockerhub/library/python:3.9.0 docker://…/medisphere/essai-politiques:vulnerable`, signée, analysée : `current image with "<N> vulnerabilities" cannot be pulled due to configured policy in 'Prevent images with vulnerability severity of "Critical" or higher from running.'` Une image **pas encore analysée** est refusée aussi (`The image has not been scanned for vulnerabilities and cannot be pulled…`, code de `vulnerable.go`) : la politique protège contre ce qu'on n'a pas regardé, et elle impose l'ordre de la chaîne (poussée → analyse → signature → disponible).

*5. Ce que la politique ne voit pas.* Une paire jetable (`cosign generate-key-pair` dans `/dev/shm`), signature de `essai-politiques:autre-cle` : l'image **se tire**. L'API montre un accessoire `signature.cosign` comme pour une image de la CI : Harbor vérifie la **présence** d'une signature Cosign, pas la clé. L'auteur est vérifié par le consommateur (étape 6) et, sur Kubernetes, par l'admission (M26).

*6. Le consommateur.* `templates/verification.yml` : image outillée de la CI (`plateforme/outils-supply-chain`, E09) par digest, refus d'une référence par étiquette, clé publique embarquée dans cette image (ou passée en variable de type fichier) dont l'empreinte est épinglée (une clé substituée ne passe pas), `cosign verify` puis `cosign verify-attestation --type spdxjson`, sans journal de transparence, et contrôle que la SBOM attestée n'est pas vide ; mêmes règles que la publication. Dans `mediagenda/api`, le job `verifier-signature` suit `sc:signature` et reçoit `SC_REF` (image par digest) par le rapport *dotenv* de `sc:publication`. Avant d'activer la politique, la chaîne de E09 a été relue : elle ne relit pas l'image par `skopeo` entre la poussée et la signature (empreinte prise dans `--digestfile`, provenance contrôlée sur l'archive), sinon `sc:publication` échouerait en `412`. Pipeline de branche avec l'image signée par la clé jetable : `Error: no matching signatures` → échec ; pipeline normal : succès.

*7. Nettoyage* : suppression du dépôt `medisphere/essai-politiques` (interface ou `DELETE /projects/medisphere/repositories/essai-politiques`), clé jetable effacée (`/dev/shm`), `politiques.md` publié.

**Explications**

Les deux politiques sont des intergiciels du registre de Harbor, appliqués au **tirage du manifeste** (`GET /v2/…/manifests/…`) : la signature exigée vérifie qu'un accessoire de type signature Cosign est attaché au digest ; la prévention lit le résumé de la dernière analyse. Le scanner (Trivy) et Cosign sont exemptés (le code journalise « pulling by the scanner/cosign, skip the checking ») : sinon une image non signée ne pourrait être ni analysée ni signée. La poussée n'est **jamais** bloquée par ces politiques : c'est la chaîne de livraison qui empêche de pousser une image vulnérable (E09), et c'est le tirage qui est verrouillé. La vérification par clé n'existe pas dans Harbor pour Cosign : elle appartient au consommateur.

**Alternatives**
- Sigstore *policy-controller* (webhook Kubernetes) : écarté au module 13 (exige Kubernetes, doublon de Kyverno au M26).
- Seuil `high` au lieu de `critical` : plus sûr, mais bloque souvent des images de base sans correctif disponible ; MédiSphère combine `critical` au registre et « Critical corrigeable » bloquant en CI.
- Liste blanche de CVE au niveau système : une exception pour tous les projets à la fois — refusée.

**Pièges classiques**
- Activer la signature exigée avant d'avoir signé l'existant : tout `medisphere` devient intirable d'un coup.
- Croire que « signée » veut dire « signée par nous ».
- Vérifier par étiquette dans le job du consommateur (`cosign verify image:vX`) : la vérification porte sur ce que l'étiquette désigne **au moment** de la vérification, pas sur ce qui sera déployé.
- Oublier que l'analyse de Trivy vieillit : une image propre aujourd'hui peut devenir « Critical » demain (nouvelle CVE) et être refusée au tirage suivant — c'est voulu, mais il faut le savoir avant le jour du déploiement (analyse périodique, M13-E05).

**En production chez MédiSphère**
Les mêmes politiques sur `plateforme` et `bibliotheque` dès que toutes leurs images sont signées ; exceptions datées, revues chaque mois ; admission Kubernetes par clé (M26) ; alerte sur les refus 412 dans les journaux de Harbor (M22).

---

### M13-E15 — Sauvegarder et restaurer Harbor

**Solution**

Fichiers : rôle [`sauvegarde_harbor`](fichiers/M13-E15/ansible/roles/sauvegarde_harbor/) (script de sauvegarde [`wb-backup-harbor.sh`](fichiers/M13-E15/ansible/roles/sauvegarde_harbor/files/wb-backup-harbor.sh), script de restauration [`wb-restaurer-harbor.sh`](fichiers/M13-E15/ansible/roles/sauvegarde_harbor/files/wb-restaurer-harbor.sh), unités), [`host_vars/reg01/sauvegarde_harbor.yml`](fichiers/M13-E15/ansible/inventories/lab/host_vars/reg01/sauvegarde_harbor.yml), [`host_vars/reg02/sauvegarde_harbor.yml`](fichiers/M13-E15/ansible/inventories/lab/host_vars/reg02/sauvegarde_harbor.yml), [`playbooks/sauvegarde-harbor.yml`](fichiers/M13-E15/ansible/playbooks/sauvegarde-harbor.yml), [jetons PBS](fichiers/M13-E15/pbs01/pbs-jetons-registre.sh), [flux](fichiers/M13-E15/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), documentation [`sauvegarde.md`](fichiers/M13-E15/medisphere/docs/registre/sauvegarde.md), [`tests/restauration-harbor.md`](fichiers/M13-E15/medisphere/docs/registre/tests/restauration-harbor.md), [RB-131](fichiers/M13-E15/medisphere/docs/registre/runbooks/RB-131-restaurer-harbor.md).

*1. Inventaire* (tableau complet dans `sauvegarde.md`) : sauvegardés — base `registry` (vidage), `/data/secret` (dont `keys/secretkey`), `/data/registry`, `harbor.yml` ; régénérables — `common/config`, `docker-compose.yml` (prepare), images Docker de Harbor (installateur), certificat (ACME) ; inutiles — `/data/database` brut (le vidage le remplace), `redis`, `trivy-adapter`, `job_logs`. Ordre : base puis blobs ; jamais pendant le ramasse-miettes.

*2. Le rôle.* Le script tourne en root, lit ses secrets dans des fichiers 600, vide la base **dans** le conteneur (`docker exec harbor-db pg_dump -U postgres -Fc registry > …` : le client et le serveur ont la même version majeure, la sortie est écrite sur l'hôte), contrôle le vidage (`pg_restore --list`, nombre de tables), note les versions (Harbor, PostgreSQL), puis envoie **une** sauvegarde PBS à quatre archives (`base`, `config`, `secret`, `registre`), chiffrée côté client. Le dossier de travail est effacé par `trap` quoi qu'il arrive.

*3. Planifier et constater.*

```
root@pbs01:~# bash pbs-jetons-registre.sh                     # espace par1/registre, jetons
admin@adm01:~/src/ansible$ ansible-playbook playbooks/sauvegarde-harbor.yml -l reg01
admin@reg01:~$ sudo systemctl start wb-backup-harbor.service && journalctl -u wb-backup-harbor -n 20
root@pbs01:~# proxmox-backup-client snapshot list --ns par1/registre --repository root@pam@localhost:ds-lab
```

La première sauvegarde transfère tout `/data/registry` ; les suivantes, seulement les nouveaux morceaux (déduplication de PBS) : note les deux tailles.

*4-5. Reconstruire et restaurer `reg02`.*

```
admin@adm01:~/src/infra/envs/m13$ tofu destroy -target=module.reg02 && tofu apply          # (MR, pipeline)
admin@adm01:~/src/ansible$ ansible-playbook playbooks/registre.yml -l reg02                 # même version que reg01
admin@adm01:~/src/ansible$ ansible-playbook playbooks/sauvegarde-harbor.yml -l reg02        # mode restauration
admin@reg02:~$ sudo wb-restaurer-harbor.sh --je-sais-ce-que-je-fais
```

Le script refuse une version de Harbor différente de celle de la sauvegarde, arrête Harbor, restaure blobs et clés (en gardant les anciens dossiers en `*.avant-restauration`), démarre **seulement** le service `postgresql` du `docker-compose.yml` (conteneur `harbor-db`), recrée la base et y restaure le vidage, **désactive toutes les politiques de réplication** dans la base, puis démarre Harbor.

*6. Vérifier* : la liste de `restauration-harbor.md`. La preuve que la bonne `secretkey` est restaurée : l'endpoint de réplication (ou d'un cache avec identifiant) restauré se teste sans erreur de déchiffrement. Les robots fonctionnent même sans elle : leurs secrets sont stockés **hachés** (avec sel), pas chiffrés.

*7-8.* Documentation et RB-131 ; puis `reg02` reconstruite vide et E13 rejouée (ou gardée restaurée, réplications désactivées, jusqu'à E16 : un choix à écrire).

**Explications**

Harbor est une application à état réparti : une base (l'index de tout : quels artefacts, quelles étiquettes, quels accessoires, quels droits), un stockage de blobs adressé par digest, et des clés. Une sauvegarde cohérente doit garantir que tout ce que la base référence existe dans les blobs : d'où le vidage d'abord (un instantané transactionnel), puis les blobs (qui ne font que s'ajouter entre-temps, sauf ramasse-miettes). La clé `secretkey` chiffre en base les identifiants des endpoints ; `core/private_key.pem` signe les jetons ; `registry/root.crt` permet au registre de les vérifier : restaurer la base sans `secret/` donne un Harbor qui démarre mais dont une partie ne marche pas, ce qui est pire qu'une panne franche.

**Alternatives**
- Sauvegarde de la VM entière par PBS (`lab-nuit`) : simple, mais 200 Go de blobs chaque nuit, pas de restauration sur une autre machine sans tout restaurer, cohérence de PostgreSQL « comme après une coupure ».
- Instantané de système de fichiers (LVM, XFS gelé) Harbor arrêté : cohérent, mais indisponibilité pendant l'instantané.
- Blobs par la réplication, base par sauvegarde : divise le volume ; dépend d'une seconde instance (PAR2).

**Pièges classiques**
- Copier `/data/database` à chaud (`tar`, `rsync`) : copie inutilisable, découverte le jour de la restauration.
- Restaurer dans une autre version de Harbor : schéma différent.
- Oublier les politiques de réplication restaurées (elles pointent vers la source ou vers soi-même) et les robots de production restaurés sur une VM d'essai.
- Clé de chiffrement PBS perdue : sauvegardes indéchiffrables ; elle est en Vault, et sa présence est testée par chaque restauration.

**En production chez MédiSphère**
Restauration testée chaque trimestre et à chaque livraison (E25), RTO et RPO suivis, alerte de la sonde si la sauvegarde a plus de 26 h, copie hors site par la synchronisation de PBS (PAR2 aux finaux).

---

### M13-E16 — Superviser et mettre à jour Harbor

**Solution**

Fichiers : sonde [`bin/ms-verif-registre`](fichiers/M13-E16/outils/bin/ms-verif-registre), [configuration](fichiers/M13-E16/outils/etc/ms-verif-registre.conf), [tests `bats`](fichiers/M13-E16/outils/tests/bats/ms-verif-registre.bats) (16 tests, sans réseau), unités [`.service`](fichiers/M13-E16/outils/systemd/ms-verif-registre.service) et [`.timer`](fichiers/M13-E16/outils/systemd/ms-verif-registre.timer) ; robot [`registre/supervision.tf`](fichiers/M13-E16/infra/registre/supervision.tf) ; [extrait de `group_vars/role_registre/harbor.yml`](fichiers/M13-E16/ansible/inventories/lab/group_vars/role_registre/harbor.yml.extrait) ; playbook [`harbor-mise-a-jour.yml`](fichiers/M13-E16/ansible/playbooks/harbor-mise-a-jour.yml) ; [RB-132](fichiers/M13-E16/medisphere/docs/registre/runbooks/RB-132-mettre-a-jour-harbor.md), [`tests/montee-version-harbor.md`](fichiers/M13-E16/medisphere/docs/registre/tests/montee-version-harbor.md).

*1. Observer.*

```
admin@adm01:~$ curl -s https://registry.par1.medisphere.internal/api/v2.0/health | jq
{ "status": "healthy", "components": [ {"name":"core","status":"healthy"}, {"name":"database",…}, {"name":"jobservice",…},
  {"name":"portal",…}, {"name":"redis",…}, {"name":"registry",…}, {"name":"registryctl",…}, {"name":"trivy",…} ] }
admin@reg01:~$ cd /opt/harbor && sudo docker compose ps
admin@reg01:~$ sudo ls /var/log/harbor/          # core.log, registry.log, proxy.log, jobservice.log, postgresql.log, …
```

Tous les conteneurs journalisent par `syslog` vers `harbor-log` (localhost:1514), qui écrit un fichier par composant. Sur `reg02`, `docker stop harbor-jobservice` : la santé passe à `unhealthy` (composant `jobservice`), tirages et poussées continuent, les exécutions de réplication restent en attente puis reprennent au redémarrage.

*2. Métriques.* `harbor_metriques: true` (rôle `harbor`, section `metric` de `harbor.yml`, `prepare` puis redémarrage par le rôle). Le proxy publie le port 9090 et l'exportateur `harbor-exporter` collecte.

```
admin@adm01:~$ curl -s http://reg01.par1.medisphere.internal:9090/metrics | grep -E '^harbor_(up|health|project_quota_usage_byte|statistics_total_storage_consumption|artifact_pulled)' | head
```

`harbor_up{component=…}` et `harbor_health` (état), `harbor_project_quota_usage_byte{project_name=…}` (occupation par projet), `harbor_statistics_total_storage_consumption` (volume total), `harbor_artifact_pulled` (tirages par projet). Aucun ne donne **l'espace libre** de `/data` : la sonde le lit dans `systeminfo/volumes`, et le module 21 ajoutera l'exportateur de nœud.

*3. La sonde.* Même structure que `ms-verif-ceph` (bibliothèque `ms-commun.sh`, configuration séparée, `ok`/`ko`, « rien vu » est un KO). Contrôles : santé et composants (le nom du composant en défaut dans le message), version (`systeminfo`), disque (`systeminfo/volumes`, seuil 80 %), chaque politique de réplication active (dernière exécution `Succeed` de moins de 26 h), dernier ramasse-miettes réussi depuis moins de 8 jours, métriques, certificat. Elle lit l'API avec **son** robot (`robot$supervision`, droits système en lecture sur volumes, réplication, GC), dont le secret est dans un fichier 600 au format shell (le nom entre apostrophes, à cause du `$`). Installation par `task install:systeme`, comme les autres sondes. Preuve de la chaîne d'alerte : `docker stop harbor-jobservice` sur `reg01` (5 minutes, fenêtre calme) → la sonde passe en KO au passage suivant, `ms-alerte@ms-verif-registre.service` part.

*4-5. Répétition et retour arrière sur `reg02`.* Version N-1 dans `host_vars/reg02/harbor.yml` (avec son empreinte), installation, réplication de quelques images, puis version N et :

```
admin@adm01:~/src/ansible$ ansible-playbook playbooks/harbor-mise-a-jour.yml -l reg02
```

Le playbook vérifie (un seul hôte ; montée strictement corrective en 2.15 ; santé ; sauvegarde récente pour `reg01`), arrête Harbor, copie `/data/database` **à l'arrêt**, appelle le rôle `harbor` avec `harbor_autoriser_changement_version: true` (archive vérifiée par empreinte, `harbor.yml` de l'ancienne version gardé en `harbor.yml.version-precedente`, bascule du lien `/opt/harbor`, `install.sh --with-trivy` dans le nouveau dossier), compare les clés de `harbor.yml` migré par `prepare migrate` (image `goharbor/prepare` de la nouvelle version) avec celles du gabarit du rôle, attend la santé (le cœur migre le schéma à son premier démarrage), contrôle la version annoncée. Retour arrière : RB-132 section 4 (lien vers l'ancien dossier, base d'avant, démarrage) — répété, chronométré.

*6-7.* RB-132 ; sur `reg01`, mise à jour dans la fenêtre si une version corrective plus récente existe, sinon date de la prochaine vérification.

**Explications**

Une mise à jour de Harbor change trois choses : les images des conteneurs (chargées depuis l'archive hors ligne), la configuration générée (le format de `harbor.yml` peut évoluer : `prepare migrate` le convertit, `prepare` régénère `common/config` et `docker-compose.yml`), et le **schéma de la base**, migré par `harbor-core` au démarrage (migrations SQL numérotées). Les deux premières se défont en revenant à l'ancien dossier ; la troisième seulement avec une copie de la base prise **avant** et **à l'arrêt**. C'est pourquoi le retour arrière est une procédure humaine et non un `rescue` automatique : il doit être décidé.

**Alternatives**
- Installateur en ligne (images tirées de Docker Hub au moment de l'installation) : plus léger, mais dépend du réseau et ne garantit pas que les images sont celles qu'on a vérifiées.
- Harbor sur Kubernetes par le chart Helm officiel (après M17) : mises à jour par `helm upgrade`, mais base et stockage à gérer à côté.

**Pièges classiques**
- Sonde lancée avec le robot des checks du workbook : une dépendance de la production envers un outil de formation.
- Métriques exposées à tout le lab : elles décrivent l'inventaire des projets (noms, volumes) ; MGMT seulement jusqu'au module 21.
- Monter de version sans relire les notes (changement de base embarquée, options supprimées).

**En production chez MédiSphère**
Vérification mensuelle des versions et avis de sécurité, répétition systématique sur une instance jetable, fenêtre annoncée ; alertes Prometheus au module 21 (santé, disque, réplication, certificat), avec les mêmes seuils que la sonde.

---

### M13-E17 — ADR : registre et politique de confiance des images

**Solution**

Modèle : [`ADR-0130-registre-et-confiance.md`](fichiers/M13-E17/medisphere/docs/registre/adr/ADR-0130-registre-et-confiance.md).

**Grille d'auto-évaluation**

| Critère | Attendu | Points |
|---|---|---|
| Contexte | exigences HDS/ISO formulées en questions (« d'où vient, que contient, qui a validé »), contraintes réelles (souveraineté, équipe, lab sans Rekor) | 2 |
| Registres | au moins trois options, critères **mesurés** dans le module (RPO, RTO, refus 412) plutôt qu'affirmés ; souveraineté éliminatoire pour le nuage public | 3 |
| Signature | quatre modes comparés sur dépendance, fuite d'information, clé, révocation, horodatage, outillage Kubernetes | 3 |
| Politique de confiance | chaque règle dit **où** et **comment** elle est vérifiée ; la limite de la politique Harbor (présence, pas clé) est explicite | 4 |
| Compromission | procédure pas à pas avec période de recouvrement et **preuve de provenance avant re-signature** | 3 |
| Risques acceptés | propriétaire, date ou module de révision | 2 |
| Forme | statut, décideurs, conséquences ; lisible par un auditeur | 1 |

16 points et plus : prêt pour Sophie. En dessous de 12 : reprends la politique de confiance, c'est elle que l'auditeur lira.

**Explications**

Un ADR ne justifie pas un outil, il rend un choix **révisable** : on doit pouvoir le rouvrir le jour où une hypothèse tombe (Rekor privé disponible, Kubernetes en production). Le cœur de celui-ci est la politique de confiance, qui survivra au changement d'outil.

**Pièges classiques**
- Comparer sur des généralités (« Harbor est plus complet ») au lieu des mesures du module.
- Écrire « les images sont signées » sans dire qui vérifie quoi.
- Oublier ce qu'on n'a pas (horodatage, révocation) : l'auditeur le trouvera.

---

### M13-E18 — Alerte CVE critique : répondre en temps limité

**Solution**

Outil : [`outils/sbom-recherche.sh`](fichiers/M13-E18/outils/sbom-recherche.sh) ; compte-rendu exemple : [`alertes/CS-2026-0412.md`](fichiers/M13-E18/medisphere/docs/registre/alertes/CS-2026-0412.md).

*Plan de 60 minutes* (celui qui marche) :

| Temps | Action |
|---|---|
| 0-5 min | Lire l'avis **mot à mot** : écosystème (PyPI), nom exact (`prometheus-client`), versions (≥ 0.26.0), condition d'exploitation (serveurs d'exposition de la bibliothèque), exclusions explicites (Go `client_golang`, Java), contournement (0.25.x). |
| 5-20 min | Inventaire par les SBOM attestées : un petit script (ou `sbom-recherche.sh`) qui, pour chaque dépôt et chaque étiquette `v*`, vérifie l'attestation SPDX avec la clé MédiSphère et cherche le nom normalisé. |
| 20-25 min | Priorisation : lire comment chaque application expose ses métriques. |
| 25-50 min | Correction de `medinotif` (exploitable) puis de `mediagenda-api` : contrainte `prometheus-client>=0.25,<0.26` dans `pyproject.toml`, `uv lock`, MR, pipeline (la chaîne fait le reste : SBOM, signature, attestation, publication). |
| 50-60 min | Preuve par la SBOM attestée de la nouvelle image, compte-rendu publié. |

*Inventaire* :

```
admin@adm01:~$ ~/src/outils/sbom-recherche.sh prometheus-client | column -t -s $'\t'
image                       etiquette  digest          paquet             version  purl                               preuve
medisphere/mediagenda-api   vX.Y.Z     sha256:…        prometheus-client  0.26.0   pkg:pypi/prometheus-client@0.26.0  SBOM attestée vérifiée
medisphere/medinotif        vX.Y.Z     sha256:…        prometheus-client  0.26.0   pkg:pypi/prometheus-client@0.26.0  SBOM attestée vérifiée
```

`medidoc` contient `github.com/prometheus/client_golang` : **faux ami** (autre langage, autre projet, exclu par l'avis). Une recherche naïve sur « prometheus » ou « client » le ferait apparaître.

*Priorisation* : `apps/medinotif/src/medinotif/__main__.py` appelle `start_http_server(settings.port_metriques)` → vecteur exploitable sur le port 9100 ; `apps/mediagenda/src/mediagenda/app.py` appelle `generate_latest()` dans sa propre route FastAPI `/metrics` → vecteur connu non exploitable, mais version vulnérable présente (l'avis demande de la retirer). Les deux sont corrigées ; `medinotif` d'abord.

*Correction et preuve* :

```
admin@adm01:~/src/medinotif$ sed -i 's/"prometheus-client>=0.26.0,<1"/"prometheus-client>=0.25,<0.26"/' pyproject.toml && uv lock
admin@adm01:~/src/medinotif$ grep -A1 'name = "prometheus-client"' uv.lock
name = "prometheus-client"
version = "0.25.0"
admin@adm01:~$ cosign verify-attestation --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true --type spdxjson \
    registry.par1.medisphere.internal/medisphere/medinotif@sha256:<NOUVEAU> \
  | jq -r '.payload | @base64d | fromjson | .predicate.packages[] | select(.name == "prometheus-client") | .versionInfo'
0.25.0
```

Renovate reproposera 0.26.0 : règle temporaire `allowedVersions: "<0.26"` pour ce paquet dans `renovate.json` des deux projets (ou dans `plateforme/renovate-config`), à retirer quand le correctif sort.

**Explications**

C'est l'usage même du SBOM : répondre à « sommes-nous touchés ? » sans réanalyser ni relire le code, à partir d'un inventaire **signé** (on sait qu'il décrit bien l'image et qu'il n'a pas été modifié). Trivy ne sert à rien ici tant que la CVE n'est pas publiée dans sa base : seule la recherche dans le SBOM fonctionne. La priorisation demande ensuite de revenir au code : le SBOM dit ce qui est **présent**, pas ce qui est **atteignable**.

**Pièges classiques**
- Rechercher « prometheus » et conclure que MédiDoc est touché.
- Rechercher `prometheus_client` (nom d'import) au lieu du nom du paquet, ou sans normalisation.
- Corriger en reconstruisant l'image sans changer le verrou (`uv.lock` fige 0.26.0).
- Republier sous la même étiquette (immuabilité `v*`) au lieu d'une nouvelle version.
- Oublier Renovate, qui rouvrira la porte la nuit suivante.

**En production chez MédiSphère**
`sbom-recherche.sh` versionné et testé, alimenté par la liste des images **déployées** (M20, Argo CD) plutôt que par toutes les étiquettes ; exercice d'alerte deux fois par an ; abonnement aux avis (CERT Santé, GHSA, listes Debian) branché sur un ticket automatique.
