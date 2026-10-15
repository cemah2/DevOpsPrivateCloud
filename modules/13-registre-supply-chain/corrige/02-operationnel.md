# Module 13 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Même organisation qu'au palier 1 ([`fichiers/`](fichiers/), un dossier par exercice, extraits des projets, superposés dans l'ordre). État final de l'état OpenTofu `registre` : `M13-E03` + `M13-E04/caches.tf` + `M13-E05/analyse.tf` + `M13-E10/projets.tf` (qui remplace ceux de E03 et E06) + `M13-E10/politiques.tf` + `M13-E11/robots-renovate.tf` (+ l'extrait de `M13-E09/robots.tf.extrait`).

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Cosign 3.1.3* (binaire officiel, empreinte contrôlée) contre un registre `registry:3` local : `cosign signing-config create --out …` sans service produit `{"mediaType":"application/vnd.dev.sigstore.signingconfig.v0.2+json","rekorTlogConfig":{},"tsaConfig":{}}` ; `cosign sign --key env://COSIGN_KEY --signing-config <ce fichier>` signe **sans** demander de confirmation et le bundle stocké a `tlogEntries` vide ; `cosign verify --key cosign.pub --insecure-ignore-tlog=true` réussit ; une autre clé échoue ; `cosign attest --type spdxjson` puis `verify-attestation --type spdxjson` réussissent (`predicateType: https://spdx.dev/Document`, `subject` = nom et empreinte), `--type cyclonedx` échoue tant qu'aucune attestation CycloneDX n'existe ; `--tlog-upload=false` seul est **refusé** (« not supported with --signing-config or --use-signing-config ») ; `--use-signing-config=false --tlog-upload=false` fonctionne avec un avertissement de dépréciation ; **sans** configuration de signature, Cosign a signé **et envoyé l'entrée au Rekor public sans aucune question** (bundle avec une entrée de journal et un horodatage) ; signer une étiquette affiche l'avertissement « uses a tag, not a digest » ; le référent a pour `artifactType` `application/vnd.dev.sigstore.bundle.v0.3+json`, un `subject` vers l'index, et chaque `cosign sign` ajoute un référent (ce n'est pas idempotent). Le registre local n'ayant pas l'API *Referrers*, Cosign a utilisé l'étiquette de repli `sha256-<empreinte>` ; Harbor 2.15, lui, sert l'API.
- *BuildKit / Buildx 0.37.1 (Docker 29.8.2)* : `--provenance=mode=max` ajoute à l'index un manifeste `unknown/unknown` annoté `vnd.docker.reference.type: attestation-manifest`, couche `application/vnd.in-toto+json` de prédicat `https://slsa.dev/provenance/v1` ; `imagetools inspect --format '{{json .Provenance}}'` donne `.SLSA.buildDefinition` et `.SLSA.runDetails` (`builder.id` vide pour une construction locale).
- *Image outillée* : le `Dockerfile` de l'image `plateforme/outils-supply-chain` (dossier `images/outils-supply-chain/` de `plateforme/ci-templates`) a été construit (base `debian:trixie-slim` substituée à `bibliotheque/debian`) : les quatre empreintes SHA-256 épinglées passent `sha256sum -c`, Cosign 3.1.3, Trivy 0.75.0, Syft 1.54.1, Grype 0.120.1, Skopeo 1.18.0 répondent, utilisateur 10001. Dans cette image, sur une archive OCI produite par BuildKit : `skopeo copy … docker-archive:` puis `trivy image --input` fonctionne, **`trivy image --input` sur l'archive OCI elle-même échoue** (Trivy lit une archive `docker save` ou un **dossier** OCI) ; `syft scan oci-archive:image.tar --platform linux/amd64` et `grype sbom:` fonctionnent ; `skopeo copy --all --preserve-digests` publie l'index à l'empreinte annoncée par `--metadata-file` ; une étiquette absente renvoie « manifest unknown ».
- *Renovate 44.145.3* : `renovate-config-validator` accepte `default.json` (`--strict`) et `config.js`. *OpenTofu* : comme au palier 1. *YAML* : `yamllint` sur tous les fichiers ; aucun élément de `script:` n'est lu comme une table (contrôle Python).

**Non testés en conditions réelles** : la chaîne `templates/supply-chain.yml` complète sur `runner02` (BuildKit rootless sous l'exécuteur Docker et son fichier `buildkitd.toml`, la variable d'instance de type fichier `MEDISPHERE_ROOT_CA`, `resource_group` avec variable, la lecture de l'index dans l'archive OCI par `tar`, `skopeo copy --digestfile` avec `--all`) ; l'affichage des signatures et attestations Cosign 3 comme accessoires dans Harbor 2.15 ; la SBOM générée par Harbor (`sbom_overview`) ; la fusion automatique de Renovate sur GitLab CE 19.4 ; les champs exacts des réponses de rétention et de ramasse-miettes lus par `check-E10.sh`. ⚠️ À vérifier sur ton lab.

---

### M13-E06 — SBOM avec Syft, analyse avec Grype

**Solution**

Fichiers : [`host_vars/adm01/outils_supply_chain.yml`](fichiers/M13-E06/ansible/inventories/lab/host_vars/adm01/outils_supply_chain.yml) (le rôle complet est dans `M13-E05` : Syft et Grype y sont déjà décrits), [`registre/projets.tf`](fichiers/M13-E06/infra/registre/projets.tf), [`outils/sbom-images.sh`](fichiers/M13-E06/outils/sbom-images.sh), [`comparaison-analyseurs.md`](fichiers/M13-E06/medisphere/docs/registre/comparaison-analyseurs.md).

1. Anchore signe `syft_1.54.1_checksums.txt` (bundle `…_checksums.txt.sigstore.json`, identité du workflow `release.yaml` sur `refs/heads/main`) ; le rôle vérifie la signature du fichier puis la présence de la ligne `<empreinte épinglée>  <paquet>`. Aussi sûr : le fichier signé **lie** chaque nom de paquet à son empreinte ; falsifier le paquet changerait son empreinte, falsifier le fichier casserait la signature. Remarque : l'identité porte une **branche** (`main`) et non l'étiquette : elle prouve « publié par le workflow officiel », pas « pour la version 1.54.1 » ; c'est l'empreinte épinglée qui fixe la version.
2. `printf '%s' "$HARBOR_PASSWORD" | cosign login registry.par1.medisphere.internal -u "$HARBOR_USER" --password-stdin` (après `. ~/.config/workbook/harbor-moi.env`) puis `chmod 600 ~/.docker/config.json`. Le fichier contient l'identifiant **en base64, pas chiffré**.
3. `~/src/outils/sbom-images.sh` : empreinte résolue une fois, une analyse Syft (`registry:<nom>@<empreinte>`) et deux sorties. Lecture :
   ```
   admin@adm01:~/m13/e06$ jq '.packages | length, (map(.externalRefs[]? | select(.referenceType == "purl") | .referenceLocator | split(":")[1] | split("/")[0]) | group_by(.) | map({(.[0]): length}) | add)' mediagenda-api.spdx.json
   admin@adm01:~/m13/e06$ jq '.relationships[] | select(.relationshipType == "DESCRIBES" or .relationshipType == "CONTAINS")' mediagenda-api.spdx.json | head
   ```
   Composants `pkg:deb/debian/…` (image de base), `pkg:pypi/…` (environnement virtuel), et, pour MédiDoc, `pkg:golang/…` lus dans les informations de construction du binaire.
4. `grype db status` (schéma v6, date de construction) ; `grype sbom:mediagenda-api.spdx.json --only-fixed -o json --file mediagenda-api.grype.json`. Six mois plus tard, l'image a pu être supprimée par la rétention, ou elle est en production et la tirer de nouveau n'est pas souhaitable ; la SBOM conservée décrit **ce qui a été livré**, et sa nouvelle analyse contre une base à jour suffit pour une alerte CVE (M13-E18).
5. Écarts typiques et leurs causes : voir le modèle de `comparaison-analyseurs.md` (catalogues, bases, correspondance, notion de correctif, sévérités). `trivy image --format spdx-json` compte autrement (les fichiers du système d'exploitation, la manière de rattacher les paquets Python).
6. `auto_sbom_generation = true` sur `medisphere`, `plateforme`, `bibliotheque` ; dans l'IHM, l'artefact a un onglet « SBOM » (génération par Trivy, format SPDX) ; téléchargement et comparaison : même ordre de grandeur que Trivy, pas que Syft.
7. La SBOM de **référence** est celle de la CI (Syft), attestée et signée (E08, E09) ; celle de Harbor sert de contrôle croisé. En garder deux comme « référence » donne deux vérités en cas d'alerte.

**Explications**

Une SBOM n'est pas un rapport de vulnérabilités : c'est un **inventaire** qui ne vieillit pas (la liste des composants d'une empreinte ne change jamais), alors qu'un rapport de vulnérabilités vieillit chaque jour. C'est ce qui permet de répondre à « sommes-nous touchés ? » en interrogeant des fichiers plutôt qu'en réanalysant le registre.

**Alternatives**

- SBOM produite par BuildKit (`--sbom=true`, générateur `docker/buildkit-syft-scanner`) : rangée dans l'index comme la provenance, mais l'image du générateur vient de Docker Hub et n'est pas signée par nous.
- Dependency-Track (OWASP) : base de SBOM CycloneDX avec suivi continu des vulnérabilités ; pertinent quand le nombre d'images grandit.

**Pièges classiques**

- Analyser `mediagenda-api:latest` (ou l'étiquette) puis attester la SBOM sur une autre empreinte.
- `syft <image>` sans préfixe : Syft essaie d'abord un démon Docker local ; sur `adm01`, préfixe `registry:`.
- Comparer des comptes de composants sans regarder **quels** composants diffèrent.
- `~/.docker/config.json` lisible par d'autres (créé en 644 selon l'outil).

**En production chez MédiSphère**

SBOM de chaque version conservée deux fois (référent dans Harbor, artefact du pipeline exporté vers un compartiment S3 versionné), inventaire consolidé interrogeable (M13-E18), second avis de Grype planifié chaque semaine.

---

### M13-E07 — Signer et vérifier avec Cosign

**Solution**

Fichiers : [`signing-config.json`](fichiers/M13-E07/medisphere/docs/registre/signing-config.json), [`cosign.pub.exemple`](fichiers/M13-E07/medisphere/docs/registre/cosign.pub.exemple), [`signature.md`](fichiers/M13-E07/medisphere/docs/registre/signature.md), [`secrets/cosign/LISEZMOI.md`](fichiers/M13-E07/ansible/secrets/cosign/LISEZMOI.md), [`outils/cosign-cle.sh`](fichiers/M13-E07/outils/cosign-cle.sh), [`outils/signer-image.sh`](fichiers/M13-E07/outils/signer-image.sh), [`outils/variables-ci-cosign.sh`](fichiers/M13-E07/outils/variables-ci-cosign.sh).

1. Options (Cosign 3.1.3) : `--use-signing-config` (vrai par défaut : configuration **publique** de Sigstore, récupérée par TUF), `--signing-config <fichier>` (configuration locale), `--tlog-upload` (déprécié depuis 3.0.3 : « prefer using a --signing-config file with no transparency log services », et refusé avec une configuration de signature), `--insecure-ignore-tlog` à la vérification.
2. Génération en mémoire :
   ```
   admin@adm01:~$ install -d -m 700 /dev/shm/cle && cd /dev/shm/cle
   admin@adm01:/dev/shm/cle$ python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > mdp && chmod 600 mdp
   admin@adm01:/dev/shm/cle$ COSIGN_PASSWORD="$(<mdp)" cosign generate-key-pair
   Private key written to cosign.key
   Public key written to cosign.pub
   admin@adm01:/dev/shm/cle$ cd ~/src/ansible && install -d secrets/cosign && cp /dev/shm/cle/cosign.key secrets/cosign/cosign.key
   admin@adm01:~/src/ansible$ uv run ansible-vault encrypt --vault-id critique@outils/vault-pass-client.sh secrets/cosign/cosign.key
   admin@adm01:~/src/ansible$ printf 'vault_cosign_mdp: "%s"\n' "$(</dev/shm/cle/mdp)" > inventories/lab/group_vars/all/vault-critique-cosign.yml
   admin@adm01:~/src/ansible$ uv run ansible-vault encrypt --vault-id critique@outils/vault-pass-client.sh inventories/lab/group_vars/all/vault-critique-cosign.yml
   admin@adm01:~/src/ansible$ cp /dev/shm/cle/cosign.pub ~/medisphere/docs/registre/cosign.pub
   admin@adm01:~$ shred -u /dev/shm/cle/cosign.key /dev/shm/cle/mdp && rmdir /dev/shm/cle
   admin@adm01:~$ . ~/src/outils/cosign-cle.sh      # relecture depuis le Vault
   ```
   ⚠️ La copie de `cosign.key` dans `secrets/cosign/` est en clair **jusqu'au chiffrement** : ne fais rien d'autre entre les deux commandes, et vérifie `head -1 secrets/cosign/cosign.key` (`$ANSIBLE_VAULT;1.2;AES256;critique`) avant tout `git add`.
3. `cosign signing-config create --out ~/medisphere/docs/registre/signing-config.json` (aucun service) ; `jq` : seulement `mediaType`, `rekorTlogConfig: {}`, `tsaConfig: {}`. MR « clé publique et configuration de signature » relue par Karim et Sophie (une MR qui change `cosign.pub` est un changement de sécurité).
4. Signature :
   ```
   admin@adm01:~$ IMG=registry.par1.medisphere.internal/medisphere/mediagenda-api
   admin@adm01:~$ D=$(skopeo inspect --format '{{.Digest}}' docker://$IMG:<VERSION>)
   admin@adm01:~$ cosign sign --key env://COSIGN_KEY --signing-config ~/medisphere/docs/registre/signing-config.json $IMG@$D
   Pushing signature to: registry.par1.medisphere.internal/medisphere/mediagenda-api
   ```
   (ou `~/src/outils/signer-image.sh $IMG:<VERSION>`, qui refuse une configuration contenant un service et vérifie ensuite.)
5. Vérification et stockage :
   ```
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true $IMG@$D | jq '.[0].critical'
   admin@adm01:~$ cosign tree $IMG@$D
   └── 🔗 https://sigstore.dev/cosign/sign/v1 artifacts via OCI referrer: …@sha256:…
   admin@adm01:~$ curl -s --netrc-file ~/.config/workbook/harbor-moi.netrc -H 'Accept: application/vnd.oci.image.index.v1+json' \
       https://registry.par1.medisphere.internal/v2/medisphere/mediagenda-api/referrers/$D | jq '.manifests[] | {artifactType, digest}'
   ```
   `artifactType` : `application/vnd.dev.sigstore.bundle.v0.3+json` ; le manifeste de l'image **n'a pas changé** (même empreinte) : la signature est un objet à part, qui le désigne par `subject`. (`harbor-moi.netrc` : fichier `netrc` en 600 fabriqué depuis `harbor-moi.env` le temps de l'exploration, comme `harbor-admin.netrc` en E03, puis effacé. ⚠️ L'API `/v2/…/referrers/` de Harbor demande un jeton du registre ; si `curl` avec `--netrc-file` reçoit 401, passe par `oras discover` ou `cosign tree`, M13-E23 détaille l'échange de jeton.) Contrôle de l'absence de journal : télécharger la couche du référent et vérifier `jq '.verificationMaterial.tlogEntries | length'` = 0.
6. Refus : autre clé → `error during command execution: no matching signatures` ; autre empreinte non signée → même erreur ; signature d'étiquette → avertissement « uses a tag, not a digest » (Cosign résout l'étiquette **à cet instant** et signe l'empreinte obtenue) ; si l'étiquette est ensuite déplacée vers une autre image, `cosign verify $IMG:<VERSION>` résout la **nouvelle** empreinte, qui n'est pas signée : refus. La signature n'a pas suivi l'étiquette — c'est voulu, et c'est pourquoi on signe et vérifie des empreintes.
7. Les trois autres images (`signer-image.sh`), puis `variables-ci-cosign.sh` : `COSIGN_PRIVATE_KEY` de type **fichier** (une clé PEM multiligne ne peut pas être masquée ; le type fichier évite qu'elle apparaisse développée dans une commande), protégée ; `COSIGN_PASSWORD` protégée et masquée.
8. Paragraphe *keyless* : voir `signature.md`.

**Explications**

Sans journal ni horodatage, la vérification ne porte que sur « cette empreinte a été signée par cette clé ». C'est suffisant pour un registre privé, à deux conditions : la clé est rare (Vault, CI protégée), et la **révocation** est prête (retirer la clé publique, re-signer). C'est le prix de la confidentialité de l'inventaire.

**Alternatives**

- Clé dans un **KMS** (`--key hashivault://…`, OpenBao au M25) : la clé ne quitte jamais le coffre, la CI demande une signature.
- *Keyless* avec Fulcio/Rekor privés et l'OIDC de GitLab : voir `signature.md` et l'ADR-0130.
- **Notation** (Notary Project, CNCF) avec des certificats X.509 de la PKI MédiSphère : intéressant parce que la PKI existe (M06) ; Harbor l'affiche aussi.

**Pièges classiques**

- Oublier `--signing-config` : la signature part dans le journal public, **sans question**, et ne s'efface pas.
- `--yes` par habitude (il supprimerait les confirmations qui existent, par exemple en *keyless*).
- Clé privée tapée en argument, ou laissée dans `/tmp`, ou en clair dans l'historique (`history`).
- Vérifier avec la `cosign.pub` du poste au lieu de celle du dépôt.
- Croire qu'une deuxième signature remplace la première : elles s'accumulent (référents).

**En production chez MédiSphère**

Clé dans OpenBao (transit) ou un HSM, cérémonie de génération à deux, rotation annuelle documentée, vérification imposée au déploiement (Harbor au palier 3, Kyverno `verifyImages` au M26), alerte sur toute signature faite hors de la CI.

---

### M13-E08 — Attestations : SBOM et provenance attachés à l'image

**Solution**

Fichier : [`signature.md.extrait`](fichiers/M13-E08/medisphere/docs/registre/signature.md.extrait).

1. Attestation SPDX :
   ```
   admin@adm01:~$ cosign attest --key env://COSIGN_KEY --signing-config ~/medisphere/docs/registre/signing-config.json \
       --type spdxjson --predicate ~/m13/e06/mediagenda-api.spdx.json $IMG@$D
   admin@adm01:~$ cosign verify-attestation --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
       --type spdxjson $IMG@$D | jq -r .payload | base64 -d | jq '{predicateType, subject}'
   {
     "predicateType": "https://spdx.dev/Document",
     "subject": [ { "name": "registry.par1.medisphere.internal/medisphere/mediagenda-api", "digest": { "sha256": "…" } } ]
   }
   ```
   `subject` lie la déclaration à **cette empreinte** : déplacée sur une autre image, l'attestation ne vaut rien.
2. `--type cyclonedx --predicate …cdx.json` ; `cosign tree` liste la signature et deux attestations (référents) ; Harbor les montre comme accessoires de l'artefact.
3. Construction de l'essai sur `runner02` :
   ```
   admin@runner02:~$ git clone https://git01.par1.medisphere.internal/mediagenda/api.git /tmp/e08 && cd /tmp/e08
   admin@runner02:/tmp/e08$ export DOCKER_CONFIG=$(mktemp -d) && chmod 700 "$DOCKER_CONFIG"
   admin@runner02:/tmp/e08$ sudo --preserve-env=DOCKER_CONFIG docker login registry.par1.medisphere.internal -u <MOI> --password-stdin < /dev/stdin
   admin@runner02:/tmp/e08$ sudo --preserve-env=DOCKER_CONFIG docker buildx build --provenance=mode=max \
       -t registry.par1.medisphere.internal/medisphere/mediagenda-api:0.0.0-attest-essai --push .
   ```
   (`docker login --password-stdin` : colle le mot de passe puis Ctrl-D ; à la fin `sudo rm -rf "$DOCKER_CONFIG" /tmp/e08`.)
4. Lecture :
   ```
   admin@runner02:/tmp/e08$ sudo --preserve-env=DOCKER_CONFIG docker buildx imagetools inspect \
       registry.par1.medisphere.internal/medisphere/mediagenda-api:0.0.0-attest-essai --format '{{json .Provenance}}' \
       | jq '.SLSA | {builder: .runDetails.builder, deps: [.buildDefinition.resolvedDependencies[]?.uri], params: .buildDefinition.externalParameters.request.args}'
   ```
   `resolvedDependencies` liste les images de base **par empreinte** (`pkg:docker/…@sha256`), `externalParameters` le Dockerfile, les arguments, la cible ; `runDetails.metadata` les dates ; pour une construction locale `builder.id` est **vide** et le contexte Git n'est renseigné que si BuildKit le voit (contexte Git, ou `BUILDX_GIT_INFO`). Si un attaquant contrôle `runner02`, il écrit la provenance qu'il veut : elle n'est fiable que si le constructeur l'est. Niveau : **SLSA Build L1** (voir l'extrait).
5. Index brut : un manifeste `linux/amd64` et un manifeste `unknown/unknown` annoté `vnd.docker.reference.type: attestation-manifest` et `vnd.docker.reference.digest: <empreinte du manifeste de l'image>`, dont la couche est un relevé in-toto **non signé**. Une attestation Cosign est un **référent signé** hors de l'index. Signer l'**index** avec Cosign couvre ses entrées, donc l'empreinte du manifeste de provenance : la provenance de BuildKit devient « signée par transitivité ». C'est ce que fait la chaîne de E09.
6. Suppression de l'étiquette d'essai (IHM, ou API `DELETE /projects/medisphere/repositories/mediagenda-api/artifacts/0.0.0-attest-essai/tags/0.0.0-attest-essai`), après lecture de l'empreinte.
7. Section « Attestations » de `signature.md`.

**Explications**

Deux mécanismes coexistent : l'attestation **dans l'index** (BuildKit, standard Docker, lue par `imagetools`) et l'attestation **référent signé** (Cosign, in-toto/DSSE, lue par `verify-attestation`, et par Kyverno au M26). MédiSphère exige les deux : la provenance de BuildKit (faite par le constructeur) sous la signature de l'index, la SBOM en attestation Cosign (vérifiable indépendamment).

**Alternatives**

- Attestation SLSA par Cosign (`--type slsaprovenance1 --predicate provenance.json` extrait de BuildKit) : une provenance vérifiable par `verify-attestation`, comme la SBOM.
- Attestation de résultat d'analyse (`--type vuln`) : utile pour prouver « analysée et sans critique corrigeable à telle date ».

**Pièges classiques**

- Attester la SBOM d'une **autre** image (étiquette résolue deux fois).
- `docker build` sans `--push` avec l'ancien stockage d'images : les attestations ne sont pas conservées localement (avec le stockage containerd de Docker 29, elles le sont).
- Oublier `--type` à la vérification : Cosign cherche le type `custom`.
- Laisser l'identifiant Harbor dans `/root/.docker/config.json` de `runner02`.

**En production chez MédiSphère**

Provenance produite par une plateforme de construction isolée, clé de signature inaccessible au code des jobs (SLSA L3), politique d'admission qui exige provenance et SBOM (M26).

---

### M13-E09 — La chaîne de livraison d'une image

**Solution** (une solution parmi d'autres ; ce qui compte : l'empreinte transmise, l'ordre, les secrets, le blocage)

Fichiers : [`ci-templates/templates/supply-chain.yml`](fichiers/M13-E09/ci-templates/templates/supply-chain.yml), [`images/outils-supply-chain/Dockerfile`](fichiers/M13-E09/ci-templates/images/outils-supply-chain/Dockerfile) et son [`LISEZMOI.md`](fichiers/M13-E09/ci-templates/images/outils-supply-chain/LISEZMOI.md), [`gitlab-ci.yml.extrait`](fichiers/M13-E09/ci-templates/gitlab-ci.yml.extrait) (pipeline de `plateforme/ci-templates`), [`robots.tf.extrait`](fichiers/M13-E09/infra/registre/robots.tf.extrait) (`robot$plateforme+ci`), [`mediagenda-api/.gitlab-ci.yml`](fichiers/M13-E09/mediagenda-api/.gitlab-ci.yml), [`chaine-livraison.md`](fichiers/M13-E09/medisphere/docs/registre/chaine-livraison.md).

Conception :

| Contrainte | Réponse |
|---|---|
| Empreinte de bout en bout | `sc:construction` lit `containerimage.digest` dans `--metadata-file` (index, provenance comprise), la transmet en `dotenv` ; `sc:publication` vérifie que l'index de l'archive et l'empreinte publiée (`skopeo copy --digestfile`) sont les mêmes, transmet `SC_REF=<dépôt>@<empreinte>` ; signature et vérification n'utilisent que `SC_REF` |
| Sans privilège | `moby/buildkit:v0.34.0-rootless` (`buildctl-daemonless.sh`, `--oci-worker-no-process-sandbox`), réglages d'exécuteur de M12-E21 ; racine MédiSphère dans `buildkitd.toml` |
| Analyse avant publication | construction vers une **archive OCI** (`--output type=oci`) ; Trivy lit une conversion `docker-archive` de la plateforme (Trivy ne lit pas l'archive OCI elle-même) ; rapport complet non bloquant + contrôle `CRITICAL --ignore-unfixed --exit-code 1`, `.trivyignore` du projet |
| SBOM | Syft sur `oci-archive:image.tar`, SPDX + CycloneDX en artefacts (1 an) puis attestés |
| Publication | `skopeo copy --all --preserve-digests`, robot du projet par `--password-stdin` ; refus si l'étiquette existe, erreur si le registre ne répond pas ; `main` → `main-<sha court>` ; `vX.Y.Z` seulement sur étiquette Git (protégée : sinon pas de secrets) |
| Signature | `cosign sign` + `cosign attest` (SPDX, CycloneDX) par empreinte, clé en variable **fichier**, `--signing-config` sans journal (dans l'image outillée) |
| Vérification | présence du manifeste de provenance dans l'index de l'archive (avant publication), puis `cosign verify` et `verify-attestation --type spdxjson` sur `SC_REF` ; aucun job ne relit l'image par `skopeo` après la poussée : avec les politiques de M13-E14, Harbor refuse de servir une image pas encore signée et analysée (Cosign et le scanner sont exemptés) |
| Outils | image `plateforme/outils-supply-chain` (paquets épinglés par SHA-256, clé publique, configuration de signature, racine), construite depuis `bibliotheque/debian` et publiée par `robot$plateforme+ci` ; images de jobs par Harbor, `étiquette@sha256` |
| Racine MédiSphère | variable d'instance `MEDISPHERE_ROOT_CA` (Admin → CI/CD → Variables, type **fichier**, non protégée : la racine est publique), créée ici ; BuildKit la reçoit dans `buildkitd.toml`, Renovate (E11) et M17 la réutilisent |
| Réutilisable | variables `SC_*`, documentation en tête et dans `chaine-livraison.md` ; fichier dans `templates/` comme les gabarits de M01 et M12 ; le projet déclare la liste complète des stages (`lint`, `test`, ceux de la chaîne, `release`) et inclut une **étiquette** `v1.x.y` du dépôt de gabarits |

Preuve de la double publication : relancer le job `sc:publication` du pipeline de l'étiquette → `REFUS : medisphere/mediagenda-api:v1.4.0 existe déjà dans Harbor` (et, après E10, Harbor refuse aussi la poussée d'une étiquette `v*` existante).

**Explications**

- **Pourquoi publier avant de signer.** La signature est un référent **dans le registre** : il faut que l'image y soit. Entre la publication et la signature (quelques secondes), l'image est tirable non signée ; la politique « signature exigée » du palier 3 (M13-E14) ferme cette fenêtre : Harbor refuse de servir une image non signée.
- **Pourquoi une archive OCI.** Une image poussée « pour l'analyser » serait tirable avant d'être analysée ; l'archive garde aussi l'index et la provenance tels que BuildKit les a produits, et `--preserve-digests` publie exactement l'empreinte analysée.
- **Pourquoi l'image outillée embarque la clé publique.** La vérification de fin de chaîne ne doit pas dépendre d'un fichier que le projet pourrait remplacer dans sa propre branche. Contrepartie : une rotation de clé exige une nouvelle version de l'image (et d'abord deux clés acceptées, `signature.md`).
- **MR de Renovate.** Elles passent par la même chaîne en mode MR : construction, analyse, SBOM ; rien n'est publié, aucun secret protégé n'est exposé.

**Alternatives**

- Buildah (sans démon, rootless) à la place de BuildKit ; Kaniko est archivé depuis 2025, à éviter.
- Pousser directement depuis BuildKit vers une étiquette temporaire (`…:ci-<id>`) puis promouvoir après analyse : plus rapide pour les grosses images, mais des images non analysées existent dans le registre.
- `--recursive` sur `cosign sign` pour signer aussi chaque manifeste de plateforme (utile si des consommateurs tirent par l'empreinte d'une plateforme, multi-architecture).

**Pièges classiques**

- Variable `HARBOR_ROBOT_USER` **développée** : `robot$medisphere+ci` devient `robot+ci`, la connexion échoue. Et elle ne peut pas être **masquée** (`$` hors de l'alphabet admis) : ce n'est pas un secret.
- Étiquettes Git `v*` non protégées : le pipeline de l'étiquette n'a pas accès aux variables protégées, la publication échoue (c'est la bonne protection : un développeur ne publie pas une version en posant une étiquette).
- `allow_failure: true` sur l'analyse « en attendant » : il ne sera jamais retiré.
- Images de Cosign ou Syft officielles : pas de shell, le job ne démarre pas.
- Une ligne de `script:` contenant `: ` (deux-points espace) devient une **table** YAML : bloc `|` ou guillemets.
- Re-résoudre `vX.Y.Z` au moment de signer : une autre exécution concurrente a pu la créer entre-temps (d'où aussi `resource_group`).
- Relire l'image publiée par `skopeo inspect` pour contrôler son empreinte : dès que la signature est exigée (M13-E14), Harbor répond `412` tant que l'image n'est pas signée et analysée, et la chaîne casse. L'empreinte publiée se lit dans `--digestfile`.
- Oublier la liste des stages dans le projet : `templates/qualite.yml` et `templates/supply-chain.yml` déclarent chacun les leurs, seul le dernier inclus compte, et les jobs de `lint` ou de `release` deviennent invalides.

**En production chez MédiSphère**

Chaîne exécutée sur des runners Kubernetes éphémères (M19), clé de signature par KMS, vérification au déploiement (Argo CD, Kyverno : M20, M26), métriques de la chaîne (durées, échecs par étape, M21), SBOM exportées vers un inventaire central.

---

### M13-E10 — Quotas, rétention et immuabilité des étiquettes

**Solution**

Fichiers : [`registre/projets.tf`](fichiers/M13-E10/infra/registre/projets.tf) (version finale : quotas), [`registre/politiques.tf`](fichiers/M13-E10/infra/registre/politiques.tf), [`stockage.md`](fichiers/M13-E10/medisphere/docs/registre/stockage.md) ; quotas des caches dans `M13-E04/caches.tf`.

1. Mesure : `GET /api/v2.0/projects/<projet>/summary` (`quota.used.storage`, `quota.hard.storage`, en octets) et `df -h /data` sur `reg01`. Quota atteint : la poussée est **refusée** (le client reçoit une erreur de quota sur le blob ou le manifeste qui dépasse) ; rien n'est corrompu, mais la CI ne publie plus. Somme des quotas (160 Gio) sous la taille du disque : un quota ne compte que les blobs, pas la base, les rapports, les envois en cours, ni l'espace dont le ramasse-miettes a besoin.
2. Rétention : un artefact est **gardé si au moins une règle le retient** (OU) ; tout le reste est supprimé. Les **accessoires** (signatures, attestations) ne sont pas évalués seuls : ils partent avec leur artefact. Les artefacts **sans étiquette** sont évalués si `untagged_artifacts = true`.
3. Simulation : « Policy > Tag Retention > DRY RUN », puis le journal de l'exécution (liste « retained / deleted ») ; aucun `v*` dans « deleted ». Ensuite seulement, la planification (déclarée dans `politiques.tf`) est utile.
4. Immuabilité (`harbor_immutable_tag_rule`, `v*`). Repousser une autre image sous `v1.4.0` : refus (« … configured as immutable, cannot be updated ») ; supprimer l'étiquette : refus. Signer reste possible : la signature est un **nouvel artefact référent**, l'étiquette `v1.4.0` ne bouge pas.
5. Ramasse-miettes (`harbor_garbage_collection`, cron `0 0 3 * * 0`) ; « Administration > Clean Up > DRY RUN » puis « GC NOW » ; `df` avant/après sur `reg01`. Une suppression ne fait que retirer des **références** ; les blobs, partagés entre images (couches de base communes), ne sont supprimés que lorsqu'aucune image ne les référence, ce que seul le ramasse-miettes calcule.
6. `stockage.md`.

**Explications**

La rétention et le ramasse-miettes sont deux étapes : la rétention décide **quelles images** disparaissent, le ramasse-miettes **libère les blobs** qui ne servent plus. Depuis Harbor 2.1, le ramasse-miettes n'interrompt plus les poussées.

**Alternatives**

- `n_days_since_last_pull` pour les images de suivi (garder ce qui sert encore) ; `most_recently_pulled` pour les caches.
- Quotas plus serrés et alertes plus tôt ; stockage objet extensible au lieu d'un disque fixe.

**Pièges classiques**

- Règle unique « garder les 10 derniers » : les vieilles versions `v*` encore en production disparaissent.
- Immuabilité posée **avant** d'avoir corrigé la chaîne : on ne peut plus repousser une version ratée (il faut en publier une nouvelle : c'est le comportement voulu).
- Les images migrées du M12 (E03) portent des étiquettes `X.Y.Z` **sans** `v` : ni la règle « toujours garder `v*` » ni l'immuabilité ne les couvrent. La simulation de rétention les montre dans « deleted » dès que dix artefacts plus récents existent : décide (règle de rétention supplémentaire sur `[0-9]*` le temps de la transition, ou départ assumé une fois `vX.Y.Z` publiée par la chaîne) et écris-le dans `stockage.md`.
- Cron à cinq champs : Harbor attend six champs (secondes).
- S'étonner que `/data` ne baisse pas après une rétention : le ramasse-miettes n'est pas encore passé.

**En production chez MédiSphère**

Alertes de quotas et de disque (M21), rapport mensuel d'occupation par projet, procédure de retrait d'une version compromise (désactivation temporaire de la règle, tracée).

---

### M13-E11 — Renovate auto-hébergé

**Solution**

Fichiers : [`renovate/.gitlab-ci.yml`](fichiers/M13-E11/renovate/.gitlab-ci.yml), [`renovate/config.js`](fichiers/M13-E11/renovate/config.js), [`renovate-config/default.json`](fichiers/M13-E11/renovate-config/default.json), [`applications/renovate.json`](fichiers/M13-E11/applications/renovate.json) (le même dans chaque projet traité), [`registre/robots-renovate.tf`](fichiers/M13-E11/infra/registre/robots-renovate.tf), [`outils/creer-renovate-bot.sh`](fichiers/M13-E11/outils/creer-renovate-bot.sh), [`renovate.md`](fichiers/M13-E11/medisphere/docs/registre/renovate.md).

1. Le gabarit `templates/renovate.gitlab-ci.yml` (v26.1.0) : job `renovate` avec `rules: - if: '$CI_PIPELINE_SOURCE == "schedule"'`, variables `RENOVATE_PLATFORM: gitlab`, `RENOVATE_ENDPOINT: $CI_API_V4_URL`, `CI_RENOVATE_IMAGE: ghcr.io/renovatebot/renovate:44`, `RENOVATE_REPOSITORY_CACHE`, journal `renovate-log.ndjson` en artefact ; à fournir : `RENOVATE_TOKEN`, la liste ou la découverte des dépôts.
2. Import (« New project > Import project > Repository by URL » vers `https://gitlab.com/renovate-bot/renovate-runner.git`, puis garder l'étiquette `v26.1.0`) : l'inclusion depuis gitlab.com n'est pas possible d'une instance à l'autre, et l'on veut qu'une nouvelle version du gabarit passe par une MR.
3. `creer-renovate-bot.sh` (jeton d'administration de `~/.config/workbook/gitlab-admin.token`). *Developer* plutôt que *Maintainer* : le bot n'a pas à changer les réglages, les protections, les variables des projets. Conséquence : la fusion automatique ne marche que si `main` autorise la fusion aux *Developers* (« Allowed to merge: Developers + Maintainers ») avec « Pipelines must succeed » — dans GitLab CE, sans règles d'approbation obligatoires (fonction payante), c'est la CI verte qui protège. Si tes branches `main` n'autorisent que les *Maintainers*, choisis consciemment : relâcher la fusion aux *Developers* sur ces projets, ou renoncer à la fusion automatique.
4. `robots-renovate.tf` (`robot$renovate`, tirage de `bibliotheque` et `plateforme`) ; variables du projet `plateforme/renovate` : `RENOVATE_TOKEN` (protégée, masquée), `HARBOR_RENOVATE_USER` (protégée, non développée), `HARBOR_RENOVATE_TOKEN` (protégée, masquée) ; variable d'**instance** `MEDISPHERE_ROOT_CA` (créée en E09) ; planification « chaque nuit » `0 4 * * *` sur `main`, fuseau Europe/Paris.
5. Préréglage `default.json` : `pinDigests` pour la source `docker`, `registryAliases` des quatre caches, `minimumReleaseAge: "3 days"`, `automerge` seulement pour `matchUpdateTypes: ["patch"]` avec `platformAutomerge`, majeures et outils de sécurité jamais automatiques, `postUpdateOptions: ["gomodTidy"]`, `prConcurrentLimit: 5`. `uv.lock` est mis à jour par le gestionnaire `pep621` (il lance `uv lock` ; l'image `:44` installe `uv` à la demande, depuis Internet — d'où la sortie de `runner02` vers Internet).
6. Journal (artefact `renovate-log.ndjson`) : `jq -c 'select(.msg == "packageFiles with updates") | .config' renovate-log.ndjson`. Échecs typiques : images de `bibliotheque` sans identifiants (robot oublié), changelogs GitHub limités (sans `RENOVATE_GITHUB_COM_TOKEN`), TLS si `NODE_EXTRA_CA_CERTS` manque (« unable to get local issuer certificate »).
7. MR : « chore(deps): update registry.par1…/dockerhub/library/python:3.13-slim-trixie docker digest to … » (Dockerfile), « fix(deps): update dependency fastapi to v0.142.x » (pyproject + uv.lock), « fix(deps): update module github.com/aws/aws-sdk-go-v2/service/s3 … » (go.mod + go.sum) ; la chaîne de E09 tourne en mode MR. Une MR de correctif attend la maturité (statut « minimumReleaseAge » dans la description) avant d'être fusionnée seule.
8. `renovate.md` ; date d'expiration du jeton au registre des secrets.

**Explications**

Le cache Harbor ne connaît que les étiquettes qu'il a déjà tirées : Renovate y verrait une liste incomplète. `registryAliases` lui fait consulter l'**amont** pour les caches, tout en écrivant le nom du cache dans les fichiers ; l'empreinte proposée est celle de l'amont, donc celle que le cache servira. Les images de `bibliotheque`, elles, sont consultées dans Harbor avec le robot.

**Alternatives**

- Dependabot : pas disponible pour GitLab CE auto-hébergé (GitHub seulement, ou forks communautaires).
- Renovate en `npm`/`npx` sur `runner01` : Node 24 requis, outils de verrouillage à installer à la main ; l'image est plus simple.
- Mises à jour manuelles trimestrielles : c'est l'état d'InfoGér, et la raison du ticket.

**Pièges classiques**

- `NODE_TLS_REJECT_UNAUTHORIZED=0` « pour que ça marche » (E12).
- `autodiscover` sans filtre : le bot traite tout projet où quelqu'un l'ajoute.
- `automerge: true` global, ou `ignoreTests: true` : fusion de majeures, ou fusion malgré une CI rouge.
- Jeton sans date d'expiration (GitLab 19 l'impose) ou oublié au registre des secrets : un matin, plus aucune MR, sans erreur visible ailleurs que dans le journal du job.
- Bot *Maintainer* : il peut modifier les protections de branche.

**En production chez MédiSphère**

Tableau de bord des dépendances par projet, regroupements (`group:`) pour limiter le bruit, revue hebdomadaire des majeures, alerte si le pipeline planifié échoue deux nuits de suite (M21), Renovate pour les charts et manifestes (M17-M20).

---

### M13-E12 — Revue : la chaîne de livraison du stagiaire

**Solution**

Fichiers : une revue modèle [`revue-medinotif-lucas.md`](fichiers/M13-E12/medisphere/docs/registre/revues/revue-medinotif-lucas.md), la version corrigée [`medinotif-worker/.gitlab-ci.yml`](fichiers/M13-E12/medinotif-worker/.gitlab-ci.yml) et [`renovate.json`](fichiers/M13-E12/medinotif-worker/renovate.json).

**Action immédiate.** Le mot de passe d'`admin` de Harbor et `cosign.key` sont dans une branche **poussée** : changer le mot de passe d'`admin` (API de Harbor, puis Vault `critique` et variable `HARBOR_PASSWORD` de `plateforme/infra`), lire le journal d'audit de Harbor depuis la date de la poussée, supprimer la branche et faire purger l'historique (les commits restent accessibles par leur empreinte et dans les MR tant que GitLab ne les a pas nettoyés : `housekeeping` ou suppression de la MR), retirer l'image signée par cette clé. Le job `trivy` a tourné avec **`aquasec/trivy:0.69.5`**, une des images piégées de mars 2026 : considérer **tous** les secrets visibles de ce pipeline comme volés (mot de passe d'`admin`, jeton de job), et suivre la remédiation d'Aqua (chercher un dépôt `tpcp-docs`, des jobs inconnus).

**Défauts** (18 dans les fichiers ; dix suffisent pour valider, les six premiers sont attendus) :

| # | Fichier | Défaut | Risque | Gravité | Correctif |
|---|---|---|---|---|---|
| 1 | `.gitlab-ci.yml` | mot de passe d'`admin` en clair dans `variables:` | administration du registre par tout lecteur du dépôt | bloquant | robot du projet, variables protégées |
| 2 | `cosign.key`, `COSIGN_PASSWORD: ""` | clé privée dans le dépôt, sans phrase de passe | signatures « MédiSphère » par n'importe qui | bloquant | clé MédiSphère en variable fichier protégée |
| 3 | job `trivy` | `aquasec/trivy:0.69.5` (image malveillante) | vol des secrets du pipeline | bloquant | image outillée épinglée par empreinte |
| 4 | job `trivy` | `allow_failure: true`, `--exit-code 0` | image critique publiée | bloquant | contrôle bloquant critique corrigeable |
| 5 | `build` | poussée **avant** analyse | image vulnérable tirable | bloquant | archive OCI, analyse, puis publication |
| 6 | `sign` | signature de `:latest` (étiquette), `verify … \|\| true` | on signe ce que `latest` désigne à cet instant ; vérification inopérante | bloquant | signature et vérification par empreinte, bloquantes |
| 7 | `sign` | `--yes` sans `--signing-config` | nom et empreinte publiés dans Rekor, définitivement | bloquant | configuration de signature sans journal |
| 8 | `.trivyignore` | six CVE sans justification ni date, dont CVE-2024-3094 (xz) | exceptions éternelles | important | format daté et justifié (E05) |
| 9 | `build` | `latest` et étiquettes réécrites, aucune `rules:` | versions mouvantes, publication depuis toute branche | important | `vX.Y.Z` sur étiquette protégée, refus si existante |
| 10 | `build` | `docker:dind` (mode privilégié), `DOCKER_TLS_CERTDIR: ""` | interdit sur `runner02` ; démon Docker sans TLS | important | BuildKit rootless |
| 11 | `sbom` | `curl … install.sh \| sh` depuis `main` | code non épinglé exécuté avec les secrets | important | Syft de l'image outillée |
| 12 | tous | `docker:latest`, `alpine:latest`, `bitnami/cosign:latest` depuis Docker Hub | refusées par `allowed_images`, non épinglées | important | images de Harbor `@sha256` |
| 13 | tous | `GIT_SSL_NO_VERIFY`, `trivy --insecure`, `NODE_TLS_REJECT_UNAUTHORIZED: "0"` | interception possible | important | racine MédiSphère |
| 14 | `build`, `sign` | `-p $HARBOR_PASSWORD` en argument | secret visible dans `ps`, parfois dans le journal | important | `--password-stdin` |
| 15 | `renovate.json` | `automerge` de tout, `ignoreTests: true`, `minimumReleaseAge: null`, `pinDigests: false` | majeures et versions piégées fusionnées malgré une CI rouge | important | étendre le préréglage |
| 16 | `config.js` | jeton GitLab et mot de passe d'`admin` en clair, `autodiscover` sans filtre, `onboarding: true` | prise de contrôle des projets par le jeton ; MR surprises partout | bloquant (secret) | variables, filtre, `requireConfig` |
| 17 | `plateforme/renovate/.gitlab-ci.yml` | pas de `rules:`, image `latest`, pas de gabarit | Renovate à chaque poussée, version flottante | mineur | gabarit importé, planification |
| 18 | `sbom` | SBOM de `latest`, pas de l'image construite | inventaire d'une autre image | mineur | SBOM de l'archive de la construction |

**Explications**

La plupart des défauts viennent d'un même réflexe : « faire passer » le pipeline (désactiver TLS, rendre l'analyse non bloquante, mettre la clé à côté du code, fusionner automatiquement). La correction n'est pas un pipeline plus long : c'est **l'inclusion du gabarit commun**, qui porte déjà les bonnes réponses, et un préréglage Renovate partagé.

**Pièges classiques** (pour le relecteur)

- S'arrêter aux défauts de syntaxe et passer à côté de `0.69.5`.
- Oublier que ce qui a été **poussé** est compromis, même si la MR n'est jamais fusionnée.
- Une revue sans hiérarchie : dix-huit points au même niveau, Lucas corrige d'abord les mineurs.

**En production chez MédiSphère**

Gitleaks dans `qualite.yml` (M01) aurait bloqué la clé et le mot de passe au `pre-commit` et en CI : vérifier qu'il est bien inclus dans `medinotif/worker` ; règle de protection « pas de `variables:` contenant `PASSWORD|TOKEN|SECRET` » dans le gabarit de qualité ; formation des stagiaires à la chaîne commune plutôt qu'aux tutoriels.
