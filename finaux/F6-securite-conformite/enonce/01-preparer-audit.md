# Final F6 — Phase 1 : Préparer l'audit

Un auditeur ne demande pas « êtes-vous sécurisés ? ». Il demande : « sur quel périmètre ? selon quelles exigences ? montrez-moi ». Cette phase fabrique les trois réponses : un périmètre et une déclaration d'applicabilité qui disent ce que MédiSphère s'engage à faire, des preuves qui se produisent toutes seules et ne se retouchent pas, et une revue des accès qui montre que les droits de chacun sont ceux qu'il doit avoir — et ceux des partis, aucun.

Prérequis de la phase : [`00-introduction.md`](00-introduction.md) lu, état d'entrée vérifié.

---

### F6-S01 — Périmètre, exigences et déclaration d'applicabilité  `RED` `★★★`

> **Ticket SEC-3601** — *De : Sophie Laurent* — *Copie : Thomas Renaud, Claire Morel*
> Hélène commencera par deux questions : « Qu'est-ce que vous faites certifier, exactement ? » et « Montrez-moi votre déclaration d'applicabilité. » Je veux un périmètre qu'on puisse défendre — quelles activités HDS nous exerçons vraiment, lesquelles non et pourquoi — et une SoA qui passe en revue les **93** mesures, sans en oublier une, sans « applicable » de complaisance ni exclusion de confort. Thomas relira tout ce qui touche aux données de santé. Je signe vendredi.

**Objectifs pédagogiques**
- Traduire un référentiel en périmètre : distinguer ce qu'on exerce, ce qu'on sous-traite, ce qui est hors champ.
- Rédiger une déclaration d'applicabilité complète et défendable, chaque décision justifiée et reliée à une preuve.
- Situer les exigences propres à HDS v2 (localisation, transparence, contrat, réversibilité) par rapport à ISO/IEC 27001.

**Prérequis** : modules 24 à 26 ; F2 (équipes, prestataires) ; F4 (processus de changement), F5 (PRA) si tu les as faits.
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- **Sites** : les salles PAR1 et PAR2 sont des espaces privatifs (cages) loués chez **DataCampus**, opérateur de colocation (fictif) **certifié HDS pour l'activité 1** ; il fournit le bâtiment, l'énergie, la climatisation, le contrôle d'accès et la surveillance des salles. Les serveurs (`pve01`, `hp01`), les baies et le réseau de baie appartiennent à MédiSphère.
- **Clients** : cabinets médicaux, centres de santé et établissements, responsables de traitement des données de leurs patients ; ils accèdent à MédiAgenda, MédiDoc (pièces jointes), MédiNotif (rappels), Legacy-RDV et MédiVisio (téléconsultation).
- **SI interne** (messagerie, bureautique, RH, comptabilité) : géré par un autre prestataire, sans donnée de santé, séparé de la plateforme.
- **Format de la SoA** (lu par le check) : rappelé dans [`00-introduction.md`](00-introduction.md), « Conventions du final ».
- Le texte d'ISO/IEC 27001 est payant : si tu ne l'as pas, la liste des intitulés de l'annexe A (identique à ISO/IEC 27002:2022) est largement publiée par les organismes certificateurs ; cite tes sources.

**Travail demandé**
1. Rédige `docs/conformite/perimetre.md` : ce que fait MédiSphère au sens du code de la santé publique ; pour **chacune** des six activités HDS, exercée ou non, comment, avec quelle preuve ; l'énoncé du périmètre du SMSI ; ce qui est dedans, ce qui est dehors et pourquoi ; les interfaces (clients, sous-traitants) ; la classification des données ; la localisation ; les parties intéressées et leurs exigences.
2. Rédige `docs/conformite/soa.md` : les **93** mesures de l'annexe A, chacune avec sa décision, sa justification, sa mise en œuvre **chez MédiSphère** (outil, processus, dépôt) et la preuve qu'on montrera ; puis les exigences HDS propres à l'hébergement (localisation, transparence, contrat, information du client, réversibilité, sauvegarde…) avec ce qui les démontre.
3. Repère dans ta SoA les mesures dont la mise en œuvre te paraît **fragile** aujourd'hui : note-les, elles serviront en S04-S07.
4. MR relue par Sophie (et Thomas pour les données), fusionnée sur `main`.

**Contraintes**
- Une mesure assurée par un fournisseur n'est pas « non applicable ».
- Chaque exclusion se justifie en une phrase qu'un auditeur peut vérifier.
- Pas de mise en œuvre générique (« des procédures existent ») : un nom d'outil, de dépôt, de document ou de processus.

**Critères de réussite**
- [ ] `perimetre.md` est sur `main` : six activités, chacune dite exercée ou non avec sa justification ; périmètre du SMSI, exclusions et interfaces.
- [ ] `soa.md` est sur `main` : les 93 mesures (5.1 à 8.34) ont une décision `Oui`/`Non` ; chaque `Non` a une justification ; les exigences HDS sont traitées ; la version et la date de la déclaration sont indiquées.

**Vérification** : `lab/bin/check F6 1` (présence et complétude ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Pour les activités HDS, pose la question « qui, concrètement, fait ce travail, et avec quoi ? ». Si la réponse est « un fournisseur certifié pour cette activité », tu ne l'exerces pas — mais tu dois le prouver (son certificat, ton contrat) et le suivre. Si la réponse est « nous, avec nos outils », tu l'exerces, même si c'est « juste » de la sauvegarde.
</details>

<details><summary>Indice 2</summary>

Pour remplir vite et juste la colonne « mise en œuvre », pars de ce qui existe : chaque module t'a laissé un outil, un dépôt, un runbook ou une politique. Les mesures 7.x (physiques) concernent aussi l'intérieur de **tes** baies et **tes** disques ; les mesures 8.x se relient presque toutes à un composant que tu as installé. La colonne « preuve » prépare S02 : si tu ne sais pas quoi montrer pour une mesure, c'est un signal.
</details>

<details><summary>Indice 3</summary>

Une exclusion défendable porte sur une mesure dont le **risque** n'existe pas dans le périmètre (pas « on n'a pas eu le temps »). Peu d'exclusions est normal pour un hébergeur. Demande-toi pour chaque exclusion candidate : un auditeur peut-il trouver, dans le périmètre, un cas où la mesure aurait dû s'appliquer ?
</details>

**Pour aller plus loin** (facultatif) : relier chaque mesure aux risques de ton appréciation des risques (chapitre 6.1.3 de la norme) ; comparer ta SoA à la table de correspondance publiée par l'ANSSI ou un organisme certificateur entre ISO/IEC 27001:2013 et 2022.

---

### F6-S02 — Les preuves se collectent seules  `LIBRE` `★★★`

> **Ticket PLAT-3602** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Sophie veut qu'on puisse montrer à Hélène, pour n'importe quelle date des derniers mois, qui avait accès à quoi, quelles dérogations couraient, si les sauvegardes passaient, ce que disait la bordure… Pas en refaisant des captures d'écran la veille : avec des preuves **collectées chaque jour par une machine**, horodatées, signées, et rangées là où **personne** ne peut les retoucher, nous compris. Un outil `ms-preuves` dans `plateforme/outils`, un compartiment RGW `preuves-conformite` en verrouillage d'objets, un pipeline planifié, et le catalogue qui dit quelle preuve couvre quelle mesure. Et je relis tout : un outil de preuves qui laisse fuir un secret dans un compartiment indélébile, c'est le pire des deux mondes.

**Objectifs pédagogiques**
- Concevoir une chaîne de preuves : collecte en lecture seule, horodatage, empreinte, signature, dépôt inaltérable, vérification indépendante.
- Mettre en œuvre le verrouillage d'objets S3 (Object Lock) du RGW, comprendre `GOVERNANCE` et `COMPLIANCE` et leurs conséquences.
- Industrialiser : outil testé, identités dédiées, pipeline planifié, échec visible.

**Prérequis** : F6-S01 ; M08 (RGW), F2-S08 (utilisateurs et compartiments RGW par script, `plateforme/ceph`) ; M25 (OpenBao `transit`, Cosign `hashivault://`, méthode `jwt` `gitlab`, rôles `ci-*`) ; M02 et F2-S13 (conventions des outils `ms-*` de `plateforme/outils`, tests sans service réel) ; M19 (pipelines planifiés).
**Durée indicative** : 7 à 8 h.

**Contexte technique**
- RGW de `ceph-par1` : `https://rgw.par1.medisphere.internal` ; `radosgw-admin` sur `ceph01` ; le script `outils/rgw-compartiment.sh` de `plateforme/ceph` (F2-S08) montre comment créer un utilisateur, ranger ses clés dans OpenBao sans les afficher, et créer un compartiment.
- Valeurs figées (les checks et les phases suivantes les lisent) : compartiment **`preuves-conformite`** ; utilisateur RGW de lecture **`preuves-lecture`** (l'auditrice, les checks : fichier `~/.config/workbook/s3-preuves-conformite-lecture.env` sur `adm01`, mode 600, variables `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY`) ; clé publique de signature publiée en **`docs/conformite/cle-preuves.pub`** ; lots déposés sous le préfixe **`lots/AAAA/MM/JJ/<lot>/`**, chaque lot contenant un **`lot.json`** (avec au moins `preuves[].statut` et l'origine `origine.pipeline`), un manifeste **`MANIFESTE.sha256`** (format `sha256sum`) et sa signature **`MANIFESTE.sha256.sigstore.json`** (bundle Cosign).
- Le verrouillage d'objets se décide **à la création** du compartiment ; il impose le versionnage. La documentation de Ceph : [opérations sur les compartiments](https://docs.ceph.com/en/latest/radosgw/s3/bucketops/) (verrouillage, rétention par défaut) et [sur les objets](https://docs.ceph.com/en/latest/radosgw/s3/objectops/) (rétention, mise en suspens légale).
- ⚠️ Un objet écrit en mode **`COMPLIANCE`** ne peut être ni supprimé, ni écrasé, ni voir sa rétention raccourcie avant l'échéance, **par personne**. Essaie d'abord en **`GOVERNANCE` avec une rétention d'un jour**, sur des lots d'essai ; ne passe en `COMPLIANCE` que lorsque le contenu des lots est juste (aucun secret, aucune donnée de santé).
- Les outils `ms-*` de `plateforme/outils` sont en **Bash** (mode strict, `shellcheck`, journal sur la sortie d'erreur et données sur la sortie standard, codes retour 0/1/2/3, tests avec de faux outils dans `tests/`). Le pipeline planifié tourne sur un runner du socle ; Cosign, `bao` et l'AWS CLI doivent y être installés par le code.

**Travail demandé**

Objectifs :
1. Le **compartiment** `preuves-conformite` en verrouillage d'objets, avec une rétention par défaut, une identité d'écriture pour la collecte et l'identité de lecture `preuves-lecture`, le tout par un script versionné dans `plateforme/ceph`, clés rangées dans OpenBao.
2. Une **clé de signature** dédiée dans `transit` d'OpenBao (pas celle des images), un rôle `jwt` réservé au pipeline de collecte, une politique minimale, par le code de `plateforme/secrets`.
3. L'outil **`ms-preuves`** : il lance des **collecteurs** déclarés dans un catalogue (au moins **dix preuves**, couvrant identités, droits, dérogations, vulnérabilités, sauvegardes, bordure, coffre, supervision, conformité des hôtes), écrit chaque preuve avec son horodatage et son origine, calcule les empreintes, signe le manifeste, dépose le lot dans le compartiment verrouillé et **vérifie** un lot déposé. Un collecteur en échec n'arrête pas le lot : il le marque.
4. Des **tests** sans service réel (faux outils), dans la CI de `plateforme/outils`.
5. Un **pipeline planifié** quotidien (et d'autres fréquences si ton catalogue en a), sans aucun secret en variable CI, et un contrôle d'intégrité régulier du dernier lot dont l'échec se voit.
6. Le **catalogue** `docs/conformite/preuves.md` : chaque preuve (identifiant, mesures ISO couvertes, activité HDS, fréquence, source), le stockage et la rétention, les limites connues, et la procédure de vérification pour l'auditrice.
7. La **bascule** en `COMPLIANCE` avec une rétention d'au moins un an, une fois les lots d'essai jugés bons.

Contraintes :
- Collecteurs en **lecture seule**, avec des identités de lecture ; jamais de secret ni de donnée de santé dans une preuve — et un garde-fou dans l'outil qui refuse une preuve qui en contient.
- Rien ne doit permettre à la collecte de **supprimer** ou de remplacer un lot déposé.
- Les lots d'essai en `GOVERNANCE` peuvent être retirés (avec le droit de contournement) ; note comment.

Livrables : MR dans `plateforme/outils`, `plateforme/ceph`, `plateforme/secrets`, `plateforme/ansible` (outils du runner) et `plateforme/medisphere` (`preuves.md`, `cle-preuves.pub`).

**Critères de réussite**
- [ ] `preuves-conformite` a le verrouillage d'objets, le versionnage, une rétention par défaut **`COMPLIANCE` d'au moins 365 jours** ; `preuves-lecture` peut lister et lire, pas écrire.
- [ ] Un lot de moins de 36 h existe, déposé par un pipeline planifié de `plateforme/outils` ; il contient au moins huit preuves collectées avec succès, un manifeste dont les empreintes sont justes, et une signature vérifiable avec `cle-preuves.pub`.
- [ ] Chaque objet du lot porte une rétention en cours.
- [ ] `ms-preuves`, son catalogue et ses tests sont sur `main` de `plateforme/outils` ; le dernier pipeline planifié n'a pas échoué.
- [ ] `docs/conformite/preuves.md` décrit le catalogue, la rétention, les limites et la vérification.

**Vérification** : `lab/bin/check F6 2`

<details><summary>Indice 1</summary>

Sépare trois questions : **qui** a produit la preuve (la signature, par une clé qui ne sort jamais du coffre et qu'un seul pipeline peut utiliser), **quand** (une signature sans journal de transparence ne date rien ; qui, dans ta chaîne, pose une date que tu ne contrôles pas ?), **n'a-t-elle pas changé** (empreintes et verrouillage). Une preuve forte répond aux trois sans te faire confiance.
</details>

<details><summary>Indice 2</summary>

Le verrouillage d'objets protège contre les **identités S3**. Demande-toi ce qu'il ne couvre pas (qui administre Ceph lui-même ?) et écris-le dans les limites du catalogue : un auditeur préfère une limite écrite à une promesse fausse. Côté dépôt, vérifie après chaque écriture que l'objet porte bien un mode et une échéance : un compartiment mal réglé accepterait des objets sans protection, en silence.
</details>

<details><summary>Indice 3</summary>

Pour les tests, inspire-toi de `tests/ms-verif-equipe/` (F2-S13) : de faux `aws`, `cosign` et `yq` dans un dossier placé en tête du `PATH`, un compartiment simulé dans un dossier temporaire, des collecteurs d'essai (un qui réussit, un qui échoue, un qui « fuit » un faux mot de passe). Teste surtout les **refus** : lot non signé, compartiment sans verrou, double dépôt, fichier modifié après signature.
</details>

**Pour aller plus loin** (facultatif) : un horodatage de confiance RFC 3161 (Cosign accepte une autorité d'horodatage dans sa configuration de signature) ; copier `preuves-conformite` vers `s3-02` (PAR2) avec la même rétention ; une métrique « âge du dernier lot » et son alerte.

---

### F6-S03 — La revue des accès  `LIBRE` `★★★`

> **Ticket SEC-3603** — *De : Sophie Laurent* — *Copie : Claire Morel, Karim Benali*
> La dernière vraie revue des accès date… de jamais. On a fait le départ d'AxiomDev proprement, je crois, mais « je crois » n'est pas une preuve. Avant qu'Hélène arrive, je veux une revue **complète** : annuaire, Keycloak, GitLab, Proxmox, les droits Kubernetes, OpenBao, Harbor, Argo CD, Grafana. Chaque compte rattaché à une personne présente ou déclaré comme compte technique avec un propriétaire ; tout le reste, une décision. Et je ne veux pas d'un tableur fait à la main : une revue que l'on peut **refaire** le mois prochain à l'identique.

**Objectifs pédagogiques**
- Mener une revue des accès sur plusieurs systèmes à partir d'une source de vérité des personnes.
- Distinguer comptes de personnes, comptes techniques, bris de glace, comptes orphelins, et décider pour chacun.
- Rendre la revue reproductible (outil, déclarations versionnées) et en garder la preuve.

**Prérequis** : F6-S02 (`ms-preuves`, pour garder l'état brut) ; M24 (FreeIPA, Keycloak, SSO des services, comptes de bris de glace) ; M25 (OpenBao, AppRole, rôles `jwt`) ; F2-S10 à S12 (AxiomDev, son départ, `depart-externe.sh`).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Source de vérité des personnes : l'**annuaire FreeIPA** (`ipa01`) — un compte actif = une personne présente ; `nsAccountLock: TRUE` = désactivé. Les identités de lecture des checks (M24-M26 : `ipa-checks.env`, `keycloak-checks.env`, `openbao-checks.env`, `grafana-checks.token`, `k8s-checks.kubeconfig`) montrent comment lire chaque système sans pouvoir écrire ; certaines ne suffisent pas pour une revue complète (liste des utilisateurs de Grafana ou de Harbor, par exemple) : à toi de décider quelles identités de revue créer, et de l'écrire.
- Départ d'AxiomDev (F2-S12) : `marc.vidal`, `yanis.perrin`, groupe `ext-axiomdev`, espace `mediagenda-axiomdev` ; ce que le code retire et ce que `depart-externe.sh` retire (sessions, jetons personnels, clés, appartenances). Pense à ce qui n'est **ni l'un ni l'autre**.
- Livrable figé (lu par le check) : `docs/conformite/revue-acces/AAAA-MM.md`, mois de la revue.
- Les identités du **workbook** (`wb-checks`, `wb-tofu-hv@pve`, etc.) n'existeraient pas dans un MédiSphère réel : déclare-les comme telles, ne les supprime pas.

**Travail demandé**

Objectifs :
1. Un **outil de revue** dans `plateforme/outils` (convention `ms-*`) qui relève, en lecture seule, les comptes et droits des neuf systèmes, les confronte à l'annuaire et à une liste **versionnée** de comptes non personnels déclarés (nature, propriétaire, justification), et classe chaque compte. Il doit pouvoir tourner sans personne devant (pipeline) et produire un brouillon de revue et un état brut.
2. Une **revue** effective : `docs/conformite/revue-acces/AAAA-MM.md` avec la méthode, le résultat outillé, **chaque** compte à traiter et sa décision (retrait, justification, déclaration), son responsable et son échéance, la revue spécifique des droits d'administration, ce que la revue ne couvre pas encore.
3. Les **corrections** décidées, faites par le bon chemin (code quand l'objet est décrit dans un dépôt).
4. La **périodicité** : quand on refait la revue, pour quels comptes, qui décide ; l'état brut gardé comme preuve (catalogue de S02).

Contraintes :
- Ne supprime aucun compte de personne : on désactive ou on bloque (l'historique garde son auteur).
- Ne touche pas aux comptes de bris de glace : on vérifie qu'ils sont déclarés, protégés, et que leur usage se voit.
- Les décisions sont prises par Sophie et Claire (approbation de la MR) : l'outil propose, il ne décide pas.

**Critères de réussite**
- [ ] `docs/conformite/revue-acces/AAAA-MM.md` est sur `main` ; il couvre FreeIPA, Keycloak, GitLab, Proxmox, Kubernetes, OpenBao, Harbor, Argo CD et Grafana, et donne pour chaque compte orphelin (AxiomDev compris) une décision, un responsable et une échéance.
- [ ] L'outil de revue est versionné dans `plateforme/outils` (`bin/ms-…acces…`).
- [ ] Il ne reste aucun accès d'AxiomDev : comptes désactivés dans l'annuaire et non actifs dans GitLab, aucune liaison RBAC vers ses personnes ou son groupe, plus d'espace `mediagenda-axiomdev`, aucune mention dans la politique RBAC d'Argo CD.

**Vérification** : `lab/bin/check F6 3`

<details><summary>Indice 1</summary>

Classe avant de décider. Quatre familles suffisent : personne présente, compte non personnel **déclaré** (technique, bris de glace), compte d'une personne **partie** encore actif quelque part (orphelin), compte que personne ne sait expliquer (à justifier). Les deux dernières sont la revue ; les deux premières sont sa preuve.
</details>

<details><summary>Indice 2</summary>

Un départ coupe ce qui est **rattaché à la personne** (son compte, ses sessions, ses jetons personnels). Cherche ce qui a été **créé par elle** mais n'est pas à son nom : jetons de projet, robots, comptes de service, liaisons RBAC posées à la main, lignes de politique Argo CD, groupes cités dans une configuration. Et cherche ce qui a été créé « pour un essai » par des personnes encore là.
</details>

<details><summary>Indice 3</summary>

Pour la reproductibilité : sortie triée, même entrée → même sortie, liste des comptes déclarés dans le dépôt (une ligne = une décision relue), un système sans identité de lecture signalé « non vérifié » plutôt que passé sous silence. Fais tourner l'outil deux fois de suite : les deux résultats doivent être identiques.
</details>

**Pour aller plus loin** (facultatif) : ajouter PBS, NetBox, le royaume `master` de Keycloak et les certificats SSH émis par step-ca ; une métrique « comptes à traiter » par système et une alerte au-delà de zéro pendant plus de dix jours.
