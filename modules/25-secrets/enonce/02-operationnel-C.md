### M25-E17 — Transit : le chiffrement comme service  `LAB` `★★`

> **Ticket SEC-2617** — *De : Sophie Laurent*
> Les fiches d'intervention que `medictl` exporte pour InfoGér contiennent les codes d'accès des baies de PAR1 et les numéros d'astreinte des prestataires. Elles finissent en pièce jointe dans des tickets. Je veux ces deux champs chiffrés par le coffre, avec une clé qui n'en sort jamais et qui tourne chaque année. Quand un prestataire part, je veux pouvoir rendre illisibles les anciennes fiches d'un coup. Et Julien va poser la même question pour les données de santé de MédiAgenda : je veux une note qui dise quand on chiffre par le coffre, et quand on ne le fait pas.

**Objectifs pédagogiques**
- Comprendre le moteur `transit` : le client envoie des données, la clé reste dans OpenBao, le chiffré porte la version de la clé (`vault:v<N>:`).
- Faire tourner une clé sans rien casser, rechiffrer (`rewrap`) sans revoir le clair, et distinguer **gel** (`min_decryption_version`) et **destruction** (`trim`) des anciennes versions.
- Donner à une identité machine le droit de chiffrer avec **sa** clé et rien d'autre.
- Comprendre le chiffrement par clé de données (*envelope encryption*) avec le fournisseur de clé `openbao` d'OpenTofu (promesse du M05-E27).

**Prérequis** : M25-E07 (AppRole `medictl`, politique `wb-checks`), M25-E08 (projet `plateforme/secrets`, `outils/charger-acces.sh`) ; M02 (`medictl`, `plateforme/outils`) ; M05-E27 (chiffrement des états OpenTofu).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Moteur | `transit/`, monté par OpenTofu (`plateforme/secrets`, nouveau fichier `tofu/transit.tf`) |
| Clé des fiches | `medictl-donnees` : `aes256-gcm96`, **non exportable**, pas de sauvegarde en clair, suppression interdite, rotation automatique **365 jours** (`auto_rotate_period`, en secondes dans le fournisseur) |
| Clé d'essai | `essai-e17` : mêmes réglages mais suppression **autorisée** ; toutes les manipulations destructrices se font sur elle ; supprimée à la fin |
| Politiques (`politiques/*.hcl`) | `medictl` : chiffrer, déchiffrer et rechiffrer avec `medictl-donnees`, rien sur `transit/keys/…` ; `plateforme-admin` : administrer les clés (créer, régler, tourner), sans `transit/export` ni `transit/backup` ; `wb-checks` : **lister** `transit/keys` et **lire** `transit/keys/+` (métadonnées : type, versions, réglages ; jamais de matériel de clé pour une clé symétrique non exportable) |
| `medictl` | projet `plateforme/outils` (clone `~/src/outils`) ; nouveau module `src/medictl/transit.py` et commandes `medictl transit chiffrer|rechiffrer|dechiffrer FICHIER -c CHAMP…` sur un document JSON (objet ou liste d'objets), réécrit sur place ; jeton : `BAO_TOKEN` (AppRole `medictl`, E07) sinon `~/.vault-token` (écrit par `bao login`) ; adresse `BAO_ADDR` ; autorité du système ou `BAO_CACERT` ; `requests` (comme le client Proxmox du M02) |
| Fiche de travail | `~/m25/e17/fiche-intervention.json` : liste de fiches `{"vm", "baie", "code_baie", "astreinte_tel", "prestataire"}` (valeurs **fictives**) ; `code_baie` et `astreinte_tel` chiffrés |
| Note | `docs/securite/secrets/transit.md` de `plateforme/medisphere` |

> ⚠️ **Attention** : une clé de transit supprimée rend **définitivement** illisible tout ce qu'elle a chiffré, copies et sauvegardes comprises ; `trim` détruit des versions sans retour. Ces deux gestes ne se font que sur `essai-e17`. Garde `deletion_allowed = false` sur toute clé qui a chiffré une donnée réelle.

**Travail demandé**

1. **Lire avant d'écrire.** Dans la documentation du moteur transit d'OpenBao, relève : les types de clés symétriques et asymétriques ; pourquoi le clair est envoyé en base64 ; ce que contient le préfixe d'un chiffré ; ce que font `rotate`, `rewrap`, `min_decryption_version`, `min_encryption_version`, `trim` ; ce qu'est une clé de données (`datakey`). Note tes réponses dans `~/m25/e17/notes.md`.
2. **En code.** Dans `plateforme/secrets`, écris `tofu/transit.tf` (montage et deux clés) et complète les politiques `medictl`, `plateforme-admin` et `wb-checks`. Branche, MR, `tofu plan` depuis `adm01` (session chargée par `outils/charger-acces.sh` après `bao login -method=oidc`), fusion, `tofu apply`, plan vide. Le fournisseur sait-il **tourner** une clé ? Pourquoi est-ce une bonne chose de ne pas gérer `min_decryption_version` dans OpenTofu ?
3. **Premiers chiffrés (`essai-e17`).** Chiffre deux fois la même chaîne avec la CLI :
   ```
   admin@adm01:~$ bao write -field=ciphertext transit/encrypt/essai-e17 plaintext="$(printf 'code 4821' | base64)"
   ```
   Pourquoi les deux chiffrés diffèrent-ils ? Déchiffre-les. Refais la même chose par l'API avec `curl`, le jeton passé par un fichier de configuration de `curl` (jamais sur la ligne de commande), puis chiffre trois valeurs en **une** requête (`batch_input`).
4. **Rotation et rechiffrement (`essai-e17`).** Garde un chiffré `v1` dans un fichier, tourne la clé, chiffre une nouvelle valeur (quelle version ?), déchiffre l'ancien (que se passe-t-il ?), puis rechiffre-le par `rewrap` : as-tu vu le clair à un moment ?
5. **Geler, puis détruire (`essai-e17`).** Règle `min_decryption_version` à 2 et essaie de déchiffrer un chiffré `v1` : quel message ? Reviens à 1 : le chiffré redevient-il lisible ? Qu'en conclus-tu pour la demande de Sophie (« rendre illisibles d'un coup ») ? Essaie ensuite `trim` avec `min_available_version=2` : que demande OpenBao avant de l'accepter, et que devient la version 1 ?
6. **`medictl`.** Ajoute `src/medictl/transit.py` (un client qui parle à l'API de transit, par lots, sans jamais écrire le jeton dans un message) et les trois commandes, avec des tests `pytest` qui simulent l'API (`responses`, déjà utilisé au M02). Contraintes : `https://` obligatoire ; vérification TLS jamais désactivée ; un champ déjà chiffré n'est pas rechiffré par `chiffrer` ; réécriture **atomique** du fichier. MR, pipeline vert, publication comme au M02.
7. **Les fiches.** Écris `~/m25/e17/fiche-intervention.json` (trois fiches fictives), chiffre `code_baie` et `astreinte_tel` **avec l'AppRole `medictl`** (un jeton obtenu comme en E07, dans `BAO_TOKEN` le temps de la commande). Puis, avec ton identité `plateforme-admins`, tourne la vraie clé `medictl-donnees` une fois, et repasse la fiche à la dernière version avec `medictl transit rechiffrer`. Essaie enfin `bao write -f transit/keys/medictl-donnees/rotate` avec le jeton de `medictl` : que répond OpenBao, et pourquoi est-ce voulu ?
8. **Clé de données : un état OpenTofu chiffré par le coffre.** Dans `~/m25/e17/tofu-essai/`, crée un état **local** jetable (une ressource `terraform_data`), puis ajoute un bloc `encryption` avec le fournisseur de clé `openbao` (clé `essai-e17`) et une méthode de repli `unencrypted` pour la migration ; applique, regarde le fichier d'état et ses métadonnées, retire le repli. Quels appels OpenBao a-t-il reçus (lis la documentation du fournisseur) ? Supprime enfin `essai-e17` par OpenTofu (retrait du bloc, MR) et relance `tofu plan` dans l'essai : que se passe-t-il ? Quels états réels de MédiSphère peuvent dépendre du coffre, et lequel **ne doit pas** ?
9. **La note.** Écris `docs/securite/secrets/transit.md` (MR) : quand chiffrer par transit et quand non (KV, secret dynamique, clé de données), règles de nommage et de réglage des clés, rotation et rechiffrement, gel et destruction, ce qu'il faut savoir avant de chiffrer une colonne de MédiAgenda (disponibilité, recherche, volume), et la décision pour les états OpenTofu.

**Critères de réussite**
- [ ] `transit/` est monté ; `medictl-donnees` est en `aes256-gcm96`, non exportable, sans sauvegarde en clair, non supprimable, avec une rotation automatique d'un an, au moins deux versions et `min_decryption_version` à 1.
- [ ] `essai-e17` n'existe plus.
- [ ] La politique `medictl` n'autorise que `encrypt`, `decrypt` et `rewrap` sur `medictl-donnees`.
- [ ] Dans `~/m25/e17/fiche-intervention.json`, tous les `code_baie` et `astreinte_tel` sont chiffrés à la **dernière** version de la clé.
- [ ] `src/medictl/transit.py` et ses tests, `tofu/transit.tf` et `transit.md` sont sur `main` de leurs projets.

**Vérification** : `lab/bin/check 25 17`

<details><summary>Indice 1</summary>

Pour transit, toute opération est un `POST` : dans une politique, c'est la capacité `update` sur `transit/encrypt/<clé>`, `transit/decrypt/<clé>`… Une politique qui donne `update` sur `transit/keys/*` donne aussi `transit/keys/<clé>/config` et `rotate` : regarde ce que deviendrait `exportable` si quelqu'un pouvait le changer.
</details>

<details><summary>Indice 2</summary>

`min_decryption_version` ne supprime rien : les versions sont toujours là, simplement refusées. `trim` exige qu'on ait d'abord interdit le **chiffrement** avec les versions qu'il va supprimer. Lis le message d'erreur de `trim` : il dit quel réglage poser avant.
</details>

<details><summary>Indice 3</summary>

Dans `requests`, une vérification TLS posée sur la session (`session.verify`) peut être remplacée sans bruit par la variable `REQUESTS_CA_BUNDLE` du shell ; le M02-E08 a déjà rencontré ce piège avec `proxmoxer`. Passe `verify=` à chaque requête. Côté OpenTofu, le fournisseur de clé `openbao` lit `BAO_ADDR` et `BAO_TOKEN`.
</details>

**Pour aller plus loin** (facultatif) : chiffrement **dérivé** et **convergent** (`derived`, `convergent_encryption`, `context`) et ce qu'il fait fuir ; empreintes `transit/hmac/<clé>` pour rechercher une valeur chiffrée ; [moteur transit d'OpenBao](https://openbao.org/docs/secrets/transit/), [API transit](https://openbao.org/api-docs/secret/transit/), [chiffrement des états OpenTofu](https://opentofu.org/docs/language/state/encryption/).

---

### M25-E18 — Des secrets chiffrés dans Git : SOPS, age et transit  `LAB` `★★`

> **Ticket PLAT-2618** — *De : Karim Benali*
> On a choisi External Secrets pour le cluster, très bien. Mais à chaque conférence, quelqu'un me demande pourquoi on ne fait pas « tout simplement » du SOPS : les secrets chiffrés dans Git, à côté du reste. Je veux qu'on l'ait pratiqué pour de vrai avant de répondre : avec `age` d'abord, puis avec notre coffre comme gestionnaire de clés. Sur un dépôt d'essai, pas sur nos vrais dépôts. Et à la fin, une comparaison honnête et ce qu'on retient.

**Objectifs pédagogiques**
- Comprendre le chiffrement par enveloppe de SOPS : une clé de données par fichier, chiffrée pour chaque destinataire (`age`, transit d'OpenBao) ; un MAC sur tout le fichier.
- Écrire des règles `.sops.yaml` (chemins, champs chiffrés, destinataires) et travailler sans jamais écrire le clair sur disque (`sops edit`).
- Retirer un destinataire correctement (`updatekeys`, `rotate`) et comprendre ce que l'historique Git garde.
- Brancher SOPS sur le moteur transit (`hc_vault_transit_uri`), borner les adresses de coffre autorisées (`SOPS_HC_VAULT_ALLOWLIST`) et comparer avec External Secrets.

**Prérequis** : M25-E12 (External Secrets, `wb-essais`), M25-E17 (moteur transit) ; M01 (GitLab, MR) ; M14-E05 (rôle `outils_k8s`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Versions | **SOPS 3.13.3** (jamais 3.13.2 : MAC erroné sur les listes YAML commentées) ; **age 1.3.2** (Debian 13 livre 1.2.1) ; installés sur `adm01` par le rôle `outils_k8s` (le binaire de SOPS est publié **sans archive** : le rôle doit apprendre à installer un binaire brut ; vérifie la signature du fichier de sommes de SOPS avec Cosign avant d'en recopier l'empreinte, comme au M13) |
| Dépôt d'essai | projet GitLab **`formation/sops-labo`** (clone `~/src/sops-labo`) : `.sops.yaml`, `.gitattributes`, `k8s/wb-essais/*.sops.yaml`, `outils/verifier-chiffres.sh`, `.gitlab-ci.yml` |
| Clés `age` | la tienne (`~/.config/sops/age/keys.txt`, emplacement lu par défaut par SOPS) ; une clé « Karim » **simulée** que tu génères et que tu retireras ; une clé « secours » de l'équipe, privée **hors ligne** (même traitement que les parts Shamir d'E03), dont seule la publique va dans `.sops.yaml` |
| Coffre | clé de transit **`sops-plateforme`** (`aes256-gcm96`, non exportable, non supprimable) et politique **`sops-plateforme`** (chiffrer et déchiffrer avec elle, rien d'autre), attachée aux groupes externes `plateforme-admins` et `plateforme` (variable `groupes_keycloak`) ; URI SOPS : `https://openbao.par1.medisphere.internal:8200/v1/transit/keys/sops-plateforme` |
| Jeton pour SOPS | SOPS lit `VAULT_TOKEN` ou `~/.vault-token` (pas `BAO_TOKEN`) ; `bao login -method=oidc` écrit `~/.vault-token` |
| Fichier à chiffrer | un Secret Kubernetes **fictif** `essai-sops` de `wb-essais` (clés `mot_de_passe`, `utilisateur`) |
| Comparaison | `docs/securite/secrets/comparatif-livraison-k8s.md` (créé ici, complété en E19) |

> ⚠️ **Attention** : un secret commité en clair, même une seconde, est dans l'historique pour toujours (M01). Dans ce dépôt, n'utilise que des valeurs fictives, et ne commite jamais un fichier avant d'avoir vérifié qu'il est chiffré (`outils/verifier-chiffres.sh`, et un `git diff --cached` qui ne montre que des `ENC[…]`).

**Travail demandé**

1. **Outils.** Étends le rôle `outils_k8s` pour qu'il sache installer un binaire publié sans archive, ajoute `sops` et `age` à sa liste, MR, playbook sur `adm01`. Montre dans la MR la vérification de la signature du fichier de sommes de SOPS (identité du flux de publication du projet, émetteur GitHub).
2. **SOPS + age.** Crée le projet `formation/sops-labo`. Génère ta clé `age` et la clé « Karim » (dans `~/m25/e18/`). Écris un `.sops.yaml` qui chiffre **seulement** `data` et `stringData` des fichiers `k8s/**/*.sops.yaml` pour vous deux. Crée le Secret d'essai avec `sops edit` (où le clair existe-t-il pendant l'édition ?). Ouvre le fichier chiffré : qu'est-ce qui reste lisible, que contient la section `sops`, que protège le MAC ? Modifie une valeur à la main dans le chiffré (sans SOPS) et essaie de déchiffrer.
3. **Lire l'historique.** Ajoute le pilote de différence de `.gitattributes` (`diff=sopsdiffer`, `textconv`) et compare `git log -p` avec et sans lui.
4. **Contrôle en CI.** Écris `outils/verifier-chiffres.sh` (yq v4) qui refuse : un `kind: Secret` hors d'un `*.sops.yaml`, un `*.sops.yaml` sans métadonnées SOPS ou sans destinataire, une valeur en clair sous `data`/`stringData`. Branche-le dans `.gitlab-ci.yml` (MR et `main`). Prouve qu'il échoue sur une MR qui ajoute un Secret en clair (puis ferme cette MR **sans** la fusionner, et supprime la branche).
5. **Retirer Karim.** Il quitte le projet : retire sa clé de `.sops.yaml`, puis `sops updatekeys`. Peut-il encore déchiffrer le fichier de `main` ? Et celui du commit précédent ? Que fait `sops rotate`, et pourquoi ne suffit-il pas non plus ? Que faut-il faire de la **valeur** du secret ?
6. **SOPS + transit.** Ajoute en code (`plateforme/secrets`) la clé `sops-plateforme`, la politique `sops-plateforme` et son attachement aux groupes ; MR, apply. Remplace ta clé personnelle par la clé de transit et la clé « secours » dans `.sops.yaml`, `updatekeys`, `rotate`. Déchiffre après `bao login -method=oidc`, puis sans jeton : quel message ? Ajoute `export SOPS_HC_VAULT_ALLOWLIST=https://openbao.par1.medisphere.internal:8200` à ton `~/.bashrc` et explique contre quoi il protège (pense à un fichier `.sops.yaml` ou chiffré fourni par quelqu'un d'autre). Dans le journal d'audit d'OpenBao (s'il est déjà en place, sinon après E21), qu'apparaît-il quand tu déchiffres ?
7. **Dans le cluster ?** Applique le Secret déchiffré dans `wb-essais` (`sops decrypt … | kubectl apply -n wb-essais -f -`), puis supprime-le. Comment Argo CD pourrait-il le faire lui-même (cherche « KSOPS » et « helm-secrets ») et quel droit faudrait-il lui donner ?
8. **Comparer et décider.** Écris `comparatif-livraison-k8s.md` (MR dans `plateforme/medisphere`) : SOPS face à External Secrets, critère par critère (où vit la valeur, qui déchiffre, rotation, retrait d'un accès, secrets dynamiques, revue de MR, reprise après sinistre), et ce que MédiSphère retient.

**Critères de réussite**
- [ ] `sops` 3.13.3 et `age` sont installés sur `adm01` par le rôle `outils_k8s` ; `SOPS_HC_VAULT_ALLOWLIST` limite SOPS au coffre de MédiSphère.
- [ ] La clé `sops-plateforme` et la politique `sops-plateforme` (chiffrer, déchiffrer, rien d'autre) existent.
- [ ] Sur `main` de `formation/sops-labo`, `.sops.yaml` vise la clé de transit et **une seule** clé `age` (la clé de secours), et au moins un `k8s/**/*.sops.yaml` est chiffré par SOPS 3.13.3 pour ces deux destinataires, sans aucune valeur en clair ; le contrôle de la CI est vert.
- [ ] La comparaison SOPS / ESO est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 25 18`

<details><summary>Indice 1</summary>

Dans une règle `creation_rules`, `age` et `hc_vault_transit_uri` côte à côte forment **un seul** groupe de clés : n'importe quel destinataire suffit à déchiffrer. `encrypted_regex` décide des champs chiffrés ; le MAC, lui, couvre tout le fichier, champs en clair compris : on ne peut pas changer le `namespace` d'un fichier chiffré sans SOPS.
</details>

<details><summary>Indice 2</summary>

`updatekeys` change les destinataires de la **clé de données** du fichier, pas la clé de données elle-même : qui l'a déjà vue (ou qui a l'ancien fichier) peut toujours lire. `rotate` change la clé de données ; ni l'un ni l'autre ne touche à l'historique Git ni à la **valeur** du secret.
</details>

<details><summary>Indice 3</summary>

Pour le rôle : `ansible.builtin.get_url` accepte une somme sous la forme `sha256:<URL du fichier de sommes>` (il y cherche le nom du fichier téléchargé) ou `sha256:<empreinte>` ; un binaire brut n'a pas besoin d'`unarchive`, mais d'un mode exécutable.
</details>

**Pour aller plus loin** (facultatif) : groupes de clés à seuil (`key_groups`, `shamir_threshold`) : exiger deux destinataires pour déchiffrer ; identités `age` post-quantiques et plugins (`age-plugin-*`) pris en charge par SOPS 3.13 ; [documentation de SOPS](https://getsops.io/docs/), [age](https://github.com/FiloSottile/age), [KSOPS](https://github.com/viaduct-ai/kustomize-sops).

---

### M25-E19 — Comparer : Sealed Secrets et Secrets Store CSI  `LAB` `★★`

> **Ticket PLAT-2619** — *De : Claire Morel*
> L'auditeur HDS de l'an prochain demandera pourquoi nous avons choisi External Secrets et pas autre chose. « On a lu des articles » ne suffira pas. Essayez les deux autres approches qu'on nous cite toujours, Sealed Secrets et le pilote CSI avec OpenBao, dans `wb-essais`, mesurez, écrivez la comparaison, puis désinstallez tout : je ne veux pas trois façons de livrer un secret dans le cluster.

**Objectifs pédagogiques**
- Installer temporairement des composants tiers par le chemin normal (chart recopié dans Harbor, Application Argo CD, espace déclaré) et les retirer proprement.
- Comprendre Sealed Secrets : chiffrement asymétrique pour **un** cluster, portées, clé privée du contrôleur et ce qu'elle implique pour la reprise.
- Comprendre le pilote Secrets Store CSI : volume monté au démarrage du pod avec l'identité **du pod**, recopie facultative dans un Secret, rotation.
- Mesurer et comparer avec External Secrets, puis décider par écrit.

**Prérequis** : M25-E12 (méthode `kubernetes` montée en `k8s-par1`, audience `openbao.medisphere.internal`), M25-E18 (comparaison commencée) ; M20-E13 (`plateforme/charts-miroir`), M14-E18 (Pod Security Admission).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Sealed Secrets | **0.40.0**, chart **`sealed-secrets` 2.20.0 du projet** (`https://bitnami.github.io/sealed-secrets`), image publiée par le projet (`docker.io/bitnami/sealed-secrets-controller`, tirée par le cache `dockerhub` de Harbor) — **jamais** le chart `bitnamicharts/sealed-secrets` du catalogue retiré ; espace **`sealed-secrets`** (PSA `restricted`) ; CLI **`kubeseal` 0.40.0** sur `adm01` (rôle `outils_k8s`) |
| Pilote CSI | **Secrets Store CSI Driver 1.6.1** (chart `secrets-store-csi-driver` 1.6.1, images du cache `k8s`) et fournisseur **OpenBao** `openbao-csi-provider` 2.0.3 (chart `openbao` 0.30.4 avec `server` et `injector` désactivés, images du cache `quay`) ; espace **`essai-csi`** (les deux DaemonSets : pilote **privilégié** et `hostPath` → PSA `privileged`, exception écrite) |
| Argo CD | Applications `essai-sealed-secrets`, `essai-csi-driver`, `essai-openbao-csi` dans `plateforme/gitops/plateforme/`, valeurs dans `valeurs/<application>/values.yaml`, projet `plateforme` ; charts ajoutés à `plateforme/charts-miroir` |
| OpenBao | secret de démonstration `kv/plateforme/essais/csi-demo` (clé `message`, valeur sans importance) ; politique `essai-csi` (lecture de ce seul secret) ; rôle `essai-csi` de `k8s-par1` (compte `essai-csi` de `wb-essais`, audience `openbao.medisphere.internal`, 10 min) — dans `plateforme/secrets`, fichiers **temporaires** `tofu/essais-m25.tf` et `politiques/essai-csi.hcl` |
| Objets d'essai | dans `wb-essais` seulement : un `SealedSecret`, une `SecretProviderClass` (`provider: openbao`, API `secrets-store.csi.x-k8s.io/v1`), un compte de service et un pod `essai-csi` |
| Travail | `~/m25/e19/` : garde `sealedsecret.yaml` (le résultat de `kubeseal`) ; le Secret **en clair** que tu scelles est détruit (`shred -u`) dès le scellement |

> ⚠️ **Mémoire et sécurité.** Le pilote CSI et son fournisseur tournent sur **chaque** nœud (deux DaemonSets, dont un privilégié) : profil serré (≈ 111 Go), arrête ce qui ne sert pas pendant l'essai et ne le laisse pas en place plus que nécessaire. La clé privée du contrôleur Sealed Secrets descelle **tout** ce qui a été scellé pour le cluster : ne l'exporte que dans `~/m25/e19/` le temps de l'étape 4, puis détruis la copie.

**Travail demandé**

1. **Recopie des charts.** Ajoute les trois charts à `plateforme/charts-miroir` (versions exactes, empreintes relevées dans les index et contrôlées), MR, pipeline : ils sont dans Harbor, signés. Ajoute `kubeseal` au rôle `outils_k8s`.
2. **Espaces et Applications.** Déclare les espaces `sealed-secrets` et `essai-csi` dans `plateforme/k8s/espaces/` (étiquettes PSA, annotation d'exception pour `essai-csi`, et la racine MédiSphère dont l'agent du fournisseur aura besoin). Écris les valeurs et les trois Applications (avec un finaliseur de suppression en cascade : pourquoi ici, alors qu'on l'a refusé pour kube-prometheus-stack au M21 ?). MR, synchronisation, pods `Running`.
3. **Sealed Secrets.** Récupère le certificat du contrôleur (`kubeseal --fetch-cert --controller-namespace sealed-secrets`), scelle un Secret fictif de `wb-essais` (portée `strict`, par défaut), applique le `SealedSecret` dans `wb-essais` et regarde le Secret produit (propriétaire, étiquettes). Fais-en une copie dont tu changes **seulement le nom** (`metadata.name`), applique-la dans `wb-essais` : que dit le contrôleur (événements du `SealedSecret`) ? Pourquoi ? Qu'en serait-il dans un autre espace ? Que changent les portées `namespace-wide` et `cluster-wide` ?
4. **La clé du contrôleur.** Liste (sans les afficher) les Secrets de clé de l'espace `sealed-secrets` : combien, pourquoi plusieurs avec le temps (`keyrenewperiod`) ? Exporte la clé privée active dans `~/m25/e19/` et descelle ton `SealedSecret` **hors du cluster** (`kubeseal --recovery-unseal`). Qu'en conclus-tu pour la reprise après sinistre et pour la protection de cette clé ? Détruis la copie.
5. **Pilote CSI.** Écris le secret de démonstration, la politique et le rôle d'essai (MR dans `plateforme/secrets`). Applique la `SecretProviderClass`, le compte et le pod d'essai : le pod lit le secret dans un **fichier** et (par `secretObjects`) dans une variable d'environnement. Puis :
   - change la valeur dans OpenBao : au bout de combien de temps le fichier change-t-il ? la variable ? (règle de rotation du pilote : 2 min) ;
   - retire temporairement la politique au rôle (MR, ou essai noté puis rétabli) et recrée le pod : dans quel état reste-t-il, et que disent ses événements ? Comparez avec un pod qui lit un Secret d'ESO quand le coffre ne répond pas ;
   - dans le journal d'audit (après E21, ou dans les journaux de l'agent avant), quelle identité a lu le secret ?
6. **Mesurer.** Relève la mémoire des composants de chaque approche (Prometheus, `container_memory_working_set_bytes`), le délai de rotation, le comportement quand OpenBao est injoignable, et ce que contient etcd dans chaque cas.
7. **Écrire et décider.** Complète `comparatif-livraison-k8s.md` : tableau des quatre approches (ESO, SOPS, Sealed Secrets, CSI), mesures, décision argumentée pour chacune, et critère de réexamen.
8. **Désinstaller.** Dans l'ordre : objets de `wb-essais`, Applications (MR : la cascade supprime CRD et contrôleurs), espaces, politique et rôle d'essai et secret de démonstration (MR), entrées de `charts-miroir` et de `kubeseal` (MR). Vérifie qu'il ne reste ni CRD, ni espace, ni politique.

**Critères de réussite**
- [ ] La comparaison complète (quatre approches, mesures, décision) est sur `main` de `plateforme/medisphere`.
- [ ] L'historique de `plateforme/gitops` montre l'ajout **puis** le retrait des trois Applications ; aucune n'existe plus dans Argo CD.
- [ ] Les espaces `sealed-secrets` et `essai-csi`, les CRD `sealedsecrets.bitnami.com` et `secretproviderclasses.secrets-store.csi.x-k8s.io` et la politique OpenBao `essai-csi` n'existent plus.
- [ ] `~/m25/e19/sealedsecret.yaml` est un `SealedSecret` de `wb-essais` en portée stricte ; le Secret en clair de l'essai a été détruit.

**Vérification** : `lab/bin/check 25 19` (à la fin, après la désinstallation)

<details><summary>Indice 1</summary>

Le fournisseur CSI demande lui-même au cluster (API *TokenRequest*) un jeton du compte de service **du pod**, avec l'audience écrite dans la `SecretProviderClass` (`audience`) : elle doit être celle qu'exige le rôle OpenBao. Le montage de la méthode se donne par `baoAuthMountPath`. Les journaux utiles sont ceux du conteneur `openbao-agent` du DaemonSet du fournisseur et les événements du pod.
</details>

<details><summary>Indice 2</summary>

Un `SealedSecret` en portée stricte a été chiffré avec, en données associées, l'espace **et** le nom : le contrôleur refuse de le desceller ailleurs. La clé privée active et les anciennes sont des Secrets de l'espace du contrôleur, étiquetés `sealedsecrets.bitnami.com/sealed-secrets-key`.
</details>

<details><summary>Indice 3</summary>

Pour l'agent OpenBao du fournisseur, le chart ne propose pas de réglage d'autorité de certification : il propose `csi.volumes` et `csi.volumeMounts`, montés dans les deux conteneurs du DaemonSet. Un client Go lit `/etc/ssl/certs/ca-certificates.crt`.
</details>

**Pour aller plus loin** (facultatif) : l'injecteur d'agent d'OpenBao (`openbao-k8s`, annotations de pod) comme quatrième approche ; le chiffrement d'etcd et pourquoi aucun plugin KMS v2 n'est disponible pour OpenBao (ADR-0251, E31) ; [Sealed Secrets](https://github.com/bitnami/sealed-secrets), [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/), [fournisseur CSI d'OpenBao](https://openbao.org/docs/platform/k8s/csi/).

---

### M25-E20 — Signer avec une clé qui ne sort jamais du coffre  `LAB` `★★★`

> **Ticket SEC-2620** — *De : Sophie Laurent*
> La clé qui signe nos images vit aujourd'hui dans un Secret Kubernetes monté par le runner protégé, dans un fichier Ansible Vault, et elle a passé des mois dans des variables de CI. Au M26, Kyverno refusera tout ce qui n'est pas signé par elle : elle devient la clé la plus précieuse du cluster. Je veux qu'elle soit dans le coffre, que personne ne puisse l'en sortir, que chaque signature soit tracée avec le projet et le pipeline qui l'ont demandée, et qu'on sache ce qu'on fait des signatures existantes.

**Objectifs pédagogiques**
- Utiliser une clé asymétrique du moteur transit comme clé de signature Cosign (`hashivault://`), et vérifier ce qu'OpenBao reçoit vraiment.
- Donner le droit de signer à un job de CI **par son identité** (jeton GitLab) avec des conditions précises : référence protégée, groupe, runner.
- Découvrir une limite du fournisseur OpenTofu et la contourner proprement.
- Décider du sort de l'ancienne clé et des signatures existantes, en pensant aux vérificateurs (porte de déploiement, Kyverno au M26).

**Prérequis** : M25-E10 (méthode `jwt` montée en `gitlab`, composant `securite` v2.9.0 avec `bao` dans l'image outillée), M25-E17 (transit) ; M19-E24 et E29 (runner protégé, composant `securite` v2.8.0, attestations), M20-E13 (`charts-miroir`), M13-E09 et E14 (Cosign, `docs/registre/cosign.pub`).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Cosign | 3.1.x (image `outils-supply-chain`, `adm01`) : référence de clé **`hashivault://cosign-medisphere`** ; l'adresse et le jeton viennent de `VAULT_ADDR`/`VAULT_TOKEN` **ou** `BAO_ADDR`/`BAO_TOKEN` (à vérifier dans la documentation KMS de Cosign et dans ton essai) ; configuration de signature sans service `/etc/medisphere/signing-config.json` (M13) |
| Clé | transit **`cosign-medisphere`** : `ecdsa-p256`, non exportable, sans sauvegarde en clair, non supprimable, **sans** rotation automatique ; **générée** dans le coffre (pas d'import de l'ancienne : décision à justifier) |
| Politique | **`cosign-signature`** : ce dont Cosign a besoin, et rien d'autre — à déterminer **dans le journal d'audit** ou la documentation, pas au jugé |
| Rôle CI | **`ci-signature`** de la méthode `gitlab` : audience `openbao.medisphere.internal`, référence protégée, groupes `mediagenda`, `medidoc`, `medinotif`, `plateforme`, runner **`k8s-par1-protege`** (son identifiant numérique : *Admin → CI/CD → Runners*), jeton de 10 min, politique `cosign-signature` seule ; projet, référence et pipeline recopiés dans les métadonnées du jeton (`claim_mappings`) pour l'audit |
| Composant | `securite` **v2.10.0** de `plateforme/ci-templates` : `securite:signature` se connecte au coffre par `id_tokens` puis signe et atteste par la clé de transit ; plus aucun fichier de clé ; nouvelle version de l'image outillée avec la **nouvelle** clé publique dans `/etc/medisphere/cosign.pub` |
| Autre signataire | `plateforme/charts-miroir` (`outils/signer.sh`, job `signer`, M20-E13) |
| Publication | `docs/registre/cosign.pub` = nouvelle clé publique ; ancienne gardée sous `docs/registre/cosign-m13.pub` ; décision et procédures dans `docs/securite/secrets/cle-signature.md` |
| À retirer à la fin | Secret `ci-jobs-protege/cosign-medisphere`, son montage dans le runner protégé (`composants/gitlab-runner-protege/values.yaml`), sa ligne de `outils/secrets-k8s.conf`, `secrets/cosign-ci.yml`, les variables Cosign qui resteraient (groupe `plateforme`, `charts-miroir`) |

> ⚠️ **Attention** : changer de clé de signature casse toute vérification qui ne connaît que l'ancienne (porte de déploiement de `…/deploiement`, `securite:verification`, et Kyverno au M26). Ordre imposé : publier la nouvelle clé publique **et** l'embarquer dans les vérificateurs, signer avec la nouvelle, re-signer ce qui est déployé, **puis** retirer l'ancienne. Retour arrière tant que l'ancienne n'est pas détruite : revenir au composant v2.8.0 et à l'ancienne image outillée. Le runner protégé reste le seul à signer : ne retire pas son montage avant que la v2.10.0 ait signé une version avec succès.

**Travail demandé**

1. **Essai à blanc.** Lis la page KMS de la documentation de Cosign. Sur un OpenBao de développement local (`bao server -dev` sur `adm01`, arrêté ensuite), crée une clé `ecdsa-p256`, active un audit vers un fichier (en mode `-dev`, comment fait-on depuis OpenBao 2.4 ?), puis : `cosign public-key --key hashivault://…`, `cosign sign-blob` d'un fichier, `cosign verify-blob` avec la clé publique. Relève dans l'audit les **chemins** appelés : ce sera ta politique. Essaie avec `BAO_ADDR`/`BAO_TOKEN` seuls, puis avec `VAULT_*` seuls.
2. **En code.** Dans `plateforme/secrets` : la clé, la politique, le rôle `ci-signature`. Écris d'abord le rôle avec `vault_jwt_auth_backend_role` et teste une connexion (un job d'essai de `formation/ci-labo` sur `main` et sur une branche, dont tu lis le jeton comme au M19-E25 ; ou, contre ton OpenBao de développement, un jeton que tu signes toi-même avec une clé RSA d'essai déclarée par `jwt_validation_pubkeys`) : la condition sur le runner passe-t-elle ? Lis le rôle tel qu'OpenBao l'a enregistré (`bao read auth/gitlab/role/ci-signature`) et compare avec le type de la revendication `runner_id` dans un jeton GitLab. Trouve un moyen d'écrire le rôle en code **avec les bons types**.
3. **Le composant.** Publie la v2.10.0 de `securite` : connexion au coffre par le jeton d'identité (le JWT ne passe jamais en argument d'une commande), signature et attestations par `hashivault://`, révocation du jeton à la fin du job. Nouvelle version de l'image outillée avec la nouvelle clé publique (et l'empreinte attendue dans la porte du composant `deploiement`). Fais de même pour `charts-miroir`.
4. **Bascule.** Publie `docs/registre/cosign.pub` (nouvelle) et `cosign-m13.pub` (ancienne). Passe `mediagenda/api` sur `@v2.10.0`, pose une étiquette de version : le job tourne-t-il sur le runner protégé ? `cosign verify` avec la **nouvelle** clé publique réussit-il, avec l'**ancienne** échoue-t-il ? Relance le pipeline planifié de `charts-miroir` : que fait `signer.sh` des charts signés par l'ancienne clé ?
5. **Re-signer ce qui est déployé.** Liste les images en `recette` et `prod` (Applications Argo CD, `kustomize build` des overlays), re-signe celles qui ne vérifient pas avec la nouvelle clé (ton identité `plateforme-admins`, ticket CHG-2620 dans le message de chaque commande notée), vérifie.
6. **Retirer l'ancienne clé.** Supprime le montage du runner protégé, la ligne de `secrets-k8s.conf` et le Secret du cluster, puis `secrets/cosign-ci.yml` et les variables Cosign restantes ; décris dans un procès-verbal la destruction des copies de l'ancienne clé privée. Un job sur une branche non protégée, ou sur `main` d'un projet d'un autre groupe, peut-il signer ? Prouve-le (connexion refusée : quel message ?).
7. **Écrire.** `docs/securite/secrets/cle-signature.md` : état avant/après, pourquoi une nouvelle clé plutôt qu'un import, conséquences pour les vérificateurs et pour Kyverno au M26, procédure de rotation future (que devient la clé publique après un `rotate` de transit ?), repli si `hashivault://` cessait de fonctionner avec OpenBao.

**Critères de réussite**
- [ ] `cosign-medisphere` est `ecdsa-p256`, non exportable, sans sauvegarde en clair, non supprimable ; `docs/registre/cosign.pub` est **sa** clé publique, l'ancienne est dans `cosign-m13.pub`.
- [ ] `cosign-signature` permet de signer et de lire la clé publique, rien d'autre ; `ci-signature` n'accepte que l'audience `openbao.medisphere.internal`, les références protégées, le runner protégé (identifiant numérique), pour 15 min au plus.
- [ ] `securite` v2.10.0 et `charts-miroir` signent par `hashivault://cosign-medisphere` ; le runner protégé ne monte plus de clé ; `secrets-k8s.conf` n'a plus de ligne `cosign-ci`.
- [ ] La dernière version de `mediagenda-api` se vérifie avec la nouvelle clé publique ; `cle-signature.md` est sur `main`.

**Vérification** : `lab/bin/check 25 20`

<details><summary>Indice 1</summary>

Cosign lit la clé de transit (`transit/keys/<clé>`, pour la clé publique et la dernière version) puis demande une signature d'empreinte : le chemin exact contient l'algorithme de hachage. Une politique `transit/sign/<clé>` sans ce suffixe ne suffit pas, `transit/sign/*` en donne trop.
</details>

<details><summary>Indice 2</summary>

Dans un jeton GitLab, `ref_protected` est une **chaîne** (`"true"`) mais `runner_id` est un **nombre**. Le fournisseur `hashicorp/vault` décrit `bound_claims` comme une table de chaînes. Le type de comparaison `glob` n'accepte que des chaînes ; `string`, si la valeur liée est elle-même un nombre. La ressource `vault_generic_endpoint` écrit un JSON tel quel.
</details>

<details><summary>Indice 3</summary>

Avec `token_no_default_policy`, le jeton n'a plus la politique `default`… qui donnait `auth/token/revoke-self`. Et en mode `-dev`, un dispositif d'audit se déclare dans un fichier de configuration passé en plus (`-config`).
</details>

**Pour aller plus loin** (facultatif) : signature sans clé (*keyless*) avec Fulcio et un émetteur OIDC interne, et ce qu'il faudrait héberger ; clés ML-DSA du transit d'OpenBao 2.7 et leur prise en charge par Cosign ; [Cosign, gestion des clés KMS](https://docs.sigstore.dev/cosign/key_management/overview/), [jetons d'identité de GitLab](https://docs.gitlab.com/ci/secrets/id_token_authentication/), [méthode JWT d'OpenBao](https://openbao.org/docs/auth/jwt/).

---

### M25-E21 — Audit : qui a lu quel secret  `LAB` `★★`

> **Ticket SEC-2621** — *De : Sophie Laurent*
> Quand Lucas a collé son fichier `.env` dans un ticket, personne n'a su dire qui avait lu ces secrets avant lui, ni après. Avec le coffre, je veux pouvoir répondre en cinq minutes à « qui a lu le mot de passe de la base de prod de MédiAgenda cette semaine », avec des preuves conservées un an. Et je veux être prévenue si quelqu'un se sert d'un jeton racine ou modifie une politique.

**Objectifs pédagogiques**
- Activer l'audit d'OpenBao de façon **déclarative** et comprendre pourquoi l'API ne le permet plus.
- Comprendre ce que contient une ligne d'audit (requête, réponse, identité, HMAC) et ce qui n'y est pas.
- Faire tourner le journal sans perte, l'acheminer vers le bon locataire de Loki, et l'interroger en LogQL.
- Alerter sur les événements qui comptent, et savoir pourquoi un audit en panne arrête le coffre.

**Prérequis** : M25-E08 (`plateforme/secrets`), M25-E17 et E20 (événements à retrouver) ; M22-E05 (rôle `alloy`), M22-E08 (ruler de Loki, règles par locataire), M22 (locataire `audit`, 1 an).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Dispositif | type `file`, chemin `fichier`, fichier **`/var/log/openbao/audit.log`** (dossier `openbao:openbao` 0750 créé par le rôle depuis E03), mode `0640`, **accessors en clair** (`hmac_accessor`) ; déclaré dans `openbao.hcl` par une nouvelle variable du rôle `openbao` (liste de dispositifs) |
| Rotation | `logrotate` (`/etc/logrotate.d/openbao-audit`, gabarit du rôle) : quotidienne, 14 jours, compression, puis **SIGHUP** (`systemctl reload openbao`, `ExecReload` de l'unité du paquet) |
| Acheminement | rôle `alloy` (M22) étendu : le fichier est lu par Alloy (membre du groupe `openbao`) et envoyé au locataire **`audit`** de Loki avec l'étiquette **`service="openbao"`** (liste fermée : `job`, `host`, `site`, `service`) ; variables dans `group_vars/role_coffre/alloy.yml` |
| Alertes | règles du ruler de Loki dans `plateforme/observabilite` : `loki/regles/audit/openbao.yaml` (`OpenBaoJetonRacineUtilise` critique, `OpenBaoPolitiqueModifiee`, `OpenBaoCleTransitModifiee`) et `loki/regles/plateforme/openbao.yaml` (`OpenBaoAuditImpossible`, sur le journal du **service**) ; même mécanisme qu'au M22-E08 (`configMapGenerator` par locataire) |
| Droits | `securite-audit` a déjà `sys/audit` et `sys/audit-hash/*` ; donne-les aussi à `plateforme-admin` (astreinte) |
| Documentation | `docs/securite/secrets/audit-openbao.md` : chaîne, requêtes LogQL, `sys/audit-hash`, alertes, panne de l'audit |

> ⚠️ **Attention** : si **aucun** dispositif d'audit ne peut écrire, OpenBao **refuse toutes les requêtes** — ESO, CI, Ansible, identifiants dynamiques s'arrêtent. Avant d'activer l'audit, vérifie la place libre de `/var/log` sur `vault01`, et n'essaie la panne (étape 6) que sur un OpenBao de développement local, jamais sur `vault01`. Le rechargement (`systemctl reload openbao`) ne scelle pas le coffre ; un **redémarrage**, si : ne redémarre pas `vault01` pour cet exercice.

**Travail demandé**

1. **Essayer l'API.** Avec ton jeton `plateforme-admins`, essaie `bao audit enable file file_path=/var/log/openbao/audit.log`. Quel message ? Lis dans les notes de version d'OpenBao 2.4 la raison (CVE-2025-6000) et la page de configuration `audit` : comment déclare-t-on un dispositif, quand est-il créé, que se passe-t-il si on change une option ou si on retire le bloc ?
2. **Déclarer.** Étends le rôle `openbao` : variable de dispositifs d'audit, bloc `audit` dans le gabarit de `openbao.hcl`, gabarit `logrotate`. MR, playbook sur `vault01`. Le rôle annonce qu'un redémarrage serait nécessaire : pourquoi un **rechargement** suffit-il ici ? Recharge, puis `bao audit list -detailed`. Essaie `bao audit disable fichier` : réponse ?
3. **Lire une ligne.** Fais une lecture KV, une écriture, un refus (`permission denied`), une connexion OIDC. Pour chacune, lis les lignes `request` et `response` (`sudo jq` sur `vault01`) : identité (`auth.display_name`, `auth.metadata`), chemin, opération, adresse, ce qui est en HMAC et ce qui est en clair. Calcule le HMAC d'une valeur connue avec `sys/audit-hash/fichier` (valeur jamais en argument) et retrouve-la. Quels chemins ne sont **jamais** audités ?
4. **Acheminer.** Étends le rôle `alloy` (fichiers d'audit vers le locataire `audit`, étiquette `service`), donne à Alloy la lecture du fichier par le groupe `openbao`, MR, playbook. Dans Grafana (Explore, locataire `audit`), retrouve tes requêtes de l'étape 3. Force une rotation (`sudo logrotate -f /etc/logrotate.d/openbao-audit`) : manque-t-il des lignes dans Loki ?
5. **Interroger.** Écris et range dans `audit-openbao.md` les requêtes LogQL : qui a lu `kv/data/mediagenda/prod/*` ces 7 derniers jours ; tout ce qu'une identité a lu ; les refus ; les modifications de politique ; les signatures Cosign d'E20 avec leur projet et leur pipeline ; tout ce qu'a fait un jeton dont on connaît l'accessor.
6. **La panne de l'audit (OpenBao de développement local).** Démarre un `bao server -dev` avec un dispositif déclaré (fichier passé par `-config`), fais une requête, puis rends le fichier impossible à écrire (remplace-le par un dossier) et recharge : que répond OpenBao aux requêtes, que dit son journal ? Rétablis. Qu'en conclus-tu pour la supervision et pour un second dispositif ?
7. **Alerter.** Écris les règles du ruler (locataires `audit` et `plateforme`), MR, synchronisation : santé `ok` dans l'API du ruler. Déclenche `OpenBaoPolitiqueModifiee` par une MR de `plateforme/secrets` (une politique réelle, par exemple les droits de l'étape « Droits »), et vérifie le courriel dans Mailpit.

**Critères de réussite**
- [ ] Sur `vault01` (et sur chaque nœud qui existe), `openbao.hcl` déclare le dispositif `file` vers `/var/log/openbao/audit.log` avec les accessors en clair ; le fichier est en `0640 openbao` et s'écrit ; `logrotate` le tourne avec un rechargement, sans `copytruncate` ; Alloy le lit.
- [ ] Le locataire `audit` de Loki reçoit `{service="openbao"}` (accessors en clair), le locataire `plateforme` ne le reçoit pas.
- [ ] Les quatre règles sont chargées et saines dans le ruler.
- [ ] `audit-openbao.md` est sur `main`.

**Vérification** : `lab/bin/check 25 21`

<details><summary>Indice 1</summary>

Un dispositif déclaré est créé (ou retiré) sur le nœud actif au démarrage **et à chaque SIGHUP**. Une option modifiée sur un chemin existant est refusée au rechargement et l'ancien dispositif reste actif : pour changer une option, on déclare un nouveau chemin. Lis le journal du service après chaque rechargement.
</details>

<details><summary>Indice 2</summary>

`| json` de LogQL aplatit `request.path` en `request_path` ; avec des expressions (`| json chemin="request.path", qui="auth.display_name"`), tu choisis les noms. Chaque requête produit deux lignes : filtre `type="response"` pour compter une fois. Un jeton racine se repère par ses politiques (`"policies":["root"]`).
</details>

<details><summary>Indice 3</summary>

Quand l'audit ne peut plus écrire, ce n'est pas l'audit qui le dit (il ne peut pas) : c'est le journal du **service** (`journalctl -u openbao`), que le rôle `alloy` envoie déjà au locataire `plateforme` (unité en métadonnée structurée `unite`).
</details>

**Pour aller plus loin** (facultatif) : second dispositif (`syslog` ou `socket` vers Alloy) avec un filtre qui le garde hors du locataire `plateforme` ; options communes des dispositifs (`elide_list_responses`, `skip_test` ; et pourquoi `log_raw` reste à faux) ; [dispositifs d'audit d'OpenBao](https://openbao.org/docs/audit/), [configuration déclarative](https://openbao.org/docs/configuration/audit/), [`sys/audit-hash`](https://openbao.org/api-docs/system/audit-hash/), [requêtes de journaux LogQL](https://grafana.com/docs/loki/latest/query/log_queries/).

---

### M25-E22 — Revue : les politiques du stagiaire  `REV` `★★`

> **Ticket PLAT-2622** — *De : Karim Benali*
> Lucas a ouvert la MR !214 sur `plateforme/secrets` : les accès de l'équipe MédiDoc au coffre. `tofu validate` passe, le plan est propre, et il demande s'il peut fusionner. Fais-en la revue comme si c'était la prod : tout ce qui ne va pas, du plus grave au plus anodin, avec la correction. Et explique-lui, il apprendra plus de ta revue que de la mienne.

**Objectifs pédagogiques**
- Lire une politique HCL comme OpenBao la lit : correspondance des chemins (`*`, `+`), `data/` et `metadata/` du KV v2, capacités, `deny`, `sudo`.
- Relire un rôle d'authentification : ce qui lie un jeton à une identité (revendications, audience, compte de service, CIDR, `secret_id`) et sa durée de vie.
- Distinguer un défaut de sécurité, un défaut de fonctionnement et un choix discutable ; ne pas signaler ce qui est correct.

**Prérequis** : M25-E05 (politiques), M25-E07 (AppRole), M25-E10 (JWT de GitLab), M25-E12 (méthode `kubernetes`), M25-E14 (identifiants dynamiques).
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers de la MR : `modules/25-secrets/ressources/M25-E22/` (`MR-description.md`, `politiques/medidoc-dev.hcl`, `politiques/medidoc-ci.hcl`, `tofu/medidoc.tf`).
- Conventions du coffre (PLAN §4.12 et fichiers des exercices précédents) : `kv/<application>/<env>/<secret>` (MédiDoc : `kv/medidoc/dev/<composant>/<secret>`, `kv/medidoc/prod/…`) ; un rôle JWT `ci-<projet>` par projet ; un rôle Kubernetes et une politique `eso-<espace>` par espace applicatif, compte de service `eso` ; moteur `db-medidoc/` sur le modèle de `db-mediagenda/` (E14) ; audience `openbao.medisphere.internal` partout ; le script de purge de MédiDoc tourne sur `runner02` (10.10.20.17).
- Tu peux charger les politiques dans un OpenBao de développement local et interroger `bao token capabilities` ; ne les applique **pas** sur `vault01`.

**Travail demandé**
1. Lis la description de la MR, puis chaque fichier. Pour chaque défaut : fichier et bloc, gravité (**bloquant** : sécurité ou fonctionnement ; **à corriger** ; **remarque**), ce qui ne va pas, un scénario concret qui le montre (qui obtient quoi), la correction.
2. Vérifie tes affirmations sur les politiques avec un OpenBao de développement : un jeton par politique, `bao token capabilities` sur des chemins bien choisis (dont des chemins d'**autres** équipes).
3. Repère aussi ce qui est **correct** dans la MR (au moins un bloc) : une revue qui signale tout n'aide personne.
4. Écris la revue dans `~/m25/e22/revue.md` sous forme de commentaires de MR (un par défaut), puis les fichiers corrigés dans `~/m25/e22/corrige/`.
5. Termine par un paragraphe pour Lucas : les trois règles qu'il doit retenir.

**Critères de réussite**
- [ ] Au moins dix défauts réels identifiés et classés, chacun avec un scénario et une correction.
- [ ] Les affirmations sur les politiques sont étayées par `bao token capabilities` (sorties dans la revue).
- [ ] Les fichiers corrigés passent `bao policy fmt` et `tofu validate`, et ne gardent aucun des défauts.

*Auto-évaluation avec le corrigé (pas de vérification automatique).*

<details><summary>Indice 1</summary>

Dans le KV v2, `kv/data/…` porte les valeurs, `kv/metadata/…` les versions et la suppression **définitive** ; `+` remplace exactement **un** segment ; un `deny` l'emporte sur tout ; `sudo` ne sert que sur les chemins qui l'exigent (et il y donne beaucoup).
</details>

<details><summary>Indice 2</summary>

Pour chaque rôle, pose la question : « qui, exactement, peut obtenir ce jeton ? » — quelle branche de quel projet, quel pod de quel espace, quelle machine avec quel secret. Puis : « combien de temps ce jeton vit-il après la fin de son usage ? ». Regarde aussi quelle **politique** chaque rôle reçoit.
</details>

---

### M25-E23 — Runbook : un secret a fuité  `RED` `★★`

> **Ticket INC-5223** — *De : Nadia Roussel*
> Hier soir, un développeur de MédiDoc a collé dans le canal de l'équipe la sortie d'un job de CI qui contenait un jeton OpenBao et le mot de passe d'un compte de service. Personne n'a su quoi faire dans l'ordre : on a supprimé le message, on a hésité, on a appelé Karim à 23 h. Je veux un runbook que la personne d'astreinte suit seule, pour **tout** type de secret du coffre, et qui laisse des preuves exploitables par Sophie.

**Objectifs pédagogiques**
- Organiser la réponse à une fuite : contenir, qualifier, tourner, vérifier, enquêter, prouver, communiquer, clôturer.
- Connaître le geste de contention et de rotation propre à chaque type de secret du coffre (jeton, `secret_id`, KV, dynamique, certificat, clé de transit, clé de signature, secrets d'autres systèmes).
- S'appuyer sur l'audit (E21) pour l'enquête, sans exposer davantage le secret.

**Prérequis** : M25-E07, E10, E14, E16, E17, E20, E21 ; M19-E40 (RB-198, fuite d'un secret de CI) ; M22 (post-mortems).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Emplacement : `docs/securite/secrets/runbooks/RB-250-fuite-de-secret.md` de `plateforme/medisphere`. RB-198 (M19) reste le runbook des secrets **de GitLab** ; RB-250 couvre le coffre et ce qu'il délivre, et renvoie à RB-198 pour la partie GitLab.
- Inventaire des secrets (propriétaire, emplacement, consommateurs) : `docs/securite/secrets/inventaire-secrets.md` (E02).
- Les gestes de révocation par préfixe exigent `sudo` : le runbook dit **qui** les détient (et propose la MR de politique si personne ne les a).
- MédiSphère est hébergeur de données de santé : la RSSI décide de la notification d'une violation de données personnelles (CNIL, 72 h) ; le runbook lui fournit les faits.

**Travail demandé**
1. Écris RB-250 avec au moins : déclencheurs ; rôles ; les dix premières minutes ; une échelle de gravité avec délais ; un tableau « type de secret → contenir → tourner » couvrant tous les types délivrés par le coffre aux exercices précédents ; les vérifications de retour à la normale ; l'enquête (questions dans l'ordre, requêtes de `audit-openbao.md`, recherche par HMAC et par accessor) ; la conservation des preuves (où, comment, sans recopier le secret) ; la communication ; une liste de clôture ; les commandes de référence (aucun secret en argument).
2. Rejoue mentalement l'incident de Nadia avec ton runbook : jeton OpenBao d'un job de CI de MédiDoc + mot de passe d'un compte de service rangé dans le KV. Écris dans `~/m25/e23/rejeu.md` la chronologie que tu aurais suivie, minute par minute, et les endroits où ton runbook t'a manqué (corrige-le).
3. Si un geste exige un droit que personne n'a (par exemple la révocation par préfixe), propose la MR de politique et justifie-la.
4. MR, relue par Nadia (astreinte) et Sophie (RSSI) : chacune doit pouvoir dire « je saurais le suivre seule ».

**Critères de réussite**
- [ ] RB-250 est sur `main` et couvre chaque type de secret du coffre avec un geste de contention et de rotation.
- [ ] L'enquête s'appuie sur des requêtes LogQL précises et sur `sys/audit-hash`, sans recopier le secret.
- [ ] Le rejeu de l'incident tient en moins de 60 minutes jusqu'à la fin de la rotation, et les manques trouvés sont corrigés dans le runbook.

*Auto-évaluation avec le corrigé ; le runbook sert au M25-E34 (rotation d'urgence chronométrée).*

<details><summary>Indice 1</summary>

Un jeton vu en clair se révoque par son **accessor** (en clair dans l'audit depuis E21), ce qui révoque aussi ses jetons enfants et leurs baux. Un `secret_id` d'AppRole se détruit par son propre accessor. Pour un secret statique, l'ordre compte : nouvelle valeur dans le système cible, puis dans le coffre, puis vérification que l'ancienne est **refusée**.
</details>

<details><summary>Indice 2</summary>

« Qui a lu » se demande au coffre (audit) ; « qui a **utilisé** la valeur fuitée » se demande au système cible (journaux de PostgreSQL, de GitLab, de Keycloak…). Les deux questions n'ont pas la même réponse.
</details>

**Pour aller plus loin** (facultatif) : un exercice de table (*tabletop*) avec Nadia et Sophie sur un scénario G1 (jeton `plateforme-admin` fuité) ; [baux et révocation](https://openbao.org/docs/concepts/lease/), [jetons et accessors](https://openbao.org/docs/concepts/tokens/), guide de la CNIL sur la notification des violations de données personnelles.
