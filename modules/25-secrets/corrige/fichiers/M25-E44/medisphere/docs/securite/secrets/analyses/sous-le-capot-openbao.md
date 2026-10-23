# Sous le capot d'OpenBao : barrière, trousseau, Raft et baux

> M25-E44 (PLAT-2644). Compte rendu pour les arrivants de l'équipe Plateforme. Relevés du `<AAAA-MM-JJ>`
> sur la grappe `openbao-par1` (OpenBao 2.7.1). **Modèle du corrigé** : les chiffres ci-dessous viennent
> d'un banc (une grappe de deux nœuds et un `kms01` simulé) ; remplace-les par les tiens. Aucun secret,
> aucun jeton, aucun accesseur complet.

## Les clés

```
admin@adm01:~$ bao status | grep -E 'Seal Type|Recovery'
Seal Type                transit
Recovery Seal Type       shamir
admin@adm01:~$ bao read sys/key-status
encryptions     1846
install_time    2026-…T…Z
term            1
admin@adm01:~$ bao read sys/rotate/config
enabled           true
interval          0
max_operations    3865470566
```

Hiérarchie, de l'extérieur vers les données :

```
kms01 : clé transit autodescellement-par1 (aes256-gcm96, non exportable)
   └─ chiffre → clé racine (root key) — stockée chiffrée dans Raft : core/hsm/barrier-unseal-keys
         └─ chiffre → trousseau (keyring : termes 1..N) — stocké chiffré : core/keyring
               └─ chiffre → toutes les entrées écrites par la barrière (montages, secrets, jetons, baux)
clés de récupération (Shamir 5/3) : ne déchiffrent rien ; autorisent generate-root, rotate-keys, migration
```

- `term` : numéro de la clé **active** du trousseau ; `install_time` : date de son installation ;
  `encryptions` : nombre de chiffrements faits avec elle.
- Rotation automatique activée par défaut au-delà de `max_operations` ≈ 3,87 milliards de
  chiffrements : AES-GCM à nonce aléatoire de 96 bits ne doit pas dépasser environ 2³² chiffrements
  avec la même clé (probabilité de collision de nonce) ; le seuil par défaut s'en tient en dessous.
  `interval = 0` : pas de rotation périodique ; MédiSphère en fait une par an (procédure ci-dessous).

## La rotation du trousseau

Séance du `<AAAA-MM-JJ>` (consignée dans `procedure-jeton-racine.md`) : jeton racine régénéré avec
trois clés de récupération (procédure M25-E28), une seule opération, révocation dans la minute.

```
admin@adm01:~$ bao operator rotate
Success! Rotated key

Key Term            2
Install Time        <JJ> <Mmm> <AA> <hh:mm> UTC
Encryption Count    1
admin@adm01:~$ bao read -field=term sys/key-status
2
admin@adm01:~$ bao token revoke -self
```

- La boucle d'écriture et de lecture (E24) n'a vu **aucune** erreur : opération en ligne, sans
  verrou global perceptible.
- Rien n'est réécrit : les entrées anciennes restent chiffrées par le terme 1, gardé dans le
  trousseau ; toute écriture nouvelle utilise le terme 2. L'entrée `core/keyring` du stockage a
  changé (nouvelle version, chiffrée par la clé racine).
- Sans `sudo` sur `sys/rotate`, refus (403) : c'est voulu, `plateforme-admin` ne l'a pas.
- À ne pas confondre : `bao operator rotate-keys` (nouvelle clé racine et nouvelles parts **de
  récupération**, avec le quorum des parts actuelles) et la rotation de la clé `autodescellement-par1`
  sur `kms01` (changer la clé qui protège la clé racine, puis la réenvelopper).

## Le disque d'un nœud

Nœud en attente (`vault02`), lecture seule, rien copié :

```
root@vault02:~# ls -la /var/lib/openbao /var/lib/openbao/raft
-rw------- 1 openbao openbao 16801792 … vault.db          # BoltDB : l'état (FSM)
drwx------ 2 openbao openbao     4096 … raft/snapshots
-rw------- 1 openbao openbao 16801792 … raft/raft.db      # journal Raft
root@vault02:~# strings /var/lib/openbao/vault.db | grep -oE '^.?(core|sys|logical)/[a-z-]+' | sed 's/^.//' | sort | uniq -c
     12 core/…        41 logical/…        57 sys/…
root@vault02:~# strings /var/lib/openbao/vault.db | grep -c mediagenda
0
```

| Cherché | Trouvé ? | Pourquoi |
|---|---|---|
| structure (`core/mounts`, `core/keyring`, `core/seal-config`, `core/hsm/barrier-unseal-keys`, `sys/policy/<nom>`, `sys/token/accessor/<empreinte>`) | **oui**, en clair | les **clés** de stockage ne sont pas chiffrées, seules les **valeurs** le sont |
| identifiants des montages (`logical/<uuid>/…`) | oui | idem |
| noms des secrets KV v2 (`mediagenda/prod/valkey`) | **non** | le moteur KV v2 range les métadonnées sous un chemin **chiffré** segment par segment et les versions sous une **empreinte** |
| une valeur connue de moi | non | chiffrée par la barrière (AES-GCM, terme 1 ou 2) |
| un jeton | non | rangé par empreinte salée (`sys/token/id/h…`) |
| noms de politiques | **oui** (`sys/policy/mediagenda-dev`) | clés de stockage en clair |

Un voleur du disque (ou d'un instantané) apprend la **forme** du coffre (montages, noms de politiques,
nombre d'entrées) ; il lui manque la clé racine, donc `kms01` **et** son jeton (ou une copie de la clé
de transit, non exportable).

## Raft

```
admin@adm01:~$ bao operator raft list-peers
Node       Address                               State       Voter
vault01    vault01.par1.medisphere.internal:8201  leader      true
vault02    vault02.par1.medisphere.internal:8201  follower    true
vault03    vault03.par1.medisphere.internal:8201  follower    true
admin@adm01:~$ bao read -format=json sys/leader | jq '.data | {raft_committed_index, raft_applied_index}'
admin@adm01:~$ bao operator raft autopilot state
```

Un nœud dont l'index appliqué prend du retard (`last_index` dans autopilot) n'est plus **sain** pour
autopilot ; au-delà de `dead_server_last_contact_threshold` sans contact, il est candidat au nettoyage
(`cleanup_dead_servers`, borné par `min_quorum = 3`). Un nœud qui revient rattrape par le journal, ou
par un instantané envoyé par le leader si le journal a été compacté.

## Le nœud en attente

Sur `vault02` (en attente), par son adresse propre, avec mon jeton OIDC (en-tête par `-K`) :

| Requête | Code | Ce qui s'est passé |
|---|---|---|
| `GET kv/metadata/wb-essais/bascule` | 200 | **servie localement** (lecture permise sur un nœud en attente depuis la 2.5 ; journal : `entering read-enabled standby mode`) |
| `POST kv/data/wb-essais/bascule` | 200 | **transmise** au nœud actif par le port de grappe 8201 (TLS mutuel), réponse relayée |
| idem avec `X-Vault-No-Request-Forwarding: true` | **307**, `Location: https://vault01…:8200/v1/kv/data/wb-essais/bascule` | **redirection** : au client d'aller voir l'actif |
| `GET kv/data/wb-essais/bascule` juste après l'écriture | 404 puis 200 | lecture **à terme cohérente** : le nœud en attente n'avait pas encore appliqué l'entrée |

Si 8201 était filtré entre deux nœuds : la transmission échoue et l'écriture sur un nœud en attente
retombe en redirection (307) ; un client qui ne suit pas les redirections échoue. Les clients de
MédiSphère passent par la VIP, donc par l'actif.

## Les baux

```
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette/
admin@adm01:~$ bao write -format=json sys/leases/lookup lease_id=db-mediagenda/creds/mediagenda-api-recette/<ID> \
    | jq '.data | {ttl, expire_time, renewable}'
```

Le bail est la **trace** d'un secret émis (identifiant, durée, chemin de révocation) ; le secret, lui,
est le rôle PostgreSQL créé. À l'échéance, le **gestionnaire d'expiration** du nœud **actif** révoque
le rôle dans PostgreSQL (journal du nœud en attente : `skipping lease restoration - standby`). Quand
l'actif change, le nouveau recharge les baux depuis le stockage avant de servir. Si PostgreSQL est
injoignable à la révocation, OpenBao réessaie avec un délai croissant (journal `failed to revoke
lease`, métrique de baux qui ne baisse pas : `OpenBaoBauxNombreux`).

## Réponses aux questions

1. **Deux niveaux** : la clé racine ne chiffre que le trousseau ; la changer (rotate-keys, migration de
   seal) ne réécrit qu'une entrée. Le trousseau chiffre tout ; le faire tourner n'oblige à rien
   réécrire (les anciens termes restent pour lire). Une seule clé obligerait à tout rechiffrer.
2. **Rotations** : trousseau (limite d'usage AES-GCM, compromission supposée d'un terme ; plateforme,
   jeton racine en cérémonie, annuelle) ; clé racine et parts (départ d'un dépositaire, soupçon sur
   une part ; trois dépositaires) ; clé de transit de `kms01` (soupçon sur `kms01` ; cérémonie
   `kms01` + réenveloppement) ; jeton du seal (fuite de `kms.env` ; plateforme, Vault `critique`).
3. **Clé racine** : en mémoire quand le nœud tourne ; chiffrée par `kms01` dans Raft quand il est
   arrêté et dans tout instantané. Pour lire un secret d'un instantané volé : la clé `age` de
   restauration, **et** `kms01` joignable avec un jeton qui peut déchiffrer (ou les clés de
   récupération pour une migration vers Shamir sur un serveur à soi, ce qui exige aussi `kms01`).
4. **Noms KV v2** : chiffrés ou hachés par le moteur ; la structure de la barrière reste en clair
   parce qu'elle sert à **adresser** les entrées. Un attaquant déduit les montages, les politiques,
   le volume de secrets et de jetons, les dates d'écriture (par le journal Raft).
5. **Lecture sur un nœud en attente** : oui (2.5+). Cohérence à terme : une lecture juste après une
   écriture peut être périmée ; l'en-tête `X-Vault-Index` et `X-Vault-Inconsistent` permettent
   d'exiger l'état (ou `disable_standby_reads`).
6. **Transmission contre redirection** : la transmission est transparente et passe par 8201 en TLS
   mutuel (certificat interne de grappe) ; la redirection exige un client qui suit le 307 et une
   adresse `api_addr` joignable par lui.
7. **Bail** : non, c'est sa trace et sa poignée de révocation. Révocation impossible : nouvelle
   tentative, bail qui traîne, compteur qui monte, journal du nœud actif.
8. **Preuves pour l'auditeur** : `strings`/comptages sans valeur ni nom de secret ; `sys/seal-status`
   (`transit`, clé non exportable sur `kms01`) ; essai de restauration RB-252 qui **échoue** sans
   `kms01`. Hypothèse à défendre : `kms01` et son jeton ne sont pas volés **avec** le disque
   (hyperviseur, sauvegardes PBS séparées, ADR-0250).
