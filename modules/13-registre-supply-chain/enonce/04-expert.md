# Module 13 — Palier 4 : Expert

Le registre est en production : répliqué, sauvegardé, supervisé, protégé par ses politiques. C'est maintenant qu'il casse, et de la pire façon : un registre en panne ne fait rien tomber tout de suite, il fait échouer **tout le reste** — chaque pipeline, chaque déploiement, bientôt chaque pod. Nadia Roussel a rassemblé les tickets des trois dernières années d'InfoGér et des post-mortems publics : un tirage refusé « sans raison », une publication qui échoue au dernier job, une signature qui « n'est plus reconnue » le jour d'un déploiement, un Harbor qui ne redémarre pas après une maintenance. Karim Benali les a transformés en quatre pannes. Puis tu descends sous le capot, au niveau du protocole, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au registre :
- **Lis le message d'erreur en entier, et d'où il vient.** Un `unauthorized` vient du service de jetons ; un `denied` d'une autorisation refusée ; un `412` d'une politique de projet ; un `x509` du client TLS, avant même que Harbor ne soit joint. Le client (`docker`, `skopeo`, `cosign`) reformule souvent : relance avec plus de détail (`--debug`, `skopeo --debug`, `cosign … --verbose`) ou rejoue la requête avec `curl`.
- **Sépare le client, le réseau, le registre et la donnée.** La même image peut être intirable depuis `runner02` et tirable depuis `adm01` : c'est alors le client. Elle peut être tirable par `adm01` avec un compte et pas avec un autre : c'est l'identité. Teste toujours depuis deux endroits et avec deux identités.
- **Ne détruis rien que tu ne sais pas recréer.** Pas de suppression de projet, de dépôt, d'artefact signé, de robot de production, de `/data` « pour repartir propre ». Une signature supprimée ne se recrée qu'en re-signant, et re-signer une image qu'on n'a pas vérifiée revient à la blanchir.

> **Rappels** : tout se lance depuis `adm01`. L'URL du registre est `https://registry.par1.medisphere.internal` ; `reg01` se joint en SSH (`admin` + sudo) ; le dossier d'installation de Harbor est celui de l'unité `harbor.service` (`systemctl cat harbor`). Le code de configuration de Harbor (E03) et le rôle `harbor` restent la référence : une réparation à chaud qui touche ce qu'ils décrivent est reportée ensuite par une MR, sinon la prochaine application la défera.

## Règles du jeu des pannes (M13-E19 à M13-E22)

- **Préparation, une fois pour toutes, avant la première injection** (10 min) :
  1. Crée dans Harbor de `reg01` un **utilisateur local** `wb-pannes` (base locale, case « administrateur » cochée), avec un mot de passe long tiré au hasard. Écris-le sur `adm01` dans `~/.config/workbook/harbor-pannes.env` (mode 600) : `HARBOR_USER=wb-pannes` et `HARBOR_PASSWORD=…`. C'est l'identité des scripts de panne ; un robot ne suffit pas (un robot ne peut ni créer ni modifier d'autres robots). C'est une **exception documentée** (registre des secrets, date de fin) : le compte est supprimé au mini-projet (E25), avant le passage à OIDC du module 24.
  2. Vérifie que `runner02` a Docker et accès à `reg01`, et que `lab/bin/check 13 19` est vert.
- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 13 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante). Si une variante n'a pas d'effet sur ton lab, le script le constate, annule, et te le dit.
- **Témoins.** À la première injection de E19, E20 ou E21, le script crée (s'ils n'existent pas) des **témoins** qui jouent le rôle des pipelines et qu'il ne supprime jamais :
  - dans Harbor : le projet privé `wb-sonde` (dépôts `temoin`, `publication`, `signee`) et le projet public `wb-sonde-public` (dépôt `temoin`), sans politique ; deux robots système, `robot$wb-sonde-tirage` (lecture de `wb-sonde`, `dockerhub` et `ghcr`) et `robot$wb-sonde-ci` (lecture et poussée sur `wb-sonde`) ; l'image `wb-sonde/signee:1.0` est signée par une **paire de clés de test** propre aux témoins ;
  - sur `runner02` : les identifiants des deux robots et la clé publique de test dans `/etc/workbook/sonde-registre/` (root, 700), la clé privée de test dans `/var/lib/workbook/temoins-m13/`, et la sonde **`/usr/local/sbin/wb-sonde-registre`**. `sudo wb-sonde-registre` fait, comme une CI : un tirage privé avec le robot, un tirage anonyme du projet public, un tirage par le cache `dockerhub`, une construction et une poussée, et une vérification Cosign de `wb-sonde/signee:1.0` (Cosign lancé en conteneur, image tirée par le cache `ghcr`). C'est ton premier instrument de reproduction : lis-la, elle ne contient aucune cause.

  Les témoins restent après le palier ; tu les supprimes au mini-projet, toi-même, en vérifiant deux fois ce que tu supprimes.
- **E22 agit sur `reg01`** (Harbor de production) : le script refuse de l'injecter si la dernière sauvegarde de E15 a plus de 26 h ou a échoué. Les autres pannes agissent sur les témoins, sur `runner02` et sur la configuration de Harbor (endpoints, quotas, règles), jamais sur les images de `medisphere`. Jamais sur `pbs01`, `pve01` ou une VM hors du pool `lab`. Toute valeur modifiée est sauvegardée avant, dans `/var/lib/workbook/` de l'hôte touché ou `~/.local/state/workbook/` de `adm01`.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 13 19 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (MR) : heure, hypothèse, commande, résultat observé, conclusion. Chaque panne se termine par un runbook (RB-133 à RB-135) ou un ajout à un runbook existant.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours pour E22** : si Harbor ne démarre plus, tu travailles directement sur `reg01` (SSH, `docker`, `journalctl`). Vérifie **avant** d'injecter que tu y entres par la console série (`qm terminal 1013` depuis `pve01`) au cas où une saturation de disque gênerait ta session SSH, et que tu sais où est la dernière sauvegarde (E15, RB-131).

---

### M13-E19 — Panne : impossible de tirer l'image  `BF` `★★`

> **Ticket INC-4031** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, des jobs qui n'arrivent plus à tirer une image privée, une image « publique » qui ne l'est plus, un `runner02` qui ne fait plus confiance au registre, ou une nouvelle image de base qui ne passe pas alors que les anciennes passent.)* Lucas propose de « mettre le projet en public pour débloquer » : n'en fais rien.

**Objectifs pédagogiques**
- Remonter d'un échec de tirage à son étage : TLS du client, service de jetons, identité (robot, expiration, droits), visibilité du projet, cache et registre amont.
- Lire les échanges réels (`WWW-Authenticate`, `/service/token`, codes HTTP) plutôt que le message reformulé du client.
- Réparer à la racine, par le code, sans élargir les droits.

**Prérequis** : M13-E03, M13-E04 ; `lab/bin/check 13 19` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les robots, projets et endpoints des témoins ont été créés par le script, pas par ton code de configuration : ici, une réparation dans l'interface ou par l'API est acceptée, et tu écris dans ton journal ce que tu aurais changé dans le code s'il s'agissait d'un objet de production. Le service de jetons de Harbor est `https://registry.par1.medisphere.internal/service/token` ; le journal du cœur est `/var/log/harbor/core.log` sur `reg01`, celui du proxy `/var/log/harbor/proxy.log`.

**Injection** : `lab/bin/break 13 19` (4 variantes).

**Travail demandé**
1. Reproduis avec `sudo wb-sonde-registre` sur `runner02`, puis depuis `adm01` avec `skopeo inspect` (et la même identité si tu peux l'obtenir). Le problème est-il propre à `runner02` ?
2. Rejoue l'échange à la main avec `curl` : requête anonyme vers `/v2/`, lecture de `WWW-Authenticate`, demande de jeton pour la portée exacte, requête du manifeste avec le jeton. À quelle étape cela échoue-t-il, avec quel code ?
3. Cherche la cause côté Harbor (état du robot, visibilité et membres du projet, état de l'endpoint du cache, journaux) ou côté client (magasin de certificats, configuration de Docker).
4. Répare sans élargir aucun droit et sans désactiver aucune vérification TLS. Vérifie avec la sonde.
5. Écris `RB-133 — Tirage ou publication en échec` (section « tirage ») dans `docs/registre/runbooks/` : l'arbre de décision par message d'erreur.

**Critères de réussite**
- [ ] `sudo wb-sonde-registre` est entièrement vert sur `runner02`.
- [ ] `robot$wb-sonde-tirage` est actif et non expiré ; `wb-sonde` est privé, `wb-sonde-public` public ; l'endpoint du cache `dockerhub` est `healthy`.
- [ ] `runner02` vérifie le certificat de Harbor avec la racine MédiSphère (aucun registre `insecure` dans la configuration de Docker).
- [ ] Ton journal contient l'échange `curl` qui localise l'échec ; RB-133 est publié.

**Vérification** : `lab/bin/check 13 19`

<details><summary>Indice 1</summary>

`docker pull` dit « unauthorized » dans plusieurs cas très différents. `curl -sv https://registry.par1.medisphere.internal/v2/` puis `curl -s -u '<robot>:<secret>' 'https://registry.par1.medisphere.internal/service/token?service=harbor-registry&scope=repository:<projet>/<dépôt>:pull'` : décode la partie centrale du jeton obtenu (base64) et regarde la liste `access` — est-elle vide ?
</details>

<details><summary>Indice 2</summary>

Dans Harbor : la liste des robots indique la date d'expiration et l'état ; un projet a une case « Public » ; un endpoint a un état et un bouton de test. Côté `runner02` : `openssl s_client -connect registry.par1.medisphere.internal:443 -verify_return_error` et le contenu de `/etc/ssl/certs/` et `/etc/docker/certs.d/`. Le démon Docker lit les autorités de confiance **à son démarrage**.
</details>

<details><summary>Indice 3</summary>

Un cache de Harbor sert ce qu'il a déjà, même quand le registre amont est injoignable : si seules les images « nouvelles » échouent, regarde l'endpoint amont du cache (son état, son URL, l'identité qu'il présente au registre public) et le journal du cœur, pas le client.
</details>

**Pour aller plus loin** : écris dans RB-133 le tableau « message → étage » pour `docker`, `skopeo`, `crane` et containerd (module 14, `crictl pull`).

---

### M13-E20 — Panne : la publication de l'image échoue  `BF` `★★★`

> **Ticket INC-4032** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : le job de publication échoue au moment du `push`, après une construction réussie, avec un message différent selon le cas.)* On a une mise en production prévue cet après-midi. Ne touche ni aux politiques de `medisphere`, ni à l'immuabilité des versions : Sophie y tient.

**Objectifs pédagogiques**
- Distinguer les refus de publication : quota, immuabilité, droits de l'identité, TLS et temps, et lire où Harbor les décide.
- Corriger la bonne chose : la règle mal écrite, la limite mal dimensionnée, le droit manquant, l'horloge — sans affaiblir une politique légitime.
- Comprendre ce qu'une poussée « interrompue » laisse derrière elle (blobs orphelins, téléversements, ramasse-miettes).

**Prérequis** : M13-E09, M13-E10 (quotas, immuabilité) ; `lab/bin/check 13 20` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la sonde pousse `wb-sonde/publication:courant`, une étiquette **roulante** voulue (elle désigne toujours la dernière construction de la sonde) ; elle n'est pas une version. Le projet `wb-sonde` n'a ni quota défini, ni règle d'immuabilité dans son état sain. `runner02` se synchronise sur la passerelle de son VLAN (chrony, M00).

**Injection** : `lab/bin/break 13 20` (4 variantes).

**Travail demandé**
1. Reproduis avec `sudo wb-sonde-registre` sur `runner02` ; note le message complet de la poussée. À quelle étape de la poussée (vérification des blobs, téléversement, manifeste) l'échec survient-il ? Relance avec plus de détail si le message est vague.
2. Formule l'hypothèse à partir du message, puis vérifie-la dans Harbor (configuration du projet et du robot) ou sur `runner02`.
3. Corrige à la racine. Si la cause est une règle ou une limite, décide de sa bonne valeur et écris pourquoi ; si c'est une identité, donne exactement le droit qui manque.
4. Vérifie la sonde, puis regarde ce que les poussées échouées ont laissé dans le projet (artefacts sans étiquette, occupation) et ce que fera le prochain ramasse-miettes.
5. Complète RB-133 (section « publication »).

**Critères de réussite**
- [ ] `sudo wb-sonde-registre` est entièrement vert.
- [ ] `wb-sonde` n'a aucune règle d'immuabilité qui vise l'étiquette `courant` ; son quota (s'il en a un) laisse au moins 1 Gio de marge.
- [ ] `robot$wb-sonde-ci` a le droit de pousser sur `wb-sonde` et rien de plus.
- [ ] L'horloge de `runner02` est synchronisée (écart inférieur à une seconde) ; les règles d'immuabilité et la sécurité de `medisphere` sont inchangées.
- [ ] RB-133 contient la section « publication ».

**Vérification** : `lab/bin/check 13 20`

<details><summary>Indice 1</summary>

Les messages de Harbor sont précis quand on les lit en entier : un quota cite les chiffres (usage, ajout, limite), l'immuabilité cite l'étiquette, un refus de droit répond `denied` ou `unauthorized` **au moment du jeton de poussée**. Un message TLS qui parle de date n'est pas un problème de registre.
</details>

<details><summary>Indice 2</summary>

Dans Harbor : *Configuration* et *Résumé* du projet (quota), *Policy → Tag immutability*, détail du robot (permissions par projet). Sur `runner02` : `timedatectl`, `chronyc tracking`, `chronyc sources`, et la date de fin du certificat présenté par le registre.
</details>

<details><summary>Indice 3</summary>

Une règle d'immuabilité se lit comme un filtre : « dépôts qui correspondent à … ET étiquettes qui correspondent à … ». La politique de MédiSphère (E10) vise les **versions**. Pour le quota, le chiffre utile n'est pas l'occupation affichée, c'est ce qu'il faut pour une poussée de plus.
</details>

**Pour aller plus loin** : provoque volontairement une poussée interrompue (coupure réseau pendant le téléversement) et suis la vie des fichiers dans `/data/registry/docker/registry/v2/repositories/<dépôt>/_uploads/` jusqu'au nettoyage (`upload_purging` de `harbor.yml`).

---

### M13-E21 — Panne : la signature n'est plus reconnue  `BF` `★★★`

> **Ticket INC-4033** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> La vérification de signature avant déploiement échoue sur une image qu'on déploie depuis des semaines : « no matching signatures » ou « no signatures found » selon les essais. Personne n'a touché à l'image, paraît-il. Sophie demande qu'on ne contourne **rien** : pas de déploiement sans vérification, pas de re-signature d'une image dont on ne sait pas d'où elle vient.

**Objectifs pédagogiques**
- Comprendre ce que vérifie `cosign verify` : une signature par **digest**, rattachée comme référent OCI, produite par **une** clé, lue par un client qui connaît ce format.
- Diagnostiquer avec `cosign tree`, l'API des référents, les accessoires de Harbor et son journal d'audit.
- Rétablir la confiance proprement : savoir quand restaurer, quand re-signer, et ce qu'il faut prouver avant de re-signer.

**Prérequis** : M13-E07, M13-E08, M13-E14 ; `lab/bin/check 13 21` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la sonde vérifie `wb-sonde/signee:1.0` avec la clé publique **de test** des témoins (`/etc/workbook/sonde-registre/cosign.pub`), sans journal de transparence, avec l'image Cosign indiquée par la variable `COSIGN_IMAGE` de `/etc/workbook/sonde-registre/sonde.conf` (comme une variable de gabarit de CI). Le digest signé à la création des témoins est noté dans `/etc/workbook/sonde-registre/temoins.txt`, comme un pipeline note le digest qu'il a produit. La clé privée de test est sur `runner02` dans `/var/lib/workbook/temoins-m13/` : tu as le droit de t'en servir **pour les témoins seulement**, et seulement après avoir établi que l'image à signer est bien celle qui avait été produite.

**Injection** : `lab/bin/break 13 21` (4 variantes).

**Travail demandé**
1. Reproduis : `sudo wb-sonde-registre` puis, depuis `adm01`, `cosign verify` de la même image avec la même clé (Cosign 3.1 installé en E07). Les deux échouent-ils de la même façon ?
2. Établis les faits, sans rien modifier : digest actuel de l'étiquette `1.0`, digest attendu, signatures attachées à chacun (`cosign tree`, onglet des accessoires de Harbor, API `referrers`), clé qui a produit la signature, version de Cosign utilisée par la sonde.
3. Consulte le journal d'audit de Harbor (projet `wb-sonde`) : qui a fait quoi, quand ?
4. Rétablis une vérification réussie par le **bon** correctif : restaurer ce qui a été changé, ou re-signer — et dans ce cas, écris dans ton journal la preuve que le digest re-signé est celui qui avait été produit.
5. Écris `RB-134 — Signature non reconnue` : l'arbre de décision, et la règle « on ne re-signe jamais pour faire passer un déploiement ».

**Critères de réussite**
- [ ] `sudo wb-sonde-registre` est entièrement vert.
- [ ] `wb-sonde/signee:1.0` désigne le digest noté dans `temoins.txt` et porte une signature vérifiable par la clé de test.
- [ ] La sonde utilise une image Cosign 3.x et la clé publique de test d'origine.
- [ ] Ton journal contient les faits de l'étape 2 et l'entrée du journal d'audit ; RB-134 est publié.

**Vérification** : `lab/bin/check 13 21`

<details><summary>Indice 1</summary>

« no matching signatures » et « no signatures found » ne disent pas la même chose : dans le premier cas Cosign a trouvé des signatures mais aucune ne se vérifie avec la clé donnée ; dans le second il n'en a trouvé aucune **là où il les cherche**. Compare l'empreinte de la clé publique avec celle des témoins (`cosign public-key`, ou `sha256sum`).
</details>

<details><summary>Indice 2</summary>

`cosign tree registry.par1.medisphere.internal/wb-sonde/signee:1.0` résout l'étiquette en digest puis liste ce qui y est attaché. Fais-le aussi avec le digest de `temoins.txt`. Cosign 2 et Cosign 3 ne rangent pas leurs signatures au même endroit par défaut (étiquette `sha256-<digest>.sig` ou référent OCI 1.1).
</details>

<details><summary>Indice 3</summary>

Le journal d'audit de Harbor (*Logs* du projet, API `/projects/{nom}/auditlog-exts` ou `/audit-logs`) trace les poussées et les suppressions d'artefacts et d'étiquettes, avec l'identité. Une étiquette se replace sur un digest existant sans rien pousser (API `…/artifacts/{digest}/tags`).
</details>

**Pour aller plus loin** : écris la procédure de rotation planifiée de la clé MédiSphère (période de recouvrement où le consommateur accepte deux clés, re-signature des images en service, retrait de l'ancienne clé) et teste-la sur les témoins.

---

### M13-E22 — Panne : Harbor ne démarre plus  `BF` `★★★`

> **Ticket INC-4034** — *De : Nadia Roussel* — *Priorité : critique*
> Après la maintenance de cette nuit sur `reg01`, Harbor ne revient pas : les pipelines échouent tous, l'interface ne répond pas ou renvoie une erreur. Karim est injoignable et a laissé un mot : « j'ai juste redémarré Harbor ». La sauvegarde de cette nuit est là si besoin, mais je préfère qu'on ne restaure que si c'est vraiment nécessaire. *(Des précisions s'affichent à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer un service multi-conteneurs piloté par systemd et Docker Compose : unité, `docker compose ps`, état et journaux de chaque conteneur, dépendances entre composants.
- Reconnaître les causes classiques : disque de données plein, droits des données de PostgreSQL, fichiers de certificat illisibles, configuration générée absente ou incohérente avec `harbor.yml`.
- Choisir entre réparer et restaurer, et le justifier.

**Prérequis** : M13-E02, M13-E15 (sauvegarde et RB-131), M13-E16 (procédure, `prepare`) ; `lab/bin/check 13 22` vert avant l'injection ; sauvegarde de moins de 26 h.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `harbor.service` lance `docker compose up -d` dans le dossier d'installation (et `down` à l'arrêt) ; le fichier `docker-compose.yml` et le dossier `common/config/` sont **générés** par `prepare` à partir de `harbor.yml` ; le rôle `harbor` rend `harbor.yml` et relance `prepare` quand il change. Les conteneurs journalisent par le conteneur `harbor-log` dans `/var/log/harbor/` ; un conteneur qui ne démarre pas journalise aussi dans `docker logs <conteneur>`.

**Injection** : `lab/bin/break 13 22` (4 variantes).

> ⚠️ **Attention** : c'est le registre de production. Ne lance ni `docker compose down -v`, ni `rm` dans `/data`, ni `install.sh` « pour voir », ni restauration avant d'avoir une hypothèse étayée. Si tu dois supprimer un fichier pour libérer de la place, sache d'abord **ce qu'il est** et qui l'a posé. Si tu restaures, suis RB-131 et note l'heure de la sauvegarde utilisée.

**Travail demandé**
1. Constate : `systemctl status harbor`, `docker compose ps -a` dans le dossier d'installation, `/api/v2.0/health` depuis `adm01`. Quels conteneurs tournent, lesquels redémarrent en boucle, lesquels n'existent pas ?
2. Remonte au premier composant en échec (les autres dépendent souvent de lui) : ses journaux, son état, ses montages.
3. Trouve la cause racine ; distingue ce que Karim a pu faire de ce que tu constates.
4. Répare de la manière la plus sûre et la plus durable (par le rôle si la configuration est en cause). Vérifie : santé `healthy`, tirage et poussée depuis `runner02`, signatures, dernière réplication relancée.
5. Écris `RB-135 — Harbor ne démarre plus` et ajoute à `ms-verif-registre` (E16) le contrôle qui t'aurait prévenu **avant** la panne, s'il manquait.

**Critères de réussite**
- [ ] `/api/v2.0/health` rend `healthy` pour tous les composants ; tous les conteneurs de Harbor tournent sans redémarrage en boucle.
- [ ] `/data` est occupé à moins de 85 % ; les données de PostgreSQL appartiennent à l'utilisateur de la base (uid 999) ; la clé et le certificat du proxy sont lisibles par l'utilisateur du proxy.
- [ ] `harbor.yml` est identique à ce que rend le rôle (exécution `--check --diff` sans changement) et la configuration générée existe.
- [ ] RB-135 est publié.

**Vérification** : `lab/bin/check 13 22`

<details><summary>Indice 1</summary>

`docker compose ps -a` et `docker inspect --format '{{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}' <conteneur>`. Harbor démarre la base, Valkey et le registre d'abord ; le cœur attend la base ; le proxy attend le cœur et le portail. Si l'unité systemd elle-même échoue, `journalctl -u harbor -n 50` montre l'erreur de `docker compose` avant tout conteneur.
</details>

<details><summary>Indice 2</summary>

`df -h /data`, `du -xsh /data/* | sort -h`, `ls -ln /data/database /data/secret/cert`, `docker logs harbor-db`, `docker logs nginx`. Dans le dossier d'installation, compare la date de `harbor.yml`, de `docker-compose.yml` et de `common/config/`.
</details>

<details><summary>Indice 3</summary>

`prepare` commence par **effacer** la configuration générée, puis lit et valide `harbor.yml` : si la validation échoue, il ne reste plus rien à démarrer. Le rôle Ansible sait rendre un `harbor.yml` correct et relancer `prepare` ; un `--check --diff` te montre d'abord ce qu'il changerait.
</details>

**Pour aller plus loin** : chronomètre une restauration complète de `reg01` sur `reg02` (RB-131) et compare au temps de ta réparation : à partir de quelle durée de panne la restauration devient-elle le bon choix ?

---

### M13-E23 — Sous le capot : l'API de distribution OCI  `LAB` `★★★`

> **Ticket PLAT-1437** — *De : Karim Benali*
> Au module 14, containerd tirera nos images sans Docker, à travers le cache, avec un jeton. Le jour où ça casse, je veux que quelqu'un sache ce qui passe vraiment sur le fil. Fais-le une fois à la main : jeton, manifeste, index, blobs, référents. Et recalcule toi-même un digest : je veux que tu voies pourquoi une image « signée par digest » ne peut pas changer sous nos pieds.

**Objectifs pédagogiques**
- Dérouler à la main l'authentification du *Distribution Spec* (défi `WWW-Authenticate`, jeton porteur, portée) contre Harbor.
- Lire et distinguer index, manifeste d'image, configuration et couches ; négocier les types de média par `Accept`.
- Recalculer un digest, et utiliser l'API des **référents** (OCI 1.1) pour trouver signatures et attestations ; comparer avec ORAS.

**Prérequis** : M12-E04 (images OCI), M13-E07, M13-E08.
**Durée indicative** : 2 h.

**Contexte technique**
- Harbor implémente l'API `/v2/` de l'*OCI Distribution Specification* 1.1, référents compris (`GET /v2/<nom>/referrers/<digest>`). Le service de jetons est `https://registry.par1.medisphere.internal/service/token`, service `harbor-registry`.
- Identité : le robot `robot$medisphere+ci` (lecture suffisante ; secret depuis Vault, dans une variable d'environnement le temps de l'exercice, jamais dans l'historique du shell) ou ton compte personnel.
- Outils : `curl`, `jq`, `sha256sum` ; ORAS 1.3 (binaire officiel, somme vérifiée) sur `adm01`.
- Image d'étude : la dernière version `v*` de `medisphere/mediagenda-api` (index multi-architecture si tu l'as construite ainsi en M12).

**Travail demandé**
1. **Le défi.** `curl -sI https://registry.par1.medisphere.internal/v2/` : lis `WWW-Authenticate`. Demande un jeton au *realm* indiqué pour la portée `repository:medisphere/mediagenda-api:pull`, avec puis sans identité. Décode le jeton : qui l'a signé, pour combien de temps, quels droits ? Que vaut la liste des droits pour une portée que l'identité n'a pas ?
2. **Le manifeste.** Avec le jeton : `GET /v2/medisphere/mediagenda-api/manifests/<étiquette>` en envoyant successivement un `Accept` d'index OCI, de manifeste OCI, de manifeste Docker v2, puis aucun. Note `Content-Type` et `Docker-Content-Digest` à chaque fois. Si c'est un index, descends vers le manifeste `linux/amd64`.
3. **Le digest.** Enregistre le corps **brut** de la réponse et recalcule son SHA-256 : il doit être égal à `Docker-Content-Digest`. Reformate le JSON (`jq .`), recalcule : pourquoi est-ce différent, et qu'en déduis-tu sur la signature « par digest » ?
4. **Les blobs.** Récupère le blob de configuration (`GET /v2/<nom>/blobs/<digest>`, suis la redirection éventuelle) et lis-y l'utilisateur, la commande, les étiquettes (`org.opencontainers.image.*`) et l'historique. Récupère la plus petite couche et vérifie son digest. Que se passe-t-il avec `HEAD` ?
5. **Les référents.** `GET /v2/medisphere/mediagenda-api/referrers/<digest du manifeste>` : liste les artefacts attachés (signature, attestations SBOM et provenance), leur `artifactType`, et filtre par `artifactType`. Compare avec `oras discover` et `cosign tree`. Récupère le *bundle* de signature avec `oras manifest fetch` puis son blob : qu'y a-t-il dedans (message signé, clé, absence d'entrée Rekor) ?
6. **Ce qu'on ne peut pas faire.** Essaie `GET /v2/_catalog` et une requête `DELETE` sur un manifeste avec le jeton de lecture. Explique les réponses.
7. Consigne la démarche dans `docs/registre/notes/api-oci.md` : les requêtes, les en-têtes clés, le digest de l'image étudiée et celui recalculé, les types de média rencontrés, et un schéma « étiquette → index → manifeste → configuration et couches ← référents ».

**Critères de réussite**
- [ ] `docs/registre/notes/api-oci.md` est publié et cite le digest **actuel** d'une version `v*` de `medisphere/mediagenda-api`, avec la commande qui l'a recalculé.
- [ ] La note contient la réponse de l'API des référents (types d'artefacts trouvés) et l'explication de l'échec du digest après reformatage.
- [ ] ORAS 1.3 est installé sur `adm01`.

**Vérification** : `lab/bin/check 13 23`

<details><summary>Indice 1</summary>

L'en-tête ressemble à `Bearer realm="…",service="…"` : la demande de jeton est un `GET` sur le *realm* avec les paramètres `service` et `scope`. Le jeton se passe ensuite en `Authorization: Bearer <jeton>`. Un JWT est trois parties en base64url séparées par des points.
</details>

<details><summary>Indice 2</summary>

`curl -s -o corps.json -D entetes.txt` garde le corps tel quel et les en-têtes à part. Types de média : `application/vnd.oci.image.index.v1+json`, `application/vnd.oci.image.manifest.v1+json`, `application/vnd.docker.distribution.manifest.v2+json`, `application/vnd.docker.distribution.manifest.list.v2+json`.
</details>

<details><summary>Indice 3</summary>

Les blobs peuvent être servis par une redirection (`curl -L`). Pour les référents, l'en-tête `Accept` attendu est celui d'un index OCI ; le paramètre `artifactType` filtre la liste.
</details>

**Pour aller plus loin** : refais l'étape 2 contre le cache `dockerhub` pour une image jamais tirée, et observe dans `/var/log/harbor/core.log` la requête que Harbor fait au registre amont ; lis la section *Pulling manifests* de la spécification.

---

### M13-E24 — Questions expert : supply chain  `Q` `★★★`

> **Ticket PLAT-1438** — *De : Claire Morel*
> Avant la revue du module, Karim te pose les questions qu'il pose en entretien. Réponds par écrit, en argumentant, comme si tu devais convaincre un auditeur.

**Prérequis** : tout le module jusqu'à E23.
**Durée indicative** : 1 h 30.

**Questions**
1. Une image est signée par Cosign avec la clé MédiSphère, son SBOM est attesté, elle passe l'analyse de Trivy. Cite trois attaques de la chaîne d'approvisionnement que ces trois garanties n'arrêtent **pas**, et pour chacune le contrôle qui l'arrêterait.
2. L'incident Trivy de mars 2026 : un pipeline qui utilisait `aquasecurity/trivy-action@v0.35.0` était-il protégé ? Et `@<sha de commit>` ? Et le binaire 0.69.4 vérifié par sa somme SHA-256 publiée à côté ? Qu'est-ce qui distingue une **somme** d'une **signature avec identité** (`cosign verify-blob --certificate-identity`) ?
3. Pourquoi signer **par digest** et jamais par étiquette ? Donne un scénario concret où une signature par étiquette laisse passer une image malveillante, puis explique pourquoi l'immuabilité des étiquettes ne suffit pas à elle seule.
4. Cosign 3 range la signature comme **référent OCI 1.1** au lieu d'une étiquette `sha256-<digest>.sig`. Quelles conséquences pour : la réplication vers un registre ancien, le ramasse-miettes et les règles de rétention, un client Cosign 2, les outils qui listent les étiquettes ?
5. Signature sans clé (Fulcio + Rekor publics) ou avec clé : compare la gestion de la compromission (clé volée, compte OIDC volé), la dépendance à Internet, la fuite d'information, la preuve d'horodatage. Pourquoi MédiSphère vérifie-t-elle avec `--insecure-ignore-tlog`, et qu'est-ce qu'elle perd ?
6. SLSA : à quel niveau de construction (*Build L1, L2, L3*) se situe la chaîne de E09, et que faudrait-il pour monter d'un niveau ? Qu'apporte la provenance `mode=max` de BuildKit et que ne prouve-t-elle pas ?
7. Un SBOM SPDX produit par Syft sur l'image finale et un SBOM produit à partir du `uv.lock` : lequel croire en cas d'alerte comme celle de E18, et pourquoi pas toujours le même ? Cite deux composants qu'un SBOM d'image manque souvent.
8. Le cache `dockerhub` de Harbor : quels risques ajoute-t-il (empoisonnement, image retirée en amont, étiquette déplacée en amont) et comment les réduire (épinglage par digest, `proxy_cache_local_on_not_found`, réplication *pull* contrôlée vers `bibliotheque`) ?
9. La politique « Cosign obligatoire » de Harbor et une politique d'admission Kubernetes `verifyImages` (module 26) : pourquoi la première ne suffit-elle pas en production, et pourquoi garder les deux ?
10. Harbor perd `/data/secret/keys/secretkey` mais garde sa base. Qu'est-ce qui marche encore, qu'est-ce qui ne marche plus, comment le découvre-t-on, et comment l'éviter ?
11. Renovate propose une MR qui change le digest de `python:3.13-slim-trixie` sans changer l'étiquette. Comment décider de la fusionner automatiquement ou non ? Que vérifier dans le pipeline pour que l'automatisation n'ouvre pas une porte (référence amont, signature de l'éditeur, analyse) ?
12. Un auditeur demande la liste de toutes les images qui ont tourné en production chez MédiSphère le 3 mars, avec leur SBOM. Que faut-il conserver, où, combien de temps, et que doivent laisser passer les règles de rétention et le ramasse-miettes ?

**Vérification** : auto-évaluation avec le corrigé (réponses argumentées).
