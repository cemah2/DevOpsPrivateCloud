# RB-252 — Sauvegarde et restauration d'OpenBao

> `docs/securite/secrets/runbooks/RB-252-sauvegarde-restauration-openbao.md` — M25-E26 (SEC-2626). Propriétaire : équipe Plateforme. Relu par : Sophie Laurent.
> Alerte liée : `OpenBaoInstantaneEnRetard` (M25-E27). Restauration éprouvée le `<DATE>` (voir §8).

## 1. Ce qui est sauvegardé, où, par qui

| Quoi | Comment | Où | Rétention | Ce qu'il faut pour le relire |
|---|---|---|---|---|
| Données de la grappe (Raft : secrets, politiques, montages, baux, jetons) | `openbao-instantane.timer` (minute 07, chaque heure) sur les trois nœuds, seul l'actif envoie ; `bao operator raft snapshot save` ; chiffré `age` | `s3-01`, `s3://openbao-instantanes/horaire/<jour>/<nœud>-<horodatage>.snap.age` (compartiment versionné, suppression refusée à l'identité qui écrit) | 30 jours (cycle de vie) | la clé **privée** `age` de restauration (Vault `critique` `secrets/openbao-restauration.age`, papier au coffre) **et** la clé de transit `autodescellement-par1` de `kms01` (ou les clés de récupération : voir §7) |
| VMs `vault01-03`, `kms01` | PBS, tâche `secrets-nuit` (02:30) | `pbs-par2-secrets`, espace de noms `par1/secrets` | 14 quotidiennes, 8 hebdomadaires | rien de plus (mais voir §4) |
| Configuration | Git : `plateforme/secrets` (OpenTofu), `plateforme/ansible` (rôles, inventaire) | GitLab | historique | — |
| Parts et clés | Vault `critique` (`secrets/openbao-init.yml`, `secrets/kms01-init.yml`), supports hors ligne des dépositaires | voir `garde-des-parts.md` | — | identités `age` des dépositaires |

## 2. Contrôle quotidien (astreinte)

- Alerte `OpenBaoInstantaneEnRetard` muette ; tableau OpenBao : « âge du dernier instantané » < 1 h 10.
- `sudo journalctl -u openbao-instantane --since -2h` sur le nœud actif : ligne `envoyé : s3://…`.

## 3. Ce que contient un instantané

Une archive gzip : `meta.json` (index, terme, configuration Raft), `state.bin` (toutes les paires clé/valeur du stockage, **chiffrées par la barrière** : aucun secret lisible), `SHA256SUMS` et `SHA256SUMS.sealed`. Il porte aussi le trousseau chiffré par la clé racine, elle-même chiffrée par le seal : sans `kms01` (même clé de transit), ou sans les clés de récupération et une procédure de migration, il est illisible. C'est voulu : un instantané volé ne suffit pas. C'est aussi un risque : **perdre `kms01` rend tous les instantanés inutiles** (RB-251 §7).

## 4. PBS : ce que ça permet et ne permet pas

- Restaurer **un** nœud (VM) d'hier : il redémarre avec des données Raft anciennes, rejoint la grappe et **rattrape** par Raft (journaux ou instantané envoyé par le leader). Utile, mais un nœud neuf vide (VM recréée, `retry_join`) fait la même chose plus proprement.
- Restaurer **les trois** VMs : chacune a été sauvegardée à un instant différent ; Raft prendra l'état du nœud élu, d'autres écritures récentes peuvent disparaître. Possible en dernier recours, jamais comme méthode.
- Restaurer `kms01` : **le** cas où PBS est indispensable (sa clé de transit n'existe nulle part ailleurs).

## 5. Restauration complète sur une grappe neuve (essai trimestriel ou perte totale)

Durée mesurée : voir §8. Principe : une grappe neuve initialisée, puis remplacée par l'instantané.

1. **Isolement.** Une copie vivante a les mêmes moteurs et baux que la production : pour un essai, VM `bao-restauration` (2252, `vsandbox`, 10.10.99.52, état `envs/m25`), **seul** flux sortant : `kms01` 8200 (bordure et pare-feu local de `kms01`, règle temporaire marquée `M25-E26`). Jamais de flux vers 10.10.41.64-65 (PostgreSQL), Keycloak, GitLab.
2. **Jeton d'essai sur `kms01`** (jeton racine régénéré, RB-251 §5) : `bao token create -orphan -no-default-policy -policy=kms-autodescellement -ttl=4h -display-name=restauration-essai -format=json | jq -r '"vault_kms_jeton_essai: \(.auth.client_token)"' | ansible-vault encrypt …` ; noter l'accesseur.
3. **VM et OpenBao** : `tofu apply` (`groupes = ["restauration"]`), rôle `openbao` (inventaire d'essai), même version que celle de l'instantané.
4. **Initialisation** : `BAO_ADDR=https://bao-restauration.par1.medisphere.internal:8200 bao operator init -recovery-shares=1 -recovery-threshold=1 -format=json` → sortie dans un fichier 600 de `/run/user/$UID` (jetable : ces clés et ce jeton cessent d'exister à la restauration).
5. **Instantané** : `outils/instantane-vers-restauration.sh bao-restauration` (téléchargement, déchiffrement en tube, copie, contrôle).
6. **Restauration** (sur la VM, jeton racine de la grappe neuve passé par `bao login -`) : `bao operator raft snapshot restore -force /var/tmp/restauration.snap` ; `-force` car l'instantané vient d'une autre grappe (autre clé racine). Le jeton utilisé cesse aussitôt d'exister.
7. **Redémarrage** du service : le nœud doit se desceller seul (seal `transit`, même clé).
8. **Contrôles** : `bao status` (transit, descellé), `bao operator raft list-peers` (un seul pair : la configuration Raft du nœud restauré est la sienne), `bao login -method=oidc` impossible (pas de Keycloak joignable : attendu) → se connecter avec un jeton de la production encore valide, ou générer un jeton racine sur la copie avec les **clés de récupération de la production** (elles viennent de l'instantané) ; lire un secret ancien ; vérifier l'**absence** du secret témoin écrit après l'instantané (RPO).
9. **Nettoyage** : effacer `/var/tmp/restauration.snap`, `tofu apply` (`groupes = []`), révoquer le jeton d'essai sur `kms01` par son accesseur, retirer la règle temporaire (MR), effacer les sorties de l'étape 4.

## 6. Restaurer la PRODUCTION (perte des données de la grappe)

Décision de Claire Morel et Sophie Laurent (perte de données = depuis le dernier instantané). Sur la grappe existante, nœud actif : `bao operator raft snapshot restore` **sans** `-force` (même grappe) ; les nœuds en attente reçoivent l'état par Raft. Si la grappe est détruite : §5 sur `vault01`, puis `vault02` et `vault03` vides qui rejoignent. Ensuite : faire tourner les identifiants dynamiques émis depuis l'instantané (ils existent dans PostgreSQL, plus dans le coffre), révoquer les jetons émis depuis.

## 7. Sans `kms01`

Instantané illisible tant que la clé de transit manque : restaurer `kms01` depuis PBS d'abord (RB-251 §4, §7).

## 8. Mesures du dernier essai

| Élément | Valeur |
|---|---|
| Date de l'essai | `<DATE>` |
| Dernier instantané utilisé | `<CLÉ-OBJET>` (pris à `<HEURE>`) |
| T0 (début : décision de restaurer) | `<HEURE>` |
| Secret témoin `kv/wb-essais/rpo` écrit à | `<HEURE>` — absent après restauration |
| T1 (copie descellée, secret ancien lu) | `<HEURE>` |
| **RPO mesuré** | `<MINUTES>` (au plus une heure plus la durée d'envoi, par construction) |
| **RTO mesuré** | `<MINUTES>` (dont création de la VM `<MINUTES>`, OpenBao `<MINUTES>`, restauration `<SECONDES>`) |

Ordres de grandeur dans le lab : la restauration elle-même prend quelques secondes ; le RTO est dominé par la création et la configuration de la VM (10 à 20 min). Avec une VM déjà prête, il tombe sous 5 min.

## 9. Essai trimestriel

Le premier lundi de chaque trimestre, par l'astreinte de la semaine : §5 en entier, mesures reportées en §8, ticket `SEC-` fermé avec le lien de la MR de ce runbook.
