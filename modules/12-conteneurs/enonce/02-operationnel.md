# Module 12 — Palier 2 : Opérationnel

Le palier 1 a monté les hôtes et fait pratiquer les gestes de base : MédiAgenda a une première image, mono-étape et lourde, et une pile Compose sur `ctr01`. Ce palier traite les demandes courantes d'une équipe Plateforme qui livre en conteneurs : des images **minimales** (multi-étapes, *distroless*), des constructions **rapides et reproductibles** (cache, secrets et montages de BuildKit), **multi-architectures**, construites aussi **sans démon** (Buildah) ; des conteneurs **gérés par systemd** (pods et Quadlet) ; un **registre** pour ranger les images ; la **qualité** mesurée (Hadolint, Dive) ; les deux applications qui restent à conteneuriser, MédiNotif (arrêt propre) et Legacy-RDV (le monolithe d'InfoGér) ; les **journaux, limites et sondes** ; enfin la CI : un runner du socle à exécuteur Docker, `runner02`, et un gabarit qui construit et publie les images **sans mode privilégié**. Tu termines en relisant le travail de Lucas et en écrivant le runbook que Nadia attend.

> **Rappels du module** (introduction) : une VM, c'est OpenTofu (`envs/m12` pour les hôtes du module, état `socle` pour `runner02`) ; une configuration d'hôte, c'est un rôle Ansible de `plateforme/ansible` (rôles du palier 1 `docker_engine`, `podman_hote` **étendus**, jamais réécrits) ; une image, c'est un Dockerfile relu en MR dans le projet de l'application ; tout nouveau flux qui traverse la bordure passe par la matrice (`group_vars/role_routeur/pare_feu.yml`) et `docs/socle/matrice-flux.md` ; tout secret par le Vault `lab`, les fichiers 600 de `~/.config/workbook/` ou les variables protégées et masquées de la CI, et il est inscrit au registre des secrets. Images désignées par leur **nom complet**, jamais `latest`. Les vérifications se lancent depuis `adm01` et ne lancent aucun conteneur.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Hôtes | `ctr01` (Docker 29.8, construit et exécute ; registre de travail à partir de E15), `ctr02` (Podman 5.4, Buildah 1.39, Skopeo 1.18, compte `app`), `ctr03` (Podman 5.8, compte `app`), `runner02` (créé en E20), `adm01` |
| Projets GitLab | `mediagenda/api` (M12-E05) ; `medidoc/medidoc` (E10, groupe `medidoc` à créer) ; `medinotif/worker` (E17, groupe `medinotif`) ; `legacy/legacy-rdv` (E19, groupe `legacy`) ; `plateforme/ci-templates` (gabarit `templates/image.yml`, E21). Julien Petit mainteneur des projets applicatifs, Karim Benali développeur (revues) |
| Copies de travail | sur `adm01` : `~/src/mediagenda-api`, `~/src/medidoc`, `~/src/medinotif-worker`, `~/src/legacy-rdv`, `~/src/ci-templates` ; synchronisées vers `ctr01:~/src/<même nom>/` par `rsync` (sans `.git`, sans `secrets/`), comme en M12-E05 ; sur `ctr02` : `/home/app/src/mediagenda-api` (E13, E14) |
| Images locales (`ctr01`) | `medidoc:1.0.0` (E10), `mediagenda-api:0.2.0` (E11), `medinotif-worker:1.0.0` (E17), `legacy-rdv:2.3.1` (E19) |
| Registre de travail (E15) | `https://ctr01.par1.medisphere.internal:5000` (`registry:3`, TLS step-ca, htpasswd), comptes `plateforme` et `ci` ; images `ctr01.par1.medisphere.internal:5000/<groupe>/<projet>:<version>` : `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv` ; adresse stable de `ctr01` : réservation Kea **10.10.99.121** |
| `runner02` (E20) | VMID 1012, 10.10.20.17, état OpenTofu `socle`, Docker 29.8 + GitLab Runner 19.4, runner `runner02-docker`, étiquettes `docker` et `socle`, exécuteur `docker`, **jamais privilégié** |
| Secrets | `~/.config/workbook/registre-travail.env` (compte `plateforme` : `REGISTRE_UTILISATEUR`, `REGISTRE_MOT_DE_PASSE` ; variable `WB_REGISTRE_ENV` de `lab/lab.env`), `~/.config/workbook/registre-ci.curl` (compte `ci`, format `curl -K`) ; Vault `lab` : `vault_registre_travail_mdp_plateforme`, `vault_registre_travail_mdp_ci`, `vault_gitlab_runner02_jeton` ; CI : variables protégées et masquées `REGISTRE_UTILISATEUR`, `REGISTRE_MOT_DE_PASSE` |
| Ports sur `ctr01` | 5000 registre ; 8000 pile MédiAgenda (M12-E08) ; 8010 MédiDoc d'essai (E10) ; 8090 Legacy-RDV (E19) ; 9100 métriques de MédiNotif (E17) ; 8080-8081 déjà pris (M12-E03, E07) |
| Brouillons | `~/m12/eXX/` sur `adm01` et sur les hôtes (non versionnés, sans secret) |
| Documentation | `docs/conteneurs/` de `plateforme/medisphere` : `registre-travail.md` (E15), `qualite-images.md` (E16), `journaux.md` (E18), `legacy-rdv-12-facteurs.md` (E19), `construction-ci.md` (E21), `runbooks/RB-120-…` (E23) ; `docs/socle/` : matrice des flux, inventaire, registre des secrets |

Durée indicative du palier : 22 à 28 heures. Ordre conseillé :

```
E10 ─ E11 ─ E12 ─ E15 ─┬─ E13 ─ E14
                       ├─ E16
                       └─ E20 ─ E21
E17, E18 (après E11)
E19 (quand tu veux après E15 ; c'est le plus long)
E22, E23 (en fin de palier)
```

E15 (le registre) passe avant E13 : la dernière partie de E13 copie des images vers lui, et tout le reste du module y range les images.

---

### M12-E10 — Multi-étapes et image minimale pour MédiDoc  `LAB` `★★`

> **Ticket DEV-1310** — *De : Julien Petit* — *Copie : Sophie Laurent*
> L'équipe MédiDoc copie toujours son binaire Go à la main sur une VM. Je voudrais une image, mais pas comme la première de MédiAgenda : 370 Mo pour une API, c'est un compilateur, un shell et des centaines de paquets livrés en production. Sophie veut une image où il n'y a **rien** d'autre que le service : pas de shell, pas de gestionnaire de paquets, pas root. Objectif affiché : moins de 30 Mo. Crée le projet `medidoc/medidoc` au passage, comme pour MédiAgenda.

**Objectifs pédagogiques**
- Écrire un Dockerfile **multi-étapes** : compiler dans une image complète, livrer dans une image minimale.
- Produire un binaire Go **statique** et comprendre pourquoi il est indispensable sur une base *distroless* ou `scratch`.
- Comparer *distroless* et `scratch` : ce que chacune apporte, ce qu'il faut ajouter soi-même.

**Prérequis** : M12-E04 (empreintes), M12-E05 (premier Dockerfile, projet GitLab de l'application).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | `medidoc/medidoc` : groupe `medidoc` à créer (visibilité privée, comme `mediagenda`), contenu initial = `apps/medidoc/` du workbook ; même réglage que `mediagenda/api` (M12-E05) |
| Application | voir le [README de MédiDoc](../../../apps/medidoc/README.md) : Go 1.26, port 8080, `/healthz` (vivacité, sans S3), `/readyz` (disponibilité, `HeadBucket`), version fixée par `-ldflags "-X main.version=…"`, arrêt propre en 20 s ; sans `MEDIDOC_S3_ENDPOINT` et `MEDIDOC_S3_BUCKET`, le processus s'arrête |
| Images de base | `docker.io/library/golang:1.26-trixie` (compilation), `gcr.io/distroless/static-debian13:nonroot` (exécution) ; `scratch` en comparaison ; toutes désignées par étiquette **et** empreinte d'index (M12-E04) |
| Image | `medidoc:1.0.0` sur `ctr01` ; conteneur d'essai `m12-e10-doc`, port **8010** de `ctr01` |

**Travail demandé**

1. Crée le groupe `medidoc` et le projet `medidoc/medidoc`, pousse `apps/medidoc/` en premier commit, protège `main`, ajoute `julien.petit` (mainteneur) et `karim.benali` (développeur). Sur `adm01`, vérifie que les tests passent (`go vet ./... && go test ./...`).
2. Lis la page « Multi-stage builds » de la documentation Docker et le README de `distroless` (dépôt `GoogleContainerTools/distroless`). Note dans `~/m12/e10/notes.md` : que contient `static-debian13` ? que change le suffixe `:nonroot` ? pourquoi un binaire lié dynamiquement à la glibc ne démarrerait-il pas dessus ?
3. Sur une branche `feat/dockerfile`, écris un `Dockerfile` en deux étapes et un `.dockerignore`. Exigences (Karim relit exactement celles-ci) :
   - étape de compilation sur `golang:1.26-trixie`, dépendances téléchargées et **vérifiées** contre `go.sum` dans une couche qui ne dépend que de `go.mod` et `go.sum` ;
   - binaire statique, sans chemins de la machine de construction, version passée par `--build-arg VERSION=…` ;
   - image finale `static-debian13:nonroot`, qui ne reçoit **que** le binaire ;
   - utilisateur numérique non root, port 8080 documenté, commande en forme exec ;
   - étiquettes OCI `org.opencontainers.image.title`, `version`, `source`, `vendor` ;
   - `.dockerignore` en **liste blanche** : n'entre dans le contexte que ce qui sert à compiler (ni tests, ni `.git`).
4. Synchronise vers `ctr01` et construis `medidoc:1.0.0`. Compare les tailles :
   ```
   admin@ctr01:~$ docker image ls medidoc
   admin@ctr01:~$ docker save medidoc:1.0.0 | wc -c
   admin@ctr01:~$ docker image ls docker.io/library/golang:1.26-trixie
   ```
   Que mesure chacun de ces nombres ? Lequel est transféré sur le réseau à chaque déploiement ?
5. Vérifie ce qu'il y a (et ce qu'il n'y a pas) dans l'image :
   ```
   admin@ctr01:~$ docker image inspect medidoc:1.0.0 --format '{{.Config.User}} {{json .Config.Entrypoint}} {{json .Config.Labels}}'
   admin@ctr01:~$ docker image history medidoc:1.0.0
   admin@ctr01:~$ docker run --rm --entrypoint sh medidoc:1.0.0 -c id; echo "code=$?"
   ```
   Lance ensuite `m12-e10-doc`, publié sur le port 8010, avec un point d'accès S3 **fictif** (`MEDIDOC_S3_ENDPOINT=https://s3.invalid`, `MEDIDOC_S3_BUCKET=essai` ; aucun identifiant) ; depuis `adm01`, interroge `/healthz` puis `/readyz`. Explique les deux réponses.
6. Écris `Dockerfile.scratch`, la même image sur `scratch`. Qu'as-tu dû ajouter que `distroless` fournissait ? Construis-la (`medidoc:1.0.0-scratch`) et compare tailles et couches. Que se passerait-il, sur `scratch`, au premier appel HTTPS vers S3 si tu avais oublié un de ces ajouts ?
7. Mesure l'arrêt de `m12-e10-doc` (`time docker stop`) et lis ses journaux. Relance-le ensuite : la vérification le cherche.
8. MR (exigences, tailles mesurées, décision distroless ou scratch argumentée en trois lignes), relecture de `karim.benali`, fusion. Supprime l'image `medidoc:1.0.0-scratch`.

**Critères de réussite**
- [ ] `medidoc/medidoc` existe ; `main` contient le code, un `Dockerfile` à deux étapes au moins dont la dernière part d'une image *distroless* ou de `scratch`, et un `.dockerignore`.
- [ ] L'image `medidoc:1.0.0` existe sur `ctr01` : utilisateur numérique non root, commande en forme exec, étiquettes OCI, moins de 30 Mo dans l'archive de `docker save`.
- [ ] `m12-e10-doc` tourne, son image n'a pas de shell, et `/healthz` répond la version `1.0.0` depuis `adm01` sur le port 8010.

**Vérification** : `lab/bin/check 12 10`

<details><summary>Indice 1</summary>

`COPY --from=<étape>` copie un fichier d'une étape précédente ; seule la **dernière** étape devient l'image. Pour le binaire : la variable d'environnement `CGO_ENABLED` de Go, et les options `-trimpath` et `-ldflags` de `go build` (README de MédiDoc, section « Compiler et lancer »).
</details>

<details><summary>Indice 2</summary>

Un `.dockerignore` en liste blanche commence par `*`, puis réautorise ce qu'il faut avec `!`. Les fichiers de test Go se reconnaissent à leur suffixe. Sur `scratch`, il n'y a ni `/etc/passwd`, ni magasin de certificats : regarde où la bibliothèque standard de Go cherche les autorités racines sous Linux.
</details>

**Pour aller plus loin** (facultatif) : `docker scout` n'est pas utilisé chez MédiSphère (service en ligne) ; compare plutôt, au module 13, le nombre de vulnérabilités que Trivy trouve dans `golang:1.26-trixie`, `medidoc:1.0.0` et `medidoc:1.0.0-scratch`.

---

### M12-E11 — BuildKit : cache, secrets de construction, montages  `LAB` `★★★`

> **Ticket PLAT-1311** — *De : Karim Benali*
> La nouvelle image de MédiDoc est propre ; celle de MédiAgenda ne l'est pas : un seul étage, `uv` et son cache livrés en production, et chaque changement de dépendance retélécharge tout. Deux autres sujets arrivent : l'équipe de Julien va publier des paquets dans un index Python privé, protégé par un jeton, et Sophie veut qu'on puisse **prouver** qu'une image a été produite à partir d'un commit donné, en la reconstruisant à l'identique. Regarde ce que BuildKit sait faire : montages de cache, secrets, agent SSH, export du cache, horodatages. Version 0.2.0 de MédiAgenda.

**Objectifs pédagogiques**
- Utiliser les montages de BuildKit (`--mount=type=cache`, `bind`, `secret`, `ssh`) et savoir ce qui entre ou non dans une couche.
- Exporter et réimporter le cache de construction.
- Rendre une construction **reproductible** (`SOURCE_DATE_EPOCH`, réécriture des horodatages) et trouver ce qui l'empêche.

**Prérequis** : M12-E05, M12-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Docker 29 construit avec BuildKit (pilote `docker`, stockage containerd) : `docker build` et `docker buildx build` ; la syntaxe des montages est celle du frontal Dockerfile (`# syntax=docker/dockerfile:1`).
- Jeton d'index : **fictif** pour l'instant (aucun index privé n'existe encore) ; uv lit `UV_INDEX_<NOM>_PASSWORD` pour l'index `<nom>` déclaré dans `pyproject.toml`. Range le jeton d'essai dans `~/.config/medisphere/jeton-index` sur `ctr01` (600) ; il ne doit apparaître **ni** dans le Dockerfile, ni dans l'historique, ni dans une couche, ni dans la commande de construction.
- Version de l'image : `mediagenda-api:0.2.0`. Elle doit fonctionner avec le `compose.yaml` de M12-E08 (`MEDIAGENDA_TAG=0.2.0`).
- Dossier de travail sur `ctr01` : `~/m12/e11/` (cache exporté dans `~/m12/e11/cache/`, archives de reproductibilité `~/m12/e11/repro-a.oci.tar` et `repro-b.oci.tar`, essai SSH dans `~/m12/e11/ssh/`).

**Travail demandé**

1. Lis les pages « Optimize cache usage in builds », « Build secrets » et « Reproducible builds » de la documentation Docker, et la page « Using uv in Docker ». Note dans `~/m12/e11/notes.md` la différence entre un montage `cache`, un montage `bind` et un `COPY`, du point de vue des couches.
2. Réécris le Dockerfile de MédiAgenda (branche `feat/buildkit`) en deux étapes : une étape qui fabrique l'environnement virtuel, une étape d'exécution qui ne reçoit que l'environnement virtuel et les migrations. Exigences :
   - images de base et image d'uv désignées par étiquette **et** empreinte ;
   - cache d'uv dans un montage de cache ; `pyproject.toml` et `uv.lock` montés (pas copiés) pour l'installation des dépendances ;
   - le jeton d'index lu dans un **secret** de construction, facultatif (la construction passe sans lui) ;
   - ni `uv`, ni son cache, ni les sources du projet dans l'image finale ; utilisateur 10001 ; `MEDIAGENDA_VERSION` et étiquettes OCI à partir de `VERSION` ;
   - le Dockerfile doit aussi se construire avec Buildah 1.39 (M12-E13) : n'utilise pas d'option de secret propre aux versions récentes de BuildKit sans l'avoir vérifiée.
3. Construis `mediagenda-api:0.2.0` en passant le secret par fichier. Prouve ensuite que le jeton n'est nulle part : `docker image history --no-trunc`, `docker image inspect`, et une recherche dans les couches de l'image (`docker save` puis `tar`). Compare la taille avec `0.1.0`.
4. Le cache. Modifie une dépendance de développement seulement (une ligne vide dans `pyproject.toml` suffit pour la démonstration), reconstruis : quelles étapes repartent, et combien de temps prend le téléchargement grâce au montage de cache ? Puis purge le cache de construction (`docker builder prune`) et reconstruis en important un cache exporté :
   ```
   admin@ctr01:~/src/mediagenda-api$ docker buildx build --build-arg VERSION=0.2.0 \
       --cache-to type=local,dest=$HOME/m12/e11/cache,mode=max -t mediagenda-api:0.2.0 .
   admin@ctr01:~$ docker builder prune -af
   admin@ctr01:~/src/mediagenda-api$ docker buildx build --build-arg VERSION=0.2.0 \
       --cache-from type=local,src=$HOME/m12/e11/cache -t mediagenda-api:0.2.0 .
   ```
   Que contient `~/m12/e11/cache/` ? Que change `mode=max` ? Quel autre type d'export utiliseras-tu une fois le registre en place (E15, E21) ?
   > ⚠️ **Attention** : `docker builder prune -af` vide **tout** le cache de construction de `ctr01`, y compris celui d'autres essais en cours. Sans danger pour les images et les conteneurs.
5. La reproductibilité, d'abord sur MédiDoc : construis deux fois de suite, **sans cache**, l'image de E10 en archive OCI, avec la date du dernier commit comme `SOURCE_DATE_EPOCH` et la réécriture des horodatages des couches :
   ```
   admin@ctr01:~/src/medidoc$ docker buildx build --no-cache --provenance=false --build-arg VERSION=1.0.0 \
       --build-arg SOURCE_DATE_EPOCH=<DATE-DU-COMMIT> \
       --output type=oci,dest=$HOME/m12/e11/repro-a.oci.tar,rewrite-timestamp=true .
   ```
   (`<DATE-DU-COMMIT>` : `git log -1 --format=%ct` sur `adm01`, la copie de `ctr01` n'a pas de `.git`.) Recommence vers `repro-b.oci.tar` et compare les empreintes des deux index (`tar -xOf … index.json`). Refais l'essai sans `SOURCE_DATE_EPOCH` : que constates-tu ?
6. Même essai sur MédiAgenda 0.2.0. Si les deux empreintes diffèrent, **trouve le fichier responsable** : compare les couches des deux archives une à une, extrais la première qui diffère et compare les fichiers. Corrige le Dockerfile pour que deux constructions donnent la même empreinte, et garde les deux archives MédiAgenda sous `repro-a.oci.tar` et `repro-b.oci.tar` (elles remplacent celles de MédiDoc).
7. L'agent SSH : dans `~/m12/e11/ssh/`, écris un petit Dockerfile d'essai dont une instruction `RUN` liste les clés de l'agent SSH du client (`ssh-add -l`) grâce à un montage `ssh`, et une instruction suivante prouve que l'agent n'est plus là. Utilise une clé **jetable** créée pour l'occasion, chargée dans un agent lancé pour l'occasion sur `ctr01`. Construis avec et sans `--ssh default` : quels messages ?
   > ⚠️ **Attention** : ne transfère jamais ton agent personnel (`ssh -A`) vers un hôte partagé pour cet essai : quiconque est root sur `ctr01` pourrait s'en servir le temps de ta session.
8. MR (Dockerfile, `.dockerignore`), relecture de Karim, fusion. Démarre la pile de M12-E08 avec l'image 0.2.0 (`MEDIAGENDA_TAG=0.2.0 docker compose up -d --wait`) et vérifie `/sante` depuis `adm01`.

**Critères de réussite**
- [ ] Le `Dockerfile` de `main` (`mediagenda/api`) a deux étapes au moins, un montage de cache, un montage de secret, et ni `ARG` ni `ENV` porteur d'un jeton ou d'un mot de passe.
- [ ] L'image `mediagenda-api:0.2.0` existe sur `ctr01` (utilisateur 10001, version 0.2.0) et ne contient pas `uv` ; la pile `mediagenda` de `ctr01` tourne avec elle et `/sante` répond `0.2.0`.
- [ ] `~/m12/e11/cache/` contient un cache exporté (disposition OCI) ; `repro-a.oci.tar` et `repro-b.oci.tar` ont la même empreinte d'index.

**Vérification** : `lab/bin/check 12 11`

<details><summary>Indice 1</summary>

Un montage n'est présent que **pendant** l'instruction `RUN` qui le déclare : c'est ce qui le distingue d'un `COPY`. Un secret arrive par défaut sous `/run/secrets/<id>`. Vérifie dans la référence du Dockerfile quelles options de `--mount=type=secret` existent, et dans les notes de version lesquelles sont récentes.
</details>

<details><summary>Indice 2</summary>

Pour comparer deux archives OCI : `index.json` → l'empreinte du manifeste (ou de l'index) → le manifeste (un fichier sous `blobs/sha256/`) → la liste ordonnée des couches. `diff` des deux listes donne la première couche qui change ; `tar -xzf` de chacune dans deux dossiers et `diff -rq` donnent le fichier. Un outil peut écrire dans ce qu'il installe une date que ni `SOURCE_DATE_EPOCH` ni `touch` ne gouvernent.
</details>

<details><summary>Indice 3</summary>

Le fichier responsable est dans le `*.dist-info` du projet installé dans le venv. Lis la documentation d'uv sur ce fichier ; tu peux aussi le retirer après l'installation, à condition de retirer sa ligne de la liste des fichiers installés (`RECORD`), qui porte son empreinte.
</details>

**Pour aller plus loin** (facultatif) : `docker buildx build --provenance=mode=max` produit une attestation de provenance (SLSA) rangée dans l'index ; lis-la avec `docker buildx imagetools inspect --format '{{json .Provenance}}'` une fois l'image poussée (E15). Le module 13 la signe.

---

### M12-E12 — Images multi-architectures avec Buildx  `LAB` `★★★`

> **Ticket DEV-1312** — *De : Julien Petit* — *Copie : Claire Morel*
> Deux nouvelles : le prestataire de téléconsultation nous prête des serveurs ARM (Ampere) pour un essai de performances, et la moitié de mon équipe est passée sur des portables Apple M. Il nous faut MédiAgenda et MédiDoc en `amd64` **et** `arm64`, sous la même étiquette, sans maintenir deux Dockerfiles. Le registre n'est pas encore là : fais-moi des archives, on les poussera quand il existera.

**Objectifs pédagogiques**
- Produire un **index** multi-plateformes avec Buildx et le lire.
- Choisir entre **émulation** (QEMU, binfmt_misc) et **compilation croisée** selon le langage, et mesurer la différence.
- Utiliser un constructeur `docker-container` et savoir ce qu'il change par rapport au pilote `docker`.

**Prérequis** : M12-E04 (index et manifestes), M12-E10, M12-E11.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Émulation : QEMU en mode utilisateur, enregistré dans `binfmt_misc` par le paquet Debian **`qemu-user-binfmt`** (il tire `qemu-user`), installé sur `ctr01` par une extension du rôle `docker_engine` (variable `docker_engine_emulation`, désactivée par défaut, activée dans `host_vars/ctr01/`). Pas de conteneur privilégié pour l'installer.
- Constructeur : `multiarch`, pilote `docker-container`, image `docker.io/moby/buildkit:v0.34.0` désignée par son empreinte (BuildKit 0.34, PLAN §6).
- Archives produites (sur `ctr01`) : `~/m12/e12/medidoc-1.0.0.oci.tar` et `~/m12/e12/mediagenda-api-0.2.0.oci.tar`, chacune un index `linux/amd64` + `linux/arm64`. E15 les poussera.

**Travail demandé**

1. Lis la page « Multi-platform builds » de la documentation Docker. Note les trois stratégies qu'elle décrit et, pour chacune, ce qu'elle demande au constructeur.
2. Étends le rôle `docker_engine` : un fichier de tâches (importé seulement si `docker_engine_emulation` est vrai) installe l'émulation et **vérifie** que l'architecture `aarch64` est enregistrée et active, avec le drapeau qui la rend utilisable depuis un conteneur. MR, application sur `ctr01`. Lis `/proc/sys/fs/binfmt_misc/qemu-aarch64` : que signifie chaque drapeau ? Puis :
   ```
   admin@ctr01:~$ docker run --rm --platform linux/arm64 docker.io/library/debian:trixie-slim uname -m
   ```
3. Crée le constructeur `multiarch` :
   ```
   admin@ctr01:~$ docker buildx create --name multiarch --driver docker-container \
       --driver-opt image=docker.io/moby/buildkit:v0.34.0@sha256:<EMPREINTE>
   admin@ctr01:~$ docker buildx inspect --bootstrap multiarch
   admin@ctr01:~$ docker ps --filter name=buildx_buildkit_multiarch --format '{{.Names}} {{.Image}}'
   ```
   Quelles plateformes annonce-t-il ? Ce constructeur est-il un conteneur privilégié (`docker inspect`) ? Note-le : c'est une des raisons pour lesquelles la CI (E21) n'utilisera pas ce pilote.
4. MédiDoc par **compilation croisée** : réécris son Dockerfile (MR) pour que l'étape de compilation tourne sur la plateforme de la machine qui construit et que Go produise le binaire de la plateforme cible. Construis l'archive :
   ```
   admin@ctr01:~/src/medidoc$ time docker buildx build --builder multiarch --platform linux/amd64,linux/arm64 \
       --build-arg VERSION=1.0.0 --output type=oci,dest=$HOME/m12/e12/medidoc-1.0.0.oci.tar,name=medidoc:1.0.0 .
   ```
5. MédiAgenda par **émulation** : construis l'archive `mediagenda-api-0.2.0.oci.tar` des deux plateformes avec le Dockerfile de E11, sans le modifier. Mesure la durée. Pourquoi la partie `arm64` est-elle si lente, et quelles instructions en sont la cause ?
6. Lis les deux index sans les charger dans Docker : `index.json` de l'archive, puis l'index qu'il désigne (sous `blobs/sha256/`). Combien d'entrées ? Que sont les entrées `unknown/unknown` ? Vérifie l'architecture du binaire `arm64` de MédiDoc (extrais sa dernière couche et passe le binaire à `file`).
7. Compare avec le pilote `docker` par défaut : refais la construction de MédiDoc sans `--builder multiarch`. Fonctionne-t-elle ? Qu'est-ce que le stockage containerd de Docker 29 a changé (M12-E03) ? Note dans `~/m12/e12/notes.md` quand le pilote `docker-container` reste utile.
8. Ouvre les MR (rôle, Dockerfile de MédiDoc) et fais-les relire.

**Critères de réussite**
- [ ] Sur `ctr01`, l'émulation `aarch64` est active avec le drapeau `F`, installée par le rôle `docker_engine` (`main` de `plateforme/ansible`).
- [ ] Le constructeur `multiarch` (pilote `docker-container`) existe pour `admin` sur `ctr01`.
- [ ] `~/m12/e12/medidoc-1.0.0.oci.tar` et `~/m12/e12/mediagenda-api-0.2.0.oci.tar` contiennent chacune un index avec `linux/amd64` et `linux/arm64`.
- [ ] Le Dockerfile de `main` (`medidoc/medidoc`) compile sur `$BUILDPLATFORM` pour `$TARGETARCH`.

**Vérification** : `lab/bin/check 12 12`

<details><summary>Indice 1</summary>

BuildKit fournit des arguments automatiques (`BUILDPLATFORM`, `TARGETPLATFORM`, `TARGETOS`, `TARGETARCH`…) ; ils doivent être **déclarés** (`ARG`) dans l'étape qui s'en sert. `FROM --platform=…` choisit la plateforme d'une étape. Go sait compiler pour une autre architecture avec deux variables d'environnement.
</details>

<details><summary>Indice 2</summary>

Dans `/proc/sys/fs/binfmt_misc/`, le drapeau `F` (*fix binary*) fait ouvrir l'interpréteur par le noyau au moment de l'enregistrement : sans lui, il faudrait que `/usr/libexec/qemu-binfmt/…` existe **dans** chaque conteneur. Le module systemd qui lit `/usr/lib/binfmt.d/` s'appelle `systemd-binfmt`.
</details>

**Pour aller plus loin** (facultatif) : un constructeur Buildx peut avoir plusieurs nœuds (`docker buildx create --append`), dont un nœud `arm64` natif joint par SSH : chaque plateforme est alors construite sans émulation. Quand `arm64` deviendra une cible de production, ce sera à étudier pour `runner02`.

---

### M12-E13 — Buildah et Skopeo : construire sans démon, copier entre registres  `LAB` `★★`

> **Ticket PLAT-1313** — *De : Karim Benali*
> Sur les serveurs Podman, pas de démon Docker, et c'est très bien. Mais il faut savoir y construire et y déplacer des images : Buildah pour construire (avec nos Dockerfiles, ou en script quand il n'y a pas de Dockerfile), Skopeo pour copier une image d'un registre, d'une archive ou d'un stockage local vers un autre, sans la « tirer ». Au passage, je veux un **miroir** de nos images de base dans le registre de travail : le jour où Docker Hub nous limite, on construit quand même.

**Objectifs pédagogiques**
- Construire une image sans démon, sans privilège, avec Buildah : à partir d'un Dockerfile, puis en mode script.
- Copier des images entre transports (`containers-storage`, `oci-archive`, `dir`, `docker`) avec Skopeo, toutes plateformes comprises.
- Synchroniser un ensemble d'images vers un registre (`skopeo sync`).

**Prérequis** : M12-E06 (Podman sans privilège), M12-E11 (Dockerfile de MédiAgenda), M12-E12 (archives OCI), M12-E15 (registre de travail).
**Durée indicative** : 2 h.

**Contexte technique**
- Tout se passe sur `ctr02` sous le compte `app` (session ouverte par `sudo machinectl shell app@`). Copie de travail de MédiAgenda : `/home/app/src/mediagenda-api`, synchronisée depuis `adm01` vers `admin@ctr02` (`rsync`, comme vers `ctr01`), puis copiée sous `app` par `admin` (`sudo rsync --chown=app:app …`) : `app` n'a ni clé SSH ni accès à GitLab.
- Buildah 1.39 et Skopeo 1.18 (Debian 13), configuration des registres de M12-E02 (`short-name-mode = "enforcing"`).
- Identifiants du registre pour `app` : compte `plateforme`, dans un fichier d'authentification **persistant** `~/.config/containers/auth.json` (600). Le fichier par défaut, sous `$XDG_RUNTIME_DIR`, est vidé à chaque redémarrage.
- Images produites : `localhost/mediagenda-api:0.2.0` et `localhost/m12/diag:1.0` (stockage de `app`) ; miroir : `ctr01.par1.medisphere.internal:5000/miroir/…`.
- Dossier de travail : `~/m12/e13/` (compte `app`).

**Travail demandé**

1. Lis `man buildah-build`, `man buildah-from`, `man buildah-commit`, `man skopeo-copy` et `man skopeo-sync` (sections *TRANSPORTS* et *YAML FILE CONTENT*). Note les transports que tu utiliseras.
2. Construis l'image de MédiAgenda avec Buildah, à partir du Dockerfile de E11 et du secret de construction :
   ```
   app@ctr02:~/src/mediagenda-api$ buildah build --layers --build-arg VERSION=0.2.0 \
       --secret id=jeton_index,src=$HOME/.config/medisphere/jeton-index -t localhost/mediagenda-api:0.2.0 .
   app@ctr02:~$ buildah images; podman images
   ```
   Où l'image est-elle rangée ? Que voient `podman images` et `buildah images` ? Le montage de cache fonctionne-t-il sans démon (reconstruis) ?
3. Mode script : écris `~/m12/e13/construire-diag.sh`, qui fabrique **sans Dockerfile** une image d'outils de diagnostic réseau (`curl`, `dig`, `ip`, `jq`, `nc`) à partir de `debian:trixie-slim` épinglée, avec `buildah from`, `buildah run`, `buildah config` et `buildah commit` : une seule couche ajoutée, cache APT vidé, utilisateur non root numérique, étiquettes OCI, conteneur de travail supprimé même en cas d'erreur. Produis `localhost/m12/diag:1.0` et essaie-la (`podman run --rm localhost/m12/diag:1.0 dig +short git01.par1.medisphere.internal`).
4. Regarde dans le conteneur de travail sans le lancer : `buildah mount` exige ici une étape de plus. Laquelle, et pourquoi (compte sans privilège) ?
5. Les identifiants : connecte `app` au registre de travail avec le compte `plateforme`, dans le fichier persistant, sans que le mot de passe passe en argument. Le mot de passe vient du Vault : fais-le transiter de `adm01` à `ctr02` sans l'écrire dans un fichier ni l'afficher.
6. Skopeo, d'un transport à l'autre (toutes les commandes sous `app`) :
   - de ton stockage local vers une archive OCI : `localhost/mediagenda-api:0.2.0` → `~/m12/e13/mediagenda-api-0.2.0.oci.tar` ;
   - de l'archive multi-plateformes de E12 (copiée depuis `ctr01` dans `~/m12/e13/`) vers le registre, **toutes les plateformes**, sous `…:5000/medidoc/medidoc:1.0.0-essai` ; vérifie avec `skopeo inspect --raw` ;
   - du registre vers un dossier `dir:` : qu'y trouve-t-on ?
   - supprime l'étiquette d'essai du registre avec `skopeo delete` : que se passe-t-il ?
7. Le miroir : écris `~/m12/e13/miroir.yaml` pour `skopeo sync` (source `yaml`) avec les images de base de M12-E04 (`debian:trixie-slim`, `python:3.13-slim-trixie`, `postgres:18-trixie`, `valkey/valkey:8-trixie`), synchronise-les vers `ctr01.par1.medisphere.internal:5000/miroir`, **toutes plateformes**. Liste ensuite ce qui est arrivé dans le registre : sous quels noms ? Les empreintes d'index sont-elles celles de Docker Hub ?
8. Range `construire-diag.sh` et `miroir.yaml` dans `plateforme/outils` (dossier `conteneurs/`, MR).

**Critères de réussite**
- [ ] Sous `app` sur `ctr02` : `localhost/mediagenda-api:0.2.0` (construite par Buildah, utilisateur 10001) et `localhost/m12/diag:1.0` (utilisateur numérique non root) existent ; `~/.config/containers/auth.json` est en 600.
- [ ] Le registre de travail contient `miroir/debian:trixie-slim` et `miroir/python:3.13-slim-trixie`, en `amd64` et `arm64`.
- [ ] `construire-diag.sh` et `miroir.yaml` sont sur `main` de `plateforme/outils`.

**Vérification** : `lab/bin/check 12 13`

<details><summary>Indice 1</summary>

Un compte sans privilège ne peut pas monter un système de fichiers dans l'espace de noms de l'hôte : il faut d'abord entrer dans son espace de noms `user` (la même commande qu'en M12-E06, version Buildah). Pour le script : un `trap … EXIT` garantit le ménage.
</details>

<details><summary>Indice 2</summary>

`podman login` et `skopeo login` lisent le mot de passe sur l'entrée standard avec `--password-stdin`, et écrivent où on le leur dit avec `--authfile`. Une commande `ssh` transmet son entrée standard à la commande distante. Pour les copies : l'option qui copie **toutes** les entrées d'un index est la même pour `skopeo copy` et `skopeo sync`.
</details>

**Pour aller plus loin** (facultatif) : `skopeo copy --preserve-digests` refuse une copie qui changerait l'empreinte ; essaie-la vers un dossier `dir:` en format `v2s2` (`--format v2s2`) : pourquoi échoue-t-elle ?

---

### M12-E14 — Pods Podman et Quadlet : des conteneurs gérés par systemd  `LAB` `★★★`

> **Ticket PLAT-1314** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Sur `ctr02`, les conteneurs de tes essais disparaissent au redémarrage de la VM, et personne ne sait les relancer dans le bon ordre. Je veux la pile MédiAgenda sur `ctr02` comme un **service** : elle démarre avec la machine, dans l'ordre (base, migrations, cache, API), sous le compte `app`, sans root ; je la pilote avec `systemctl` et je lis ses journaux avec `journalctl`, comme le reste. Et un fichier Kubernetes qu'on pourra montrer à l'équipe du M14.

**Objectifs pédagogiques**
- Regrouper des conteneurs dans un **pod** Podman (espace réseau partagé) et en générer une description Kubernetes.
- Décrire des conteneurs, pods, réseaux, volumes et constructions en fichiers **Quadlet**, convertis en unités systemd par le générateur.
- Exploiter des services systemd **utilisateur** (linger, dépendances, journaux) et connaître les écarts entre Podman 5.4 et 5.8.

**Prérequis** : M12-E06 (session `app`, linger), M12-E08 (la pile Compose), M12-E11 (Dockerfile 0.2.0), M12-E13 (construction par Buildah sous `app`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Hôte, compte | `ctr02`, compte `app` (session `sudo machinectl shell app@`) ; fichiers Quadlet dans `~/.config/containers/systemd/` |
| Fichiers attendus | `mediagenda.network`, `mediagenda-pg.volume`, `mediagenda-pg.container`, `mediagenda.pod`, `mediagenda-valkey.container`, `mediagenda-migrations.container`, `mediagenda-api.build`, `mediagenda-api.container` |
| Services générés | `mediagenda-pg.service`, `mediagenda-migrations.service`, `mediagenda-valkey.service`, `mediagenda-api.service`, `mediagenda-pod.service`… (les noms des unités suivent ceux des fichiers : la suite du module s'en sert) |
| Architecture | réseau Podman `mediagenda` ; PostgreSQL 18 **hors** du pod (cycle de vie à part), volume `mediagenda-pg` ; pod `mediagenda` (API + Valkey, qui se parlent par `127.0.0.1`), seul le pod publie le port **8000** de `ctr02` ; image de l'API construite localement par une unité `.build` à partir de `/home/app/src/mediagenda-api` |
| Secrets | secrets Podman `mediagenda-pg-mdp` (mot de passe) et `mediagenda-db-url` (URL complète, qui contient le mot de passe), créés par un petit script `~/m12/e14/creer-secrets.sh` ; jamais dans un fichier Quadlet |
| Versions | Podman 5.4 (Debian 13) : `.pod` et `.build` présents, **`podman quadlet install` absent** ; Podman 5.8 (`ctr03`) : présent |

**Travail demandé**

*A. Le pod à la main*

1. Lis `man podman-pod-create`, `man podman-kube-generate`, `man podman-systemd.unit` (la page de référence de Quadlet). Note quelles clés existent pour les types `.container`, `.pod`, `.network`, `.volume` et `.build` dans **ta** version (`podman version`) : la page de la documentation en ligne décrit la dernière.
2. Crée le pod et ses conteneurs à la main (réseau, volume, base, Valkey et API dans le pod, migrations), avec des secrets Podman créés par ton script : le mot de passe ne doit jamais apparaître à l'écran ni dans un fichier. Vérifie `/pret` depuis `adm01` sur `ctr02:8000`. Compare ce que montrent `podman pod ps`, `podman ps --pod` et `podman inspect mediagenda-api` (où est passé le secret ?).
3. Génère la description Kubernetes du pod dans `~/m12/e14/mediagenda-pod.yaml` et lis-la : qu'est-ce qui manque pour qu'elle soit utilisable ailleurs ? Essaie `podman kube play --replace` sur ce fichier puis `podman kube down`. Supprime ensuite tout ce que tu as créé à la main (pod, conteneurs, réseau), **garde** le volume et les secrets.

*B. Quadlet*

4. Écris les huit fichiers Quadlet du contexte. Exigences :
   - dépendances explicites : les migrations attendent une base **saine**, l'API attend que les migrations aient **réussi** et que Valkey soit saine ; une unité n'est « démarrée » pour systemd que lorsque son conteneur est sain ;
   - sondes de santé (vivacité de l'API sur `/sante`, sans `curl`) ; arrêt propre (délai supérieur aux 20 s de l'API) ;
   - images désignées par leur nom complet ; l'API par l'unité de construction ; aucun mot de passe dans les fichiers ;
   - tout ce qui doit démarrer avec la machine est rattaché à la cible par défaut de la session utilisateur.
5. Avant de démarrer quoi que ce soit, fais lire tes fichiers au générateur sans rien installer :
   ```
   app@ctr02:~$ /usr/libexec/podman/quadlet -dryrun -user
   ```
   Lis la ligne `ExecStart=` produite pour chaque unité. Vérifie en particulier les commandes de tes sondes et les arguments de Valkey : sont-ils transmis exactement comme tu les as écrits ?
6. Charge et démarre :
   ```
   app@ctr02:~$ systemctl --user daemon-reload
   app@ctr02:~$ systemctl --user start mediagenda-api.service
   app@ctr02:~$ systemctl --user list-dependencies mediagenda-api.service
   app@ctr02:~$ journalctl --user -u mediagenda-migrations.service --no-pager
   ```
   Dans quel ordre les unités ont-elles démarré ? Pourquoi `systemctl --user enable mediagenda-api.service` est-il refusé, et qu'est-ce qui le remplace ?
7. Prouve que la pile survit : `sudo systemctl reboot` de `ctr02` (depuis `admin`), puis, **sans ouvrir de session `app`**, vérifie `/pret` depuis `adm01`. Arrête l'API (`systemctl --user stop`) : la base et le cache restent-ils ?
8. Sur `ctr03` (Podman 5.8, compte `app`), installe une unité d'essai `m12-e14-essai.container` (un nginx publié sur le port 8084) avec `podman quadlet install`, liste-la avec `podman quadlet list`, démarre-la. Que fait la commande de plus qu'une copie de fichier ? Note dans `docs/conteneurs/hotes.md` (M12-E02) l'écart de version et sa conséquence pour le rôle Ansible.
9. Range les fichiers Quadlet et le script de secrets dans `mediagenda/api` (dossier `deploiement/quadlet/`, MR). Le palier 3 les reprendra (E30) et le mini-projet les fera déposer par Ansible.

**Critères de réussite**
- [ ] Sur `ctr02`, sous `app` : `mediagenda-api.service`, `mediagenda-valkey.service` et `mediagenda-pg.service` sont actifs, le pod `mediagenda` tourne, et `/pret` répond 200 depuis `adm01` sur `ctr02:8000`.
- [ ] Les fichiers `.pod`, `.network`, `.volume` et `.build` sont dans `~app/.config/containers/systemd/` ; aucun mot de passe en clair dans ces fichiers ni dans l'environnement des conteneurs vu par `podman inspect`.
- [ ] `~app/m12/e14/mediagenda-pod.yaml` (sur `ctr02`) décrit un `Pod` Kubernetes.
- [ ] Sur `ctr03`, `m12-e14-essai` est installé par `podman quadlet install` et son service est actif.

**Vérification** : `lab/bin/check 12 14`

<details><summary>Indice 1</summary>

Une unité Quadlet en désigne une autre **par son nom de fichier** (`Network=mediagenda.network`, `Pod=mediagenda.pod`, `Image=mediagenda-api.build`, `Volume=mediagenda-pg.volume:/…`) : le générateur en déduit les dépendances. Pour « démarrée quand saine » : une clé de la section `[Container]` change le mode de notification de systemd. Pour une tâche ponctuelle : `Type=` et `RemainAfterExit=` dans `[Service]`.
</details>

<details><summary>Indice 2</summary>

Le générateur ne fait pas toujours ce qu'on croit avec les guillemets et les arguments vides : `-dryrun` le montre. Une sonde peut aussi s'écrire comme un tableau JSON. Une unité générée ne s'active pas (`enable`) : c'est la section `[Install]` du fichier Quadlet qui la rattache à une cible.
</details>

<details><summary>Indice 3</summary>

Un secret Podman de type `env` est injecté au démarrage du conteneur ; compare avec une variable passée par `Environment=`. Si l'API ne joint pas la base, demande-toi sur quel réseau est le **pod**, et donc l'API.
</details>

**Pour aller plus loin** (facultatif) : un fichier `.kube` fait jouer à Quadlet un YAML Kubernetes (`podman kube play`) ; transforme `mediagenda-pod.yaml` en unité `.kube` et compare ce que tu perds (dépendances, secrets).

---

### M12-E15 — Un registre de travail  `LAB` `★★`

> **Ticket PLAT-1315** — *De : Claire Morel* — *Copie : Sophie Laurent*
> Les images vivent sur les disques des machines qui les ont construites, et on les recopie à la main. Harbor arrive au module 13 ; d'ici là, je veux un registre de travail simple sur `ctr01` : en HTTPS avec notre PKI, un compte pour l'équipe et un pour la CI, la suppression possible et le ménage automatique. Sophie : aucun accès anonyme, aucun contournement TLS chez les clients. Et on y range tout ce qu'on a construit jusqu'ici.

**Objectifs pédagogiques**
- Déployer CNCF Distribution 3 (`registry:3`) par un rôle Ansible : TLS par ACME, authentification htpasswd idempotente, suppression, ramasse-miettes.
- Ouvrir les flux de bordure strictement nécessaires (ACME, CI) vers une adresse stable.
- Pousser et lire des images par l'API du registre (OCI Distribution), images multi-plateformes comprises.

**Prérequis** : M12-E02 (rôle `docker_engine`), M06-E18 et M06-E27 (rôle `certificats_acme`, step-ca), M11 (réservations Kea), M07-E24 (matrice des flux), M12-E05, E10, E12.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Logiciel | `docker.io/library/registry:3` (Distribution 3.1), épinglée par empreinte, lancée par Docker Compose depuis `/opt/registre/` sur `ctr01` |
| Rôle Ansible | `registre_travail` (nouveau) + `certificats_acme` (M06) : certificat d'identifiant `registre`, `/etc/registre/tls/registre.crt` et `.key`, renouvelé par `cert-renewer@registre.timer` ; playbook `playbooks/registre-travail.yml` ; variables dans `host_vars/ctr01/` |
| Adresse | `https://ctr01.par1.medisphere.internal:5000` ; `ctr01` reçoit une **réservation Kea 10.10.99.121** (MAC `bc:24:11:99:12:01`, sous-réseau `id: 99`) : les règles de bordure visent une adresse fixe |
| Comptes | htpasswd (bcrypt) : `plateforme` (équipe, vérifications, recette de `ctr02`) et `ci` (pipelines, E20-E21) ; mots de passe générés, Vault `lab` (`vault_registre_travail_mdp_plateforme`, `vault_registre_travail_mdp_ci`) |
| Fichiers de `adm01` | `~/.config/workbook/registre-travail.env` (600) : `REGISTRE_UTILISATEUR=plateforme`, `REGISTRE_MOT_DE_PASSE=…` ; `~/.config/workbook/registre-ci.curl` (600) : `user = "ci:…"` (format `curl -K`) |
| Flux de bordure | `ctr01` → `ca01:443` (ACME) ; `ca01` → `ctr01:80` (défi HTTP-01) ; `adm01` (MGMT) et `ctr02`/`ctr03` (même VLAN) n'en demandent pas |
| Images à pousser | `mediagenda/api:0.1.0` (E05), `mediagenda/api:0.2.0` (archive multi-plateformes de E12), `medidoc/medidoc:1.0.0` (archive de E12) |

**Travail demandé**

1. Lis la page « Configuration » de Distribution (`distribution.github.io/distribution`) : sections `http` (dont `host` et `tls`), `auth.htpasswd`, `storage.delete`, et la page « Garbage collection ». Note pourquoi le ramasse-miettes ne doit pas tourner pendant une poussée, et ce que fait `--delete-untagged`.
2. Réserve 10.10.99.121 pour `ctr01` dans Kea (même méthode que les réservations du M11), applique, renouvelle le bail de `ctr01` et vérifie l'adresse et le DNS.
3. Ajoute à la matrice des flux les deux règles ACME (définition `CTR01`), MR, application, et la matrice documentaire.
4. Écris le rôle `registre_travail`. Exigences :
   - image épinglée par empreinte, conteneur sans privilège (racine en lecture seule sauf le volume de données, aucune capacité, pas d'escalade), sonde de santé ;
   - configuration de Distribution par modèle : TLS (certificat de `certificats_acme`), htpasswd, suppression activée, journaux JSON ;
   - comptes htpasswd **idempotents** : une ligne n'est réécrite que si le mot de passe du Vault ne correspond plus ; aucun mot de passe dans un argument de commande ni dans la sortie d'Ansible ;
   - ramasse-miettes hebdomadaire par une minuterie systemd, registre arrêté pendant l'opération et **toujours** relancé ;
   - un contrôle final : `/v2/` répond 401 sans identifiants, en TLS vérifié contre la racine MédiSphère.
   Écris `playbooks/registre-travail.yml` (garde-fou : `ctr01` seulement) ; MR, application, second passage `changed=0`.
5. Crée les deux fichiers de `~/.config/workbook/`, puis :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://ctr01.par1.medisphere.internal:5000/v2/
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -K ~/.config/workbook/registre-ci.curl https://ctr01.par1.medisphere.internal:5000/v2/
   admin@adm01:~$ openssl s_client -connect ctr01.par1.medisphere.internal:5000 -servername ctr01.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -issuer -enddate
   ```
6. Pousse les images : `mediagenda-api:0.1.0` depuis `ctr01` (`docker login` en compte `plateforme`, puis `docker tag` et `docker push`) ; les deux archives multi-plateformes de E12 depuis `ctr02` (Skopeo, en `admin`, fichier d'authentification **temporaire** effacé ensuite), toutes plateformes, sous `mediagenda/api:0.2.0` et `medidoc/medidoc:1.0.0`. Où `docker login` a-t-il rangé le mot de passe sur `ctr01`, et sous quelle forme ? Supprime-le ensuite (`docker logout`).
7. Lis le registre par son API, depuis `adm01` : catalogue, étiquettes de chaque dépôt, manifeste de `medidoc/medidoc:1.0.0` (avec l'en-tête `Accept` d'un index OCI) et son empreinte (`Docker-Content-Digest`). Compare avec l'empreinte d'index de l'archive de E12 : sont-elles égales ? Pourquoi est-ce important ?
8. Suppression et ménage : pousse une étiquette d'essai (`medidoc/medidoc:essai`), supprime-la par l'API (`DELETE` du manifeste), puis lance le ramasse-miettes **à la main** par le service systemd et lis son journal. L'espace disque a-t-il diminué (`docker system df -v`) ?
9. Écris la fiche `docs/conteneurs/registre-travail.md` (adresse, comptes, nommage des images, gestes courants, rotation d'un mot de passe, limites) et inscris les deux comptes au registre des secrets (emplacements, pas valeurs).

**Critères de réussite**
- [ ] `https://ctr01.par1.medisphere.internal:5000` présente un certificat de la PKI MédiSphère (chaîne vérifiée) et répond 401 sans identifiants ; le compte de `registre-travail.env` est accepté.
- [ ] Le registre contient `mediagenda/api` (0.1.0 et 0.2.0) et `medidoc/medidoc` (1.0.0, index `amd64` + `arm64`) ; la suppression est activée.
- [ ] Sur `ctr01`, le conteneur du registre a une racine en lecture seule et aucune capacité ; `registre-gc.timer` et `cert-renewer@registre.timer` sont actifs ; `ctr01` a l'adresse 10.10.99.121.
- [ ] `~/.config/workbook/registre-travail.env` et `registre-ci.curl` existent sur `adm01` en 600.

**Vérification** : `lab/bin/check 12 15`

<details><summary>Indice 1</summary>

`htpasswd` (paquet `apache2-utils`) sait **vérifier** un mot de passe (`-v`) et lire celui-ci sur l'entrée standard (`-i`) ; le module `command` d'Ansible a un paramètre `stdin`. Pour le ramasse-miettes : un service `Type=oneshot` avec `ExecStartPre=` (arrêt) et une commande qui s'exécute même en cas d'échec de `ExecStart=` (regarde `ExecStopPost=`).
</details>

<details><summary>Indice 2</summary>

Si la poussée d'un client échoue avec une erreur d'authentification alors que la connexion fonctionne, lis les URL des requêtes refusées dans le journal du registre : le registre renvoie au client des adresses de téléversement construites à partir d'un réglage de sa configuration. Pour pousser une archive OCI avec toutes ses plateformes : transport `oci-archive:` de Skopeo, option `--all`.
</details>

**Pour aller plus loin** (facultatif) : Distribution sait servir de cache d'un registre public (`proxy.remoteurl`) ; Harbor le fera au M13 avec des droits et des quotas. Lis la section et dis pourquoi on ne le fait pas ici.

---

### M12-E16 — Hadolint et Dive : la qualité d'une image  `LAB` `★★`

> **Ticket SEC-1316** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Chaque revue de Dockerfile se joue au feeling. Je veux des **règles écrites et outillées** : un analyseur de Dockerfile avec notre configuration, les mêmes règles partout, des dérogations justifiées ligne par ligne, et une mesure de ce que chaque image gaspille. Passe toutes nos images dedans et donne-moi les chiffres ; on fixera les seuils ensemble.

**Objectifs pédagogiques**
- Configurer Hadolint pour une organisation (seuil d'échec, registres de confiance, étiquettes obligatoires, règles relevées) et gérer les dérogations.
- Mesurer l'efficacité d'une image avec Dive et lire ce qui la dégrade.
- Fixer des seuils qui attrapent les vraies erreurs sans bloquer à tort.

**Prérequis** : M12-E05, M12-E10, M12-E11.
**Durée indicative** : 2 h.

**Contexte technique**
- Outils sur `ctr01`, installés par une extension du rôle `docker_engine` (variable `docker_engine_outils_qualite`) : Hadolint **2.15.1** (binaire de la release ; la release ne publie pas d'empreinte, calcule la tienne et note-la dans le rôle, comme pour bats au M02) et Dive **0.13.1** (paquet `.deb` de la release, empreinte publiée dans `dive_0.13.1_checksums.txt`).
- Fichiers de configuration : `.hadolint.yaml` et `.dive-ci` à la racine de chaque projet applicatif ; copie de référence dans `plateforme/ci-templates` (`exemples/`).
- Images à mesurer : `mediagenda-api:0.1.0`, `mediagenda-api:0.2.0`, `medidoc:1.0.0`.

**Travail demandé**

1. Lis le README de Hadolint (sections *Configure*, *Inline ignores*, *Rules*) et celui de Dive (*CI Integration*). Note les règles DL qui correspondent à des exigences déjà posées dans ce module (nom complet de l'image, `latest`, `USER`, forme exec, `pipefail`).
2. Étends le rôle `docker_engine` (fichier de tâches importé seulement si `docker_engine_outils_qualite` est vrai) : téléchargement dans un dossier versionné, empreinte vérifiée **avant** installation, contrôle de la version installée. MR, application sur `ctr01`.
3. Passe Hadolint, sans configuration, sur les Dockerfiles de E05, E10, E11 et sur celui-ci, écrit exprès :
   ```dockerfile
   FROM debian
   RUN apt-get update && apt-get install -y curl
   USER app
   CMD curl -s http://exemple.invalid | sh
   ```
   Classe chaque message : vrai défaut, défaut mineur, faux positif.
4. Écris `.hadolint.yaml` : avertissement = échec ; registres de confiance (Docker Hub, `gcr.io`, `ghcr.io`, le registre de travail) ; les quatre étiquettes OCI de E10 obligatoires ; relève en erreur les règles qui correspondent aux exigences du module ; aucune règle dans `ignored`. Vérifie que les Dockerfiles de E10 et E11 passent et que celui de E05 échoue, et pourquoi.
5. Une dérogation : dans le Dockerfile d'essai de M12-E11 (`~/m12/e11/ssh/`), Hadolint signale l'absence de version sur le paquet `openssh-client`. Écris la dérogation **dans le Dockerfile**, sur la bonne ligne, avec sa raison. Pourquoi est-ce préférable à une règle ignorée globalement ?
6. Dive : lance-le en mode interactif sur `mediagenda-api:0.1.0` et repère la couche la plus lourde et les fichiers « gaspillés ». Puis en mode CI sur les trois images :
   ```
   admin@ctr01:~$ CI=true dive mediagenda-api:0.2.0
   admin@ctr01:~$ dive --ci --ci-config ~/src/mediagenda-api/.dive-ci mediagenda-api:0.1.0
   ```
   Que mesurent `efficiency`, `wastedBytes` et `userWastedPercent` ? D'où viennent les octets perdus de `0.2.0`, alors que tu n'as rien supprimé ?
7. Fixe les seuils dans `.dive-ci` (efficacité minimale, octets perdus, part perdue par nos couches) : ils doivent laisser passer les images de E10 et E11 et faire échouer une image qui laisse le cache APT dans une couche (fais l'essai avec une image construite pour l'occasion). Note tes mesures et tes seuils dans `docs/conteneurs/qualite-images.md`.
8. Ajoute `.hadolint.yaml` et `.dive-ci` à `mediagenda/api` et `medidoc/medidoc` (MR), et leur copie de référence dans `plateforme/ci-templates` (`exemples/`).

**Critères de réussite**
- [ ] Hadolint 2.15.1 et Dive 0.13.1 sont installés sur `ctr01` par le rôle `docker_engine`.
- [ ] `.hadolint.yaml` (seuil `warning`, étiquettes obligatoires) et `.dive-ci` sont sur `main` de `mediagenda/api` et `medidoc/medidoc` ; les Dockerfiles de `main` de ces deux projets passent Hadolint avec cette configuration.
- [ ] `mediagenda-api:0.2.0` passe `dive --ci` avec le `.dive-ci` du projet ; `docs/conteneurs/qualite-images.md` donne les mesures et les seuils.

**Vérification** : `lab/bin/check 12 16`

<details><summary>Indice 1</summary>

Hadolint lit `.hadolint.yaml` dans le répertoire courant, ou le fichier donné par `-c`. Les clés utiles : `failure-threshold`, `trustedRegistries`, `label-schema`, `override` (par niveau). Une dérogation en ligne s'écrit en commentaire juste **avant** l'instruction concernée.
</details>

<details><summary>Indice 2</summary>

Dive compte comme « gaspillé » un fichier présent dans une couche puis modifié ou supprimé par une couche suivante, **y compris dans les couches de l'image de base**. `userWastedPercent` rapporte le gaspillage aux seules couches ajoutées après la base : c'est le seuil qui juge ton travail.
</details>

---

### M12-E17 — Conteneuriser MédiNotif : signaux, PID 1, arrêt propre  `LAB` `★★`

> **Ticket DEV-1317** — *De : Julien Petit* — *Copie : Nadia Roussel*
> MédiNotif envoie les SMS et mails de rappel. Il consomme une file RabbitMQ et n'acquitte un message qu'après l'avoir envoyé. Sur la VM actuelle, chaque redémarrage du service fait partir des SMS en double, parce que le worker est tué au milieu d'un envoi. En conteneur, je veux l'inverse : à l'arrêt, il finit son message, l'acquitte et sort proprement. Prouve-le-moi avec des mesures, pas avec des promesses.

**Objectifs pédagogiques**
- Comprendre ce qui arrive aux signaux dans un conteneur : PID 1, forme exec ou shell, `STOPSIGNAL`, délai de grâce.
- Savoir quand un `init` (`--init`, tini) est nécessaire et quand il ne sert à rien.
- Mesurer un arrêt propre et le rendre vérifiable.

**Prérequis** : M12-E03 (codes de sortie, `docker stop`), M12-E08 (secrets Compose), M12-E11 (Dockerfile Python en deux étapes).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | `medinotif/worker` : groupe `medinotif` à créer, contenu initial = `apps/medinotif/` (même réglage que `mediagenda/api`) |
| Application | [README de MédiNotif](../../../apps/medinotif/README.md) : file RabbitMQ `notifications`, `MEDINOTIF_AMQP_URL` obligatoire, métriques et vivacité sur le port 9100, envoi simulé de `MEDINOTIF_DELAI_ENVOI_MS` ; sur SIGTERM, finit le message en cours, l'acquitte, sort avec le code 0 |
| Image | `medinotif-worker:1.0.0` sur `ctr01`, UID **10002** (distinct de MédiAgenda) |
| Pile de test | `compose.yaml` du projet (nom de projet Compose `medinotif`) : le worker et un RabbitMQ `docker.io/library/rabbitmq:4.1` jetable ; secret `secrets/amqp_mdp` (dossier ignoré par Git) ; métriques publiées sur le port 9100 de `ctr01` ; délai d'envoi simulé de 3 s pour observer l'arrêt |
| Résultat de mesure | `~/m12/e17/arret.txt` sur `ctr01` (durée de l'arrêt, code de sortie, dernières lignes du journal) |

**Travail demandé**

1. Lis la documentation Docker sur `STOPSIGNAL`, la forme exec et la forme shell (`ENTRYPOINT`/`CMD`), `docker run --init`, et le README de tini. Note : qui reçoit le signal envoyé par `docker stop` ? que fait le noyau d'un signal adressé à un PID 1 qui n'a pas installé de gestionnaire ?
2. Crée le groupe et le projet `medinotif/worker` ; sur une branche, écris le Dockerfile (même méthode que E11 : deux étapes, uv, verrou, cache) : utilisateur 10002, port 9100 documenté, sonde de santé intégrée à l'image (sans `curl`), **signal d'arrêt explicite**, commande en forme exec. Construis `medinotif-worker:1.0.0` sur `ctr01`.
3. Écris le `compose.yaml` de test et un script `outils/secrets-compose.sh` (mot de passe tiré au hasard, jamais remplacé, dossier `secrets/` en 700). Exigences : le mot de passe n'apparaît dans l'environnement d'**aucun** conteneur (l'image officielle de RabbitMQ refuse désormais les variables `*_FILE` : vérifie-le, et trouve une autre façon) ; RabbitMQ sur un réseau interne ; délai de grâce du worker supérieur à un envoi ; démarrage conditionné par la santé de RabbitMQ.
4. Démarre la pile (`docker compose up -d --build --wait`), vérifie les métriques depuis `adm01` (`curl -s http://ctr01.par1.medisphere.internal:9100/metrics | grep medinotif_messages_total`) et le PID 1 du worker (`docker exec … cat /proc/1/cmdline`).
5. La mesure : écris `outils/essai-arret.sh` qui publie une notification (avec la bibliothèque AMQP déjà présente dans l'image du worker), attend que le worker la prenne, arrête le conteneur pendant l'envoi et affiche la durée de l'arrêt, le code de sortie et les dernières lignes du journal. Lance-le et garde la sortie dans `~/m12/e17/arret.txt`.
6. Les contre-exemples (dans `~/m12/e17/`, images jetables construites `FROM medinotif-worker:1.0.0`) :
   - `ENTRYPOINT medinotif` (forme shell) : qui est le PID 1 ? durée et code de l'arrêt ? le message est-il perdu, envoyé deux fois ?
   - la même image lancée avec `--init` : qui reçoit le signal, et le worker termine-t-il son message ?
   - le backend `stdin` (`MEDINOTIF_BACKEND=stdin`, `docker run -i`), en forme exec : l'arrêt est-il propre ? Pourquoi ?
   Consigne chaque cas (PID 1, durée, code, message) dans un tableau de `~/m12/e17/notes.md`.
7. MR (Dockerfile, `.dockerignore`, `compose.yaml`, scripts, `.gitignore`), relecture de Julien et Karim, fusion. Laisse la pile `medinotif` démarrée.

**Critères de réussite**
- [ ] `medinotif/worker` existe ; `main` contient un Dockerfile (utilisateur numérique non root, `STOPSIGNAL`, forme exec), un `compose.yaml` et un `.dockerignore`.
- [ ] La pile `medinotif` tourne sur `ctr01` : worker sain, PID 1 = le worker (pas un shell), délai de grâce d'au moins 15 s, métriques joignables depuis `adm01` ; aucun mot de passe dans l'environnement des conteneurs.
- [ ] `~/m12/e17/arret.txt` montre un arrêt en moins de 10 s avec le code de sortie 0 et le message « arrêt terminé ».

**Vérification** : `lab/bin/check 12 17`

<details><summary>Indice 1</summary>

Un script d'entrée de console Python (`/app/.venv/bin/medinotif`) est un fichier avec une ligne `#!` : en forme exec, c'est l'interpréteur Python qui devient le PID 1, sans shell entre lui et le signal. Pour RabbitMQ : la même astuce que pour l'API en M12-E08 (composer la variable au démarrage du processus, à partir du fichier du secret), puis rendre la main au script d'entrée de l'image.
</details>

<details><summary>Indice 2</summary>

`--init` place `docker-init` (tini) en PID 1 ; tini transmet les signaux à **son** enfant direct. Si cet enfant est un shell qui a lancé le worker sans `exec`, qui reçoit SIGTERM, et que devient le worker quand le shell meurt ? Pour le backend `stdin`, lis comment il attend les messages.
</details>

---

### M12-E18 — Journaux, ressources et santé des conteneurs  `LAB` `★★`

> **Ticket PLAT-1318** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Trois questions de l'astreinte, auxquelles personne ne sait répondre aujourd'hui. Où sont les journaux d'un conteneur, combien de place peuvent-ils prendre et combien de temps on les garde ? Qu'est-ce qui empêche un conteneur de manger toute la mémoire de `ctr01` ? Et un conteneur « unhealthy », qui s'en occupe ? Je veux des réglages écrits dans le code et une fiche que je peux lire à 3 h du matin.

**Objectifs pédagogiques**
- Choisir et régler un pilote de journaux (`json-file`, `local`, `journald`), par défaut et par conteneur.
- Poser des limites de mémoire, de CPU et de processus, et observer ce qui se passe quand elles sont atteintes (OOM du cgroup, étranglement CPU).
- Distinguer ce que font Docker et Podman d'un conteneur dont la sonde échoue.

**Prérequis** : M12-E03, M12-E08 (pile Compose), M12-E11 (image 0.2.0), M12-E14 (unités Quadlet).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Journaux par défaut de `ctr01` : `daemon.json` géré par le rôle `docker_engine` (M12-E02 : `json-file`, 10 Mo × 3). Tu y ajoutes la compression des fichiers tournés, par le rôle.
- Pile Compose de `ctr01` (`~/src/mediagenda-api`, image 0.2.0) : le `compose.yaml` de M12-E08 reçoit des limites et des délais d'arrêt (MR dans `mediagenda/api`).
- Conteneurs d'essai sur `ctr01` (gardés jusqu'à la vérification) : `m12-e18-local` (pilote `local`), `m12-e18-journald` (pilote `journald`), `m12-e18-oom` (tué par le noyau), `m12-e18-malade` (sonde qui échoue).
- `ctr02` : l'unité `mediagenda-api.container` de M12-E14 reçoit une action sur échec de la sonde et des limites. Le Quadlet de Podman 5.4 n'a pas toutes les clés de la documentation en ligne : `-dryrun` avant tout.

**Travail demandé**

*A. Journaux*

1. Lis la page « Configure logging drivers » et celles des pilotes `json-file`, `local` et `journald`. Où se trouvent les fichiers de `json-file` d'un conteneur (`docker inspect -f '{{.LogPath}}'`) ? Que se passe-t-il, sans `max-size`, pour un conteneur bavard ?
2. Ajoute la compression des fichiers tournés aux options par défaut (rôle `docker_engine`, MR, application). Une option de `daemon.json` s'applique-t-elle aux conteneurs **déjà créés** ? Vérifie sur `mediagenda-api-1` (`docker inspect -f '{{json .HostConfig.LogConfig}}'`), puis recrée la pile.
3. Lance deux conteneurs bavards (`debian:trixie-slim`, une ligne par seconde) : `m12-e18-local` avec le pilote `local`, `m12-e18-journald` avec le pilote `journald` et une étiquette (`tag`) lisible. Lis leurs journaux avec `docker logs`, puis directement : `journalctl CONTAINER_NAME=m12-e18-journald`, et le dossier de `local`. Note dans `~/m12/e18/notes.md` les avantages et limites de chacun pour un collecteur de journaux (M22).

*B. Ressources*

4. Mesure la pile au repos et sous une petite charge (`docker stats --no-stream` ; une boucle de `curl` sur `/api/v1/creneaux` depuis `adm01`). Choisis des limites (mémoire, CPU, processus) pour `db`, `valkey`, `api` et `migrations`, justifiées par la mesure, et écris-les dans `compose.yaml`. Pour Valkey, fais en sorte que le **cache** évince ses clés avant d'atteindre la limite du conteneur.
5. Ajoute aux services des délais d'arrêt cohérents avec les applications (20 s pour l'API, PostgreSQL qui doit écrire son point de reprise). Vérifie dans `docker inspect` ce que deviennent tes réglages (`HostConfig.Memory`, `NanoCpus`, `PidsLimit`, `Config.StopTimeout`).
6. L'OOM : lance `m12-e18-oom` avec 64 Mo de mémoire au plus et un processus qui en demande davantage (par exemple `python3 -c "b = bytearray(200 * 1024 * 1024)"` dans l'image `python:3.13-slim-trixie`). Lis `docker inspect -f '{{.State.OOMKilled}} {{.State.ExitCode}}'`, `journalctl -k` et le fichier `memory.events` du cgroup du conteneur pendant qu'il existe. Recommence avec `--cpus 0.2` et une boucle infinie : que montre `docker stats`, le conteneur est-il tué ?

*C. Santé*

7. Lance `m12-e18-malade` : un nginx dont la sonde interroge une page qui n'existe pas (intervalle 5 s, 3 essais), avec `--restart unless-stopped`. Au bout d'une minute : quel état ? Docker l'a-t-il redémarré ? Lis `docker inspect -f '{{json .State.Health}}'` et `docker events --filter event=health_status`. Qui devrait agir sur ce conteneur malade, chez MédiSphère, aujourd'hui (M12-E28) et demain (Kubernetes) ?
8. Sur `ctr02`, ajoute à `mediagenda-api.container` une action sur échec de la sonde qui fait relancer le conteneur par systemd, et des limites (mémoire, CPU, processus). Passe le fichier au générateur (`-dryrun`) : quelles clés sont refusées par Podman 5.4, et comment s'en passer ? Recharge, puis rends l'API muette pendant deux minutes **sans toucher** ni à Valkey ni à la base (la sonde de vivacité ne doit pas en dépendre), et observe : que montrent `podman healthcheck run`, `systemctl --user status` et `journalctl --user` ? L'unité revient-elle seule ?
9. Écris `docs/conteneurs/journaux.md` : pilote retenu et pourquoi, rotation, où lire les journaux sur chaque hôte, bornes par défaut des services, ce qui se passe à la limite (mémoire, CPU, processus), qui agit sur un conteneur malade.

**Critères de réussite**
- [ ] `daemon.json` de `ctr01` : `json-file` avec `max-size` et `compress`, posé par le rôle (`main` de `plateforme/ansible`).
- [ ] Pile `mediagenda` de `ctr01` : `api`, `db` et `valkey` ont une limite de mémoire, une limite de processus et un délai d'arrêt ; Valkey a une mémoire maximale et une politique d'éviction ; le `compose.yaml` de `main` les contient.
- [ ] `m12-e18-local` et `m12-e18-journald` utilisent les pilotes `local` et `journald` ; `m12-e18-oom` est arrêté avec `OOMKilled` vrai ; `m12-e18-malade` est `unhealthy`.
- [ ] Sur `ctr02`, `mediagenda-api.container` porte une action sur échec de sonde et une limite de processus ; l'API est saine.

**Vérification** : `lab/bin/check 12 18`

<details><summary>Indice 1</summary>

Compose accepte, au niveau d'un service, `mem_limit`, `cpus`, `pids_limit` et `stop_grace_period` (ou leurs équivalents sous `deploy.resources`). Valkey a ses propres réglages de mémoire maximale et de politique d'éviction, en arguments de `valkey-server`. Le cgroup d'un conteneur Docker est sous `/sys/fs/cgroup/system.slice/docker-<ID>.scope/`.
</details>

<details><summary>Indice 2</summary>

Pour Podman : `man podman-systemd.unit`, clés `HealthOnFailure=`, `PidsLimit=` ; ce que le générateur de 5.4 ne connaît pas passe par `PodmanArgs=` (options de `podman run`). `HealthOnFailure=kill` arrête le conteneur : c'est la politique `Restart=` de la section `[Service]` qui le relance.
</details>

---

### M12-E19 — Conteneuriser Legacy-RDV  `LIBRE` `★★★`

> **Ticket DEV-1319** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel*
> Legacy-RDV tourne depuis 2014 sur une VM qu'InfoGér a montée à la main, et dont tu as fait une copie fidèle (`legacy01`). Il nous reste dix-huit mois avant la fin du contrat, et il ne sera pas réécrit d'ici là. Je veux une image de Legacy-RDV et une pile de recette, sans changer ce que voient les cabinets : mêmes pages, mêmes règles, mêmes données. La configuration doit sortir du code, les journaux doivent aller là où vont ceux des autres applications, et ce qu'on ne peut pas corriger maintenant doit être écrit noir sur blanc. Sophie : le mot de passe de 2014 ne doit plus servir nulle part.

**Objectifs pédagogiques**
- Conteneuriser une application qui n'a pas été écrite pour : repérer ce qui suppose une VM (disque local, `localhost`, cron, fichiers de journaux, droits).
- Appliquer les « 12 facteurs » autant que possible **sans changer le comportement**, et documenter les écarts assumés.
- Migrer des données d'une VM vers des volumes de conteneurs.

**Prérequis** : M12-E02 (`legacy01`), M12-E07, M12-E08, M12-E15, M12-E18 ; le [README de Legacy-RDV](../../../apps/legacy-rdv/README.md), en particulier « Ce qui rend la migration difficile ».
**Durée indicative** : 5 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | `legacy/legacy-rdv` : groupe `legacy` à créer, contenu initial = `apps/legacy-rdv/` |
| Version | `2.3.1` (version d'InfoGér) : image `legacy-rdv:2.3.1` sur `ctr01`, puis `ctr01.par1.medisphere.internal:5000/legacy/legacy-rdv:2.3.1` |
| Pile de recette | `compose.yaml` du projet, sur `ctr01`, application publiée sur le port **8090** ; MariaDB **11.8** (`docker.io/library/mariadb:11.8`), jamais publiée |
| Contraintes de l'image | base officielle `php:8.4-apache-trixie` (même pile que la VM) ; Apache **et** PHP sous un compte non root ; l'application écoute dans le conteneur sur le port 8080 (les modules suivants s'en servent : M12-E25, M12-E46) ; code dans `/var/www/legacy-rdv` comme sur la VM |
| Données | base `legacy_rdv` et pièces jointes de `legacy01` ; ce sont des **données de santé** (fictives ici) : aucun fichier intermédiaire ne traîne après la migration |
| Ce qu'on peut changer | `config.php` (la configuration) et des **ajouts** (page de sonde, fichiers de configuration de l'image) ; rien dans la logique des pages |

**Travail demandé**

Livre, dans `legacy/legacy-rdv` (MR relue par Karim et Claire) :

1. un `Dockerfile` et un `.dockerignore` : image qui passe le `.hadolint.yaml` de MédiSphère (E16), sans le mot de passe d'InfoGér ni aucun secret, sans les fichiers de la VM ni le schéma dans la racine du site ;
2. un `config.php` qui lit sa configuration dans l'environnement, avec les valeurs d'InfoGér par défaut **sauf** le mot de passe, qui n'a plus de valeur par défaut et peut être lu dans un fichier de secret ; sans aucune variable, l'application doit se comporter comme sur la VM (à ce mot de passe près) ;
3. une page de sonde de **vivacité** qui ne touche ni à la base ni aux sessions ;
4. un `compose.yaml` de recette : application, MariaDB avec sa sonde, secrets hors du dépôt, données (base, pièces jointes, sessions) dans des volumes nommés, journaux de l'application et d'Apache sur les sorties du conteneur, la purge nocturne en **tâche ponctuelle** déclenchée par l'hôte (plus de cron dans un conteneur) ;
5. la migration des données de `legacy01` vers la pile de recette (base et pièces jointes), décrite pas à pas et rejouable ;
6. `docs/conteneurs/legacy-rdv-12-facteurs.md` dans `plateforme/medisphere` : pour chacun des 13 points du README, ce qui est corrigé, ce qui est un **écart assumé** (et jusqu'à quand), ce qui reste un défaut.

**Contraintes**
- Aucun mot de passe dans un fichier versionné, dans l'image, dans l'environnement d'un conteneur visible par `docker inspect`, ni dans une ligne de commande. Le mot de passe de la base de recette n'est **pas** celui d'InfoGér.
- Une seule instance web (les sessions et les pièces jointes ne sont pas encore partagées) : écrit-le.
- Les pièces jointes ne sont jamais servies directement par Apache, comme sur la VM.
- Les réglages PHP qui étaient dans l'hôte virtuel de la VM (taille des téléversements) doivent continuer à s'appliquer.
- L'heure des rendez-vous existants ne doit pas changer.
- Avant de migrer, prends sur `legacy01`, par l'application, un rendez-vous au nom du patient « Témoin Migration », **avec une pièce jointe** (un PDF de ton choix) : il doit se retrouver dans la recette, pièce jointe comprise.

**Critères de réussite**
- [ ] `legacy/legacy-rdv` existe ; `main` contient `Dockerfile`, `.dockerignore`, `compose.yaml`, une page de sonde et un `config.php` sans le mot de passe d'InfoGér.
- [ ] La pile de recette tourne sur `ctr01` : application et MariaDB saines, page d'accueil de Legacy-RDV sur le port 8090 depuis `adm01`, MariaDB sans port publié.
- [ ] L'application tourne sous un compte non root, écoute sur 8080 dans le conteneur, a ses pièces jointes et ses sessions sur des volumes nommés ; aucun mot de passe dans l'environnement des conteneurs ; ses journaux sortent par `docker logs`.
- [ ] Les rendez-vous de `legacy01` sont présents dans la base de recette, dont « Témoin Migration », et sa pièce jointe se télécharge depuis la recette.
- [ ] `docs/conteneurs/legacy-rdv-12-facteurs.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 19`

<details><summary>Indice 1</summary>

Lis le script d'entrée de l'image officielle `php:8.4-apache-trixie` (`apache2-foreground`) et ses variables `APACHE_*` : il démarre en root pour ouvrir le port 80, puis change de compte ; un Apache entièrement non root doit écouter sur le port imposé par le contexte, qui fonctionne aussi hors de Docker. Les extensions PHP absentes de l'image s'ajoutent par `docker-php-ext-install`. Les images officielles de MariaDB acceptent les variables `*_FILE`.
</details>

<details><summary>Indice 2</summary>

`@file_put_contents` vers `/dev/stderr` échoue sans bruit dans un conteneur : PHP résout le lien. Il a un flux à lui pour la sortie d'erreur. Pour Apache, les journaux d'un hôte virtuel peuvent viser `/proc/self/fd/1` et `/proc/self/fd/2`.
</details>

<details><summary>Indice 3</summary>

Pour la migration : `mariadb-dump --single-transaction` sur `legacy01`, import par `docker compose exec -T`. Un conteneur jetable qui monte le volume des pièces jointes et tourne sous l'UID d'Apache peut y décompresser une archive. Le fuseau : regarde ce que contient une colonne `DATETIME` et ce que fait la variable `TZ` du conteneur de base.
</details>

---

### M12-E20 — Un runner GitLab à exécuteur Docker  `LAB` `★★★`

> **Ticket PLAT-1320** — *De : Karim Benali* — *Copie : Sophie Laurent*
> `runner01` exécute tout dans son shell, avec ses outils installés à la main par le rôle : chaque projet qui veut une autre version de Python ou de Go nous fait modifier le runner du socle. Il nous faut un second runner, `runner02`, à exécuteur **Docker** : chaque job choisit son image. Il rejoint le socle, il est décrit par le code comme les autres, et il n'est **jamais** privilégié. Sophie a une liste : pas de socket Docker dans les jobs, pas d'image « latest » par défaut, des jobs bornés en mémoire, et aucun secret qu'un job pourrait lire sans y avoir droit.

**Objectifs pédagogiques**
- Ajouter un hôte permanent au socle par le code (état `socle`, NetBox, DNS, Ansible) et à la matrice des flux.
- Configurer un runner à exécuteur Docker : image par défaut, politique de tirage, volumes, options de sécurité, limites ; comprendre ce que coûterait le mode privilégié.
- Étendre un rôle existant (`gitlab_runner`) pour un second profil sans casser le premier.

**Prérequis** : M01-E23 (runner, étiquettes), M04-E16 (rôle `gitlab_runner`), M05 (état `socle`, module `vm-debian`), M06 (NetBox, DNS, `ca_lab`), M12-E02 (rôle `docker_engine`), M12-E15 (registre, compte `ci`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `runner02`, VMID **1012**, `vinfra`, **10.10.20.17**, 2 vCPU, 4 Go, 64 Gio `local-nvme`, étiquettes `socle` et `role-runner`, démarrage automatique (ordre 5) ; état OpenTofu **`socle`**, module `vm-debian` + `enregistrement-dns` (comme `dns02`, `lb01`) |
| Logiciels | Docker Engine 29.8 (rôle `docker_engine`, mêmes versions que `ctr01`, **personne** dans le groupe `docker`, émulation QEMU de E12) ; GitLab Runner 19.4 (rôle `gitlab_runner`, même version que `runner01`) |
| Runner | objet GitLab créé par toi (*Admin → CI/CD → Runners → New instance runner*) : description `runner02-docker`, étiquettes `docker` et `socle`, jobs sans étiquette refusés ; jeton `glrt-…` dans le Vault `lab` (`vault_gitlab_runner02_jeton`) |
| Exécuteur | `docker` ; `privileged = false` ; image par défaut `docker.io/library/debian:trixie-slim` épinglée ; politique de tirage `always` puis `if-not-present` ; volumes : `/cache` et la racine MédiSphère en lecture seule sur `/etc/medisphere/racine-ca.crt` ; jobs bornés à 1,5 Go et 2 CPU ; deux jobs simultanés |
| Rôle | `gitlab_runner` étendu : variable `gitlab_runner_executeur` (`shell` par défaut, `docker` pour `runner02`) ; pour l'exécuteur `docker`, `config.toml` est **généré** par le rôle (au contraire de `runner01`) |
| Flux | `runner02` → Internet (images des jobs) : règle existante ; `runner02` → `git01` : même VLAN ; **`runner02` → `ctr01:5000`** : à ajouter |

**Travail demandé**

1. Lis la page « Docker executor » et la section `[runners.docker]` de « Advanced configuration » de GitLab Runner. Note, pour `privileged`, `volumes`, `pull_policy`, `allowed_pull_policies`, `security_opt`, `memory`, `cpus` : ce que fait la clé et sa valeur par défaut. Puis la section « Use Docker-in-Docker » : qu'accorde exactement `privileged = true` à un job, et à qui appartient le démon ?
2. Crée `runner02` par OpenTofu dans l'état `socle` (MR, plan relu : combien de ressources ?), pose son ordre de démarrage, vérifie NetBox et le DNS. Mets à jour `docs/socle/inventaire.md`.
3. Crée l'objet runner dans GitLab et range son jeton dans le Vault.
4. Étends le rôle `gitlab_runner` (MR, scénario Molecule de l'exécuteur shell toujours vert). Exigences :
   - pour l'exécuteur `docker` : aucun outil de CI installé sur l'hôte ; `config.toml` généré par modèle, en 600, avec les réglages du contexte ; un `config.toml` qui contiendrait `privileged = true` ou une politique de tirage `never` seule, ou une image par défaut non épinglée, est **refusé** par le rôle ;
   - le jeton vient du Vault la première fois, puis du fichier en place (le runner peut le renouveler) ;
   - en fin de rôle, le runner est vérifié auprès de GitLab ;
   - `runner01` est inchangé (second passage du playbook de `runner01` : `changed=0`).
5. Écris `host_vars/runner02/` (`gitlab_runner.yml`, `docker_engine.yml`, `vault.yml`) et `playbooks/runner02.yml` (rôles communs du socle, `docker_engine`, `gitlab_runner`) ; ajoute la règle `runner02` → `ctr01:5000` à la matrice des flux ; application par le pipeline.
6. Essaie le runner avec un projet de `formation/` : un job d'étiquette `docker` dans `python:3.13-slim-trixie` (épinglée) qui affiche `id`, `cat /proc/1/cgroup`, la racine MédiSphère montée, et tente `ls -l /var/run/docker.sock`. Un second job qui demande `image: docker.io/library/debian:latest` : passe-t-il ? Sous quel UID tourne le job ? Que voit-il de `runner02` ?
7. Lis sur `runner02`, pendant un job, `docker ps` et `docker inspect` du conteneur du job : options de sécurité, mémoire, montages. Où sont rangés les fichiers du dépôt cloné et le cache ?
8. Mets à jour la matrice des flux documentaire, l'inventaire du socle, le registre des secrets (jeton du runner), et la supervision de base du socle si elle liste les hôtes (sonde `ms-verif-services` de M06-E29).

**Critères de réussite**
- [ ] La VM 1012 `runner02` existe (étiquettes `socle`, `role-runner`), active dans NetBox avec l'adresse primaire 10.10.20.17, résolue par le DNS.
- [ ] Sur `runner02` : Docker 29.8, `gitlab-runner` actif ; `config.toml` en 600, exécuteur `docker`, `privileged = false`, image par défaut épinglée par empreinte, politique de tirage sans `never` seul, mémoire bornée ; le compte `gitlab-runner` n'est pas dans le groupe `docker`.
- [ ] GitLab voit un runner d'étiquette `docker` en ligne.
- [ ] La matrice des flux de `plateforme/ansible` (`main`) contient la règle `runner02` → `ctr01:5000`.

**Vérification** : `lab/bin/check 12 20`

<details><summary>Indice 1</summary>

Le module `vm-debian` crée l'intention dans NetBox avant la VM ; regarde `socle/dns02.tf` (M06-E24) ou `socle/repartiteurs.tf` (M07-E12) et recopie la forme. Pour le rôle : un `import_tasks` accepte un `when`, qui s'applique à chacune des tâches importées.
</details>

<details><summary>Indice 2</summary>

Dans `config.toml`, les listes s'écrivent comme en JSON (`["a", "b"]`) : le filtre `to_json` de Jinja produit une liste TOML valide. Pour retrouver un jeton déjà en place : `slurp` puis `regex_search`. Le compte qui exécute le **service** `gitlab-runner` sur l'hôte n'est pas le compte `gitlab-runner` : regarde l'unité systemd.
</details>

---

### M12-E21 — Construire les images en CI sans mode privilégié  `LAB` `★★★`

> **Ticket SEC-1321** — *De : Sophie Laurent* — *Copie : Karim Benali, Julien Petit*
> Une image de production ne se construit plus sur le poste de quelqu'un : la CI la construit, depuis le dépôt, et la publie dans le registre. Ma condition : aucun job privilégié, aucun socket Docker monté, aucun mot de passe du registre lisible par un pipeline de MR. Karim veut un gabarit commun dans `plateforme/ci-templates`, pour que chaque application n'ait que trois lignes à écrire. Julien veut que chaque version (`vX.Y.Z`) donne son image, `amd64` et `arm64` pour MédiAgenda.

**Objectifs pédagogiques**
- Construire une image dans un job **sans privilège** avec BuildKit *rootless* (`buildctl-daemonless.sh`), et comprendre les exceptions de sécurité qu'il demande et pourquoi.
- Écrire un gabarit de CI réutilisable (job caché, variables, règles par type de pipeline) et l'utiliser dans plusieurs projets.
- Publier avec des identifiants **protégés et masqués**, du cache de construction dans le registre, des étiquettes de version déduites de Git.

**Prérequis** : M01-E24, M01-E25 (`ci-templates`, branche `v1`, semantic-release), M12-E11 (cache, `SOURCE_DATE_EPOCH`), M12-E12 (multi-plateformes, émulation sur `runner02`), M12-E15 (registre, compte `ci`), M12-E16 (Hadolint), M12-E20 (`runner02`).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Constructeur | image `docker.io/moby/buildkit:v0.34.0-rootless` épinglée par empreinte ; dans le job : `buildctl-daemonless.sh build …` (un démon BuildKit éphémère, sous l'UID 1000 du conteneur) |
| Gabarit | `templates/image.yml` de `plateforme/ci-templates`, publié dans la branche `v1` (nouvelle version mineure) ; deux jobs cachés : `.hadolint` (stage `lint`) et **`.image-construction`** (stage `build`) ; variables de `.image-construction` : **`IMAGE`** (dépôt complet, sans étiquette), **`ETIQUETTES`** (liste séparée par des espaces ; vide = déduites de Git), **`FICHIER`** (Dockerfile), **`CONTEXTE`**, **`ARGS_CONSTRUCTION`** (`CLE=valeur …`), **`PLATEFORMES`** (liste séparée par des virgules), `PUBLIER` (`oui`/`non`, posé par les règles) ; stages et workflow : ceux de `templates/qualite.yml` (M01) |
| Étiquettes déduites | étiquette Git `vX.Y.Z` → image `X.Y.Z` ; `main` → `main-<SHA court>` ; MR → construction sans publication ; jamais `latest` |
| Identifiants | compte `ci` du registre ; variables **protégées et masquées** `REGISTRE_UTILISATEUR`, `REGISTRE_MOT_DE_PASSE` sur les groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` et `plateforme`, posées par un petit outil de `plateforme/outils` (`ms-variables-registre`) qui lit le mot de passe sur l'entrée standard |
| Confiance TLS | la racine MédiSphère montée par `runner02` dans chaque job (`/etc/medisphere/racine-ca.crt`, E20), déclarée au démon BuildKit pour le registre ; jamais d'option `insecure` |
| Projets | `mediagenda/api` (amd64 + arm64) et `medidoc/medidoc` (amd64 + arm64) ; `medinotif/worker` et `legacy/legacy-rdv` (amd64) peuvent suivre maintenant, ils sont exigés au mini-projet |

**Travail demandé**

1. Lis la page « Rootless mode » de la documentation de BuildKit (section *Containerized deployment*, *Docker*) et la page « Build Docker images with BuildKit » de GitLab. Note les trois options `--security-opt` que BuildKit demande pour tourner sans privilège dans un conteneur Docker, la raison de chacune, et ce qui peut remplacer la troisième. Note aussi la mise en garde de GitLab sur `seccomp`.
2. Essaie d'abord à la main sur `runner02`, avec le Docker de l'hôte (`sudo docker run --rm …`), un `buildctl-daemonless.sh build` d'un Dockerfile minimal monté dans le conteneur, **sans** aucune option de sécurité : quelle erreur ? Ajoute les options une à une jusqu'à ce que la construction passe. Ne garde que le minimum nécessaire.
3. Ajoute ces exceptions — et elles seules — au runner, par le rôle `gitlab_runner` (`host_vars/runner02/`), avec leur justification en commentaire. Ajoute aussi, par le rôle, des identifiants de **tirage** pour les images de jobs du registre de travail (compte `ci`) qui ne soient pas lisibles par les jobs. Écris `docs/conteneurs/construction-ci.md` : méthodes possibles (Docker-in-Docker, socket monté, BuildKit sans privilège, Buildah, Kaniko), privilège exigé par chacune, choix retenu, exceptions accordées et ce qu'elles n'accordent pas.
4. Écris `templates/image.yml` dans `plateforme/ci-templates` (branche de travail). Exigences :
   - `.hadolint` : Hadolint 2.15 dans son image épinglée, configuration du projet (E16), rapport Code Quality ;
   - `.image-construction` : construction de toutes les `PLATEFORMES` ; en MR, rien n'est poussé et aucun identifiant n'est demandé ; sur `main` et sur une étiquette de version, poussée de l'image **et** du cache de construction dans le registre ; échec explicite si les identifiants manquent ; `VERSION`, `REVISION` et `SOURCE_DATE_EPOCH` (date du commit) passés à la construction, horodatages réécrits ;
   - identifiants dans le fichier de configuration du client, jamais en argument ; refus de `latest` ;
   - le gabarit ne suppose rien d'autre que les variables documentées en tête de fichier.
   Teste-le depuis une branche de `mediagenda/api` qui inclut le gabarit **par sa branche de travail** (`ref:`), puis publie une version mineure de `ci-templates` (la branche `v1` avance).
5. Pose les variables de groupe avec `ms-variables-registre` (mot de passe du compte `ci` tiré du Vault, jamais affiché) ; inscris-les au registre des secrets.
6. `mediagenda/api` : `.gitlab-ci.yml` qui inclut `qualite.yml`, `release.yml` et `image.yml` (`ref: v1`), un job de tests, `hadolint` et `image` par extension des jobs cachés, `PLATEFORMES` amd64 + arm64. Le workflow de `qualite.yml` ne lance rien sur les étiquettes : complète-le dans le projet pour que l'étiquette `vX.Y.Z` lance un pipeline. MR (lis le journal du job de construction : rien n'est poussé), fusion (`main-<SHA>` publiée), puis étiquette `v1.0.0` (par semantic-release si le projet a son `.releaserc.json`, sinon à la main, étiquette protégée) : l'image `1.0.0` est publiée.
7. Même chose pour `medidoc/medidoc` (tests Go dans l'image Go épinglée, sur `runner02`). Lance deux fois le pipeline de l'étiquette `v1.0.0` de MédiDoc : l'empreinte publiée change-t-elle ? Le cache a-t-il servi ?
8. Les preuves que Sophie demande, dans `docs/conteneurs/construction-ci.md` : le journal d'un job de MR (pas de poussée, variables absentes), `docker inspect` d'un conteneur de job sur `runner02` pendant une construction (`Privileged`, `SecurityOpt`, montages), l'index publié de `mediagenda/api:1.0.0` (deux plateformes).

**Critères de réussite**
- [ ] `templates/image.yml` est dans la branche `v1` de `plateforme/ci-templates`, avec les jobs cachés `.hadolint` et `.image-construction` et les variables du contexte.
- [ ] `runner02` : exceptions `seccomp` et `apparmor` (et rien de plus), toujours sans mode privilégié.
- [ ] `mediagenda/api` et `medidoc/medidoc` : dernier pipeline de `main` réussi, jobs Hadolint et de construction réussis sur un runner d'étiquette `docker` ; aucune valeur de mot de passe dans `.gitlab-ci.yml`.
- [ ] Le registre contient `mediagenda/api:1.0.0` et `medidoc/medidoc:1.0.0` en `amd64` et `arm64`, et une image `main-<SHA>` de chacun.
- [ ] `docs/conteneurs/construction-ci.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 21`

<details><summary>Indice 1</summary>

L'image `moby/buildkit:rootless` démarre par défaut son propre démon : dans un job, remplace son point d'entrée (`entrypoint: [""]`). Le démon éphémère de `buildctl-daemonless.sh` lit `BUILDKITD_FLAGS` ; sur une petite VM, il met plusieurs secondes à répondre (lis le script : une variable règle le nombre d'essais). Sa configuration se trouve, en mode sans privilège, sous `~/.config/buildkit/`.
</details>

<details><summary>Indice 2</summary>

`buildctl` lit les identifiants dans `~/.docker/config.json` (`{"auths": {"<hôte>": {"auth": "<base64 de utilisateur:mot de passe>"}}}`). Plusieurs noms d'image dans une seule sortie : `type=image,"name=a:1,a:2",push=true` (les guillemets protègent les virgules). Les variables d'une règle (`rules: … variables:`) permettent de changer `PUBLIER` selon le type de pipeline.
</details>

<details><summary>Indice 3</summary>

Si le job de `main` échoue avec « identifiants absents » alors que les variables existent : sont-elles **protégées**, et la branche l'est-elle ? Si la date du commit n'est pas lisible : `git` refuse un dépôt qui n'appartient pas à l'utilisateur courant (`safe.directory`).
</details>

**Pour aller plus loin** (facultatif) : remplace `seccomp=unconfined` par un profil seccomp dédié (profil par défaut de Docker + `unshare`, `mount`, `umount2`, `pivot_root`, `setns`), déposé par le rôle sur `runner02` ; vérifie dans la documentation de GitLab Runner comment `security_opt` accepte un profil, et éprouve-le.

---

### M12-E22 — Revue : les Dockerfiles du stagiaire  `REV` `★★`

> **Ticket PLAT-1322** — *De : Karim Benali*
> Lucas a ouvert sa première MR « conteneurs » : trois Dockerfiles, un script de sauvegarde et un `compose.yaml` pour une recette « tout-en-un ». Il y a passé du temps et il est fier ; il y a aussi de quoi se faire licencier par un auditeur HDS. Fais-en la revue : chaque défaut, pourquoi c'en est un, ce qu'il risque, et ce qu'il faut écrire à la place. Bienveillant et précis : c'est comme ça qu'il apprendra.

**Objectifs pédagogiques**
- Relire un Dockerfile et un `compose.yaml` comme du code de production : sécurité, reproductibilité, taille, exploitation.
- Classer les défauts par gravité et distinguer ce qu'un outil trouve de ce que seul un humain voit.
- Rédiger une revue utile à son auteur.

**Prérequis** : M12-E05 à E19 (tout ce que le palier a pratiqué), M12-E16 (Hadolint).
**Durée indicative** : 1 h 30.

**Ressources** : [`ressources/E22-revue-lucas/`](../ressources/E22-revue-lucas/) (description de la MR dans `LISEZMOI.md`, `mediagenda-api/Dockerfile`, `medidoc/Dockerfile`, `sauvegarde-pg/Dockerfile` et `sauvegarde.sh`, `compose.yaml`). Ces fichiers sont fictifs, ne les construis pas et ne les lance pas.

**Travail demandé**

1. Passe d'abord Hadolint (configuration de MédiSphère, E16) sur les trois Dockerfiles. Note ce qu'il trouve.
2. Relis ensuite **à la main** chaque fichier, ligne par ligne. Pour chaque défaut : fichier et ligne, catégorie (sécurité, secret, reproductibilité, taille, exploitation, exactitude), gravité (bloquant, majeur, mineur), explication en une ou deux phrases, correction proposée. Au moins **12 défauts distincts**, dont au moins **5 qu'Hadolint ne signale pas**.
3. Rédige la revue dans `~/m12/e22/revue.md` comme des commentaires de MR : un commentaire général (ce qui va bien, ce qui bloque la fusion, l'ordre dans lequel corriger), puis les commentaires ligne par ligne.
4. Écris à Lucas, en dix lignes au plus, les trois règles qu'il doit retenir en priorité, et dis-lui où elles sont écrites (introduction du module, normes à venir en M12-E33).

**Critères de réussite**
- [ ] La revue contient au moins 12 défauts distincts, chacun avec gravité, explication et correction ; au moins 5 ne sont pas détectés par Hadolint.
- [ ] Les défauts bloquants (secrets, privilèges, socket du démon) sont identifiés comme tels et expliqués par leur risque concret.
- [ ] Le ton reste celui d'une revue entre collègues : chaque critique propose une correction.

<details><summary>Indice 1</summary>

Relis les règles du module (introduction) et les exigences de Karim en E05, E10, E11 : chaque règle a ici au moins un contre-exemple. Pense aussi à ce que la revue d'un `compose.yaml` doit regarder : ce qui est publié, ce qui est monté, ce qui est privilégié, ce qui démarre dans quel ordre.
</details>

<details><summary>Indice 2</summary>

Pour chaque valeur qui ressemble à une donnée (mot de passe, clé, jeton, URL), demande-toi où elle finira : couche, historique, `docker inspect`, journal de CI, dépôt Git. Pour chaque `latest` ou version absente, demande-toi ce qui sera construit dans six mois.
</details>

---

### M12-E23 — Runbook : un conteneur redémarre en boucle  `RED` `★★`

> **Ticket PLAT-1323** — *De : Nadia Roussel*
> Ma question de 3 h du matin, enfin : « un conteneur redémarre en boucle, je fais quoi ? ». Je veux un runbook que l'astreinte peut suivre sans t'appeler : comment le constater, comment lire ce qu'il dit, comment trouver dans quelle famille de causes on est, comment le geler sans perdre les traces, quand escalader et à qui. Docker sur `ctr01`, Podman et Quadlet sur `ctr02`. Il sera complété au fil des pannes du palier 4.

**Objectifs pédagogiques**
- Transformer ce que le palier a appris (codes de sortie, journaux, sondes, limites, politiques de redémarrage, Quadlet) en procédure d'exploitation.
- Écrire pour quelqu'un qui n'est pas l'auteur : commandes exactes, critères de décision, interdits.

**Prérequis** : M12-E03 (codes de sortie, politiques de redémarrage), M12-E14 (Quadlet), M12-E17 (arrêt propre), M12-E18 (journaux, limites, santé) ; modèle de runbook de M00/M01 (`docs/socle/runbooks/`).
**Durée indicative** : 1 h 30.

**Travail demandé**

Rédige `docs/conteneurs/runbooks/RB-120-conteneur-redemarre-en-boucle.md` dans `plateforme/medisphere` (MR relue par Nadia et Karim). Il contient au moins :

1. un en-tête (périmètre, durée visée, droits nécessaires) et les **règles** pendant l'intervention (ce qu'on ne fait jamais) ;
2. **constater** : commandes Docker et Podman/Quadlet qui donnent l'état, le code de sortie, le nombre de redémarrages, les journaux, les événements ;
3. **lire le code de sortie** : un tableau des codes courants et de leur signification ;
4. **classer la cause** : configuration, dépendance, ressources, sonde de santé, image, hôte — indices et vérification pour chacune ;
5. **geler sans détruire** un conteneur qui boucle, et revenir ensuite à la normale ;
6. **corriger, redéployer, vérifier** (critère de retour à la normale mesurable) ;
7. **escalader** : à qui, avec quelles informations ;
8. une section « le conteneur est **tué sans prévenir** » (OOM, plafond de processus, délai de grâce, sonde qui tue) : le palier 4 ajoutera « le conteneur s'arrête dès le démarrage » (M12-E35).

Éprouve-le : demande à quelqu'un (ou fais-le toi-même le lendemain, sans tes notes) de suivre le runbook sur un conteneur volontairement cassé de `ctr01` (par exemple `docker run -d --name m12-e23-boucle --restart always docker.io/library/debian:trixie-slim sh -c 'echo démarrage; sleep 3; exit 3'`), puis supprime ce conteneur. Note ce qui a manqué et corrige.

**Critères de réussite**
- [ ] RB-120 est sur `main` de `plateforme/medisphere`, avec les huit parties demandées.
- [ ] Chaque étape donne des commandes exactes, pour Docker **et** pour Podman/Quadlet, et le critère qui fait passer à l'étape suivante.
- [ ] Le runbook interdit explicitement les gestes qui détruisent les traces ou les données, et dit comment geler sans détruire.
- [ ] L'essai sur un conteneur cassé est fait ; ce qui a manqué est corrigé.

<details><summary>Indice 1</summary>

Pars des codes de sortie de M12-E03 (0, 137, 143) et complète : 1 et 2 (refus de l'application), 126 et 127 (commande), 139. Un conteneur arrêté se lit encore (`logs`, `inspect`, `cp`) ; un conteneur supprimé, non. `docker update` change la politique de redémarrage d'un conteneur existant.
</details>

<details><summary>Indice 2</summary>

Côté systemd : `RestartSec=`, `StartLimitBurst=`, `StartLimitIntervalSec=` et le message `start request repeated too quickly`. Côté Docker : le délai entre deux redémarrages double à chaque échec. Les deux disent combien de temps tu as avant que « ça se calme tout seul »… sans que rien ne soit réparé.
</details>
