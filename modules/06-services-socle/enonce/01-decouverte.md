# Module 06 — Palier 1 : Découverte

Le socle tient sur trois solutions provisoires : une CA bricolée avec `openssl`, dnsmasq qui fait tout, des adresses notées dans un tableau. Ce palier pose les trois briques qui les remplacent, chacune par le chemin habituel (OpenTofu, rôle Ansible testé, pipeline) : une **PKI** à deux niveaux dont la racine ne touche aucune machine en ligne, puis la confiance de tout le socle basculée vers elle ; **NetBox**, installé et rempli avec le plan d'adressage de MédiSphère ; **PowerDNS**, serveur faisant autorité et résolveur, construit à côté de dnsmasq puis mis à sa place sans que personne ne s'en aperçoive. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 05 terminé (`lab/bin/check 05 46` vert) ; module 04 (rôles, Vault à deux identités, Molecule, pipeline de `plateforme/ansible`) ; module 03 (image dorée `current`, pipeline de `plateforme/images`). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M06-E01 — Test de positionnement : services d'infrastructure  `Q` `★★`

> **Ticket PLAT-701** — *De : Karim Benali*
> Le rituel : DNS, DHCP, PKI, SSH, temps, source de vérité. Par écrit, sans moteur de recherche ni IA, sans rien exécuter, une heure. Ce sont des protocoles qu'on croit connaître parce qu'on s'en sert tous les jours ; ce module va les démonter. Réponds même là où tu hésites : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les protocoles d'infrastructure que le module met en production.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*DNS*

1. Distingue serveur **faisant autorité** et **résolveur récursif** : ce que chacun détient, à qui il pose des questions, ce que signifient les drapeaux `aa`, `rd` et `ra` d'une réponse. Pourquoi les séparer, alors que dnsmasq fait les deux très bien dans un petit réseau ?

2. *(QCM)* Un client demande `AAAA` pour `git01.par1.medisphere.internal`, qui n'a qu'un enregistrement `A`. Que reçoit-il d'un serveur correctement configuré ?
   - A. `NXDOMAIN`
   - B. `NOERROR` avec une section réponse vide
   - C. `SERVFAIL`
   - D. `REFUSED`

3. Décris les champs d'un enregistrement **SOA**. À quoi sert le numéro de série ? Que se passe-t-il si quelqu'un le fait **diminuer** sur le serveur primaire ?

4. La zone `medisphere.internal` délègue `par1.medisphere.internal` au serveur `dns01.par1.medisphere.internal`. Pourquoi la zone parente doit-elle contenir, en plus de l'enregistrement NS, un enregistrement A pour `dns01.par1.medisphere.internal` ? Comment appelle-t-on cet enregistrement ?

5. *(QCM)* Un résolveur vient de recevoir `NXDOMAIN` pour `nexistepas.par1.medisphere.internal`. Combien de temps garde-t-il cette réponse négative ?
   - A. Le TTL par défaut du résolveur
   - B. Le plus petit des deux : le TTL de l'enregistrement SOA et le dernier champ du SOA
   - C. Il ne la garde pas : une réponse négative ne se met jamais en cache
   - D. Le champ « refresh » du SOA

6. Qu'est-ce que le drapeau `ad` dans une réponse ? Pourquoi un résolveur qui **valide** DNSSEC peut-il refuser de répondre (SERVFAIL) pour une zone interne comme `medisphere.internal`, alors que la zone est parfaitement servie ? Cite deux façons de régler le problème.

7. Dans quels cas une question DNS passe-t-elle en **TCP** ? Que se passe-t-il si un pare-feu ne laisse passer que l'UDP 53 ?

*DHCP*

8. Rappelle l'échange DORA à travers un **relais** (M00-E14) : à quoi sert le champ `giaddr` ? Puis : quand un client obtient un bail, qui peut mettre à jour le DNS avec son nom, et avec quelle option DHCP le client l'y aide-t-il ?

9. *(QCM)* Deux serveurs DHCP servent la même plage d'un sous-réseau, sans se coordonner. Quel est le risque principal ?
   - A. Aucun : le client prend la première offre, les deux serveurs se partagent la charge
   - B. Les deux serveurs peuvent attribuer la même adresse à deux clients différents
   - C. Le relais refuse de transmettre vers deux serveurs
   - D. Les clients reçoivent deux adresses sur la même interface

10. À quoi correspondent les instants **T1** et **T2** d'un bail ? Que fait le client à chacun, et vers qui envoie-t-il sa demande ?

*PKI et TLS*

11. Lors d'une poignée de main TLS, quels certificats le serveur doit-il envoyer ? Pourquoi n'envoie-t-il pas la racine ? Que doit déjà posséder le client ?

12. Pourquoi une PKI d'entreprise a-t-elle une **racine hors ligne** et une **autorité intermédiaire** en ligne ? Compare les conséquences d'une compromission de la clé de l'intermédiaire et de celle de la racine.

13. *(QCM)* Un certificat serveur porte `CN=git01.par1.medisphere.internal` et **aucune** extension *Subject Alternative Name*. Que fait un navigateur ou un client TLS récent ?
   - A. Il l'accepte : le CN suffit
   - B. Il le refuse : seul le SAN est examiné pour vérifier le nom
   - C. Il l'accepte avec un avertissement
   - D. Il l'accepte si le certificat est signé par une racine de confiance

14. Un certificat volé reste utilisable jusqu'à son expiration… sauf révocation. Compare les deux stratégies : **révocation** (CRL, OCSP) et **certificats de courte durée**. Pourquoi l'industrie va-t-elle vers la seconde ?

15. Le protocole **ACME** propose les défis HTTP-01, DNS-01 et TLS-ALPN-01. Pour chacun : que doit prouver le client, quel flux réseau est nécessaire, et lequel permet d'obtenir un certificat générique (`*.par1.medisphere.internal`) ?

16. *(QCM)* Que signifie `basicConstraints = critical, CA:TRUE, pathlen:0` dans le certificat d'une autorité ?
   - A. Elle peut signer d'autres autorités, sans limite de profondeur
   - B. Elle peut signer des certificats finaux, mais aucune autre autorité
   - C. Elle ne peut rien signer
   - D. Elle ne peut signer que des certificats d'une durée nulle (révoqués)

*SSH*

17. Qu'est-ce que le modèle **TOFU** (*trust on first use*) des clés d'hôte SSH ? Quel risque fait-il courir dans un parc où l'on crée et détruit des VMs chaque jour ? Qu'apporte un **certificat d'hôte** signé par une CA, et que contient la ligne `@cert-authority` d'un fichier `known_hosts` ?

18. Un certificat SSH d'**utilisateur** contient des *principals* et une période de validité. À quoi servent-ils côté serveur ? Qu'est-ce que cela change par rapport à des clés publiques déposées dans `authorized_keys` ?

*Source de vérité et temps*

19. Qu'appelle-t-on une **source de vérité** ? Distingue l'**intention** (ce qui devrait exister) et la **réalité** (ce qui tourne). Donne un exemple de désaccord entre NetBox et Proxmox, et dis lequel des deux devrait l'emporter.

20. Cite trois mécanismes qui cessent de fonctionner quand l'horloge d'une machine dérive de quelques minutes. Que garantit **NTS** (*Network Time Security*) que NTP classique ne garantit pas ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions DNS, distingue toujours **qui parle à qui** : client → résolveur (question récursive, drapeau `rd`), résolveur → serveur faisant autorité (question itérative). Beaucoup de réponses en découlent.
</details>

<details><summary>Indice 2</summary>

Pour la PKI, dessine la chaîne : racine → intermédiaire → certificat final. Pour chaque maillon, demande-toi où est sa clé privée, qui en a besoin, et ce qu'on doit refaire si elle fuit.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M06-E46), sans relire le corrigé, et compare.

---

### M06-E02 — Déployer `ca01` et initialiser step-ca  `LAB` `★★`

> **Ticket SEC-702** — *De : Sophie Laurent* — *Copie : Claire Morel*
> La CA « provisoire » du module 01 n'en a que le nom : clé sur un poste d'administration, pas de politique, des certificats signés à la main pour un an. Pour l'audit HDS, il me faut une vraie PKI à deux niveaux. La **racine** est créée lors d'une cérémonie tracée, sa clé ne vit sur aucun serveur en ligne et elle est sauvegardée chiffrée. L'**intermédiaire** tourne sur une machine dédiée, `ca01`, et délivre des certificats courts. Je veux pouvoir dire à l'auditeur : voici où est chaque clé, qui peut s'en servir, et ce qui se passe si l'une fuit.

**Objectifs pédagogiques**
- Comprendre ce que produit `step ca init` (fichiers, clés, provisioners) avant de l'industrialiser.
- Réaliser une **cérémonie de racine hors ligne** : création, archivage chiffré, signature d'un intermédiaire à partir d'une demande (CSR) produite sur la machine qui le portera.
- Déployer step-ca par le chemin standard : VM par OpenTofu, rôle Ansible testé par Molecule, secrets en Vault « critique ».
- Configurer les **provisioners** et la politique de durées (*claims*) d'une CA.

**Prérequis** : M05-E46 (socle déclaré, pipelines `plateforme/infra` et `plateforme/ansible`) ; M04-E30 (Vault à deux identités) ; M04-E24 (Molecule).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `ca01`, VMID 1003, 10.10.20.11/24 sur `vinfra`, passerelle 10.10.20.1 ; 1 vCPU, 1 Go, disque 10 Go ; étiquettes `socle`, `role-pki` ; protection Proxmox ; démarrage automatique, rang 3 (après `gw01` et `dns01`, avant `git01` et `s3-01`) |
| Création | état `socle` de `plateforme/infra`, module `vm-debian` à sa dernière version publiée |
| Paquets | `step-ca` 0.30 et `step-cli` 0.31 du dépôt APT Smallstep (`https://packages.smallstep.com/stable/debian`, suite `debs`) ; clé de signature `https://packages.smallstep.com/keys/apt/repo-signing-key.gpg`, empreinte `35BA A0B3 3E9E B396 F59C A838 C0BA 5CE6 DC63 15A3` |
| Emplacements sur `ca01` | `/etc/step-ca` (`STEPPATH`) : `config/ca.json`, `certs/`, `secrets/`, `db/`, `password.txt` ; compte de service `step` ; unité systemd `step-ca` (modèle du guide de production Smallstep) ; écoute sur le port 443 |
| Racine | sujet `CN=MédiSphère Root CA`, courbe P-384, 10 ans ; dossier `~/pki-racine` sur `adm01` (700) ; clé chiffrée par une phrase de passe tapée au clavier ; archive chiffrée dans `~/pki-racine/archives/` |
| Intermédiaire | sujet `O=MédiSphère, CN=MédiSphère Intermediate CA`, courbe P-256, 5 ans, `pathlen:0` ; clé **générée sur `ca01`** |
| Provisioners | `admin` (JWK) : émission manuelle, 90 jours au plus, peut signer des certificats SSH ; `acme` (ACME) : 30 jours au plus ; `sshpop` : renouvellement des certificats SSH |
| Durées globales | serveur TLS 30 jours (720 h) par défaut et au plus ; SSH : hôtes 30 jours, utilisateurs 16 heures ; CA SSH activée |
| Certificats publics | `pki/medisphere-root-ca.crt` et `pki/medisphere-intermediate-ca.crt` à la racine du projet `plateforme/ansible` (versionnés) |
| Secrets | Vault `critique`, `group_vars/role_pki/vault-critique.yml` : `vault_step_ca_mot_de_passe` (clés en ligne de `ca01`), `vault_step_ca_admin_cle_chiffree` (clé privée JWK du provisioner `admin`, chiffrée), `vault_step_ca_mot_de_passe_admin` ; sur `adm01` : `~/.config/workbook/step-admin.pass` (600) |
| Molecule | scénario `step_ca`, instance VMID 2046 (partagé avec `ssh_durci`, M04-E24) |

**Travail demandé**

*A. Comprendre avant d'industrialiser (sur `adm01`, dans un dossier jetable)*

1. Installe la commande `step` sur `adm01` **par le code** : le rôle `step_ca` que tu vas écrire aura un point d'entrée `client` (dépôt Smallstep vérifié par son empreinte, paquet `step-cli` figé) ; un petit playbook l'applique au groupe `role_bastion`. Commence par ce point d'entrée, applique-le, vérifie `step version`.
2. Dans un dossier temporaire, lance un `step ca init` complet (déploiement autonome, nom au choix, provisioner JWK, ACME et SSH activés), avec `STEPPATH` pointant vers ce dossier. Liste ce qui a été créé. Note dans ton journal : combien de clés privées, protégées par quel(s) mot(s) de passe, où est la clé de la racine, ce que contient le provisioner JWK dans `ca.json` (champs `key` et `encryptedKey`), à quoi sert `defaults.json`.
3. Réponds : pourquoi ce résultat ne convient-il pas tel quel à la production de MédiSphère ? Puis détruis le dossier.

*B. La cérémonie de la racine (sur `adm01`)*

4. Prépare `~/pki-racine` (droits **avant** toute génération). Crée la racine : la phrase de passe est saisie au clavier et rangée dans ton gestionnaire de mots de passe. Note l'empreinte SHA-256 du certificat.
5. Fais une archive **chiffrée** du dossier (phrase différente), copie-la hors de `adm01` (support amovible rangé au coffre) en plus de la sauvegarde PBS nocturne de `adm01`. Rédige le procès-verbal de la cérémonie : `docs/socle/pki/ceremonie-racine.md` (date, participants, commandes, empreinte, emplacements des copies, qui détient les phrases de passe).
6. Copie le **certificat** (public) de la racine dans `pki/` du projet Ansible.

*C. La machine*

7. Déclare `ca01` dans l'état `socle` de `plateforme/infra` (MR, plan relu, `apply` par le pipeline). Déclare son nom dans le DNS du moment (rôle `dnsmasq`), puis vérifie A et PTR. Ajoute l'alias SSH et la clé d'hôte au `known_hosts` du projet Ansible ; vérifie que l'inventaire dynamique la range dans `socle` et `role_pki`.

*D. Le provisioner `admin`*

8. Sur `adm01`, génère la paire de clés JWK du provisioner `admin`, chiffrée par un mot de passe que tu ranges dans `~/.config/workbook/step-admin.pass`. La partie **publique** va dans l'inventaire (`group_vars/role_pki/`), la partie privée **chiffrée** (forme compacte JWE) dans Vault `critique`. Pourquoi peut-on se permettre de mettre cette clé chiffrée sur `ca01`, et pas la racine ?

*E. Le rôle `step_ca`*

9. Écris le rôle (et son scénario Molecule, qui fabrique sa propre PKI de test) : paquets figés, compte `step`, arborescence et droits, mot de passe des clés en ligne, certificat de la racine, **clé et CSR de l'intermédiaire générées sur l'hôte**, vérification que le certificat signé correspond à la clé, clés de la CA SSH, `ca.json` généré, unité systemd, contrôle de santé après redémarrage avec retour à la configuration précédente en cas d'échec. Le rôle ne doit jamais trouver de clé de racine sur l'hôte : il refuse de continuer s'il en voit une.
10. Premier passage sur `ca01` : le rôle s'arrête proprement après avoir produit la CSR de l'intermédiaire et l'avoir rapatriée dans `pki/`. Inspecte la CSR (sujet, clé publique), signe-la avec la racine sur `adm01` (profil d'autorité intermédiaire, 5 ans, aucune autorité en dessous), vérifie le certificat obtenu, ajoute-le à `pki/`. Second passage : la CA démarre.

*F. Vérifier en client*

11. Sur `adm01`, configure le client `step` vers `https://ca01.par1.medisphere.internal` **en vérifiant l'empreinte de la racine** notée en B. Vérifie la santé de la CA, la chaîne qu'elle présente, la liste des provisioners.
12. Émets un certificat de test d'une durée de 30 jours avec le provisioner `admin`, inspecte-le (émetteur, SAN, durée, usages), vérifie-le jusqu'à la racine. Tente ensuite une durée de 100 jours : note le message. Supprime la clé de test.
13. Mets à jour l'inventaire du socle, la matrice des flux (rien de nouveau : dis pourquoi) et le registre des secrets (phrases de la racine et de l'archive, mot de passe des clés en ligne, mot de passe et clé du provisioner `admin` : emplacements et détenteurs, jamais les valeurs).

**Critères de réussite**
- [ ] La VM 1003 `ca01` est créée par OpenTofu (déclarée dans l'état `socle`), conforme au tableau, résolue en A et PTR.
- [ ] `~/pki-racine` est en 700 et contient la clé de la racine **chiffrée** (600) et au moins une archive chiffrée ; le procès-verbal de cérémonie est publié.
- [ ] La racine du dépôt est auto-signée, `CA:TRUE`, valable 10 ans ; l'intermédiaire est signé par elle, avec `pathlen:0`.
- [ ] Sur `ca01`, `step-ca` tourne sous le compte `step`, écoute sur 443, et `/etc/step-ca/secrets/` ne contient que la clé de l'intermédiaire et les deux clés de la CA SSH : aucune clé de racine sur `ca01`.
- [ ] Depuis `adm01`, `https://ca01.par1.medisphere.internal/health` répond avec un TLS vérifié par la **seule** racine MédiSphère ; les provisioners `admin`, `acme` et `sshpop` sont publiés ; l'annuaire ACME répond ; une demande de certificat de plus de 90 jours est refusée.
- [ ] Le rôle `step_ca` et son scénario Molecule sont sur `main` (Molecule et `ansible-lint` verts) ; les secrets de la PKI sont chiffrés sous l'identité `critique` ; un second passage du playbook donne `changed=0`.

**Vérification** : `lab/bin/check 06 02`

<details><summary>Indice 1</summary>

Le guide « Production considerations » de Smallstep décrit exactement la cible : racine hors ligne, CSR de l'intermédiaire signée par la racine, compte de service, unité systemd. Côté commandes, `step certificate create` (avec `--profile root-ca`, ou `--csr`), `step certificate sign` (avec `--profile intermediate-ca`), `step crypto jwk create` et `step crypto jose format` couvrent la cérémonie et le provisioner. `step ca bootstrap` configure le client.
</details>

<details><summary>Indice 2</summary>

Une CSR dont le sujet contient des caractères accentués peut être refusée par `step certificate create --csr` : par défaut, le nom passé en argument est aussi ajouté aux SAN, qui n'acceptent que de l'ASCII. Un **modèle** (`--template`) qui ne décrit que le sujet règle la question. Le rôle doit aussi pouvoir s'arrêter « proprement » pour un hôte sans échouer le passage : regarde `meta: end_host`.
</details>

<details><summary>Indice 3</summary>

`ca.json` est du JSON : plutôt qu'un modèle Jinja qui écrit du JSON à la main (virgules, guillemets), construis une structure (dictionnaire) et sérialise-la avec `to_nice_json`. Les provisioners sont alors une simple liste de dictionnaires dans l'inventaire. Pour vérifier que le certificat signé correspond à la clé de l'hôte, compare les clés publiques (`step certificate key` et `step crypto key public`).
</details>

**Pour aller plus loin** (facultatif) : lis la section « Cryptographic Protection » de la documentation step-ca : clé de l'intermédiaire dans un HSM ou un TPM (le TPM d'une VM Proxmox est virtuel : qu'est-ce que cela protège, et contre quoi ?). Imagine une cérémonie à deux personnes avec un partage de secret (Shamir) pour la phrase de la racine.

---

### M06-E03 — Faire confiance à la nouvelle PKI  `LAB` `★★`

> **Ticket SEC-703** — *De : Sophie Laurent*
> La racine existe, très bien. Maintenant je veux que **tout** le socle lui fasse confiance, que GitLab et le stockage S3 présentent des certificats émis par elle, et que la CA provisoire disparaisse : plus aucune machine ne doit la croire. Fais-le sans casser la forge ni l'état OpenTofu un seul instant. Et je veux la liste de tous les endroits où « faire confiance à une CA » se configure chez nous : je sais qu'il y en a plus d'un.

**Objectifs pédagogiques**
- Inventorier les **magasins de confiance** d'un parc (système, applications qui embarquent le leur, images, variables de clients) et leur mise à jour.
- Conduire un changement de racine avec **période de recouvrement** : ajouter, basculer, vérifier, retirer.
- Étendre un rôle partagé de collection (versionnement SemVer) pour qu'il sache **retirer** une confiance, pas seulement l'ajouter.
- Émettre des certificats serveur avec step-ca et les déposer dans des services existants.

**Prérequis** : M06-E02 ; M04-E18 (collection `medisphere.socle`, rôle `ca_lab`) ; M03 (pipeline des images, `outils/publier-image.sh`) ; M01-E04 (CA provisoire, certificat de `git01`) ; M05-E10 (certificat de `s3-01`).
**Durée indicative** : 3 h.

**Contexte technique**
- Certificats à remplacer : `git01` (`/etc/gitlab/ssl/git01.par1.medisphere.internal.crt` et `.key`, M01-E04) et `s3-01` (passerelle S3 HTTPS sur le port 8333, certificat déployé par ton rôle `seaweedfs`, M05-E10). Mêmes noms dans les SAN qu'aujourd'hui (FQDN, nom court, adresse IP).
- Émission : provisioner `admin` de `ca01`, **90 jours** au plus. Ces certificats sont transitoires : M06-E18 les remplace par des certificats ACME renouvelés automatiquement. Note leur échéance dans l'inventaire.
- Magasin système Debian : `/usr/local/share/ca-certificates/<nom>.crt` puis `update-ca-certificates` ; lien résultant `/etc/ssl/certs/<nom>.pem`. Nom de la nouvelle racine : `medisphere-root-ca`. Rôle : `medisphere.socle.ca_lab` (collection interne, version 1.0.0 au module 04).
- GitLab embarque son propre magasin : `/etc/gitlab/trusted-certs/` (pris en compte par `gitlab-ctl reconfigure`).
- Image dorée : la CA provisoire y est installée par `plateforme/images` (`fichiers/ca/`, M03-E09) ; toute nouvelle VM la recevrait encore.
- La clé privée de la CA provisoire est dans `~/pki-provisoire/` sur `adm01` (M01-E04).

**Travail demandé**
1. **Inventaire.** Avant de toucher à quoi que ce soit, dresse dans ton journal la liste de tous les endroits du lab qui font confiance à la CA provisoire : hôtes, applications avec leur propre magasin, images, variables d'environnement de clients (pense aux outils Python, Node, Go, à GitLab, à Packer, à OpenTofu…). Pour chacun : comment il apprend une nouvelle autorité.
2. **Le rôle.** Fais évoluer `ca_lab` : il installe la racine MédiSphère par défaut et sait **retirer** une liste d'autorités (reconstruction complète du magasin), puis vérifie le magasin consolidé. Version **mineure** suivante de la collection (pourquoi mineure ?), CHANGELOG, documentation du rôle. Applique-le à **tout** le socle via les rôles communs, `adm01` compris. Le rôle `gitlab_runner`, qui appelait `ca_lab` avec la CA provisoire, doit suivre.
3. **Recouvrement.** Les deux autorités sont maintenant de confiance partout. Vérifie-le sur chaque hôte, et dans le magasin de GitLab (ajoute la racine à `/etc/gitlab/trusted-certs/`, au moyen de l'outil de GitLab).
   > ⚠️ **Attention** : `gitlab-ctl reconfigure` réapplique toute la configuration de GitLab. Fais-le dans un créneau annoncé, après un instantané de `git01`, et vérifie l'état des services ensuite (`gitlab-ctl status`).
4. **Bascule des certificats.** Émets les nouveaux certificats de `git01` et de `s3-01` (un petit script réutilisable sur `adm01` est bienvenu : il servira encore en E04). Déploie-les : pour `git01`, comme en M01-E04 (fichier `.crt` = chaîne complète) puis rechargement de NGINX ; pour `s3-01`, par ton rôle `seaweedfs` (clé en Vault). Vérifie chaque service depuis plusieurs clients **avec la seule nouvelle racine** : `adm01`, `runner01`, un `tofu plan` de l'état `socle` (le backend S3 parle TLS à `s3-01`), un pipeline de la forge.
5. **Images.** Remplace la CA provisoire par la racine MédiSphère dans `plateforme/images`, construis et publie une nouvelle image `current` par le pipeline habituel.
6. **Retrait.** Quand plus rien ne présente de certificat de la CA provisoire, retire-la de partout par le code, puis de GitLab. Archive `~/pki-provisoire` chiffré (comme la racine) et supprime les clés privées en clair. Note dans le registre des secrets que ces clés ne sont plus en service.
7. **Documentation.** Ajoute à `docs/socle/pki/` la liste des magasins de confiance (ton inventaire de l'étape 1, mis à jour) : c'est elle qu'on relira le jour où il faudra changer de racine.

**Critères de réussite**
- [ ] Les sept hôtes du socle (`gw01`, `adm01`, `dns01`, `ca01`, `git01`, `s3-01`, `runner01`) ont la racine MédiSphère dans leur magasin système et **ne font plus confiance** à la CA provisoire.
- [ ] `git01:443` et `s3-01:8333` présentent un certificat émis par « MédiSphère Intermediate CA », avec la chaîne complète, vérifiable par la seule racine MédiSphère.
- [ ] Le magasin de GitLab contient la racine ; `runner01` et `adm01` joignent `git01` et `s3-01` en HTTPS vérifié ; `tofu plan` de l'état `socle` fonctionne.
- [ ] La collection `medisphere.socle` est en 1.1.x, `ca_lab` sait retirer une autorité, et un second passage des rôles communs donne `changed=0`.
- [ ] La nouvelle image `current` contient la racine MédiSphère et pas la CA provisoire.
- [ ] `~/pki-provisoire` ne contient plus aucune clé privée en clair.

**Vérification** : `lab/bin/check 06 03`

<details><summary>Indice 1</summary>

Pour trouver les magasins « cachés » : cherche dans les dépôts et sur les hôtes les mentions `provisoire`, `ca.crt`, `CA_BUNDLE`, `cacert`, `ca_path`, `ca_file`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, `trusted-certs`. Une bibliothèque Python comme `requests` a son propre magasin (paquet `certifi`) quand on ne lui en désigne pas un autre.
</details>

<details><summary>Indice 2</summary>

`update-ca-certificates` ajoute les nouveaux certificats et retire les liens de ceux qui ont disparu ; l'option `--fresh` reconstruit tout depuis zéro. Pour vérifier qu'une autorité est bien dans le magasin consolidé, cherche son contenu dans `/etc/ssl/certs/ca-certificates.crt`.
</details>

<details><summary>Indice 3</summary>

L'ordre est la clé : d'abord la confiance (nouvelle racine partout, y compris dans les magasins applicatifs), ensuite les certificats des services, enfin le retrait de l'ancienne confiance. À l'envers, chaque étape casse quelque chose. Pour prouver qu'un client fait confiance à la nouvelle racine **seule**, donne-lui explicitement ce seul fichier (`curl --cacert`, `openssl s_client -CAfile … -verify_return_error`).
</details>

**Pour aller plus loin** (facultatif) : imagine la procédure du jour où il faudra changer de **racine** (dans dix ans, ou après une compromission) : combien de temps de recouvrement, que se passe-t-il pour les clients qu'on ne gère pas (navigateurs des équipes, postes de travail) ? Lis comment les distributions gèrent le retrait d'une autorité publique compromise.

---

### M06-E04 — Déployer NetBox sur `nbx01`  `LAB` `★★`

> **Ticket PLAT-704** — *De : Claire Morel*
> Notre « inventaire » est un fichier Markdown et un tableur que Karim met à jour quand il y pense. Pour le bloc B, ce sera des centaines d'adresses. Je veux NetBox, installé proprement sur `nbx01`, en HTTPS avec un certificat de notre PKI, reconstruisible par le code. Pas de conteneur ici : on l'installe comme la documentation le décrit, on doit savoir ce qui tourne et où. Et je veux des comptes nominatifs, pas un `admin` partagé.

**Objectifs pédagogiques**
- Installer une application Python complète (base PostgreSQL, cache et file de tâches Valkey, serveur d'application gunicorn, frontal nginx) en suivant la documentation officielle, transposée dans un rôle Ansible.
- Maîtriser les secrets propres à NetBox (`SECRET_KEY`, poivres des jetons API v2) et le modèle de jetons v2.
- Durcir l'exposition réseau : seul nginx (TLS) écoute sur le réseau.

**Prérequis** : M06-E03 (racine de confiance partout, script d'émission de certificat) ; M05-E46 ; M04-E30.
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `nbx01`, VMID 1005, 10.10.20.13/24 sur `vinfra` ; 2 vCPU, 4 Go, disque 30 Go ; étiquettes `socle`, `role-netbox` ; protection ; démarrage automatique, rang 6 |
| NetBox | 4.6.x (version de PLAN §6) ; code obtenu par Git (étiquette `v4.6.x` de `https://github.com/netbox-community/netbox`), commit vérifié ; installation dans `/opt/netbox-<version>`, lien `/opt/netbox` ; compte système `netbox` ; script `upgrade.sh` de NetBox pour le venv, les dépendances et les migrations |
| Pile Debian 13 | Python 3.13, PostgreSQL 17 (`postgresql`), Valkey 8 (`valkey-server`, à la place de Redis), nginx |
| Écoutes | nginx 80 (redirection) et 443 ; gunicorn **127.0.0.1:8001** ; PostgreSQL et Valkey sur la boucle locale seulement |
| Nom | `https://nbx01.par1.medisphere.internal` ; certificat émis par `ca01` (provisioner `admin`, 90 jours) jusqu'à M06-E18 |
| Secrets | Vault `critique` (`group_vars/role_netbox/vault-critique.yml`) : `vault_netbox_secret_key`, `vault_netbox_api_token_peppers`, `vault_netbox_tls_cle` ; Vault `lab` : `vault_netbox_bdd_mot_de_passe`, `vault_netbox_admin_mot_de_passe` |
| Comptes NetBox | `admin` (bris de glace, mot de passe en Vault) ; ton compte nominatif `<MOI>` (administrateur) ; `wb-checks` : lecture seule (permission « view » sur tous les types d'objets), jeton v2 **sans écriture**, avec expiration, dans `~/.config/workbook/netbox-checks.token` (600) — c'est `WB_NETBOX_TOKEN_FILE` de `lab/lab.env` |
| Molecule | scénario `netbox`, VMID 2047 (partagé avec `pare_feu`), 4 Go de mémoire (variable d'instance `mol_memoire`) ; compter 10 à 15 minutes |

**Travail demandé**
1. Lis les sections « Installation » de la documentation de NetBox 4.6 (PostgreSQL, Redis, NetBox, gunicorn, serveur HTTP) et la section « Required parameters » de la configuration. Note les écarts avec Debian 13 (paquets, Valkey, Python) et les paramètres obligatoires. Question au journal : à quoi servent les **poivres** (`API_TOKEN_PEPPERS`) ? Qu'est-ce qui est stocké dans la base pour un jeton v2 ? Que se passe-t-il si on perd les poivres ?
2. Crée `nbx01` (OpenTofu, MR, pipeline), déclare son nom, ajoute-la au `known_hosts` du projet Ansible et vérifie son groupe dans l'inventaire.
3. Émets son certificat (chaîne complète) avec ton script de M06-E03 ; le certificat va dans le dépôt Ansible, la clé dans Vault `critique`, puis supprime-la de `adm01`.
4. Écris le rôle `netbox` et son scénario Molecule. Exigences :
   - l'installation se fait **par version** (le dossier de la version suivante pourra être préparé à côté) et le code est refusé si son commit n'est pas celui de l'étiquette attendue ;
   - `upgrade.sh` ne tourne qu'une fois par version ; un second passage du rôle ne change rien ;
   - `configuration.py` ne contient que ce qui s'écarte des valeurs par défaut, n'est lisible que par root et le compte `netbox`, et sa syntaxe est validée avant mise en place ;
   - le mot de passe PostgreSQL ne passe jamais en argument de commande ; le compte `admin` est créé une seule fois ;
   - Valkey n'écoute que sur la boucle locale (le rôle le vérifie) ; gunicorn aussi ;
   - la configuration nginx est validée dans son ensemble avant tout rechargement ;
   - le rôle se termine par une vérification de bout en bout en HTTPS **vérifié**.
5. Applique-le par le pipeline. Connecte-toi avec `admin`, crée ton compte nominatif, déconnecte-toi de `admin` et range son mot de passe.
6. Crée le compte `wb-checks` avec un groupe et une permission d'objet en lecture seule, puis son jeton v2 sans écriture, avec une date d'expiration. Range-le dans `~/.config/workbook/netbox-checks.token`. Vérifie que ce jeton lit l'API (`/api/status/`) mais ne peut rien créer. Inscris les secrets au registre.

**Critères de réussite**
- [ ] `nbx01` est créée par OpenTofu, conforme au tableau, résolue en A et PTR.
- [ ] `https://nbx01.par1.medisphere.internal/login/` répond 200 avec un TLS vérifié (chaîne de la PKI MédiSphère) ; `http://` redirige vers `https://`.
- [ ] `/api/status/` (jeton des checks) annonce NetBox 4.6.x, Python 3.13 et au moins un *worker* de file de tâches.
- [ ] Sur `nbx01`, `netbox`, `netbox-rq`, `nginx`, PostgreSQL et Valkey tournent ; hors SSH, seuls les ports 80 et 443 écoutent hors de la boucle locale ; `configuration.py` est en `root:netbox` 640 et définit `API_TOKEN_PEPPERS`.
- [ ] Le jeton des checks est un jeton v2 en lecture seule, dans un fichier en 600.
- [ ] Le rôle `netbox` et son scénario Molecule sont sur `main` ; les secrets `critique` de NetBox sont chiffrés sous cette identité ; un second passage donne `changed=0`.

**Vérification** : `lab/bin/check 06 04`

<details><summary>Indice 1</summary>

Le paquet `postgresql` de Debian 13 installe PostgreSQL 17 ; `valkey-server` fournit Valkey, compatible avec le protocole de Redis : NetBox s'y connecte comme à un Redis (section `REDIS` de la configuration). Sous Debian, le service réel de PostgreSQL est l'instance `postgresql@17-main` ; `postgresql.service` n'est qu'une unité « parapluie ».
</details>

<details><summary>Indice 2</summary>

Sans collection supplémentaire, `psql` sous le compte `postgres` suffit pour créer rôle et base de façon idempotente : on interroge `pg_roles` et `pg_database` avant de créer. Pour définir un mot de passe sans le mettre dans la ligne de commande, `psql` accepte des variables (`-v`) interpolées dans un script lu sur l'entrée standard. Django sait créer un super-utilisateur sans question, avec le mot de passe dans une variable d'environnement.
</details>

<details><summary>Indice 3</summary>

`upgrade.sh` recrée le venv à chaque exécution : c'est le **venv de la version** qui prouve qu'elle est installée. Pour la création d'un jeton par l'interface : menu utilisateur, puis « API Tokens » ; la valeur complète (`nbt_…`) n'est affichée qu'une fois. Les permissions de NetBox sont des « object permissions » : actions (view, add, change, delete) sur des types d'objets, attribuées à des utilisateurs ou des groupes.
</details>

**Pour aller plus loin** (facultatif) : lis le guide de montée de version de NetBox (« Upgrading ») et écris dans le README du rôle comment ton installation par version permettrait de préparer la 4.6 suivante sans couper le service (et ce qui coupe forcément : les migrations).

---

### M06-E05 — Modéliser MédiSphère dans NetBox  `LAB` `★`

> **Ticket PLAT-705** — *De : Karim Benali*
> NetBox tourne, il est vide. Avant que la synchronisation avec Proxmox et OpenTofu ne s'y branchent (palier 2), je veux qu'il décrive notre plan : sites, baies, matériel, cluster, VLAN, préfixes, plages, et les VMs du socle avec leurs adresses. Fais-en une partie à la main pour comprendre le modèle, puis écris le reste en code : je veux pouvoir le rejouer sur une base vide.

**Objectifs pédagogiques**
- Comprendre le modèle de données de NetBox : organisation (régions, sites, locataires), DCIM (baies, fabricants, types et rôles d'équipements, équipements), IPAM (groupes de VLAN, VLAN, préfixes, plages, rôles, adresses), virtualisation (types de clusters, clusters, VMs, interfaces).
- Étendre le modèle (champ personnalisé, étiquettes).
- Écrire un script **idempotent** contre une API REST : chercher par clé naturelle, créer ce qui manque, corriger ce qui diffère, ne rien faire sinon.

**Prérequis** : M06-E04 ; M02 (Python, uv, requests).
**Durée indicative** : 3 h.

**Contexte technique**
- Données à décrire : PLAN.md §4.2 (VLAN et préfixes de PAR1, convention d'adresses `.10-.49` statique, `.50-.99` nœuds, `.100-.199` DHCP, `.200-.249` VIP), §4.3 (PAR2, interconnexion, VPN), §4.5 (VMs du socle). Région « France », locataire « MédiSphère », sites `PAR1` et `PAR2`, une baie virtuelle par site, équipements `pve01` (PAR1) et `hp01` (PAR2), type de cluster « Proxmox VE », cluster `pve01` rattaché au site PAR1 et dont `pve01` est l'hôte, groupe de VLAN `PAR1`, rôles IPAM « Statique », « Nœuds », « DHCP », « VIP », champ personnalisé `vmid` (entier) sur les VMs, étiquettes `socle` et `role-<rôle>` (celles de Proxmox).
- Les VMs du socle : `gw01`, `adm01`, `dns01`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, avec VMID, ressources (relevées dans Proxmox), interfaces et adresses (pour `gw01` : une interface par VLAN routé et ses tunnels WireGuard ; IP primaire 10.10.10.1).
- Écriture : un jeton v2 **personnel** (compte `<MOI>`), avec écriture, expirant dans 7 jours, dans `~/.config/workbook/netbox-moi.token` (600). Le compte de service de l'automatisation arrive en M06-E10.
- Code : dans `plateforme/outils` (clone `~/src/outils`), dossier `netbox/` : le script et un fichier de données séparé.
- API : NetBox 4.6. Le rattachement d'un cluster, d'un préfixe ou d'un groupe de VLAN à un site passe par `scope_type` / `scope_id` ; la mémoire et le disque d'une VM s'expriment en Mo.

**Travail demandé**
1. Dans l'interface, crée à la main la région, le locataire, le site `PAR1`, le groupe de VLAN, le VLAN 20 et son préfixe. Observe pour chaque objet ses champs obligatoires et ses liens. Puis ouvre l'API navigable (`/api/`) sur ces mêmes objets : note la forme des champs liés (objets imbriqués), des champs à choix (`status`) et des étiquettes.
2. Écris le fichier de données (YAML) qui décrit **tout** le modèle du contexte technique.
3. Écris le script : il lit le fichier, et pour chaque objet le cherche par une clé naturelle (slug, nom, préfixe, adresse…), le crée s'il manque, met à jour **seulement** les champs décrits qui diffèrent, et dit ce qu'il fait (`+`, `~`, `=`). Un mode `--dry-run` n'écrit rien. TLS vérifié avec le magasin système ; jeton lu dans un fichier, jamais affiché.
4. Lance-le en simulation, puis pour de vrai, puis une seconde fois : le second passage ne doit rien changer. Vérifie dans l'interface les objets faits à la main à l'étape 1 : le script les a-t-il repris ou dupliqués ?
5. Contrôle la cohérence : utilisation des préfixes, adresses de chaque VM, IP primaires, plages par rôle. Publie le script et ses données dans `plateforme/outils` (MR, pipeline).

**Critères de réussite**
- [ ] Organisation, physique, cluster, adressage et VMs du socle sont décrits dans NetBox conformément au contexte technique.
- [ ] Les 13 VLAN de PAR1 ont chacun leur préfixe /24 ; la plage DHCP du VLAN 99 (10.10.99.100-199) a le rôle DHCP.
- [ ] Chaque VM du socle porte son `vmid`, ses étiquettes `socle` et `role-…`, et son IP primaire (PLAN.md §4.5).
- [ ] Un second passage du script ne crée ni ne modifie rien ; le script et ses données sont versionnés dans `plateforme/outils`.

**Vérification** : `lab/bin/check 06 05`

<details><summary>Indice 1</summary>

L'ordre de création compte : un objet ne peut référencer que des objets qui existent déjà (région → site → baie ; fabricant → type d'équipement → équipement ; VLAN → préfixe ; interface → adresse → IP primaire de la VM).
</details>

<details><summary>Indice 2</summary>

Les filtres de l'API (`?slug=`, `?name=`, `?prefix=`, `?vid=…&group_id=…`, `?virtual_machine_id=…&name=…`, `?vrf_id=null`) servent de recherche par clé naturelle. Une lecture renvoie les objets liés sous forme imbriquée (`{"id": …, "name": …}`) et les champs à choix sous forme `{"value": …, "label": …}` : pour comparer avec ce que tu écris, ramène les deux à la même forme.
</details>

<details><summary>Indice 3</summary>

L'IP primaire d'une VM ne peut être posée qu'une fois l'adresse rattachée à l'une de ses interfaces : il faut donc revenir sur la VM après avoir créé interfaces et adresses. Un script Python autonome peut déclarer ses dépendances dans un en-tête (PEP 723) que `uv run` sait lire.
</details>

**Pour aller plus loin** (facultatif) : compare ton approche (script maison) avec le module `netbox.netbox` d'Ansible et avec les « Data sources » et « Config contexts » de NetBox. Quand préférer chacun ?

---

### M06-E06 — PowerDNS Authoritative sur `dns01`  `LAB` `★★`

> **Ticket PLAT-706** — *De : Karim Benali*
> On remplace le DNS de dnsmasq par PowerDNS, en deux morceaux. Premier morceau : le serveur **faisant autorité**, avec nos zones, une API, une vraie base. Il s'installe **à côté** de dnsmasq, sur un autre port : à la fin de cet exercice, rien n'a changé pour les clients, mais on peut interroger les deux et comparer. Les données ne se saisissent pas deux fois : la liste des hôtes doit servir aux deux serveurs tant qu'ils cohabitent.

**Objectifs pédagogiques**
- Installer PowerDNS Authoritative 5.0 depuis le dépôt officiel, avec un backend SQL et son API.
- Comprendre zones, SOA, numéro de série, délégation et colle en les écrivant.
- Générer le contenu des zones à partir d'une source unique, avec un numéro de série toujours croissant.
- Cohabiter sans conflit avec le service en place (ports, démarrage automatique des paquets).

**Prérequis** : M04-E46 (rôle `dnsmasq`) ; M00-E13 (zones et enregistrements actuels).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Dépôt | `http://repo.powerdns.com/debian`, suite `trixie-auth-50`, clé `https://repo.powerdns.com/FD380FBB-pub.asc` (empreinte `9FAA A557 7E8F CF62 093D 036C 1B0C 6205 FD38 0FBB`), épinglage à 600 (procédure de repo.powerdns.com) ; paquets `pdns-server`, `pdns-backend-sqlite3` |
| Backend | `gsqlite3`, base `/var/lib/powerdns/pdns.sqlite3` (schéma fourni par le paquet du backend), DNSSEC activé dans le backend (pour M06-E26) |
| Écoute DNS | 127.0.0.1:5300 et 10.10.20.10:5300 ; **jamais** le port 53 |
| API | 10.10.20.10:8081, clients autorisés : `dns01` lui-même, `adm01` (10.10.10.10), `runner01` (10.10.20.15) ; clé `vault_powerdns_api_cle` (Vault `critique`, `group_vars/role_dns/vault-critique.yml`) |
| Zones | `medisphere.internal` (parente : délègue `par1` et `par2`), `par1.medisphere.internal`, `par2.medisphere.internal`, `10.10.in-addr.arpa`, `20.10.in-addr.arpa` ; SOA : primaire `dns01.par1.medisphere.internal`, contact `hostmaster.medisphere.internal`, TTL négatif 300 s ; NS : `dns01.par1.medisphere.internal` (`dns02` viendra en M06-E24) ; numéro de série au format `AAAAMMJJnn` |
| Contenu | les noms de `/etc/dnsmasq.d/medisphere.conf` (A, PTR, PTR des autres adresses de `gw01`), **depuis la même liste** que le rôle `dnsmasq` ; à partir de M06-E14/E15, certaines zones seront écrites par l'API (OpenTofu, NetBox) : le rôle doit pouvoir ne créer une zone que si elle manque, sans toucher à son contenu |
| `dns01` | 2 Go de mémoire conseillés pour héberger dnsmasq, PowerDNS et bientôt Kea : si ta VM en a moins, augmente-la par le code (`plateforme/infra`) |
| Molecule | scénario `powerdns_auth`, VMID 2048 (partagé avec `gitlab_runner`) |

**Travail demandé**
1. Lis dans la documentation de PowerDNS Authoritative 5.0 : le backend Generic SQLite 3, les paramètres `launch`, `local-address`, `api`, `api-key`, `webserver-*`, `default-soa-content`, et la page de `pdnsutil` (la version 5.0 a changé la forme des commandes). Note ce que fait le paquet `pdns-server` à l'installation (fichiers, service démarré ou non, configuration par défaut).
2. Rends la liste des hôtes **unique** dans l'inventaire : une seule variable, lue par le rôle `dnsmasq` et par le futur rôle PowerDNS. Vérifie par `--check --diff` que `dnsmasq` ne voit aucune différence.
3. Écris le rôle `powerdns_auth` et son scénario Molecule. Exigences :
   - clé du dépôt vérifiée par son empreinte ;
   - le paquet ne démarre pas de service avant que le rôle l'ait configuré, et aucun backend inutile n'est chargé ;
   - base créée avec le schéma du paquet, appartenant au compte `pdns` (fichiers annexes de SQLite compris) ;
   - zones créées si elles manquent ; pour les zones dont le rôle gère le contenu, contenu **généré** (A dans la zone la plus précise, PTR vers le premier nom, enregistrements propres à la zone), rechargé seulement s'il a changé, avec un numéro de série strictement croissant ; métadonnée qui fera incrémenter le numéro de série lors des modifications par l'API ;
   - vérifications : chaque zone répond avec autorité ; l'API répond avec la clé et refuse sans.
4. Applique-le sur `dns01` par le pipeline. dnsmasq doit continuer à servir le port 53 sans interruption.
5. Explore : `pdnsutil zone list`, `zone check`, `zone show` sur une zone ; puis l'API avec `curl` depuis `adm01` (liste des zones, contenu d'une zone). Compare, pour quelques noms, `dig @10.10.20.10` (dnsmasq) et `dig -p 5300 @10.10.20.10` (PowerDNS) : statut, drapeaux, TTL. Que répond PowerDNS à une question sur `deb.debian.org` ? Pourquoi est-ce le bon comportement ?
6. Change un enregistrement de test dans l'inventaire, applique, observe le numéro de série avant et après ; remets l'état initial.

**Critères de réussite**
- [ ] `pdns` (PowerDNS Authoritative 5.0 du dépôt officiel) tourne sur `dns01`, backend `gsqlite3` seul, sur 127.0.0.1:5300 et 10.10.20.10:5300, jamais sur le port 53 ; dnsmasq sert toujours le port 53.
- [ ] Les cinq zones répondent avec autorité ; chaque nom du socle a son A et son PTR, identiques à ceux de dnsmasq ; un nom inexistant reçoit `NXDOMAIN` avec autorité ; une question hors zone est refusée.
- [ ] Le numéro de série est au format `AAAAMMJJnn` et augmente à chaque changement de contenu.
- [ ] L'API répond sur 10.10.20.10:8081 avec la clé, refuse sans clé (401), et ne répond pas à un hôte non autorisé.
- [ ] Le rôle et son scénario Molecule sont sur `main` ; un second passage donne `changed=0`.

**Vérification** : `lab/bin/check 06 06`

<details><summary>Indice 1</summary>

Le paquet `pdns-server` *recommande* un autre backend, qui ajoute son propre fichier dans `/etc/powerdns/pdns.d/` : regarde ce qu'APT installe par défaut avec les recommandations. Debian dispose d'un mécanisme standard pour empêcher les paquets de démarrer leurs services pendant une installation : `policy-rc.d`.
</details>

<details><summary>Indice 2</summary>

`pdnsutil zone load ZONE FICHIER` remplace d'un bloc le contenu d'une zone à partir d'un fichier au format BIND. Le numéro de série du fichier fait foi : il faut donc le calculer au moment du chargement (à partir du numéro en place), pas dans le modèle Jinja (sinon chaque passage changerait le fichier). Une zone créée par `pdnsutil` peut répondre `REFUSED` pendant quelques minutes : cherche le paramètre `zone-cache-refresh-interval`.
</details>

<details><summary>Indice 3</summary>

Pour placer un nom dans la bonne zone, cherche parmi les zones servies celle dont le nom est le **plus long** suffixe du nom. Le nom inverse d'une adresse IPv4 s'obtient en renversant ses octets et en ajoutant `in-addr.arpa`. Le serveur web de PowerDNS n'écoute que sur **une** adresse : un client local qui passe par l'adresse de service se présente avec cette adresse, pas avec 127.0.0.1.
</details>

**Pour aller plus loin** (facultatif) : compare les backends `gsqlite3`, `gpgsql` et `lmdb` (réplication, vues de la 5.0, sauvegarde à chaud, dépendances) et justifie le choix pour un socle à deux serveurs (M06-E24). Cherche l'option qui permet de stocker une clé d'API **hachée** dans la configuration.

---

### M06-E07 — PowerDNS Recursor et zones relayées  `LAB` `★★`

> **Ticket PLAT-707** — *De : Karim Benali*
> Deuxième morceau : le **résolveur**. C'est lui que les clients interrogeront, sur le port 53, quand on aura basculé. Pour l'instant, installe-le sur un port d'essai, relaie nos zones vers l'autoritaire, laisse-le résoudre Internet et **valider DNSSEC** en mode strict. Puis prouve-moi, question par question, qu'il répond exactement comme dnsmasq.

**Objectifs pédagogiques**
- Configurer PowerDNS Recursor 5.4 en YAML : écoute, clients autorisés, zones relayées, résolution d'Internet.
- Comprendre la validation DNSSEC d'un résolveur, ses modes, et le cas des zones internes (ancres négatives).
- Comparer deux résolveurs de façon systématique avant une bascule.

**Prérequis** : M06-E06.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Dépôt | même dépôt et même clé que l'Authoritative, suite `trixie-rec-54` ; paquet `pdns-recursor` (Debian 13 livre une 5.2 : l'épinglage doit faire gagner le dépôt officiel) |
| Configuration | `/etc/powerdns/recursor.yml` (YAML ; présent, il est lu à la place de `recursor.conf`) |
| Écoute pendant l'essai | 127.0.0.1:**5301** et 10.10.20.10:**5301** (le port 53 reste à dnsmasq jusqu'à M06-E08) |
| Clients autorisés | 127.0.0.0/8, 10.10.0.0/16, 10.20.0.0/16, 10.255.1.0/24 |
| Zones relayées | les cinq zones de M06-E06, vers 127.0.0.1:5300 |
| Internet | résolution itérative depuis la racine (`gw01` laisse sortir `dns01` en UDP et TCP 53) ; ou relais vers `<DNS-AMONT>` si tu le préfères (justifie) |
| DNSSEC | mode `validate` |
| Questions de référence | [`ressources/M06-E07/questions-socle.txt`](../ressources/M06-E07/questions-socle.txt) : une question par ligne, arguments de `dig` |
| Molecule | scénario `powerdns_recursor`, VMID 2049 (partagé avec `dnsmasq` et `node_exporter`) ; il installe aussi l'autoritaire sur l'instance, pour tester la chaîne complète |

**Travail demandé**
1. Lis la page « YAML settings » et la page DNSSEC de la documentation du Recursor 5.4 : sections `incoming`, `recursor` (`forward_zones`, `forward_zones_recurse`), `dnssec` (`validation`, `trustanchors`, `negative_trustanchors`), `outgoing` (`dont_query`). Note les valeurs par défaut de `incoming.listen`, `dnssec.validation` et `recursor.serve_rfc1918`, et ce que dit la documentation des zones relayées quand la validation est active.
2. Écris le rôle `powerdns_recursor` et son scénario Molecule : dépôt vérifié, installation sans démarrage intempestif (le port 53 est déjà pris), `recursor.yml` généré à partir de l'inventaire et **validé avant mise en place** par le Recursor lui-même, redémarrage contrôlé avec retour à la configuration précédente si le service ne répond plus. Le rôle doit pouvoir écrire sa configuration **sans redémarrer** (la bascule de M06-E08 en aura besoin).
3. Applique-le sur `dns01` (port d'essai). Interroge-le sur un nom interne, un inverse, un nom inexistant de `par1`, un nom Internet signé (`+dnssec`), et le domaine de test `dnssec-failed.org`. Pour chacun : statut et drapeaux.
4. Expérience : retire temporairement l'ancre négative de la zone interne (sur la VM Molecule, pas sur `dns01`), relance les questions internes. Observe et explique ; remets l'ancre. Même expérience avec le mode `process` au lieu de `validate` : quelle différence pour un client qui ne demande pas de validation ? Utilise l'option `+noadflag` de `dig`.
5. Écris un script de comparaison (dans `plateforme/outils`, dossier `dns/`) : pour chaque question du fichier de référence, il interroge deux résolveurs et compare **statut** et **données** (ordre et TTL ignorés), puis donne un bilan et un code retour. Lance-le entre dnsmasq (10.10.20.10:53) et le Recursor (10.10.20.10:5301). Corrige jusqu'à **zéro écart** sur les noms internes ; explique les éventuels écarts sur les noms Internet.

**Critères de réussite**
- [ ] `pdns-recursor` 5.4 (dépôt officiel) tourne sur `dns01`, configuré en YAML, sur 127.0.0.1 et 10.10.20.10 seulement (port d'essai 5301).
- [ ] Il résout les noms internes (A, PTR, `par1` et `par2`), répond `NXDOMAIN` pour un nom interne inexistant (sans SERVFAIL), et ne valide pas la zone interne (pas de drapeau `ad`).
- [ ] Il résout Internet ; une réponse signée porte le drapeau `ad` ; `dnssec-failed.org` reçoit SERVFAIL **même** pour un client qui ne demande pas de validation.
- [ ] Le script de comparaison ne trouve aucun écart entre dnsmasq et le Recursor sur les noms internes.
- [ ] Le rôle et son scénario Molecule sont sur `main` ; un second passage donne `changed=0`.

**Vérification** : `lab/bin/check 06 07`

<details><summary>Indice 1</summary>

Une zone relayée par `forward_zones` est interrogée **sans récursion** (bit RD à 0) : c'est le bon mode pour parler à un serveur faisant autorité. `forward_zones_recurse` (avec récursion) sert à relayer vers un **autre résolveur**. Les adresses de relais ne sont pas soumises à `outgoing.dont_query`, qui interdit pourtant 127.0.0.0/8 et 10.0.0.0/8 par défaut.
</details>

<details><summary>Indice 2</summary>

`pdns_recursor --config-dir=DOSSIER --config=check` vérifie le `recursor.yml` de ce dossier et renvoie un code d'erreur s'il est invalide (clé inconnue, type faux). Le paramètre `validate` du module `template` ne donne qu'un **chemin de fichier temporaire** : il faut un petit intermédiaire qui place ce fichier sous le bon nom dans un dossier temporaire.
</details>

<details><summary>Indice 3</summary>

`medisphere.internal` n'existe pas dans la racine signée : la racine **prouve** son absence. Un résolveur strict en déduit que toute réponse pour cette zone est fausse. Les zones inverses `10.10` et `20.10` sont sous `10.in-addr.arpa`, déléguée sans signature : leur cas est différent ; demande-toi s'il vaut mieux dépendre ou non de la chaîne publique pour résoudre une adresse interne.
</details>

**Pour aller plus loin** (facultatif) : la clé de la racine DNS change : la nouvelle clé (KSK-2024) signe la zone racine à partir du 11 octobre 2026. Vérifie quelles ancres ton Recursor utilise (intégrées ou fichier de Debian), et ce que dit la documentation du Recursor sur le suivi automatique des ancres (RFC 5011).

---

### M06-E08 — Basculer le DNS du lab sans coupure  `LAB` `★★★`

> **Ticket CHG-708** — *De : Nadia Roussel* — *Copie : Claire Morel*
> J'ai vu passer la MR « bascule DNS ». Avant que tu la fusionnes : le DNS, c'est **tout** le lab. La dernière fois qu'InfoGér a « juste redémarré le DNS », trois traitements de nuit sont tombés parce que leurs résolutions avaient échoué pendant deux secondes. Je veux une fiche de changement, une répétition sur une machine d'essai avec une mesure de ce que voient les clients, et le jour J, la même mesure. Le critère est simple : **zéro résolution en échec**. Un peu de lenteur, je l'accepte.

**Objectifs pédagogiques**
- Préparer un changement à risque comme en production : fiche de changement, répétition, critères mesurables, retour arrière automatique.
- Comprendre ce que vit un client DNS pendant qu'un serveur change de main : refus immédiat ou silence, nouvelles tentatives, délais.
- Faire passer un port d'un service à un autre sans échec côté clients, puis vérifier que le code décrit le nouvel état.

**Prérequis** : M06-E06, M06-E07 (zéro écart) ; M02-E11 (`ms-snapshot`).
**Durée indicative** : 4 h.

**Contexte technique**
- État de départ : dnsmasq sert le DNS (port 53) **et** le DHCP du VLAN 99 sur `dns01` ; le Recursor écoute sur 5301 ; l'Authoritative sur 5300.
- État visé : le Recursor sur 127.0.0.1:53 et 10.10.20.10:53 ; dnsmasq **sans DNS** (`port=0`), il garde le DHCP jusqu'à Kea (M06-E16) ; plus rien sur 5301.
- Les clients ne changent pas : leur résolveur reste 10.10.20.10. Client typique : la bibliothèque C (glibc), 5 secondes d'attente et 2 tentatives par défaut (`man 5 resolv.conf`).
- Mesure : [`ressources/M06-E08/sonde-continue.sh`](../ressources/M06-E08/sonde-continue.sh) interroge un résolveur plusieurs fois par seconde et compte deux sortes d'échecs : « brut » (une tentative d'une seconde) et « client » (réglages d'un client glibc). Le critère de Nadia porte sur la colonne « client ».
- Répétition : VM d'essai 2060 `m06-repetition`, clone de l'image dorée `current`, pool `lab`, étiquette `env-m06` (et **pas** `role-dns`), VNet `vsandbox` en DHCP, configurée par les mêmes rôles avec un inventaire à part (`inventories/repetition/`).
- Livrables : la fiche `docs/socle/changements/CHG-708-bascule-dns.md` (dans `plateforme/medisphere`) et un playbook de bascule `playbooks/bascule-dns.yml` (dans `plateforme/ansible`).
- Effet connu à annoncer : dnsmasq publiait dans le DNS les noms des baux DHCP du VLAN 99 (`sbxNN`) ; après la bascule, plus personne ne le fait, jusqu'à la mise à jour dynamique par Kea (M06-E17).

**Travail demandé**
1. **La fiche.** Rédige CHG-708 : objet, préalables (avec leurs preuves), déroulé pas à pas avec contrôle à chaque étape, critère de réussite, retour arrière (automatique et manuel), effets connus, communication, et une section « compte rendu » à remplir après.
2. **Préparer le code.** La MR de bascule ne doit décrire que **l'état après** (dnsmasq sans DNS, Recursor sur le port 53). Le rôle `dnsmasq` doit savoir ne plus faire de DNS en gardant le DHCP, et les deux rôles doivent savoir écrire leur configuration sans redémarrer. Le playbook de bascule enchaîne : contrôles préalables, configurations écrites, passage du port, contrôles, retour arrière automatique en cas d'échec.
3. **Répétition, version naïve.** Crée la VM 2060, applique-lui l'état de départ (inventaire de répétition), lance la sonde contre elle depuis `adm01`, puis fais la bascule en redémarrant simplement les deux services dans le bon ordre. Lis le bilan de la sonde. Combien d'échecs « client » ? Combien de temps a duré la fenêtre ? Pourquoi un client glibc échoue-t-il **tout de suite** au lieu d'attendre et de réessayer ? (Capture le trafic sur la VM pendant la fenêtre : que renvoie-t-elle aux clients ?)
4. **Répétition, version corrigée.** Modifie ta procédure pour que, pendant la fenêtre, les clients **attendent** au lieu d'échouer, sans toucher à `gw01` ni aux clients, et en laissant `dns01` exactement dans son état normal à la fin. Recommence (remets la VM dans l'état de départ) jusqu'à obtenir zéro échec « client ». Teste aussi le retour arrière automatique : provoque un échec de contrôle et vérifie que la VM revient à l'état de départ.
5. **Le jour J.** Instantané de `dns01`, sonde lancée depuis `adm01` **et** depuis une VM du VLAN 99, fusion de la MR, application du playbook de bascule, contrôles de la fiche. Puis un passage normal du playbook de `dns01` (ou de `site.yml`) : aucun changement.
6. **Clôture.** Complète le compte rendu de CHG-708 (résultats des sondes), détruis la VM 2060, supprime l'instantané le lendemain.

**Critères de réussite**
- [ ] Sur `dns01`, le port 53 n'est tenu que par PowerDNS Recursor ; `dig CH TXT version.bind @10.10.20.10` répond PowerDNS Recursor 5.4 ; plus rien n'écoute sur 5301.
- [ ] dnsmasq tourne toujours, sans DNS, et sert le DHCP du VLAN 99.
- [ ] Les hôtes du socle résolvent les noms du lab (noms courts compris) et d'Internet, en UDP et en TCP.
- [ ] La sonde du jour J ne compte **aucun** échec « client » ; son bilan figure dans le compte rendu de CHG-708.
- [ ] Le playbook de bascule et la fiche CHG-708 sont publiés ; un passage normal après la bascule donne `changed=0` ; aucune règle temporaire ne subsiste sur `dns01`.

**Vérification** : `lab/bin/check 06 08`

<details><summary>Indice 1</summary>

Quand un paquet UDP arrive sur un port où aucun programme n'écoute, le noyau répond par un message ICMP « port unreachable » ; pour une connexion TCP, par un RST. Le client apprend aussitôt que personne ne répondra : il passe à la tentative suivante, puis abandonne. S'il ne reçoit **rien**, il attend la fin de son délai avant de réessayer.
</details>

<details><summary>Indice 2</summary>

Une règle nftables **temporaire**, dans une table à part créée et supprimée par le playbook, peut changer ce que le noyau de `dns01` renvoie pendant quelques secondes, sans toucher au pare-feu de `gw01` ni au reste de la configuration. Vérifie qu'elle disparaît dans tous les cas, y compris en cas d'échec.
</details>

<details><summary>Indice 3</summary>

Dans un playbook, `block` / `rescue` / `always` organise le retour arrière. Les rôles qui écrivent leur configuration avec une copie de sauvegarde (`backup: true`) donnent dans leur résultat enregistré le chemin de cette copie. Les variables de play l'emportent sur celles de l'inventaire : si l'inventaire de répétition doit fournir l'adresse à tester, le playbook doit la lire sous un autre nom.
</details>

**Pour aller plus loin** (facultatif) : une bascule **sans aucun délai** est possible : redirection temporaire du port 53 vers le port d'essai, puis seconde instance du Recursor partageant le port 53 (option `SO_REUSEPORT`, `incoming.reuseport`) le temps du redémarrage de la première. Décris-la, compare son coût à celui de la solution retenue, et dis dans quels contextes elle se justifierait.

---

### M06-E09 — Questions : DNS, DHCP et PKI  `Q` `★★`

> **Ticket PLAT-709** — *De : Karim Benali*
> Avant d'attaquer le palier 2, je veux savoir si tu as compris ce que tu as monté, pas seulement si ça marche. Réponds par écrit, en t'appuyant sur ce que tu as observé dans le lab.

**Objectifs pédagogiques**
- Expliquer les choix faits au palier 1 et leurs conséquences.
- Relier ce qui a été observé (sorties, journaux, mesures) aux mécanismes des protocoles.

**Prérequis** : M06-E02 à M06-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 12 questions.

1. Pourquoi l'intermédiaire de `ca01` a-t-il été généré **sur `ca01`** à partir d'une CSR, plutôt que créé sur `adm01` avec la racine puis copié ? Qu'est-ce que ce choix complique (reconstruction de `ca01`, sauvegarde) et comment y répondre ?
2. Le provisioner `admin` a sa clé privée **chiffrée** dans `ca.json`, sur `ca01`. Qui peut l'utiliser, avec quoi ? Que se passe-t-il si `ca01` est compromise ? Et si le fichier `step-admin.pass` de `adm01` fuit ?
3. Pourquoi les certificats émis à la main (provisioner `admin`) ont-ils droit à 90 jours et ceux d'ACME à 30 seulement, alors que l'ACME est l'objectif ?
4. *(QCM)* La racine MédiSphère vient d'être retirée par erreur du magasin système de `runner01` (la CA provisoire aussi). Que se passe-t-il au prochain pipeline ?
   - A. Rien : `runner01` a gardé les certificats en cache
   - B. Les clones HTTPS depuis `git01` et l'accès à l'état OpenTofu sur `s3-01` échouent pour les outils qui utilisent le magasin système
   - C. Seul `git` échoue ; OpenTofu a son propre magasin
   - D. Le runner se désenregistre de GitLab
5. NetBox stocke les jetons v2 sous forme d'empreinte calculée avec un **poivre**. Un attaquant obtient une copie de la base PostgreSQL de `nbx01`, mais pas `configuration.py`. Que peut-il faire des jetons ? Et s'il obtient les deux ? Comment fait-on tourner un poivre ?
6. Pourquoi Valkey ne doit-il jamais écouter sur le réseau, même dans le VLAN INFRA, alors qu'il ne contient « que » un cache et une file de tâches ?
7. Le Recursor relaie `par1.medisphere.internal` vers 127.0.0.1:5300 par `forward_zones` (sans récursion). Que se passerait-il si on utilisait `forward_zones_recurse` à la place ? Et si l'on relayait toute la zone vers dnsmasq ?
8. Pourquoi la zone parente `medisphere.internal` a-t-elle été créée, alors que les clients n'utilisent que `par1` et `par2` ? Que se passait-il, sans elle, pour une question sur `git01.medisphere.internal` (faute de frappe) ?
9. Le rôle `powerdns_auth` calcule le numéro de série **au chargement** et lui donne la forme `AAAAMMJJnn`, en partant du numéro en place. Pourquoi pas un numéro fixe dans le modèle, ni l'heure Unix ? Que vient faire la métadonnée `SOA-EDIT-API` ?
10. *(QCM)* Pendant la répétition naïve de M06-E08, la sonde a compté des échecs « client » en quelques millisecondes, alors qu'un client glibc attend 5 secondes avant de réessayer. Pourquoi ?
    - A. La sonde est mal écrite : elle n'attend pas
    - B. Le noyau de la VM a répondu « port unreachable » : le client sait aussitôt que personne n'écoute et épuise ses tentatives
    - C. Le Recursor a répondu REFUSED pendant son démarrage
    - D. Les questions ont été perdues par le réseau
11. Un an plus tard, l'intermédiaire de `ca01` arrive à mi-vie. Décris ce que tu fais, dans l'ordre, et ce que les clients du socle voient pendant l'opération.
12. Le 11 octobre 2026, la nouvelle clé de la racine DNS (KSK-2024) commence à signer la zone racine. Ton Recursor validera-t-il encore Internet le 12 ? Qu'aurais-tu vérifié avant ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions, en citant au moins trois observations faites dans le lab (sortie de commande, mesure, journal).
- [ ] Tu as noté chaque réponse avec la grille du corrigé et listé ce qui reste flou.

<details><summary>Indice</summary>

Pour chaque question, demande-toi d'abord **où est le secret** (ou la donnée qui fait foi), **qui peut l'utiliser**, et **ce qui se passe s'il disparaît ou fuit**. La plupart des réponses de ce questionnaire en découlent.
</details>

**Pour aller plus loin** (facultatif) : transforme les questions 2, 5 et 11 en entrées du registre des risques de l'équipe (risque, probabilité, impact, mesure en place, mesure à venir) : Sophie Laurent en aura besoin pour la politique de certification (M06-E33).
