# Final F6 — Phase 3 : Remédier

Le rapport d'écarts est écrit (F6-S07), le plan de remédiation est priorisé par le risque. Deux écarts se traitent maintenant, parce qu'ils conditionnent tout le reste : sans **traçabilité inaltérable**, aucune enquête ne tient devant un auditeur ni devant un juge ; sans **gestion des vulnérabilités sous contrôle**, on ne sait pas ce qui est exposé ni depuis quand. On ne rédige plus : on code, on vérifie que la preuve se produit toute seule, et on ferme l'écart avec sa preuve de clôture.

Prérequis de la phase : F6-S07 terminé (registre des écarts `ECA-36xx` formalisé, plan de remédiation sur `main`). Les écarts injectés par F6-S04 (`ECA-3611` et suivants) sont déjà corrigés.

> **Rappel — collecte des preuves** : chaque remédiation produit une preuve rangée par `ms-preuves` (F6-S02) dans le compartiment `preuves-conformite` (verrouillage d'objets, versionné). Une remédiation sans preuve n'en est pas une.

---

### F6-S08 — Une traçabilité inaltérable  `LIBRE` `★★★`

> **Ticket SEC-3608** — *De : Sophie Laurent (RSSI)* — *Copie : Thomas Renaud (DPO), Karim Benali*
> Hélène Mercier a relevé l'écart **ECA-3601** : nos journaux d'audit existent, mais rien ne prouve qu'ils n'ont pas été modifiés, et chaque brique les garde dans son coin, avec sa propre durée. Elle a été directe : « Le jour où un administrateur efface la trace de ce qu'il a fait, vous ne le verrez pas. Et le jour où vous présentez un journal à un juge, l'autre partie vous demandera comment vous prouvez qu'il n'a pas été retouché. » Je veux une chaîne de traçabilité **complète** (Kubernetes, OpenBao, Keycloak, GitLab, Proxmox, FreeIPA), centralisée, **horodatée de façon cohérente**, dont l'intégrité se vérifie, conservée **un an**, et dont la copie d'archive ne peut être ni modifiée ni supprimée avant l'échéance — même par moi. Ferme l'écart avec la preuve.

**Objectifs pédagogiques**
- Recenser les sources de journaux d'audit d'une plateforme et les acheminer vers un puits central (Loki, locataire `audit`).
- Garantir l'inaltérabilité par une archive en verrouillage d'objets et un contrôle d'intégrité indépendant.
- Raisonner conservation : durée réglementaire, minimisation RGPD, coût, et la différence entre « centralisé » et « inaltérable ».

**Prérequis** : F6-S01 à F6-S07 ; M22 (Loki multi-locataire, locataire `audit`, Alloy, rétentions par locataire, compartiment de l'audit) ; M14 (politique d'audit de l'API Kubernetes), M24 (événements Keycloak, audit FreeIPA), M25 (journal d'audit d'OpenBao), M08 (RGW, verrouillage d'objets), M13 (Cosign/`transit` pour signer). F6-S02 (`ms-preuves`).
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Puits central : **Loki 3.7**, locataire **`audit`** (`X-Scope-OrgID: audit`), alimenté par Alloy (M22). La politique d'audit de l'API Kubernetes (M14) ne journalise jamais le contenu des Secrets (niveau `Metadata`) : le locataire `audit` ne contient donc aucun secret.
- Sources à couvrir, avec leur mécanisme natif :
  - **Kubernetes** : journal d'audit de l'API (`/var/log/kubernetes/audit/audit.log`, déjà collecté) ;
  - **OpenBao** : moteur d'audit (`bao audit enable file` ou `socket`) — le format est en clair, le HMAC des valeurs sensibles est fait par OpenBao ;
  - **Keycloak** : événements d'administration et de connexion (`events`, écouteur `jboss-logging` ou export) ;
  - **GitLab** : événements d'audit (flux de journaux `audit_json.log` des composants, ou API `audit_events`) ;
  - **Proxmox** : journal des tâches de `pve01` et `pbs01` (qui a lancé quoi) et le syslog d'authentification ;
  - **FreeIPA** : journal d'audit du serveur d'annuaire (389-ds) et les connexions Kerberos.
- Horodatage : toutes les sources doivent être **synchronisées** sur la même référence de temps (chrony sur `gw01`, M00) ; une ligne d'audit sans horodatage fiable ne prouve rien.
- Archive inaltérable : compartiment RGW en **verrouillage d'objets** (*Object Lock*). Le compartiment `preuves-conformite` existe déjà (F6-S02) ; décide si l'archive des journaux y va ou dans un compartiment dédié (`archive-audit`), et dans quel **mode** (`GOVERNANCE` pour tester, `COMPLIANCE` pour l'inaltérabilité réelle). ⚠️ Un objet en mode `COMPLIANCE` ne peut **pas** être supprimé avant l'échéance, même par l'administrateur : éprouve en `GOVERNANCE` d'abord, bascule ensuite.
- Conservation : **un an** pour l'audit (exigence HDS/ISO et argumentée au M22-E13). Les journaux applicatifs (diagnostic) gardent leur rétention courte : ne les confonds pas avec l'audit.
- Intégrité : la centralisation ne suffit pas (qui garde Loki peut altérer Loki). Il faut une preuve **indépendante** : condensats en chaîne, ou manifeste signé (`transit` d'OpenBao / Cosign), déposé dans l'archive verrouillée.

**Travail demandé**

Objectifs :
1. **Acheminer** les six familles de journaux d'audit vers le locataire `audit` de Loki, par le code de `plateforme/observabilite` et `plateforme/ansible` (Alloy, pas de collecte manuelle). Chaque source garde une étiquette qui l'identifie (`job`/`service`).
2. **Horodater** de façon cohérente : vérifie que chaque source émet un horodatage fiable et que l'étape `timestamp` d'Alloy s'en sert ; documente la source de temps.
3. **Archiver** le locataire `audit` vers un compartiment RGW **en verrouillage d'objets**, versionné, rétention **un an**, par un travail planifié (pipeline du runner protégé ou CronJob) ; l'archive est écrite une fois par période et ne peut plus être modifiée.
4. **Prouver l'intégrité** : un contrôle qui, pour une période donnée, recalcule le condensat de l'archive et le compare à un manifeste **signé** déposé à part ; un échec est une alerte.
5. **Conserver et minimiser** : rétention `audit` d'un an dans Loki **et** dans l'archive ; écris la politique dans `docs/conformite/` (ce qu'on garde, combien de temps, pourquoi, et pourquoi pas plus).
6. **Fermer ECA-3601** : mets à jour `docs/conformite/ecarts/ECA-3601.md` (statut clos, preuve collectée par `ms-preuves`, date) et le plan de remédiation.

Contraintes :
- Aucune valeur de secret dans le locataire `audit` ni dans l'archive (vérifie la politique d'audit de l'API et le HMAC d'OpenBao).
- L'archive doit résister à une tentative de suppression par un compte administrateur une fois en `COMPLIANCE` : c'est le cœur de l'écart.
- Rien à la main sur les hôtes ni dans Loki : tout par MR et CI.

Livrables : MR dans `plateforme/observabilite`, `plateforme/ansible` (et `plateforme/k8s` si CronJob) ; `docs/conformite/journaux-audit.md` ; `ECA-3601` clos avec preuve.

**Critères de réussite**
- [ ] Le locataire `audit` de Loki contient des lignes récentes des six sources (Kubernetes, OpenBao, Keycloak, GitLab, Proxmox, FreeIPA), chacune avec une étiquette de source.
- [ ] Un compartiment RGW en verrouillage d'objets (versionné, rétention ≥ 1 an) reçoit l'archive de l'audit par un travail planifié ; une tentative de suppression d'un objet sous `COMPLIANCE` échoue.
- [ ] Un contrôle d'intégrité (manifeste signé + recalcul de condensat) existe, est automatisé, et passe au rouge si un objet d'archive est modifié.
- [ ] `docs/conformite/journaux-audit.md` décrit sources, horodatage, archive, intégrité, conservation ; `ECA-3601` est clos sur `main` avec sa preuve.

**Vérification** : `lab/bin/check F6 8`

<details><summary>Indice 1</summary>

« Centralisé » et « inaltérable » sont deux propriétés différentes. Loki centralise, mais celui qui administre Loki peut en principe réécrire un segment. L'inaltérabilité vient du **verrouillage d'objets** du RGW (le même mécanisme que `preuves-conformite`, F6-S02) : une fois un objet écrit en mode `COMPLIANCE` avec une échéance, personne ne peut le supprimer ni le remplacer avant cette échéance. L'archive, pas Loki, est la preuve.
</details>

<details><summary>Indice 2</summary>

Pour que l'archive **prouve**, il faut pouvoir montrer qu'elle correspond bien aux journaux de la période et qu'elle n'a pas été tronquée. Un manifeste par période (liste des objets, leurs condensats SHA-256, la période couverte, le nombre de lignes) signé par `transit` d'OpenBao (M25) ou Cosign, déposé lui aussi dans l'archive verrouillée, donne cette preuve : le contrôle recalcule et compare, la signature atteste qui a produit le manifeste.
</details>

<details><summary>Indice 3</summary>

OpenBao, Keycloak, GitLab, FreeIPA : regarde d'abord ce que chacun sait **émettre** nativement avant d'écrire du code. `bao audit enable`, l'écouteur d'événements de Keycloak, `audit_json.log` de GitLab, le greffon d'audit de 389-ds. Ensuite seulement, une cible de fichier dans Alloy sur l'hôte concerné, comme la cible `audit` du M22 pour l'API Kubernetes.
</details>

**Pour aller plus loin** (facultatif) : une alerte « trou de journalisation » (aucune ligne d'une source pendant N minutes = un collecteur muet ou une source coupée, un angle mort d'audit) ; la différence entre `GOVERNANCE` et `COMPLIANCE` du point de vue d'un auditeur (qui peut lever un verrou `GOVERNANCE`, et pourquoi `COMPLIANCE` ne se teste jamais sur des vraies données la première fois).

---

### F6-S09 — Vulnérabilités et exceptions sous contrôle  `LIBRE` `★★★`

> **Ticket SEC-3609** — *De : Sophie Laurent (RSSI)* — *Copie : Karim Benali, Julien Petit*
> Deux écarts dans le même sujet. **ECA-3602** : on détecte les vulnérabilités (Trivy, Harbor), mais on n'a écrit nulle part **sous combien de temps** on doit corriger une critique, et nos « exceptions » sont des lignes de tableur qui ne meurent jamais. **ECA-3603** : nos sauvegardes Velero et nos exports ne sont **pas chiffrés côté serveur** — un administrateur du stockage objet lit des données de santé en clair. Hélène veut une politique de traitement avec des **délais par criticité**, des **exceptions datées qui expirent toutes seules**, un **tableau de suivi** qui dit ce qui est en retard, et le **chiffrement** de ce qui sort du cluster. Code-le, ne me fais pas une note.

**Objectifs pédagogiques**
- Définir une politique de gestion des vulnérabilités opérationnelle : délais par criticité, mesure du retard, exceptions à durée de vie bornée.
- Rendre les exceptions auto-expirantes (le mécanisme refuse de lui-même une exception échue) et suivies.
- Chiffrer les sauvegardes et exports côté serveur, et savoir où est la clé.

**Prérequis** : F6-S01 à F6-S07 ; M13 (Trivy, Harbor, politique « images vulnérables », `cve_allowlist`), M26 (registre des exceptions `EXC-…`, `PolicyException` Kyverno, RB-261), M16 (Velero/Kopia, planifications), M25 (OpenBao `transit`, chiffrement). F6-S02 (`ms-preuves`).
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Détection déjà en place : Harbor bloque au tirage les images avec une critique (M13) ; la chaîne CI bloque les critiques **corrigeables** (`--ignore-unfixed`) ; Trivy Operator (cité au M26) peut produire des `VulnerabilityReport` dans le cluster. Ce qui manque, c'est la **politique de traitement** : rien ne dit qu'une critique doit être corrigée en X jours.
- Délais : à toi de les fixer et de les justifier (ordre de grandeur attendu par les référentiels : critique quelques jours, élevée quelques semaines, moyenne un trimestre). Le **retard** se mesure : date de première détection → aujourd'hui.
- Exceptions : le registre `EXC-…` et les `PolicyException` Kyverno du M26 portent déjà un champ d'échéance (`expiresAt`) et un pipeline qui échoue 14 jours avant l'échéance. Étends ce mécanisme aux **exceptions de vulnérabilité** (une critique acceptée temporairement, ex. sans correctif disponible) : l'exception doit cesser de s'appliquer d'elle-même à sa date, et apparaître dans le suivi.
- ECA-3603 : **Velero** (`velero-k8s-par1`, M16, Kopia) et les exports (dumps, archives déposées sur `s3-01` / RGW). « Chiffré côté serveur » = le stockage objet ne voit que du chiffré. Deux voies : chiffrement du dépôt Kopia de Velero (phrase/clé), ou chiffrement applicatif de l'export avant dépôt (`age`, clé dans OpenBao) ; décide et écris où est la clé et qui peut déchiffrer.
- Suivi : un tableau (Grafana, ou un rapport généré par pipeline) qui liste, par image/charge, les vulnérabilités ouvertes, leur criticité, leur âge, l'échéance de traitement, et ce qui est **en retard** — c'est ce qu'on montre à l'auditeur.

**Travail demandé**

Objectifs :
1. **Politique** `docs/conformite/vulnerabilites.md` : délais de traitement par criticité (justifiés), mesure du retard, circuit d'exception (qui valide, durée maximale, compensation), et le lien avec les blocages déjà en place (Harbor, CI).
2. **Exceptions datées** : un mécanisme d'exception de vulnérabilité **auto-expirant** (par ex. `cve_allowlist` de Harbor avec une date d'expiration, ou une `PolicyException`/annotation avec `expiresAt` et un contrôle CI qui la rejette une fois échue), relié au registre `EXC-…` (identifiant des deux côtés).
3. **Tableau de suivi** : vulnérabilités ouvertes par criticité et par âge, échéance, retard ; alimenté par Trivy/Harbor (et/ou Trivy Operator), sans saisie manuelle.
4. **Chiffrement (ECA-3603)** : Velero/Kopia et les exports chiffrés côté serveur ; la clé dans OpenBao ; procédure de restauration/déchiffrement documentée (et **éprouvée** par une restauration d'essai).
5. **Fermer ECA-3602 et ECA-3603** : `ecarts/ECA-3602.md` et `ecarts/ECA-3603.md` clos avec preuve (`ms-preuves`), plan de remédiation à jour.

Contraintes :
- Une exception échue ne doit **jamais** continuer à s'appliquer en silence : le mécanisme la refuse, le suivi la montre en rouge.
- Les délais sont des engagements : s'ils sont irréalistes, l'auditeur le verra au premier retard. Choisis-les tenables.
- La restauration d'une sauvegarde chiffrée doit être prouvée (une sauvegarde qu'on ne sait pas déchiffrer n'est pas une sauvegarde).

Livrables : MR dans `plateforme/politiques`, `plateforme/k8s` (Velero), `plateforme/observabilite` (tableau), `plateforme/medisphere` (docs, écarts) ; `ECA-3602` et `ECA-3603` clos avec preuve.

**Critères de réussite**
- [ ] `docs/conformite/vulnerabilites.md` fixe des délais par criticité, le circuit d'exception et le lien avec Harbor/CI.
- [ ] Une exception de vulnérabilité porte une date d'expiration ; une exception datée dans le passé **ne s'applique plus** (contrôle automatisé qui le rejette).
- [ ] Un tableau de suivi montre les vulnérabilités ouvertes, leur âge et le retard par rapport aux délais, sans saisie manuelle.
- [ ] Velero (`velero-k8s-par1`) et les exports sont chiffrés côté serveur (clé dans OpenBao) ; une restauration d'essai a réussi.
- [ ] `ECA-3602` et `ECA-3603` sont clos sur `main` avec leur preuve.

**Vérification** : `lab/bin/check F6 9`

<details><summary>Indice 1</summary>

Tu as déjà presque tout le mécanisme d'exception datée : le registre `EXC-…` et les `PolicyException` Kyverno du M26 portent `expiresAt`, et un pipeline échoue 14 jours avant l'échéance. Une exception de vulnérabilité est la même idée appliquée à une CVE précise sur une image précise : identifiant au registre, échéance, compensation, et un contrôle qui refuse l'exception quand la date est passée (un job de CI qui lit la date, ou la `cve_allowlist` de Harbor avec `expires_at`).
</details>

<details><summary>Indice 2</summary>

« Côté serveur » veut dire que le stockage objet ne détient jamais le clair. Pour Velero, Kopia chiffre déjà son dépôt si tu lui donnes une phrase de passe (secret du `BackupStorageLocation` / dépôt) : la question est **où** est la phrase et qui peut la lire (OpenBao). Pour un export brut (un dump), le plus simple et le plus explicite est `age` : clé publique pour chiffrer dans le pipeline, clé privée dans OpenBao pour la restauration. Dans les deux cas, prouve que tu sais restaurer.
</details>

**Pour aller plus loin** (facultatif) : relier le retard de traitement à un SLO (« 95 % des critiques traitées dans le délai ») ; `VulnerabilityReport` de Trivy Operator exposés en métriques et comparés à l'analyse de Harbor (deux sources, un écart = un angle mort) ; rotation de la clé de chiffrement des sauvegardes et ce que cela implique pour les anciennes sauvegardes.

---

## Points non testés en conditions réelles (phase 3)

- Collecte Alloy des événements **Keycloak, GitLab, FreeIPA** vers le locataire `audit` : les formats et chemins exacts dépendent de la version et de la configuration retenues au M22/M24 ; vérifie sur ta plateforme et signale tes retours.
- Bascule `GOVERNANCE` → `COMPLIANCE` d'un compartiment RGW : à éprouver d'abord sur un compartiment jetable (un objet en `COMPLIANCE` ne se supprime plus avant l'échéance, même pour corriger une erreur de rétention).
- Chiffrement du dépôt Kopia de Velero via un secret de dépôt : champ exact selon Velero 1.18 ; à confirmer sur le lab.
