# Chiffrement applicatif par le moteur transit d'OpenBao

> Propriétaire : équipe Plateforme · Relu par : Sophie Laurent (RSSI) · Ticket : SEC-2617 (M25-E17)
> Dernière revue : <DATE> · Prochaine revue : à chaque nouvelle clé, et au plus tard dans un an

## 1. Quand utiliser transit

Transit chiffre et déchiffre **pour** un client : la clé reste dans OpenBao, le client n'en voit
jamais le matériel. On l'utilise quand une **donnée** doit être stockée ailleurs (fichier, base,
ticket, objet S3) sans que ce stockage puisse la lire :

| Cas | Transit ? | Pourquoi |
|---|---|---|
| Champs sensibles d'un export (`medictl`, fiches d'intervention) | Oui, `encrypt`/`decrypt` | Petites valeurs, peu nombreuses |
| Colonne de données de santé dans PostgreSQL (MédiAgenda : NIR, motif) | Oui, avec **contexte dérivé** par patient (`derived`) | Une fuite de la base seule ne livre rien ; le coffre devient une dépendance de lecture |
| Gros fichiers, sauvegardes | Non directement : **clé de données** (`datakey/wrapped`), chiffrement local, la clé de données chiffrée stockée à côté | Ne pas faire transiter des gigaoctets par le coffre |
| État OpenTofu | Fournisseur de clé `openbao` (même principe : clé de données) | Une clé de transit **par état** |
| Mot de passe, jeton (un secret qu'un service doit **utiliser**) | Non : KV v2 ou secret dynamique | Transit protège une donnée stockée ailleurs, pas un secret à distribuer |
| Signature (Cosign, M25-E20) | Oui, clé asymétrique `sign`/`verify` | La clé privée ne sort pas |

## 2. Règles des clés

- **Une clé par usage et par propriétaire** : `medictl-donnees`, `sops-plateforme`, `cosign-medisphere`, `<application>-<donnee>` ; jamais de clé partagée entre équipes.
- Créée par OpenTofu (`plateforme/secrets`, `tofu/transit.tf`), **non exportable**, **sans sauvegarde en clair**, `deletion_allowed = false`. Une clé détruite rend illisible pour toujours tout ce qu'elle a chiffré (y compris un état OpenTofu : essayé en E17).
- Rotation **automatique annuelle** (`auto_rotate_period = 365 j`) pour les clés de chiffrement ; une rotation ne rend rien illisible : les anciennes versions déchiffrent toujours.
- **Rechiffrement** (`rewrap`) après rotation par un job du propriétaire de la donnée (pour `medictl` : `medictl transit rechiffrer`) ; le clair ne sort jamais pendant un rewrap.
- **Crypto-effacement** : relever `min_decryption_version` rend les chiffrés plus anciens illisibles (réversible tant que les versions existent : c'est un **gel**) ; `min_encryption_version` puis `trim` **détruit** les anciennes versions (irréversible). Décision du propriétaire de la donnée et de la RSSI, tracée par ticket (ex. départ d'un prestataire, RB-250).
- Politiques : le **client** a `update` sur `transit/encrypt|decrypt|rewrap/<sa clé>` et rien sur `transit/keys/…` ; les réglages et la rotation sont à `plateforme-admin` ; personne n'a `transit/export/*` ni `transit/backup/*`.

## 3. Ce qu'il faut savoir avant de chiffrer une colonne

- **Disponibilité** : si OpenBao est indisponible, la donnée l'est aussi. Le coffre devient une dépendance de lecture (grappe de trois nœuds, M25-E24 ; supervision, M25-E27).
- **Recherche** : un chiffré transit est non déterministe (même clair → chiffrés différents). Pour rechercher par égalité : chiffrement **convergent** (`derived` + `convergent_encryption`), au prix d'une fuite d'égalité ; ou une empreinte HMAC séparée (`transit/hmac/<clé>`).
- **Volume** : `batch_input` (une requête pour 100 valeurs) ; au-delà, clé de données.
- **Format** : le chiffré commence par `vault:v<N>:` (préfixe historique, conservé par OpenBao) ; prévoir la place en base (~ 1,4 × le clair + 30 octets).
- **Audit** : chaque appel est dans le journal d'audit (M25-E21), avec l'identité et le chemin, jamais le clair (HMAC).

## 4. États OpenTofu (promesse du M05-E27)

| État | Clé | Décision |
|---|---|---|
| `socle` (`plateforme/infra`) | phrase PBKDF2 (inchangé) | Il recrée `vault01-03` et `kms01` : il ne peut pas dépendre du coffre (dépendance circulaire au PRA) |
| `secrets` (`plateforme/secrets`) | `tofu-secrets` (à créer) | Le coffre doit être en marche pour appliquer cet état de toute façon |
| `identite` (`plateforme/identite`) | `tofu-identite` (à créer) | Idem pour Keycloak ; la CI aura besoin de `transit/datakey/plaintext/tofu-identite` et `transit/decrypt/tofu-identite` |
| `envs/m2x` (VMs temporaires) | phrase PBKDF2 | États jetables |

Migration : comme M05-E27 (méthode `aes_gcm` avec le fournisseur `openbao`, l'ancienne méthode PBKDF2 en `fallback`, un `apply` qui réécrit l'état, puis retrait du `fallback`). Planifiée avec la politique de rotation (M25-E33).

## 5. Exploitation

- Rotation manuelle (incident) : `bao write -f transit/keys/<clé>/rotate` (`plateforme-admin`), puis rewrap par le propriétaire.
- Vérifier l'état d'une clé : `bao read transit/keys/<clé>` (`latest_version`, `min_decryption_version`, `auto_rotate_period`, `exportable`).
- Une clé n'est jamais supprimée sans ticket de la RSSI et preuve qu'aucune donnée ne dépend plus d'elle.
