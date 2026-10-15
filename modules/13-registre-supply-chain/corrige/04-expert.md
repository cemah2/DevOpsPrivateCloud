# Module 13 — Corrigé du palier 4 : Expert

> ⚠️ Corrigé — à lire après avoir cherché. Il révèle la cause de chaque variante des pannes.

**Points non testés en conditions réelles** (signale tes retours) :
- comportement d'un **cache** Harbor dont l'amont refuse l'authentification : les images déjà en cache sont attendues servies (le contrôleur du cache consulte d'abord la copie locale quand l'amont échoue), les autres en erreur ; message exact côté client à relever (`manifest unknown`, `500` ou `404` selon la version) ;
- mise à jour d'un robot système par `PUT /api/v2.0/robots/{id}` avec l'objet complet (durée ramenée à 1 jour pour l'expirer, `disable`) et effet immédiat sur les jetons ;
- image `ghcr.io/sigstore/cosign/cosign:v2.5.0` tirée par le cache `ghcr` et son comportement face à une signature Cosign 3 en référent OCI (attendu : `no signatures found`) ;
- signature des témoins avec `--signing-config` pointant sur un fichier ne contenant que le type de média (`application/vnd.dev.sigstore.signingconfig.v0.2+json`) : à aligner sur le `signing-config.json` produit en M13-E07 si le type diffère ;
- démarrage de `harbor-db` avec un volume `/data` saturé (attendu : échec d'écriture de `postmaster.pid` ou des journaux d'écriture) ; XFS (`/data`, rôle `harbor`) n'a pas de réserve pour root ;
- message de `docker compose` quand les fichiers `env_file` de `common/config` manquent (attendu : `env file … not found`).

**Rappel des témoins** (créés par le script de panne, voir l'en-tête de `enonce/04-expert.md`) : projets `wb-sonde` et `wb-sonde-public`, robots système `robot$wb-sonde-tirage` et `robot$wb-sonde-ci`, image signée `wb-sonde/signee:1.0` (paire de clés de test sur `runner02`), sonde `/usr/local/sbin/wb-sonde-registre`. Runbooks : [RB-133](fichiers/M13-E19/medisphere/docs/registre/runbooks/RB-133-tirage-ou-publication-en-echec.md) (E19, E20), [RB-134](fichiers/M13-E21/medisphere/docs/registre/runbooks/RB-134-signature-non-reconnue.md) (E21), [RB-135](fichiers/M13-E22/medisphere/docs/registre/runbooks/RB-135-harbor-ne-demarre-plus.md) (E22).

---

### M13-E19 — Panne : impossible de tirer l'image

**Démarche de diagnostic**

*Symptômes* : selon la variante, échec des tirages privés (et par le cache), du tirage anonyme, de **tous** les tirages depuis `runner02` seulement, ou des seules images publiques « nouvelles ».

*Hypothèses* : identité (robot désactivé, expiré, droits) ; visibilité du projet ; confiance TLS du client ; cache et amont ; panne du registre (exclue si `/api/v2.0/health` est `healthy` et que `adm01` tire).

**Étape 1 — Reproduire et situer.**

```
admin@runner02:~$ sudo wb-sonde-registre
admin@adm01:~$ skopeo inspect docker://registry.par1.medisphere.internal/wb-sonde-public/temoin:1.0     # anonyme ? (sans --creds)
admin@adm01:~$ curl -s https://registry.par1.medisphere.internal/api/v2.0/health | jq -r .status
```

**Étape 2 — Rejouer l'échange** (RB-133, section 3) : défi `WWW-Authenticate`, demande de jeton pour la portée exacte, puis manifeste.

**Variante 1 — robot désactivé ou expiré.** La sonde échoue sur `tirage` et `cache` (même robot), `public` passe. À la main, la demande de jeton avec les identifiants du robot répond `401` (ou un jeton sans droits) ; dans Harbor (*Administration → Robot Accounts*), `robot$wb-sonde-tirage` apparaît **désactivé**, ou avec une date d'expiration dépassée (durée ramenée à 1 jour s'il avait plus de deux jours). Le journal d'audit et `core.log` montrent l'échec d'authentification. Correctif : réactiver le robot ou prolonger sa durée (pour un robot de production : par le code, `duration` dans `registre/robots.tf`, et la rotation du secret si l'expiration était voulue). Prévention : dates d'expiration dans le registre des secrets, alerte à J-30, sonde qui teste les identifiants réels.

**Variante 2 — projet repassé en privé.** Seule l'étape `public` échoue : `unauthorized to access repository: wb-sonde-public/temoin, action: pull`. Le jeton anonyme est délivré (`200`) mais sa liste `access` est **vide**. *Projets → wb-sonde-public → Configuration* : « Public » décochée. Correctif : la recocher **si** le projet doit être public (ici oui, c'est son contrat) — et non « tout passer en public » comme le propose Lucas. Pour un projet de production, la visibilité est dans le code (`public` de `harbor_project`) : la dérive est visible au prochain `tofu plan`.

**Variante 3 — racine MédiSphère retirée de `runner02`.** Tout échoue depuis `runner02`, tout passe depuis `adm01` : `x509: certificate signed by unknown authority`.

```
admin@runner02:~$ echo | openssl s_client -connect registry.par1.medisphere.internal:443 -verify_return_error 2>&1 | grep -E 'verify|Verification'
admin@runner02:~$ ls -l /usr/local/share/ca-certificates/ /etc/docker/certs.d/registry.par1.medisphere.internal/ 2>&1
admin@runner02:~$ systemctl show -p ActiveEnterTimestamp docker
```

Le fichier de la racine a disparu (et celui de `certs.d`), le magasin a été régénéré, et Docker a redémarré cette nuit : le démon lit les autorités de confiance **à son démarrage** (un démon resté démarré aurait continué de fonctionner, ce qui rend ce genre de panne différé et trompeur). Correctif : **repasser le rôle** qui installe la racine (`ca_lab`) sur `runner02`, puis `sudo systemctl restart docker` hors job en cours ; jamais `insecure-registries`. Le runner GitLab était aussi touché (TLS vers `git01`) : `gitlab-runner verify`.

**Variante 4 — identifiants invalides sur l'endpoint amont du cache.** Les images déjà en cache (`busybox:1.37`) passent ; l'image nouvelle du ticket échoue. `docker pull` ou `skopeo inspect` de cette image : erreur côté registre (manifeste introuvable ou erreur 5xx selon la version). `/var/log/harbor/core.log` : échec d'authentification auprès de Docker Hub. *Administration → Registries → dockerhub* : un identifiant `medisphere-ci` et un jeton y ont été posés, l'état est `unhealthy` (le test de connexion échoue). Correctif : retirer ces identifiants (cache anonyme, choix de M13-E04) ou poser un vrai jeton en lecture — **par le code** (`caches.tf`, variables `dockerhub_*`), jamais à la main. Comprendre pourquoi les anciennes images passent : un cache sert sa copie locale quand l'amont ne répond pas, ce qui masque la panne jusqu'à la première image nouvelle.

**Clôture** : sonde verte, `lab/bin/check 13 19`, `lab/bin/break 13 19 --annuler`, RB-133 (section tirage).

**Explications**

Le protocole sépare l'**authentification** (service de jetons de Harbor, `/service/token`) de l'**autorisation** (portée du jeton) et du **service** (le registre, qui refuse un jeton sans l'action demandée). Un même mot (« unauthorized ») sort des trois étages : seul l'échange à la main dit lequel. Côté client, la confiance TLS est vérifiée avant même la première requête. Côté cache, Harbor joue le client d'un autre registre avec sa propre identité : une panne de cette identité ne touche que ce qui doit être cherché en amont.

**Pièges classiques**
- Rendre le projet public, ou ajouter `insecure-registries`, « pour débloquer » : la panne disparaît, le risque reste.
- Recréer le robot au lieu de le réactiver : nouveau secret, toutes les variables de CI à changer.
- Tester depuis `adm01` avec son compte personnel administrateur et conclure « ça marche ».

**En production chez MédiSphère**
Sonde fonctionnelle (vrais identifiants, vraie image) depuis chaque population de clients (`runner02`, nœuds Kubernetes au M14) ; registre des secrets avec échéances ; racine MédiSphère distribuée par un seul rôle ; alerte sur l'état des endpoints de cache.

---

### M13-E20 — Panne : la publication de l'image échoue

**Démarche de diagnostic**

*Symptômes* : la construction réussit, la poussée échoue ; le message diffère selon la variante.

*Hypothèses* : quota ; immuabilité ; droits du robot ; TLS et heure du client ; registre en panne (exclu par la santé).

**Étape 1 — Le message complet.**

```
admin@runner02:~$ sudo wb-sonde-registre --etape publication
```

**Variante 1 — quota plein.** `denied: adding <N> of storage resource, which when updated to current usage of <U> will exceed the configured upper limit of <L>.` (forme du message de quota de Harbor). *Projet wb-sonde → Résumé* : quota égal à l'occupation. Les blobs déjà présents (couches communes) passent, le premier blob **nouveau** échoue. Correctif : décider d'une limite (ici, retirer la limite ou poser une valeur avec marge, ≥ 1 Gio), par le code pour un projet de production (`storage_quota`) ; regarder aussi ce qui occupe (artefacts sans étiquette des poussées roulantes, que la rétention et le ramasse-miettes de M13-E10 doivent nettoyer).

**Variante 2 — immuabilité trop large.** `unknown: … configured as immutable, cannot be updated` (ou `immutable` dans le message). *Projet → Policy → Tag immutability* : une règle « dépôts `**` / étiquettes `**` » — tout le projet est figé, y compris l'étiquette roulante `courant`. Correctif : la règle doit viser les **versions** (`v*`, politique de E10) ; supprimer la règle trop large et, si besoin, poser la bonne. Ne jamais « débloquer » une version (`v*`) immuable : on publie la version suivante.

**Variante 3 — robot sans droit de poussée.** `denied: requested access to the resource is denied` (ou `unauthorized` lors de la demande du jeton de poussée). Le jeton demandé pour `pull,push` ne contient que `pull` :

```
admin@adm01:~$ curl -s -u 'robot$wb-sonde-ci:<SECRET>' 'https://registry.par1.medisphere.internal/service/token?service=harbor-registry&scope=repository:wb-sonde/publication:pull,push' \
    | jq -r .token | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq .access
```

(Le secret est sur `runner02`, dans `/etc/workbook/sonde-registre/ci/config.json`, encodé en base64 avec le nom : ne l'affiche pas, passe-le par un fichier.) Détail du robot dans Harbor : permission `repository:push` retirée sur `wb-sonde`. Correctif : rendre **exactement** ce droit, rien de plus.

**Variante 4 — horloge de `runner02` en avance.** `x509: certificate has expired or is not yet valid: current time 2026-…-… is after …`. La date du message est dans quarante jours.

```
admin@runner02:~$ timedatectl ; chronyc tracking ; systemctl status chrony
```

`chrony` est arrêté, l'heure système avancée : le certificat de Harbor (30 jours au plus, ACME) est vu expiré par **ce** client. Le registre n'y est pour rien (depuis `adm01`, tout passe ; `openssl s_client` sur `adm01` montre un certificat valide). Correctif : `sudo systemctl enable --now chrony && sudo chronyc -a makestep`, vérifier l'écart, puis chercher **pourquoi** chrony s'est arrêté. Le runner GitLab était aussi touché (TLS vers `git01`). Prévention : supervision de la synchronisation (`chronyc tracking`, M21), jamais de réglage manuel de l'heure.

**Clôture** : sonde verte, regarder les artefacts sans étiquette laissés par les poussées échouées (une poussée interrompue laisse des blobs dans `_uploads`, purgés par `upload_purging` de `harbor.yml` ; des blobs complets non référencés, retirés par le ramasse-miettes), `--annuler`, RB-133 (section publication).

**Explications**

Une poussée se fait en trois temps : vérification de l'existence des blobs (`HEAD`), téléversement des manquants (`POST`/`PUT` sur `/blobs/uploads/`), puis `PUT` du manifeste. Le quota se décide au téléversement d'un blob nouveau, l'immuabilité au `PUT` du manifeste sur une étiquette existante, les droits à la délivrance du jeton, le TLS avant tout. L'ordre des messages dit donc où l'on est.

**Pièges classiques**
- Supprimer l'immuabilité de `medisphere` « pour la mise en production ».
- Donner au robot `projectadmin` au lieu du droit manquant.
- Relancer le job en boucle : chaque essai laisse des blobs orphelins.

**En production chez MédiSphère**
Quotas dimensionnés et suivis (`harbor_project_quota_usage_byte`, M21) ; règles d'immuabilité dans le code et revues ; synchronisation horaire supervisée sur tous les clients.

---

### M13-E21 — Panne : la signature n'est plus reconnue

**Démarche de diagnostic**

*Symptômes* : `cosign verify` échoue sur `wb-sonde/signee:1.0` ; « no matching signatures » ou « no signatures found » selon la variante.

*Hypothèses* : mauvaise clé ; étiquette déplacée ; signature absente du registre ; client qui ne sait pas où chercher.

**Étape 1 — Reproduire de deux endroits.**

```
admin@runner02:~$ sudo wb-sonde-registre --etape signature
admin@adm01:~$ ssh runner02 sudo cat /var/lib/workbook/temoins-m13/cosign-sonde.pub > /tmp/sonde.pub
admin@adm01:~$ cosign verify --key /tmp/sonde.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/wb-sonde/signee:1.0
```

(Lecture d'une **clé publique** : sans risque. La clé privée ne sort pas de `runner02`.)

**Étape 2 — Les faits.**

```
admin@adm01:~$ ssh runner02 sudo cat /etc/workbook/sonde-registre/temoins.txt         # digest produit
admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/wb-sonde/signee:1.0
admin@adm01:~$ cosign tree registry.par1.medisphere.internal/wb-sonde/signee@<DIGEST-PRODUIT>
admin@adm01:~$ ssh runner02 'sudo sha256sum /etc/workbook/sonde-registre/cosign.pub /var/lib/workbook/temoins-m13/cosign-sonde.pub; sudo grep COSIGN_IMAGE /etc/workbook/sonde-registre/sonde.conf'
```

**Variante 1 — clé publique changée.** Depuis `adm01` avec la clé d'origine : **succès** ; la sonde : `no matching signatures`. Les empreintes de `cosign.pub` (sonde) et de `cosign-sonde.pub` (témoins) diffèrent : la clé de la sonde a été remplacée par celle d'une nouvelle paire (« rotation ») sans que rien ne soit re-signé. Correctif : remettre la clé d'origine dans la sonde. Une vraie rotation : nouvelle paire, re-signature de toutes les images en service, période où le consommateur accepte **les deux** clés, puis retrait de l'ancienne (ADR-0130).

**Variante 2 — étiquette déplacée.** Les deux vérifications échouent : `no signatures found`. Le digest de `1.0` n'est plus celui de `temoins.txt` ; `cosign tree` du digest d'origine montre la signature, celui du nouveau digest rien. Journal d'audit du projet `wb-sonde` : une poussée de `signee:1.0` par `robot$wb-sonde-ci`, à l'heure de la panne. La signature n'a pas « disparu » : elle porte sur l'ancien digest, et l'étiquette désigne une autre image. Correctif : replacer l'étiquette sur le digest signé et retirer l'image intruse (après l'avoir regardée : qu'y a-t-il dedans, qui l'a poussée ?) :

```
admin@adm01:~$ curl -s -u "$U" -X DELETE https://registry.par1.medisphere.internal/api/v2.0/projects/wb-sonde/repositories/signee/artifacts/<NOUVEAU>/tags/1.0
admin@adm01:~$ curl -s -u "$U" -X POST -H 'Content-Type: application/json' -d '{"name":"1.0"}' \
    https://registry.par1.medisphere.internal/api/v2.0/projects/wb-sonde/repositories/signee/artifacts/<DIGEST-PRODUIT>/tags
```

**Re-signer le nouveau digest serait la faute** : ce serait attester une image dont on ignore l'origine. Prévention : immuabilité, déploiement par digest.

**Variante 3 — signature supprimée.** `no signatures found` des deux côtés ; le digest de l'étiquette **est** celui de `temoins.txt` ; `cosign tree` ne montre plus rien ; l'onglet des accessoires est vide ; le journal d'audit montre la suppression de l'artefact de signature (identité `wb-pannes` ici, Lucas dans l'histoire). Correctif : la signature d'origine ne se « restaure » pas ; on re-signe **ce digest** avec la clé de test, **après** avoir établi qu'il est bien celui produit (même digest que `temoins.txt`, noté à la création comme un pipeline note le sien) :

```
admin@runner02:~$ sudo bash -c '. /etc/workbook/sonde-registre/sonde.conf; K=/var/lib/workbook/temoins-m13; D=/etc/workbook/sonde-registre
  docker --config $D/tirage run --rm --network host --user 0:0 -v $K:/k -v $D/ci:/cfg:ro -v $RACINE:/ca.crt:ro \
    -e DOCKER_CONFIG=/cfg -e SSL_CERT_FILE=/ca.crt -e COSIGN_PASSWORD="$(cat $K/cosign-sonde.pass)" $COSIGN_IMAGE \
    sign --key /k/cosign-sonde.key --signing-config /k/signing-config.json $REGISTRE/wb-sonde/signee@<DIGEST-PRODUIT>'
```

(Pour une image de production, la preuve est l'attestation de provenance et le journal du pipeline ; à défaut, on reconstruit et on republie.) Même cause dans la vraie vie : une copie par `docker pull/tag/push` ou `skopeo copy` vers un autre projet garde le digest mais pas les référents.

**Variante 4 — Cosign 2 dans la sonde.** `no signatures found` depuis la sonde, **succès** depuis `adm01` (Cosign 3.1). `COSIGN_IMAGE` désigne `cosign:v2.5.0` (la version du paquet Debian 13). Cosign 2 cherche la signature sous l'étiquette `sha256-<digest>.sig` ; Cosign 3 la range comme **référent OCI 1.1** (*bundle*) : le vieux client ne regarde pas au bon endroit. Correctif : image Cosign 3.1 épinglée (par digest, dans le gabarit). Prévention : versions d'outils de sécurité épinglées et vérifiées partout (règle n° 2 du module).

**Clôture** : sonde verte, `--annuler`, RB-134.

**Explications**

Une signature Cosign 3 est un artefact OCI dont le champ `subject` désigne le **digest** signé ; le registre l'expose par l'API des référents. Vérifier, c'est : résoudre la référence en digest, lister ses référents, trouver ceux qui portent une signature, et vérifier chacune avec la clé. Chaque variante casse un maillon différent de cette chaîne. La règle « on ne re-signe pas pour faire passer » vient de là : la signature ne vaut que par ce que le signataire a vérifié avant de signer.

**Pièges classiques**
- Re-signer l'image désignée par l'étiquette sans comparer son digest à celui produit.
- Conclure « Harbor a perdu nos signatures » sans regarder le journal d'audit.
- Mélanger Cosign 2 et 3 dans une même chaîne (signature v3, vérification v2).

**En production chez MédiSphère**
Vérification par digest dans les déploiements ; immuabilité ; alerte sur la suppression d'accessoires ; rotation de clé répétée chaque année sur les témoins.

---

### M13-E22 — Panne : Harbor ne démarre plus

**Démarche de diagnostic**

*Symptômes* : `/api/v2.0/health` injoignable ou en erreur, pipelines en échec ; `harbor.service` en échec (son démarrage attend que les conteneurs soient sains, `--wait`).

*Hypothèses* (RB-135) : un composant ne démarre pas (base, proxy, registre) ; la pile ne démarre pas du tout (configuration générée) ; ressource (disque) ; droits.

**Étape 1 — Constater.**

```
admin@reg01:~$ systemctl status harbor --no-pager ; journalctl -u harbor -n 40 --no-pager
admin@reg01:~$ cd /opt/harbor && sudo docker compose ps -a
```

**Variante 1 — `/data` plein.** `harbor-db` redémarre en boucle ; `docker logs harbor-db` : `could not write lock file "postmaster.pid": No space left on device` (ou une erreur d'écriture des journaux de PostgreSQL) ; le cœur attend la base.

```
admin@reg01:~$ df -h /data ; sudo du -xsh /data/* | sort -h
admin@reg01:~$ sudo find /data -xdev -type f -size +1G -not -path '/data/registry/*' -ls
```

Un dossier `/data/tmp-export/` contient un « export » de la taille du disque, daté de la nuit : ce n'est ni la base, ni des blobs. Avant de le supprimer : `stat` (date, propriétaire), et la question à Karim ou dans le canal (« c'est à quelqu'un ? »). Correctif : le supprimer (ou le déplacer hors de `/data` s'il est utile), `sudo systemctl restart harbor`. Prévention : seuil disque de `ms-verif-registre` (il aurait alerté à 80 %), exports hors de `/data`.

**Variante 2 — droits de `/data/database`.** `harbor-db` redémarre en boucle ; `docker logs harbor-db` : `could not open directory … Permission denied` ou `data directory … has wrong ownership`. `ls -ln /data/` : `database` appartient à `0:0` (root), mode 700, au lieu de `999:999` (utilisateur `postgres` du conteneur, qui tourne **sans** privilège). Correctif : `sudo chown 999:999 /data/database && sudo chmod 700 /data/database`, ou Harbor arrêté, `sudo ./prepare --with-trivy` (qui pose ces droits) ; puis `systemctl restart harbor`. Prévention : jamais de `chown -R root` « de ménage » sur `/data` ; contrôle des droits dans RB-135.

**Variante 3 — clé du proxy illisible.** Tous les conteneurs tournent sauf `nginx`, qui redémarre ; plus rien sur 443 (connexion refusée), l'API interne est saine. `docker logs nginx` : `cannot load certificate key "/etc/cert/server.key": … Permission denied`. `ls -ln /data/secret/cert/` : `server.key` en `0:0`, mode 000 (au lieu de `10000:10000`, lisible). Correctif : `sudo chown 10000:10000 /data/secret/cert/server.key && sudo chmod 644 /data/secret/cert/server.key` (droits posés par `prepare`), `sudo docker restart nginx`. Note : `harbor-recharger-certificat` (renouvellement) réécrit le contenu en **gardant** les droits : il ne répare pas ce cas.

**Variante 4 — configuration générée absente.** Aucun conteneur ne démarre ; `journalctl -u harbor` : `docker compose` refuse (`env file /opt/harbor/common/config/…/env not found`). `ls /opt/harbor/common/` : `config/` a disparu ; `harbor.yml` est plus récent que `docker-compose.yml`, et `diff` avec ce que rend le rôle montre un nouveau chemin de certificat (`/etc/harbor/tls/registry-2026.crt`) **qui n'existe pas**. Reconstitution : Karim a modifié `harbor.yml` à la main et relancé `prepare` ; `prepare` efface `common/config/` **avant** de valider `harbor.yml`, la validation a échoué sur le certificat absent, il ne restait rien à démarrer. Correctif : ne pas réparer à la main ; repasser le rôle `harbor` (d'abord `--check --diff` sur `reg01`, sans afficher `harbor.yml` qui contient des secrets — le rôle désactive le diff sur ce fichier : compare les clés à la main) :

```
admin@adm01:~/src/ansible$ ansible-playbook playbooks/registre.yml -l reg01 --check
admin@adm01:~/src/ansible$ ansible-playbook playbooks/registre.yml -l reg01
```

Le rôle rend `harbor.yml` depuis le gabarit (modification manuelle annulée), relance `prepare --with-trivy` (configuration régénérée) et redémarre Harbor. Si le nouveau chemin de certificat était voulu, il passe par `certificats.yml` et le gabarit, dans une MR.

**Réparer ou restaurer ?** Aucune variante n'exige la restauration : les données sont intactes. RB-131 n'est la bonne réponse que si la base ou les blobs sont endommagés, ou si la cause n'est pas trouvée dans un délai fixé (1 h 30 dans RB-135).

**Clôture** : santé `healthy`, tirage et poussée depuis `runner02`, `cosign verify`, relance de la dernière réplication, `--annuler`, RB-135, et le contrôle qui manquait à la sonde (disque, déjà là ; droits et configuration générée : contrôles SSH possibles, ou alerte sur `harbor.service` en échec).

**Explications**

Harbor est une pile Compose dont la configuration est **générée** : `harbor.yml` est la source, `prepare` produit `common/config/*` et `docker-compose.yml`. Les conteneurs tournent sans privilège avec des utilisateurs fixes (999 pour PostgreSQL, 10000 pour nginx et les autres) : tout changement de droits sur l'hôte les touche. Les dépendances de démarrage font qu'un seul composant cassé fait tomber l'ensemble : le premier en échec est la piste.

**Pièges classiques**
- `docker compose down -v` ou `rm -rf /data/database` « pour repartir propre ».
- Recréer `common/config` à la main ou éditer `docker-compose.yml`.
- Restaurer la sauvegarde de la nuit alors qu'un fichier de trop remplissait le disque : perte des images de la journée.
- Supprimer le gros fichier sans savoir ce qu'il est.

**En production chez MédiSphère**
`harbor.yml` jamais modifié à la main (dérive détectée par un `--check` planifié) ; seuils disque ; alerte sur l'échec de `harbor.service` ; RB-135 répété en exercice d'astreinte (F3).

---

### M13-E23 — Sous le capot : l'API de distribution OCI

**Solution**

Outil : [`outils/oci-inspecter.sh`](fichiers/M13-E23/outils/oci-inspecter.sh) ; note modèle : [`notes/api-oci.md`](fichiers/M13-E23/medisphere/docs/registre/notes/api-oci.md).

*1. Le défi.* `GET /v2/` sans identité → `401` et `WWW-Authenticate: Bearer realm="https://registry.par1.medisphere.internal/service/token",service="harbor-registry"`. Jeton : `GET <realm>?service=harbor-registry&scope=repository:medisphere/mediagenda-api:pull` avec `-u` (identité) ou sans. Le JWT (trois parties base64url) est signé par `harbor-core`, valable 30 minutes (`expires_in`), et sa charge porte `access`. Pour une portée que l'identité n'a pas (ou en anonyme sur un projet privé), le service **délivre** un jeton… avec une liste d'actions vide : c'est le registre qui refuse ensuite.

*2. Le manifeste.*

```
admin@adm01:~$ J=<JETON>
admin@adm01:~$ for t in application/vnd.oci.image.index.v1+json application/vnd.oci.image.manifest.v1+json \
      application/vnd.docker.distribution.manifest.v2+json ''; do
    curl -s -o /dev/null -D - -H "Authorization: Bearer $J" ${t:+-H "Accept: $t"} \
      https://registry.par1.medisphere.internal/v2/medisphere/mediagenda-api/manifests/vX.Y.Z \
      | grep -iE '^(HTTP|content-type|docker-content-digest)'; done
```

Un registre ne **convertit** pas : si l'image est un index OCI (multi-architecture, M12), une demande qui n'accepte que le manifeste Docker v2 reçoit `404`/`406` ou le type réellement stocké selon l'implémentation ; sans `Accept`, Harbor renvoie le type stocké. `Docker-Content-Digest` est toujours le digest de ce qui est renvoyé.

*3. Le digest.* `sha256sum` du corps **brut** = `Docker-Content-Digest` ; après `jq .`, le digest change : c'est l'empreinte des octets. Conséquence : signer un digest, c'est signer ces octets, et tout ce qu'ils référencent par digest (index → manifestes → configuration et couches) : rien ne peut changer « sous » une signature par digest.

*4. Les blobs.* `GET /v2/<dépôt>/blobs/<digest>` (avec `-L` si le stockage redirige) ; la configuration est un JSON (utilisateur, commande, étiquettes OCI, historique des étapes) ; `sha256sum` d'une couche téléchargée = son digest. `HEAD` donne `Content-Length` et `Docker-Content-Digest` sans transférer : c'est ce qu'un client fait avant de pousser (« ce blob existe-t-il déjà ? »).

*5. Les référents.* `GET /v2/<dépôt>/referrers/<digest>` (réponse : un index OCI) liste signature et attestations (`artifactType` du bundle Sigstore v0.3 pour Cosign 3), et la SBOM générée par Harbor. `?artifactType=…` filtre (le `+` s'encode `%2B`). `oras discover registry.par1.medisphere.internal/medisphere/mediagenda-api@<digest>` donne l'arbre ; `oras manifest fetch` sur un référent puis `oras blob fetch --output - …` sur sa couche montre le *bundle* : matériel de vérification (clé ou identifiant de clé), message ou enveloppe DSSE signés, `tlogEntries` vide (aucune entrée Rekor) — d'où `--insecure-ignore-tlog=true` à la vérification.

*6. Ce qu'on ne peut pas faire.* `/v2/_catalog` est réservé aux administrateurs du système dans Harbor (`401`/`403` avec un robot de projet). `DELETE` d'un manifeste avec un jeton `pull` : `401`, l'action n'est pas dans le jeton (et `v*` est immuable).

**Explications**

Tout ce que font `docker`, `containerd`, `skopeo`, `cosign` et `oras` se ramène à ces quelques requêtes. Les connaître permet de diagnostiquer un client opaque (M14 : `crictl pull` qui échoue) et de comprendre pourquoi une signature par digest est solide. L'API des référents (OCI 1.1) remplace l'astuce des étiquettes `sha256-….sig` de Cosign 2 : les attachements sont liés au sujet par le registre, et un client les découvre sans connaître de convention de nommage.

**Pièges classiques**
- Recalculer le digest sur une sortie reformatée (`jq`, `curl … | python -m json.tool`).
- Oublier l'en-tête `Accept` sur l'API des référents ou sur un index.
- Coller un jeton dans une note publiée : il est valable 30 minutes, et c'est déjà trop.

---

### M13-E24 — Questions expert : supply chain

**1. Trois attaques que signature + SBOM + analyse n'arrêtent pas.**
- *Code malveillant dans une dépendance encore inconnue* (xz-utils 2024, `event-stream`) : la SBOM le liste, Trivy ne le connaît pas, la CI le signe. Contrôles : épinglage par verrou et revue des mises à jour (Renovate sans fusion automatique des mineures), délai de quarantaine avant adoption d'une nouvelle version, analyse de comportement.
- *CI compromise* (SolarWinds, Trivy 2026 : vol des secrets de pipeline) : une CI compromise signe ce qu'on lui donne avec la vraie clé. Contrôles : provenance vérifiée (dépôt, commit, constructeur) et non seulement la signature ; clé hors de la CI (Vault Transit, M25) ; runners isolés et éphémères ; SLSA Build L3.
- *Image correcte détournée au déploiement* (étiquette déplacée, image d'un autre projet signée par la même clé) : contrôles : déploiement par digest, admission qui vérifie le registre, le projet **et** la signature (M26), immuabilité.

**2. Trivy 2026.** `@v0.35.0` : le seul tag de `trivy-action` non réécrit, donc **par chance** sain — un tag n'est pas une protection, il peut être déplacé (76 sur 77 l'ont été). `@<sha de commit>` : protégé contre le déplacement du tag (un commit est immuable), à condition d'avoir épinglé un commit sain **avant** l'attaque. Le binaire 0.69.4 vérifié par la somme publiée **à côté** : non protégé — l'attaquant publiait aussi la somme. Une somme garantit l'intégrité par rapport à une valeur, pas l'**origine** ; une signature avec identité (`cosign verify-blob --certificate-identity …/reusable-release.yaml@refs/tags/v0.75.0 --certificate-oidc-issuer …`) prouve que l'artefact a été produit par **ce** workflow de **ce** dépôt pour **ce** tag — ce que le compte de service volé ne pouvait pas imiter depuis un autre workflow, et ce qui se vérifie hors du canal de distribution. Les deux ensemble : identité à l'épinglage, empreinte ensuite (RB-130).

**3. Par digest.** Scénario : la CI signe `mediagenda-api:v2.0.0` ; un attaquant ayant des droits de poussée (ou une erreur de pipeline) pousse une autre image sous la même étiquette ; si la vérification résout l'étiquette au moment de la signature puis celle du déploiement séparément, chacune voit une image différente — et si la signature a été faite « par étiquette » juste après la réécriture, c'est l'image de l'attaquant qui est signée. L'immuabilité empêche la réécriture **dans ce registre**, pas la copie dans un autre projet, ni la résolution d'une étiquette vers un registre différent (cache, miroir), ni l'erreur d'une règle mal écrite (E20 variante 2) ou retirée.

**4. Référents OCI 1.1.**
- *Réplication vers un registre ancien* (Distribution 2.x, sans API des référents) : les accessoires ne se publient pas comme référents ; il faut le mode de repli (`--registry-referrers-mode legacy` côté Cosign, ou l'étiquette de repli `sha256-<digest>` définie par la spécification) ou ne répliquer que vers des registres 1.1.
- *Ramasse-miettes et rétention* : un référent sans étiquette est un artefact « non étiqueté » ; Harbor le rattache à son sujet (accessoire) et le garde avec lui, mais un nettoyage générique des artefacts sans étiquette, ou un outil externe qui ne connaît pas les référents, peut supprimer les signatures.
- *Client Cosign 2* : cherche `sha256-<digest>.sig` et ne trouve rien (E21 variante 4).
- *Outils qui listent les étiquettes* (`skopeo list-tags`, `crane ls`) : les signatures n'apparaissent plus comme étiquettes, la liste est plus propre, mais un audit fondé sur les étiquettes ne voit plus les signatures : utiliser `cosign tree`, `oras discover` ou l'API des référents.

**5. Avec ou sans clé.** *Clé volée* : avec clé, l'attaquant signe ce qu'il veut jusqu'à la rotation, et sans horodatage on ne peut pas trier les signatures antérieures ; sans clé, un certificat de 10 minutes lié à une identité OIDC : voler la clé ne sert à rien, il faut voler l'**identité** (compte de pipeline) — révocable, et chaque signature est horodatée dans Rekor. *Internet* : le sans-clé public exige Fulcio et Rekor à la signature et (sauf *bundle* hors ligne) des racines TUF à jour à la vérification. *Fuite* : Rekor public publie pour toujours le digest, le nom de l'image et l'identité du signataire. *Horodatage* : seul le journal ou une TSA le fournit. MédiSphère vérifie avec `--insecure-ignore-tlog` parce que ses signatures ne sont dans aucun journal ; elle perd la preuve de date et la détection d'une signature faite à son insu (un journal permet de **surveiller** ce qui a été signé avec sa clé ou son identité).

**6. SLSA.** La chaîne de E09 : processus de construction scripté et provenance générée par BuildKit (Build L1), sur une plateforme de construction hébergée (runner GitLab) avec provenance signée par la CI (proche de L2, si la provenance est signée par une clé que les jobs ne contrôlent pas — ce n'est pas le cas : la clé est une variable lisible par le job) ; L3 exige l'isolation entre les constructions et que les secrets de signature soient **inaccessibles** aux étapes définies par l'utilisateur (signature par le runner ou un service, M25). `mode=max` ajoute à la provenance les paramètres de construction, les matériaux (images de base par digest, contexte) et les étapes ; elle ne prouve pas que le code source n'est pas malveillant, ni que la plateforme de construction n'était pas compromise : elle dit **comment** l'image a été faite, telle que le constructeur le déclare.

**7. SBOM d'image ou de verrou.** Celui de l'**image** décrit ce qui est livré (y compris les paquets système de l'image de base, absents du verrou) : c'est lui qu'on interroge en alerte. Celui du **verrou** décrit l'intention et couvre des dépendances qu'un analyseur d'image peut manquer : binaires compilés statiquement sans métadonnées (outils Go copiés, dont Syft ne voit que ce que le binaire embarque), fichiers ajoutés par `COPY`/`curl` sans gestionnaire de paquets, bibliothèques vendues (*vendored*) dans le code. En cas d'écart, les deux se complètent ; la règle MédiSphère : SBOM d'image attestée par la CI, contrôle croisé par la SBOM de Harbor et par le verrou.

**8. Le cache `dockerhub`.** Risques : *empoisonnement* (une image malveillante en amont entre dans le cache et y reste), *image retirée en amont* (le cache la sert encore… ou plus, selon `proxy_cache_local_on_not_found`), *étiquette déplacée en amont* (`python:3.13-slim-trixie` change de contenu chaque semaine : le cache suit). Réduction : épingler par digest dans les Dockerfile (Renovate propose les nouveaux digests en MR), images de base reconstruites dans `bibliotheque` (M12-E27) par une réplication *pull* contrôlée ou une construction propre, analyse de ce qui entre, `proxy_cache_local_on_not_found` pour la disponibilité (en sachant qu'il garde aussi une image retirée pour une raison de sécurité).

**9. Politique Harbor et admission.** La politique de Harbor vérifie la présence d'une signature (pas la clé), seulement pour les tirages **par Harbor**, seulement dans les projets où elle est active ; elle ne voit pas une image tirée d'un autre registre, ni le digest réellement déployé. L'admission vérifie, au moment de créer le pod, la clé, le registre, le digest, quelle que soit l'origine. On garde les deux : défense en profondeur (le registre protège aussi les clients hors Kubernetes : CI, Docker, Podman) et une politique qui échoue « tôt » (au tirage) plutôt qu'au déploiement.

**10. `secretkey` perdue.** Ce qui marche : tirages et poussées (jetons signés par `private_key.pem`, pas par `secretkey`), robots et utilisateurs locaux (mots de passe hachés), interface. Ce qui ne marche plus : tout ce qui est **chiffré** en base avec elle — identifiants des endpoints (réplication, caches avec compte), secret OIDC (M24), certains paramètres de scanners — avec des erreurs de déchiffrement au premier usage, souvent la nuit (réplication planifiée). On le découvre par la sonde (réplication en échec), `core.log` (erreurs de déchiffrement). Prévention : `secret/` dans la même sauvegarde que la base (E15), restauration testée en vérifiant justement un endpoint.

**11. MR de Renovate sur un digest.** Fusion automatique seulement si : l'image et l'étiquette sont celles déjà utilisées (même version, nouveau digest : correctifs de l'éditeur), le pipeline est **complet** et vert (construction, Trivy bloquant, tests, SBOM, signature, vérification), la source amont est vérifiée (images officielles ; pour celles qui signent — Docker Hardened Images, Chainguard, les images de Kubernetes —, vérification de la signature de l'éditeur dans le pipeline), et la MR passe par le cache Harbor (pas d'accès direct). Sinon (nouvelle version mineure, nouvelle image) : revue humaine. Ce que l'automatisation ne doit pas ouvrir : un dépôt amont changé sans revue (`packageRules` limitées par `matchPackageNames`), un `latest`, un saut de majeure.

**12. Traçabilité au 3 mars.** Conserver : l'historique des déploiements avec les **digests** (GitOps : l'historique Git des manifestes, M20 ; événements de l'API Kubernetes dans les journaux d'audit, M14/M22), les artefacts eux-mêmes et leurs référents (SBOM, provenance, signature) dans Harbor ou dans un archivage, et les journaux d'audit de Harbor. Durée : celle de la politique de conservation HDS/ISO (souvent un à plusieurs années pour les preuves d'audit). Les règles de rétention et le ramasse-miettes doivent **exclure** les versions déployées en production pendant cette durée (étiquettes `v*` conservées, ou réplication vers un projet d'archive en lecture seule), sinon on ne pourra produire ni l'image ni sa SBOM le jour de l'audit.
