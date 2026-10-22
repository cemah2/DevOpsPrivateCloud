# Module 25 — Introduction : secrets

## Le fichier `.env` de Lucas

Lundi, 8 h 40. Sophie Laurent a passé le week-end sur une question qu'elle n'a pas su résoudre. Claire Morel transfère son message à l'équipe Plateforme avec sa décision.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
> **Objet** : Un coffre pour nos secrets
>
> Bonjour,
>
> Le mois dernier, Lucas a collé un fichier `.env` dans un ticket pour qu'on l'aide à lancer MédiAgenda en local. Le ticket était visible par quarante personnes pendant trois jours. Sophie m'a posé deux questions simples : quels secrets étaient dans ce fichier, et qui d'autre les a lus depuis ? Nous n'avons su répondre à aucune des deux. Le mot de passe de la base de recette n'a pas changé depuis son installation ; la clé de signature Cosign est dans un Secret du runner ; les mots de passe de nos services sont dans un Ansible Vault que chacun déchiffre sur `adm01` ; les Secrets du cluster sont créés par un script hors de Git.
>
> Ce que je veux à la fin du module :
> 1. un **coffre** unique, OpenBao, en grappe, sauvegardé, qui redémarre seul sans exposer ses clés ;
> 2. des secrets délivrés à des **identités vérifiées** : les personnes par le SSO, les jobs de CI par leur jeton signé, les pods par leur compte de service, les machines par une identité qu'on peut révoquer ;
> 3. des secrets **courts** quand c'est possible : un mot de passe de base qui vit une heure vaut mieux qu'un mot de passe qui vit trois ans ;
> 4. pouvoir **tourner** n'importe quel secret sans coupure, et répondre en une heure à la question « qui a lu ce secret ? » ;
> 5. aucun secret durable dans Git, dans les variables de CI ni dans un script.
>
> Les règles de la maison s'appliquent : Git et MR pour tout, OpenTofu pour ce qui a une API, Ansible pour les VMs, Argo CD pour le cluster. Et la règle du M24 tient toujours : **on ne retire jamais un accès sans un accès de secours testé**. Un coffre fermé dont personne ne sait rouvrir la porte, c'est toute la plateforme à l'arrêt.
>
> Premier jalon : OpenBao installé et initialisé proprement, les personnes qui y entrent par le SSO, les machines par AppRole, et sa configuration en code. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 25, MédiSphère a ses secrets **v1** (étiquette `secrets-v1` de `plateforme/medisphere`), repris par le M26 (vérification des signatures, audit), le M27 et les workbooks finaux :

- **`vault01-03`** : **OpenBao** en grappe Raft derrière la VIP `openbao.par1.medisphere.internal`, auto-descellé par **`kms01`** (seal `transit`), sauvegardé, supervisé, audité ;
- le projet **`plateforme/secrets`** : toute la configuration d'OpenBao en OpenTofu (fournisseur `hashicorp/vault`) ;
- les personnes par **OIDC** (Keycloak), les jobs de CI par **JWT** (jetons d'identité de GitLab), les pods par la méthode **Kubernetes**, les machines par **AppRole** ;
- des secrets statiques (**KV v2**), **dynamiques** (PostgreSQL de MédiAgenda), du **chiffrement** (transit, Cosign) et des **certificats** (PKI de services) ;
- **External Secrets Operator** à la place du script `secrets-k8s.sh`, et les alternatives comparées (SOPS, Sealed Secrets, pilote CSI) ;
- la rotation sans coupure, l'audit, les runbooks de fuite, de descellement, de sauvegarde et de montée de version.

Le **palier 1** (ce fichier et `01-decouverte.md`) pose les fondations sur un seul nœud : l'inventaire de ce qu'il faut protéger, `vault01` installé et initialisé en cérémonie, le moteur KV, les politiques et les jetons, l'entrée des personnes par le SSO et des machines par AppRole, puis toute la configuration reprise en code et le jeton racine révoqué. Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module (fin du palier 1)

```
   poste (VPN wg1 10.255.1.0/24)                         adm01 (MGMT 10.10.10.10)
     navigateur ── https://openbao…:8200/ui              bao (CLI) · tofu · medictl · lab/bin/check
          │          tunnel SSH 8250 ◄── bao login -method=oidc        │
          │                                                            │ AppRole « wb-checks » (checks)
          │                                                            │ AppRole « medictl »
 ════════ gw01/gw02 (bordure : MGMT et VPN → vault01:8200) ═══════════════════════════════════════
          │
          ▼  openbao.par1.medisphere.internal → 10.10.20.21 (VIP 10.10.20.200 au M25-E24)
  vault01 10.10.20.21 ─ OpenBao 2.6 (:8200 API+UI en TLS, :8201 grappe) ─ certificat ACME de ca01
     ┌──────────────────────────── barrière (chiffrement de tout ce qui est écrit) ─────────────┐
     │ méthodes d'authentification      politiques             moteurs de secrets             │
     │   oidc/    ── personnes ──►  plateforme-admin…    ──►   kv/ (KV v2)                     │
     │   approle/ ── machines ──►   wb-checks, medictl          plateforme/…, mediagenda/dev/… │
     │   token/   ── jetons                                     (db, transit, pki au palier 2) │
     │ identité : groupes EXTERNES ← revendication « groups » de Keycloak                      │
     └────────────────────────────────────────────────────────────────────────────────────────┘
     stockage Raft /var/lib/openbao (données chiffrées) ─ scellé au démarrage : 3 parts sur 5
          │ découverte OIDC, JWKS
          ▼
  sso.par1.medisphere.internal (VIP lb 10.10.70.200) ─ Keycloak, royaume medisphere, client « openbao »
  git01 : plateforme/secrets (OpenTofu), plateforme/ansible (rôle openbao, parts chiffrées), plateforme/outils (medictl)
```

### Une lecture de secret, de bout en bout

Ce que fera `medictl` en E07, et chaque client du coffre aux paliers suivants :

1. `medictl` présente son **identité** à une méthode d'authentification : `POST /v1/auth/approle/login` avec son `role_id` et son `secret_id`. OpenBao vérifie le couple, l'adresse d'origine (`adm01`), la validité du `secret_id`.
2. La méthode rend un **jeton** qui porte des **politiques** (`medictl`) et une durée (5 minutes). Le jeton ne contient pas les droits : OpenBao les relit à chaque requête.
3. `medictl` demande `GET /v1/kv/data/plateforme/medictl/pve` avec ce jeton (en-tête `X-Vault-Token`). OpenBao trouve la règle la plus précise qui correspond au chemin dans les politiques du jeton : `read` est permis.
4. Le moteur **KV** monté en `kv/` lit l'entrée dans le stockage, la **déchiffre** à travers la barrière et la renvoie. L'audit (palier 2) écrit qui a lu quoi.
5. Cinq minutes plus tard, le jeton expire. Un voleur du jeton n'aurait eu que ces cinq minutes, depuis `adm01`, sur ce seul chemin.

Identité → méthode → jeton → politiques → moteur : c'est toute l'architecture d'OpenBao. Les paliers suivants ne changent que l'identité (JWT d'un job, compte de service d'un pod) et le moteur (identifiants dynamiques, chiffrement, certificats).

---

## Le chemin imposé

1. **VMs** : `plateforme/infra`, état `socle` (module `vm-debian`, enregistrements PowerDNS), puis `plateforme/ansible` (rôle `openbao`, pipeline protégé, ADR-0040).
2. **Flux** : rôle `pare_feu` (`group_vars/role_routeur/pare_feu.yml`), une passerelle à la fois, et `docs/socle/matrice-flux.md` ; filtrage local par `pare_feu_local`.
3. **Configuration du coffre** : projet **`plateforme/secrets`** (créé en E08) en OpenTofu. Exception **voulue**, limitée aux exercices E04 à E07 : montages, politiques, méthodes et rôles sont d'abord créés **à la main** avec la CLI, pour comprendre ce que le code décrira ; E08 les **importe**. Ensuite, plus rien à la main dans la configuration d'OpenBao.
4. **Valeurs des secrets** : jamais dans un dépôt ; écrites dans `kv/` par leurs propriétaires, lues par des identités.
5. **Client Keycloak** : projet `plateforme/identite` (M24), par MR.
6. **Documentation** : `docs/securite/secrets/` de `plateforme/medisphere` (inventaire, conventions, modèle d'accès, garde des parts ; ADR et runbooks aux paliers suivants).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation d'OpenBao (liens en fin de fichier) et les exercices approfondissent.

**Secret, configuration, identité.** Un secret est une donnée dont la **connaissance** donne un pouvoir (mot de passe, jeton, clé privée). Une configuration se lit sans danger. Une identité est ce qu'on **prouve** pour obtenir un secret. Le « secret zéro » est le premier secret qu'il faut donner à une machine pour qu'elle puisse prouver qui elle est : on ne le supprime jamais tout à fait, on le **réduit** (court, lié à une adresse, à usage unique, ou remplacé par une identité fournie par la plateforme : jeton signé de GitLab, compte de service de Kubernetes).

**Statique, dynamique, chiffrement comme service.** Un secret **statique** est stocké tel quel et vit jusqu'à sa rotation (KV). Un secret **dynamique** est **fabriqué** à la demande pour un demandeur (un rôle PostgreSQL créé pour une heure) puis détruit : il n'existe pas avant qu'on le demande, et chaque demandeur a le sien. Le **chiffrement comme service** (transit) garde la clé dans le coffre : l'application envoie des données à chiffrer ou à signer, la clé ne sort jamais.

**Barrière, scellement, Shamir.** Tout ce qu'OpenBao écrit sur disque est chiffré par une **clé de chiffrement** (le trousseau de la barrière), elle-même chiffrée par une **clé racine** (*root key*). Au démarrage, OpenBao ne connaît pas la clé racine : il est **scellé** et ne sert rien. Avec le *seal* **Shamir**, la clé racine est découpée en N **parts** dont il faut un seuil (3 sur 5) pour la reconstituer : c'est le **descellement**. Avec un *seal* **automatique** (`transit` au M25-E25), un autre service détient la clé qui déchiffre la clé racine, et les parts deviennent des **clés de récupération**. Un nœud redémarré se re-scelle toujours.

**Méthodes, jetons, politiques.** Toute requête porte un **jeton**. On l'obtient d'une **méthode d'authentification** (`oidc`, `approle`, `jwt`, `kubernetes`…) en prouvant une identité, ou d'un autre jeton. Un jeton a des **politiques**, une durée (TTL), éventuellement une durée maximale ou une **période** de renouvellement, un **parent** (révoquer le parent révoque ses enfants) et un **accessor** (identifiant pour le consulter ou le révoquer sans le connaître). Les politiques sont des listes de **chemins** et de **capacités** (`read`, `create`, `update`, `delete`, `list`, `sudo`, `deny`) : tout ce qui n'est pas permis est refusé.

**Chemins et montages.** Tout est un chemin : `sys/…` pour l'administration, `auth/<méthode>/…` pour l'authentification, `<montage>/…` pour un moteur. Le **même** moteur peut être monté plusieurs fois (`kv/`, `kv-essai/`) ; chaque montage est isolé.

**Baux.** Un secret dynamique ou un jeton de service vient avec un **bail** (*lease*) : une durée, un renouvellement possible jusqu'à un maximum, une révocation qui détruit le secret à la source. Les secrets KV n'ont pas de bail : ils vivent jusqu'à ce qu'on les change.

**OpenBao et Vault.** OpenBao est le fork **libre** (MPL 2.0, Linux Foundation) de HashiCorp Vault, créé après le passage de Vault sous licence BUSL en 2023. La CLI s'appelle `bao`, l'API reste compatible avec celle de Vault (chemins `/v1/…`, en-tête `X-Vault-Token`, jetons préfixés `s.` au lieu de `hvs.`), ce qui permet d'utiliser les clients de Vault (fournisseur OpenTofu `hashicorp/vault`, ESO, `community.hashi_vault`) — à condition de vérifier chaque fonction utilisée. Le M25-E30 compare avec Vault 2.2.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | **OpenBao 2.6.4** (dernière corrective de la 2.6, paquet `.deb` amont) installé en E03, monté en **2.7.1** en E29 ; fournisseur OpenTofu **`hashicorp/vault` `~> 5.13`** ; OpenTofu 1.13 ; `age` 1.3 ; Keycloak du M24 ; ESO 2.13, SOPS 3.13.3, Sealed Secrets 0.40, Secrets Store CSI 1.6, `community.hashi_vault` 7.1 (palier 2) ; Vault 2.2 (comparaison, E30) |
| Changements de version | [`annexes/versions-bloc-F.md`](../../../annexes/versions-bloc-F.md), section « Secrets » : ruptures de la 2.7 (stockage `file` supprimé, seals de cloud et PKCS#11 en greffons), pas de dépôt APT, ESO 2.x et son API `v1`, SOPS et `SOPS_HC_VAULT_ALLOWLIST`, Cosign et `hashivault://`. Et pour la 2.6 : `disable_mlock` n'existe plus dans OpenBao (mlock retiré en 2.0) ; `bao operator generate-root` passe par des chemins **authentifiés** (les anciens sont désactivés par défaut depuis 2.5.3) |
| `vault01` | VMID **1021**, **10.10.20.21**, Debian 13, 2 vCPU, 1 Go, 20 Go ; étiquettes `socle`, `role-coffre` ; groupe Ansible `role_coffre` |
| `vault02-03`, `kms01` | 1022-1023 (10.10.20.22-23) au M25-E24 ; 1024 (10.10.20.24) au M25-E25 |
| Nom du service | **`openbao.par1.medisphere.internal`** : A vers `vault01` au palier 1, vers la VIP **10.10.20.200** (keepalived VRID 120) au M25-E24 |
| Ports | **8200** (API, interface web, TLS seulement), **8201** (grappe Raft, transfert de requêtes) |
| Fichiers | `/etc/openbao/openbao.hcl`, données Raft `/var/lib/openbao`, TLS `/etc/openbao/tls/{cert,key}.pem` (ACME de step-ca, `cert-renewer@openbao`, rechargement par `SIGHUP`), audit `/var/log/openbao/` (palier 2) ; unité `openbao.service` du paquet, utilisateur `openbao` |
| Initialisation | **5 parts, seuil 3** : Claire, Karim, Sophie, Nadia, `<MOI>` ; parts chiffrées par `age` pour chaque dépositaire, rangées dans `secrets/openbao-init.yml` (Ansible Vault `critique`) de `plateforme/ansible` ; jeton racine initial **révoqué** en E08 |
| Moteur KV | `kv/` (KV v2, 10 versions) : `kv/plateforme/<composant>/<secret>`, `kv/<application>/<env>/<secret>` |
| Méthodes | `oidc/` (personnes, client Keycloak `openbao`, rôle `personne`), `approle/` (machines : `wb-checks`, `medictl`) ; `jwt` monté en `gitlab/` (E10) et `kubernetes` en `k8s-par1/` (E12) au palier 2 |
| Politiques du palier 1 | `plateforme-admin`, `plateforme-lecture`, `securite-audit`, `mediagenda-dev`, `wb-checks`, `medictl` (fichiers `politiques/*.hcl` de `plateforme/secrets`) |
| Groupes externes | `plateforme-admins` → `plateforme-admin` ; `plateforme`, `support` → `plateforme-lecture` ; `securite` → `securite-audit` ; `mediagenda` → `mediagenda-dev` |
| Projet | **`plateforme/secrets`** (E08) : `tofu/` (état S3 `secrets/terraform.tfstate` du compartiment `tofu-state`, chiffré), `politiques/`, `outils/` |
| Documentation | `docs/securite/secrets/` de `plateforme/medisphere` : `inventaire-secrets.md` (E02), `garde-des-parts.md` (E03), `conventions-kv.md` (E04), `modele-acces-coffre.md` (E05) ; ADR-0250, ADR-0251 et runbooks RB-250 à RB-255 aux paliers suivants |
| Tickets | PLAT-26xx, SEC-26xx, DEV-26xx, CHG-26xx, INC-52xx (xx = exercice) |
| Brouillons | `~/m25/eXX/` sur `adm01` (non versionnés, **sans secret** ; tout secret local est dans `~/.config/workbook/` en 600) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton identifiant (GitLab, annuaire, Keycloak) : aussi ton nom de dépositaire |
| `<VERSION-TOFU-MODULES>` | La dernière étiquette publiée de `plateforme/tofu-modules` |
| `<SUPPORT>` | Le support amovible (clé USB) où tu ranges les exports chiffrés des clés simulées |

### Variables de `lab/lab.env`

La fonction `bao_api` de `lab/lib/check-lib.sh` lit le coffre avec l'identité AppRole des vérifications, créée en E07 (`~/.config/workbook/openbao-checks.env`). **Avant E07**, les vérifications lisent avec le jeton de ta session `bao` (lectures seulement) et le signalent par une ligne « ignoré ». Les variables ci-dessous sont **facultatives** :

```
#WB_OPENBAO_URL="https://openbao.par1.medisphere.internal:8200"
#WB_OPENBAO_CHECKS_FILE="$HOME/.config/workbook/openbao-checks.env"   # AppRole wb-checks (E07)
#WB_M25_VAULT01=vault01                                                # alias SSH de vault01
#WB_RACINE_PKI=/usr/local/share/ca-certificates/medisphere-root-ca.crt
```

---

## Règles du module

1. **Un redémarrage scelle.** Tant que l'auto-descellement n'existe pas (M25-E25), tout redémarrage d'OpenBao (service, VM, `pve01`) laisse le coffre **fermé** jusqu'à ce que trois dépositaires donnent leur part. Ne redémarre jamais le service sans l'avoir décidé ; le rôle Ansible refuse de le faire sans qu'on le lui demande.
   > ⚠️ **Attention** : le jour où les parts sont perdues et le coffre scellé, **rien** ne permet de rouvrir les données (c'est le but). La garde des parts (E03) n'est pas une formalité : vérifie, avant de clore E03, que tu sais déchiffrer **trois** parts depuis leurs supports.
2. **Le jeton racine ne sert qu'au démarrage.** Il crée la première configuration (E04-E07), puis il est **révoqué** (E08), après qu'un administrateur nominatif a été vérifié par le SSO. Une nouvelle racine se régénère avec les parts (M25-E28).
3. **Aucun secret sur une ligne de commande** (`ps` et l'historique le montrent), dans Git en clair, dans un ticket ni dans un compte rendu : valeur passée par l'entrée standard (`champ=-`) ou un fichier en 600, en-têtes de `curl` par `-K <(…)`, jetons jamais affichés. La sortie de `bao operator init` ne s'affiche **jamais** : elle part directement, par un tube, dans le chiffrement.
4. **Un accès de secours avant de retirer un accès.** Avant de révoquer la racine (E08) : connexion OIDC d'un administrateur **essayée**, parts accessibles. Avant de toucher au SSO (M24) : `kc-secours`.
5. **Mémoire.** Profil du bloc F ≈ 111 Go sur 128 Go quand `vault01-03` et `kms01` existeront ; au palier 1, `vault01` ajoute 1 Go au profil du M24. Aucune VM temporaire d'un module précédent ne doit tourner (`idp02` détruite au M24-E24). Le palier 1 ne touche pas au cluster, sauf pour lire : si la mémoire manque, arrête `k8s-par1` (procédure du M14), jamais une VM du socle.

---

## Préparer `adm01`

Vérifie d'abord l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 24 46        # mini-projet du M24 : identite-v1 (Keycloak, annuaire, SSO)
admin@adm01:~$ lab/bin/check 06 46        # socle v1 : PKI (step-ca), PowerDNS, NetBox
admin@adm01:~$ step ca health             # ca01 répond (ACME pour vault01)
admin@adm01:~$ curl -s https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration | jq -r .issuer
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Il te faut **1 Go libre** sur `pve01` en plus du profil en cours.

Contrôle les outils dont le palier a besoin : `age` (chiffrement des parts), `jq`, `openssl`, `curl`, `tofu`. La CLI `bao` arrive en E03 par Ansible.

```
admin@adm01:~$ age --version && age-keygen --version
admin@adm01:~$ jq --version && openssl version && tofu version | head -n 1
```

`age` a servi aux instantanés etcd (M14) ; s'il manque, installe le paquet de Debian (`sudo apt install age`, version suffisante pour ce palier : chiffrement pour une clé publique, identités protégées par phrase de passe), de préférence par le rôle de `plateforme/ansible` qui gère les paquets d'`adm01`. La version 1.3 du PLAN sert au M25-E18 (SOPS).

Prépare un **support amovible** (`<SUPPORT>`, une clé USB de ton poste) : E03 y range les exports chiffrés des clés des dépositaires simulés.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 25 <XX>`. Elles sont en lecture seule : DNS, NetBox, chaîne TLS, état du coffre sans jeton (`sys/seal-status`), **métadonnées** du coffre (montages, politiques, rôles, groupes, existence et versions des secrets ; jamais une valeur), SSH en consultation sur `vault01`, Keycloak en lecture (client `wb-checks` du M24), GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M25-EXX/` : `infra/` reproduit `plateforme/infra`, `ansible/` reproduit `plateforme/ansible`, `identite/` reproduit `plateforme/identite`, `secrets/` reproduit `plateforme/secrets`, `outils/` reproduit `plateforme/outils`, `medisphere/` la documentation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
```

L'ordre de la carte est l'ordre de travail : on inventorie avant d'installer, on initialise avant de stocker, on comprend les politiques avant de les attacher à des identités, et on reprend le tout en code avant de jeter la clé racine. E02 peut se faire en parallèle d'E03 (pendant les temps d'attente de la VM et du pipeline).

Durée indicative du palier 1 : 15 à 19 heures.

## Pour aller plus loin

- OpenBao, documentation : concepts (<https://openbao.org/docs/concepts/>), configuration du serveur (<https://openbao.org/docs/configuration/>), stockage Raft (<https://openbao.org/docs/configuration/storage/raft/>), API (<https://openbao.org/api-docs/>), notes de version (<https://openbao.org/docs/release-notes/>)
- OpenBao, politiques : <https://openbao.org/docs/concepts/policies/> · jetons : <https://openbao.org/docs/concepts/tokens/> · méthodes JWT/OIDC : <https://openbao.org/docs/auth/jwt/> · AppRole : <https://openbao.org/docs/auth/approle/>
- Fournisseur OpenTofu `hashicorp/vault` : <https://search.opentofu.org/provider/hashicorp/vault/latest>
- `age` : <https://github.com/FiloSottile/age> · OWASP *Secrets Management Cheat Sheet* : <https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html>
