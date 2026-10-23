# Final F6 — Phase 1 : Préparer l'audit — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence : d'autres sont valables, jugées sur les mêmes critères.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `ms-preuves` : `bash -n`, `shellcheck -x`, et ses 29 tests ([`tests/ms-preuves/lancer.sh`](fichiers/F6-S02/outils/tests/ms-preuves/lancer.sh)) **verts** avec de faux `aws`, `cosign` et `yq` : collecte (succès, échec, collecteur absent, secret refusé et effacé, secret sur la sortie d'erreur effacé du journal), manifeste, refus de re-signer, refus de déposer sans verrou / sans rétention par défaut / objets sans rétention / deux fois, dépôt, vérification d'un lot local et d'un lot du compartiment, détection d'une preuve modifiée, d'un fichier ajouté et d'un manifeste réécrit ;
- `ms-revue-acces` : `bash -n`, `shellcheck -x`, 13 tests verts ([`tests/ms-revue-acces/lancer.sh`](fichiers/F6-S03/outils/tests/ms-revue-acces/lancer.sh)) avec de faux `ldapsearch`, `kubectl` et `yq` ;
- collecteurs, `rgw-preuves.sh`, `preuves-pare-feu` : `shellcheck` ; la SoA de référence passe le contrôle de complétude du check (93 mesures) et le contrôle échoue bien sur une SoA privée d'une ligne ou d'une justification.

**Fichiers** : `fichiers/F6-S01/` (documents), `fichiers/F6-S02/` et `fichiers/F6-S03/`, rangés comme les dépôts : `medisphere/…` = `plateforme/medisphere`, `outils/…` = `plateforme/outils`, `ceph/…`, `secrets/…`, `ansible/…`. Les `*.extrait-*` se fusionnent dans le fichier existant.

---

### F6-S01 — Périmètre, exigences et déclaration d'applicabilité

**Solution**

Documents de référence : [`perimetre.md`](fichiers/F6-S01/medisphere/docs/conformite/perimetre.md) et [`soa.md`](fichiers/F6-S01/medisphere/docs/conformite/soa.md) (SoA complète : 93 mesures, 92 applicables, 1 exclue).

Les décisions qui comptent, et pourquoi :

1. **MédiSphère est hébergeur** parce qu'elle héberge les données **de ses clients**, responsables de traitement. Un éditeur qui n'hébergerait que ses propres données n'aurait pas besoin de la certification ; ici, chaque cabinet confie les données de ses patients.
2. **Activité 1 : non exercée.** DataCampus fournit le bâtiment, l'énergie, le froid, l'accès physique : il est certifié HDS pour l'activité 1. MédiSphère ne la revendique pas (elle ne la fait pas), mais elle doit **le prouver** (certificat en vigueur, contrat) et **suivre** ce fournisseur (5.19 à 5.22). Dire « exercée » serait faux ; l'oublier serait laisser un trou dans la chaîne.
3. **Activités 2 à 6 : exercées**, chacune reliée à des outils et à des preuves. L'activité 6 (sauvegarde externalisée) est souvent oubliée : PBS sur `hp01` à PAR2, Velero et CloudNativePG vers `s3-01` puis `s3-02`, c'est bien de la sauvegarde de données de santé faite par MédiSphère.
4. **Périmètre du SMSI** : la plateforme et les applications hébergées, **pas** le SI interne (aucune donnée de santé, autre prestataire). Les postes de travail sortent du périmètre, mais **leurs accès** y restent (8.1, 8.5, 6.7) : c'est par là qu'un attaquant arriverait.
5. **Mesures physiques applicables** même avec un colocataire : 7.1 à 7.5 et 7.11 sont mises en œuvre par DataCampus (contrat, certificat), 7.8, 7.10, 7.13, 7.14 par MédiSphère (ses baies, ses disques). Une mesure assurée par un fournisseur reste **applicable** ; sa mise en œuvre passe par 5.19 à 5.22.
6. **Une seule exclusion, discutable et dite comme telle** : 8.23 (filtrage web), parce qu'aucun système du périmètre ne navigue et que la sortie Internet des serveurs est une liste fermée (8.20, 8.22). La SoA note elle-même la question qu'Hélène posera (`adm01` sort-il librement ?). Si la réponse est oui, l'exclusion tombe — et c'est très bien de le découvrir maintenant (voir S06, question 2).
7. **Exigences HDS** traitées à part, parce qu'elles **s'ajoutent** à ISO : localisation dans l'EEE, transparence et cartographie publiée des transferts, contrat d'hébergement, information du client en cas d'incident, réversibilité, traçabilité des accès, sauvegarde. Trois d'entre elles renvoient déjà à des écarts que l'audit formalisera (ECA-3601, 3603, 3605, 3606).
8. **Mesures fragiles** relevées pour la suite (travail demandé n° 3) : 5.18 (revue des accès jamais faite), 5.24 à 5.28 (réponse à incident jamais testée, aucune collecte de preuves forensiques), 5.33 et 8.15 (journaux d'audit centralisés mais modifiables par ceux qu'ils tracent), 8.8 (pas de délai de traitement des vulnérabilités), 8.13 (sauvegardes en clair côté serveur), 5.23 et la transparence HDS (fournisseurs jamais revus sous l'angle des transferts). C'est, à peu de chose près, la liste d'Hélène en S07 : un auditeur interne qui connaît sa SoA voit venir l'audit.

**Explications**

La SoA est le **contrat** du SMSI : pour chaque mesure, l'organisation s'engage (ou explique pourquoi elle ne s'engage pas) et dit comment elle le prouve. L'auditeur part de la SoA et tire au hasard : « 8.13, montrez-moi ». Une ligne générique (« des sauvegardes sont faites ») le renvoie chercher ; une ligne précise (« PBS, Velero, CNPG, preuve P-SAV-01 ») le mène à la preuve. La colonne « preuve » est ce qui relie S01 à S02.

Le périmètre, lui, borne ce que l'auditeur a le droit de regarder et ce que le certificat couvre. Un périmètre trop large est indéfendable ; un périmètre trop étroit est inutile aux clients (s'il exclut la sauvegarde, le client n'est pas couvert).

**Alternatives**
- Exercer l'activité 1 (salles en propre) : possible pour une grande organisation, lourd (sécurité physique, énergie, maintenance) ; le recours à un colocataire certifié est la norme pour un acteur de la taille de MédiSphère.
- SoA dans un outil de GRC (gestion des risques et de la conformité) plutôt que dans Git : meilleur pour les liens entre risques, mesures et preuves ; Git a l'avantage de l'historique relu et des preuves de date.
- Aucune exclusion : défendable aussi (8.23 appliquée par la liste fermée de la bordure, et un filtrage DNS sur les postes d'administration).

**Pièges classiques**
- Déclarer « non applicables » les mesures physiques parce qu'un colocataire existe.
- Revendiquer les six activités « pour être tranquille » : l'organisme certificateur demandera les preuves de l'activité 1.
- Une SoA de 93 lignes « Oui — politique en place » : aucune mise en œuvre vérifiable.
- Oublier que le SI interne, hors périmètre, peut **recevoir** des données de santé par la bande (courriels, tickets) : c'est un des sujets de S07.
- Confondre ISO/IEC 27001:2013 (114 mesures) et 2022 (93) : la transition est terminée depuis le 31 octobre 2025.

**En production chez MédiSphère**

La SoA est revue à chaque changement de périmètre et à la revue de direction ; chaque ligne porte un propriétaire ; un job de CI vérifie que chaque preuve citée (`P-…`) existe dans le catalogue et qu'un lot récent la contient.

---

### F6-S02 — Les preuves se collectent seules

**Solution** (une solution de référence ; ce `LIBRE` s'évalue sur la chaîne obtenue et ses garanties)

*1. Le compartiment.* [`ceph/outils/rgw-preuves.sh`](fichiers/F6-S02/ceph/outils/rgw-preuves.sh) (`plateforme/ceph`), même construction que `rgw-compartiment.sh` du F2-S08 :

```
admin@adm01:~$ bao login -method=oidc
admin@adm01:~/src/ceph$ outils/rgw-preuves.sh creer
utilisateur RGW preuves créé ; clés rangées dans kv/plateforme/preuves/rgw-ecriture
utilisateur RGW preuves-lecture créé ; clés rangées dans kv/plateforme/preuves/rgw-lecture
compartiment preuves-conformite créé avec verrouillage d'objets
rétention par défaut : GOVERNANCE 1 jour (phase d'essai)
politique de lecture posée pour preuves-lecture
{"ObjectLockConfiguration":{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":1}}}}
{"Status":"Enabled", …}
```

- `create-bucket --object-lock-enabled-for-bucket` envoie l'en-tête `x-amz-bucket-object-lock-enabled` ; RGW active alors le versionnage, qui ne peut plus être suspendu. Sur un compartiment créé **sans** verrou, RGW 20.2 accepte `put-object-lock-configuration` seulement si le versionnage est déjà actif (sinon `409 InvalidBucketState`, code de `RGWPutBucketObjectLock` dans `rgw_op.cc` de la v20.2.0) ; on le demande quand même à la création, pour qu'aucun objet n'y ait jamais existé sans protection ([doc Ceph](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/)).
- Deux utilisateurs RGW : `preuves` (propriétaire, écriture, quota 20 Go, un seul compartiment) et `preuves-lecture` (aucun compartiment à lui, lecture par la **politique de compartiment** : objets, versions, rétentions, configuration du verrou).
- Fichier des checks, sans afficher les clés :
  ```
  admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/s3-preuves-conformite-lecture.env
  admin@adm01:~$ bao kv get -format=json -mount=kv plateforme/preuves/rgw-lecture \
      | jq -r '.data.data | "AWS_ACCESS_KEY_ID=\(.AWS_ACCESS_KEY_ID)\nAWS_SECRET_ACCESS_KEY=\(.AWS_SECRET_ACCESS_KEY)"' \
      > ~/.config/workbook/s3-preuves-conformite-lecture.env
  ```
  Même commande, depuis `kv/plateforme/preuves/rgw-ecriture`, pour `~/.config/workbook/s3-preuves-conformite-depot.env` (identité de dépôt du kit forensique, S10-S12) : elle **écrit**, elle ne doit jamais servir aux checks.

*2. Essais en GOVERNANCE* (rétention d'un jour), avec l'identité d'écriture chargée dans un sous-shell :

```
admin@adm01:~$ echo essai > /tmp/essai.txt
admin@adm01:~$ aws --endpoint-url https://rgw.par1.medisphere.internal s3api put-object --bucket preuves-conformite \
    --key essais/essai.txt --body /tmp/essai.txt --content-md5 "$(openssl dgst -md5 -binary /tmp/essai.txt | openssl base64)"
{ "ETag": "…", "VersionId": "<V1>" }
admin@adm01:~$ aws … s3api get-object-retention --bucket preuves-conformite --key essais/essai.txt --version-id <V1>
{ "Retention": { "Mode": "GOVERNANCE", "RetainUntilDate": "…" } }
admin@adm01:~$ aws … s3api delete-object --bucket preuves-conformite --key essais/essai.txt --version-id <V1>
An error occurred (AccessDenied) when calling the DeleteObject operation …
admin@adm01:~$ aws … s3api delete-object --bucket preuves-conformite --key essais/essai.txt
{ "DeleteMarker": true, "VersionId": "<M1>" }          # un marqueur : la version verrouillée reste
admin@adm01:~$ aws … s3api list-object-versions --bucket preuves-conformite --prefix essais/
admin@adm01:~$ aws … s3api delete-object --bucket preuves-conformite --key essais/essai.txt --version-id <V1> --bypass-governance-retention
```

Trois enseignements à écrire dans `preuves.md` : une suppression **sans** version ne détruit rien (marqueur de suppression) ; supprimer une version verrouillée est refusé ; en `GOVERNANCE`, une identité qui a le droit de **contournement** (le propriétaire du compartiment, ici) peut le faire avec l'en-tête de contournement — d'où le passage en `COMPLIANCE`.

*3. La clé de signature et le rôle du pipeline.* [`secrets/tofu/preuves.tf`](fichiers/F6-S02/secrets/tofu/preuves.tf) et [`politiques/preuves-collecte.hcl`](fichiers/F6-S02/secrets/politiques/preuves-collecte.hcl) (`plateforme/secrets`) : clé `transit/preuves-conformite` (ECDSA P-256, non exportable, non supprimable), politique `preuves-collecte` (signer, lire `kv/plateforme/preuves/*`, rien d'autre), rôle `jwt` **`ci-preuves`** lié à `plateforme/outils`, `main` protégée, **runner01** (identifiant numérique, comme `ci-signature` au M25). Identités de lecture des collecteurs rangées en `kv/plateforme/preuves/lecture` (une clé par variable : `IPA_BIND_DN`, `KEYCLOAK_CLIENT_ID`, `GITLAB_TOKEN`…), kubeconfig de lecture en `kv/plateforme/preuves/kubernetes`, clé SSH de la bordure en `kv/plateforme/preuves/ssh-bordure`.

```
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan -var runner_socle_id=<ID-RUNNER01> && tofu -chdir=tofu apply …
admin@adm01:~/medisphere$ cosign public-key --key hashivault://preuves-conformite > docs/conformite/cle-preuves.pub
```

(La même clé publique est copiée dans `plateforme/outils`, `preuves/preuves-conformite.pub`, défaut de `ms-preuves verifier`.)

*4. L'outil.* [`outils/bin/ms-preuves`](fichiers/F6-S02/outils/bin/ms-preuves), son [catalogue](fichiers/F6-S02/outils/preuves/catalogue.yaml) (15 preuves) et ses [collecteurs](fichiers/F6-S02/outils/preuves/collecteurs/) (+ [`_commun.sh`](fichiers/F6-S02/outils/preuves/collecteurs/_commun.sh)). Sous-commandes `collecter`, `signer`, `deposer`, `executer`, `verifier`, `lister`. Points de conception :
- un **lot** = un dossier : `preuves/`, `journal/`, `lot.json` (horodatage UTC, hôte, projet, commit, pipeline, empreinte du catalogue, statut de chaque preuve), `MANIFESTE.sha256`, `MANIFESTE.sha256.sigstore.json` ;
- un collecteur qui échoue n'arrête pas le lot : statut `echec`, lot `partiel`, dépôt quand même, code 1 à la fin (le pipeline est rouge, la preuve de l'échec est conservée) ;
- **garde-fou** : une sortie qui ressemble à un secret (clé privée, `"password": "…"`, URL à identifiants, clés AWS, jetons GitLab ou OpenBao) est **vidée** et marquée `refusee` avant toute empreinte : on ne dépose jamais un secret dans un compartiment qu'on ne pourra plus vider ;
- `deposer` vérifie le verrou **avant** (verrou activé et rétention par défaut, sinon refus code 3), envoie `Content-MD5` (exigé par S3 pour un objet soumis à rétention), contrôle **après** chaque objet qu'il porte un mode et une échéance, envoie le bundle **en dernier**, refuse d'écraser un lot existant ;
- `verifier` recalcule les empreintes, refuse un fichier hors manifeste, vérifie la signature (`cosign verify-blob --insecure-ignore-tlog=true`, configuration « sans service » du M25) et, pour un lot du compartiment, la rétention en cours de chaque objet.

Collecteurs ajoutés côté infrastructure : rôle [`preuves_bordure`](fichiers/F6-S02/ansible/roles/preuves_bordure/) (compte `preuves` des passerelles, commande **forcée** `preuves-pare-feu`, sudo limité, connexion depuis `runner01` et `adm01` seulement — même construction que `sonde_reseau` du M07-E29), outils de `runner01` ([extrait](fichiers/F6-S02/ansible/inventories/lab/host_vars/runner01/outils_supply_chain.yml.extrait-F6)) :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --tags preuves_bordure --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --tags preuves_bordure
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-supply-chain.yml -l runner01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-openbao.yml -l runner01
```

(Ajoute le rôle au jeu des routeurs avec l'étiquette `preuves_bordure`, et `aws`, `ldap-utils`, `kubectl`, `yq` aux outils de `runner01`, par les rôles d'outillage d'`adm01`.)

*5. Tests et CI.* [`tests/ms-preuves/`](fichiers/F6-S02/outils/tests/ms-preuves/) et [extrait de `.gitlab-ci.yml`](fichiers/F6-S02/outils/.gitlab-ci.extrait-F6-S02.yml) : `test:ms-preuves`, `preuves:collecte` (une seule connexion au coffre par le jeton d'identité du job, aucun secret en variable CI, `resource_group` pour ne jamais lancer deux collectes en même temps), `preuves:verification` (le dernier lot se vérifie avec l'identité de **lecture**). Planifications par l'API (ou l'interface) de GitLab :

```
admin@adm01:~$ GL=https://git01.par1.medisphere.internal; P=plateforme%2Foutils
admin@adm01:~$ curl -sf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(cat ~/.config/workbook/gitlab-admin.token)") \
    --data-urlencode description=preuves-quotidiennes --data-urlencode ref=main \
    --data-urlencode cron='5 2 * * *' --data-urlencode cron_timezone=Europe/Paris \
    "$GL/api/v4/projects/$P/pipeline_schedules" | jq .id
admin@adm01:~$ curl -sf -H @<(…) --data-urlencode key=TACHE --data-urlencode value=preuves \
    "$GL/api/v4/projects/$P/pipeline_schedules/<ID>/variables"
admin@adm01:~$ curl -sf -H @<(…) --data-urlencode key=FREQUENCE --data-urlencode value=quotidienne \
    "$GL/api/v4/projects/$P/pipeline_schedules/<ID>/variables"
```

Puis `preuves-hebdomadaires` (`35 5 * * 0`, `FREQUENCE=hebdomadaire`), `preuves-mensuelles` (`5 6 1 * *`), `preuves-verification` (`35 7 * * *`, `TACHE=preuves-verification`). Premier lancement à la main (« Run pipeline » de la planification) et lecture :

```
admin@adm01:~/src/outils$ set -a; . ~/.config/workbook/s3-preuves-conformite-lecture.env; set +a
admin@adm01:~/src/outils$ bin/ms-preuves lister
20261105T010512Z-quotidienne	s3://preuves-conformite/lots/2026/11/05/20261105T010512Z-quotidienne/
admin@adm01:~/src/outils$ bin/ms-preuves verifier s3://preuves-conformite/lots/2026/11/05/20261105T010512Z-quotidienne/
… INFO empreintes : conformes (31 fichier(s))
… INFO signature : vérifiée (clé …/preuves-conformite.pub)
… INFO rétention : en cours sur tous les objets du lot
lot 20261105T010512Z-quotidienne — complet — 10 preuve(s) ok, 0 autre(s) — collecté le 2026-11-05T01:05:12Z
```

Relis **chaque** preuve du premier lot avant la bascule : rien de sensible (Keycloak : aucun champ `secret` ; RBAC : des noms ; bordure : des règles), sortie triée et stable.

*6. Le catalogue.* [`preuves.md`](fichiers/F6-S02/medisphere/docs/conformite/preuves.md) : principe, stockage et rétention, **limites écrites** (l'administrateur de Ceph ; la date de confiance), les 15 preuves automatiques et les preuves documentaires, la procédure de vérification pour l'auditrice, la règle d'ajout.

*7. La bascule en COMPLIANCE*, une fois les lots d'essai relus :

```
admin@adm01:~/src/ceph$ outils/rgw-preuves.sh retention COMPLIANCE 400
⚠️  COMPLIANCE 400 jours : chaque objet écrit à partir de maintenant sera INDESTRUCTIBLE pendant 400 jours, …
Tape « COMPLIANCE 400 » pour confirmer : COMPLIANCE 400
rétention par défaut : COMPLIANCE 400 jours
```

Contrôle au lot suivant : `get-object-retention` d'un objet du lot → `"Mode": "COMPLIANCE"` ; `delete-object --version-id … --bypass-governance-retention` avec l'identité propriétaire → refusé. Les lots d'essai écrits en `GOVERNANCE` 1 jour restent lisibles et deviennent supprimables le lendemain (on les garde : ce sont aussi des preuves, de la mise en place).

**Explications**
- **Trois garanties distinctes.** *Qui* : la signature par une clé née dans le coffre, utilisable par un seul rôle (projet, branche protégée, runner). *Quoi* : les empreintes du manifeste. *Quand, et pas retouché depuis* : le dépôt dans un compartiment verrouillé — la date de dernière modification et l'échéance sont posées par le **serveur**, et la version ne peut plus changer. Une signature sans journal de transparence ne date rien : c'est le verrou qui date.
- **`GOVERNANCE` et `COMPLIANCE`.** Les deux interdisent la suppression d'une version et le raccourcissement de la rétention ; `GOVERNANCE` laisse une porte (le droit de contournement `s3:BypassGovernanceRetention`, que RGW 20.2 rattache à la permission d'écriture de la liste de contrôle d'accès : le propriétaire l'a de fait), `COMPLIANCE` n'en laisse aucune. D'où l'ordre : essayer en `GOVERNANCE`, basculer quand on est sûr.
- **Versionnage obligatoire** : une écriture sur une clé existante crée une version ; une suppression sans version crée un marqueur. Rien ne remplace une preuve déjà déposée.
- **Lecture seule partout** : les collecteurs n'ont que des identités de lecture ; l'identité d'écriture S3 ne sert qu'à `deposer`, et le verrou l'empêche de détruire.

**Alternatives**
- **Mise en suspens légale** (*legal hold*) plutôt qu'une rétention : sans échéance, levée explicitement ; utile pour un incident (phase 4), pas pour une collecte continue.
- **Horodatage RFC 3161** (autorité d'horodatage dans la configuration de signature de Cosign) ou journal de transparence interne (Rekor) : date de confiance indépendante du stockage ; un service de plus.
- **Ancrage dans Git** : committer chaque jour l'empreinte du manifeste dans un dépôt relu (et poussé en miroir à PAR2) : simple, mais l'historique Git d'un administrateur de GitLab n'est pas inaltérable.
- **WORM matériel ou bande** : le classique des archives légales ; hors de portée du lab.
- **Kyverno, OpenSCAP, Velero exposent déjà des rapports** : la preuve est la photographie datée et signée de ces rapports, pas un nouveau contrôle.

**Pièges classiques**
- Créer le compartiment sans verrou, « on l'activera après » : les objets écrits avant l'activation n'ont aucune rétention, et un compartiment non versionné refuse l'activation (RGW 20.2) ; créer `preuves-conformite` verrouillé dès le départ.
- Passer en `COMPLIANCE` avant d'avoir relu le contenu : un secret ou une donnée de santé déposés y restent jusqu'à l'échéance.
- Oublier `Content-MD5` : S3 l'exige pour un objet soumis à rétention ; selon la version de RGW, le dépôt échoue ou non (on l'envoie toujours).
- Faire confiance au verrou sans **vérifier** chaque objet après écriture : un compartiment mal réglé accepte des objets sans protection, en silence.
- Des preuves dont l'ordre change d'un jour à l'autre (sortie non triée) : deux états identiques ont deux empreintes différentes, les différences réelles se noient.
- Mettre les identités des collecteurs en variables CI masquées : elles se lisent dans un job modifié par une branche ; le rôle `jwt` lié à `main` protégée l'empêche.
- Réutiliser la clé `cosign-medisphere` : la clé publique remise à l'auditeur vérifierait aussi nos images, et une rotation de l'une casserait l'autre.
- Croire qu'une preuve non collectée « n'existe pas » : un lot partiel déposé **est** la preuve qu'on a essayé et échoué.

**En production chez MédiSphère**

Réplication de `preuves-conformite` vers `s3-02` (PAR2) avec la même rétention ; une autorité d'horodatage ; administration de Ceph séparée de la Plateforme (deux équipes, deux identités) ; métrique « âge du dernier lot » et alerte à 36 h ; l'identité `preuves-lecture` remise à l'organisme certificateur pour la durée de l'audit et révoquée ensuite.

---

### F6-S03 — La revue des accès

**Solution** (une solution de référence)

*1. Identités de revue.* Celles des checks suffisent pour l'annuaire, Keycloak (`view-users`), Kubernetes, OpenBao (à condition que la politique de lecture des métadonnées autorise `LIST` sur `auth/approle/role` et `auth/gitlab/role` : ajoute-le à la politique `wb-checks` ou crée une politique `revue-acces`), mais pas pour :
- **Grafana** : la liste des utilisateurs de l'organisation (`/api/org/users`) et des comptes de service demande plus que le rôle Viewer : compte de service `revue-acces` dédié (rôle d'organisation **Admin**, jeton de 30 jours, déclaré au registre comme risque accepté : Grafana n'a pas de rôle « lecture des utilisateurs » dans l'édition libre) ;
- **Harbor** : un robot **système** avec les seules permissions `user` (list, read) et `robot` (list, read) — Harbor 2.15 les propose aux robots système (`src/common/rbac/const.go` de la v2.15.4, fournisseur « sans limite ») ;
- **GitLab** : un jeton `read_api` d'**administrateur** (l'état des comptes et la dernière activité ne sont visibles qu'ainsi) ;
- **Proxmox** : jeton d'API en rôle `PVEAuditor`.

Toutes rangées dans `kv/plateforme/preuves/lecture` (celles de `ms-preuves`), lues par le rôle `ci-preuves`.

*2. L'outil.* [`outils/bin/ms-revue-acces`](fichiers/F6-S03/outils/bin/ms-revue-acces), la liste des [comptes déclarés](fichiers/F6-S03/outils/revue-acces/comptes-declares.yaml), les [tests](fichiers/F6-S03/outils/tests/ms-revue-acces/) et l'[extrait de CI](fichiers/F6-S03/outils/.gitlab-ci.extrait-F6-S03.yml) (job mensuel `revue:acces`, brouillon en artefact). Classement : `personne` (actif dans l'annuaire), `declare` (non personnel déclaré : technique, bris de glace, groupe de l'annuaire, banc de formation), `orphelin` (personne désactivée, expirée ou absente de l'annuaire, encore active ailleurs ; ou désactivée **encore membre de groupes**), `a-justifier` (inconnu). Un système sans identité est `NON-VERIFIE` et fait échouer la commande.

```
admin@adm01:~/src/outils$ install -m 600 /dev/null ~/.config/ms-outils/revue-acces.env && "${EDITOR:-vi}" ~/.config/ms-outils/revue-acces.env
admin@adm01:~/src/outils$ bin/ms-revue-acces > /tmp/revue.md ; echo $?
1
admin@adm01:~/src/outils$ bin/ms-revue-acces --json | jq '.resume, (.a_traiter[] | [.systeme, .compte, .statut, .motif] | @tsv)'
```

*3. La revue.* [`revue-acces/2026-11.md`](fichiers/F6-S03/medisphere/docs/conformite/revue-acces/2026-11.md) : méthode et identités, résultat outillé, **une ligne par compte à traiter** avec constat, décision, responsable, échéance, réalisation ; revue des droits d'administration système par système ; ce qui n'est pas couvert (bordure, PBS, NetBox, royaume `master`) ; périodicité. Les lignes du document de référence sont celles d'un lab type ; les tiennes dépendent de ton parcours, mais tu dois y trouver au moins les traces d'AxiomDev que le départ n'a pas vues.

*4. Ce qu'on trouve typiquement, et comment on le corrige* :

| Constat | Correction (bon chemin) |
|---|---|
| Liaison RBAC vers `oidc:ext-axiomdev` ou une personne d'AxiomDev, posée à la main hors du rendu de l'équipe en code | `kubectl delete rolebinding …` (objet hors dépôt), puis vérifier que la politique Kyverno du F2-S11 l'aurait refusée aujourd'hui (dry-run) |
| Ligne `g, ext-axiomdev, …` dans la politique RBAC d'Argo CD | MR sur les valeurs d'Argo CD (`argocd-rbac-cm` est rendu par le chart) |
| Jeton d'accès **de projet** créé par un prestataire : il survit au blocage de la personne | `DELETE /projects/:id/access_tokens/:token_id` (API GitLab) ; ajout de ce cas à `depart-externe.sh` |
| Robot Harbor sans échéance créé pour un essai | suppression (interface ou API Harbor) |
| Jeton d'API Proxmox sans expiration | nouveau jeton expirant, ancien supprimé (`pveum user token remove`) |
| Administrateur temporaire du royaume `master` (amorçage du M24) | suppression dans la console d'administration de `master` |
| Compte de service à `cluster-admin` laissé par un essai | retrait de la liaison |
| Désactivé dans l'annuaire mais encore membre de groupes | retrait des appartenances par l'équipe en code (MR), pour que la revue suivante soit propre |

*5. Preuve et périodicité.* L'état brut est déposé par `ms-preuves` (P-IAM-06, collecteur [`revue-acces`](fichiers/F6-S02/outils/preuves/collecteurs/revue-acces), mensuel) ; la décision est la MR du document, approuvée par Sophie et Claire. Revue mensuelle pour les comptes à privilèges et les prestataires, trimestrielle pour tous.

**Explications**
- **La source de vérité, c'est l'annuaire** : une personne présente y est active ; tout le reste se rattache à elle (fédération) ou est **déclaré**. Le fichier des comptes déclarés transforme les exceptions en décisions relues, avec un propriétaire.
- **Un départ coupe ce qui est au nom de la personne**, pas ce qu'elle a **créé** : jetons de projet, robots, liaisons ou lignes de politique ajoutées à la main. C'est ce que la revue attrape et que l'automatisation du départ ne voyait pas.
- **Reproductible** : même identités, même liste déclarée, sortie triée → même résultat. La revue suivante se compare à celle-ci ligne à ligne.

**Alternatives**
- Une solution de gouvernance des identités (midPoint, par exemple) : connecteurs, campagnes de certification, workflows d'approbation ; justifiée au-delà de quelques centaines de comptes ou de dizaines d'applications.
- Tout centraliser dans Keycloak (comptes locaux interdits partout, SSO obligatoire) : réduit la revue aux groupes, mais les comptes techniques et les bris de glace restent.
- Tableur rempli à la main : rapide la première fois, impossible à refaire à l'identique, aucune preuve de l'état.

**Pièges classiques**
- Supprimer les comptes des partants : l'historique (commits, MR, journaux) perd son auteur.
- « Nettoyer » les bris de glace parce qu'ils ne sont pas nominatifs.
- Ignorer les groupes : un groupe `ext-axiomdev` encore cité donne des droits au premier qui y sera ajouté.
- Faire la revue avec des identités d'administration en écriture « parce que c'est plus simple ».
- Une identité de revue trop faible qui ne voit pas tout, sans le dire : la revue paraît propre.
- Oublier les identités du banc (`wb-*`) : elles sortent « à justifier » ; on les déclare, on ne les supprime pas (les checks en dépendent).

**En production chez MédiSphère**

Campagne mensuelle déclenchée par le pipeline, tickets `SEC-` ouverts automatiquement pour chaque ligne « à traiter », relance à J+7, escalade à Claire à J+10 ; la revue trimestrielle des droits est présentée en revue de direction ; la revue des prestataires est faite à chaque fin de contrat **et** le mois suivant.

---

## Points non testés en conditions réelles (phase 1)

Signale tes retours : ils corrigent le workbook.

- **RGW et Object Lock** (Ceph 20.2) : vérifié dans le **code source** de la v20.2.0 (pas sur un lab) : actions `s3:BypassGovernanceRetention`, `s3:GetObjectRetention`, `s3:GetObjectLegalHold`, `s3:GetBucketObjectLockConfiguration`, `s3:ListBucketVersions` reconnues dans une politique de compartiment ; contournement de `GOVERNANCE` rattaché à la permission d'écriture (le propriétaire l'a) ; `max_buckets` négatif = création de compartiment refusée ; les en-têtes de rétention de `head-object` exigent `s3:GetObjectRetention`. À constater sur le lab : exigence de `Content-MD5` au dépôt, format de principal `arn:aws:iam:::user/preuves-lecture`.
- **`radosgw-admin`** face à un objet en `COMPLIANCE` (`object rm`, `bucket rm --purge-objects`) : la limite écrite dans `preuves.md` suppose qu'un administrateur de Ceph peut détruire ; à constater sur un compartiment jetable, jamais sur `preuves-conformite`.
- **Cosign 3 `sign-blob` / `verify-blob`** avec `hashivault://preuves-conformite` et la configuration de signature sans service : mêmes options qu'au M25-E20 (`--signing-config`, `--bundle`, `--insecure-ignore-tlog=true`), non rejouées avec une clé de preuves.
- **Collecteurs** : champs exacts renvoyés par les API (Keycloak 26.8 `users?briefRepresentation=false` et `federationLink`, Harbor `scan_overview`, GitLab `two_factor_enabled` et `last_activity_on` pour un jeton d'administrateur, Proxmox `access/users?full=1` et `tokens`), non vérifiés sur le lab ; lecture de `nsAccountLock` et `krbPrincipalExpiration` par le compte système de lecture (ACI par défaut de FreeIPA).
- **`preuves-pare-feu`** : la comparaison configuration persistée ↔ règles actives recharge `/etc/nftables.conf` dans un espace de noms réseau jetable (`unshare -n`) ; une règle qui cite une interface par **index** échouerait. La section « écart » dit alors qu'elle n'a pas pu comparer.
- **Identités de revue** : rôle minimal d'un compte de service Grafana pour lister les utilisateurs de l'organisation ; robot **système** Harbor à permissions `user`/`robot` en lecture : présentes dans le code de la v2.15.4, interface et comportement de `GET /users` avec ce robot à constater sur le lab.
- **Durées** des collectes (hebdomadaire ≈ 10 min estimées) et taille d'un lot (quelques Mo) : celles d'un lab de référence imaginé.
