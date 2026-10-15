# Module 13 — Palier 2 : Opérationnel

Le registre est en place et les images sont analysées. Ce palier construit les **preuves** : une nomenclature (SBOM) pour chaque image, une **signature** MédiSphère par empreinte, des **attestations** (SBOM et provenance) attachées à l'image, puis une **chaîne de livraison** standard qui fait tout cela seule, en CI, pour chaque version. Il règle aussi ce que le registre garde et combien de temps, met **Renovate** au travail sur les dépendances, et se termine par la revue d'une chaîne écrite par le stagiaire.

Prérequis : palier 1 terminé (`lab/bin/check 13 02` à `13 05` verts). Les outils du palier (Syft, Grype, Cosign) s'installent par le rôle `outils_supply_chain` de E05.

---

### M13-E06 — SBOM avec Syft, analyse avec Grype  `LAB` `★★`

> **Ticket SEC-1406** — *De : Sophie Laurent*
> L'analyse de Trivy, c'est l'état des vulnérabilités **aujourd'hui**. Ce que l'auditeur veut, c'est l'**inventaire** : quels composants, quelles versions, quelles licences, image par image, conservé. Et je veux un second avis : un autre analyseur, sur cet inventaire, et une explication écrite des écarts. Enfin, Harbor sait produire des SBOM lui-même : est-ce qu'on s'en sert ?

**Objectifs pédagogiques**
- Produire des SBOM aux formats SPDX et CycloneDX avec Syft, et les lire.
- Analyser une SBOM (et non l'image) avec Grype ; comprendre la base de Grype.
- Comparer deux analyseurs et deux générateurs de SBOM, et en tirer une règle.

**Prérequis** : M13-E05.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Paquets | Syft **1.54.1** (`syft_1.54.1_linux_amd64.deb`, release `github.com/anchore/syft`) et Grype **0.120.1** (`grype_0.120.1_linux_amd64.deb`, release `github.com/anchore/grype`) ; chez Anchore, c'est le fichier `<outil>_<version>_checksums.txt` qui est signé (bundle `…_checksums.txt.sigstore.json`, identité `https://github.com/anchore/<outil>/.github/workflows/release.yaml@refs/heads/main`, émetteur `https://token.actions.githubusercontent.com`) |
| Base de Grype | schéma **v6** (les Grype antérieurs à 0.88 ne reçoivent plus de mises à jour), dans `~/.cache/grype/db/` |
| Accès à Harbor | Syft et Grype lisent le fichier d'authentification Docker (`~/.docker/config.json`, ou `DOCKER_CONFIG`) |
| Fichiers | `~/m13/e06/<image>.spdx.json`, `<image>.cdx.json`, `<image>.grype.json` pour `mediagenda-api`, `medidoc`, `medinotif`, `legacy-rdv` |
| Harbor | génération de SBOM par Trivy, propriété de projet (« automatically generate SBOM on push ») |

**Travail demandé**

1. Ajoute Syft et Grype au rôle `outils_supply_chain` : ici, tu vérifies la signature du **fichier d'empreintes**, puis l'empreinte du paquet dans ce fichier. Pourquoi ce schéma est-il aussi sûr que la signature de chaque paquet ? Applique à `adm01`.
2. Connecte le fichier d'authentification Docker de `adm01` à Harbor avec ton compte (`--password-stdin`), puis vérifie ses droits (600).
3. Produis avec Syft, pour la dernière version de chacune des quatre images de `medisphere`, une SBOM **SPDX JSON** et une SBOM **CycloneDX JSON** (une seule analyse par image, deux sorties). Ouvre-en une avec `jq` : où sont les composants, leur `purl`, leurs licences, la relation avec l'image ? Combien de composants Debian, Python, Go ?
4. Lis `grype db status` puis analyse **les SBOM** (pas les images) avec Grype, en JSON, en ne gardant que ce qui a un correctif. Pourquoi analyser une SBOM conservée plutôt que l'image, six mois plus tard ?
5. Compare, pour `mediagenda-api` : les CVE critiques et élevées de Trivy (E05) et de Grype, et le nombre de composants vus par Syft et par Trivy (`trivy image --format spdx-json`). Explique au moins trois écarts.
6. Active la génération de SBOM à la poussée dans `medisphere` (état `registre`), génère la SBOM d'une image depuis l'IHM, télécharge-la et compare-la avec celle de Syft. Laquelle conserveras-tu comme référence, et pourquoi pas les deux ?
7. Écris `docs/registre/comparaison-analyseurs.md` : méthode, chiffres, écarts expliqués, décision (quel analyseur bloque, lequel sert de second avis, quel format de SBOM on conserve, où).

**Critères de réussite**
- [ ] Syft 1.54.x et Grype 0.120.x sont installés sur `adm01` par le rôle `outils_supply_chain` ; la base de Grype est au schéma v6.
- [ ] `~/m13/e06/` contient, pour les quatre images, une SBOM SPDX 2.3 et une SBOM CycloneDX non vides, et un rapport Grype JSON.
- [ ] La génération de SBOM à la poussée est active sur `medisphere` et au moins un artefact de `medisphere/mediagenda-api` a une SBOM produite par Harbor.
- [ ] `docs/registre/comparaison-analyseurs.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 13 06`

<details><summary>Indice 1</summary>

`syft scan <source> -o <format>=<fichier>` peut être répété pour plusieurs sorties. La source d'une image distante s'écrit `registry:<nom>@<empreinte>` pour forcer la lecture dans le registre (sans démon local). Grype accepte `sbom:<fichier>` comme source.
</details>

<details><summary>Indice 2</summary>

Les écarts viennent de trois endroits : **ce qui est vu** (catalogueurs : dpkg, métadonnées Python installées, binaires Go et leurs informations de construction), **la base** (sources d'avis, dates de mise à jour) et **la correspondance** (CPE contre `purl`, avis de la distribution contre avis amont, versions « corrigées dans Debian » contre « corrigées en amont »).
</details>

---

### M13-E07 — Signer et vérifier avec Cosign  `LAB` `★★★`

> **Ticket SEC-1407** — *De : Sophie Laurent* — *Copie : Karim Benali, Claire Morel*
> Une clé de signature MédiSphère. La privée ne se trouve que dans le coffre (Vault `critique`) et, pour la CI, dans une variable protégée ; la publique est publiée, versionnée, et c'est **elle** que tout le monde utilise pour vérifier. On signe des **empreintes**. Et pas de journal public : personne en dehors de MédiSphère ne doit pouvoir apprendre ce que contient notre registre. Montre-moi aussi qu'une signature faite avec une autre clé, ou portée par la mauvaise image, est bien refusée.

**Objectifs pédagogiques**
- Créer et protéger une paire de clés de signature ; publier la clé publique.
- Signer une image par empreinte avec Cosign 3, sans journal de transparence, et vérifier la signature.
- Voir où et comment la signature est stockée (bundle, référent OCI 1.1) dans Harbor.
- Comprendre la signature sans clé (*keyless*) et pourquoi on ne l'utilise pas ici.

**Prérequis** : M13-E02 (Cosign 3.1 sur `adm01`) ; M13-E03 (images dans `medisphere`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Clés | paire **`cosign.key`** / **`cosign.pub`** (ECDSA P-256, format de Cosign), phrase de passe forte ; privée et phrase de passe en Vault `critique` dans `plateforme/ansible` (fichier entièrement chiffré `secrets/cosign/cosign.key`, variable `vault_cosign_mdp`) ; publique dans `plateforme/medisphere`, **`docs/registre/cosign.pub`** |
| Configuration de signature | `docs/registre/signing-config.json` : configuration de signature Sigstore **sans** journal de transparence ni horodatage ; passée à `cosign sign` et `cosign attest` par `--signing-config` |
| Vérification | `cosign verify --key cosign.pub --insecure-ignore-tlog=true <image>@<empreinte>` |
| Variables de CI (E09) | `COSIGN_PRIVATE_KEY` (type **fichier**, protégée), `COSIGN_PASSWORD` (protégée, masquée), dans les groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` |
| Cosign et le registre | Cosign lit le fichier d'authentification Docker (E06) ; Harbor 2.15 accepte le format *bundle* de Cosign 3 et l'affiche comme accessoire de l'artefact signé |

**Travail demandé**

1. Lis `cosign sign --help`, `cosign verify --help` et `cosign signing-config create --help` (Cosign 3.1). Repère : l'option qui désactive la configuration de signature publique de Sigstore, celle qui en fournit une locale, l'option dépréciée `--tlog-upload` et pourquoi elle est refusée avec une configuration de signature, l'option de vérification sans journal.
2. Génère la paire de clés dans un dossier **temporaire en mémoire** sur `adm01` (`/dev/shm` ou un `tmpfs`), la phrase de passe fournie par une variable d'environnement lue depuis un fichier, jamais tapée en argument. Chiffre la clé privée en Vault `critique` et range la phrase de passe dans `vault-critique` ; efface les copies en clair ; vérifie que tu sais **relire** la clé depuis le Vault.
3. Crée la configuration de signature MédiSphère (aucun service : pas de Fulcio, pas de Rekor, pas d'autorité d'horodatage) et vérifie son contenu avec `jq`. Publie `cosign.pub` et `signing-config.json` dans `docs/registre/` (MR relue par Karim et Sophie), avec une fiche `docs/registre/signature.md` : empreinte de la clé publique, procédure de vérification, procédure de **rotation** et de **révocation**.
4. Résous l'empreinte de la dernière version de `medisphere/mediagenda-api` (`skopeo inspect` ou `crane digest`), puis signe **cette empreinte**, la clé privée passée à Cosign sans fichier en clair sur le disque (lis la documentation des références de clé `env://`).
   > ⚠️ **Attention** : relis la commande avant de la lancer. Sans `--signing-config` (ou avec une configuration qui contient un journal), Cosign envoie la signature au journal de transparence **public** sans demander de confirmation, et cette entrée ne s'efface pas. Après la signature, contrôle dans le bundle stocké que la liste `tlogEntries` est vide.
5. Vérifie la signature avec `cosign.pub` (celle du dépôt, pas ta copie de travail). Regarde ce que Cosign a écrit dans le registre : `cosign tree`, la vue de l'artefact dans Harbor (onglet des accessoires), puis l'API des référents (`/v2/medisphere/mediagenda-api/referrers/<empreinte>`) avec `skopeo` ou `curl`. Quel `artifactType` ? Le manifeste de l'image a-t-il changé d'empreinte ?
6. Prouve les refus : vérification avec une **autre** clé publique (génère-en une jetable) ; vérification d'une **autre** empreinte du même dépôt (non signée) ; signature d'une étiquette au lieu d'une empreinte (que dit Cosign ?) puis déplacement de l'étiquette vers une autre image : que vérifie-t-on alors ?
7. Signe aussi la dernière version de `medidoc`, `medinotif` et `legacy-rdv`. Prépare les variables de CI de E09 (`COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`) dans les quatre groupes, par l'API de GitLab, sans que la clé transite en clair dans l'historique du shell.
8. Écris dans `signature.md` un paragraphe « Et le *keyless* ? » : ce qu'il faudrait (Fulcio et Rekor privés, émetteur OIDC de GitLab, identités de pipeline) et ce que l'on y gagnerait.

**Critères de réussite**
- [ ] Cosign 3.1.x sur `adm01` ; `docs/registre/cosign.pub` et `docs/registre/signing-config.json` (sans journal de transparence) sont sur `main` de `plateforme/medisphere`, avec `signature.md`.
- [ ] La clé privée n'existe dans aucun dépôt en clair ; elle est chiffrée en Vault `critique` dans `plateforme/ansible` ; le registre des secrets la mentionne.
- [ ] La dernière version de chacune des quatre images de `medisphere` porte une signature que `cosign verify` accepte avec la clé publique publiée, sans journal de transparence.
- [ ] Les variables `COSIGN_PRIVATE_KEY` (fichier, protégée) et `COSIGN_PASSWORD` (protégée, masquée) existent dans les groupes `mediagenda`, `medidoc`, `medinotif` et `legacy`.

**Vérification** : `lab/bin/check 13 07`

<details><summary>Indice 1</summary>

`cosign generate-key-pair` lit la phrase de passe dans `COSIGN_PASSWORD`. Une clé privée peut être passée par `--key env://NOM_DE_VARIABLE`. `ansible-vault encrypt --vault-id critique@<script> <fichier>` chiffre un fichier entier ; `ansible-vault view` le relit sur la sortie standard.
</details>

<details><summary>Indice 2</summary>

Avec Cosign 3, `--tlog-upload=false` ne se combine pas avec une configuration de signature (celle de Sigstore est utilisée par défaut). Une configuration de signature créée par `cosign signing-config create` sans aucun service ne contient que son type de média. À la vérification, sans journal **et** sans horodatage signé, Cosign doit être autorisé à ignorer le journal.
</details>

<details><summary>Indice 3</summary>

Pour une variable de CI de type fichier, l'API de GitLab prend `variable_type=file` ; `curl --data-urlencode "value@<fichier>"` lit la valeur dans un fichier (ici un fichier temporaire en mémoire, effacé ensuite) ; le jeton d'administration se passe par `--header @<fichier>`.
</details>

**Pour aller plus loin** (facultatif) : signe la même image avec Notation (le projet CNCF concurrent) et compare les formats dans Harbor.

---

### M13-E08 — Attestations : SBOM et provenance attachés à l'image  `LAB` `★★★`

> **Ticket SEC-1408** — *De : Sophie Laurent* — *Copie : Julien Petit*
> La signature dit « MédiSphère a approuvé ceci ». L'auditeur demandera aussi « qu'y a-t-il dedans » et « comment a-t-elle été fabriquée ». Je veux ces deux réponses **attachées à l'image**, signées, vérifiables par n'importe qui chez nous avec notre clé publique, sans aller fouiller dans un partage de fichiers.

**Objectifs pédagogiques**
- Attacher une SBOM à une image sous forme d'attestation in-toto signée, et la vérifier.
- Produire une provenance de construction avec BuildKit et la lire ; comprendre ce qu'elle prouve et ce qu'elle ne prouve pas.
- Distinguer attestation signée par Cosign et attestation non signée stockée dans l'index par BuildKit.

**Prérequis** : M13-E06 (SBOM) ; M13-E07 (clés, configuration de signature).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Attestation SBOM | `cosign attest --type spdxjson --predicate <sbom.spdx.json>` ; vérification `cosign verify-attestation --type spdxjson --key cosign.pub --insecure-ignore-tlog=true` |
| Provenance | BuildKit : `--provenance=mode=max` (Buildx) ou `--opt attest:provenance=mode=max` (`buildctl`) ; l'attestation est rangée **dans l'index** de l'image, comme un manifeste supplémentaire de plateforme `unknown/unknown` |
| Construction de l'essai | sur `runner02`, avec le Docker 29 de l'hôte (`sudo docker buildx build`), dans un dossier d'authentification **temporaire** ; étiquette d'essai `medisphere/mediagenda-api:0.0.0-attest-essai` |
| Lecture | `docker buildx imagetools inspect <image> --format '{{json .Provenance}}'` (et `.SBOM`) |

**Travail demandé**

1. Attache la SBOM SPDX de E06 à la dernière version de `medisphere/mediagenda-api`, par empreinte, avec la configuration de signature MédiSphère. Vérifie l'attestation avec la clé publique et lis le prédicat déchiffré (`jq` sur la sortie : l'enveloppe DSSE est en base64). Que contient `subject`, et pourquoi ?
2. Fais de même avec la SBOM CycloneDX (type `cyclonedx`). Qu'affiche `cosign tree` maintenant ? Que montre Harbor pour l'artefact ?
3. Sur `runner02`, clone `mediagenda/api`, construis l'image avec une **provenance maximale** et pousse-la sous l'étiquette d'essai, avec ton compte Harbor dans un `DOCKER_CONFIG` temporaire effacé ensuite.
4. Lis la provenance (`imagetools inspect`, format SLSA **v1** chez Buildx 0.37) : qui (`runDetails.builder.id`), à partir de quoi (`buildDefinition.resolvedDependencies` : images de base et leurs empreintes, contexte Git), comment (`buildDefinition.externalParameters` : Dockerfile, arguments de construction, cible), quand (`runDetails.metadata`). Quels champs sont vides ou peu fiables pour une construction lancée à la main ? Que vaudrait cette provenance si un attaquant contrôlait `runner02` ? À quel niveau de SLSA cela correspond-il ?
5. Inspecte l'index brut (`skopeo inspect --raw`) : comment le manifeste d'attestation est-il rattaché au manifeste de l'image ? En quoi diffère-t-il d'une attestation Cosign (référent signé) ? Signe ensuite l'index de l'essai avec Cosign, puis vérifie : la provenance de BuildKit est-elle couverte par la signature ?
6. Supprime l'étiquette d'essai de Harbor quand tu as fini (la rétention de E10 nettoiera le reste).
   > ⚠️ **Attention** : supprime l'**étiquette** `0.0.0-attest-essai`, pas le dépôt ni l'artefact d'une autre version : vérifie l'empreinte avant de valider.
7. Complète `docs/registre/signature.md` d'une section « Attestations » : types utilisés, commandes de vérification, ce que l'on exige pour une image de production.

**Critères de réussite**
- [ ] La dernière version de `medisphere/mediagenda-api` porte une attestation SPDX que `cosign verify-attestation --type spdxjson` accepte avec la clé publique publiée.
- [ ] Une attestation CycloneDX est aussi attachée à cette image et vérifiable.
- [ ] `docs/registre/signature.md` sur `main` contient une section sur les attestations et la provenance.

**Vérification** : `lab/bin/check 13 08`

<details><summary>Indice 1</summary>

La sortie de `cosign verify-attestation` est une suite d'enveloppes JSON ; le champ `payload` est le relevé in-toto encodé en base64 (`jq -r .payload | base64 -d | jq .predicateType`). La construction Docker a besoin du contexte et du `Dockerfile` du dépôt, et d'un builder qui sache exporter les attestations (le pilote `docker` de Docker 29, avec le stockage d'images containerd, le sait).
</details>

<details><summary>Indice 2</summary>

Dans l'index produit par BuildKit, le manifeste d'attestation porte les annotations `vnd.docker.reference.type: attestation-manifest` et `vnd.docker.reference.digest: <empreinte du manifeste de l'image>`. Une signature Cosign de l'**index** couvre son contenu, donc les empreintes des manifestes qu'il liste.
</details>

---

### M13-E09 — La chaîne de livraison d'une image  `LIBRE` `★★★`

> **Ticket DEV-1409** — *De : Julien Petit* — *Copie : Karim Benali, Sophie Laurent*
> Tout ce que vous avez fait à la main depuis une semaine, je le veux à chaque version de MédiAgenda, sans y penser : construction, analyse, SBOM, publication dans Harbor, signature, attestations. Un gabarit que les autres équipes incluront, pas un `.gitlab-ci.yml` de 300 lignes copié partout. Et une règle simple : une version `vX.Y.Z` publiée ne bouge plus jamais.

**Objectifs pédagogiques**
- Concevoir une chaîne de livraison d'images complète, sans privilège, réutilisable par inclusion.
- Faire de chaque étape un contrôle bloquant qui porte sur une empreinte, et propager l'empreinte d'étape en étape.
- Protéger les secrets de publication et de signature (robot, clé) dans la CI.

**Prérequis** : M13-E04 à M13-E08 ; M12-E21 (construction sans privilège, gabarit `image.yml`) ; M01 (semantic-release, étiquettes `vX.Y.Z`).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Gabarit | `plateforme/ci-templates`, fichier **`supply-chain.yml`**, inclus par `include: project` avec une référence épinglée (étiquette du dépôt de gabarits) |
| Premier client | `mediagenda/api` → `registry.par1.medisphere.internal/medisphere/mediagenda-api` |
| Exécuteur | `runner02`, exécuteur `docker`, étiquette `docker`, **sans mode privilégié** ; images des jobs tirées par les caches (E04) |
| Robot | `robot$medisphere+ci` dans `HARBOR_ROBOT_USER` / `HARBOR_ROBOT_TOKEN` (groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` ; protégées ; le jeton masqué) |
| Signature | `COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD` (E07) ; `cosign.pub` et `signing-config.json` de `docs/registre/` |
| Versions publiées | étiquettes Git `vX.Y.Z` posées par semantic-release sur `main` ; image publiée sous la même étiquette |

**Travail demandé**

Conçois et livre le gabarit `supply-chain.yml` et son utilisation par `mediagenda/api`. Contraintes :

1. **Étapes** : construction, analyse de vulnérabilités, SBOM, publication, signature, attestations, vérification finale. Chaque étape travaille sur **l'empreinte** produite par la construction, transmise de job en job ; aucune étape ne re-résout une étiquette.
2. **Construction sans privilège**, reproductible autant que possible, avec une provenance de construction.
3. **Blocage** : la chaîne s'arrête si l'image contient une vulnérabilité **critique qui a un correctif**, avant toute publication ; les exceptions passent par le `.trivyignore` justifié du projet (E05). Aucun job de contrôle n'est autorisé à échouer.
4. **SBOM** SPDX conservée comme artefact du pipeline **et** attachée à l'image (attestation signée).
5. **Publication** par le robot du projet uniquement ; une version `vX.Y.Z` n'est publiée que depuis une étiquette Git protégée, et **jamais deux fois** (la chaîne refuse de réécrire une étiquette existante) ; les pipelines de `main` publient une étiquette de suivi non `v`.
6. **Signature et attestations** par empreinte, avec la clé de la CI, sans journal de transparence ; **vérification** en fin de chaîne avec la clé publique publiée.
7. **Outils** épinglés par version **et** par empreinte d'image ; aucune image de job tirée hors de Harbor ; aucun `latest` ; aucun secret dans un argument de commande ni dans le journal.
8. **Réutilisable** : nom d'image, contexte, Dockerfile, seuil de blocage paramétrables par variables ; documenté en tête du fichier et dans `docs/registre/chaine-livraison.md`.
9. Publie une version de `mediagenda/api` par la chaîne (MR, fusion, semantic-release) et montre qu'une seconde publication de la même version échoue.

**Critères de réussite**
- [ ] `supply-chain.yml` est sur `main` de `plateforme/ci-templates` (et dans une étiquette du dépôt) ; il ne désigne que des images de Harbor, épinglées par empreinte, et aucun job n'y est autorisé à échouer.
- [ ] `mediagenda/api` inclut le gabarit par une référence épinglée ; le dernier pipeline de l'étiquette `vX.Y.Z` la plus récente a réussi.
- [ ] `medisphere/mediagenda-api:vX.Y.Z` existe dans Harbor, porte une signature et une attestation SPDX vérifiables avec la clé publique publiée.
- [ ] Les variables `HARBOR_ROBOT_USER` et `HARBOR_ROBOT_TOKEN` du groupe `mediagenda` sont protégées et non développées, `HARBOR_ROBOT_TOKEN` est masquée ; `HARBOR_ROBOT_USER` désigne `robot$medisphere+ci`.
- [ ] `docs/registre/chaine-livraison.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 13 09`

<details><summary>Indice 1</summary>

Un job transmet une valeur aux suivants par un fichier `dotenv` déclaré en `artifacts:reports:dotenv`. Construire vers une **archive OCI** (au lieu de pousser) permet d'analyser avant de publier ; la publication copie ensuite l'archive vers Harbor en préservant les empreintes.
</details>

<details><summary>Indice 2</summary>

Les images officielles de Cosign et de Syft sont minimales : sans shell, l'exécuteur Docker de GitLab ne peut pas y lancer un `script`. Une image outillée MédiSphère, construite depuis une image de base de `bibliotheque` avec les paquets vérifiés de E05/E06, résout aussi l'épinglage des versions.
</details>

<details><summary>Indice 3</summary>

Une variable GitLab dont la valeur contient `$` (le nom d'un robot) doit être déclarée **sans développement** des références. Pour savoir si une étiquette existe déjà dans le registre, une lecture du manifeste suffit ; distingue bien « absente » de « registre injoignable ».
</details>

---

### M13-E10 — Quotas, rétention et immuabilité des étiquettes  `LAB` `★★`

> **Ticket PLAT-1410** — *De : Karim Benali* — *Copie : Nadia Roussel*
> `/data` fait 200 Gio et la CI pousse une image par commit sur `main`. Dans deux mois on est plein, et le jour où ça arrive, plus personne ne publie. Il me faut : un quota par projet, une rétention qui garde ce qui compte (toutes les versions, les dix dernières images de suivi), le ramasse-miettes planifié, et l'immuabilité des `v*` côté registre, pas seulement dans le pipeline.

**Objectifs pédagogiques**
- Dimensionner et poser des quotas de stockage par projet.
- Écrire des règles de rétention, les simuler et comprendre leur combinaison.
- Rendre des étiquettes immuables et en mesurer les effets (y compris sur les signatures).
- Planifier le ramasse-miettes et comprendre ce qu'il libère réellement.

**Prérequis** : M13-E09.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Quotas | `medisphere` 40 Gio, `plateforme` 15 Gio, `bibliotheque` 15 Gio, `charts` 5 Gio ; caches (E04) : `dockerhub` 40, `ghcr` 20, `quay` 10, `k8s` 15 |
| Rétention (`medisphere`) | garder **toujours** les étiquettes `v*` ; garder les **10** artefacts poussés le plus récemment de chaque dépôt ; exécution quotidienne |
| Immuabilité (`medisphere`, `bibliotheque`) | étiquettes `v*` de tous les dépôts |
| Ramasse-miettes | hebdomadaire (nuit du dimanche, 3 h), suppression des artefacts sans étiquette |
| Code | état `registre` (`politiques.tf`, quotas dans les projets) |

**Travail demandé**

1. Mesure l'occupation actuelle de chaque projet (IHM, API `projects/<projet>/summary`) et de `/data` sur `reg01`. Justifie les quotas du contexte : que se passe-t-il quand un projet atteint son quota pendant une poussée ? Pourquoi la somme des quotas doit-elle rester sous la taille du disque, avec une marge ?
2. Déclare les quotas dans l'état `registre`. Lis la documentation de la rétention : comment se combinent plusieurs règles (ET ou OU) ? Que deviennent les artefacts **sans étiquette** et les **accessoires** (signatures, attestations) d'un artefact supprimé ?
3. Déclare la règle de rétention de `medisphere`. Avant le premier passage planifié, lance une **simulation** depuis l'IHM et lis son journal : quels artefacts partiraient ? Aucun `v*` ne doit y figurer.
   > ⚠️ **Attention** : une rétention mal écrite supprime des images de production en une nuit. Ne laisse la planification active qu'après une simulation relue.
4. Déclare l'immuabilité des `v*` dans `medisphere` et `bibliotheque`. Essaie, avec ton compte, de repousser une autre image sous une étiquette `v*` existante, puis de la supprimer : que répond Harbor ? Signer une image immuable est-il encore possible, et pourquoi ?
5. Planifie le ramasse-miettes (état `registre`). Lance-le une fois à la main en **simulation**, puis pour de vrai, et compare l'occupation de `/data` avant et après. Pourquoi supprimer une étiquette ne libère-t-il pas d'espace disque tout de suite ?
6. Ajoute à `docs/registre/stockage.md` : quotas, règles, ce que fait le ramasse-miettes et quand, comment demander une hausse de quota.

**Critères de réussite**
- [ ] Les huit projets ont le quota du contexte technique.
- [ ] `medisphere` a une règle de rétention planifiée qui garde toujours les `v*` et les 10 derniers artefacts poussés.
- [ ] Les étiquettes `v*` sont immuables dans `medisphere` et `bibliotheque`.
- [ ] Le ramasse-miettes est planifié chaque semaine et supprime les artefacts sans étiquette ; il a déjà tourné avec succès.
- [ ] `politiques.tf` est sur `main` de `plateforme/infra` ; `docs/registre/stockage.md` sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 13 10`

<details><summary>Indice 1</summary>

Dans le fournisseur, les quotas sont l'attribut `storage_quota` du projet (en Gio) ; la rétention est la ressource `harbor_retention_policy` (règles `always_retain`, `most_recently_pushed`, filtres `repo_matching`, `tag_matching`) ; l'immuabilité, `harbor_immutable_tag_rule` ; le ramasse-miettes, `harbor_garbage_collection` (planification au format cron à **six** champs, secondes comprises).
</details>

<details><summary>Indice 2</summary>

Une rétention garde un artefact dès qu'**une** de ses règles le retient. Une signature Cosign n'est pas une étiquette : c'est un accessoire de l'artefact, qui n'est pas concerné par l'immuabilité de l'étiquette de l'image.
</details>

---

### M13-E11 — Renovate auto-hébergé  `LAB` `★★★`

> **Ticket PLAT-1411** — *De : Karim Benali* — *Copie : Julien Petit, Sophie Laurent*
> Nos images de base sont épinglées par empreinte : c'est bien, mais plus personne ne les met à jour, et les CVE s'accumulent. Même chose pour les dépendances Python et Go. Je veux un Renovate à nous, qui tourne chaque nuit sur `runner02`, ouvre des MR propres, et fusionne seul **les correctifs** quand la CI est verte. Le reste, on relit. Sophie ajoute une condition : pas de version publiée depuis moins de trois jours, on a vu ce qui s'est passé avec Trivy.

**Objectifs pédagogiques**
- Déployer Renovate auto-hébergé sur GitLab CE avec renovate-runner, en pipeline planifié.
- Écrire une configuration partagée (préréglage) et l'appliquer aux projets.
- Mettre à jour des images épinglées par empreinte derrière un cache Harbor, des verrous `uv.lock` et des modules Go.
- Limiter la fusion automatique aux correctifs, avec un délai de maturité.

**Prérequis** : M13-E04 (caches), M13-E09 (chaîne de livraison verte sur `mediagenda/api`) ; M01 (MR, protections, CI).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projets | `plateforme/renovate-runner` (import du projet `renovate-bot/renovate-runner` de gitlab.com, étiquette **v26.1.0**) ; `plateforme/renovate` (`.gitlab-ci.yml`, `config.js`) ; `plateforme/renovate-config` (préréglage partagé `default.json`) |
| Image | `ghcr.io/renovatebot/renovate:44`, tirée par le cache `ghcr` (variable `CI_RENOVATE_IMAGE` du gabarit), épinglée par empreinte |
| Compte | utilisateur GitLab **`renovate-bot`** (non administrateur), membre *Developer* des projets qu'il traite ; jeton personnel portée `api`, expiration obligatoire, dans la variable `RENOVATE_TOKEN` de `plateforme/renovate` (protégée, masquée) |
| Harbor | robot `robot$renovate` (système, tirage de `bibliotheque` et `plateforme`) dans `HARBOR_RENOVATE_USER` / `HARBOR_RENOVATE_TOKEN` (protégées, non développées ; le jeton masqué) |
| CA | Renovate est une application Node.js : elle n'utilise pas le magasin de certificats du système ; `NODE_EXTRA_CA_CERTS` désigne un fichier de CA supplémentaire |
| Planification | chaque nuit, sur `main` de `plateforme/renovate`, exécuteur `runner02` (étiquette `docker`) |
| Projets traités | `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv`, `plateforme/ci-templates` |

**Travail demandé**

1. Lis la documentation de Renovate : « Self-hosting », la plateforme GitLab, les options `registryAliases`, `pinDigests`, `automerge`, `automergeType`, `platformAutomerge`, `minimumReleaseAge`, `packageRules`, `postUpdateOptions`, et le gabarit `templates/renovate.gitlab-ci.yml` de renovate-runner. Note : sur quel événement le job tourne-t-il ? Quelles variables attend-il ?
2. Importe renovate-runner dans `plateforme/renovate-runner` à l'étiquette v26.1.0. Pourquoi l'importer plutôt que l'inclure depuis gitlab.com ?
3. Crée le compte `renovate-bot` et son jeton (par l'API, avec le jeton d'administration de `~/.config/workbook/`), donne-lui le rôle *Developer* sur les projets traités. Pourquoi pas *Maintainer* ? Que se passe-t-il pour la fusion automatique sur une branche protégée ?
4. Ajoute le robot `renovate` à l'état `registre`. Crée `plateforme/renovate` : inclusion du gabarit **importé**, image par le cache, `config.js` (plateforme, découverte limitée aux projets traités, identifiants du registre lus dans l'environnement, auteur des commits), CA MédiSphère pour Node.js et pour Git, variables protégées. Planifie le pipeline chaque nuit.
5. Écris le préréglage `plateforme/renovate-config` (`default.json`) : images Docker épinglées par empreinte, alias des caches Harbor vers leur registre amont, fusion automatique **des seuls correctifs** (*patch*) quand la CI passe, rien d'automatique pour les majeures, délai de maturité de 3 jours, verrou `uv.lock` et `go.sum` mis à jour, MR étiquetées, nombre de MR ouvertes limité. Ajoute à chaque projet traité un `renovate.json` qui l'étend (une MR par projet).
6. Lance un pipeline à la main (bouton « Run pipeline » de la planification), lis le journal (`renovate-log.ndjson`) : quelles dépendances ont été trouvées dans `mediagenda/api` ? Lesquelles n'ont pas pu être consultées, et pourquoi ?
7. Relis les MR ouvertes : une MR d'empreinte d'image de base (Dockerfile), une MR de dépendance Python, une de module Go. La chaîne de E09 tourne-t-elle sur la MR ? Fusionne une MR de correctif à la main si la fusion automatique attend encore la maturité ; laisse la majeure ouverte avec un commentaire.
8. Documente `docs/registre/renovate.md` : ce que fait Renovate, quand, ce qui fusionne seul, comment exclure une dépendance, comment renouveler le jeton (date d'expiration au registre des secrets).

**Critères de réussite**
- [ ] `plateforme/renovate-runner` (v26.1.0), `plateforme/renovate` et `plateforme/renovate-config` existent ; `plateforme/renovate` a une planification active et son dernier pipeline planifié a réussi.
- [ ] `renovate-bot` existe, n'est pas administrateur ; `RENOVATE_TOKEN` est protégée et masquée.
- [ ] Le préréglage épingle les images par empreinte, déclare les alias des caches, limite la fusion automatique aux correctifs et impose un délai de maturité.
- [ ] Chaque projet traité a un `renovate.json` sur `main` qui étend le préréglage ; au moins une MR de `renovate-bot` existe dans `mediagenda/api`.

**Vérification** : `lab/bin/check 13 11`

<details><summary>Indice 1</summary>

Un préréglage d'un dépôt GitLab de la même instance s'étend par `local>plateforme/renovate-config`. Pour un cache Harbor, Renovate consulte l'amont si on lui dit que `registry.par1.medisphere.internal/dockerhub` est un alias de `docker.io` : le cache ne liste pas les étiquettes qu'il n'a jamais tirées.
</details>

<details><summary>Indice 2</summary>

`config.js` est un module Node : `process.env.NOM` y lit une variable. Une variable de CI de type **fichier** donne un chemin : c'est ce qu'attend `NODE_EXTRA_CA_CERTS`. La fusion automatique côté plateforme (`platformAutomerge`) s'appuie sur « fusionner quand le pipeline réussit » de GitLab.
</details>

**Pour aller plus loin** (facultatif) : le tableau de bord des dépendances (*Dependency Dashboard*) ouvre un ticket récapitulatif par projet ; active-le sur `mediagenda/api` et regarde ce qu'il apporte à la revue hebdomadaire.

---

### M13-E12 — Revue : la chaîne de livraison du stagiaire  `REV` `★★`

> **Ticket PLAT-1412** — *De : Lucas Martin* — *Copie : Karim Benali*
> J'ai essayé de faire la chaîne de livraison de MédiNotif tout seul pendant que vous étiez sur MédiAgenda ! Ça marche, l'image est dans Harbor et signée. J'ai aussi branché Renovate dessus. Karim m'a dit de te demander une relecture avant de fusionner, il trouve que « ça marche » n'est pas un critère. Mes fichiers sont dans la MR.

**Objectifs pédagogiques**
- Relire une chaîne de livraison et une configuration Renovate sous l'angle de la sécurité de la chaîne d'approvisionnement.
- Hiérarchiser les défauts (risque immédiat, fragilité, style) et proposer un correctif pour chacun.

**Prérequis** : M13-E05 à M13-E11.
**Durée indicative** : 1 h 30.

**Contexte technique** : les fichiers de Lucas sont dans [`ressources/E12-medinotif-lucas/`](../ressources/E12-medinotif-lucas/) : le `.gitlab-ci.yml` de `medinotif/worker`, son `renovate.json`, le `config.js` qu'il propose pour `plateforme/renovate`, un `.trivyignore`, et les autres fichiers de sa branche.

**Travail demandé**

1. Lis tous les fichiers sans rien exécuter.
2. Relève **au moins dix** défauts. Pour chacun : fichier et ligne, ce qui ne va pas, le **risque** concret (qui peut faire quoi, ce qui peut casser), la gravité (bloquant, important, mineur) et le correctif proposé.
3. Indique ce qu'il faut faire **immédiatement**, avant même de répondre à Lucas, pour l'un au moins des défauts (pense à ce qui a déjà été poussé).
4. Rédige ta revue dans `docs/registre/revues/revue-medinotif-lucas.md` (dépôt `plateforme/medisphere`), comme un commentaire de MR bienveillant et précis : défauts numérotés, du plus grave au moins grave, avec une phrase pour ce qui est bien fait.

**Critères de réussite**
- [ ] Au moins dix défauts réels relevés, chacun avec son risque et son correctif.
- [ ] Les défauts bloquants (secrets, signature, blocage des vulnérabilités) sont en tête et l'action immédiate est identifiée.
- [ ] La revue est sur `main` de `plateforme/medisphere`, avec au moins dix points numérotés.

**Vérification** : `lab/bin/check 13 12` (présence et forme de la revue) ; le fond s'auto-évalue avec le corrigé.

<details><summary>Indice 1</summary>

Pour chaque job, demande-toi : quelle image, épinglée comment ; quels secrets, exposés comment ; ce que le job fait **en cas d'échec** ; sur quelle référence (étiquette ou empreinte) il agit.
</details>

<details><summary>Indice 2</summary>

Ne te limite pas au pipeline : un fichier ajouté « pour tester » dans une branche poussée reste dans l'historique de Git, même s'il est retiré ensuite.
</details>
