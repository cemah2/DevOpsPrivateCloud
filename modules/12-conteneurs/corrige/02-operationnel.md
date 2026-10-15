# Module 12 — Corrigé du palier 2 : Opérationnel

> ⚠️ Corrigé. Ne le lis qu'après avoir cherché. Les fichiers complets sont dans [`fichiers/`](fichiers/) : `M12-EXX/<projet>/` reproduit l'arborescence du projet GitLab de l'application (`mediagenda-api/` = `mediagenda/api`, `medidoc/` = `medidoc/medidoc`, `medinotif-worker/` = `medinotif/worker`, `legacy-rdv/` = `legacy/legacy-rdv`), `ansible/` celle de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `ci-templates/` celle de `plateforme/ci-templates`, `outils/` celle de `plateforme/outils`, `medisphere/` celle de `plateforme/medisphere`.

**Points vérifiés pour ce corrigé** (2026-10-15, Docker 29.8.2 / BuildKit 0.33 intégré, `moby/buildkit:v0.34.0-rootless`, Podman 5.4.2 en conteneur, Hadolint 2.15.1, Dive 0.13.1, `registry:3` = Distribution 3.1.2, Skopeo 1.18) : constructions des images de E10, E11, E12 (MédiDoc multi-plateformes), E17, E19 ; reproductibilité de MédiDoc et de MédiAgenda 0.2.0 (empreintes identiques) ; fonctionnement du pod MédiAgenda sous Podman 5.4 (secrets `type=env`, sonde en tableau JSON, `podman kube generate`) ; sortie de `quadlet -dryrun` 5.4 (clés refusées, guillemets perdus) ; registre (TLS, htpasswd idempotent, suppression, ramasse-miettes, poussée multi-plateformes) ; arrêt propre de MédiNotif (2,3 s, code 0) ; pile de recette de Legacy-RDV (téléversement de 4,5 Mo, persistance, purge) ; gabarit `image.yml` exécuté hors GitLab dans `moby/buildkit:v0.34.0-rootless` (poussée multi-plateformes, cache, MR sans identifiants, échec sans exceptions de sécurité).

**Non testé en conditions réelles** (à confirmer sur le lab, retours bienvenus) : rôles Ansible appliqués sur les vraies VMs (`registre_travail`, extensions de `docker_engine` et de `gitlab_runner`, `runner02.yml`) ; émission ACME du certificat du registre ; Quadlet sous un vrai systemd utilisateur (ordre de démarrage, redémarrage de `ctr02`, `HealthOnFailure=kill` avec `Restart=`) ; `podman quadlet install` de Podman 5.8 sur Rocky ; script `construire-diag.sh` (Buildah) ; construction arm64 **émulée** de MédiAgenda (le registre public limitait les tirages pendant la rédaction) ; pipelines GitLab réels (workflow sur étiquette, variables de groupe, rapport Code Quality) ; `gitlab-runner verify` et lecture de `/root/.docker/config.json` par le runner.

---

### M12-E10 — Multi-étapes et image minimale pour MédiDoc

**Solution**

Fichiers : [`Dockerfile`](fichiers/M12-E10/medidoc/Dockerfile), [`Dockerfile.scratch`](fichiers/M12-E10/medidoc/Dockerfile.scratch), [`.dockerignore`](fichiers/M12-E10/medidoc/.dockerignore).

1. Projet : `Admin → Groups → New group` `medidoc` (privé), projet `medidoc` dedans ; `git init -b main` dans `~/src/medidoc` (copie de `apps/medidoc/`), `git remote add origin git@git01.par1.medisphere.internal:medidoc/medidoc.git`, premier commit `feat: import de MédiDoc 1.0.0 depuis le workbook`, `git push -u origin main` ; protection de `main` (fusion par MR, personne en poussée directe), membres comme pour `mediagenda/api`. Tests : `go vet ./... && go test ./...` sur `adm01` (Go 1.26 du M02).

2. Notes : `static-debian13` contient les certificats racines de Debian (`/etc/ssl/certs/ca-certificates.crt`), `/etc/passwd` et `/etc/group` (comptes `root`, `nonroot` 65532, `nobody`), `/etc/nsswitch.conf`, les fuseaux horaires (`tzdata`), `/tmp` ; ni shell, ni libc, ni gestionnaire de paquets. `:nonroot` fixe `USER 65532` et le répertoire de travail `/home/nonroot`. Un binaire lié à la glibc cherche `/lib64/ld-linux-x86-64.so.2` : absent, le noyau répond `no such file or directory` en tentant de charger l'interpréteur (le message trompe : c'est le chargeur qui manque, pas le binaire) ; pour un binaire dynamique, il existe `distroless/base-debian13` (glibc) ou `cc-debian13` (+ libgcc).

3. Le Dockerfile : étape `construction` sur `golang:1.26-trixie@sha256:…` ; `COPY go.mod go.sum ./` puis `RUN go mod download && go mod verify` (couche qui ne change qu'avec les dépendances) ; `COPY cmd/ internal/` ; `CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}"` ; étape finale `static-debian13:nonroot@sha256:…`, `COPY --from=construction` du seul binaire, `USER 65532:65532`, `EXPOSE 8080`, `ENTRYPOINT ["/usr/local/bin/medidoc"]`, étiquettes OCI. Le `.dockerignore` commence par `*` et réautorise `go.mod`, `go.sum`, `cmd/`, `internal/`, puis réexclut `**/*_test.go` et le faux S3 des tests (`stockagetest/`, importé par les seuls tests).

4. Mesures relevées sur l'environnement de rédaction :

   | Image | `DISK USAGE` | `CONTENT SIZE` | `docker save \| wc -c` |
   |---|---|---|---|
   | `golang:1.26-trixie` | 1,29 Go | ≈ 300 Mo | — |
   | `medidoc:1.0.0` (distroless) | 32,9 Mo | 7,4 Mo | 7,45 Mo |
   | `medidoc:1.0.0-scratch` | 26,6 Mo | 6,7 Mo | 6,70 Mo |

   Avec le stockage containerd de Docker 29, `DISK USAGE` additionne les couches **compressées** (contenu, tel que transféré) et le **déballage** (*snapshot*) ; `CONTENT SIZE` est le contenu compressé, c'est lui qui passe sur le réseau et que le registre stocke. `docker save` produit une archive OCI de ces blobs compressés : c'est la mesure retenue pour le critère « < 30 Mo ». L'image de compilation, elle, ne quitte jamais `ctr01`.

5. `Config.User` vaut `65532:65532`, `Entrypoint` `["/usr/local/bin/medidoc"]` ; `docker image history` montre les couches de distroless (une par paquet Debian intégré) et la nôtre (le binaire, ≈ 7 Mo compressés). `docker run --entrypoint sh` échoue : `exec: "sh": executable file not found in $PATH` (code 127) : il n'y a pas de shell, c'était le but. Un attaquant qui exploite une faille du service n'a ni shell, ni `curl`, ni gestionnaire de paquets pour la suite.
   ```
   admin@ctr01:~$ docker run -d --name m12-e10-doc -p 8010:8080 -e MEDIDOC_S3_ENDPOINT=https://s3.invalid -e MEDIDOC_S3_BUCKET=essai medidoc:1.0.0
   admin@adm01:~$ curl -s http://ctr01.par1.medisphere.internal:8010/healthz      # {"statut":"ok","version":"1.0.0"}
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' http://ctr01.par1.medisphere.internal:8010/readyz   # 503
   ```
   `/healthz` ne contacte pas S3 (vivacité) ; `/readyz` fait un `HeadBucket` qui échoue (pas d'identifiants, nom invalide) : 503, le service n'est pas **prêt**. Un orchestrateur ne lui enverrait pas de trafic mais ne le redémarrerait pas.

6. Sur `scratch`, il faut apporter soi-même les certificats racines (`COPY --from=construction /etc/ssl/certs/ca-certificates.crt …`) et, pour la lisibilité, `/etc/passwd` et `/etc/group` (sinon `USER 65532` fonctionne, mais aucun outil ne trouve de nom). Sans les certificats : `x509: certificate signed by unknown authority` au premier appel HTTPS vers S3, c'est-à-dire **à l'exécution**, pas à la construction. Gain : ≈ 0,7 Mo et une dizaine de couches. Décision MédiSphère : **distroless**, qui suit les mises à jour de sécurité de Debian (certificats, `tzdata`) sans que l'équipe y pense ; `scratch` se justifie pour un binaire qui ne parle ni TLS ni dates locales.

7. `docker stop` rend la main en moins d'une seconde : le binaire est le PID 1, reçoit SIGTERM, ferme son écouteur et sort (journal : `signal reçu, arrêt en cours`, puis `arrêt terminé`). Le journal montre aussi un avertissement du SDK AWS qui cherche des identifiants (IMDS) : attendu sans clés.

**Explications**

Le multi-étapes sépare **ce qu'il faut pour construire** (compilateur, sources, cache de modules) de **ce qu'il faut pour exécuter**. Seule la dernière étape devient l'image ; les autres ne sont que des intermédiaires du constructeur. Un binaire Go statique (`CGO_ENABLED=0`) n'a besoin de rien d'autre que du noyau : c'est le cas idéal. Moins de fichiers, c'est moins de vulnérabilités à suivre (le M13 les comptera), moins d'outils pour un attaquant, et des déploiements plus rapides.

**Alternatives**
- `cgr.dev/chainguard/static` (Chainguard) : équivalent de distroless, reconstruit chaque nuit ; registre externe de plus à maîtriser.
- `debian:trixie-slim` en étape finale : utile si l'on a besoin d'un shell pour diagnostiquer, au prix de ≈ 30 Mo et d'APT. On préfère diagnostiquer avec un conteneur éphémère qui partage les espaces de noms du conteneur malade (`docker run --rm -it --pid container:m12-e10-doc --network container:m12-e10-doc localhost/m12/diag:1.0`, image de E13).
- `ko` (construction d'images Go sans Dockerfile) : très bien pour Go seul ; on garde ici un Dockerfile, commun à toutes les applications.

**Pièges classiques**
- Oublier `CGO_ENABLED=0` : le binaire est dynamique, l'image se construit, le conteneur meurt aussitôt (`exec /usr/local/bin/medidoc: no such file or directory`) — c'est une des pannes du palier 4 (M12-E35).
- `COPY . .` dans l'étape de compilation sans `.dockerignore` : chaque modification d'un README ou d'un test invalide la couche de compilation, et `.git` entre dans le contexte.
- `USER nonroot` (nom) au lieu de `65532` : fonctionne ici (le nom existe dans l'image), mais Kubernetes ne peut pas vérifier `runAsNonRoot` sur un nom.
- Comparer `DISK USAGE` d'une image Docker 29 à la taille affichée par un registre : ce ne sont pas les mêmes octets.
- Penser qu'une image sans shell empêche le diagnostic : `docker cp` en sortie, `nsenter` depuis l'hôte, conteneur éphémère dans les mêmes espaces de noms.

**En production chez MédiSphère**

Base distroless épinglée par empreinte, mise à jour par Renovate (M13) ; image construite en CI (E21), jamais sur un poste ; analyse de vulnérabilités dans Harbor (M13) ; test de fumée du binaire dans le pipeline (`file` : *statically linked*, démarrage et `/healthz`).

---

### M12-E11 — BuildKit : cache, secrets de construction, montages

**Solution**

Fichiers : [`Dockerfile`](fichiers/M12-E11/mediagenda-api/Dockerfile) et [`.dockerignore`](fichiers/M12-E11/mediagenda-api/.dockerignore) de MédiAgenda 0.2.0, essai SSH [`Dockerfile.ssh`](fichiers/M12-E11/essais/Dockerfile.ssh).

1. Notes : un `COPY` crée une **couche** (le fichier est dans l'image pour toujours) ; un montage `bind` rend un fichier du contexte (ou d'une étape) visible **pendant** un `RUN` seulement, sans couche ; un montage `cache` est un dossier persistant **du constructeur**, réutilisé d'une construction à l'autre et jamais exporté dans l'image ; un montage `secret` est un fichier temporaire (`/run/secrets/<id>` par défaut, `tmpfs`) qui n'entre ni dans la couche ni dans la clé de cache.

2. Le Dockerfile en deux étapes :
   - étape `construction` : `python:3.13-slim-trixie@sha256:…`, `COPY --from=ghcr.io/astral-sh/uv:0.12.23@sha256:… /uv /usr/local/bin/uv`, `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy` (le cache est un montage : pas de liens physiques vers lui), `UV_PYTHON_DOWNLOADS=never`, `UV_PROJECT_ENVIRONMENT=/app/.venv` ;
   - `RUN --mount=type=cache,target=/root/.cache/uv --mount=type=bind,source=uv.lock,target=uv.lock --mount=type=bind,source=pyproject.toml,target=pyproject.toml --mount=type=secret,id=jeton_index,required=false UV_INDEX_MEDISPHERE_PASSWORD="$(cat /run/secrets/jeton_index 2>/dev/null || true)" uv sync --locked --no-dev --no-install-project` ;
   - puis `COPY` du projet et installation **non éditable** du projet (le code est copié dans le venv) ;
   - étape finale : même image de base (le venv pointe vers `/usr/local/bin/python3.13`), compte 10001, `COPY --from=construction /app/.venv`, `COPY migrations/`, `ENV PATH`, `MEDIAGENDA_MIGRATIONS_DIR`, `MEDIAGENDA_VERSION=${VERSION}`, `USER 10001:10001`, `CMD ["mediagenda"]`.
   Le secret est lu par `cat` et non par l'option `env=` de `--mount=type=secret` (BuildKit ≥ 0.14, Dockerfile 1.10) : Buildah 1.39 ne la reconnaît pas (constaté lors de la rédaction de E13-E14 ; à vérifier sur ta version si tu veux t'en servir). `required=false` est la valeur par défaut, écrite pour la lisibilité.

3. Construction et preuves :
   ```
   admin@ctr01:~$ install -d -m 700 ~/.config/medisphere && (umask 077; openssl rand -hex 16 > ~/.config/medisphere/jeton-index)
   admin@ctr01:~/src/mediagenda-api$ docker build --build-arg VERSION=0.2.0 --secret id=jeton_index,src=$HOME/.config/medisphere/jeton-index -t mediagenda-api:0.2.0 .
   admin@ctr01:~$ docker image history --no-trunc mediagenda-api:0.2.0 | grep -c -F -f ~/.config/medisphere/jeton-index     # 0
   admin@ctr01:~$ mkdir -p ~/m12/e11/couches && docker save mediagenda-api:0.2.0 | tar -x -C ~/m12/e11/couches
   admin@ctr01:~$ for b in ~/m12/e11/couches/blobs/sha256/*; do tar -xzOf "$b" 2>/dev/null; done | grep -ac -F -f ~/.config/medisphere/jeton-index   # 0
   admin@ctr01:~$ rm -rf ~/m12/e11/couches
   ```
   L'historique montre la commande `RUN … uv sync …` **avec** `$(cat /run/secrets/jeton_index …)` littéral, pas sa valeur. Le jeton n'est nulle part. (`grep -F -f` lit le motif dans le fichier : le jeton ne passe pas non plus dans la ligne de commande de `grep`, visible par `ps`.) Taille : 241 Mo sur disque, 56,5 Mo de contenu, contre 367 Mo pour 0.1.0 (ni uv, ni cache d'uv, ni outils de construction). Contrôle : `docker run --rm --entrypoint sh mediagenda-api:0.2.0 -c 'command -v uv'` ne renvoie rien.

4. Une ligne vide dans `pyproject.toml` change la clé de cache de l'étape des dépendances (le fichier est **monté** : son contenu fait partie de la clé) : l'étape repart, mais uv trouve tout dans le montage de cache et n'installe que des liens… copiés : quelques secondes au lieu d'une minute de téléchargement. Après `docker builder prune -af`, le cache **local** est vide ; avec `--cache-from type=local,src=…`, les étapes redeviennent `CACHED` (le cache importé contient les couches de résultat de chaque étape ; `mode=max` exporte aussi celles des étapes intermédiaires, sans lui seules les couches de l'image finale le sont, et l'étape `construction` serait refaite). `~/m12/e11/cache/` est une disposition OCI (`index.json`, `oci-layout`, `blobs/`). Le **montage de cache**, lui, n'est jamais exporté. Avec le registre : `--cache-to type=registry,ref=…:cache,mode=max` (E21, gabarit).

5. Reproductibilité de MédiDoc : deux constructions sans cache, `SOURCE_DATE_EPOCH` fixé, `rewrite-timestamp=true` : **même empreinte d'index** (vérifié : `sha256:af07…` deux fois). Sans `SOURCE_DATE_EPOCH`, les dates de création de la configuration et des fichiers des couches changent : les empreintes diffèrent. `--provenance=false` : l'attestation de provenance (si elle est produite) contient l'heure de la construction.

6. MédiAgenda : avec le Dockerfile écrit « naturellement » (`uv sync --no-editable` pour le projet), les deux empreintes **diffèrent**. Démarche :
   ```
   admin@ctr01:~/m12/e11$ for x in a b; do mkdir -p $x && tar -xf repro-$x.oci.tar -C $x; m=$(jq -r '.manifests[0].digest' $x/index.json | cut -d: -f2); jq -r '.layers[].digest' $x/blobs/sha256/$m > couches-$x.txt; done
   admin@ctr01:~/m12/e11$ diff couches-a.txt couches-b.txt          # une seule ligne : la couche du venv
   admin@ctr01:~/m12/e11$ # extraire cette couche des deux côtés, puis :
   admin@ctr01:~/m12/e11$ diff -rq --no-dereference ca cb
   Files ca/app/.venv/lib/python3.13/site-packages/mediagenda-1.0.0.dist-info/RECORD and cb/…/RECORD differ
   Files ca/app/.venv/lib/python3.13/site-packages/mediagenda-1.0.0.dist-info/uv_cache.json and cb/…/uv_cache.json differ
   ```
   `uv_cache.json` est un fichier interne d'uv (il lui sert à savoir si le projet local a changé) ; il contient les dates de changement d'état (*ctime*) de `pyproject.toml` et de `src/` : la date de la construction, que ni `SOURCE_DATE_EPOCH` ni `touch` ne fixent (constaté : `touch -d @…` ne change rien, `uv sync --no-cache` et l'installation d'une roue par `uv pip install --no-cache` l'écrivent aussi). `RECORD` liste chaque fichier installé avec son empreinte, donc celle de `uv_cache.json`. Correction retenue (dans le Dockerfile) : supprimer ce fichier et sa ligne de `RECORD` juste après l'installation du projet, dans la même instruction. Résultat vérifié : deux constructions sans cache, même empreinte (`sha256:18e3…`). Les `.pyc` sont produits en mode *checked-hash* parce que `SOURCE_DATE_EPOCH` est déclaré dans l'étape (`ARG SOURCE_DATE_EPOCH`) : Python l'exige pour la reproductibilité, et ils restent valides malgré la réécriture des dates des fichiers. Dans l'étape finale, `useradd` lit lui aussi `SOURCE_DATE_EPOCH` pour la date de `/etc/shadow` : sans l'`ARG`, l'empreinte changerait chaque jour.

7. L'essai SSH :
   ```
   admin@ctr01:~/m12/e11/ssh$ ssh-keygen -q -t ed25519 -N '' -C essai-m12 -f cle-essai
   admin@ctr01:~/m12/e11/ssh$ eval "$(ssh-agent -s)" && ssh-add cle-essai
   admin@ctr01:~/m12/e11/ssh$ docker build --ssh default --progress plain --no-cache -t m12-e11-ssh .
   #11 0.255 256 SHA256:… essai-m12 (ED25519)
   #12 0.333 aucun agent SSH hors du RUN qui le monte
   admin@ctr01:~/m12/e11/ssh$ docker build --progress plain --no-cache -t m12-e11-ssh .
   ERROR: failed to build: failed to solve: unset ssh forward key default
   admin@ctr01:~/m12/e11/ssh$ ssh-agent -k; docker rmi m12-e11-ssh; rm -f cle-essai cle-essai.pub
   ```
   Le refus de la seconde construction vient de `required=true` sur le montage `ssh` (vérifié avec Docker 29.8.2) : sans lui, le `RUN` tournerait sans agent et c'est `ssh-add -l` qui échouerait (« Could not open a connection to your authentication agent »).
   L'usage réel : cloner un dépôt privé par SSH pendant la construction (`git clone git@git01…` dans le `RUN`) sans jamais copier de clé dans l'image ; il faudrait alors le flux `ctr01` → `git01:22` et une clé de déploiement en lecture seule.

8. Avec l'image 0.2.0, la pile de M12-E08 démarre telle quelle (`MEDIAGENDA_TAG=0.2.0 docker compose up -d --wait`) : même `CMD`, même compte, mêmes chemins. `/sante` répond `"version": "0.2.0"`.

**Explications**

BuildKit construit un **graphe** d'opérations, chacune avec une clé de cache calculée sur ses entrées (instruction, fichiers copiés ou montés, arguments, image parente). Les montages (`cache`, `bind`, `secret`, `ssh`) sont des entrées **temporaires** : ils servent pendant l'opération sans devenir des couches. Le cache de résultat (les couches) s'exporte (`--cache-to`) ; le contenu d'un montage de cache, jamais. Une construction est **reproductible** si les mêmes entrées donnent le même résultat octet pour octet : il faut alors fixer tout ce qui dépend du moment (dates, aléas, réseau). `SOURCE_DATE_EPOCH` règle les dates connues de BuildKit et des outils qui respectent la convention (Python, shadow-utils, Debian) ; ce qui reste se trouve par comparaison des couches, comme ici. L'intérêt : prouver qu'une image publiée vient bien d'un commit donné, en la reconstruisant (Sophie, HDS) ; l'empreinte devient une signature du contenu.

**Alternatives**
- Jeton d'index : `uv` sait aussi lire `~/.netrc` (montage secret `target=/root/.netrc`) ; ou un fichier `uv.toml` de configuration monté en secret.
- Cache des dépendances Python : exporter le cache par le registre (`type=registry`) plutôt que monter un cache local, indispensable en CI où chaque job démarre vide (E21).
- Reproductibilité de MédiAgenda : installer le projet depuis une roue avec `pip` (qui n'écrit pas `uv_cache.json`) ; ou ne pas installer le projet du tout (`PYTHONPATH=/app/src`), au prix de fichiers sources dans l'image.

**Pièges classiques**
- `ARG JETON` + `--build-arg JETON=…` : la valeur est dans l'historique de l'image (`docker image history --no-trunc`) et dans les métadonnées de provenance. Hadolint (DL3064) le signale pour les noms qui ressemblent à des secrets, pas pour les autres.
- Un `ENV` fabriqué à partir du secret : il reste dans la configuration de l'image.
- `--mount=type=cache` sans `UV_LINK_MODE=copy` : uv tente des liens physiques vers le cache, qui n'est plus là dans l'image (avertissement, puis copie).
- Comparer deux constructions **avec** cache et conclure à la reproductibilité : la seconde réutilise les couches de la première, elle n'a rien reconstruit.
- Transférer son agent SSH personnel vers un hôte partagé pour « tester ».

**En production chez MédiSphère**

Le gabarit de CI (E21) fixe `SOURCE_DATE_EPOCH` à la date du commit et réécrit les horodatages ; deux pipelines sur le même commit publient la même empreinte. Les jetons d'index privé sont des variables protégées et masquées passées en secret de construction (`--secret id=…,env=…` côté client). Au M13, la provenance est attestée et signée.

---

### M12-E12 — Images multi-architectures avec Buildx

**Solution**

Fichiers : [`Dockerfile`](fichiers/M12-E12/medidoc/Dockerfile) de MédiDoc (compilation croisée) ; extension du rôle `docker_engine` : [`tasks/emulation.yml`](fichiers/M12-E12/ansible/roles/docker_engine/tasks/emulation.yml), [`defaults` (extrait)](fichiers/M12-E12/ansible/roles/docker_engine/defaults/main-extrait-M12-E12.yml), [`host_vars/ctr01/docker_engine.yml`](fichiers/M12-E12/ansible/inventories/lab/host_vars/ctr01/docker_engine.yml).

1. Trois stratégies (documentation « Multi-platform builds ») : **émulation** QEMU (le constructeur exécute les `RUN` d'une autre architecture sous QEMU : il faut binfmt_misc), **plusieurs nœuds natifs** (un constructeur Buildx à nœuds `amd64` et `arm64`), **compilation croisée** (l'étape de compilation tourne sur la plateforme de construction et produit le code de la cible : il faut un langage qui sait le faire et un Dockerfile écrit pour).

2. Le fichier `emulation.yml` installe `qemu-user-binfmt` (Debian 13 ; il tire `qemu-user`, binaires statiques ; `qemu-user-static` n'est plus qu'un paquet de transition), relance `systemd-binfmt` si le paquet vient d'être installé, puis **vérifie** `/proc/sys/fs/binfmt_misc/qemu-aarch64` : `enabled`, interpréteur `/usr/libexec/qemu-binfmt/aarch64-binfmt-P`, drapeaux `POF` (vérifié dans le paquet : `:qemu-aarch64:M::…:/usr/libexec/qemu-binfmt/aarch64-binfmt-P:OPF`). `P` (*preserve argv[0]*), `O` (*open binary* : l'interpréteur reçoit un descripteur du programme), `F` (*fix binary* : l'interpréteur est ouvert à l'enregistrement, utilisable depuis n'importe quel espace de noms de montage, donc dans les conteneurs). `docker run --platform linux/arm64 … uname -m` affiche `aarch64`.

3. Constructeur :
   ```
   admin@ctr01:~$ docker buildx create --name multiarch --driver docker-container \
       --driver-opt image=docker.io/moby/buildkit:v0.34.0@sha256:b059f8d7226d0b326bc871af489a5dddf65e36af4d20d14251b072974d9ee87c
   admin@ctr01:~$ docker buildx inspect --bootstrap multiarch     # Platforms: linux/amd64, …, linux/arm64, …
   admin@ctr01:~$ docker inspect -f '{{.HostConfig.Privileged}}' buildx_buildkit_multiarch0      # true
   ```
   Le pilote `docker-container` lance BuildKit dans un conteneur **privilégié** (le démon BuildKit y tourne en root). Acceptable sur `ctr01`, hôte de travail où `admin` est déjà root ; **pas** sur un runner partagé (E21).

4. MédiDoc : `FROM --platform=$BUILDPLATFORM golang:…` pour l'étape de compilation, `ARG TARGETOS TARGETARCH`, `GOOS=${TARGETOS} GOARCH=${TARGETARCH}` ; l'étape finale (distroless, index multi-plateformes) sans `--platform` : elle est celle de la cible. Les modules sont dans un montage de cache, le code monté (`--mount=type=bind,target=.`). Durée sur l'environnement de rédaction : ≈ 70 s pour les deux plateformes, autant que pour une seule : rien n'est émulé (aucun `RUN` dans l'étape finale).

5. MédiAgenda par émulation : les `RUN` de l'étape `construction` (`uv sync`, compilation des `.pyc`) et `useradd` de l'étape finale s'exécutent sous QEMU pour `arm64` : comptez 5 à 15 fois plus long que pour `amd64` (selon le processeur ; mesure à relever). C'est acceptable pour une application Python sans extension compilée par nous ; ce serait rédhibitoire pour un projet qui compile du C++ dans le Dockerfile.

6. Lecture de l'index :
   ```
   admin@ctr01:~/m12/e12$ mkdir x && tar -xf medidoc-1.0.0.oci.tar -C x && jq . x/index.json
   admin@ctr01:~/m12/e12$ jq '.manifests[] | {platform, annotations}' x/blobs/sha256/$(jq -r '.manifests[0].digest' x/index.json | cut -d: -f2)
   ```
   `index.json` de l'archive désigne **un** index (`application/vnd.oci.image.index.v1+json`, annotation `org.opencontainers.image.ref.name: 1.0.0`) ; cet index a quatre entrées : `linux/amd64`, `linux/arm64` et deux `unknown/unknown` portant `vnd.docker.reference.type: attestation-manifest` (attestations de provenance de BuildKit, une par plateforme, rattachées par `vnd.docker.reference.digest`). Le binaire `arm64` : `file` répond `ELF 64-bit LSB executable, ARM aarch64, … statically linked, stripped`.

7. Avec Docker 29 et le stockage containerd, le pilote `docker` sait lui aussi produire un index multi-plateformes (vérifié) : avant Docker 25/29, il fallait un constructeur `docker-container`. Ce dernier reste utile pour : une version de BuildKit différente de celle du démon (ici 0.34 contre 0.33 intégré), une configuration propre (`buildkitd.toml` : miroirs, autorités de certification d'un registre), des nœuds multiples, les exportations de cache vers un registre sur d'anciens moteurs.

**Explications**

Une image multi-architectures n'est pas « une image » : c'est un **index** (M12-E04) qui désigne un manifeste par plateforme ; le client (Docker, Podman, containerd, kubelet) choisit l'entrée de sa plateforme. Construire pour `arm64` sur `amd64` demande soit d'émuler le processeur cible pour chaque `RUN` (lent mais universel), soit de ne rien exécuter de la cible (compilation croisée : rapide, mais il faut un langage et un Dockerfile qui s'y prêtent). Go s'y prête parfaitement ; Python, non (les roues binaires des dépendances doivent être celles de la cible, installées par l'interpréteur de la cible).

**Alternatives**
- Enregistrer l'émulation par `docker run --privileged --rm tonistiigi/binfmt --install arm64` : rapide, mais conteneur privilégié, enregistrement perdu au redémarrage et absent du code de l'hôte.
- Nœud natif `arm64` (`docker buildx create --append --name multiarch ssh://admin@<hôte-arm64>`) : la bonne solution le jour où `arm64` est une cible de production.
- Pour Python : `uv` peut installer les roues d'une autre plateforme (`--python-platform`) dans une étape native, puis copier le venv dans l'image cible ; plus rapide, mais fragile (tout paquet sans roue pour la cible casse).

**Pièges classiques**
- `ARG TARGETARCH` absent de l'étape : la variable est vide, Go compile pour l'hôte, l'image `arm64` contient un binaire `amd64` (`exec format error` sur un Mac M).
- `FROM --platform=$BUILDPLATFORM` sur l'étape **finale** : l'image `arm64` est faite d'une base `amd64`.
- `--load` d'un index multi-plateformes avec un ancien stockage : refusé ; avec le stockage containerd, accepté (toutes les plateformes sont gardées).
- Émulation non enregistrée avec `F` : `exec /bin/sh: exec format error` dans les `RUN` arm64 d'un constructeur en conteneur.

**En production chez MédiSphère**

L'émulation est activée sur `ctr01` et `runner02` (E20) par le rôle ; MédiAgenda et MédiDoc sont publiées en `amd64` et `arm64` par la CI (E21), les autres en `amd64` jusqu'à ce qu'un besoin `arm64` soit exprimé. Un nœud `arm64` natif est à prévoir si les serveurs Ampere du prestataire deviennent une cible.

---

### M12-E13 — Buildah et Skopeo : construire sans démon, copier entre registres

**Solution**

Fichiers : [`construire-diag.sh`](fichiers/M12-E13/ctr02/outils-diag/construire-diag.sh), [`miroir.yaml`](fichiers/M12-E13/ctr02/skopeo/miroir.yaml).

1. Transports utilisés : `containers-storage:` (stockage local de Podman/Buildah, celui de `app`), `oci-archive:` (archive tar au format OCI, celles de E12), `oci:` (dossier OCI), `dir:` (dossier « à plat » : un fichier par blob + `manifest.json`), `docker://` (un registre). `skopeo sync` accepte en source `docker`, `dir` ou `yaml` (une liste de registres, dépôts et étiquettes), en destination `docker` ou `dir`.

2. `buildah build --layers` lit le Dockerfile de E11 sans modification : `RUN --mount=type=cache`, `bind` et `secret` sont pris en charge par Buildah 1.39 (le cache vit sous `~/.local/share/containers/…` de `app`, et sert d'une construction à l'autre). L'image va dans le stockage de `app` (`~/.local/share/containers/storage`) : `podman images` et `buildah images` montrent la même image, ce sont les mêmes bibliothèques (`containers/storage`). Sans `--layers`, Buildah ne garde pas les couches intermédiaires (pas de cache de couches) : c'est son défaut historique, contrairement à `podman build`. Le secret facultatif : créer pour `app` un jeton fictif `~/.config/medisphere/jeton-index` (600), comme en E11.

3. Le script : `buildah from --pull=missing debian:trixie-slim@sha256:…` donne un conteneur de travail ; `trap 'buildah rm …' EXIT` ; un seul `buildah run … sh -c 'apt-get update && apt-get install -y --no-install-recommends … && rm -rf /var/lib/apt/lists/*'` ; `buildah run … useradd --system --uid 10050 …` ; `buildah config --user 10050:10050 --cmd '["/bin/bash"]' --label …` ; `buildah commit "$ctr" localhost/m12/diag:1.0`. Chaque `buildah run` ne crée pas de couche : c'est le `commit` qui fige l'état (une seule couche ajoutée, quoi qu'il y ait eu de `run`). Essai : `podman run --rm localhost/m12/diag:1.0 dig +short git01.par1.medisphere.internal` → 10.10.20.12.

4. `buildah mount <conteneur>` sous un compte sans privilège répond `cannot mount using driver overlay in rootless mode. You need to run it in a buildah unshare session`. Il faut d'abord entrer dans l'espace de noms `user` de `app` (où `app` est root et peut monter) : `buildah unshare`, puis `buildah mount` dans ce shell ; le chemin affiché n'est visible que dans cet espace de noms.

5. Connexion persistante, sans mot de passe en argument ni en fichier temporaire :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-vault view inventories/lab/host_vars/ctr01/vault.yml \
       | sed -n 's/^vault_registre_travail_mdp_plateforme: "\(.*\)"$/\1/p' \
       | ssh ctr02.par1.medisphere.internal 'cd /tmp && sudo -u app XDG_RUNTIME_DIR=/run/user/1001 podman login --authfile /home/app/.config/containers/auth.json --username plateforme --password-stdin ctr01.par1.medisphere.internal:5000'
   app@ctr02:~$ chmod 600 ~/.config/containers/auth.json
   ```
   Podman lit aussi `~/.config/containers/auth.json` par défaut quand le fichier sous `$XDG_RUNTIME_DIR` n'existe pas (`containers-auth.json(5)` : à vérifier sur ta version ; sinon passe `--authfile` ou `REGISTRY_AUTH_FILE`). Le fichier contient `utilisateur:mot de passe` en base64 : c'est un secret, inscrit au registre des secrets.

6. Copies :
   ```
   app@ctr02:~$ skopeo copy containers-storage:localhost/mediagenda-api:0.2.0 oci-archive:$HOME/m12/e13/mediagenda-api-0.2.0.oci.tar
   app@ctr02:~$ skopeo copy --all --authfile ~/.config/containers/auth.json oci-archive:$HOME/m12/e13/medidoc-1.0.0.oci.tar docker://ctr01.par1.medisphere.internal:5000/medidoc/medidoc:1.0.0-essai
   app@ctr02:~$ skopeo inspect --raw --authfile ~/.config/containers/auth.json docker://ctr01.par1.medisphere.internal:5000/medidoc/medidoc:1.0.0-essai | jq '.manifests[].platform'
   app@ctr02:~$ skopeo copy --all --authfile ~/.config/containers/auth.json docker://ctr01.par1.medisphere.internal:5000/medidoc/medidoc:1.0.0-essai dir:$HOME/m12/e13/medidoc-dir
   app@ctr02:~$ skopeo delete --authfile ~/.config/containers/auth.json docker://ctr01.par1.medisphere.internal:5000/medidoc/medidoc:1.0.0-essai
   ```
   Le dossier `dir:` contient l'index, un fichier par manifeste et par blob (nommés par leur empreinte sans préfixe), `version`. `skopeo delete` supprime le **manifeste** désigné par l'étiquette (il le résout en empreinte et appelle `DELETE /v2/…/manifests/<empreinte>`) : comme `1.0.0` (poussée en E15) désigne **le même index**, elle disparaît aussi ! Le registre ne supprime pas une étiquette, il supprime un contenu, et toutes les étiquettes qui y menaient. Repousse `medidoc/medidoc:1.0.0` depuis l'archive de E12 (et retiens le piège : on supprime une étiquette d'essai d'un contenu partagé par un autre moyen, ou pas du tout).

7. Le miroir : `skopeo sync --all --src yaml --dest docker --authfile ~/.config/containers/auth.json miroir.yaml ctr01.par1.medisphere.internal:5000/miroir`. Noms d'arrivée (vérifié avec Skopeo 1.18, `--dry-run`) : sans `--scoped`, `skopeo sync` ne garde que le **dernier** élément du nom source (`path.Base`) : `miroir/debian:trixie-slim`, `miroir/python:3.13-slim-trixie`, `miroir/postgres:18-trixie` et `miroir/valkey:8-trixie` (et non `miroir/valkey/valkey`). Deux sources de même nom final (`docker.io/library/nginx` et `quay.io/x/nginx`) se marcheraient dessus : c'est le rôle de `--scoped`, qui garde le chemin complet (`miroir/docker.io/library/debian:trixie-slim`). Avec `--all` et sans conversion, les empreintes d'index sont **identiques** à celles de Docker Hub : une construction qui épingle `debian:trixie-slim@sha256:a292…` peut tirer la même image depuis le miroir.

8. Dossier `conteneurs/` de `plateforme/outils` : le script, `miroir.yaml` et un court `LISEZMOI.md` (usage, compte utilisé, ce que fait `--all`).

**Explications**

Buildah et Podman partagent le même stockage et la même bibliothèque d'images ; Buildah n'est qu'une autre interface, plus fine (on peut construire une image sans Dockerfile, monter son système de fichiers, la modifier avec les outils de l'hôte). Aucun démon : chaque commande fait son travail et s'arrête, sous l'identité de qui la lance. Skopeo travaille au niveau du **format** : il lit et écrit des manifestes et des blobs d'un transport à l'autre sans jamais « déballer » l'image, d'où sa rapidité et l'absence de démon et de privilège.

**Alternatives**
- `podman build` à la place de `buildah build` : même moteur ; `podman build` garde les couches par défaut.
- `crane copy` / `regctl image copy` (PLAN §6, facultatifs) : équivalents de `skopeo copy`, en un binaire statique.
- Miroir par proxy : Harbor (M13) fait des caches de Docker Hub à la demande, au lieu d'une copie planifiée.

**Pièges classiques**
- Oublier `--all` : seule la plateforme de l'hôte est copiée, l'index devient un manifeste simple, l'empreinte change, et les machines `arm64` ne trouvent plus rien.
- `podman login` sans `--authfile` : identifiants dans `/run/user/1001/containers/auth.json`, perdus au premier redémarrage (la mise à jour automatique du M12-E30 échoue alors en silence).
- `skopeo delete` d'une étiquette d'essai qui partage son contenu avec une étiquette de version.
- `buildah commit` en oubliant `--format oci` ou `docker` selon le registre visé (Buildah produit de l'OCI par défaut ; certains vieux outils attendent `v2s2`).

**En production chez MédiSphère**

Les constructions sur les serveurs Podman sont l'exception (essais) ; la règle est la CI. Le miroir des images de base est remplacé au M13 par les caches de Harbor et la bibliothèque `bibliotheque/*` (M12-E27). `skopeo` reste l'outil de migration des images (M13-E03) et de promotion d'une étiquette (M12-E30).

---

### M12-E14 — Pods Podman et Quadlet : des conteneurs gérés par systemd

**Solution**

Fichiers (à déposer dans `~app/.config/containers/systemd/` sur `ctr02`) : [`mediagenda.network`](fichiers/M12-E14/quadlet/mediagenda.network), [`mediagenda-pg.volume`](fichiers/M12-E14/quadlet/mediagenda-pg.volume), [`mediagenda-pg.container`](fichiers/M12-E14/quadlet/mediagenda-pg.container), [`mediagenda.pod`](fichiers/M12-E14/quadlet/mediagenda.pod), [`mediagenda-valkey.container`](fichiers/M12-E14/quadlet/mediagenda-valkey.container), [`mediagenda-migrations.container`](fichiers/M12-E14/quadlet/mediagenda-migrations.container), [`mediagenda-api.build`](fichiers/M12-E14/quadlet/mediagenda-api.build), [`mediagenda-api.container`](fichiers/M12-E14/quadlet/mediagenda-api.container) ; script [`creer-secrets.sh`](fichiers/M12-E14/ctr02/creer-secrets.sh) ; exemple de [`mediagenda-pod.yaml`](fichiers/M12-E14/ctr02/mediagenda-pod.yaml.exemple) ; unité d'essai de `ctr03` [`m12-e14-essai.container`](fichiers/M12-E14/ctr03/m12-e14-essai.container).

1. Clés disponibles en Podman 5.4.2 (vérifiées par `quadlet -dryrun`) : `.build` existe (`ImageTag=`, `File=`, `SetWorkingDirectory=`, `Label=`, `Secret=`, `PodmanArgs=`…) mais **pas** `BuildArg=` (« unsupported key ») ; `.container` n'a pas `Memory=` (E18) ; `Pod=`, `Notify=healthy`, `HealthOnFailure=`, `PidsLimit=`, `Secret=…,type=env` existent. La page en ligne décrit la dernière version : toujours `man podman-systemd.unit` de l'hôte.

2. À la main (session `app`) : `./creer-secrets.sh` (le mot de passe est tiré par `openssl rand -hex 24` dans une variable du script et envoyé sur l'entrée standard de `podman secret create … -`, jamais affiché ni écrit), puis :
   ```
   app@ctr02:~$ podman network create mediagenda
   app@ctr02:~$ podman volume create mediagenda-pg
   app@ctr02:~$ podman run -d --name mediagenda-pg --network mediagenda -v mediagenda-pg:/var/lib/postgresql \
       -e POSTGRES_DB=mediagenda -e POSTGRES_USER=mediagenda --secret mediagenda-pg-mdp,type=env,target=POSTGRES_PASSWORD \
       --health-cmd '["pg_isready", "-U", "mediagenda", "-d", "mediagenda"]' docker.io/library/postgres:18-trixie
   app@ctr02:~$ podman pod create --name mediagenda --network mediagenda -p 8000:8000
   app@ctr02:~$ podman run -d --name mediagenda-valkey --pod mediagenda docker.io/valkey/valkey:8-trixie valkey-server --bind 127.0.0.1 --appendonly no
   app@ctr02:~$ podman run --rm --network mediagenda --secret mediagenda-db-url,type=env,target=MEDIAGENDA_DB_URL localhost/mediagenda-api:0.2.0 mediagenda-migrate
   app@ctr02:~$ podman run -d --name mediagenda-api --pod mediagenda --secret mediagenda-db-url,type=env,target=MEDIAGENDA_DB_URL \
       -e MEDIAGENDA_VALKEY_URL=redis://127.0.0.1:6379/0 localhost/mediagenda-api:0.2.0
   admin@adm01:~$ curl -s http://ctr02.par1.medisphere.internal:8000/pret     # {"statut":"pret","postgresql":"ok","valkey":"ok"}
   ```
   `podman pod ps` montre le pod avec **trois** conteneurs : l'API, Valkey et le conteneur *infra* (`pause`) qui porte les espaces de noms partagés. `podman inspect mediagenda-api` : le secret n'apparaît pas dans `Config.Env` (vérifié), seulement sa référence (`Config.Secrets`/`HostConfig`) : la valeur est injectée au démarrage. Le pod est sur le réseau `mediagenda` : l'API résout `mediagenda-pg` (aardvark-dns) et joint Valkey sur `127.0.0.1` (même espace réseau).

3. `podman kube generate mediagenda > ~/m12/e14/mediagenda-pod.yaml` produit un `Pod` (version `v1`) avec les deux conteneurs, leurs images, leurs variables **non secrètes** et le `hostPort` 8000. Il manque : les secrets (ni valeur, ni référence), la base (hors du pod), le réseau Podman, les sondes, les volumes de la base ; l'image de l'API est `localhost/…`, introuvable ailleurs. C'est une ébauche pour discuter avec l'équipe du M14, pas un manifeste déployable. `podman kube play --replace` recrée le pod depuis le fichier ; `podman kube down` le supprime. Ménage : `podman pod rm -f mediagenda`, `podman rm -f mediagenda-pg`, `podman network rm mediagenda` ; le volume et les secrets restent.

4. Les fichiers : voir les liens. Points d'écriture :
   - `mediagenda-pg.container` : `Network=mediagenda.network`, `Volume=mediagenda-pg.volume:/var/lib/postgresql`, `Secret=mediagenda-pg-mdp,type=env,target=POSTGRES_PASSWORD`, sonde `pg_isready`, **`Notify=healthy`** (le service n'est démarré que lorsque la base répond), `TimeoutStartSec=120` ;
   - `mediagenda.pod` : `Network=mediagenda.network`, `PublishPort=8000:8000` ; `mediagenda-valkey.container` et `mediagenda-api.container` : `Pod=mediagenda.pod` ;
   - `mediagenda-migrations.container` : `Exec=mediagenda-migrate`, `[Service] Type=oneshot` et `RemainAfterExit=yes`, `Requires=`/`After=mediagenda-pg.service` ;
   - `mediagenda-api.container` : `Image=mediagenda-api.build` (dépendance automatique sur `mediagenda-api-build.service`), `Requires=`/`After=` migrations et Valkey, sonde **en tableau JSON**, `Notify=healthy`, `StopTimeout=30`, `Restart=on-failure` ;
   - `[Install] WantedBy=default.target` sur la base, le pod, Valkey et l'API.

5. `-dryrun` montre deux pièges de la 5.4, vérifiés à la rédaction :
   - `HealthCmd=python -c "import urllib.request; …timeout=2)"` en chaîne devient `--health-cmd "python -c \"import …timeout=2)"` : le guillemet final est perdu, la sonde échoue toujours (*SyntaxError* dans le conteneur). En tableau JSON, `HealthCmd=["python", "-c", "…"]` est transmis intact et Podman l'exécute en forme exec (`["CMD", "python", …]` dans `podman inspect`) ;
   - `Exec=valkey-server --save "" --appendonly no` devient `valkey-server --save` : l'argument vide **et tout ce qui le suit** disparaissent. On renonce à `--save ""` (l'instantané RDB par défaut reste dans la couche du conteneur, jetée à chaque redémarrage puisque Quadlet lance avec `--rm`).
   Le fichier `.build` : `podman build --tag localhost/mediagenda-api:0.2.0 --label app=mediagenda --file Dockerfile --build-arg VERSION=0.2.0 /home/app/src/mediagenda-api`.

6. `systemctl --user start mediagenda-api.service` tire, par les dépendances : `mediagenda-network.service`, `mediagenda-pg-volume.service`, `mediagenda-pg.service` (attend `healthy`), `mediagenda-api-build.service` (construction, plusieurs minutes la première fois : d'où `TimeoutStartSec=300` sur l'API), `mediagenda-migrations.service`, `mediagenda-pod.service`, `mediagenda-valkey.service`, puis l'API. `systemctl --user enable` est refusé (`Unit … is transient or generated`) : une unité générée ne s'active pas, c'est le `[Install]` du fichier Quadlet que le générateur traduit en lien `default.target.wants/`.

7. Après `sudo systemctl reboot` : le linger (M12-E02) démarre `user@1001.service` sans connexion, qui démarre `default.target` et donc la pile ; `/pret` répond en une à deux minutes. `systemctl --user stop mediagenda-api.service` n'arrête que l'API : Valkey (autre unité, même pod) et la base restent ; arrêter `mediagenda-pod.service` arrête tout le pod.

8. Sur `ctr03` : `podman quadlet install ~/m12/e14/m12-e14-essai.container` copie le fichier dans `~/.config/containers/systemd/`, **et** relance le générateur (`daemon-reload`) ; `podman quadlet list` montre l'unité, son état et son chemin ; `podman quadlet rm` désinstalle (et arrête). Sur `ctr02` (5.4), la commande n'existe pas : le rôle Ansible (mini-projet, rôle `pile_recette`) dépose les fichiers avec `template` et relance `systemctl --user daemon-reload` lui-même, ce qui marche sur les deux versions. Note dans `hotes.md` : « Podman 5.4 (Debian 13) : pas de `podman quadlet` ; ne pas l'utiliser dans les rôles ».

9. MR dans `mediagenda/api` : `deploiement/quadlet/*.{network,volume,container,pod,build}` et `deploiement/quadlet/creer-secrets.sh`.

**Explications**

Un **pod** est un groupe de conteneurs qui partagent des espaces de noms (réseau, IPC, UTS), tenus ouverts par un petit conteneur *infra* : l'équivalent exact du pod Kubernetes. **Quadlet** est un générateur systemd (`/usr/lib/systemd/user-generators/podman-user-generator`) : à chaque `daemon-reload`, il lit les fichiers de `~/.config/containers/systemd/` et produit des unités `.service` dans `/run/user/1001/systemd/generator/`. systemd gère alors l'ordre, les dépendances, le redémarrage et les journaux ; Podman (et `conmon`) fait tourner le conteneur. `Notify=healthy` fait attendre à systemd la première sonde réussie (`--sdnotify=healthy`) : les `After=` signifient alors « après que le service **réponde** ».

**Alternatives**
- `podman generate systemd` : déprécié depuis Podman 4.7 au profit de Quadlet.
- Un fichier `.kube` (`Yaml=mediagenda-pod.yaml`) : Quadlet joue le YAML ; on perd la finesse des dépendances et des secrets Podman.
- Compose sous Podman (`podman compose`, qui délègue à `docker-compose` ou `podman-compose`) : pratique sur un poste, sans l'intégration systemd.
- Image tirée du registre (`Image=ctr01…:5000/mediagenda/api:…`) au lieu d'une construction locale : c'est la cible (M12-E30), qui évite d'avoir les sources et un constructeur sur un serveur.

**Pièges classiques**
- Oublier le linger : la pile ne démarre qu'à la première connexion de `app` et s'arrête à sa déconnexion (panne de M12-E40).
- `sudo -u app systemctl --user …` sans `XDG_RUNTIME_DIR` ni bus : « Failed to connect to bus ».
- Mettre la base **dans** le pod : redémarrer le pod (une mise à jour de l'API) redémarre la base.
- Nom d'image court (`postgres:18`) : refusé par `short-name-mode = "enforcing"` dans un service (pas de terminal pour choisir).
- `Requires=` sans `After=` : systemd démarre les deux en même temps.
- Croire la documentation en ligne pour une 5.4 : `BuildArg=`, `Memory=` n'y sont pas.

**En production chez MédiSphère**

ADR-0120 (M12-E31) retient Podman sans privilège + Quadlet pour les serveurs applicatifs hors Kubernetes. Les fichiers sont déposés par Ansible (M12-E46), l'image vient du registre et se met à jour par `AutoUpdate=registry` (M12-E30), la supervision lit l'état des unités (M12-E28).

---

### M12-E15 — Un registre de travail

**Solution**

Fichiers : rôle [`registre_travail`](fichiers/M12-E15/ansible/roles/registre_travail/) (`defaults`, `tasks`, `handlers`, `templates/compose.yaml.j2`, `config.yml.j2`, `registre-gc.service.j2`, `registre-gc.timer.j2`), [`host_vars/ctr01/`](fichiers/M12-E15/ansible/inventories/lab/host_vars/ctr01/) (`registre_travail.yml`, `certificats.yml`, `vault.yml.exemple`), [`playbooks/registre-travail.yml`](fichiers/M12-E15/ansible/playbooks/registre-travail.yml), [extrait de la matrice des flux](fichiers/M12-E15/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [réservation Kea](fichiers/M12-E15/kea/reservation-ctr01.extrait.json), modèles des fichiers de `adm01` ([`registre-travail.env`](fichiers/M12-E15/adm01/registre-travail.env.exemple), [`registre-ci.curl`](fichiers/M12-E15/adm01/registre-ci.curl.exemple)), fiche [`registre-travail.md`](fichiers/M12-E15/medisphere/docs/conteneurs/registre-travail.md).

1. Le ramasse-miettes parcourt les manifestes pour marquer les blobs référencés, puis supprime les autres : une poussée en cours (blobs envoyés, manifeste pas encore écrit) verrait ses blobs supprimés. `--delete-untagged` supprime aussi les manifestes qu'aucune étiquette ne désigne (anciennes versions d'une étiquette déplacée, comme `main-…` réécrites, ou `cache`).

2. Réservation dans la variable de réservations du sous-réseau 99 du rôle Kea (M11), `hw-address` `bc:24:11:99:12:01`. Sur `ctr01` : `sudo networkctl renew <CARTE>` (nom de la carte donné par `ip -br link`, selon l'image dorée ; ou un redémarrage), puis `ip -4 addr` ; le DDNS met à jour A et PTR (`dig +short ctr01.par1.medisphere.internal` → 10.10.99.121).

3. Matrice : définition `CTR01 = 10.10.99.121` ; transit `ctr01` → `ca01:443` et `ca01` → `ctr01:80`. La règle `ca01` → `V_SANDBOX:80` de la maquette du M07 (si elle existe encore) ne suffit pas : elle devait être retirée avec la maquette, et elle ouvrait tout le VLAN.

4. Le rôle : voir les fichiers. Points clés :
   - **htpasswd idempotent** : `htpasswd -v -i <fichier> <compte>` (mot de passe sur l'entrée standard, `stdin:` du module `command`, `no_log`) ; code 0 : rien à faire ; sinon `htpasswd -i -B -C 12 <fichier> <compte>`. Une empreinte bcrypt change à chaque calcul (sel aléatoire) : sans vérification, chaque passage réécrirait le fichier et redémarrerait le registre ;
   - conteneur `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges:true` ; le processus tourne en root **dans** le conteneur, mais sans aucune capacité : il lit les fichiers dont root est propriétaire et écrit dans le volume (propriétaire root), rien d'autre. Sonde : `wget … https://127.0.0.1:5000/v2/` qui attend la réponse 401 ;
   - `config.yml` : `http.host: https://ctr01.par1.medisphere.internal:5000`, `http.tls`, `auth.htpasswd`, `storage.delete.enabled: true`, journaux JSON ;
   - ramasse-miettes : `registre-gc.service` (`ExecStartPre=` arrêt, `ExecStart=` service `ramasse-miettes` du profil `maintenance`, `ExecStopPost=` relance **toujours**) et `registre-gc.timer` ;
   - certificat : rôle `certificats_acme`, identifiant `registre`, `recharger:` redémarre le registre (Distribution ne relit pas son certificat à chaud).
   Second passage : `changed=0` (vérifié pour la partie htpasswd ; l'application sur `ctr01` reste à confirmer).

5. `curl` sans identifiants : 401 ; avec `-K ~/.config/workbook/registre-ci.curl` : 200 ; `openssl` : `issuer=… MédiSphère Intermediate CA`, fin de validité ≤ 30 jours.

6. Poussées (le mot de passe part du fichier 600 de `adm01` et arrive sur l'**entrée standard** de la commande distante : ni argument, ni fichier en clair) :
   ```
   admin@adm01:~$ ( . ~/.config/workbook/registre-travail.env; printf '%s' "$REGISTRE_MOT_DE_PASSE" ) \
       | ssh ctr01.par1.medisphere.internal 'docker login ctr01.par1.medisphere.internal:5000 -u plateforme --password-stdin'
   admin@ctr01:~$ docker tag mediagenda-api:0.1.0 ctr01.par1.medisphere.internal:5000/mediagenda/api:0.1.0
   admin@ctr01:~$ docker push ctr01.par1.medisphere.internal:5000/mediagenda/api:0.1.0
   admin@ctr01:~$ docker logout ctr01.par1.medisphere.internal:5000
   admin@adm01:~$ scp -3 ctr01.par1.medisphere.internal:m12/e12/'*.oci.tar' ctr02.par1.medisphere.internal:m12/e15/
   admin@adm01:~$ ( . ~/.config/workbook/registre-travail.env; printf '%s' "$REGISTRE_MOT_DE_PASSE" ) \
       | ssh ctr02.par1.medisphere.internal 'set -e; af=$(mktemp); trap "shred -u $af" EXIT
           R=ctr01.par1.medisphere.internal:5000
           skopeo login --authfile "$af" -u plateforme --password-stdin $R
           skopeo copy --all --authfile "$af" oci-archive:m12/e15/medidoc-1.0.0.oci.tar docker://$R/medidoc/medidoc:1.0.0
           skopeo copy --all --authfile "$af" oci-archive:m12/e15/mediagenda-api-0.2.0.oci.tar docker://$R/mediagenda/api:0.2.0'
   ```
   `docker login` range les identifiants dans `~/.docker/config.json`, en **base64** (pas chiffré) : `utilisateur:mot de passe` lisible par quiconque lit le fichier. En production : un *credential helper* (`docker-credential-pass`, `secretservice`) ou des identifiants à courte durée (robots Harbor, M13). Le fichier temporaire de Skopeo est détruit en fin de session, quoi qu'il arrive (`trap`).

7. API :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/registre-travail.env; set +a
   admin@adm01:~$ R=https://ctr01.par1.medisphere.internal:5000; A="$REGISTRE_UTILISATEUR:$REGISTRE_MOT_DE_PASSE"
   admin@adm01:~$ curl -s -u "$A" $R/v2/_catalog | jq
   admin@adm01:~$ curl -s -u "$A" $R/v2/medidoc/medidoc/tags/list | jq
   admin@adm01:~$ curl -s -u "$A" -H 'Accept: application/vnd.oci.image.index.v1+json' $R/v2/medidoc/medidoc/manifests/1.0.0 | jq '.manifests[].platform'
   admin@adm01:~$ curl -sI -u "$A" -H 'Accept: application/vnd.oci.image.index.v1+json' $R/v2/medidoc/medidoc/manifests/1.0.0 | grep -i docker-content-digest
   ```
   L'empreinte est **celle de l'index de l'archive** : `skopeo copy --all` sans conversion de format conserve les octets du manifeste. C'est ce qui permet d'épingler `…@sha256:` une image construite ailleurs, et de prouver (E11) qu'elle n'a pas été modifiée en route. (`-u "$A"` met le mot de passe dans la ligne de commande de `curl` : visible par `ps` sur `adm01` ; acceptable sur un poste personnel, sinon `-K`.)

8. `skopeo copy … medidoc/medidoc:essai` (depuis une image **différente**, par exemple `medidoc:1.0.0-scratch` si tu l'as encore, sinon `docker push` d'une image retaguée et modifiée) ; `DELETE …/manifests/<empreinte>` → 202 ; `sudo systemctl start registre-gc.service` ; `journalctl -u registre-gc.service` montre les blobs marqués et supprimés (« layer link eligible for deletion », « Deleting blob »). L'espace du volume `registre_donnees` diminue. Si l'étiquette d'essai désignait le **même** contenu que `1.0.0`, le `DELETE` aurait supprimé les deux (voir E13).

9. Fiche et registre des secrets : voir le modèle. Le registre des secrets dit **où** sont les mots de passe (Vault `lab`, `host_vars/ctr01/vault.yml` ; `~/.config/workbook/` ; variables de CI de E21), qui les utilise et comment les faire tourner.

**Explications**

CNCF Distribution est l'implémentation de référence de l'*OCI Distribution Specification* : une API HTTP (`/v2/<nom>/manifests/<référence>`, `/v2/<nom>/blobs/<empreinte>`, `/v2/<nom>/blobs/uploads/`) devant un stockage (ici un dossier). Il ne connaît ni projets, ni droits, ni analyse : une authentification simple (htpasswd), et c'est tout. Supprimer un manifeste ne libère rien : les blobs restent tant que le ramasse-miettes ne les a pas balayés, et ce balayage exige un registre inactif. Le réglage `http.host` est l'adresse que le registre écrit dans les en-têtes `Location` des téléversements : s'il ne correspond pas au nom utilisé par les clients, ceux-ci envoient la suite de la poussée à une autre adresse (constaté à la rédaction : les identifiants ne suivent pas, la poussée échoue en `unauthorized`).

**Alternatives**
- Harbor dès maintenant : trop lourd pour `ctr01` (2 Go) et c'est l'objet du M13.
- Zot (registre OCI natif, une seule binaire, droits par dépôt) : bonne alternative légère, non retenue pour rester sur l'implémentation de référence.
- Jetons (`auth.token`) au lieu de htpasswd : demande un serveur d'autorisation, c'est ce que fait Harbor.
- Registre en HTTP sur `localhost` seulement + tunnel SSH : évite le TLS, mais oblige chaque client à ouvrir un tunnel ; refusé (Sophie).

**Pièges classiques**
- `insecure-registries` dans `daemon.json` « pour aller vite » : désactive la vérification TLS pour cet hôte, sur toutes les machines qui l'ont, et pour toujours.
- Recalculer l'empreinte bcrypt à chaque passage d'Ansible : registre redémarré à chaque fois, poussées de la CI interrompues.
- `http.host` absent ou faux derrière un nom différent : poussées en échec avec des messages d'authentification trompeurs.
- Lancer `garbage-collect` registre démarré.
- Supprimer une étiquette en croyant ne supprimer qu'elle : on supprime un **contenu**.
- Oublier que tout compte authentifié peut **supprimer** : le compte `ci` peut effacer une version publiée. Harbor (M13) sépare enfin les droits.

**En production chez MédiSphère**

Ce registre ne vit que jusqu'au M13 : Harbor (`reg01`) apporte projets, robots à droits limités, immuabilité des étiquettes, analyse Trivy, signatures et réplication. La fiche dit comment migrer (M13-E03 : `skopeo copy --all`, empreintes préservées).

---

### M12-E16 — Hadolint et Dive : la qualité d'une image

**Solution**

Fichiers : [`.hadolint.yaml`](fichiers/M12-E16/.hadolint.yaml), [`.dive-ci`](fichiers/M12-E16/.dive-ci), extension du rôle `docker_engine` : [`tasks/outils_qualite.yml`](fichiers/M12-E16/ansible/roles/docker_engine/tasks/outils_qualite.yml), [`defaults` (extrait)](fichiers/M12-E16/ansible/roles/docker_engine/defaults/main-extrait-M12-E16.yml), [`host_vars/ctr01/docker_engine.yml`](fichiers/M12-E16/ansible/inventories/lab/host_vars/ctr01/docker_engine.yml) ; fiche [`qualite-images.md`](fichiers/M12-E16/medisphere/docs/conteneurs/qualite-images.md).

1. Correspondances : DL3006 (étiquette explicite), DL3007 (`latest`), DL3026 (registres de confiance), DL3002 (dernier `USER` root), DL3066 (Hadolint 2.15 : `USER` non numérique), DL3025 (forme JSON de `CMD`/`ENTRYPOINT`), DL4006 (`pipefail` avant un tube), DL3020 (`COPY` plutôt qu'`ADD`), DL3008/DL3009/DL3015 (paquets APT : version, ménage, recommandations), DL3064 (secret probable dans `ARG`/`ENV`), DL3048/DL3049 (étiquettes).

2. Hadolint : pas d'empreinte publiée par la release (seul le binaire `hadolint-linux-x86_64` est publié ; constaté le 2026-10-15) : empreinte calculée par l'équipe (`c7187db9…507`, à recalculer de ton côté et à comparer avec un second téléchargement) ; Dive : `0c20d18f…0571` (`dive_0.13.1_checksums.txt`). `get_url` avec `checksum: sha256:…` refuse un fichier dont l'empreinte diffère, **avant** de le mettre en place.

3. Sans configuration (niveau par défaut `info`) : le Dockerfile d'essai donne DL3006 (pas d'étiquette), DL3008, DL3009, DL3015, DL3066 (`USER app`), DL3025 (forme shell du `CMD`) — vérifié avec Hadolint 2.15.1. Tous de vrais défauts, mais le plus grave, le `curl … | sh` du `CMD`, n'est **pas** signalé comme tel : DL4006 (`pipefail`) ne regarde que les tubes des `RUN`, et aucune règle ne repère l'exécution d'un script téléchargé. C'est la limite de l'outil, et la raison de la revue humaine (E22). E05 : DL3049 (étiquettes) seulement avec la configuration de MédiSphère ; E10 et E11 : rien. Faux positifs typiques : DL3008 sur une image qu'on veut toujours à jour de sécurité (on choisit de **ne pas** figer les versions APT des images de base reconstruites chaque semaine, M12-E27 : dérogation écrite).

4. `.hadolint.yaml` : `failure-threshold: warning`, `trustedRegistries` (docker.io, gcr.io, ghcr.io, le registre de travail), `label-schema` des quatre étiquettes, `override.error` (DL3002, DL3004, DL3006, DL3007, DL3020, DL3025, DL4006, SC2086), `override.warning` (DL3066, DL3049). Résultat (vérifié) : E10, E11, E12 passent ; E05 échoue sur DL3049 (étiquettes absentes) : c'était une première image, E11 l'a remplacée.

5. Dans `~/m12/e11/ssh/Dockerfile` : `# hadolint ignore=DL3008` sur la ligne qui précède le `RUN apt-get …`, suivi de la raison dans le même commentaire ou la ligne au-dessus (« image d'essai jetable, jamais publiée »). Une règle ignorée globalement disparaît pour **tous** les Dockerfiles, y compris ceux où elle aurait attrapé une vraie erreur ; une dérogation en ligne est locale, visible en revue, et datée par Git.

6. Dive en mode CI (vérifié, Dive 0.13.1 avec le stockage containerd de Docker 29, par le socket du démon) : `efficiency` = part des octets de l'image qui ne sont pas « gaspillés » ; `wastedBytes` = octets de fichiers présents dans une couche puis remplacés ou supprimés par une couche suivante ; `userWastedPercent` = **tous** ces octets rapportés à la taille des couches qui suivent la **première** (code de Dive 0.13.1, `dive/image/image.go` : pour Dive, la « base » n'est que la toute première couche, pas l'image du `FROM`). `0.2.0` passe (mesuré : efficacité ≈ 97,5 %, ≈ 6,1 Mo perdus, `userWastedPercent` ≈ 7 %) : ces octets viennent pour l'essentiel (≈ 5,7 Mo, le même chiffre que `python:3.13-slim-trixie` seule) des couches de l'image Python officielle (fichiers de `dpkg` réécrits d'une couche à l'autre), le reste de `useradd` (`/etc/shadow`, `/etc/gshadow`… réécrits). D'où un `userWastedPercent` jamais nul pour une image Python, même sans faute de notre part : c'est ce qui fixe le seuil. `0.1.0` : uv et son cache dans l'image ne sont pas « gaspillés » au sens de Dive (rien n'est supprimé), d'où la limite de l'outil : il mesure le gaspillage, pas l'inutile. `medidoc:1.0.0` : 99,99 %.

7. Seuils retenus (`.dive-ci`) : `lowestEfficiency: 0.95`, `highestWastedBytes: 20MB`, `highestUserWastedPercent: 0.20`. Essai d'échec : une image `FROM python:3.13-slim-trixie` avec `RUN apt-get update && apt-get install -y curl` puis `RUN rm -rf /var/lib/apt/lists/*` dans une **autre** couche : `wastedBytes` ≈ 20 à 25 Mo, l'image échoue.

8. MR dans les deux projets, et copie de référence `exemples/.hadolint.yaml` et `exemples/.dive-ci` dans `ci-templates`.

**Explications**

Hadolint analyse le Dockerfile (et, via ShellCheck, les scripts des `RUN`) sans rien construire : il juge **l'intention**. Dive analyse l'image construite, couche par couche : il juge **le résultat**. Les deux sont complémentaires et aucun ne remplace la revue (E22 : une bonne moitié des défauts de Lucas leur échappe). Le seuil d'échec à `warning` force à traiter chaque avertissement, par une correction ou une dérogation justifiée, plutôt que de laisser s'accumuler un bruit qu'on finit par ignorer.

**Alternatives**
- `docker buildx build --check` (vérifications intégrées de BuildKit, Docker 27+) : quelques règles de syntaxe et de bonnes pratiques, sans configuration d'organisation ; utile en complément.
- `container-structure-test` (Google) : tests de **contenu** d'une image (tel fichier existe, tel utilisateur, telle commande répond) ; à considérer pour les tests de fumée.
- Trivy en mode `config` (M13) : contrôle les Dockerfiles comme du code d'infrastructure.

**Pièges classiques**
- Tout mettre dans `ignored:` pour « faire passer » : le contrôle ne contrôle plus rien.
- Lancer Dive sur une image d'une autre plateforme que l'hôte avec le stockage containerd : il analyse ce que `docker save` lui donne (à vérifier sur ta version si tu analyses une image `arm64`).
- Monter `/var/run/docker.sock` dans un conteneur Dive « pour éviter de l'installer » : c'est root sur l'hôte (règle 3 du module) ; d'où l'installation par le rôle. En CI, Dive lit une archive (`--source docker-archive`), sans socket.

**En production chez MédiSphère**

Job `hadolint` du gabarit de CI (E21) sur chaque MR, rapport Code Quality dans la MR ; Dive sur les images de base (M12-E27) et à la demande ; les normes (M12-E33) reprennent les seuils.

---

### M12-E17 — Conteneuriser MédiNotif : signaux, PID 1, arrêt propre

**Solution**

Fichiers : [`Dockerfile`](fichiers/M12-E17/medinotif-worker/Dockerfile), [`.dockerignore`](fichiers/M12-E17/medinotif-worker/.dockerignore), [`compose.yaml`](fichiers/M12-E17/medinotif-worker/compose.yaml), [`outils/secrets-compose.sh`](fichiers/M12-E17/medinotif-worker/outils/secrets-compose.sh), [`outils/essai-arret.sh`](fichiers/M12-E17/medinotif-worker/outils/essai-arret.sh), [`gitignore.extrait`](fichiers/M12-E17/medinotif-worker/gitignore.extrait).

1. `docker stop` envoie le signal d'arrêt de l'image (`STOPSIGNAL`, SIGTERM par défaut) au **PID 1** du conteneur, attend le délai de grâce (10 s par défaut, `--stop-timeout`/`stop_grace_period`), puis envoie SIGKILL. Le noyau **ignore** un signal adressé au PID 1 d'un espace de noms PID si ce processus n'a pas installé de gestionnaire pour ce signal (sauf SIGKILL et SIGSTOP venus de l'espace parent) : un `sleep`, un shell sans `trap`, ne meurent pas sur SIGTERM.

2. Dockerfile : même structure que E11 (deux étapes, uv 0.12.23, cache, verrou), compte 10002, `EXPOSE 9100`, `HEALTHCHECK` en Python sur `http://127.0.0.1:9100/metrics`, **`STOPSIGNAL SIGTERM`**, `ENTRYPOINT ["medinotif"]`. Le PID 1 est l'interpréteur Python (`/app/.venv/bin/python /app/.venv/bin/medinotif`, vérifié par `/proc/1/cmdline`) : le worker a installé ses gestionnaires de SIGTERM/SIGINT, il reçoit le signal.

3. `compose.yaml` : RabbitMQ `docker.io/library/rabbitmq:4.1`, sur un réseau interne seulement ; le mot de passe est passé par un **secret** Compose. L'image refuse `RABBITMQ_DEFAULT_PASS_FILE` (vérifié : « error: RABBITMQ_DEFAULT_PASS_FILE is set but deprecated », le conteneur s'arrête) : on compose `RABBITMQ_DEFAULT_PASS` au démarrage du processus (`entrypoint: ["/bin/sh", "-c"]`, `RABBITMQ_DEFAULT_PASS="$$(cat /run/secrets/amqp_mdp)" exec docker-entrypoint.sh rabbitmq-server`) : la variable n'existe que dans l'environnement du processus, pas dans la définition du conteneur (`docker inspect` ne la montre pas). Même méthode pour le worker et `MEDINOTIF_AMQP_URL`. `stop_grace_period: 30s`, `depends_on: rabbitmq: condition: service_healthy` (`rabbitmq-diagnostics -q check_port_connectivity`). `MEDINOTIF_TYPE_FILE: classic` : un courtier de test à un nœud n'a pas besoin d'une file quorum. Le secret est en 644 dans un dossier 700 : RabbitMQ (UID 999) et le worker (10002) doivent pouvoir le lire, les autres comptes de l'hôte ne peuvent pas entrer dans le dossier.

4. Le PID 1 du worker est `/app/.venv/bin/python /app/.venv/bin/medinotif` (le shell de `entrypoint` a fait `exec`) ; `curl …:9100/metrics | grep medinotif_messages_total` répond.

5. Résultat vérifié (`essai-arret.sh`) :
   ```
   durée de l arrêt : 2.3 s ; code de sortie : 0
   … "signal reçu, arrêt après le message en cours", "signal": 15
   … "notification envoyée (simulation)" …
   … "consommation arrêtée"
   … "arrêt terminé"
   ```
   Le message en cours (3 s d'envoi simulé) a été terminé et acquitté, puis le processus est sorti : pas de doublon.

6. Contre-exemples (mesurés à la rédaction, sauf le troisième point de la première ligne) :

   | Variante | PID 1 | Arrêt | Message |
   |---|---|---|---|
   | `ENTRYPOINT medinotif` (forme shell) | `/bin/sh -c medinotif` (le `dash` de Debian ne remplace pas le shell par la commande) | 10 s puis SIGKILL, code **137** | le worker ne reçoit jamais SIGTERM ; tué en plein envoi, le message non acquitté est **remis en file** : envoyé deux fois |
   | forme shell + `--init` | `docker-init -- /bin/sh -c medinotif` | immédiat, code **143** | tini transmet SIGTERM au **shell**, qui meurt ; le worker, orphelin, est tué avec le conteneur : message interrompu, remis en file |
   | forme exec, `MEDINOTIF_BACKEND=stdin` | le worker | 10 s puis SIGKILL, code 137 | la source `stdin` attend une ligne (lecture bloquante) et ne revient pas sur le drapeau d'arrêt : l'arrêt propre dépend aussi du code de l'application |

   `--init` ne sert qu'à deux choses : récolter les **zombies** (un PID 1 qui lance des enfants sans les attendre) et transmettre les signaux à un enfant direct qui ne serait pas PID 1. MédiNotif ne lance aucun processus : inutile ici, et il ne corrige pas une forme shell.

7. MR et fusion ; la pile reste démarrée (`docker compose up -d --wait`).

**Explications**

L'arrêt propre est une chaîne : la plateforme envoie le **bon** signal, au **bon** processus, et attend **assez** longtemps ; l'application sait s'arrêter (finir, acquitter, fermer). Il suffit d'un maillon cassé pour que l'arrêt devienne un SIGKILL au bout du délai : forme shell (mauvais destinataire), `STOPSIGNAL` inadapté (Apache attend `SIGWINCH` pour un arrêt gracieux, PostgreSQL `SIGINT` pour un arrêt rapide propre), délai trop court, ou application qui bloque. Un message acquitté **après** traitement (au moins une fois) ne se perd jamais, mais peut être traité deux fois si le worker est tué entre l'envoi et l'acquittement : l'arrêt propre réduit ce cas à presque rien.

**Alternatives**
- `tini` dans l'image (`ENTRYPOINT ["tini", "--", "medinotif"]`) : équivalent de `--init`, utile pour une application qui lance des sous-processus ; l'image de Valkey l'utilise.
- `exec` en fin d'un script d'entrée (`docker-entrypoint.sh` des images officielles) : le script prépare, puis se remplace par le processus.
- RabbitMQ : fichier de définitions (`load_definitions`) avec un utilisateur et un mot de passe haché, monté en secret : pas de mot de passe en clair dans l'environnement du processus non plus ; plus propre, plus long à mettre en place.

**Pièges classiques**
- `CMD medinotif` « parce que ça marche » : ça marche, jusqu'au premier arrêt.
- `stop_grace_period` plus court que le plus long traitement.
- Croire que `--init` règle tout.
- Tester l'arrêt sans message en cours : il est toujours propre quand il n'y a rien à finir.
- `RABBITMQ_DEFAULT_PASS` en clair dans `environment:` : visible dans `docker inspect` et dans `docker compose config`.

**En production chez MédiSphère**

Le délai de grâce de chaque plateforme suit celui de l'application (Quadlet `StopTimeout=`/`TimeoutStopSec=` au M12-E46, `terminationGracePeriodSeconds` au M14) ; le test d'arrêt devient un test de fumée du pipeline ; la métrique `medinotif_messages_total{resultat="echec"}` est suivie (M21).

---

### M12-E18 — Journaux, ressources et santé des conteneurs

**Solution**

Fichiers : [extrait des défauts du rôle `docker_engine`](fichiers/M12-E18/ansible/roles/docker_engine/defaults/main-extrait-M12-E18.yml) (journaux compressés), [`compose.yaml`](fichiers/M12-E18/mediagenda-api/compose.yaml) de MédiAgenda (limites, délais, cache borné), [extrait de `mediagenda-api.container`](fichiers/M12-E18/ctr02/mediagenda-api.container.extrait), fiche [`journaux.md`](fichiers/M12-E18/medisphere/docs/conteneurs/journaux.md).

1. `json-file` écrit `/var/lib/docker/containers/<ID>/<ID>-json.log` (une ligne JSON par ligne de sortie, avec le flux et l'heure). Sans `max-size`, le fichier grossit sans fin : c'est la première cause de disque plein des hôtes Docker (panne de M12-E39). La rotation de M12-E02 (10 Mo × 3) borne chaque conteneur à 30 Mo.

2. `docker_engine_daemon_defaut` reçoit `compress: "true"` (fichiers tournés compressés en gzip). Les options de `daemon.json` ne valent que pour les conteneurs **créés après** le redémarrage du démon : `mediagenda-api-1` garde son `LogConfig` d'origine (`{"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}`) jusqu'à sa recréation (`docker compose up -d --force-recreate`).

3. Conteneurs d'essai :
   ```
   admin@ctr01:~$ docker run -d --name m12-e18-local --log-driver local docker.io/library/debian:trixie-slim sh -c 'while :; do date; sleep 1; done'
   admin@ctr01:~$ docker run -d --name m12-e18-journald --log-driver journald --log-opt tag=m12-e18 docker.io/library/debian:trixie-slim sh -c 'while :; do date; sleep 1; done'
   admin@ctr01:~$ docker logs --tail 3 m12-e18-local; docker logs --tail 3 m12-e18-journald
   admin@ctr01:~$ sudo journalctl CONTAINER_NAME=m12-e18-journald -n 3 -o verbose | grep -E 'CONTAINER_|SYSLOG_IDENTIFIER'
   admin@ctr01:~$ sudo ls -l /var/lib/docker/containers/$(docker inspect -f '{{.Id}}' m12-e18-local)/local-logs/
   ```
   `local` : fichiers internes (format protobuf compressé), rotation 20 Mo × 5 par défaut, illisibles par un collecteur ; `journald` : champs structurés (`CONTAINER_NAME`, `CONTAINER_ID`, `CONTAINER_TAG`, `SYSLOG_IDENTIFIER=m12-e18`), rétention et quotas de journald, lisibles par tout ce qui lit le journal de l'hôte ; `docker logs` fonctionne avec les trois. Choix MédiSphère : `json-file` (format standard des collecteurs de journaux, M22), compressé et tourné.

4. Mesure (environnement de rédaction, ordre de grandeur) : API ≈ 70 à 90 Mo, PostgreSQL ≈ 40 Mo au repos, Valkey ≈ 10 Mo ; CPU négligeable sous une boucle de `curl`. Limites retenues : API 256 Mo / 1 CPU / 128 processus ; base 512 Mo / 1 CPU / 256 processus ; Valkey 128 Mo / 0,5 CPU / 64 processus avec `--maxmemory 96mb --maxmemory-policy allkeys-lru` (le cache évince avant que le noyau ne tue le conteneur, et l'API passe en mode dégradé si Valkey disparaît, README) ; migrations 256 Mo / 64 processus. `mem_limit`, `cpus`, `pids_limit` au niveau du service (Compose v5 les applique hors Swarm ; `deploy.resources.limits` aussi). Le `compose.yaml` est validé par `docker compose config -q`.

5. `stop_grace_period: 30s` pour l'API (20 s de `MEDIAGENDA_DELAI_ARRET` + marge) et pour la base (l'image arrête PostgreSQL par `SIGINT`, son `STOPSIGNAL` : arrêt *fast* avec point de reprise ; sans assez de temps, redémarrage en récupération). `docker inspect` : `HostConfig.Memory` = 268435456, `NanoCpus` = 1000000000, `PidsLimit` = 128, `Config.StopTimeout` = 30.

6. OOM :
   ```
   admin@ctr01:~$ docker run --name m12-e18-oom --memory 64m --memory-swap 64m docker.io/library/python:3.13-slim-trixie \
       python3 -c "b = bytearray(200 * 1024 * 1024)"; echo "code=$?"
   code=137
   admin@ctr01:~$ docker inspect -f '{{.State.OOMKilled}} {{.State.ExitCode}}' m12-e18-oom      # true 137
   admin@ctr01:~$ sudo journalctl -k --since -5min | grep -i -E 'oom|killed process'
   ```
   `--memory-swap` égal à `--memory` : pas de *swap* pour le conteneur (sinon il ralentit au lieu de mourir, si l'hôte a du swap). Pendant qu'il vit, `memory.events` du cgroup (`/sys/fs/cgroup/system.slice/docker-<ID>.scope/memory.events`) compte `oom` et `oom_kill`. Le noyau tue un processus **du cgroup** : l'hôte et les autres conteneurs ne sont pas touchés. Avec `--cpus 0.2` et `sh -c 'while :; do :; done'` : `docker stats` plafonne à 20 % d'un CPU, le conteneur n'est **jamais** tué (étranglement : `cpu.stat`, `nr_throttled`). Supprime le conteneur CPU ; garde `m12-e18-oom` arrêté pour la vérification.

7. Conteneur malade :
   ```
   admin@ctr01:~$ docker run -d --name m12-e18-malade --restart unless-stopped \
       --health-cmd 'curl -fsS http://127.0.0.1/nexiste-pas || exit 1' --health-interval 5s --health-retries 3 \
       docker.io/library/nginx:1.30-trixie
   ```
   Au bout de 15 à 20 s : `Up … (unhealthy)`, `RestartCount` = 0. Docker **ne redémarre pas** un conteneur malade : `restart:` ne réagit qu'à la **sortie** du processus. L'état `unhealthy` sert à `depends_on: condition: service_healthy`, à `docker compose up --wait`, et à la supervision : chez MédiSphère, la sonde `ms-verif-conteneurs` (M12-E28) le remonte ; sous Kubernetes, la sonde de vivacité (*liveness*) fait redémarrer le conteneur par le kubelet (M14). (L'image nginx a `curl` ; si la tienne ne l'a plus, utilise une autre commande.)

8. Clés ajoutées à l'unité (voir l'extrait) : `HealthOnFailure=kill`, `PidsLimit=128`, `PodmanArgs=--memory=256m --cpus=1`, `[Service] Restart=on-failure`, `RestartSec=5s`. `-dryrun` refuse `Memory=` (« unsupported key 'Memory' in group 'Container' ») : options de `podman run` par `PodmanArgs=`. Essai : rendre l'API muette sans toucher au reste, en suspendant son processus depuis l'hôte (le PID 1 d'un conteneur ignore un signal envoyé de l'intérieur, pas de l'espace parent) :
   ```
   app@ctr02:~$ podman top mediagenda-api hpid
   admin@ctr02:~$ sudo kill -STOP <HPID>
   app@ctr02:~$ podman healthcheck run mediagenda-api; echo $?          # unhealthy, 1
   app@ctr02:~$ journalctl --user -u mediagenda-api.service -f          # au 3e échec : kill, puis redémarrage par systemd
   ```
   (`podman pause` fige tout le conteneur et Podman refuse d'y exécuter la sonde : moins représentatif.) `systemctl --user status` montre l'unité repassée par `activating`, puis `active` avec un nouveau PID ; l'API répond de nouveau.

9. La fiche : voir le modèle.

**Explications**

Les limites sont des réglages de **cgroup v2** que le moteur écrit pour le conteneur : `memory.max` (au-delà, le noyau récupère des pages, puis tue un processus du groupe), `cpu.max` (quota sur une période : au-delà, le groupe attend), `pids.max` (au-delà, `fork` échoue). Elles protègent l'hôte et les voisins, et rendent la consommation **prévisible** : c'est ce que Kubernetes appellera *requests* et *limits* (M14). La sonde de santé est une commande exécutée **dans** le conteneur à intervalle régulier ; Docker en publie l'état, Podman sait en plus agir (`HealthOnFailure`), systemd s'en sert pour savoir quand un service est prêt (`Notify=healthy`).

**Alternatives**
- `deploy.resources.limits` et `reservations` dans Compose : même effet pour les limites ; les réservations ne sont appliquées qu'en Swarm.
- Pilote `journald` par défaut sur `ctr01` : cohérent avec Podman ; écarté pour garder un format de fichiers lu sans configuration par les collecteurs.
- Docker : un conteneur `autoheal` qui redémarre les conteneurs `unhealthy` (il monte le socket du démon : refusé).

**Pièges classiques**
- Une limite mémoire sans mesure : trop basse, l'application meurt sous la première vraie charge ; trop haute, elle ne protège rien.
- Limiter Valkey sans `maxmemory` : il grossit jusqu'à la limite et se fait tuer, le cache repart vide à chaque fois.
- Une sonde de vivacité qui dépend de la base (`/pret`) : une panne de la base fait redémarrer en boucle toutes les API (RB-120).
- `--memory` sans `--memory-swap` sur un hôte avec *swap* : le conteneur « survit » en swappant, l'hôte ralentit.
- Oublier que `daemon.json` ne change pas les conteneurs existants.

**En production chez MédiSphère**

Bornes par défaut dans les normes (M12-E33), mesurées et ajustées par service ; métriques des cgroups lues par la supervision (M12-E28, puis cAdvisor/kubelet et Prometheus au M21) ; journaux collectés et centralisés au M22.

---

### M12-E19 — Conteneuriser Legacy-RDV

**Solution** (une solution parmi d'autres ; l'exercice est libre)

Fichiers (projet `legacy/legacy-rdv`) : [`Dockerfile`](fichiers/M12-E19/legacy-rdv/Dockerfile), [`.dockerignore`](fichiers/M12-E19/legacy-rdv/.dockerignore), [`config.php`](fichiers/M12-E19/legacy-rdv/config.php), [`sante.php`](fichiers/M12-E19/legacy-rdv/sante.php), [`conteneur/apache-legacy-rdv.conf`](fichiers/M12-E19/legacy-rdv/conteneur/apache-legacy-rdv.conf), [`conteneur/php-legacy-rdv.ini`](fichiers/M12-E19/legacy-rdv/conteneur/php-legacy-rdv.ini), [`compose.yaml`](fichiers/M12-E19/legacy-rdv/compose.yaml), [`outils/secrets-compose.sh`](fichiers/M12-E19/legacy-rdv/outils/secrets-compose.sh) ; minuterie de purge sur `ctr01` : [`legacy-rdv-purge.service`](fichiers/M12-E19/ctr01/legacy-rdv-purge.service), [`legacy-rdv-purge.timer`](fichiers/M12-E19/ctr01/legacy-rdv-purge.timer) ; [`legacy-rdv-12-facteurs.md`](fichiers/M12-E19/medisphere/docs/conteneurs/legacy-rdv-12-facteurs.md).

*L'image.* `php:8.4-apache-trixie` épinglée ; `docker-php-ext-install mysqli` (seule extension absente : `fileinfo`, `mbstring`, `session` sont dans l'image) ; `php.ini-production` comme base, plus `conteneur/php-legacy-rdv.ini` (`upload_max_filesize = 6M`, `post_max_size = 8M` — ce que la VM mettait dans l'hôte virtuel —, sessions en fichiers sous `/var/lib/php/sessions`, `display_errors = Off`, `log_errors = On`, `expose_php = Off`) ; Apache sur **8080** (`ports.conf`), hôte virtuel `conteneur/apache-legacy-rdv.conf` qui reprend les interdictions de la VM (`uploads/`, `inc/`, `cron/`, fichiers techniques) et envoie `ErrorLog`/`CustomLog` vers `/proc/self/fd/2` et `/proc/self/fd/1` (sondes exclues du journal d'accès) ; code copié en root (lecture seule pour `www-data`), seuls `uploads/` et `/var/lib/php/sessions` appartiennent à 33 ; `USER 33:33` ; `HEALTHCHECK` sur `sante.php` (`curl` est dans l'image officielle) ; `STOPSIGNAL SIGWINCH` (arrêt gracieux d'Apache, déjà celui de l'image) ; `CMD ["apache2-foreground"]` (le script fait `exec apache2 -DFOREGROUND` : Apache est le PID 1). Construite et éprouvée à la rédaction (722 Mo : c'est l'image officielle ; une image plus fine passerait par php-fpm, écart n° 13).

*La configuration.* `config.php` lit `LEGACY_RDV_DB_HOST`, `_DB_NAME`, `_DB_USER`, `_DB_PASS_FILE` (ou `_DB_PASS`), `_UPLOAD_DIR`, `_LOG_FILE`, `_RETENTION_JOURS`, `_FUSEAU`, `_AFFICHER_ERREURS`, avec les valeurs d'InfoGér par défaut, **sauf** le mot de passe (plus de valeur par défaut). Dans l'image : `LEGACY_RDV_LOG_FILE=php://stderr` — et non `/dev/stderr` : PHP résout le lien `/dev/stderr` → `/proc/self/fd/2` → `pipe:[…]`, qui n'est pas un fichier, et `@file_put_contents` échoue sans bruit. `sante.php` n'ouvre ni session ni connexion.

*La pile.* `compose.yaml` : `web` (image construite, `8090:8080`, volumes nommés `pieces-jointes` et `sessions`, secret du mot de passe, dépendance `service_healthy` sur `mariadb`), `mariadb` (`mariadb:11.8` épinglée, `MARIADB_PASSWORD_FILE` et `MARIADB_ROOT_PASSWORD_FILE` : l'image officielle les accepte, `healthcheck.sh --connect --innodb_initialized`, `TZ=Europe/Paris`, pas de `ports:`), `purge` (profil `admin`, même image et même volume, `php cron/purge-uploads.php`) ; secrets dans `~/.config/legacy-rdv/` (dossier 700, fichiers 644 lus par 33 et 999), créés par `outils/secrets-compose.sh`. Éprouvée à la rédaction : page d'accueil 200, formulaire avec jeton anti-CSRF, téléversement d'un PDF de 4,5 Mo, téléchargement par `piece.php`, persistance après `docker compose down`/`up`, `schema.sql` et `inc/` refusés (403), purge (`0 fichier(s) supprimé(s)`), mot de passe absent de `docker inspect` (seul `LEGACY_RDV_DB_PASS_FILE=/run/secrets/…`).

*La purge.* `legacy-rdv-purge.timer` (03:30, comme le cron d'InfoGér) lance `docker compose --profile admin run --rm purge` : une seule exécution, quel que soit le nombre d'instances web, et elle voit les mêmes fichiers.

*La migration.* Sur `legacy01` : `sudo mariadb-dump --single-transaction --routines legacy_rdv | gzip > /tmp/legacy_rdv.sql.gz` et `sudo tar -C /var/www/legacy-rdv -czf /tmp/uploads.tgz uploads` ; transfert `scp -3` par `adm01` vers `ctr01:~/m12/e19/` ; import : `gunzip -c ~/m12/e19/legacy_rdv.sql.gz | docker compose exec -T mariadb sh -c 'mariadb -u root -p"$(cat /run/secrets/legacy_rdv_db_root)" legacy_rdv'` (le mot de passe ne quitte pas le conteneur) ; pièces jointes : `docker run --rm --user 33:33 -v legacy-rdv_pieces-jointes:/dest -v ~/m12/e19:/src:ro docker.io/library/debian:trixie-slim tar -C /dest --strip-components=1 -xzf /src/uploads.tgz` ; puis `shred -u` des fichiers intermédiaires sur les deux hôtes. Contrôles : nombre de lignes de `rendez_vous` égal des deux côtés, une pièce jointe migrée se télécharge, l'heure affichée d'un rendez-vous est la même que sur `legacy01` (base et application en `Europe/Paris`).

*Le mot de passe de 2014.* Il disparaît du code (`config.php`) mais reste dans l'historique Git (premier commit, copie de `apps/legacy-rdv/`) : Gitleaks le signale au premier pipeline. On ne réécrit pas l'historique d'un projet partagé ; on change le mot de passe partout où il servait (la base conteneurisée a un mot de passe neuf ; sur `legacy01`, qui disparaît en fin de module, à changer aussi si elle doit vivre), et on documente l'exception dans `.gitleaksignore` (empreinte du constat) avec la référence du ticket.

**Explications**

Conteneuriser une application héritée, c'est d'abord **lister ce qu'elle suppose de sa machine** (le README en donne treize points), puis, pour chacun, choisir : corriger par la configuration (sans toucher au code métier), compenser par la plateforme (volume, tâche ponctuelle, sonde ajoutée), ou assumer et écrire l'écart. La règle « ne pas changer le comportement » protège la recette : les cabinets ne voient aucune différence, et la migration vers Kubernetes (F4) repartira d'un état documenté.

**Alternatives**
- php-fpm + nginx (deux conteneurs ou un pod) : plus léger, configuration et journaux à revoir (écart n° 13) ; à faire au F4.
- Sessions dans Valkey (`session.save_handler = redis`, extension `redis`) : supprime l'écart n° 4 et permet deux instances ; c'est une modification de configuration PHP, pas du code — envisageable dès maintenant, au prix d'une extension compilée de plus.
- Pièces jointes sur le partage NFS CephFS `/legacy-rdv` du M08 (volume NFS de Docker) : partageable entre instances, mais `ctr01` n'a pas de carte sur le VLAN 30.

**Pièges classiques**
- Garder Apache en root « parce que l'image le fait » : l'image démarre en root pour ouvrir le port 80 puis passe à `www-data` ; en non root, on choisit un port > 1024 (sous Docker 29 un non root peut ouvrir le port 80 du conteneur, car Docker y abaisse `net.ipv4.ip_unprivileged_port_start` à 0 — M12-E32 —, mais ni Podman sans privilège ni Kubernetes ne le garantissent) et il faut les dossiers de journaux et de PID d'Apache accessibles (l'image officielle les prépare dans `/var/run/apache2` et `/var/log/apache2`, à vérifier si tu changes de base).
- `php_value` laissés dans l'hôte virtuel : sans effet hors `mod_php` et oubliés au premier changement de serveur.
- `/dev/stderr` dans `config.php` : journal perdu sans message.
- Sonde sur `index.php` : chaque panne de MariaDB fait redémarrer le serveur web.
- Base importée en UTC : les rendez-vous se décalent d'une ou deux heures.
- Laisser `legacy_rdv.sql.gz` dans `/tmp` de `legacy01` ou de `ctr01`.

**En production chez MédiSphère**

L'image est construite par la CI (E21) et analysée (M13) ; la recette tourne sous Podman/Quadlet sur `ctr02` (mini-projet), puis l'application part sur Kubernetes au final F4 avec sessions partagées et stockage objet.

---

### M12-E20 — Un runner GitLab à exécuteur Docker

**Solution**

Fichiers : [`socle/runner02.tf`](fichiers/M12-E20/infra/socle/runner02.tf) ; rôle `gitlab_runner` étendu : [`tasks/main-extrait-M12.yml`](fichiers/M12-E20/ansible/roles/gitlab_runner/tasks/main-extrait-M12.yml) (ce qui change dans `main.yml`, `preconditions.yml`, `runner.yml`), [`tasks/executeur_docker.yml`](fichiers/M12-E20/ansible/roles/gitlab_runner/tasks/executeur_docker.yml), [`templates/config.toml.j2`](fichiers/M12-E20/ansible/roles/gitlab_runner/templates/config.toml.j2), [`templates/docker-config.json.j2`](fichiers/M12-E20/ansible/roles/gitlab_runner/templates/docker-config.json.j2), [`defaults` (extrait)](fichiers/M12-E20/ansible/roles/gitlab_runner/defaults/main-extrait-M12.yml) ; [`host_vars/runner02/`](fichiers/M12-E20/ansible/inventories/lab/host_vars/runner02/) ; [`playbooks/runner02.yml`](fichiers/M12-E20/ansible/playbooks/runner02.yml) ; [extrait de la matrice des flux](fichiers/M12-E20/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait).

1. Valeurs par défaut (documentation de GitLab Runner) : `privileged = false` ; `volumes` vide (le runner crée tout de même un volume de cache) ; `pull_policy = ["always"]` ; `allowed_pull_policies` = la politique configurée ; `security_opt` vide (profils par défaut du démon : seccomp et AppArmor `docker-default`) ; `memory`, `cpus` sans limite. `privileged = true` donne au conteneur du job toutes les capacités, tous les périphériques de l'hôte, `/sys` en écriture, ni seccomp ni AppArmor : un job peut monter le disque de `runner02`, lire les jobs voisins et le `config.toml` (jeton du runner). Avec Docker-in-Docker, le démon du service `dind` appartient au job, mais il tourne dans un conteneur privilégié : c'est la même chose qu'être root sur l'hôte.

2. `socle/runner02.tf` : modules `vm-debian` (VM, intention NetBox, adresse imposée 10.10.20.17, IP primaire) et `enregistrement-dns` (A et PTR) ; plan : les ressources du module (VM, objets NetBox) et celles du DNS, **rien d'autre** dans l'état `socle` ne change. `qm set 1012 --startup order=5` en root. `docs/socle/inventaire.md` : ligne `runner02`.

3. GitLab : *Admin → CI/CD → Runners → New instance runner*, étiquettes `docker,socle`, « Run untagged jobs » décoché, description `runner02-docker` ; le jeton `glrt-…` n'est affiché qu'une fois : directement dans `ansible-vault edit inventories/lab/host_vars/runner02/vault.yml`.

4. Le rôle : `gitlab_runner_executeur` choisit le profil ; pour `docker`, `executeur_docker.yml` vérifie le démon, **refuse** une configuration dangereuse (assertions), relit le jeton dans le `config.toml` en place (`slurp` + `regex_search`) sinon prend celui du Vault, génère `config.toml` (0600, `no_log`), redémarre le service si besoin, puis `gitlab-runner verify --name runner02-docker`. Les outils de l'exécuteur shell (`outils_*.yml`, Node, Packer, OpenTofu, step) et l'enregistrement par `register` sont conditionnés à `gitlab_runner_executeur == 'shell'`. Pourquoi générer `config.toml` ici, alors qu'on ne le faisait pas pour `runner01` (M04-E16) ? Pour l'exécuteur Docker, la **sécurité** du runner est dans ce fichier (privilège, options de sécurité, volumes, politique de tirage, limites) : elle doit être relue en MR et rejouée à l'identique ; on garde la seule donnée que le runner peut changer, le jeton. Le scénario Molecule de l'exécuteur shell reste vert ; un second scénario est proposé dans l'extrait.

5. `host_vars/runner02/docker_engine.yml` : mêmes versions que `ctr01`, `docker_engine_groupe_docker: []`, émulation activée ; `gitlab_runner.yml` : profil `docker`, nom, étiquettes, jeton. Le service `gitlab-runner` tourne en **root** (unité du paquet) : c'est lui qui parle au démon, pas le compte `gitlab-runner`, qui reste hors du groupe `docker` (assertion du M04). Règle de bordure `runner02` → `ctr01:5000`.

6. Essai : le job tourne en `uid=0(root)` **dans le conteneur** (l'image Python officielle n'a pas d'`USER`) — root du conteneur, sans capacités dangereuses, dans les profils seccomp et AppArmor par défaut, pas root de l'hôte ; `/proc/1/cgroup` montre `0::/` (espace de noms cgroup) ; la racine MédiSphère est là ; `/var/run/docker.sock` n'existe pas. `image: …:latest` : accepté par le runner (aucune liste d'images autorisées avant le M13), mais c'est ce que les normes interdisent (M12-E33) et que le M13 bloquera (`allowed_images`).

7. Pendant un job : `docker ps` montre `runner-<ID>-project-<N>-concurrent-0-…-build` et le conteneur d'aide (`…-predefined`) ; `docker inspect` : `Privileged=false`, `SecurityOpt=null` (avant E21), `Memory=1610612736`, montages : volume de cache (`runner-…-cache-…`) sur `/cache`, volume de construction sur `/builds`, la racine MédiSphère en lecture seule. Le dépôt cloné vit dans un volume Docker du runner, détruit avec le job ou réutilisé selon `GIT_STRATEGY`.

8. Documentation et registre des secrets : jeton du runner (Vault `lab`, `config.toml` de `runner02`), à renouveler si la VM est reconstruite (nouvel objet runner).

**Explications**

L'exécuteur Docker isole chaque job dans des conteneurs neufs, à partir de l'image que **le job** choisit : le runner ne porte plus les outils, et deux projets aux besoins contradictoires cohabitent. La sécurité tient alors à ce que le conteneur du job ne puisse rien sur l'hôte : pas de mode privilégié, pas de socket du démon, des limites, et aucun secret de l'hôte dans le conteneur. Le jeton du runner, lui, reste sur l'hôte (`config.toml`, 0600, root).

**Alternatives**
- Exécuteur `docker-autoscaler` (VM éphémère par job) : isolation forte, demande une infrastructure à la demande ; à reconsidérer avec OpenStack (M10) si le besoin apparaît.
- Exécuteur Kubernetes (M19) : la cible à terme pour une partie des pipelines.
- Podman comme moteur de l'exécuteur Docker (socket Podman sans privilège) : possible, fonctionnalités à valider (services, caches) ; non retenu pour la CI (ADR-0120).

**Pièges classiques**
- `privileged = true` « pour Docker-in-Docker » : interdit (PLAN §4.10).
- Monter `/var/run/docker.sock` dans les jobs : root sur `runner02`.
- `DOCKER_AUTH_CONFIG` dans `environment` de `config.toml` : tout job le lit (E21).
- Générer `config.toml` sans relire le jeton en place : une rotation faite par le runner serait écrasée par l'ancien jeton.
- Oublier `allowed_pull_policies` : un projet peut alors demander `pull_policy: never` et utiliser une image laissée par un autre job.

**En production chez MédiSphère**

`runner02` est sauvegardé (VM par PBS) et supervisé comme le reste du socle (mini-projet) ; au M13, ses images de jobs passent par les caches de Harbor (`allowed_images`), au M19 une partie des pipelines part sur Kubernetes.

---

### M12-E21 — Construire les images en CI sans mode privilégié

**Solution**

Fichiers : gabarit [`templates/image.yml`](fichiers/M12-E21/ci-templates/templates/image.yml) ; `.gitlab-ci.yml` de [`mediagenda/api`](fichiers/M12-E21/mediagenda-api/.gitlab-ci.yml), [`medidoc/medidoc`](fichiers/M12-E21/medidoc/.gitlab-ci.yml), [`medinotif/worker`](fichiers/M12-E21/medinotif-worker/.gitlab-ci.yml), [`legacy/legacy-rdv`](fichiers/M12-E21/legacy-rdv/.gitlab-ci.yml) ; outil [`ms-variables-registre`](fichiers/M12-E21/outils/bin/ms-variables-registre) ; exceptions du runner dans [`host_vars/runner02/gitlab_runner.yml`](fichiers/M12-E20/ansible/inventories/lab/host_vars/runner02/gitlab_runner.yml) (section M12-E21) ; fiche [`construction-ci.md`](fichiers/M12-E21/medisphere/docs/conteneurs/construction-ci.md).

1. Documentation de BuildKit (*Rootless mode*, *Docker*) : `seccomp=unconfined` (laisser passer `unshare`, utilisé par runc, et `mount`, utilisé par les *snapshotters*), `apparmor=unconfined` (monter des systèmes de fichiers ; inutile sur un hôte sans AppArmor — Debian 13 en a un), `systempaths=unconfined` (ne pas masquer `/proc` dans le conteneur, pour que chaque `RUN` ait son propre `/proc`) ; ce dernier peut être remplacé par l'option **de buildkitd** `--oci-worker-no-process-sandbox` (pas de nouvel espace PID par `RUN` ; les `RUN` voient — et pourraient tuer — les processus du démon de leur propre conteneur). `systempaths=unconfined` est traité par le client `docker` (il vide les chemins masqués de la configuration), il n'existe pas dans `security_opt` de GitLab Runner : on prend donc `--oci-worker-no-process-sandbox`, comme la documentation de GitLab. Celle-ci déconseille `seccomp:unconfined` et propose un profil seccomp dédié : piste d'amélioration écrite dans la fiche.

2. Essai sur `runner02` (`sudo docker run --rm -v ~/m12/e21:/src:ro -w /src --entrypoint buildctl-daemonless.sh -e BUILDKITD_FLAGS=--oci-worker-no-process-sandbox -e BUILDCTL_CONNECT_RETRIES_MAX=40 docker.io/moby/buildkit:v0.34.0-rootless@sha256:… build --frontend dockerfile.v0 --local context=. --local dockerfile=.`) : sans option, `[rootlesskit:parent] error: failed to start the child: fork/exec /proc/self/exe: operation not permitted` (vérifié : seccomp refuse la création de l'espace de noms) ; avec `--security-opt seccomp=unconfined` seul, l'erreur suivante vient d'AppArmor (montage refusé, à constater sur Debian : l'environnement de rédaction n'avait pas AppArmor) ; avec les deux, la construction passe. Sans `BUILDCTL_CONNECT_RETRIES_MAX`, sur une petite VM : `could not connect to unix:///run/user/1000/buildkit/buildkitd.sock after 10 trials` avec un journal vide (vérifié : le démon met plus de 3 s à répondre).

3. `gitlab_runner_docker_security_opt: [seccomp=unconfined, apparmor=unconfined]` (commentée), `gitlab_runner_docker_auth` (compte `ci`) : le rôle écrit `/root/.docker/config.json` de `runner02`, **première** source d'identifiants de tirage du runner (documentation « Use a private container registry ») et invisible des jobs ; une variable `DOCKER_AUTH_CONFIG` dans `environment` de `config.toml` serait, elle, injectée dans **chaque** job, y compris ceux des MR. Fiche `construction-ci.md` : voir le modèle.

4. Le gabarit (vérifié hors GitLab en rejouant son script dans `moby/buildkit:v0.34.0-rootless` avec les variables d'un job : poussée `amd64` + `arm64` dans un `registry:3` en TLS et htpasswd, cache poussé puis réutilisé, empreinte identique au second passage, MR sans identifiants, échec explicite sans identifiants sur `main`) :
   - `.hadolint` : image `hadolint/hadolint:v2.15.1-debian` épinglée (elle a un shell, contrairement à l'image par défaut), `entrypoint: [""]`, rapport `gitlab_codeclimate` en artefact `codequality`, puis `hadolint` qui échoue selon `.hadolint.yaml` ;
   - `.image-construction` : image `moby/buildkit:v0.34.0-rootless` épinglée, `entrypoint: [""]`, `BUILDKITD_FLAGS=--oci-worker-no-process-sandbox`, `BUILDCTL_CONNECT_RETRIES_MAX=40` ; règles : MR → `PUBLIER=non`, étiquette `vX.Y.Z` et `main` → publication ; le script calcule les étiquettes (`${CI_COMMIT_TAG#v}`, `main-<8 caractères du SHA>`), refuse `latest`, lit la date du commit (`git -c safe.directory=…` : le dépôt du job appartient à root, le job tourne sous l'UID 1000), écrit `~/.config/buildkit/buildkitd.toml` (`[registry."<hôte>"] ca = ["/etc/medisphere/racine-ca.crt"]`), écrit `~/.docker/config.json` en 0600 **seulement** pour publier, puis `buildctl-daemonless.sh build --output type=image,"name=…",push=true,rewrite-timestamp=true --import-cache/--export-cache type=registry,ref=$IMAGE:cache,mode=max` ; en MR, sortie `type=oci` jetée. `after_script` efface le fichier d'authentification.
   - Publication de `ci-templates` : MR, `feat: gabarit image.yml (construction sans privilège)` → semantic-release publie `v1.<N>.0` et la branche `v1` avance (M01-E25).

5. `ms-variables-registre` : le mot de passe arrive sur l'entrée standard (`ansible-vault view … | sed …`), chaque appel à l'API lit le jeton d'administration dans un fichier (`curl -H @…`), la valeur passe par `--data-urlencode value@-`. `REGISTRE_UTILISATEUR` est protégée mais **pas** masquée (GitLab refuse de masquer une valeur de moins de 8 caractères ; ce n'est pas un secret), `REGISTRE_MOT_DE_PASSE` protégée et masquée.

6. `.gitlab-ci.yml` de `mediagenda/api` : inclusion des trois gabarits en `ref: v1` ; **workflow redéfini** (celui de `qualite.yml` plus `if: $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/`) ; `tests` sur `runner01` (étiquette `shell`, uv y est) ; `hadolint: extends: .hadolint` ; `image: extends: .image-construction`, `needs: [tests, hadolint]`, `IMAGE` et `PLATEFORMES`. Journal du job de MR : `publication : non`, sortie OCI, aucune ligne d'authentification. Sur `main` : `publié : …/mediagenda/api:main-<SHA>` ; sur `v1.0.0` : `…/mediagenda/api:1.0.0` (index à deux plateformes ; la partie `arm64` sous QEMU prend plusieurs minutes).

7. MédiDoc : tests Go dans `golang:1.26-trixie` épinglée (cache des modules dans le cache du runner), image multi-plateformes en compilation croisée. Deux pipelines de l'étiquette `v1.0.0` (« Retry » ou « Run pipeline » sur l'étiquette) : même empreinte d'index (même commit, même `SOURCE_DATE_EPOCH`, cache réutilisé : étapes `CACHED` dans le journal).

8. Preuves : extrait du journal de MR, `docker inspect` d'un conteneur de job (`Privileged: false`, `SecurityOpt: ["seccomp=unconfined", "apparmor=unconfined"]`, aucun montage du socket), et l'index (`curl … -H 'Accept: application/vnd.oci.image.index.v1+json' …/manifests/1.0.0 | jq '.manifests[].platform'`).

**Explications**

Construire une image, c'est exécuter les `RUN` d'un Dockerfile dans des conteneurs ; dans un job, il faut donc un moteur de conteneurs **à l'intérieur** d'un conteneur. Docker-in-Docker y parvient en demandant tous les privilèges ; BuildKit sans privilège y parvient en créant ses propres espaces de noms **utilisateur** (le root des `RUN` est l'UID 1000 du conteneur du job, lui-même non privilégié sur l'hôte) : il lui faut seulement le droit d'appeler `unshare` et `mount`, que les profils par défaut de Docker retirent. Le gabarit encapsule tout cela : un projet ne déclare que ce qui le concerne (son image, ses plateformes), et chaque amélioration (Harbor, signature au M13) se fait une fois, dans `ci-templates`.

**Alternatives**
- Buildah dans le job (`quay.io/buildah/stable`, `--isolation chroot`, stockage `vfs`) : mêmes exceptions en pratique, plus lent (`vfs`).
- Kaniko : ni mode privilégié ni option de sécurité, mais il tourne en root dans le conteneur du job ; le dépôt de Google a été archivé en juin 2025 (plus de correctifs amont), seuls des forks (Chainguard, autres) le maintiennent : non retenu.
- Construire sur `runner02` en exécuteur shell avec le Docker de l'hôte : le compte du job serait dans le groupe `docker`, donc root (refusé).
- Docker Buildx avec un constructeur distant (`buildx create --driver remote tcp://…` vers un BuildKit dédié en TLS mutuel) : séparation nette, une VM de plus.

**Pièges classiques**
- `entrypoint: [""]` oublié : le job attend un démon qui ne s'arrête jamais, ou plante.
- Variables non protégées : un pipeline de MR (venant d'une branche quelconque) peut lire le mot de passe et le publier ailleurs.
- `--tls-verify=false`, `insecure = true` dans `buildkitd.toml` : la CI pousserait vers n'importe quel serveur qui répond à ce nom.
- Étiquettes dans `ETIQUETTES` écrites avec la syntaxe du shell (`${CI_COMMIT_TAG:-…}`) : GitLab ne l'interprète pas dans `variables:` ; c'est pour cela que le gabarit **calcule** les étiquettes quand la variable est vide.
- Construire `arm64` sur `runner02` sans émulation enregistrée sur l'**hôte** : `exec format error` dans les `RUN` arm64.
- Un cache poussé sous une étiquette `cache` qui finit par grossir sans fin : `--delete-untagged` du ramasse-miettes ne le touche pas (il est étiqueté) ; il est remplacé à chaque poussée.

**En production chez MédiSphère**

Au M13, le gabarit pousse dans Harbor avec un robot par projet, signe l'image (Cosign), attache SBOM et provenance, et l'immuabilité des étiquettes `v*` apporte le contrôle « ne jamais repousser une version » que ni le gabarit (qui refuse seulement `latest`) ni `registry:3` n'assurent aujourd'hui. Un profil seccomp dédié remplacera `seccomp=unconfined` une fois éprouvé.

---

### M12-E22 — Revue : les Dockerfiles du stagiaire

**Réponse attendue** (Hadolint 2.15.1, configuration de MédiSphère : il signale environ la moitié des défauts, ceux marqués **H**)

*Commentaire général.* Merci Lucas : la MR montre que tout démarre, c'est un vrai point de départ. Elle ne peut pas être fusionnée : elle contient des **secrets en clair** (qu'il faudra changer, même après correction, puisqu'ils sont dans l'historique de la branche), donne **root sur `ctr01`** à deux conteneurs (socket du démon, mode privilégié) et publie la base de données sur le réseau. Ordre de correction : 1) secrets, 2) privilèges et publications, 3) reproductibilité (versions), 4) taille et exploitation. Les modèles de E10, E11, E17 et la fiche `construction-ci.md` montrent la forme attendue ; on en parle ensemble.

*Commentaires ligne par ligne.*

| # | Fichier, ligne | Défaut | Gravité | Pourquoi | Correction |
|---|---|---|---|---|---|
| 1 | `mediagenda-api/Dockerfile` 5 | **H** `ARG PYPI_TOKEN=pypi-…` (jeton par défaut) | bloquant | la valeur par défaut est dans l'image (historique, configuration) et dans le dépôt | secret de construction (`--mount=type=secret`), jamais de valeur dans le Dockerfile ; **révoquer** le jeton |
| 2 | id. 6 | `ENV MEDIAGENDA_DB_URL=…Recette2026…` (non détecté par Hadolint : le nom ne « ressemble » pas à un secret) | bloquant | mot de passe dans l'image et dans `docker inspect` de chaque conteneur | configuration à l'exécution, mot de passe par secret (M12-E08) ; changer le mot de passe |
| 3 | id. 1 | **H** `FROM python:latest` | majeur | image qui change sans prévenir (Python 3.14 demain), nom court | `docker.io/library/python:3.13-slim-trixie@sha256:…` |
| 4 | id. 3 | **H** `MAINTAINER` | mineur | instruction obsolète | étiquettes OCI |
| 5 | id. 9-11 | **H** `RUN apt-get update` seul, puis `install` sans `--no-install-recommends` ni ménage | majeur | couche `update` mise en cache, installations ultérieures sur un index périmé ; image alourdie | une seule instruction `update && install --no-install-recommends … && rm -rf /var/lib/apt/lists/*` — et ici, aucun de ces paquets n'est utile à l'exécution |
| 6 | id. 10 | `build-essential`, `vim`, `git` dans l'image d'exécution (non détecté) | majeur | compilateur et outils offerts à un attaquant ; taille | multi-étapes (E11) : rien de cela dans l'image finale |
| 7 | id. 11 | **H** (en partie : DL4006) `curl … \| sh` pour installer uv | bloquant | exécute un script téléchargé, non vérifié, à chaque construction ; version d'uv non fixée | `COPY --from=ghcr.io/astral-sh/uv:0.12.23@sha256:… /uv /usr/local/bin/uv` |
| 8 | id. 14 | `COPY . .` sans `.dockerignore` (non détecté) | majeur | `.git`, `.venv`, fichiers `.env` et secrets locaux entrent dans l'image ; cache invalidé à chaque modification | `.dockerignore` en liste blanche ; copier seulement ce qui sert |
| 9 | id. 16 | `uv sync` sans `--locked` ni `--no-dev`, jeton en variable dans la commande (non détecté) | majeur | dépendances non figées, dépendances de développement livrées ; jeton dans l'historique | `uv sync --locked --no-dev` ; jeton par secret |
| 10 | id. 17 | `chmod -R 777 /app` (non détecté) | majeur | tout le monde écrit dans le code de l'application : une faille devient persistante | code en lecture seule (root), aucun `chmod` |
| 11 | id. (absent) | pas de `USER` : l'API tourne en root (non détecté par DL3002, qui ne regarde que le **dernier** `USER` écrit) | bloquant | une faille de l'API donne root dans le conteneur (et sur l'hôte en cas d'évasion avec Docker en root) | `USER 10001:10001` |
| 12 | id. 19 | `EXPOSE 80` (non détecté) | mineur | l'application écoute sur 8000 : documentation fausse, publication `80:80` du compose cassée | `EXPOSE 8000` |
| 13 | id. 20 | **H** `CMD` en forme shell, et `uv run` au démarrage | majeur | le PID 1 est `sh` : pas d'arrêt propre (M12-E17) ; `uv run` resynchronise au démarrage | `CMD ["mediagenda"]` |
| 14 | `medidoc/Dockerfile` 1 | `FROM golang:1.26` et image unique (non détecté) | majeur | 1,3 Go livrés en production avec le compilateur ; étiquette mobile | multi-étapes, distroless (E10) |
| 15 | id. 3 | `ADD https://…/v2.zip` (non détecté : DL3020 ne vise que les fichiers locaux) | majeur | téléchargement non vérifié à chaque construction, fichier inutile dans l'image (une branche d'un dépôt qui n'a rien à voir) | supprimer ; si un fichier distant est nécessaire : `ADD --checksum=sha256:…` ou téléchargement vérifié dans une étape de construction |
| 16 | id. 7 | `go build` sans `CGO_ENABLED=0`, `-trimpath` (non détecté) | mineur | binaire dynamique (casse sur distroless/scratch), chemins de construction dans le binaire | `CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=…"` |
| 17 | id. 9-10 | **H** clés S3 en `ENV` | bloquant | clés dans l'image et dans le dépôt | variables à l'exécution, depuis un secret ; **révoquer** les clés |
| 18 | id. 15 | `HEALTHCHECK` sur `/readyz` avec `curl` (Hadolint ne signale que la forme shell, DL3025 ; pas le vrai défaut) | majeur | la sonde dépend de S3 (disponibilité, pas vivacité) : chaque panne de S3 marque MédiDoc malade ; et l'image finale corrigée n'aura pas de `curl` | sonde de vivacité `/healthz`, assurée par l'orchestrateur (Compose, Quadlet, Kubernetes) |
| 19 | id. 16 | **H** `ENTRYPOINT medidoc` (forme shell) | majeur | PID 1 = `sh`, pas d'arrêt propre | `ENTRYPOINT ["/usr/local/bin/medidoc"]` |
| 20 | `sauvegarde-pg/Dockerfile` 3 | `apt-get upgrade` (non détecté par la 2.15) et **H** versions non fixées | mineur | construction non reproductible ; la mise à jour se fait par reconstruction de l'image de base | image de base à jour (M12-E27) |
| 21 | id. 3 | `sudo` installé (non détecté) | majeur | inutile en conteneur, et une porte d'élévation | supprimer |
| 22 | id. 6 | `chpasswd` : mot de passe root en clair dans l'image (non détecté) | bloquant | mot de passe dans l'historique ; aucun usage légitime | supprimer |
| 23 | id. 5, 8-9 | `cron` dans le conteneur, en root (**H** pour `USER root`, DL3002, et la forme shell du `CMD`) | majeur | un démon de planification dans un conteneur : pas de journal sur la sortie standard, pas d'arrêt propre, root | tâche ponctuelle (`docker compose run`) planifiée par une minuterie systemd de l'hôte (comme la purge de Legacy-RDV, E19), ou un job planifié de la plateforme |
| 24 | `sauvegarde.sh` 3-5 | mots de passe et clés dans le script (non détecté) | bloquant | secrets dans le dépôt et dans l'image | variables d'environnement venant de secrets ; `PGPASSFILE` |
| 25 | id. 7 | `--no-verify-ssl` (non détecté) | bloquant | sauvegardes de données de santé envoyées à quiconque répond à ce nom | racine MédiSphère (`AWS_CA_BUNDLE`) |
| 26 | id. 6-9 | `pg_dump` vers `/tmp` sans compression ni chiffrement, même nom chaque nuit, pas de contrôle (non détecté) | majeur | la sauvegarde d'hier est écrasée ; aucune alerte en cas d'échec (`echo "sauvegarde OK"` quoi qu'il arrive) | `set -euo pipefail`, nom daté, chiffrement, code de sortie surveillé — et la méthode du M12-E29 |
| 27 | `compose.yaml` 1 | `version: "3.8"` (non détecté) | mineur | attribut obsolète (avertissement de Compose v5) | supprimer |
| 28 | id. 5, 15 | `postgres:latest`, `valkey/valkey` sans étiquette | majeur | PostgreSQL 19 au prochain `pull` : données illisibles | `postgres:18-trixie`, `valkey/valkey:8-trixie`, noms complets |
| 29 | id. 7 | mot de passe de la base en clair dans `environment:` | bloquant | dépôt, `docker inspect` | `POSTGRES_PASSWORD_FILE` + secret (M12-E08) |
| 30 | id. 10, 17 | `5432:5432` et `6379:6379` publiés sur toutes les adresses | bloquant | base et cache joignables depuis le VLAN, Valkey sans mot de passe | aucun port publié ; réseau interne (M12-E08) |
| 31 | id. 12 | `/srv/donnees/pg:/var/lib/postgresql/data` | majeur | PostgreSQL 18 range ses données sous `/var/lib/postgresql/18/docker` ; montage lié sur un dossier de l'hôte aux droits incertains | volume nommé sur `/var/lib/postgresql` |
| 32 | id. 23-25 | `depends_on` sans condition, pas de sondes, pas de migrations | majeur | l'API démarre avant que la base n'accepte les connexions | sondes et `condition: service_healthy` / `service_completed_successfully` |
| 33 | id. 22 | `80:80` | majeur | port privilégié ; l'application écoute sur 8000 | `8000:8000` |
| 34 | id. 30-31 | `network_mode: host` et `privileged: true` pour MédiDoc | bloquant | plus d'isolation réseau, toutes les capacités et tous les périphériques de l'hôte : root sur `ctr01` | rien de tout cela : réseau défini, aucune capacité |
| 35 | id. 39-45 | Portainer avec `/var/run/docker.sock` monté, `latest`, publié sur 9000 | bloquant | quiconque joint le port 9000 (ou exploite Portainer) pilote le démon, donc est root sur `ctr01` ; règle 3 du module | supprimer ; besoin de visibilité de l'équipe : supervision (M12-E28), journaux (M22) |
| 36 | id. 26, 35, 45 | `restart: always` partout, y compris sur la sauvegarde | mineur | une tâche qui échoue au démarrage boucle sans fin ; `always` relance même après un arrêt volontaire au redémarrage du démon | `unless-stopped` pour les services, aucun pour les tâches ponctuelles |

*Les trois règles à retenir, pour Lucas.* 1) Aucun secret dans un Dockerfile, un `compose.yaml`, un script ou une commande : un secret écrit une fois est compromis pour toujours (on le change). 2) Rien de privilégié : ni `privileged`, ni socket du démon, ni `network_mode: host`, ni root dans le conteneur ; chaque exception s'écrit et se justifie. 3) Tout ce qui est construit doit pouvoir être reconstruit à l'identique : images désignées par nom complet, étiquette et empreinte, versions figées, rien téléchargé sans vérification. Ces règles sont dans l'introduction du module (« Règles du module ») et seront dans les normes de MédiSphère (M12-E33).

**Grille** : 1 point par défaut correctement identifié **et** expliqué (24 points pour les 24 premiers trouvés, au-delà en bonus) ; 2 points de plus par défaut bloquant correctement classé ; une revue sans correction proposée vaut la moitié.

**Pièges classiques**
- S'arrêter à la sortie de Hadolint : la moitié des défauts bloquants lui échappent (secrets aux noms anodins, socket monté, privilège, publication de la base).
- Corriger le Dockerfile sans faire **changer** les secrets : ils sont dans l'historique de la branche (et dans les images déjà construites).
- Une revue sans hiérarchie : trente commentaires au même niveau, et Lucas corrige d'abord `MAINTAINER`.
- Le ton : une revue qui humilie ne sert à rien ; on explique le risque concret et on propose la correction.

---

### M12-E23 — Runbook : un conteneur redémarre en boucle

**Modèle** : [`RB-120-conteneur-redemarre-en-boucle.md`](fichiers/M12-E23/medisphere/docs/conteneurs/runbooks/RB-120-conteneur-redemarre-en-boucle.md).

**Points d'évaluation**
- **Constater** sans détruire : `docker inspect` (statut, code, `OOMKilled`, `RestartCount`, politique, dates, erreur), `docker events --filter container=…`, `docker logs --tail --timestamps` ; côté Quadlet, `systemctl --user status`, `journalctl --user -u`, `podman inspect` — avec la session du compte `app` (et pas `sudo -u app` sans bus).
- **Codes de sortie** : 0 (le processus a fini : pas un service, ou un démon qui passe en arrière-plan), 1-2 (refus de l'application, souvent la configuration), 126/127 (commande), 137 (SIGKILL : OOM, délai de grâce, sonde qui tue), 143 (SIGTERM), 139 (segmentation).
- **Familles de causes** avec, pour chacune, l'indice et la commande qui tranche : configuration, dépendance, ressources, sonde, image, hôte.
- **Geler** : `docker update --restart no` + `docker stop` (le conteneur et ses journaux restent lisibles) ; côté systemd, `systemctl --user stop` (les traces restent dans le journal). Retour à la normale écrit.
- **Interdits** : `docker rm -f`, `down -v`, `system prune`, `podman system reset`, `exec` pour « réparer à chaud », désactiver la politique de redémarrage d'un service avec données sans le geler.
- **Vérifier** : critère mesurable (`RestartCount` stable 5 min, sonde `healthy`, URL de disponibilité depuis `adm01`, sonde de supervision verte).
- **Escalader** avec les informations utiles (code, journaux, version d'image, état de l'hôte).
- Section **« tué sans prévenir »** (OOM, plafond de processus, délai de grâce, `HealthOnFailure=kill`) : M12-E35 ajoute ensuite la section « s'arrête dès le démarrage ».

Essai sur `m12-e23-boucle` : code 3, `RestartCount` qui monte avec des intervalles qui doublent ; l'astreinte doit conclure « refus de l'application (code < 126), lire les journaux » en moins de 5 minutes avec le runbook seul. Ce qui manque le plus souvent au premier jet : la commande Podman équivalente, le critère de fin, et la façon de geler sans perdre les journaux.

**Pièges classiques**
- Un runbook qui explique au lieu d'ordonner : à 3 h du matin, on suit des étapes.
- Des commandes « à adapter » sans dire quoi adapter (`<NOM>`, `<UNITÉ>` explicites).
- Oublier Podman et systemd (« start request repeated too quickly » : `systemctl --user reset-failed` après correction).
- Ne pas dire quand **arrêter** de chercher et escalader.

**En production chez MédiSphère**

RB-120 est cité par les alertes de `ms-verif-conteneurs` (M12-E28) ; chaque post-mortem qui touche un conteneur vérifie s'il faut le compléter ; au M14, un RB-14x en reprend la logique pour les pods (`CrashLoopBackOff`).
