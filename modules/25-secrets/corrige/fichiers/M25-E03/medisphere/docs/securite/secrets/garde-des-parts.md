# Garde des parts de la clé racine d'OpenBao

> Décision et procès-verbal d'initialisation du coffre (M25-E03, PLAT-2603). Ne contient **aucune
> valeur** : ni part, ni jeton, ni clé privée. Toute modification passe par une MR relue par Sophie
> Laurent.

## Décision

| Point | Décision | Pourquoi |
|---|---|---|
| Découpage | 5 parts, seuil 3 (Shamir) | Une personne seule ne peut rien ; deux absents n'empêchent pas de desceller |
| Dépositaires | Claire Morel (1), Karim Benali (2), Sophie Laurent (3), Nadia Roussel (4), `<MOI>` (5) | Deux équipes (plateforme, sécurité), la direction et l'astreinte : pas de quorum possible au sein d'un seul service |
| Protection de chaque part | chiffrée par `age` pour la clé publique **de son seul dépositaire** | Le fichier commun ne révèle rien sans la clé privée de la personne |
| Où sont les parts chiffrées | `secrets/openbao-init.yml` de `plateforme/ansible`, Ansible Vault `critique` | Sauvegardé avec le dépôt ; deux verrous (identité `critique`, puis clé privée age) |
| Clés privées age | chacune chez son dépositaire, protégée par une phrase de passe ; copie de secours chiffrée sur support amovible, sous scellé, au coffre physique | Jamais sur un serveur, jamais dans un dépôt |
| Lab | les clés de Claire, Karim, Sophie et Nadia sont **simulées** : générées par `<MOI>`, exportées chiffrées sur un support amovible, **effacées d'`adm01`** | Reproduire la séparation sans quatre personnes réelles ; écart assumé (une seule personne a vu les quatre clés le jour de l'initialisation) |
| Jeton racine initial | chiffré pour `<MOI>`, utilisé de M25-E04 à E08, **révoqué** en E08 ; régénéré à la demande par les parts (`bao operator generate-root`, M25-E28) | Un jeton racine est un compte partagé tout-puissant sans expiration |
| Après le M25-E25 | les parts deviennent des **clés de récupération** (seal `transit`) : même garde | Elles servent alors à régénérer un jeton racine ou à migrer le seal, plus au démarrage |

## Procès-verbal d'initialisation

| Champ | Valeur |
|---|---|
| Date et heure (UTC) | `<AAAA-MM-JJTHH:MM:SSZ>` (champ `date` de `openbao_init`) |
| Serveur | `vault01` (OpenBao 2.6.4), `https://openbao.par1.medisphere.internal:8200` |
| Officiant | `<MOI>` |
| Témoin | `<NOM DU TÉMOIN>` (au lab : relecture de ce PV par Karim Benali en MR) |
| Commande | `bao operator init -format=json -key-shares=5 -key-threshold=3`, sortie envoyée directement dans `outils/openbao-parts.sh chiffrer` puis `ansible-vault encrypt` (aucune copie en clair, aucun affichage) |
| Contrôles | `outils/openbao-parts.sh resume` : 5 parts, seuil 3, un dépositaire par part ; `bao status` : `Initialized true` |
| Premier descellement | parts `<n°>`, `<n°>`, `<n°>` présentées par `outils/openbao-parts.sh desceller` ; `Sealed false` à `<HH:MM>` |
| Clés simulées | exportées sur `<SUPPORT>` (étiquette `<ÉTIQUETTE>`), effacées d'`adm01` à `<HH:MM>` (`shred -u`) |
| Écarts | `<aucun / description>` |

## Descendre au coffre : quand et comment

- **Redémarrage d'un nœud** (palier 1, avant l'auto-descellement) : trois dépositaires, chacun avec sa clé, lancent `outils/openbao-parts.sh desceller <n°> <clé>` depuis `adm01`. Personne ne transmet sa part à quelqu'un d'autre.
- **Régénérer un jeton racine** (M25-E28) : `bao operator generate-root` avec trois parts, depuis une session authentifiée d'un administrateur ; jeton révoqué à la fin de l'opération.
- **Départ d'un dépositaire** : nouvelles parts (`bao operator rotate-keys`, ex-`rekey`, avec le seuil des parts actuelles, M25-E44) avant son départ ; mise à jour de `pki/openbao-depositaires.txt` et de ce document.
- **Contrôle annuel** : chaque dépositaire prouve qu'il sait déchiffrer sa part (`age -d` vers `/dev/null`), sans la présenter au serveur.
