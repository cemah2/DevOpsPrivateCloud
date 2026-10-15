# Module 13 — Palier 3 : Production

Harbor tourne sur `reg01` : des projets, des robots, des caches des registres publics, des images analysées, signées, accompagnées de leur SBOM, une chaîne de livraison et Renovate. Mais tout repose sur **une** VM : si `reg01` perd son disque, MédiSphère perd toutes ses images et toutes ses signatures, et la CI s'arrête. Rien n'empêche encore de tirer une image non signée ou truffée de vulnérabilités critiques : la signature existe, personne ne l'exige. Personne ne serait prévenu si Harbor tombait cette nuit, et la version 2.15 recevra des correctifs de sécurité que quelqu'un devra appliquer sans casser la base. Claire Morel veut un registre qu'on peut **exploiter** ; Sophie Laurent veut une **politique de confiance** écrite et appliquée ; Nadia Roussel veut savoir répondre en une heure à « sommes-nous touchés ? ». Ce palier fait passer le registre en production.

> ⚠️ **Rappel** : `reg01` est désormais un service du socle. `runner02` y pousse et y tire à chaque pipeline, et le module 14 en dépendra pour démarrer chaque pod. Avant toute intervention qui redémarre Harbor (`systemctl restart harbor`, `install.sh`, `prepare`, mise à jour), vérifie qu'aucun pipeline important ne tourne (`plateforme/ci-templates`, `mediagenda/api`…), que `https://registry.par1.medisphere.internal/api/v2.0/health` répond `healthy`, et note la commande de retour arrière. **Les essais destructifs se font sur `reg02`**, jamais sur `reg01`.

**Chemin imposé** (introduction du module) : la VM est décrite par OpenTofu (`plateforme/infra`, module `vm-debian`, comme `reg01` en E02) ; Harbor est installé et configuré par le rôle Ansible `harbor` (`plateforme/ansible`) ; les objets de Harbor (projets, robots, politiques, endpoints, réplications) sont décrits dans le **code de configuration de Harbor** mis en place en M13-E03 (le corrigé utilise OpenTofu et le fournisseur `goharbor/harbor` dans `plateforme/infra/registre/` ; garde l'outil que tu as retenu en E03). Tout flux qui traverse les passerelles est déclaré dans `group_vars/role_routeur/pare_feu.yml` et dans `docs/socle/matrice-flux.md`. Les secrets (mots de passe de Harbor, secrets des robots, clés Cosign, clés de chiffrement des sauvegardes) sont en Ansible Vault `critique` ou en variables de CI protégées et masquées, jamais en clair. La documentation va dans `docs/registre/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`).

**Hôtes de ce palier**

| Hôte | VMID | Réseau | Rôle | Exercice |
|---|---|---|---|---|
| `reg01` | 1013 | INFRA 10.10.20.18 | Harbor de production (`registry.par1.medisphere.internal`) | — |
| `reg02` | 2131 | SANDBOX **10.10.99.31** (statique, `reg02.par1.medisphere.internal`) | Harbor de test : réplication, restauration, répétition des mises à jour | E13, détruite en E25 |

`reg02` : 2 vCPU, 4 Go, disque système 32 Go et disque de données de 64 Go (`local-nvme`, numéro de série `reg02-donnees`, monté sur `/data` par le rôle `harbor`), étiquettes `env-m13` et `role-registre`, état OpenTofu `m13-registre` (`plateforme/infra/envs/m13/`). Comme pour `reg01`, l'adresse est imposée (`ipv4_imposee`) : on prend `.31`, dans la plage des adresses statiques de SANDBOX (PLAN §4.2), plutôt qu'une adresse DHCP, pour que la règle de bordure vise une seule adresse ; l'enregistrement DNS est créé par le même code.

**Fichiers de vérification** : les contrôles se lancent depuis `adm01` (`lab/bin/check 13 XX`). À partir de E13, ils lisent aussi `reg02` avec un robot système en lecture **sur `reg02`** : fichier `~/.config/workbook/harbor-reg02-checks.env` (mode 600, `HARBOR_USER=` et `HARBOR_PASSWORD=`, même format que `harbor-checks.env`, M13-E03).

**Ordre conseillé** : E13 → E14 → E15 → E16 → E17 → E18. La réplication (E13) fournit à `reg02` des images signées que la restauration (E15) écrasera ; la sauvegarde (E15) précède la mise à jour (E16), qui en a besoin pour son retour arrière. **Durée totale indicative** : 12 à 16 h.

---

### M13-E13 — Répliquer vers un second registre  `LAB` `★★★`

> **Ticket PLAT-1431** — *De : Claire Morel*
> Le comité HDS a lu notre analyse de risques : « registre unique, perte totale en cas de sinistre ». Avant la vraie copie à PAR2, je veux qu'on sache faire et qu'on mesure : un **second Harbor** qui reçoit chaque nuit les versions publiées de MédiSphère, **avec leurs signatures**, et qu'on puisse vérifier là-bas sans rien demander à `reg01`. Karim veut que ce second Harbor soit installé par exactement le même rôle que le premier : s'il faut des retouches à la main, c'est que le rôle est incomplet.

**Objectifs pédagogiques**
- Installer une seconde instance de Harbor par le code (OpenTofu + rôle `harbor`) et mesurer ce que le rôle supposait implicitement.
- Comprendre la réplication de Harbor : endpoint, sens (*push* / *pull*), filtres, déclencheurs, écrasement, propagation des suppressions, accessoires.
- Vérifier qu'une signature Cosign (référent OCI) voyage avec l'image et reste vérifiable sur la copie.

**Prérequis** : M13-E02, M13-E03 (code de configuration de Harbor, robots), M13-E07 (signature), M13-E09 (images `medisphere/*` publiées en `vX.Y.Z`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `reg02` : voir le tableau ci-dessus. Même version de Harbor que `reg01`, même rôle, `hostname` `reg02.par1.medisphere.internal`, certificat ACME de step-ca pour ce nom (même méthode qu'en E02).
- Réplication **en poussée** depuis `reg01` : le trafic part de `reg01` (10.10.20.18) vers `reg02` en 443. Les VLAN INFRA et SANDBOX ne se joignent pas par défaut (M00) : le flux est à ouvrir de façon ciblée, et il est **temporaire** (retiré au mini-projet). Les autres flux dont `reg02` a besoin (Internet pour l'installation, ACME) sont à identifier à partir de ce que tu as ouvert pour `reg01` en E02.
- Sur `reg02`, le projet de destination `medisphere` est privé ; la réplication s'y authentifie avec un robot **de `reg02`** dédié à cet usage, aux droits minimaux. Son secret va en Vault `critique`.
- Le certificat de `reg02` est émis par la PKI MédiSphère : `reg01` doit lui faire confiance **sans** désactiver la vérification TLS (Harbor 2.15 accepte un certificat d'autorité par endpoint).
- Politique attendue : nom `medisphere-vers-reg02`, ressources `medisphere/**`, étiquettes `v*` seulement, planifiée chaque nuit à 03:15 (les expressions *cron* de Harbor ont **six** champs, secondes en tête), sans propagation des suppressions.

> ⚠️ **Attention** : une politique de réplication mal filtrée peut pousser des centaines d'images (y compris les caches publics) vers `reg02` et remplir son disque. Lance d'abord une exécution **manuelle**, regarde la liste des tâches, puis seulement active la planification. Ne crée jamais de politique en sens inverse (*pull* depuis `reg02` vers `reg01`) : `reg02` n'est pas une source de confiance.

**Travail demandé**
1. **La VM.** Décris `reg02` dans `plateforme/infra/envs/m13/` (état `m13-registre`) avec les modules `vm-debian` et `enregistrement-dns` (même modèle que `infra/socle/reg01.tf`). Crée-la par MR et pipeline.
2. **Les flux.** Ajoute à `group_vars/role_routeur/pare_feu.yml` les règles nécessaires à `reg02`, commentées « M13, temporaire », et reporte-les dans `docs/socle/matrice-flux.md`.
3. **Harbor sur `reg02`.** Applique le rôle `harbor` (`host_vars/reg02/`), sans aucune action manuelle sur la VM. Note dans la description de la MR ce que tu as dû ajouter au rôle ou à l'inventaire pour qu'une seconde instance fonctionne (noms, certificats, secrets, variables qui avaient une valeur en dur).
4. **Côté `reg02`.** Dans le code de configuration de Harbor (une seconde configuration de fournisseur, ou un second état, pointant sur `reg02`) : projet `medisphere` (privé, immuabilité `v*`), robot de réplication, robot système `wb-checks` en lecture (comme sur `reg01`) ; crée `~/.config/workbook/harbor-reg02-checks.env`.
5. **Côté `reg01`.** Décris l'endpoint `reg02` (type `harbor`, certificat d'autorité MédiSphère) et la politique `medisphere-vers-reg02`. Teste la connexion de l'endpoint, puis lance une exécution manuelle et lis le détail des tâches : quelles images, quels accessoires, combien d'octets ?
6. **Vérifie sur la copie.** Depuis `adm01`, sans passer par `reg01` : le digest d'une image `medisphere/mediagenda-api:vX.Y.Z` est-il identique sur les deux registres ? Vérifie sa signature avec `cosign verify` contre `reg02` et la clé publique MédiSphère (mêmes options qu'en E07 pour l'absence de journal de transparence). Liste les référents de l'image sur `reg02` (`cosign tree` ou l'interface).
7. **Mesure.** Publie une nouvelle version de MédiAgenda, attends la nuit (ou déclenche la politique) et note le délai entre la publication et la disponibilité signée sur `reg02` : c'est ton RPO pour les images. Écris-le dans `docs/registre/replication.md` avec le sens, les filtres, ce qui n'est **pas** répliqué (caches, robots, membres, politiques, historique des analyses) et pourquoi.

**Critères de réussite**
- [ ] `reg02` existe (VMID 2131, 10.10.99.31, `reg02.par1.medisphere.internal`), Harbor y répond `healthy` en HTTPS avec un certificat de la PKI MédiSphère.
- [ ] Sur `reg01`, l'endpoint `reg02` est de type `harbor`, vérifie le certificat (pas de mode `insecure`) et est en état `healthy`.
- [ ] La politique `medisphere-vers-reg02` est active, planifiée, filtrée sur `medisphere/**` et `v*`, sans propagation des suppressions ; sa dernière exécution a réussi.
- [ ] Sur `reg02`, la dernière version `v*` de `medisphere/mediagenda-api` a le **même digest** que sur `reg01` et porte une signature Cosign ; `cosign verify` contre `reg02` réussit.
- [ ] Les flux de `reg02` sont dans la matrice (Ansible et documentation) ; `docs/registre/replication.md` donne le RPO mesuré.

**Vérification** : `lab/bin/check 13 13`

<details><summary>Indice 1</summary>

Dans Harbor, une réplication s'appuie sur deux objets distincts : un **endpoint** (Administration → Registries, API `/registries`) qui dit où et avec quelle identité, et une **règle** (API `/replication/policies`) qui dit quoi, quand et comment. Le bouton « Test connection » de l'endpoint (API `/registries/ping`) te dit tout de suite si c'est un problème de réseau, de TLS ou d'identifiants.
</details>

<details><summary>Indice 2</summary>

Lis la page *Configuring Replication* de la documentation de Harbor 2.15 et le schéma de la ressource de réplication de ton outil de configuration : filtres `name`, `tag`, `label`, `resource`, options `override`, `deletion`, `dest_namespace`. Pour le robot de `reg02`, demande-toi de quelles actions la réplication a besoin sur le projet de destination (lister, pousser, et rien d'autre).
</details>

<details><summary>Indice 3</summary>

Si les images arrivent sur `reg02` sans leurs signatures, regarde dans le détail des tâches si les accessoires ont été traités, et compare `cosign tree` sur les deux registres. Une signature Cosign 3 est un artefact référent de l'image, rattaché par son digest : elle n'a pas d'étiquette, un filtre d'étiquettes ne la sélectionne donc pas pour elle-même.
</details>

**Pour aller plus loin** : compare le temps et le volume d'une réplication avec et sans `copy_by_chunk` ; lis comment Harbor traite une réplication vers un registre qui ne connaît pas les référents OCI 1.1 (Distribution 2.x).

---

### M13-E14 — Politiques : signature obligatoire, vulnérabilités bloquantes  `LAB` `★★★`

> **Ticket SEC-1432** — *De : Sophie Laurent*
> On signe, on analyse, on produit des SBOM : bravo. Mais aujourd'hui, n'importe quelle image poussée dans `medisphere` peut être tirée, signée ou pas, avec ou sans vulnérabilité critique. Une signature que personne ne vérifie ne protège de rien. Je veux deux verrous : **le registre refuse** de servir une image de `medisphere` non signée ou porteuse d'une vulnérabilité critique, et **le consommateur vérifie lui-même** la signature avec notre clé avant de déployer. Montre-moi les deux refus.

**Objectifs pédagogiques**
- Configurer les politiques de projet de Harbor : signature Cosign exigée, prévention des images vulnérables (seuil), analyse automatique, liste blanche de CVE.
- Comprendre ce que ces politiques vérifient **vraiment** (présence d'une signature, pas son auteur ; résultat d'une analyse, pas l'absence de faille) et leurs angles morts.
- Ajouter une vérification par le consommateur (`cosign verify` par digest avec la clé MédiSphère) dans un gabarit de CI réutilisable.

**Prérequis** : M13-E05 (analyse par Harbor), M13-E07, M13-E08, M13-E09.
**Durée indicative** : 2 h.

**Contexte technique**
- Politiques à poser sur `medisphere` **par le code de configuration de Harbor** : signature Cosign exigée, analyse automatique à la poussée, prévention des images de sévérité **Critical** ou plus. La liste blanche de CVE du système reste vide ; une exception éventuelle est posée au niveau du projet, avec une date d'expiration et un ticket.
- Clé publique : `docs/registre/cosign.pub` de `plateforme/medisphere` (M13-E07).
- Gabarit à créer : `verification.yml` dans `plateforme/ci-templates`, qui fournit un job caché `.verifier-signature` (variables d'entrée : l'image **par digest**, la clé publique) ; utilisé dans le pipeline de `mediagenda/api` par un job `verifier-signature` qui suit la publication. Ce job préfigure la vérification avant déploiement du module 14.
- Image de test vulnérable : n'importe quelle vieille image publique tirée par le cache `dockerhub` (une image Debian ou Python de plusieurs années en a toujours). Les essais se font dans un dépôt `medisphere/essai-politiques`, **supprimé** à la fin.

> ⚠️ **Attention** : dès que la signature est exigée, **toute** image non signée de `medisphere` devient intirable, y compris celles que `runner02` ou un poste utilise aujourd'hui. Avant d'activer la politique, liste les artefacts de `medisphere` sans signature (API, `with_accessory=true`) et signe ou supprime-les. Retour arrière : désactiver la politique par le code (une MR), jamais à la main dans l'interface.

**Travail demandé**
1. **Inventaire.** Liste les artefacts de `medisphere` : étiquette, digest, signature présente ou non, résultat d'analyse. Traite ceux qui ne passeraient pas les politiques.
2. **Politiques.** Pose les trois réglages sur `medisphere` par une MR sur le code de configuration de Harbor. Vérifie-les dans l'interface et par l'API (`/projects/medisphere`, champ `metadata`).
3. **Refus n° 1 — non signée.** Pousse une image dans `medisphere/essai-politiques:non-signee`, laisse l'analyse se terminer, puis tente de la tirer depuis `adm01` (`skopeo inspect` ou `docker pull`). Note le code HTTP et le message. Signe-la par digest et retire-la.
4. **Refus n° 2 — vulnérable.** Copie une vieille image publique dans `medisphere/essai-politiques:vulnerable` (par exemple avec `skopeo copy` depuis le cache), **signe-la**, attends l'analyse et tente de la tirer. Note le message. Explique pourquoi une image *non encore analysée* est, elle aussi, refusée.
5. **Ce que la politique ne voit pas.** Signe une image avec une **autre** clé (une paire jetable générée pour l'essai) et tente de la tirer. Que conclus-tu de ce que vérifie Harbor ? Qui doit vérifier l'**auteur** de la signature ?
6. **Le consommateur.** Écris `verification.yml` dans `plateforme/ci-templates` : le job vérifie la signature **et** l'attestation SBOM de l'image par digest, avec la clé MédiSphère, sans journal de transparence, et échoue sinon. Branche-le dans `mediagenda/api` après la publication. Prouve qu'il échoue sur l'image signée par la clé jetable (pipeline de branche) et réussit sur une image signée par la CI.
7. **Nettoyage et trace.** Supprime le dépôt `medisphere/essai-politiques` et la clé jetable. Ajoute à `docs/registre/politiques.md` : les politiques par projet, ce qu'elles vérifient, leurs limites, la procédure d'exception (liste blanche datée), et les deux messages de refus.

**Critères de réussite**
- [ ] Le projet `medisphere` exige une signature Cosign, analyse à la poussée et refuse les images de sévérité Critical ou plus.
- [ ] La dernière version `v*` de `medisphere/mediagenda-api` est signée et son analyse ne signale aucune vulnérabilité critique.
- [ ] Le dépôt `medisphere/essai-politiques` n'existe plus.
- [ ] `plateforme/ci-templates` contient `verification.yml` (vérification Cosign par clé) ; le dernier pipeline de `main` de `mediagenda/api` a réussi un job `verifier-signature`.
- [ ] `docs/registre/politiques.md` est publié avec les deux messages de refus et la procédure d'exception.

**Vérification** : `lab/bin/check 13 14`

<details><summary>Indice 1</summary>

Les politiques sont des **métadonnées de projet** dans l'API de Harbor (`enable_content_trust_cosign`, `prevent_vul`, `severity`, `auto_scan`…) ; ton outil de configuration les expose sous d'autres noms. Une image refusée par une politique de projet répond `412 Precondition Failed` avec un message qui nomme la politique.
</details>

<details><summary>Indice 2</summary>

Le scanner (Trivy) et le moteur de signature ont le droit de lire une image que la politique refuse : sinon, une image non signée ne pourrait jamais être analysée ni signée. Pour le job du consommateur, pense à ce que `cosign verify` doit recevoir (une référence par digest, la clé, l'option qui renonce au journal de transparence) et à ce que `cosign verify-attestation` ajoute (`--type`).
</details>

<details><summary>Indice 3</summary>

Pour l'étape 5, compare ce que renvoie l'API pour l'artefact (ses accessoires et leur type) selon la clé utilisée. La réponse à « qui vérifie l'auteur ? » est l'objet de l'étape 6 et, pour Kubernetes, du module 26.
</details>

**Pour aller plus loin** : lis la documentation de la politique de signature de Harbor pour Notation et compare ; regarde comment une politique d'admission Kubernetes (Kyverno `verifyImages`, module 26) vérifiera la clé au moment du déploiement.

---

### M13-E15 — Sauvegarder et restaurer Harbor  `LAB` `★★★`

> **Ticket PLAT-1433** — *De : Nadia Roussel*
> La réplication, c'est bien, mais elle recopie aussi les erreurs : une image supprimée par erreur sur `reg01` reste sur `reg02` seulement parce qu'on a désactivé la propagation des suppressions, et ni les robots, ni les politiques, ni les membres ne sont copiés. Je veux une **vraie sauvegarde** de `reg01` vers PBS, chaque nuit, et la preuve qu'on sait **reconstruire Harbor à partir de rien** avec elle. Chronomètre : je veux un RTO écrit, pas une impression.

**Objectifs pédagogiques**
- Identifier ce qui constitue l'état de Harbor : base PostgreSQL, stockage des blobs, clés de chiffrement, configuration, certificats ; ce qui n'en fait pas partie (cache Valkey, base de Trivy, journaux).
- Sauvegarder de façon cohérente un service en fonctionnement (`pg_dump` dans le conteneur `harbor-db`, puis les blobs) vers PBS, chiffré côté client.
- Restaurer réellement sur une instance reconstruite depuis zéro, et vérifier ce qui compte : projets, robots, images, signatures.

**Prérequis** : M13-E13 (`reg02`), M06-E28 (sauvegarde applicative vers PBS, rôle `sauvegarde_pbs`), M08-E25 (sauvegarde hors du cluster) ; `pbs01` accessible.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Harbor (installateur hors ligne) range ses données sous `data_volume` (`/data` sur `reg01`, disque de 200 Go) : `database/` (fichiers PostgreSQL, sous-dossier par version majeure), `registry/` (blobs et manifestes), `secret/` (clés : notamment `secret/keys/secretkey`, qui chiffre en base les identifiants des endpoints de réplication, et le certificat présenté par le proxy), `redis/`, `trivy-adapter/`, `job_logs/`. La configuration est dans `harbor.yml` (rendu par le rôle) et le dossier d'installation.
- Le conteneur de la base s'appelle `harbor-db` ; la base de Harbor s'appelle `registry`, propriété de l'utilisateur `postgres`.
- PBS : datastore `ds-lab`, espace de noms **`par1/registre`**, identifiant de sauvegarde `reg01`, jeton dédié `wb-backup@pbs!reg01` (mêmes conventions qu'en M06-E28 ; jeton, empreinte et clé de chiffrement en Vault `critique`). Passage chaque nuit à **01:40**, avant la réplication de 03:15.
- Rôle Ansible à écrire : **`sauvegarde_harbor`** (script `/usr/local/sbin/wb-backup-harbor.sh`, unités `wb-backup-harbor.service` et `.timer`, `OnFailure=ms-alerte@%n.service`). Flux `reg01` → `pbs01` : 8007 à travers la bordure, comme pour les autres sauvegardes applicatives.
- Restauration de test : sur `reg02`, **détruite puis recréée** par OpenTofu, Harbor réinstallé par le rôle dans la **même version** que `reg01`.

> ⚠️ **Attention** : (1) la restauration écrase tout le contenu de `reg02` : c'est voulu, mais ne la lance **jamais** sur `reg01` dans cet exercice. (2) Une instance restaurée contient les politiques de réplication de `reg01`, dont `medisphere-vers-reg02` : sur `reg02`, elle pointerait vers elle-même, et toute politique planifiée se déclencherait à l'heure dite. Désactive les politiques restaurées **avant** de redémarrer Harbor complètement. (3) Les identifiants des robots restaurés sont ceux de production : `reg02` restaurée est aussi sensible que `reg01` tant qu'elle existe.

**Travail demandé**
1. **Inventaire.** Pour chaque sous-dossier de `/data` et pour la configuration, décide : sauvegardé, régénérable, ou inutile. Justifie l'ordre « base d'abord, blobs ensuite » et ce que le ramasse-miettes change pendant la sauvegarde.
2. **Le rôle.** Écris `sauvegarde_harbor` : vidage de la base par `pg_dump` (format personnalisé) **dans** le conteneur `harbor-db`, contrôle du vidage (`pg_restore --list`), archives PBS des blobs, des clés, de la configuration et du vidage, chiffrement côté client, nettoyage du dossier de travail quoi qu'il arrive, code retour non nul au moindre échec. Pas de copie brute de `/data/database` à chaud.
3. **Planifie** et lance une première sauvegarde ; constate-la sur `pbs01` (`par1/registre`) et note sa durée et sa taille (avant et après déduplication).
4. **Reconstruis `reg02` depuis zéro** : `tofu destroy` puis `apply` de `reg02`, rôle `harbor` dans la version de `reg01`. Démarre le chronomètre.
5. **Restaure** les archives sur `reg02` : blobs et clés, puis la base dans un conteneur `harbor-db` seul démarré ; désactive les politiques de réplication restaurées ; démarre Harbor.
6. **Vérifie** sur `reg02` : projets, membres et robots de `reg01` présents ; une image `medisphere/*` se tire avec le robot de la CI ; `cosign verify` réussit ; l'endpoint de réplication restauré a encore ses identifiants (preuve que la bonne clé a été restaurée). Arrête le chronomètre.
7. Écris `docs/registre/sauvegarde.md` (ce qui est sauvegardé, où, comment, ce qui ne l'est pas) et `docs/registre/tests/restauration-harbor.md` (date, durées de chaque étape, **RTO** et **RPO**, écarts), puis le runbook `RB-131 — Restaurer Harbor` dans `docs/registre/runbooks/`.
8. **Remets `reg02` dans son rôle de cible** : vide-la (reconstruction par le code) et rejoue E13, ou justifie de la garder restaurée jusqu'à E16 en ayant désactivé tout ce qui pouvait agir.

**Critères de réussite**
- [ ] Sur `reg01`, `wb-backup-harbor.timer` est actif à 01:40 ; le dernier passage du service a réussi ; les secrets PBS de `reg01` sont `root:root` en 600.
- [ ] Sur `pbs01`, l'espace de noms `par1/registre` contient une sauvegarde de moins de 48 h avec l'archive des blobs et celle du vidage de la base.
- [ ] Le script n'a lu `/data/database` que par `pg_dump` (aucune archive des fichiers PostgreSQL).
- [ ] La restauration a été faite sur `reg02` reconstruite : `restauration-harbor.md` donne le RTO et le RPO ; RB-131 est publié.
- [ ] Sur `reg02`, aucune politique de réplication restaurée n'est active vers elle-même.

**Vérification** : `lab/bin/check 13 15`

<details><summary>Indice 1</summary>

La page *Back Up and Restore Harbor* (et la procédure de mise à jour, qui commence par une sauvegarde) de la documentation de Harbor dit quels dossiers comptent. `docker exec harbor-db pg_dump --help` te donne les options dans la version de PostgreSQL embarquée ; le flux de sortie de `docker exec` peut être redirigé vers un fichier de l'hôte.
</details>

<details><summary>Indice 2</summary>

Dans le `docker-compose.yml` généré par `prepare`, le service de la base n'a pas le même nom que son conteneur : regarde-le pour démarrer la base seule (`docker compose up -d <service>`). Pour restaurer une base, il faut qu'aucun autre composant ne s'y connecte.
</details>

<details><summary>Indice 3</summary>

Si les robots marchent après restauration mais que l'endpoint de réplication restauré échoue en « unauthorized » ou ne se déchiffre pas, il manque un fichier de `secret/`. Si Harbor démarre mais que tous les tirages renvoient `blob unknown`, compare la base et les blobs : lequel a été restauré, depuis quelle sauvegarde ?
</details>

**Pour aller plus loin** : mesure le temps d'une restauration de la seule base (sans les blobs, qui seraient répliqués) et discute une stratégie mixte « blobs par réplication, base par sauvegarde » pour PAR2 ; regarde ce que la sauvegarde VM de PBS (`par1/socle`) apporte ou non en complément.

---

### M13-E16 — Superviser et mettre à jour Harbor  `LAB` `★★★`

> **Ticket CHG-1434** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Deux choses. Nadia veut une sonde comme pour Ceph : Harbor qui tombe, un disque `/data` qui se remplit, une réplication ou une sauvegarde qui échoue, un certificat qui expire — elle veut le savoir avant les développeurs. Et Harbor publie des correctifs de sécurité tous les mois : on doit savoir appliquer une version corrective **sans perdre la base** et **revenir en arrière** si ça tourne mal. Répète sur `reg02`, applique sur `reg01` dans une fenêtre annoncée.

**Objectifs pédagogiques**
- Lire l'état de Harbor : point de santé de l'API, métriques de l'exportateur, journaux des composants (`/var/log/harbor/`).
- Écrire une sonde de service dans la lignée des `ms-verif-*` et la brancher sur l'alerte.
- Appliquer une mise à jour corrective de Harbor selon la procédure officielle (sauvegarde, migration de `harbor.yml` par `prepare migrate`, installation, migration du schéma au démarrage) et la défaire.

**Prérequis** : M13-E15 (sauvegarde), M08-E24 (modèle `ms-verif-ceph`), M06-E29 (`ms-alerte@`), M02-E20 (`lib/ms-commun.sh`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Santé : `GET /api/v2.0/health` (sans authentification) rend un état global et l'état de chaque composant.
- Métriques : la section `metric` de `harbor.yml` (désactivée par défaut) fait servir par le proxy des métriques Prometheus sur le **port 9090**, chemin `/metrics`, en HTTP. Le rôle `harbor` la pilote par les variables `harbor_metriques` et `harbor_metriques_port` (E02). `adm01` (MGMT) joint `reg01` sans règle supplémentaire ; aucun autre VLAN n'a besoin de ce port avant le module 21.
- Sonde **`ms-verif-registre`** dans `plateforme/outils` (`bin/`, `etc/ms-verif-registre.conf` installée sous `/usr/local/etc`, tests `bats`, unités `ms-verif-registre.service` et `.timer`, toutes les 5 minutes, sur `adm01`, utilisateur `admin`). Mêmes codes retour que les autres sondes : 0, 1 (anomalie **ou contrôle impossible**), 2 (usage). Elle lit l'API de Harbor avec **son propre** robot système en lecture (`robot$supervision`, secret dans `/usr/local/etc/ms-verif-registre.secret`, `admin:admin` 600), jamais avec le robot `wb-checks` du workbook : une sonde de production ne dépend pas des outils de formation.
- Mise à jour : de la version installée vers la **dernière version corrective 2.15.x** publiée (vérifie sur la page des versions de Harbor ; au 8 octobre 2026, 2.15.3). Si `reg01` est déjà à jour, répète la procédure sur `reg02` installée **dans la version précédente** (2.15.2 au moment de la rédaction), puis applique-la à `reg01` à la prochaine version. Rappel : 2.15.2 a fait passer la base embarquée de PostgreSQL 15 à 18 au démarrage (PLAN §6, annexe des versions).

> ⚠️ **Attention** : une mise à jour arrête Harbor pendant plusieurs minutes et migre le schéma de la base **sans retour possible autre que la restauration**. Sur `reg01` : sauvegarde du jour vérifiée (E15), fenêtre annoncée à Julien et Nadia, aucun pipeline en cours, archive du dossier d'installation et copie de `/data/database` faites **à l'arrêt**. Ne supprime l'ancien dossier d'installation et ses images qu'après une semaine sans incident.

**Travail demandé**
1. **Observer.** Lis la réponse de `/api/v2.0/health`, la liste des conteneurs (`docker compose ps` dans le dossier d'installation) et les journaux de `/var/log/harbor/` : quel composant écrit quoi ? Arrête le conteneur `harbor-jobservice` sur **`reg02`** : que deviennent la santé et les réplications ? Redémarre-le.
2. **Métriques.** Active les métriques par le rôle, puis depuis `adm01` repère : l'état de chaque composant, l'occupation de stockage par projet, le volume total, le nombre de tirages par projet. Lequel de ces chiffres te prévient d'un `/data` qui se remplit ?
3. **La sonde.** Écris `ms-verif-registre` : santé globale et de chaque composant ; métriques joignables ; occupation de `/data` sous un seuil (80 % par défaut, lue par SSH en lecture ou par l'API `systeminfo/volumes`) ; dernière exécution de chaque politique de réplication active réussie et datée de moins de 26 h ; dernier passage du ramasse-miettes réussi ; certificat de `registry.par1.medisphere.internal` valide plus de 10 jours et vérifié par la racine MédiSphère ; version de Harbor égale à celle attendue (configuration). Tests `bats` avec au moins un test rouge par contrôle. Installe-la, planifie-la, et prouve la chaîne d'alerte en arrêtant `harbor-jobservice` sur `reg01` **cinq minutes** dans une fenêtre calme.
4. **Répétition sur `reg02`.** Version N-1 installée par le rôle, quelques images répliquées : déroule la procédure officielle de mise à jour (arrêt, sauvegarde du dossier d'installation et de la base, nouvelle archive vérifiée par sa somme, `prepare migrate` de `harbor.yml`, installation avec Trivy), en relevant chaque commande et sa durée. Vérifie : version, santé, images, signatures, analyses.
5. **Retour arrière sur `reg02`.** Reviens à N-1 (ancien dossier et base sauvegardée à l'arrêt) et vérifie que tout fonctionne. Puis remonte en N.
6. **Par le code.** Écris le playbook `playbooks/harbor-mise-a-jour.yml` qui enchaîne la procédure (avec garde-fous : sauvegarde récente, refus de descendre de version, arrêt si la santé n'est pas `healthy` après coup) en s'appuyant sur le rôle `harbor` (variable `harbor_version` et garde-fou `harbor_autoriser_changement_version`, E02) ; rédige `RB-132 — Mettre à jour Harbor` avec le retour arrière.
7. **Sur `reg01`.** Applique la mise à jour dans la fenêtre annoncée si une version corrective est disponible ; sinon, écris dans RB-132 la date de la prochaine vérification.

**Critères de réussite**
- [ ] `reg01` sert des métriques Harbor sur `http://reg01.par1.medisphere.internal:9090/metrics` ; `/api/v2.0/health` rend `healthy` pour tous les composants.
- [ ] Harbor de `reg01` est dans la dernière version corrective 2.15.x attendue.
- [ ] `ms-verif-registre` est installé sous `/usr/local/bin` sur `adm01`, son timer est actif (toutes les 5 minutes) et son service déclenche `ms-alerte@` en cas d'échec ; il rend 0 sur un registre sain.
- [ ] Les tests `bats` de la sonde sont sur `main` de `plateforme/outils` et passent dans le pipeline.
- [ ] `playbooks/harbor-mise-a-jour.yml` est sur `main` de `plateforme/ansible` ; `docs/registre/tests/montee-version-harbor.md` (répétition chronométrée, retour arrière) et RB-132 sont publiés.

**Vérification** : `lab/bin/check 13 16`

<details><summary>Indice 1</summary>

La page *Upgrade Harbor and Migrate Data* de la documentation donne l'ordre exact : la migration de `harbor.yml` se fait avec l'image `goharbor/prepare` de la **nouvelle** version (`migrate -i <harbor.yml>`), la migration de la base est faite par `harbor-core` à son premier démarrage. Les métriques de l'exportateur sont décrites dans *Harbor Metrics*.
</details>

<details><summary>Indice 2</summary>

Pour la sonde : l'API de Harbor dit la date et l'état de la dernière exécution d'une réplication (`/replication/executions?policy_id=…`) et du ramasse-miettes (`/system/gc`) ; quels droits de lecture faut-il donner au robot `supervision` pour les voir ? Pour l'espace disque, `systeminfo/volumes` donne `total` et `free`.
</details>

<details><summary>Indice 3</summary>

Pour le retour arrière, demande-toi ce qui a changé de façon irréversible pendant la mise à jour : les images, les fichiers générés, et la base (schéma migré). Une copie de `/data/database` faite **à l'arrêt** avant la mise à jour est la seule chose qui ramène le schéma ; le vidage de E15 est l'autre filet.
</details>

**Pour aller plus loin** : prépare pour le module 21 la liste des alertes Prometheus que tu écrirais à partir de ces métriques (et celles qui manquent) ; lis les notes de version des trois dernières versions correctives et classe ce qu'elles corrigent.

---

### M13-E17 — ADR : registre et politique de confiance des images  `RED` `★★`

> **Ticket SEC-1435** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'auditeur HDS va demander « pourquoi Harbor ? » et « comment savez-vous qu'une image en production vient de chez vous ? ». Je veux un ADR qui réponde aux deux, que je puisse lui donner tel quel, et qui dise honnêtement ce que nous **n'avons pas** (journal de transparence, révocation…).

**Objectifs pédagogiques**
- Argumenter un choix d'outil par des critères vérifiables et des alternatives réelles.
- Formaliser une politique de confiance des images : qui signe, avec quoi, où est vérifiée la signature, que se passe-t-il quand la clé fuit.
- Écrire les conséquences et les risques acceptés, pas seulement la décision.

**Prérequis** : M13-E01 à M13-E16 ; le modèle d'ADR du dépôt (M01).
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/registre/adr/ADR-0130-registre-et-confiance.md` (statut, contexte, options, décision, conséquences, risques, révision) qui traite :
1. **Le registre.** Harbor, le registre intégré de GitLab, un registre CNCF Distribution nu (celui du M12) — et, pour mémoire, un registre de nuage public. Critères : contrôle d'accès et robots, caches de registres publics, analyse intégrée, politiques de signature, réplication, quotas et rétention, exploitation (composants, base, mises à jour), souveraineté, dépendance à une seule VM.
2. **La signature.** Cosign avec une clé MédiSphère (choix actuel), Cosign « sans clé » avec Fulcio et Rekor publics, Cosign sans clé avec une instance Sigstore **privée** (Fulcio + Rekor + TSA auto-hébergés), Notation (Notary Project). Critères : dépendance à Internet, fuite d'information vers un journal public, gestion et rotation de la clé, révocation, preuve d'horodatage, outillage Kubernetes (module 26).
3. **La politique de confiance.** Ce qui doit être vrai d'une image pour être tirée en production (projet, signature par la clé de la CI, digest, SBOM et provenance attachés, analyse sans Critical corrigeable), **où** c'est vérifié (registre, CI, admission Kubernetes au module 26), et la procédure si la clé privée fuit (rotation, re-signature des images en service, période de recouvrement de deux clés, communication).
4. **Ce qu'on accepte de ne pas avoir** aujourd'hui et quand on le revoit (module 25 pour la clé dans Vault, module 26 pour l'admission, F6 pour l'audit).

**Critères de réussite**
- [ ] L'ADR compare au moins trois registres et trois modes de signature sur des critères explicites.
- [ ] La politique de confiance est vérifiable : chaque règle dit où et comment elle est contrôlée.
- [ ] La procédure de compromission de la clé est écrite pas à pas, avec la période de recouvrement.
- [ ] Les risques acceptés ont un propriétaire et une date de révision.

**Vérification** : auto-évaluation avec la grille du corrigé (pas de script). L'ADR est publié par MR sur `plateforme/medisphere` (le mini-projet vérifie sa présence).

<details><summary>Indice 1</summary>

Reprends les faits mesurés dans le module plutôt que des généralités : RPO de la réplication (E13), RTO de la restauration (E15), messages des politiques (E14), ce que vérifie vraiment la politique Cosign de Harbor (E14, étape 5).
</details>

<details><summary>Indice 2</summary>

Pour la signature sans clé, demande-toi ce que contient une entrée Rekor publique (nom de l'image, digest, identité du signataire) et ce qu'un concurrent ou un attaquant pourrait en déduire. Pour Sigstore privé, compte les composants à exploiter et leur disponibilité.
</details>

**Pour aller plus loin** : compare avec la politique de confiance d'un éditeur qui publie ses images (Chainguard, Docker *Hardened Images*) : que vérifient-ils que tu ne vérifies pas ?

---

### M13-E18 — Alerte CVE critique : répondre en temps limité  `CHRONO` `★★★`

> **Ticket SEC-1436** — *De : Sophie Laurent* — *Priorité : critique*
> Le CERT Santé vient de publier un avis (en pièce jointe). La faille est exploitable à distance et il n'y a **pas encore de correctif**. Dans une heure, je dois dire à la direction : quelles images de MédiSphère sont touchées, lesquelles sont exposées, ce qui est déjà corrigé, et quand le reste le sera. Pas de « je pense » : des preuves.

**Conditions** : **60 minutes**, chronomètre lancé à la lecture de l'avis. Pas de corrigé ouvert. La documentation officielle des outils, tes notes et tes runbooks sont permis. Tu travailles seul ; Julien Petit (MédiAgenda) et l'équipe de MédiNotif fusionnent sans délai une MR que tu leur proposes, si son pipeline est vert.

**Prérequis** : M13-E06 (SBOM), M13-E08 (attestations), M13-E09 (chaîne de livraison), M13-E14 (politiques et vérification).

**Matériel fourni** : [`ressources/E18-avis-CS-2026-0412.md`](../ressources/E18-avis-CS-2026-0412.md) (l'avis, **fictif**, écrit pour l'exercice : ne le cherche pas ailleurs) et [`ressources/E18-modele-compte-rendu.md`](../ressources/E18-modele-compte-rendu.md) (le modèle de compte-rendu attendu par Sophie).

**Travail demandé** (dans l'ordre que tu juges bon, en 60 minutes)
1. **Inventaire par les SBOM.** Établis la liste des images touchées parmi toutes celles de Harbor (`medisphere`, `plateforme`, `bibliotheque`, et les caches si tu le juges utile), **à partir des SBOM attachés** aux images et non en relisant le code. Pour chaque image : dépôt, étiquette(s) en service, digest, version du composant trouvée, source de la preuve.
2. **Priorisation.** Classe les images touchées selon l'exposition (point d'entrée réseau, données de santé, environnement) et décide du traitement de chacune (corriger maintenant, contournement, accepter avec justification).
3. **Correction.** Pour au moins **une** image applicative touchée, applique le contournement recommandé par l'avis, fais publier par la chaîne de livraison normale une nouvelle version **signée, avec SBOM**, et prouve, par le SBOM attesté de la nouvelle image, que la version vulnérable n'y est plus.
4. **Compte-rendu.** Remplis le modèle et publie-le dans `docs/registre/alertes/CS-2026-0412.md` (MR sur `plateforme/medisphere`) : chronologie, inventaire avec preuves, décisions, digests des images corrigées, reste à faire avec échéances, ce qui t'a ralenti.

**Critères de réussite**
- [ ] Le compte-rendu est publié dans les 60 minutes et liste chaque image touchée avec son digest et la preuve tirée du SBOM.
- [ ] Les faux amis de l'avis (composants au nom proche, images non concernées) sont identifiés comme non touchés, avec la raison.
- [ ] Au moins une nouvelle version d'une image applicative est publiée dans `medisphere`, signée, analysée, et son SBOM attesté ne contient plus le composant dans une version touchée ; son digest figure dans le compte-rendu.
- [ ] Le compte-rendu dit ce qui reste exposé et jusqu'à quand.

**Vérification** : `lab/bin/check 13 18` (après les 60 minutes)

<details><summary>Indice 1</summary>

Avant de commencer, pose-toi la question de l'outil : un SBOM attesté se récupère et se vérifie avec `cosign verify-attestation` (la clé MédiSphère, le type de prédicat) ; Grype sait analyser un SBOM sans l'image ; `jq` sait filtrer un document SPDX. Dix minutes pour un petit script d'inventaire en valent trente de clics.
</details>

<details><summary>Indice 2</summary>

Relis la section « Versions affectées » de l'avis mot à mot, et compare le **nom exact** du composant avec ce que contiennent les SBOM (écosystème, nom de paquet). Deux bibliothèques peuvent porter presque le même nom sans avoir rien en commun.
</details>

**Pour aller plus loin** : refais l'exercice en mesurant le temps de l'inventaire seul, puis automatise-le (`plateforme/outils`, `ms-sbom-recherche <paquet> <plage>`) pour qu'il tienne en une commande à la prochaine alerte.
