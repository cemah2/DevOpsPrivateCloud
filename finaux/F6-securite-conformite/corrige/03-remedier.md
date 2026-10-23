# Final F6 — Phase 3 : Remédier — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence : il en existe d'autres, jugées sur les mêmes critères (écart fermé, preuve inaltérable, mécanisme auto-portant).

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- scripts (`verifier-archive-audit.sh`, `exceptions-vuln-echues.sh`) : `bash -n` et `shellcheck -x` ;
- manifestes Alloy : relus contre la syntaxe des composants `local.file_match`, `loki.source.file`, `loki.process` de la 1.21 (M22) ; non exécutés sur une vraie plateforme F6 ;
- CronJob d'archive : YAML valide, image par Harbor, profil `restricted` ;
- verrouillage d'objets : logique relue contre l'API S3 `put-object` (`--object-lock-mode`, `--object-lock-retain-until-date`) et `get-object-lock-configuration`.

**Points non testés en conditions réelles** : voir la fin de l'énoncé (collecte Keycloak/GitLab/FreeIPA, bascule `COMPLIANCE`, chiffrement du dépôt Kopia). Signale tes retours.

**Fichiers** : [`fichiers/F6-S08/`](fichiers/F6-S08/) et [`fichiers/F6-S09/`](fichiers/F6-S09/) : `medisphere/…` = `plateforme/medisphere`, `observabilite/…` = `plateforme/observabilite`, `k8s/…` = `plateforme/k8s`, `politiques/…` = `plateforme/politiques`. Les `*.extrait*` se fusionnent dans le fichier existant (emplacement en tête).

---

### F6-S08 — Une traçabilité inaltérable

**Solution** (solution de référence ; ce `LIBRE` s'évalue sur la chaîne complète et son inaltérabilité)

Documents et code : [`journaux-audit.md`](fichiers/F6-S08/medisphere/docs/conformite/journaux-audit.md), [`audit-sources.alloy.extrait-F6`](fichiers/F6-S08/observabilite/alloy/audit-sources.alloy.extrait-F6), [`cronjob-archive-audit.yaml`](fichiers/F6-S08/k8s/composants/audit-archive/cronjob-archive-audit.yaml), [`verifier-archive-audit.sh`](fichiers/F6-S08/observabilite/outils/verifier-archive-audit.sh), [`ECA-3601.md`](fichiers/F6-S08/medisphere/docs/conformite/ecarts/ECA-3601.md).

La chaîne, bout à bout :

1. **Six sources vers un puits** (locataire `audit` de Loki) :
   - *Kubernetes* : déjà en place (M22, cible `audit` d'Alloy, `/var/log/kubernetes/audit/audit.log`, `job="kubernetes-audit"`) ;
   - *OpenBao* : `bao audit enable file file_path=/var/log/openbao/audit.log` sur chaque nœud `vault01-03` (rôle Ansible `role_coffre`) ; le format JSON HMAC les champs sensibles (les valeurs ne sont jamais en clair) ; cible Alloy sur l'hôte, `job="openbao-audit"` ;
   - *Keycloak* : écouteur d'événements `jboss-logging` activé (événements d'administration **et** de connexion), écrits en JSON dans le journal de `idp01`, cible Alloy `job="keycloak-audit"` ;
   - *GitLab* : `audit_json.log` des composants (`gitlab-rails`), cible Alloy sur `git01`, `job="gitlab-audit"` ;
   - *Proxmox* : journal des tâches (`/var/log/pve/tasks/`) et `journald` d'authentification de `pve01` et `pbs01`, cible Alloy, `job="proxmox-audit"` ;
   - *FreeIPA* : greffon d'audit de 389-ds (`nsslapd-auditlog`) et les connexions Kerberos (`/var/log/krb5kdc.log`) de `ipa01`, cible Alloy, `job="freeipa-audit"`.
   Chaque source garde `stage.tenant { value = "audit" }` et une étiquette `job` distincte. La fédération ne change pas : c'est un locataire, pas des métriques.

2. **Horodatage cohérent** : `gw01` (chrony) est la référence de temps de tout le lab (M00) ; chaque source émet un horodatage, l'étape `stage.timestamp` d'Alloy s'en sert (sinon Loki date à la réception, ce qui fausse une chronologie d'incident). Documenté dans `journaux-audit.md`.

3. **Archive inaltérable** : un CronJob quotidien (`audit-archive`, espace `observabilite`, image par Harbor, `restricted`) interroge Loki (`query_range` sur le locataire `audit`, 24 h en arrière), écrit un fichier compressé par source, calcule leurs condensats, construit un **manifeste** (période, objets, SHA-256, nombre de lignes), **signe** le manifeste par `transit` d'OpenBao, puis dépose le tout dans le compartiment `archive-audit` (RGW de `ceph-par1`) **en verrouillage d'objets** : `aws s3api put-object --object-lock-mode COMPLIANCE --object-lock-retain-until-date <aujourd'hui + 1 an>`. Le compartiment est créé **dès le départ** avec le verrouillage activé (le versionnage est obligatoire ; on ne peut pas l'activer après coup selon les versions).

4. **Contrôle d'intégrité indépendant** : `verifier-archive-audit.sh` (lancé par un pipeline planifié, et à la demande d'un auditeur) télécharge le manifeste et les objets d'une période, **vérifie la signature** (`transit`/Cosign), recalcule les condensats et les compare. Un écart → sortie non nulle → alerte. C'est ce contrôle, pas Loki, qui prouve que rien n'a bougé.

5. **Conservation et minimisation** : rétention `audit` d'un an dans Loki (M22-E13) **et** un an sur l'archive (échéance du verrouillage) ; les journaux applicatifs gardent leur rétention courte. La politique est écrite (`journaux-audit.md`) : on garde un an parce que c'est l'exigence et la durée utile d'une enquête, pas plus, parce que garder plus augmente le coût, la gravité d'une fuite et la difficulté d'un effacement (RGPD, minimisation).

6. **Fermeture d'ECA-3601** : `ECA-3601.md` passe en `clos`, preuve = l'identifiant de l'objet `ms-preuves` qui contient la configuration Alloy, la configuration du verrouillage du compartiment (`get-object-lock-configuration`), une capture d'un échec de suppression sous `COMPLIANCE`, et un rapport vert de `verifier-archive-audit.sh`.

**Explications**
- **Centraliser ≠ rendre inaltérable.** Loki rassemble et rend consultable ; mais qui administre Loki peut, en théorie, réécrire un segment. L'inaltérabilité vient du verrouillage d'objets du RGW : un objet `COMPLIANCE` ne se supprime ni ne se remplace avant son échéance, pour personne. L'archive est la pièce qu'on présente ; Loki est l'outil de travail.
- **Le manifeste signé** répond à la question de l'auditeur (« comment prouvez-vous que ce journal n'a pas été retouché ? ») : la signature atteste qui a produit le manifeste, les condensats attestent que les objets sont ceux de la période, le verrouillage atteste qu'ils n'ont pas bougé depuis.
- **Pas de secret dans l'audit** : la politique d'audit de l'API (niveau `Metadata` pour les Secrets, M14) et le HMAC d'OpenBao garantissent que le locataire `audit` — et donc l'archive — ne contient aucune valeur sensible. C'est ce qui rend acceptable de la conserver un an et de la présenter.

**Alternatives**
- WORM au niveau du système de fichiers (montage immuable, `chattr +i`) : contournable par root ; le verrouillage d'objets du RGW est opposable (l'administrateur du RGW lui-même ne peut pas lever un `COMPLIANCE`).
- Horodatage qualifié (RFC 3161, autorité de datation) sur le manifeste : plus fort juridiquement ; hors périmètre du lab, à noter comme amélioration.
- Loki avec rétention d'un an **sans** archive : centralise mais ne prouve rien (altérable, et un an de `audit` dans Loki coûte cher) ; l'archive froide verrouillée est moins chère et opposable.
- Envoyer chaque source dans un SIEM (Wazuh, Elastic) : plus riche en corrélation, plus lourd ; Loki + archive suffit à l'exigence de traçabilité inaltérable.

**Pièges classiques**
- Créer le compartiment d'archive **sans** verrouillage puis vouloir l'activer : selon les versions du RGW, impossible après coup. Créer avec `--object-lock-enabled-for-bucket` dès le départ.
- Tester directement en `COMPLIANCE` : une erreur de date (10 ans au lieu d'1) devient irréversible. Éprouver en `GOVERNANCE`, qui se lève avec le bon droit, puis basculer.
- Dater à la réception (pas d'étape `timestamp`) : une chronologie d'incident décalée de plusieurs minutes, inexploitable.
- Oublier que l'archive doit aussi contenir le **manifeste** et sa **signature** : sans eux, l'archive est inaltérable mais non prouvable.
- Confondre rétention audit (1 an) et rétention applicative (courte) : garder un an de journaux applicatifs viole la minimisation et coûte cher.

**En production chez MédiSphère**
L'archive d'audit est présentée à l'auditeur HDS avec le rapport d'intégrité ; une alerte « trou de journalisation » (aucune ligne d'une source pendant N minutes) couvre l'angle mort d'un collecteur muet ; le manifeste est en plus horodaté par une autorité de datation qualifiée ; l'accès en lecture à l'archive est tracé (lui-même dans l'audit).

---

### F6-S09 — Vulnérabilités et exceptions sous contrôle

**Solution** (solution de référence)

Documents et code : [`vulnerabilites.md`](fichiers/F6-S09/medisphere/docs/conformite/vulnerabilites.md), [`exceptions-vuln-echues.sh`](fichiers/F6-S09/politiques/outils/exceptions-vuln-echues.sh), [`planifications.extrait-F6.yaml`](fichiers/F6-S09/k8s/composants/velero/planifications.extrait-F6.yaml), [`ECA-3602.md`](fichiers/F6-S09/medisphere/docs/conformite/ecarts/ECA-3602.md), [`ECA-3603.md`](fichiers/F6-S09/medisphere/docs/conformite/ecarts/ECA-3603.md).

1. **Politique de traitement** (`vulnerabilites.md`) : délais depuis la **première détection**, justifiés —
   | Criticité | Délai de traitement | Mesure du retard |
   |---|---|---|
   | Critique | 7 jours (corrigeable), sinon exception datée | `aujourd'hui − première_détection` |
   | Élevée | 30 jours | idem |
   | Moyenne | 90 jours | idem |
   | Basse | au prochain cycle de mise à jour de l'image de base | — |
   Lien avec l'existant : Harbor bloque **toutes** les critiques au tirage, la CI bloque les critiques **corrigeables** (M13) ; la politique ajoute l'engagement de délai et la mesure. Circuit d'exception : proposée par l'équipe, validée par la RSSI, durée **≤ 90 jours**, compensation écrite, inscrite au registre `EXC-…` (type `EXC-V-nnn`, « vulnérabilité »).

2. **Exceptions auto-expirantes** : une exception de vulnérabilité = une entrée de la `cve_allowlist` du projet Harbor **avec** `expires_at` (Harbor cesse de l'appliquer à la date) + une ligne `EXC-V-nnn` au registre avec la même date. Le contrôle `exceptions-vuln-echues.sh` (job de CI de `plateforme/politiques`) lit la `cve_allowlist` (API Harbor) et le registre, et **échoue** si une exception est échue, si une date manque, ou si les deux côtés divergent — même logique que le pipeline des `PolicyException` du M26. Une exception échue ne s'applique donc plus (Harbor) **et** fait rougir la CI (contrôle).

3. **Tableau de suivi** (`observabilite/tableaux/securite/vulnerabilites.json`, UID `f6-vulnerabilites`) : alimenté par les métriques de Trivy Operator (`VulnerabilityReport` exposés) et/ou l'API de Harbor ; colonnes criticité, âge, échéance, **retard** (rouge si dépassé). Aucune saisie manuelle.

4. **Chiffrement côté serveur (ECA-3603)** :
   - *Velero* : dépôt Kopia chiffré par une phrase de passe tirée d'OpenBao (`kv/velero/depot/phrase`), injectée dans le Secret du dépôt par ESO ; le RGW/`s3-01` ne voit que du chiffré. (`planifications.extrait-F6.yaml` documente le `BackupRepository`/secret ; champ exact à confirmer sur Velero 1.18.)
   - *Exports bruts* (dumps, archives) : chiffrés par `age` dans le pipeline (clé publique en clair dans le dépôt, clé privée dans `kv/exports/age`) avant dépôt sur `s3-01`.
   - *Restauration éprouvée* : une restauration d'essai de `medidoc-dev` depuis la sauvegarde Velero chiffrée a réussi ; le déchiffrement d'un export `age` d'essai a réussi. Procédures dans `vulnerabilites.md` (section « Chiffrement et restauration »).

5. **Fermeture** : `ECA-3602` et `ECA-3603` passent en `clos`, preuve `ms-preuves` = politique sur `main`, un essai d'exception échue rejetée par la CI, la configuration de chiffrement de Velero, le journal d'une restauration d'essai.

**Explications**
- **Un délai sans mesure n'existe pas.** La politique n'a de valeur que si on mesure le retard (date de première détection → aujourd'hui) et qu'on le voit. D'où le tableau, pas une note.
- **L'exception doit mourir seule.** Le mode d'échec d'un registre de tableur est l'exception « provisoire » de trois ans. Le mécanisme auto-expirant (date dans Harbor **et** contrôle CI qui rejette l'échéance) retire la décision humaine du chemin critique : à la date, l'image vulnérable est de nouveau bloquée.
- **« Côté serveur ».** Le risque d'ECA-3603 est un administrateur du stockage objet qui lit des données de santé en clair dans une sauvegarde. Chiffrer avant que l'objet n'arrive au stockage (Kopia pour Velero, `age` pour les exports) supprime ce risque ; la clé vit dans OpenBao, séparée du stockage.

**Alternatives**
- Délais plus stricts (critique 48 h) : plus sûr, souvent intenable quand le correctif n'existe pas encore ; MédiSphère assume 7 jours + exception datée obligatoire.
- Chiffrement du compartiment RGW au repos (SSE côté RGW) : protège le disque, **pas** l'administrateur du RGW qui a la clé ; le chiffrement applicatif (`age`, Kopia) protège aussi de lui.
- Trivy Operator comme seule source : pratique dans le cluster, mais ne voit pas les images non déployées ; combiner avec l'analyse de Harbor.

**Pièges classiques**
- Une `cve_allowlist` sans `expires_at` : l'exception est éternelle, l'écart revient.
- Aligner mal les seuils chaîne/registre (M13) : une image avec une critique **non corrigeable** passe la CI puis ne peut plus être tirée ; décider (exception datée) et l'écrire.
- Chiffrer la sauvegarde sans jamais éprouver la restauration : le jour du sinistre, la clé est introuvable ou la phrase est fausse.
- Mesurer le retard depuis la date du jour de l'exception au lieu de la première détection : on masque le retard réel.

**En production chez MédiSphère**
Le respect des délais devient un SLO (« 95 % des critiques traitées dans le délai »), présenté à la revue sécurité et à l'auditeur ; la clé de chiffrement des sauvegardes est tournée annuellement (et on garde l'ancienne le temps de la rétention des anciennes sauvegardes) ; le tableau de vulnérabilités est projeté à la revue hebdomadaire de la plateforme.

---

## Points non testés en conditions réelles (phase 3)

- Collecte Alloy des événements **Keycloak, GitLab, FreeIPA** : formats/chemins selon les versions du M22/M24 ; relus, non exécutés sur une plateforme F6.
- Champ exact du secret de dépôt **Kopia** chiffré de Velero 1.18 : à confirmer sur le lab.
- `expires_at` de la `cve_allowlist` de **Harbor 2.15** : comportement (l'entrée cesse-t-elle d'être appliquée exactement à la date ?) à confirmer sur le lab ; le contrôle CI reste le filet.
- Bascule `GOVERNANCE` → `COMPLIANCE` du compartiment d'archive : éprouvée sur un compartiment jetable seulement.
