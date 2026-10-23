# Final F6 — Phase 3 : Remédier — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence : il en existe d'autres, jugées sur les mêmes critères (écart fermé, preuve inaltérable, mécanisme auto-portant).

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- scripts (`archiver-audit`, `verifier-archive-audit.sh`, `exceptions-vuln-echues.sh`, collecteurs ajoutés à `ms-preuves`) : `bash -n` et `shellcheck -x` ;
- extrait du gabarit Alloy : relu contre les composants `loki.source.file`, `loki.process` (`stage.match`, `stage.json`, `stage.timestamp`) d'Alloy 1.21 ; non exécuté sur une plateforme F6 ;
- CronJob d'archive : YAML relu, profil `restricted`, jeton projeté pour OpenBao ;
- verrouillage d'objets : logique relue contre l'API S3 (`put-object --content-md5`, `head-object`, `get-object-lock-configuration`).

**Fichiers** : [`fichiers/F6-S08/`](fichiers/F6-S08/) et [`fichiers/F6-S09/`](fichiers/F6-S09/) : `medisphere/…` = `plateforme/medisphere`, `observabilite/…` = `plateforme/observabilite`, `ansible/…` = `plateforme/ansible`, `k8s/…` = `plateforme/k8s`, `secrets/…` = `plateforme/secrets`, `outils/…` = `plateforme/outils`, `politiques/…` = `plateforme/politiques`. Les `*.extrait*` se fusionnent dans le fichier existant (emplacement en tête).

---

### F6-S08 — Une traçabilité inaltérable

**Solution** (solution de référence ; ce `LIBRE` s'évalue sur la chaîne complète et son inaltérabilité)

Documents et code : [`journaux-audit.md`](fichiers/F6-S08/medisphere/docs/conformite/journaux-audit.md) ; Alloy : [`host_vars/git01/alloy.yml`](fichiers/F6-S08/ansible/inventories/lab/host_vars/git01/alloy.yml), [`host_vars/pve01/alloy.yml`](fichiers/F6-S08/ansible/inventories/lab/host_vars/pve01/alloy.yml), [`host_vars/pbs01/alloy.yml`](fichiers/F6-S08/ansible/inventories/lab/host_vars/pbs01/alloy.yml), [`config.alloy.j2.extrait-F6-S08`](fichiers/F6-S08/ansible/roles/alloy/templates/config.alloy.j2.extrait-F6-S08) ; archive : [`archiver-audit`](fichiers/F6-S08/observabilite/outils/archiver-audit), [`Containerfile`](fichiers/F6-S08/observabilite/images/audit-archive/Containerfile), [`cronjob-archive-audit.yaml`](fichiers/F6-S08/k8s/composants/audit-archive/cronjob-archive-audit.yaml), [`audit-archive.tf`](fichiers/F6-S08/secrets/tofu/audit-archive.tf), [`audit-archive.hcl`](fichiers/F6-S08/secrets/politiques/audit-archive.hcl) ; intégrité : [`verifier-archive-audit.sh`](fichiers/F6-S08/observabilite/outils/verifier-archive-audit.sh) ; preuves : [`catalogue.yaml.extrait-F6-S08-S10`](fichiers/F6-S08/outils/preuves/catalogue.yaml.extrait-F6-S08-S10) et [`collecteurs/`](fichiers/F6-S08/outils/preuves/collecteurs/) ; écart : [`ECA-3601-journaux-audit.md`](fichiers/F6-S08/medisphere/docs/conformite/ecarts/ECA-3601-journaux-audit.md).

La chaîne, bout à bout :

1. **Faire l'inventaire avant d'écrire du code.** Quatre sources arrivent déjà dans le locataire `audit` : Kubernetes (`{job="kubernetes-audit"}`, M22-E07), OpenBao (`{service="openbao"}`, dispositif **déclaré** dans `openbao.hcl` au M25-E21 — depuis OpenBao 2.3.2, `bao audit enable` est refusé tant que `unsafe_allow_api_audit_creation` n'est pas activé, et il ne doit pas l'être), Keycloak et FreeIPA (`{service="keycloak"}`, `{service="freeipa"}`, M24-E26). Le constat d'Hélène porte donc sur **deux** sources manquantes et sur l'inaltérabilité de toutes.
   ```
   admin@adm01:~$ logcli --org-id=audit series --since=24h '{service=~".+"}' | sort -u
   admin@adm01:~$ logcli --org-id=audit series --since=24h '{job="kubernetes-audit"}' | head -3
   ```
2. **GitLab et Proxmox** par le mécanisme du M24 (rôle `alloy`), pas un nouveau : `git01` lit `audit_json.log` (`alloy_audit_fichiers`, capacité de lecture seule comme `ipa01`) ; `pve01` envoie le journal de `pvedaemon` (connexions, tâches et leur auteur) et `/var/log/pveproxy/access.log` (requêtes de l'API) ; `pbs01` (hôte `hp01`) envoie `/var/log/proxmox-backup/api/auth.log` et `access.log` (son journal systemd ne garde que les erreurs) — les deux hôtes physiques entrent dans le groupe `alloy` de l'inventaire, l'agent seul est installé. ⚠️ Plusieurs unités d'un même service sur un hôte : le gabarit du M24 nommait le composant `loki.source.journal "audit_<service>"`, ce qui donnerait deux composants de même nom et une configuration refusée par Alloy ; l'extrait le nomme par unité (étape 0 de l'extrait). ⚠️ La politique réseau de Loki (`loki-entree`, M22-E16) n'accepte de requêtes que de Grafana et d'écritures que de sources listées : ajoute la lecture pour le CronJob d'archive et l'écriture pour `pve01` et `hp01` ([`politique-reseau.extrait-F6-S08.yaml`](fichiers/F6-S08/observabilite/loki/manifestes/politique-reseau.extrait-F6-S08.yaml)), et les flux correspondants à la bordure. Vérifie ensuite les six sélecteurs (c'est ce que fait le check, et la preuve P-AUD-01).
3. **Horodatage à la source** : journald porte l'heure de l'événement ; pour les fichiers JSON, l'extrait du gabarit ajoute un champ `horodatage` par fichier (`time` pour GitLab) et une étape `stage.timestamp` avec `action_on_failure = "skip"` (une ligne illisible garde l'heure de lecture, on n'invente jamais une heure). Référence de temps : chrony de `gw01`/`gw02`.
4. **Archive inaltérable** : compartiment `archive-audit` créé **avec** le verrou par le script du F6-S02 paramétré (`COMPARTIMENT=archive-audit PROPRIETAIRE=archive-audit LECTEUR=archive-audit-lecture KV_BASE=plateforme/archive-audit rgw-preuves.sh creer`), essais en `GOVERNANCE` 1 jour, puis `rgw-preuves.sh retention COMPLIANCE 365` (même variables). Le CronJob `journaux/audit-archive` lance chaque nuit `archiver-audit` sur la veille : extraction paginée de chaque source, un `<source>.jsonl.gz` par source, `manifeste.json`, signature du SHA-256 du manifeste par `transit/audit-archive` (méthode kubernetes `k8s-par1`, rôle `audit-archive`, jeton projeté : aucune clé ni jeton statique dans le cluster), dépôt sous `AAAA-MM-JJ/` (signature en dernier) et contrôle que chaque objet porte la rétention `COMPLIANCE`. Fichier d'identité de lecture de `adm01` (`s3-archive-audit-lecture.env`) : même commande qu'en S02, depuis `kv/plateforme/archive-audit/rgw-lecture`.
5. **Contrôle d'intégrité indépendant** : `verifier-archive-audit.sh`, pipeline planifié `archive:verifier` de `plateforme/observabilite` (rôle JWT `ci-observabilite-archive`, politique `audit-archive-verif` : `transit/verify/audit-archive` et la lecture de l'identité S3 de lecture) ; à la main :
   ```
   admin@adm01:~/src/observabilite$ export BAO_TOKEN="$(bao print token)"
   admin@adm01:~/src/observabilite$ outils/verifier-archive-audit.sh "$(date -u -d yesterday +%F)"
   ```
   Fais-le rougir exprès sur une période d'essai en `GOVERNANCE` (remplace un objet : nouvelle version, condensat différent) avant de le croire.
6. **Épreuve du verrou** (le cœur de l'écart) :
   ```
   admin@adm01:~$ (set -a; . <(bao kv get -format=json -mount=kv plateforme/archive-audit/rgw-ecriture | jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"'); set +a
       v=$(aws --endpoint-url https://rgw.par1.medisphere.internal s3api list-object-versions --bucket archive-audit \
             --prefix "$(date -u -d yesterday +%F)/manifeste.json" --query 'Versions[0].VersionId' --output text)
       aws --endpoint-url https://rgw.par1.medisphere.internal s3api delete-object --bucket archive-audit \
         --key "$(date -u -d yesterday +%F)/manifeste.json" --version-id "$v")
   An error occurred (AccessDenied) when calling the DeleteObject operation: forbidden by object lock
   ```
   (message posé par le RGW, `rgw_op.cc` de Ceph 20.2, quand le verrou refuse la suppression)
   (sans `--version-id`, la commande « réussit » : elle pose un marqueur de suppression dans un compartiment versionné, la version reste — à savoir expliquer à l'auditrice.)
7. **Fermeture d'ECA-3601** : les preuves P-AUD-01, P-AUD-02 et P-CTL-01 entrent au catalogue (`ms-preuves`, et `preuves.md`), un lot quotidien les contient, la fiche passe en `clos` en citant **ce lot** (antérieur à la date de clôture), le plan de remédiation est mis à jour.

**Explications**
- **Centraliser ≠ rendre inaltérable.** Loki rassemble et rend consultable ; mais qui administre Loki peut, en théorie, réécrire un segment. L'inaltérabilité vient du verrouillage d'objets du RGW : un objet `COMPLIANCE` ne se supprime ni ne se remplace avant son échéance, pour personne. L'archive est la pièce qu'on présente ; Loki est l'outil de travail.
- **Le manifeste signé** répond à la question de l'auditeur (« comment prouvez-vous que ce journal n'a pas été retouché ? ») : la signature atteste qui a produit le manifeste, les condensats attestent que les objets sont ceux de la période, le verrouillage atteste qu'ils n'ont pas bougé depuis.
- **Pas de secret dans l'audit** : la politique d'audit de l'API (niveau `Metadata` pour les Secrets, M14) et le HMAC d'OpenBao garantissent que le locataire `audit` — et donc l'archive — ne contient aucune valeur sensible. C'est ce qui rend acceptable de la conserver un an et de la présenter. Les journaux de GitLab et de Proxmox contiennent des identifiants de personnes et des adresses : données personnelles des administrateurs, d'où la durée bornée et l'accès réservé au locataire `audit` (sécurité, astreinte).
- **Pourquoi un compartiment dédié** : l'archive n'a ni le même producteur (un CronJob du cluster, pas le pipeline de collecte), ni le même volume, ni le même lecteur ; la mêler à `preuves-conformite` donnerait au CronJob le droit d'écrire là où sont les preuves de tout le reste.

**Alternatives**
- WORM au niveau du système de fichiers (montage immuable, `chattr +i`) : contournable par root ; le verrouillage d'objets du RGW est opposable (l'administrateur du RGW lui-même ne peut pas lever un `COMPLIANCE`).
- Horodatage qualifié (RFC 3161, autorité de datation) sur le manifeste : plus fort juridiquement ; hors périmètre du lab, à noter comme amélioration.
- Loki avec rétention d'un an **sans** archive : centralise mais ne prouve rien (altérable, et un an de `audit` dans Loki coûte cher) ; l'archive froide verrouillée est moins chère et opposable.
- Envoyer chaque source dans un SIEM (Wazuh, Elastic) : plus riche en corrélation, plus lourd ; Loki + archive suffit à l'exigence de traçabilité inaltérable.

**Pièges classiques**
- Chercher à « activer l'audit d'OpenBao » avec `bao audit enable` : refusé depuis OpenBao 2.3.2 (sauf option `unsafe_allow_api_audit_creation`, à ne pas activer) ; il est déjà déclaré dans `openbao.hcl` depuis le M25.
- Créer le compartiment d'archive **sans** verrouillage en comptant l'activer plus tard : le RGW de Tentacle l'accepte après coup seulement si le versionnage est actif (sinon `InvalidBucketState`), et les objets déjà écrits n'ont aucune rétention. Créer avec `--object-lock-enabled-for-bucket` dès le départ.
- « Prouver » le verrou par un `delete-object` sans `--version-id` : il réussit (marqueur de suppression) et ne prouve rien.
- Tester directement en `COMPLIANCE` : une erreur de date (10 ans au lieu d'1) devient irréversible. Éprouver en `GOVERNANCE`, qui se lève avec le bon droit, puis basculer.
- Dater à la réception (pas d'étape `timestamp`) : une chronologie d'incident décalée de plusieurs minutes, inexploitable.
- Oublier que l'archive doit aussi contenir le **manifeste** et sa **signature** : sans eux, l'archive est inaltérable mais non prouvable.
- Confondre rétention audit (1 an) et rétention applicative (courte) : garder un an de journaux applicatifs viole la minimisation et coûte cher.

**En production chez MédiSphère**
L'archive d'audit est présentée à l'auditeur HDS avec le rapport d'intégrité ; une alerte « trou de journalisation » (aucune ligne d'une source pendant N minutes) couvre l'angle mort d'un collecteur muet ; le manifeste est en plus horodaté par une autorité de datation qualifiée ; l'accès en lecture à l'archive est tracé (lui-même dans l'audit).

---

### F6-S09 — Vulnérabilités et exceptions sous contrôle

**Solution** (solution de référence)

Documents et code : [`vulnerabilites.md`](fichiers/F6-S09/medisphere/docs/conformite/vulnerabilites.md), [`exceptions-vuln-echues.sh`](fichiers/F6-S09/politiques/outils/exceptions-vuln-echues.sh), [`planifications.extrait-F6.yaml`](fichiers/F6-S09/k8s/composants/velero/planifications.extrait-F6.yaml), [`ECA-3602-vulnerabilites.md`](fichiers/F6-S09/medisphere/docs/conformite/ecarts/ECA-3602-vulnerabilites.md), [`ECA-3603-sauvegardes-chiffrement.md`](fichiers/F6-S09/medisphere/docs/conformite/ecarts/ECA-3603-sauvegardes-chiffrement.md).

1. **Politique de traitement** (`vulnerabilites.md`) : délais depuis la **première détection**, justifiés —
   | Criticité | Délai de traitement | Mesure du retard |
   |---|---|---|
   | Critique | 7 jours (corrigeable), sinon exception datée | `aujourd'hui − première_détection` |
   | Élevée | 30 jours | idem |
   | Moyenne | 90 jours | idem |
   | Basse | au prochain cycle de mise à jour de l'image de base | — |
   Lien avec l'existant : Harbor bloque **toutes** les critiques au tirage, la CI bloque les critiques **corrigeables** (M13) ; la politique ajoute l'engagement de délai et la mesure. Circuit d'exception : proposée par l'équipe, validée par la RSSI, durée **≤ 90 jours**, compensation écrite, inscrite au registre `EXC-…` (type `EXC-V-nnn`, « vulnérabilité »).

2. **Exceptions auto-expirantes** : une exception de vulnérabilité = une CVE dans la `cve_allowlist` du projet Harbor (si le projet a `reuse_sys_cve_allowlist`, c'est la liste du système qui s'applique, et le contrôle la lit) + une ligne `EXC-V-nnn` au registre (CVE, image, compensation, échéance ≤ 90 jours, valideur). La liste de Harbor n'a qu'**une** date d'expiration (`expires_at`, pour toute la liste) : on la règle sur l'échéance la plus proche ; à cette date Harbor cesse de l'appliquer en entier, et ce qui reste justifié se revalide. Le contrôle `exceptions-vuln-echues.sh` (job de CI de `plateforme/politiques`) lit la `cve_allowlist` (API Harbor) et le registre, et **échoue** si une exception est échue, si une date manque, ou si les deux côtés divergent — même logique que le pipeline des `PolicyException` du M26. Une exception échue ne s'applique donc plus (Harbor) **et** fait rougir la CI (contrôle).

3. **Tableau de suivi** (`observabilite/tableaux/securite/vulnerabilites.json`, UID `f6-vulnerabilites`) : alimenté par les métriques de Trivy Operator (`VulnerabilityReport` exposés) et/ou l'API de Harbor ; colonnes criticité, âge, échéance, **retard** (rouge si dépassé). Aucune saisie manuelle.

4. **Chiffrement côté serveur (ECA-3603)** :
   - *Velero, données des volumes* : Kopia chiffre toujours, mais avec la phrase **par défaut** que Velero écrit à l'installation dans `velero/velero-repo-credentials` (clé `repository-password`) — publique, donc équivalente au clair. Un `ExternalSecret` (`planifications.extrait-F6.yaml`) la remplace par une phrase aléatoire rangée dans `kv/plateforme/velero/depot`. La phrase est globale et un dépôt existant garde la sienne : nouveau préfixe `kopia-v2` pour l'emplacement `s3-01` (valeurs du chart, M16-E16 ; les `BackupRepository` existants, qui gardent l'adresse de l'ancien dépôt, sont supprimés pour être recréés), ancien emplacement déclaré en lecture seule jusqu'à l'expiration des anciennes sauvegardes. Velero ne crée ce Secret que s'il n'existe pas (`EnsureCommonRepositoryKey`, phrase `static-passw0rd` dans le code de la 1.18) : c'est ce qui permet à ESO de le fournir.
   - *Velero, manifestes* : Velero dépose l'archive des objets **en clair** ; on en exclut les Secrets (recréés par ESO depuis OpenBao) par un correctif des planifications existantes (`recette-quotidienne`, `mediagenda-dev-quotidienne`), sans en créer de nouvelle. Ce qui reste n'est pas une donnée de santé.
   - *Exports bruts* (dumps, archives) : chiffrés par `age` dans le pipeline (clé publique dans le dépôt, clé privée dans `kv/plateforme/exports/age`) avant dépôt sur `s3-01`.
   - *Restauration éprouvée* : restauration d'essai de `medidoc-dev` (dans `wb-essais`) depuis une sauvegarde faite **après** le changement de phrase ; déchiffrement d'un export `age` d'essai. Procédures dans `vulnerabilites.md` (§ 5).

5. **Fermeture** : P-VUL-03, P-SAV-03 et P-CTL-01 entrent au catalogue (collecteurs `harbor-allowlist`, `velero-chiffrement`, `controles-planifies`) ; les fiches `ECA-3602` et `ECA-3603` passent en `clos` en citant chacune un lot qui les contient, antérieur à la clôture.

**Explications**
- **Un délai sans mesure n'existe pas.** La politique n'a de valeur que si on mesure le retard (date de première détection → aujourd'hui) et qu'on le voit. D'où le tableau, pas une note.
- **L'exception doit mourir seule.** Le mode d'échec d'un registre de tableur est l'exception « provisoire » de trois ans. Le mécanisme auto-expirant (date dans Harbor **et** contrôle CI qui rejette l'échéance) retire la décision humaine du chemin critique : à la date, l'image vulnérable est de nouveau bloquée.
- **« Côté serveur ».** Le risque d'ECA-3603 est un administrateur du stockage objet qui lit des données de santé en clair dans une sauvegarde. Chiffrer avant que l'objet n'arrive au stockage (Kopia pour Velero, `age` pour les exports) supprime ce risque ; la clé vit dans OpenBao, séparée du stockage.

**Alternatives**
- Délais plus stricts (critique 48 h) : plus sûr, souvent intenable quand le correctif n'existe pas encore ; MédiSphère assume 7 jours + exception datée obligatoire.
- Chiffrement côté serveur du stockage objet (SSE-S3, SSE-C par le greffon AWS de Velero) : protège le disque, **pas** l'administrateur du stockage qui détient ou voit passer la clé ; le chiffrement avant dépôt (`age`, Kopia avec une phrase d'OpenBao) protège aussi de lui.
- Trivy Operator comme seule source : pratique dans le cluster, mais ne voit pas les images non déployées ; combiner avec l'analyse de Harbor.

**Pièges classiques**
- Une `cve_allowlist` sans `expires_at` : l'exception est éternelle, l'écart revient. Croire qu'on peut dater chaque CVE dans Harbor : la date porte sur toute la liste du projet.
- Aligner mal les seuils chaîne/registre (M13) : une image avec une critique **non corrigeable** passe la CI puis ne peut plus être tirée ; décider (exception datée) et l'écrire.
- Chiffrer la sauvegarde sans jamais éprouver la restauration : le jour du sinistre, la clé est introuvable ou la phrase est fausse.
- Changer `repository-password` sur place : les dépôts Kopia existants restent chiffrés avec l'ancienne phrase, Velero ne les ouvre plus (sauvegardes et restaurations en échec) ; d'où le nouveau préfixe.
- Croire que Kopia chiffre « toute la sauvegarde » : l'archive des manifestes (Secrets compris, si on ne les exclut pas) part en clair.
- Mesurer le retard depuis la date du jour de l'exception au lieu de la première détection : on masque le retard réel.

**En production chez MédiSphère**
Le respect des délais devient un SLO (« 95 % des critiques traitées dans le délai »), présenté à la revue sécurité et à l'auditeur ; la clé de chiffrement des sauvegardes est tournée annuellement (et on garde l'ancienne le temps de la rétention des anciennes sauvegardes) ; le tableau de vulnérabilités est projeté à la revue hebdomadaire de la plateforme.

---

## Points non testés en conditions réelles (phase 3)

- Collecte Alloy de **GitLab** et de **Proxmox** vers le locataire `audit` : relue contre le mécanisme du M24-E26, non exécutée sur une plateforme F6 ; chemins et droits des journaux d'accès de `pveproxy` et de PBS (`/var/log/proxmox-backup/api/`) à relever sur tes hôtes.
- Velero 1.18 : prise de propriété par ESO du Secret `velero-repo-credentials` créé par Velero, et nouveaux dépôts Kopia sous le préfixe `kopia-v2` (vérifie sur ta plateforme que les anciennes sauvegardes restent listées par l'emplacement en lecture seule) ; CRD `backuprepositories.velero.io` lue par le collecteur `velero-chiffrement`.
- `archiver-audit` : pagination de `query_range` (entrées de même horodatage en bord de page), volume d'une journée d'audit (taille de l'`emptyDir`), paquet `awscli` de Debian 13 dans l'image, étiquette de l'image de base `bibliotheque/debian` ; signature `transit` pré-hachée (`prehashed`, clé `ecdsa-p256`).
- Adresse source de `pve01` et de `hp01` vue par Loki (traduction ou non par la bordure, `externalTrafficPolicy` du Service de Loki) : à relever par Hubble avant de figer la politique `loki-entree`.
- GitLab Free : événements réellement écrits dans `audit_json.log` ; droits du dossier des journaux d'Omnibus (lecture par Alloy avec `CAP_DAC_READ_SEARCH`) ; Alloy sur `pve01` et `pbs01` (hôtes physiques) et flux `pbs01` → Loki par `wg0`.
- Collecteurs ajoutés à `ms-preuves` (`audit-sources`, `archive-audit-verrou`, `harbor-allowlist`, `velero-chiffrement`, `controles-planifies`) : `shellcheck` propre, non exécutés. Vérifié dans le `swagger.yaml` de Harbor v2.15.0 : le modèle `Project` porte `cve_allowlist`, `CVEAllowlist.expires_at` est en secondes depuis l'époque (absent = sans fin), `GET /system/CVEAllowlist` est lisible par tout utilisateur authentifié.
- Comportement de Harbor 2.15 **à** la date `expires_at` (liste ignorée en entier au tirage) : à confirmer sur le lab ; le contrôle CI reste le filet.
- Bascule `GOVERNANCE` → `COMPLIANCE` du compartiment d'archive : éprouvée sur un compartiment jetable seulement.
