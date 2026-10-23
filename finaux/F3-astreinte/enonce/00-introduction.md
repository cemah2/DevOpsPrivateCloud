# Final F3 — Introduction : la semaine d'astreinte

## Lundi, 8 h

Nadia Roussel pose le téléphone d'astreinte sur ton bureau, avec un classeur et un café.

> **De** : Nadia Roussel — Responsable support / astreinte
> **À** : toi
> **Cc** : Claire Morel
> **Objet** : Passation d'astreinte — semaine 1
>
> Bonjour,
>
> Ta première semaine seul·e. Karim est en congé, je suis en formation jusqu'à jeudi midi (joignable le soir pour un SEV1, pas pour le reste). Claire arbitre si tu as besoin d'une décision. Lucas est là toute la semaine ; il connaît des bouts de la plateforme, il aime aider, et il lui arrive de « corriger vite » : demande-lui ce qu'il a touché avant de le laisser toucher autre chose.
>
> Ce que j'attends de toi cette semaine :
> 1. **Prendre l'astreinte** pour de bon : vérifie tes accès, la réception des alertes, et que tu sais où sont les runbooks. On ne découvre pas ses accès pendant un incident.
> 2. **Écrire notre procédure de gestion d'incident** : on n'en a pas. Chaque incident a été géré « à l'instinct ». Je veux des niveaux de gravité, des rôles, un rythme de messages, une main courante.
> 3. **Tenir chaque incident** selon cette procédure : diagnostic, correction **par le code**, messages d'état à Claire et aux équipes, trace écrite.
> 4. Vendredi : le **post-mortem** de l'incident le plus grave, le ménage dans les alertes inutiles, et ta passation pour la personne suivante.
>
> Le classeur est à jour, normalement.
> Nadia

Ce final ne t'apprend rien de neuf : il te met en situation. Les incidents arrivent comme en vrai — un utilisateur qui se plaint avant toute alerte, une alerte qui n'a pas sonné, une panne qui en cache une autre, une correction trop rapide qui en provoque une troisième. Ce qui est évalué : la **démarche** (observer avant d'agir, une hypothèse à la fois, la mesure la moins invasive), la **correction à la racine par le code**, la **communication** et la **trace**.

---

## La semaine

| Jour | Scénarios | Fichier |
|---|---|---|
| Lundi matin | F3-S01 Prendre l'astreinte · F3-S02 La procédure de gestion d'incident | [`01-prise-de-poste.md`](01-prise-de-poste.md) |
| Lundi | F3-S03 « MédiAgenda rame » · F3-S04 Pourquoi personne n'a été prévenu ? | [`02-lundi.md`](02-lundi.md) |
| Mardi | F3-S05 Les certificats ne se renouvellent plus · F3-S06 Un nœud tombe malade · F3-S07 Incident chronométré (soir) | [`03-mardi.md`](03-mardi.md) |
| Mercredi | F3-S08 Le stockage ralentit tout · F3-S09 La livraison est bloquée | [`04-mercredi.md`](04-mercredi.md) |
| Jeudi | F3-S10 Les secrets ne suivent plus · F3-S11 La moitié des noms ne répond plus | [`05-jeudi.md`](05-jeudi.md) |
| Vendredi | F3-S12 Alerte Falco en production · F3-S13 Les notifications s'accumulent | [`06-vendredi.md`](06-vendredi.md) |
| Bilan | F3-S14 Post-mortem · F3-S15 Faire taire les alertes inutiles · F3-S16 Rapport de semaine et passation (`astreinte-v1`) | [`07-bilan.md`](07-bilan.md) |

Les « jours » sont ceux du scénario, pas du calendrier : prends le temps qu'il faut entre deux incidents (30 à 45 heures en tout, attentes des injections comprises). Fais-les **dans l'ordre** : S04 suppose S03 clos, S14 et S16 s'appuient sur tout ce qui précède.

---

## État d'entrée et préparation

**État d'entrée** : la fin du final F2 (étiquette **`day1-v1`** de `plateforme/medisphere`, `lab/bin/check F2 13` vert), sur le profil de travail des blocs F et G : socle v5 + `ceph-par1` + `k8s-par1` (≈ 111 Go). F3 n'ajoute **aucune VM** (plage 3300-3399 réservée, inutilisée) ; arrête ce qui ne sert pas, mais garde `mon01` allumé toute la semaine : c'est ton témoin.

Ce que la semaine mobilise (rien à installer, tout est là depuis les modules) :

| Domaine | Où regarder | Modules |
|---|---|---|
| Alertes et courriels | Alertmanager du cluster `http://alertmanager.apps.par1.medisphere.internal:9093`, Mailpit `https://mon01.par1.medisphere.internal:8025` (`astreinte@`, `plateforme@`, `<prénom.nom>@medisphere.internal`), témoin de `mon01` (Prometheus et Alertmanager « témoins », `watchdog-cluster`) | M19, M21 |
| Métriques, journaux, traces | Thanos Query `http://prometheus.apps.par1.medisphere.internal:9090`, Grafana `https://grafana.apps.par1.medisphere.internal`, Loki (locataires `plateforme`, `mediagenda`, `medidoc`, `audit`), Tempo | M21-M23 |
| Configuration en code | `plateforme/observabilite`, `plateforme/gitops`, `plateforme/k8s`, `plateforme/ansible`, `plateforme/infra`, `plateforme/ceph`, `plateforme/secrets`, `plateforme/politiques`, `mediagenda/deploiement`, `medinotif/deploiement` | tout le parcours |
| Accès | kubelogin (OIDC + OTP), `bao login -method=oidc`, `step ssh login`, comptes de bris de glace (RB-240) | M24, M25 |
| Documentation | `plateforme/medisphere` : runbooks `docs/**/runbooks/RB-NNN-*.md`, et ce que tu vas écrire sous **`docs/exploitation/`** | tout le parcours |

**Variables de `lab/lab.env`** (toutes facultatives : les défauts conviennent au lab de référence ; ne les pose que si ton lab diffère) :

| Variable | Défaut | Rôle |
|---|---|---|
| `WB_F3_DEPOT` | `plateforme/medisphere` | dépôt de la documentation lu par les checks |
| `WB_F3_DOC` | `docs/exploitation` | dossier de l'exploitation |
| `WB_F3_PROD_URL` | `https://mediagenda.apps.par1.medisphere.internal` | MédiAgenda publié (production) |
| `WB_F3_RECETTE_URL` | `https://mediagenda-recette.apps.par1.medisphere.internal` | MédiAgenda publié (recette) |
| `WB_F3_LATENCE_MAX` | `1.0` | médiane acceptable (s) d'une consultation de créneaux qui manque le cache |
| `WB_F3_TEMOIN_URL` | `http://mon01.par1.medisphere.internal:9090` | Prometheus témoin de `mon01` |
| `WB_F3_APPS_IGNOREES` | (vide) | regex des Applications Argo CD exclues du contrôle de santé (une Application que tu sais légitimement `OutOfSync`) |
| `WB_F3_CEPH_TOLERES` | (vide) | regex de codes de santé Ceph tolérés (ex. `RECENT_CRASH` le temps de l'archiver) |
| `WB_F3_CEPH_ADMIN` | `WB_CEPH_ADMIN`, sinon `ceph01` | nœud `_admin` de Ceph |
| `WB_F3_VALKEY_MAXMEMORY_MIN` | `16777216` | plancher de `maxmemory` de Valkey en production (S03) |
| `WB_F3_VALKEY_POD` | `valkey-0` | pod Valkey de production (injection S03) |
| `WB_F3_VALKEY_ADMIN_USER`, `WB_F3_VALKEY_ADMIN_SECRET`, `WB_F3_VALKEY_ADMIN_CLE` | `WB_M27_VALKEY_ADMIN_*`, sinon `admin`, `valkey-admin`, `mot_de_passe` | compte d'administration de Valkey (injection S03, M27) |
| `WB_F3_ACME_URL` | `https://ca01.par1.medisphere.internal/acme/acme/directory` | répertoire ACME attendu de `step-ca-acme` (S05) |
| `WB_F3_DNS_PRIMAIRE` | `dns01` | autoritaire primaire (S05) |
| `WB_F3_DNS02` | `dns02` | second récurseur (injection S11) |
| `WB_F3_PASSERELLES` | `gw01 gw02` | passerelles de bordure (S05, S11) |
| `WB_F3_PROJET_OBSERVABILITE` | `plateforme/observabilite` | configuration de l'alerte (S04, S15) |
| `WB_F3_FICHIER_KPS` | `kps/values.yaml` | valeurs de kube-prometheus-stack (injection S04) |
| `WB_F3_FICHIER_ROUTES_TESTS` | `alertmanager/routes-tests.txt` | essais de routage joués par la CI (S04) |
| `WB_F3_PROJET_GITOPS` | `plateforme/gitops` | analyses des Rollouts (injection S09) |
| `WB_F3_PROJET_DEPLOIEMENT` | `mediagenda/deploiement` | déploiement de MédiAgenda (S09) |
| `WB_F3_FICHIER_OVERLAY_RECETTE` | `overlays/recette/kustomization.yaml` | overlay de recette (injection S09) |
| `WB_F3_PROJET_API` | `mediagenda/api` | code de MédiAgenda (S09) |
| `WB_F3_APP_RECETTE` | `mediagenda-recette` | Application Argo CD de la recette (S09) |
| `WB_F3_S06_NOEUDS` | `WB_K8S_WORKERS`, sinon `k8s-w01 k8s-w02 k8s-w03` | travailleurs que l'incident de S06 peut toucher |
| `WB_F3_S07_RESERVOIR` | `15:40 16:41 27:20 27:22 28:19` | réservoir de l'incident chronométré (`module:exercice`) |
| `WB_F3_S08_POOL` | `k8s-rbd` | pool RBD du cluster (S08) |
| `WB_F3_S08_CEPH_VMS` | `ceph01:2081 ceph02:2082 ceph03:2083` | VMs Ceph (`nom:VMID`, S08) |
| `WB_F3_S11_NOM` | `git01.par1.medisphere.internal` | nom de contrôle des récurseurs (injection S11) |
| `WB_F3_S11_SAUT_MORT` | `10.10.40.249` | adresse sans hôte du VLAN 40 (injection S11) |
| `WB_F3_S11_CIBLES` | `10.10.41.10:443 10.10.41.60:9090 10.10.41.61:9093 10.10.41.62:3100` | adresses de service jointes depuis `adm01` (S11) |
| `WB_F3_S12_IMAGE_DEBUG` | `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37` | image du conteneur éphémère (injection S12) |
| `WB_F3_S12_SELECTEUR_MEDIDOC` | `app.kubernetes.io/name=medidoc` | sélecteur des pods de MédiDoc en dev (injection S12) |
| `WB_F3_S12_PREUVES_ENV` | `~/.config/workbook/s3-preuves-depot.env` | identité S3 du compartiment `preuves` (M26-E33) ; le check ne fait que lister |
| `WB_F3_S3_URL` | `https://s3-01.par1.medisphere.internal:8333` | point d'accès S3 de `s3-01` (S12) |
| `WB_F3_S13_DEBIT` | `110` | messages/s de la campagne factice (injection S13) |
| `WB_F3_S13_DUREE` | `2700` | durée maximale (s) de la campagne factice (injection S13) |
| `WB_F3_S13_SEUIL` | `2000` | messages en attente tolérés dans `notifications` (prod) après réparation (S13) |
| `WB_F3_PROJET_NOTIF` | `medinotif/deploiement` | déploiement de MédiNotif (S13) |

**Outillage de `adm01`** (tout vient des modules ; vérifie-le en prenant l'astreinte, les injections refusent de partir s'il manque) : `kubectl` avec le kubeconfig d'administration (`WB_K8S_ADMIN_KUBECONFIG`) et kubelogin, `jq`, `yq` **de mikefarah (v4)**, `curl`, `ssh` (`admin` + `sudo` vers les VMs et les nœuds, `root` vers `pve01`), `dig` (S11), `amtool` (M21 : checks de S01 et S04), `bao` avec un jeton d'administration `plateforme-admin` (`BAO_TOKEN` ou `~/.vault-token`, comme les pannes du M25 ; injections S09 et S10), `aws` (CLI S3 : collecte et check de S12), `script` (paquet `util-linux` : terminal de l'injection S12), `timeout`, `base64`, `setsid` (coreutils et util-linux), `python3` (injection S13), le jeton d'administration GitLab `WB_GITLAB_ADMIN_TOKEN_FILE` (portée `api` : commits de Lucas et de Julien), la racine `WB_RACINE_PKI`, et le fichier d'identité **`~/.config/workbook/s3-preuves-depot.env`** du compartiment `preuves` (M26-E33, RB-262).

---

## Comment se passent les incidents

Les incidents (scénarios `BF` et `CHRONO`) sont **injectés** depuis `adm01`, à la racine de ta copie du workbook :

```
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break F3 3
```

Règles du jeu :

- **Le lab doit être sain** : chaque injection commence par le contrôle de santé de S01 (nœuds `Ready`, Applications Argo CD saines, Ceph `HEALTH_OK`, aucune alerte critique, sondes du témoin de `mon01` vertes). S'il n'est pas vert, l'injection refuse : « le lab n'est pas dans l'état attendu ; lance `lab/bin/check F3 1` ». Répare d'abord, c'est déjà de l'astreinte.
- **Une panne active à la fois**, dans tout le lab (modules compris). L'injection refuse tant qu'une autre panne n'est pas close.
- Le script **tire une variante au hasard** (`--variante N` en force une, sans dire laquelle est laquelle) et n'affiche **que le symptôme**, tel qu'on te le rapporte. Il sauvegarde tout ce qu'il touche et **constate** l'effet avant de te le présenter : si la panne ne prend pas sur ton lab, il annule et le dit.
- Une injection peut prendre **de 1 à 30 minutes** (commit, synchronisation d'Argo CD, sauvegarde préalable de la production, constat d'un canary…). Elle peut toucher la **production** : uniquement par des changements réversibles, sans perte de données ; une panne qui touche la base de production exige une sauvegarde CloudNativePG récente et la lance si besoin.
- Certaines pannes passent par un **commit** de Lucas (ou de Julien) dans un dépôt, avec le marqueur `F3-SXX` dans le message : un vrai changement, visible dans `git log`, dans Argo CD et dans le journal d'audit de GitLab. Corrige-le comme un vrai commit fautif (MR de correction ou `git revert`), jamais par réécriture d'historique.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01`.
- **Quand tu as réparé** : lance le contrôle (`lab/bin/check F3 3`), puis **clos l'injection** (`lab/bin/break F3 3 --annuler`). L'annulation ne défait jamais ta réparation (elle ne remet un fichier ou un réglage que s'il est encore exactement dans l'état injecté) ; elle retire les témoins de l'incident. `--annuler` est aussi ton filet de sécurité si tu abandonnes.
- Le **temps cible** de chaque incident est indicatif ; le dépasser n'est pas un échec, corriger sans comprendre en est un. Seul S07 est chronométré pour de bon.

> ⚠️ **Effets de bord** : les incidents dégradent réellement des services (la production de MédiAgenda le lundi, le stockage de tout le cluster le mercredi). C'est voulu. Ne lance pas une injection juste avant de devoir t'absenter : un incident ouvert se tient jusqu'à sa clôture.

---

## La main courante et les messages d'état

C'est la convention de l'équipe ; S02 te fait écrire la procédure complète autour d'elle, et les checks la lisent.

**Main courante** : un fichier par jour réel de travail, `docs/exploitation/journal/<AAAA-MM-JJ>.md` dans `plateforme/medisphere`. **Une ligne par entrée**, de la forme :

```markdown
- 09:14 INC-5903 [ouverture] SEV2 — lenteur de MédiAgenda prod signalée par le support (3 cabinets). Responsable : <MOI>.
- 09:21 INC-5903 [action] p95 mesuré à 7,8 s sur les créneaux ; /pret à 200 ; pas d'alerte reçue.
- 09:29 INC-5903 [état] message d'état n° 1 envoyé à incidents@ (Claire, Julien, support).
- 09:52 INC-5903 [décision] je termine la session bloquante après accord de Claire (pas de perte de données).
- 10:07 INC-5903 [clôture] rétabli à 09:58 ; cause, correctif et suites : voir ticket PLAT-3303.
```

Types d'entrée : `[ouverture]`, `[état]`, `[action]`, `[décision]`, `[clôture]`. L'heure est celle de l'événement, en `HH:MM`. Un incident = un identifiant **`INC-59XX`** (XX = numéro du scénario : INC-5903 pour S03). Tiens la main courante en direct dans ta copie du dépôt ; publie-la **par MR** au plus tard à la clôture (les checks lisent `main`). Tu peux en plus ouvrir un ticket GitLab par incident dans `plateforme/medisphere` (titre qui commence par l'identifiant) : il remplace la main courante pour l'ouverture et la clôture, pas pour les messages d'état.

**Messages d'état** : par courriel, à la liste `incidents@medisphere.internal` (et aux personnes concernées), **objet qui commence par `[INC-59XX]`**, envoyé depuis `adm01` par le relais du lab (`smtp.par1.medisphere.internal:25`, STARTTLS), par exemple :

```
admin@adm01:~$ cat ~/astreinte/etat.txt
From: astreinte@medisphere.internal
To: incidents@medisphere.internal
Cc: claire.morel@medisphere.internal, julien.petit@medisphere.internal
Subject: [INC-5903] [SEV2] État n° 1 — MédiAgenda prod lent

(texte du message selon le modèle de ta procédure)
admin@adm01:~$ curl -sS --ssl-reqd --url smtp://smtp.par1.medisphere.internal:25 \
    --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
    --mail-from astreinte@medisphere.internal --mail-rcpt incidents@medisphere.internal \
    --mail-rcpt claire.morel@medisphere.internal --mail-rcpt julien.petit@medisphere.internal \
    --upload-file ~/astreinte/etat.txt
```

Chaque message d'état envoyé a aussi son entrée `[état]` dans la main courante. Le **rythme** dépend de la gravité : c'est ta procédure (S02) qui le fixe, et tu t'y tiens.

**Tickets d'action** : ce qui ne se règle pas pendant l'incident (prévention, dette) devient un ticket **`PLAT-33XX`** dans `plateforme/medisphere` (XX = numéro du scénario d'origine, suffixe `-a`, `-b`… si besoin), repris par le post-mortem (S14) et la passation (S16). Les actions issues du post-mortem prennent **`PLAT-3371` et suivants** ; les numéros `PLAT-3350` à `PLAT-3369` sont déjà pris par des tickets antérieurs de l'équipe.

**Runbooks** : les runbooks de l'exploitation sont numérotés **RB-330 et suivants**, sous `docs/exploitation/runbooks/` : RB-330 (MédiAgenda lent en production), RB-331 (une alerte n'est pas arrivée), RB-332 (certificats ACME non délivrés), RB-333 (nœud travailleur malade), RB-334 (stockage Ceph lent), RB-335 (livraison bloquée), RB-336 (les secrets ne suivent plus), RB-337 (une partie des noms ne répond plus), RB-338 (les notifications s'accumulent). Les incidents de sécurité suivent RB-262 (M26), sans nouveau runbook.

---

## Ce qu'on attend d'une bonne astreinte

- **Le service d'abord, la cause ensuite, la prévention enfin** : rétablir (même par un geste de contournement documenté), puis trouver la cause racine, puis empêcher la récidive par le code.
- **Par le code** : la correction durable passe par une MR dans le dépôt qui décrit la chose (Ansible, OpenTofu, GitOps, règles d'alerte, politiques). Un geste à la main (terminer une session, relancer un service, expirer un silence) est permis **pour rétablir**, consigné en `[action]` ou `[décision]`, et suivi de la correction par le code si la cause est dans le code.
- **La production se touche avec une décision** : avant un geste risqué en production, une entrée `[décision]` (quoi, pourquoi, retour arrière, qui a validé).
- **Pas de coupable** : on écrit ce qu'a fait Lucas comme on écrirait ce qu'aurait fait n'importe qui, et on corrige le système qui a permis l'erreur.

Pour aller plus loin : *Site Reliability Engineering* (Google), chapitres « Managing Incidents » et « Postmortem Culture » (<https://sre.google/sre-book/managing-incidents/>), et le guide d'incident de PagerDuty (<https://response.pagerduty.com/>).
