# RB-371 — Réversibilité et fin de contrat d'un client

| | |
|---|---|
| Portée | client hébergé décrit en type `client` dans `plateforme/equipes` (aujourd'hui : GHSV) |
| Déclencheurs | demande du client (ERV-02), essai annuel ou de 3e année (ERV-03), fin de contrat, révocation des clés demandée par le client (ESC-06, R-14) |
| Délais (GHSV) | export livré sous **30 jours** ; destruction sous **30 jours** après validation de l'export (ERV-04) |
| Rôles | responsable du compte (pilote, communication), Julien Petit (export, relecture), un membre de `plateforme-admins` (déchiffrement, destruction), Sophie Laurent (témoin de la destruction, procès-verbal) |
| Outils | `ms-reversibilite` (`plateforme/outils`), `bao`, `kubectl`, `aws` |
| Créé | F7-S07 (PLAT-3707) |

## 1. Produire un export

1. Prévenir le client (ticket commun) : date, périmètre, format (`LISEZMOI.md` de l'export).
2. Depuis `adm01`, connecté à OpenBao (OIDC, membre du groupe du compte) et au cluster :
   ```
   admin@adm01:~$ ms-reversibilite exporter ghsv prod
   ```
   Recopier le résumé affiché (dossier, empreinte de l'archive chiffrée, lignes par table) dans le compte rendu (`docs/capstone/reversibilite/<AAAA-MM-JJ>.md`). L'outil travaille en mémoire (`/dev/shm`) et lit la base en transaction en lecture seule.
3. Vérifier le dépôt : `ms-reversibilite lister ghsv`.

## 2. Essai de relecture (obligatoire après chaque export)

1. Une base PostgreSQL **vierge**, sans outil de MédiSphère : VM jetable (VMID 3701, `vsandbox`, Debian 13 et son PostgreSQL 17 — une version **différente** de celle de la production prouve l'indépendance du format) ou conteneur PostgreSQL sur `adm01`.
2. Un membre de `plateforme-admins` obtient un jeton d'opération (15 min, 10 usages, politique `ghsv-dechiffrement` seule : aucune personne ne la porte en permanence, ADR-0371), puis relit :
   ```
   admin@adm01:~$ export BAO_TOKEN="$(bao token create -role=ghsv-dechiffrement -policy=ghsv-dechiffrement -field=token)"
   admin@adm01:~$ ms-reversibilite relire ghsv <DOSSIER> --pg 'postgresql://essai@<HÔTE>/essai'
   admin@adm01:~$ bao token revoke -self; unset BAO_TOKEN
   ```
   La relecture vérifie la signature, `MANIFESTE.sha256`, le nombre d'enregistrements de `rendez-vous.jsonl`, et recharge l'annexe technique dans la base vierge. Le tiers de l'ADR-0374 (équipe Data) relit **sans** l'outil, avec le seul `LISEZMOI.md`.
   Attendu : signature valide, toutes les empreintes justes, même nombre de lignes lues et rechargées.
3. Détruire la base d'essai (et la VM 3701). Compte rendu : durée, résultat, écarts.

## 3. Remise au client

1. Le client fournit sa clé publique `age` (ou une adresse SFTP de son côté, à décider avec lui) par un canal authentifié.
2. Rechiffrer pour le client : `relire` sans `--pg` dans `/dev/shm`, puis `age -r <CLÉ-PUBLIQUE-DU-CLIENT>` sur l'archive en clair, dépôt dans un compartiment ou un lien à durée limitée **dédié** ; jamais par courriel.
3. Transmettre séparément : le manifeste (déjà signé), la clé publique de signature `ghsv-signature`, la notice.
4. Le client confirme l'exploitabilité (ERV-03) : sa validation **écrite** déclenche le délai de destruction (§5) en fin de contrat.

## 4. Ce que MédiSphère garde après la fin du contrat

Seulement ce qu'une obligation légale impose, écrit **avant** la destruction, avec sa durée et sa protection (R-17 du GHSV) : par exemple les journaux d'audit de la plateforme (conservation d'un an, `preuves-conformite` en `COMPLIANCE`), les factures. Tout le reste est détruit.

## 5. Destruction et effacement cryptographique

⚠️ **Irréversible.** Préalables : export final **validé par écrit** par le client ; décision écrite de Claire Morel ; deux personnes présentes (un `plateforme-admins`, Sophie Laurent).

1. MR sur `equipes/ghsv.yaml` : `etat: retiree` (les droits tombent, les Applications sont supprimées **sans** leurs objets).
2. Supprimer les données en clair, dans cet ordre, en journalisant chaque commande (`script`) :
   - espaces `ghsv-recette`, `ghsv-prod` (PVC, base, cache) : suppression explicite, puis vérification que les images RBD ont disparu de `ceph-par1` (et purge de la corbeille RBD) ;
   - réplique de PAR2 (`k8s-par2`, espace `ghsv-prod`) et ses volumes ;
   - compartiments `cnpg-ghsv` (s3-01, **et** s3-02 : `filer.sync` propage les suppressions, vérifier) et `ghsv-reversibilite` (toutes les versions) ;
   - journaux applicatifs du client dans Loki (locataire `mediagenda`, sélecteur `namespace=~"ghsv-.*"`) : API de suppression de Loki si activée, sinon expiration par la rétention (30 jours), notée au procès-verbal ;
   - sauvegardes Velero et PBS qui contiennent des objets du client : liste, suppression ou expiration datée.
3. **Effacement cryptographique** : rend illisible ce qui ne peut pas être effacé une à une (copies en rétention).
   - MR sur `plateforme/secrets` : `deletion_allowed = true` pour les clés `ghsv-*` ; `apply` par le pipeline ;
   - un `plateforme-admins` crée un jeton d'opération par le rôle de jeton `ghsv-destruction` (politique `ghsv-destruction` seule, 15 min, 10 usages : `bao token create -role=ghsv-destruction -policy=ghsv-destruction`) ; puis, avec ce jeton : `bao delete transit/keys/ghsv-exports` (et `-signature`, `-sauvegardes`) ;
   - les **instantanés Raft** d'OpenBao (compartiment `openbao-instantanes`, PAR1 et copie de PAR2) contiennent encore les clés jusqu'à leur expiration : la date de la dernière expiration est écrite au procès-verbal (c'est là que la clé survit, ADR-0371) ;
   - preuve : `bao read transit/keys/ghsv-exports` → introuvable ; journal d'audit d'OpenBao (Loki, locataire `audit`) des suppressions ; une enveloppe d'export conservée pour la preuve **ne se déchiffre plus** (erreur montrée au procès-verbal) ;
   - MR qui retire `ghsv-*` de l'état OpenTofu (`tofu state rm` ou retrait du rendu, selon l'ordre choisi) : le plan doit être vide.
4. Retirer le courtier d'identité et les comptes fédérés (RB-372 §6).
5. **Procès-verbal de destruction** (`docs/capstone/clients/ghsv/pv-destruction.md`, signé par les deux personnes) : liste de ce qui a été détruit, comment, quand, preuves ; ce qui est gardé (§4) et jusqu'à quand. Remis au client sous 30 jours (ERV-04). Preuves déposées par `ms-preuves` dans `preuves-conformite`.

## 6. Rotation des clés

Automatique chaque année (`auto_rotate_period`). Après une rotation, réenvelopper les enveloppes existantes :
```
admin@adm01:~$ bao write transit/rewrap/ghsv-exports ciphertext=<ENVELOPPE>
```
puis remplacer `export.cle-enveloppee` dans le compartiment (nouvelle version de l'objet) ; enfin, relever `min_decryption_version` quand plus aucune enveloppe n'utilise l'ancienne version.

## Vérifications

- `lab/bin/check F7 7` vert (clés non exportables et non supprimables, export présent, compte rendu publié).
