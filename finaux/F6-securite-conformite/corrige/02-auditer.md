# Final F6 — Phase 2 : Auditer — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- panne [`break-S04.sh`](pannes/break-S04.sh) : `bash -n`, `shellcheck -x` ; logique du tirage rejouée avec des candidats simulés (deux candidats écartés, quatre posés et constatés, annulation qui vide l'état) ;
- checks S04, S05, S07 : `shellcheck -x` ; filtres `jq` (silences longs ou de sécurité, ConfigMaps à mot de passe, liaisons `cluster-admin`) rejoués sur des objets de test ; le check S07 passe sur les documents de référence.

**Fichiers** : `fichiers/F6-S04/` (fiche d'écart d'exemple), `fichiers/F6-S05/` (rapport d'audit technique), `fichiers/F6-S07/` (rapport d'écarts, fiches ECA-3601 à 3606, plan de remédiation, cartographie des transferts).

---

### F6-S04 — Panne : les écarts cachés de l'audit à blanc

**Démarche de diagnostic**

*Symptômes → hypothèses.* Hélène dit **combien** d'écarts, et **où** elle a regardé (accès, preuves, dérogations, sauvegardes, bordure, supervision). Elle ne dit pas quoi. La seule méthode qui passe à l'échelle : **comparer ce qui est déclaré à ce qui est observé**, domaine par domaine, en commençant par la photo d'avant que tu as déjà — les lots de preuves quotidiens.

*1. Comparer deux lots* (la veille de l'audit et aujourd'hui), avec l'identité de lecture :

```
admin@adm01:~/src/outils$ set -a; . ~/.config/workbook/s3-preuves-conformite-lecture.env; set +a
admin@adm01:~/src/outils$ bin/ms-preuves lister --depuis 2026-11-13
admin@adm01:~$ for l in <LOT-AVANT> <LOT-APRES>; do
    aws --endpoint-url https://rgw.par1.medisphere.internal s3 cp --recursive --only-show-errors \
      "s3://preuves-conformite/lots/<AAAA/MM/JJ>/$l/" "/tmp/lots/$l/"; done
admin@adm01:~$ diff <(jq -S 'del(.collecte_utc, .lot)' /tmp/lots/<LOT-AVANT>/preuves/P-SUP-01.json) \
                    <(jq -S 'del(.collecte_utc, .lot)' /tmp/lots/<LOT-APRES>/preuves/P-SUP-01.json)
```

Même chose pour P-IAM-03 (comptes GitLab), P-IAM-04 (RBAC), P-VUL-02 (dérogations), P-SAV-01 (Velero), P-RES-01 (bordure). Chaque différence est une piste ; certaines dérives ne sont couvertes par **aucune** preuve (une ConfigMap, par exemple) : il faut alors aller voir.

*2. Observer chaque domaine*, puis pour chaque écart trouvé : **quand**, **qui**, **correction**, **prévention**. Le lot tiré dépend de l'injection ; chaque candidat est traité ci-dessous.

> Dans le lab, l'« auteur » visible dans les journaux d'audit est l'identité d'administration qui a lancé `lab/bin/break` (et le silence porte un `createdBy` purement déclaratif). Note-le comme tel : en vrai, ce serait la personne.

#### Candidat 1 — un compte d'AxiomDev réactivé dans GitLab

1. Observation :
   ```
   admin@adm01:~$ for u in marc.vidal yanis.perrin; do
       curl -sf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(cat ~/.config/workbook/gitlab-checks.token)") \
         "https://git01.par1.medisphere.internal/api/v4/users?username=$u" | jq -r '.[0] | "\(.username) \(.state)"'; done
   marc.vidal blocked
   yanis.perrin active
   ```
   La preuve P-IAM-03 de la veille le montrait `blocked`.
2. Quand et qui : événements d'audit de GitLab (`/var/log/gitlab/gitlab-rails/audit_json.log` sur `git01` ; selon l'édition et la version, le déblocage y figure ou non : à vérifier) ; à défaut, `application_json.log` et l'heure de changement dans les lots quotidiens (encadrement à 24 h).
3. Correction : rebloquer (`POST /users/:id/block`), vérifier qu'aucun jeton personnel n'a été recréé et qu'aucune session n'a été ouverte depuis (dernière connexion `current_sign_in_at`).
4. Cause et prévention : un administrateur GitLab peut débloquer un compte sans passer par l'équipe en code ; aucune alerte ne le voit. Prévention : `ms-verif-equipe ext-axiomdev` (F2-S13) ou `ms-revue-acces` quotidien pour les comptes externes, alerte sur tout compte `@axiomdev.example` `active` ; déblocage réservé à `root` par procédure.

#### Candidat 2 — une règle ouverte à chaud sur la bordure

1. Observation, sur les **deux** passerelles :
   ```
   admin@gw01:~$ sudo nft -a list chain inet filter forward | head
       ip saddr 10.10.99.0/24 ip daddr 10.10.20.12 tcp dport 22 counter packets 0 bytes 0 accept comment "acces-temporaire-infoger" # handle 87
   admin@gw01:~$ sudo grep -c acces-temporaire-infoger /etc/nftables.conf
   0
   ```
   Elle n'est ni dans `/etc/nftables.conf`, ni dans `group_vars/role_routeur/pare_feu.yml`, ni dans la matrice des flux. La section « écart » de P-RES-01 la montre aussi.
2. Quand et qui : `sudo journalctl -t sudo --since …` sur la passerelle (qui a ouvert un shell root, à quelle heure) ; les règles `auditd` du M26-E12 si elles tracent `execve` de `nft`.
3. Correction : la retirer des deux passerelles, par son *handle* :
   ```
   admin@gw01:~$ sudo nft delete rule inet filter forward handle 87
   admin@gw02:~$ sudo nft -a list chain inet filter forward | grep acces-temporaire ; sudo nft delete rule inet filter forward handle <H>
   ```
   ⚠️ Pas de `systemctl restart nftables` sur une passerelle active « pour repartir du fichier » sans fenêtre : le rechargement vide puis recharge tout le jeu de règles (court instant sans filtrage ni NAT, connexions suivies à revalider). Si le flux était légitime : MR sur la matrice, déploiement par le rôle.
4. Prévention : une règle à chaud est invisible au code ; seul un contrôle **ruleset actif ↔ configuration persistée** la voit. `preuves-pare-feu` le fait chaque jour ; en faire une métrique (minuterie + collecteur *textfile*, `medisphere_pare_feu_ecart`) et une alerte.

#### Candidat 3 — une dérogation Kyverno sans échéance, hors registre

1. Observation :
   ```
   admin@adm01:~$ kubectl -n kyverno-exceptions get policyexceptions.policies.kyverno.io \
       -o custom-columns=NOM:.metadata.name,ECHEANCE:.spec.expiresAt,REGISTRE:.metadata.labels.medisphere\\.internal/registre-exceptions
   recette-derogation-temporaire   <none>   <none>
   admin@adm01:~$ kubectl -n kyverno-exceptions get policyexceptions.policies.kyverno.io recette-derogation-temporaire -o yaml
   ```
   Elle exempte **toute** la recette de `exiger-signature-medisphere` : une image non signée y serait admise. Absente de `plateforme/politiques/kyverno/exceptions/` et du registre `exceptions.md`.
2. Quand et qui : le M26-E28 journalise `policies.kyverno.io` au niveau `Request` :
   ```
   {job="kubernetes-audit"} |= `policyexceptions` |= `recette-derogation-temporaire` | json | line_format "{{.verb}} {{.user_username}} {{.stageTimestamp}}"
   ```
   (locataire `audit` de Loki ; adapte les noms de champs à ton pipeline Alloy) ; `managedFields` (gestionnaire `kubectl-client-side-apply`, pas Argo CD).
3. Correction : la supprimer ; si une dérogation est réellement nécessaire, elle passe par une MR dans `plateforme/politiques` avec `expiresAt`, `properties`, l'étiquette du registre et une ligne `EXC-K-…` (RB-261). Vérifier qu'aucun pod non signé n'a été admis entre-temps (rapports de politiques, `kubectl get policyreports -n mediagenda-recette`).
4. Prévention : une politique d'admission sur les `PolicyException` elles-mêmes (échéance obligatoire, 90 jours au plus, étiquette du registre), création réservée à Argo CD (RBAC) ; P-VUL-02 liste les anomalies chaque jour.

#### Candidat 4 — un mot de passe en clair dans une ConfigMap de recette

1. Observation :
   ```
   admin@adm01:~$ kubectl get configmaps -A -o json | jq -r '.items[] | select(.metadata.namespace | test("^(mediagenda|medidoc|medinotif|legacy|medivisio|data)-"))
       | .metadata as $m | (.data // {}) | keys[] | select(test("(?i)(password|secret|token)$")) | "\($m.namespace)/\($m.name) \(.)"'
   mediagenda-recette/mediagenda-parametres-essai DB_PASSWORD
   ```
   La politique `interdire-identifiants-url` (M26-E16) ne voit que les **URL** à identifiants : un mot de passe dans une clé séparée passe. kubescape le signale aussi (contrôle des identifiants dans les fichiers de configuration).
2. Quand et qui : audit de l'API (création de `configmaps`, niveau `Metadata` : qui, quand, sans le contenu).
3. Correction : supprimer la ConfigMap ; **traiter le secret comme compromis** : ici, aucun rôle `mediagenda_essai_charge` n'existe dans la base (`\du` sur le primaire CNPG de recette) — c'est un faux ; s'il avait existé : rotation immédiate, recherche d'usage dans les journaux de PostgreSQL. Un paramètre légitime va dans OpenBao, livré par un `ExternalSecret`.
4. Prévention : compléter la politique d'admission par une règle sur les **noms de clés** (`password`, `secret`, `token`…) des ConfigMaps des espaces applicatifs ; kubescape dans l'analyse hebdomadaire.

#### Candidat 5 — une planification Velero suspendue

1. Observation :
   ```
   admin@adm01:~$ kubectl -n velero get schedules.velero.io -o custom-columns=NOM:.metadata.name,SUSPENDUE:.spec.paused,DERNIERE:.status.lastBackup
   recette-quotidienne   true    2026-11-16T02:15:04Z
   admin@adm01:~$ velero schedule get
   ```
   P-SAV-01 du jour : `suspendue: true`, plus de sauvegarde de la recette depuis la veille.
2. Quand et qui : audit de l'API (`patch` sur `schedules.velero.io`).
3. Correction :
   ```
   admin@adm01:~$ kubectl -n velero patch schedules.velero.io recette-quotidienne --type merge -p '{"spec":{"paused":false}}'
   admin@adm01:~$ velero backup create --from-schedule recette-quotidienne --wait
   ```
   (`velero schedule unpause` fait la même chose.) **Piège** : réappliquer `planifications.yaml` (`kubectl apply`) ne remet **pas** `paused` à faux — le champ n'est pas dans le fichier, `apply` ne touche pas un champ qu'il n'a jamais géré. Écris `paused: false` explicitement dans le fichier versionné si tu veux que l'application le garantisse.
4. Prévention : alerte sur l'âge de la dernière sauvegarde réussie par planification (métrique `velero_backup_last_successful_timestamp` de Velero, étiquette `schedule`), seuil 26 h ; P-SAV-01.

#### Candidat 6 — un compte de service de recette `cluster-admin`

1. Observation :
   ```
   admin@adm01:~$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name == "cluster-admin")
       | "\(.metadata.name)\t\([.subjects[]? | "\(.kind):\(.namespace // "")/\(.name)"] | join(","))"'
   outil-diagnostic-temporaire   ServiceAccount:mediagenda-recette/outil-diagnostic
   ```
   (`ms-revue-acces` le sort « à justifier » ; P-IAM-04 le liste dans `cluster_admin`.)
2. Quand et qui : audit (création de la liaison) ; **usage** : ce compte a-t-il servi ?
   ```
   {job="kubernetes-audit"} |= `system:serviceaccount:mediagenda-recette:outil-diagnostic`
   ```
   Aucun événement : droits posés, jamais utilisés. Un événement : c'est un incident de sécurité (phase 4), pas un écart.
3. Correction : supprimer la liaison et le compte de service.
4. Prévention : politique d'admission qui refuse toute liaison à `cluster-admin` hors d'une liste fermée de sujets ; alerte `AuditLiaisonRoleCluster` (M26-E28) — **si elle n'a pas sonné, regarde le candidat 7**.

#### Candidat 7 — les alertes de sécurité réduites au silence

1. Observation :
   ```
   admin@adm01:~$ amtool --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093 silence query -o extended
   ID  Matchers  Starts At  Ends At  Updated At  Created By  Comment
   …   alertname=~"AlerteFalco|Audit.*"  2026-11-16 22:41  2027-01-15 22:41  …  lucas.martin  Trop de bruit pendant les essais de charge…
   ```
2. Quand et qui : la date est dans le silence ; l'auteur est **déclaratif** (Alertmanager n'authentifie pas `createdBy`) : à recouper avec les accès à l'API (qui joint `10.10.41.61` depuis MGMT ?).
3. Correction : `amtool … silence expire <ID>` ; puis relire ce qui a été tu : alertes `AlerteFalco` et `Audit*` émises pendant le silence (journaux de falcosidekick, ruler de Loki), et décider s'il y a un incident.
4. Prévention : voir la [fiche d'exemple ECA-3611](fichiers/F6-S04/medisphere/docs/conformite/ecarts/ECA-3611-silence-alertes-securite.md) (alerte sur les silences longs ou de sécurité, règle d'usage).

*3. Formaliser.* Une fiche par écart, numérotées dans l'ordre où tu les as trouvés (`ECA-3611`…), statut `clos`, preuve de clôture (le lot du lendemain qui montre l'état sain) ; dans chacune, la ligne « ce qui l'aurait vu en moins de 24 h ». Exemple complet : [`ECA-3611`](fichiers/F6-S04/medisphere/docs/conformite/ecarts/ECA-3611-silence-alertes-securite.md).

**Cause racine commune**

Toutes ces dérives ont le même mécanisme : un geste **hors du chemin du code**, fait par quelqu'un qui en avait le droit, que rien ne compare à l'état déclaré. Les preuves quotidiennes les **enregistraient** déjà (sauf la ConfigMap) ; personne ne les **lisait**. La prévention n'est donc pas « interdire » (les droits d'administration resteront), mais **comparer automatiquement** et alerter : chaque collecteur de S02 peut devenir une règle.

**Pièges classiques**
- Chercher « ce qui a l'air faux » au lieu de comparer méthodiquement : on trouve deux écarts sur quatre.
- Corriger sans dater ni attribuer : Hélène le demande, et c'est ce qui distingue une erreur d'un incident.
- Rejouer le playbook ou réappliquer un manifeste en croyant corriger : `apply` ne retire pas un champ ajouté à la main (`paused`), le rôle de la bordure ne retire pas une règle insérée à chaud tant qu'il ne recharge pas.
- Lancer `--annuler` pour « vérifier » : l'annulation répare à ta place et tu perds l'exercice.
- Oublier de se demander si la dérive a été **exploitée** (le compte a-t-il servi ? le silence a-t-il masqué une vraie alerte ?).

**En production chez MédiSphère**

Chaque preuve quotidienne a sa règle de comparaison (« diff » de lot à lot) qui ouvre un ticket `SEC-` ; les gestes d'administration hors code passent par une fiche de changement urgente, sinon ils sont des écarts.

---

### F6-S05 — L'audit technique outillé

**Solution** (une solution de référence ; le rapport type est [`audit-technique.md`](fichiers/F6-S05/medisphere/docs/conformite/audit-2026/audit-technique.md))

*1. Plan d'audit* : échantillon d'une VM par rôle et par famille de système, tout le cluster, toutes les images en service, tous les points d'accès SSH ; exclusions dites (`pve01`, `pbs01`, PAR2, OpenStack arrêté) ; créneau annoncé (fiche CHG standard), objets d'audit retirés à la fin.

*2. Analyses* :
- **OpenSCAP** : les analyses hebdomadaires du M26-E24 sont dans `s3-01` (`conformite`) ; on les relit, et on relance sur l'échantillon pour dater l'audit :
  ```
  admin@ipa01:~$ sudo systemctl start conformite-analyse.service && journalctl -u conformite-analyse.service -n 5 --no-pager
  admin@adm01:~$ (set -a; . ~/.config/workbook/s3-conformite.env; set +a; aws s3 ls --recursive s3://conformite/ | sort | tail -24)
  ```
  Les scores et comptes `fail` se lisent aussi dans Prometheus (`medisphere_conformite_score`) : c'est la preuve P-DUR-01.
- **kube-bench** : les Jobs du M26-E05 (`--benchmark cis-1.12`, cibles du nœud de contrôle et du travailleur) dans `wb-diagnostic`, journaux récupérés en JSON, Jobs supprimés.
  ```
  admin@adm01:~/m26/e05$ kubectl apply -f kube-bench-k8s-cp01.yaml -f kube-bench-k8s-w01.yaml
  admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic wait --for=condition=complete job/kube-bench-k8s-cp01 job/kube-bench-k8s-w01 --timeout=5m
  admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic logs job/kube-bench-k8s-cp01 > kube-bench-k8s-cp01.json
  admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic delete job kube-bench-k8s-cp01 kube-bench-k8s-w01
  ```
- **kubescape** : `kubescape scan framework nsa,mitre,cis-v1.12.0 --keep-local --format json --output kubescape.json`, puis le résumé du M26-E05 (`kubescape-resume.sh`) : on ne publie que cadres, scores, contrôles en échec et **nombre** de ressources.
- **Images** : `outils/cve-en-service.sh` (M26-E30, `plateforme/k8s`) pour les images **en service** analysées par Harbor ; pour une image sans analyse : `trivy image --severity CRITICAL,HIGH --format json -o <fichier>.json <IMAGE>@sha256:<EMPREINTE>`.
- **SSH** : `ssh-audit -j <hôte>` pour chaque point d'accès (16), et la politique MédiSphère du M26-E03.
- **Lynis** : `hardening_index` par hôte, en complément.

*3. Tri* : une règle écrite (§ 5 du rapport) — un échec n'est écarté que s'il est au registre des exceptions, s'il est un choix d'architecture documenté, ou s'il est non applicable pour une raison vérifiable. Les constats sont rangés par **constat** (pas par outil), classés par gravité **dans notre contexte**, et reliés à la SoA et aux écarts : les critiques en recette depuis plus de 30 jours et l'absence de délai écrit nourrissent ECA-3602.

*4. Rapport et résultats bruts* : `audit-technique.md`, `technique/` (au moins un fichier par outil), empreintes SHA-256 :

```
admin@adm01:~/medisphere/docs/conformite/audit-2026$ sha256sum technique/*
```

**Explications**

Un audit technique outillé ne vaut que par trois choses : ce qu'il a **regardé** (périmètre, échantillon, exclusions), la **règle** qui transforme des milliers de lignes en constats (et qui écarte les faux positifs de façon vérifiable), et la **traçabilité** des résultats (versions, empreintes). Les outils de conformité appliquent des référentiels écrits pour des architectures génériques : kube-bench ignore que kubeadm fait tourner etcd en pod statique, OpenSCAP ignore que nos VM n'ont qu'un disque. Le travail de l'auditeur interne est de dire, pour chaque écart d'outil, si c'est **notre** écart.

**Alternatives**
- Opérateurs d'analyse continue (Trivy Operator, opérateur kubescape) : rapports en CRD, toujours à jour ; une charge permanente et une surface de plus.
- Une plateforme de gestion des vulnérabilités (DefectDojo) pour agréger et dédoublonner : utile au-delà de quelques outils.
- `testssl.sh` pour les points d'entrée TLS : non installé au lab, à évaluer (pour aller plus loin).

**Pièges classiques**
- Publier les rapports bruts de kubescape : ils peuvent citer des valeurs de variables d'environnement ou des annotations ; on publie un **résumé**.
- Traiter un « FAIL » d'un référentiel non prévu pour la version (kube-bench `cis-1.12` sur 1.36) comme une vérité.
- Compter les vulnérabilités par dépôt du registre au lieu des images **en service** (par empreinte).
- Laisser le Job kube-bench (`hostPID`, montages de l'hôte) dans `wb-diagnostic` après l'audit.
- Un « faux positif » écarté sans référence au registre des exceptions : Hélène le rouvrira.

**En production chez MédiSphère**

Les mêmes analyses tournent chaque semaine (M26-E24) ; l'audit annuel n'en est qu'une lecture datée et signée ; un test d'intrusion externe annuel complète ce que les outils ne voient pas (logique applicative, chaînes d'attaque).

---

### F6-S06 — L'entretien d'audit

Réponses argumentées. Ce qui compte dans chacune : **la preuve qu'on montre**, et l'honnêteté sur ce qu'on ne sait pas.

**1. Activité 1 non certifiée.** Parce que nous ne l'exerçons pas : DataCampus fournit bâtiment, énergie, froid, accès aux salles, et il est certifié HDS pour l'activité 1. Je vous montre son **certificat en vigueur** (périmètre, date, organisme), notre **contrat** (localisation, engagements, droit d'audit), la **liste des personnes** autorisées à nos cages que nous tenons, et les journaux de badge qu'il nous fournit chaque trimestre. Ce qui reste chez nous (nos baies, nos disques, leur destruction) est dans l'activité 2 et les mesures 7.8, 7.10, 7.14. *Mauvaise réponse* : « c'est le colocataire, ça ne nous regarde pas » — la dépendance doit être maîtrisée (5.19-5.22).

**2. Une exclusion.** 8.23 (filtrage web) : aucun système du périmètre ne navigue, les serveurs ne sortent que vers une liste fermée par la bordure (8.20, 8.22). *Et la mesure qu'on a été tenté d'exclure* : par exemple 7.x « parce qu'on a un colocataire », ou 8.30 « parce qu'on ne sous-traite pas le développement » — faux, AxiomDev a développé pour MédiSphère. Et je dois vous dire que l'exclusion de 8.23 dépend d'une vérification que je n'ai pas encore faite sur `adm01` : si sa sortie Internet est large, l'exclusion tombe (observation O-1). Reconnaître la limite vaut mieux que la défendre à tort.

**3. P-IAM-01 du 3 novembre n'a pas été produite le 15.** Trois éléments indépendants de moi : la **date de dépôt** de l'objet et son **échéance de rétention** sont posées par le serveur RGW (`head-object`, `get-object-retention`) ; le compartiment est **versionné et verrouillé** (aucune version antérieure ou postérieure de cette clé, `list-object-versions`) ; le **pipeline** qui l'a produit est daté dans GitLab (`origine.pipeline` de `lot.json`). La signature prouve **qui** (la clé n'est utilisable que par ce pipeline), pas **quand** : je ne la mets pas en avant pour la date. Limite : la date du serveur repose sur l'horloge de Ceph (question 15) ; un horodatage RFC 3161 est au plan.

**4. L'administrateur de Ceph.** Au niveau S3, il ne peut rien effacer ; en dessous, rien ne l'en empêche : le verrouillage protège contre les identités **S3**, y compris le propriétaire du compartiment ; un administrateur de Ceph peut détruire le pool ou des objets RADOS en dessous. Compensations : copie de `preuves-conformite` à PAR2, sauvegardes, séparation des rôles (observation O-3 : aujourd'hui, ce sont les mêmes personnes — c'est écrit dans `preuves.md`). Une destruction serait **visible** (lots manquants, contrôle quotidien `preuves:verification` en échec, alerte sur l'âge du dernier lot) : on ne prévient pas, on détecte.

**5. Le lot partiel.** Pas en soi : c'est la preuve que la collecte a **essayé** et que l'échec est tracé (journal du collecteur dans le lot, pipeline rouge). Ce serait un écart si l'échec durait sans traitement, ou si la preuve manquante couvrait une mesure qu'aucune autre preuve ne couvre pendant cette période. Je vous montre le ticket ouvert par l'échec et le lot suivant, complet.

**6. Qui a lu un Secret de `mediagenda-prod`.** Requête dans Loki, locataire `audit` (alerte `AuditLectureSecretParPersonne` du M26-E28) : utilisateur, heure, nom du Secret, code de réponse — pas le contenu, jamais (niveau `Metadata`). Conservation **un an** : couvre l'année entre deux audits et l'essentiel des délais d'enquête ; au-delà, la minimisation (RGPD : ce sont des données personnelles des administrateurs) l'emporte. Et je vous dois la limite : cette réponse n'est pas **inaltérable** aujourd'hui (ECA-3601).

**7. Le bris de glace du cluster.** `admin.conf` (et `super-admin.conf`) : sur les nœuds de contrôle (root seulement) et une copie chiffrée dans l'enveloppe de reprise (F5) ; son usage produit des événements d'audit au nom `kubernetes-admin` (groupe `kubeadm:cluster-admins`), l'alerte `AuditBrisDeGlace` (critique) sonne. Dernière utilisation : je vous montre la requête et l'alerte correspondante dans Mailpit, avec le ticket d'incident qui l'a justifiée. *Si je ne la trouve pas* : je le dis, et c'est un écart.

**8. Le départ d'AxiomDev, et ce qu'il a créé.** Preuves du départ (F2-S12 : `docs/accueil/departs/axiomdev.md`, sortie de `depart-externe.sh`), comptes désactivés (P-IAM-01), bloqués (P-IAM-03), aucune liaison RBAC (P-IAM-04), espace supprimé. **Ce qu'il a créé** : c'est ce que la revue des accès (S03) a cherché — jeton de projet GitLab, liaison posée à la main, ligne de politique d'Argo CD — et retiré ; ses commits restent (attribués, relus). Le départ automatisé ne couvrait pas ces cas : ils sont ajoutés (ECA-3604).

**9. Dérogations.** Demandées par ticket, validées par la RSSI, enregistrées au registre (`EXC-…`) et en code (`PolicyException` avec `expiresAt`, `properties.ticket`, `valideur`) ; 90 jours au plus, revue mensuelle, pipeline qui échoue 14 jours avant l'échéance (M26). **À l'échéance**, Kyverno ignore l'exception : la politique s'applique de nouveau, sans action humaine. Et j'ajoute que nous avons trouvé en S04 une dérogation posée hors de ce circuit (ECA-361x) : la prévention est une politique sur les dérogations elles-mêmes.

**10. Une critique publiée ce matin.** J0 : Harbor ré-analyse (ou on force l'analyse), `cve-en-service.sh` dit quelles images **en service** sont touchées ; évaluation (exploitable chez nous ? exposée ?) ; ticket `SEC-`. J0-J2 : correctif publié → reconstruction et promotion par le chemin normal (CI, signature, Argo CD), recette puis production ; pas de correctif → mesure compensatoire (politique réseau, Tetragon, désactivation de la fonction) et **dérogation datée**. Aujourd'hui, je ne peux pas vous montrer de délai **écrit** : c'est ECA-3602, la politique de délais arrive en S09.

**11. Les clés du compartiment Velero.** Aujourd'hui : les manifestes des espaces sauvegardés, **Secrets compris**, et les données des volumes, chiffrées par Kopia avec la phrase par défaut de Velero — donc lisibles. C'est ECA-3603 (majeur). Mesure conservatoire : identités de lecture réduites ; correction en S09 (chiffrement côté serveur, clé dans OpenBao, restauration éprouvée). Répondre « tout est chiffré » parce que PBS l'est serait faux.

**12. Les données de recette.** Règle : jamais de copie de production hors production (8.31, 8.33) ; la recette est alimentée par des jeux **fictifs** générés (scénarios du M29) ; l'équipe Data ne reçoit que des extractions **pseudonymisées**. *Comment je le sais* : la recette n'a pas d'accès réseau ni d'identité vers la base de production (CNP, rôles OpenBao distincts), et aucune restauration de production vers la recette n'apparaît dans les journaux. *Dans six mois* : un contrôle à écrire (échantillonnage de la base de recette contre des motifs de données réelles, par exemple des numéros de sécurité sociale valides) — je n'ai pas de preuve automatique aujourd'hui. (Ce sera aussi la question de la phase 4.)

**13. Une fuite signalée par un client.** Première heure : on ouvre un incident de sécurité (INC-), pilote la RSSI, main courante ; on **préserve** (pas de redémarrage ni de suppression de ce qui pourrait être compromis ; captures, journaux), on **contient** si une compromission est avérée (quarantaine réseau), on qualifie (quelles données, quels patients, quels clients). **La CNIL** est notifiée par le **responsable de traitement**, c'est-à-dire le client, dans les 72 heures après qu'il en a pris connaissance ; MédiSphère, sous-traitante, l'informe **sans délai** (RGPD art. 33.2, contrat) avec les éléments utiles ; le client fait aussi, s'il y a lieu, le signalement d'incident grave sur le portail des événements sanitaires (CSP). Et nous inscrivons la violation à notre propre registre. Aujourd'hui, c'est écrit nulle part chez nous : ECA-3605.

**14. Transferts hors EEE.** Nos données de santé sont hébergées en France, sans copie hors EEE ; mais nous avons découvert pendant cet audit au moins trois sujets (outil de tickets d'une société américaine qui reçoit parfois des captures de dossiers, rapports de remise SMS traités aux États-Unis, astreinte depuis le Maroc) : la cartographie (ECA-3606) les traite. *Comment je le sais* : revue des contrats et des sous-traitants ultérieurs, et revue des connexions VPN (géolocalisation des adresses source) — la seconde est nouvelle.

**15. Les horloges.** Parce qu'une preuve d'enchaînement (« il s'est connecté, **puis** il a lu le Secret ») n'existe que si les horloges sont cohérentes entre les sources, et que la date d'une preuve en dépend (question 3). Référence : `gw01`/`gw02` (chrony, sources externes), toutes les VM, nœuds et services s'y synchronisent ; décalage supervisé (M21). Les journaux sont horodatés à la source en UTC ; Loki garde l'horodatage de la ligne, pas celui de l'ingestion (vérifié dans le pipeline Alloy).

**16. Approbation de la SoA et revue de direction.** La SoA est approuvée par la RSSI et la direction (MR approuvée, version et date dans le document). La **revue de direction** : compte rendu daté, participants, décisions (périmètre, risques acceptés, moyens) — si elle n'a pas encore eu lieu sous cette forme, je vous le dis, et c'est un écart au chapitre 9.3 de la norme (pas à l'annexe A) que l'audit de certification ne nous pardonnera pas.

---

### F6-S07 — Rapport d'écarts et plan de remédiation

**Solution**

Documents de référence :
- [`audit-2026/rapport-ecarts.md`](fichiers/F6-S07/medisphere/docs/conformite/audit-2026/rapport-ecarts.md) : synthèse pour la direction (une décision demandée), méthode et limites, points forts, six écarts avec gravités argumentées, écarts de S04, observations ;
- fiches [`ECA-3601`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3601-journaux-audit.md), [`ECA-3602`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3602-vulnerabilites.md), [`ECA-3603`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3603-sauvegardes-chiffrement.md), [`ECA-3604`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3604-revue-acces.md), [`ECA-3605`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3605-reponse-incident.md), [`ECA-3606`](fichiers/F6-S07/medisphere/docs/conformite/ecarts/ECA-3606-transferts-hors-eee.md) ;
- [`plan-remediation.md`](fichiers/F6-S07/medisphere/docs/conformite/plan-remediation.md) : méthode (impact × vraisemblance, dépendances), tableau des écarts, calendrier tenant compte du gel de fin d'année (F4), risques acceptés temporairement et par qui ;
- [`transferts-hors-eee.md`](fichiers/F6-S07/medisphere/docs/conformite/transferts-hors-eee.md) : trois questions par ligne, inventaire, ce qui est dit aux clients, synthèse publiée.

Les décisions de fond :
1. **Gravités** : quatre majeures (aucune protection des journaux, aucune confidentialité des copies indépendante du stockage, aucune capacité de réponse démontrée, exigence HDS explicite non satisfaite avec un flux réel), deux mineures (processus en place dont le pilotage ou la répétition manquent).
2. **Priorités par le risque**, pas par la gravité : ECA-3606 d'abord (des données de santé sortent **aujourd'hui** du périmètre maîtrisé ; premières actions presque gratuites), ECA-3603 et 3602 (exposition directe), ECA-3601 **avancé** parce que ECA-3605 en dépend.
3. **Transferts** : DataCampus et les registres publics **hors** cartographie (aucune donnée ne sort), mais écrits pour montrer qu'ils ont été examinés ; HelpNow **à réduire** (plus aucune donnée de santé ; outil européen à étudier) ; SMS-Express **accepté sous conditions** (minimisation du texte) ; astreinte au Maroc **refusée** (un accès d'administration depuis un pays tiers devrait être écrit au contrat de chaque client et publié).

**Explications**
- Un **constat** est un fait observable, daté, avec sa preuve ; la **gravité** est une qualification selon les définitions d'ISO ; le **risque** est une estimation pour les personnes concernées. Les trois ne se confondent pas, et le rapport les sépare.
- Les **points forts** ne sont pas de la politesse : ils disent à la direction ce qu'il ne faut **pas** casser en corrigeant (le « tout par le code », les preuves automatiques).
- Le nouveau référentiel HDS a déplacé la question des transferts du juridique vers l'**inventaire technique** : on ne peut pas répondre sans savoir quels outils reçoivent quoi, et d'où l'on administre.

**Alternatives**
- Gravité en trois niveaux internes (critique, élevé, moyen) au lieu de majeur/mineur : utile pour le pilotage, mais un audit de certification parle majeur/mineur ; on garde les deux colonnes si besoin.
- Méthode de risque EBIOS RM pour les écarts : plus riche (sources de risque, scénarios stratégiques), plus longue ; le produit impact × vraisemblance suffit pour ordonner six écarts.
- Publier la cartographie détaillée : non, seule la synthèse est publique ; le détail va aux clients.

**Pièges classiques**
- Recopier les notes d'Hélène sans les **preuves** : un écart sans preuve se conteste.
- Tout classer majeur « par prudence » : le plan devient illisible et la direction ne sait plus quoi arbitrer.
- Prioriser par facilité (ce qui se ferme vite) : on ferme quatre écarts mineurs et on laisse les données en clair.
- Oublier la **dépendance** journaux → réponse à incident.
- Cartographie limitée aux hébergeurs : les transferts viennent souvent des outils « autour » (support, SMS, messagerie) et des **accès** (astreinte, prestataires, éditeurs en télémaintenance).
- Croire qu'un hébergement « en UE » d'une société américaine règle la question : la soumission à une loi extra-européenne est une exigence de transparence à part entière.

**En production chez MédiSphère**

Le registre des écarts est suivi chaque semaine en comité sécurité ; la cartographie est revue à chaque nouveau fournisseur (étape du processus d'achat) et publiée après validation du DPO ; l'auditeur de certification reçoit le rapport d'audit à blanc et le plan : montrer qu'on a trouvé et traité ses propres écarts est un point fort.

---

## Points non testés en conditions réelles (phase 2)

Signale tes retours : ils corrigent le workbook.

- **Injection de S04** : chaque candidat est vérifié sur place, mais l'ensemble n'a pas été rejoué sur un lab réel. À confirmer : déblocage par l'API d'un compte GitLab bloqué (`POST /users/:id/unblock`) et sa trace dans `audit_json.log` selon l'édition ; acceptation d'une `PolicyException` visant une `ImageValidatingPolicy` sans `expiresAt` par Kyverno 1.19/1.20 ; `spec.paused` de Velero 1.18 et la métrique `velero_backup_last_successful_timestamp` ; création d'un silence par l'API v2 d'Alertmanager 0.34 depuis `adm01` (CiliumNetworkPolicy du M21) ; règle nftables insérée par `wb_exec` sur `gw02` en position passive.
- **Check S04, bordure** : le contrôle compare les **commentaires** des règles actives au fichier persisté ; une règle à chaud **sans** commentaire lui échappe (la section « écart » de `preuves-pare-feu` la verrait). Le check lit `/etc/nftables.conf` par `sudo -n cat`, avec le même compte que `sudo -n nft list` (F3).
- **Velero** : phrase de passe par défaut du dépôt Kopia (`velero-repo-credentials`, clé `repository-password`) et absence de chiffrement de l'archive des manifestes, tels que décrits dans ECA-3603 : à vérifier dans la documentation de Velero 1.18 et sur ton lab (sans afficher la phrase).
- **GitLab** : champs `two_factor_enabled`, `current_sign_in_at`, `last_activity_on` visibles par un jeton d'administrateur en lecture (`read_api`) ; journal `audit_json.log` dans l'édition Free.
- **Requêtes LogQL** : noms des champs de l'audit Kubernetes après le pipeline Alloy (`user_username`, `stageTimestamp`…) : adapte-les à ton extraction (M22).
- **ssh-audit `-j`** (sortie JSON) en 3.9 et **kubescape** 4.0 (noms et identifiants de contrôles) : vérifie avec `--help` et `kubescape list controls`.
- **HDS** : numérotation des exigences « de souveraineté » (28 à 31 selon des commentaires publiés) à relire dans le texte du référentiel ; périmètre exact du signalement des incidents graves (article L.1111-8-2 du CSP) : à vérifier sur Légifrance.
