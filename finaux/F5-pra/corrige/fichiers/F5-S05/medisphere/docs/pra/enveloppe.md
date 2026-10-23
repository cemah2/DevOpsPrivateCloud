# Enveloppe de reprise

| | |
|---|---|
| Ticket | PLAT-3505 |
| Propriétaire | Sophie Laurent (RSSI) |
| Dernière vérification | <AAAA-MM-JJ> par <MOI> et Sophie Laurent (double contrôle) |
| Prochaine | <AAAA-MM-JJ> (semestrielle, `calendrier-tests.md`) |

> ⚠️ Ce document **décrit** l'enveloppe ; il ne contient **aucun secret**. Une valeur de secret trouvée ici est un incident de sécurité : on la révoque, on ne se contente pas de l'effacer de Git.

L'**enveloppe de reprise** est ce qu'il faut avoir en main pour reprendre à PAR2 **sans rien de PAR1** (`dependances.md`, colonne « pour s'en servir »). Elle existe en **deux exemplaires** physiques scellés (coffre du bureau de Claire, coffre bancaire de MédiSphère) et en un **coffre numérique** hors de l'infrastructure de MédiSphère (gestionnaire de mots de passe d'entreprise, coffre « PRA », accès de Claire, Sophie et Karim, MFA matérielle).

## 1. Contenu

| # | Élément | Forme | Où | Gardiens | Sert à | Vérification sans ouvrir |
|---|---|---|---|---|---|---|
| E1 | **Parts Shamir de `kms01`** (5 parts, seuil 3) | 5 plis scellés, une part chacun | chez chaque gardien (coffre personnel) | Claire, Sophie, Karim, <MOI>, Nadia | desceller `kms01` restauré (RB-355) | chaque gardien confirme par écrit : pli présent, scellé intact, numéro de scellé inchangé |
| E2 | **Clé de chiffrement des sauvegardes PBS** (+ version papier `paperkey`) | fichier chiffré + papier | coffre numérique ; papier dans les deux exemplaires | Sophie, Claire | restaurer une VM de PAR1 sur `hp01` (`kms01`, `adm01`, `ca01`) | empreinte de la clé comparée à celle notée ici : `<EMPREINTE-CLE-PBS>` |
| E3 | **Phrase Kopia de Velero** | texte | coffre numérique | Sophie, Karim | restaurer les sauvegardes Velero (Legacy-RDV, objets) à PAR2 | date de création notée dans le coffre |
| E4 | **Mots de passe d'Ansible Vault** « lab » et « critique » | texte | coffre numérique ; papier dans les deux exemplaires | Sophie, Karim | ouvrir `plateforme/ansible` (clé `age` de restauration du coffre, clé de l'autorité PAR2, identités S3 de PAR2) quand OpenBao n'existe plus | ouverture d'un fichier d'essai **depuis `adm02`**, à la vérification semestrielle |
| E5 | **Phrase de passe de la racine** MédiSphère et **phrase de l'archive** `pki-racine-*.tar.gpg` ; **archive** sur support chiffré | texte + clé USB chiffrée | Sophie (phrases) ; exemplaire bancaire (support) | Sophie, Claire | signer en urgence (autorité de PAR2 compromise ou expirée pendant un PRA) | `ceremonie-pki.sh verifier` sur une copie restaurée, à la cérémonie suivante |
| E6 | **Comptes de bris de glace** : `root@pam` de `hp01` (PVE et PBS) ; compte local `admin` des VMs de PAR2 (clé SSH privée et sa phrase) | papier + clé SSH sur support chiffré | les deux exemplaires | Claire, Karim | se connecter à PAR2 sans SSO ni certificat SSH (RB-240) | connexion d'essai trimestrielle, journalisée |
| E7 | **`admin.conf` de `k8s-par2`** | fichier chiffré | coffre numérique | Karim, <MOI> | administrer `k8s-par2` sans OIDC | `kubectl get nodes` depuis `adm02` à la vérification |
| E8 | **Clé privée WireGuard** du poste de secours pour `wg1` de `hp01` (+ configuration) | fichier | coffre numérique | <MOI>, Karim | atteindre PAR2 sans le VPN de PAR1 | connexion d'essai trimestrielle |
| E9 | **Jeton de seal `kms-autodescellement`** (périodique 168 h) | texte | dans E4 (Ansible Vault « critique ») | — | descellement de `bao-par2` par `kms01` restauré | RB-355 §5 : valable ≈ 7 jours après la sauvegarde restaurée |
| E10 | **Jeton OpenTofu de PAR2** (`wb-tofu@pve!par2`) et identité `tofu-par2` de `s3-02` | texte | dans E4 | — | `envs/par2` depuis `adm02` | `tofu plan` depuis `adm02` à la vérification |
| E11 | **Annuaire de crise** (équipe, direction, 40 cabinets de Legacy-RDV, 20 plus gros cabinets de MédiAgenda) | papier | les deux exemplaires + chaque membre de la cellule | Nadia | communication sans la messagerie de MédiSphère (`cellule-de-crise.md`) | mise à jour trimestrielle par Nadia |
| E12 | **Ce document**, RB-350, RB-355 et `cellule-de-crise.md` imprimés | papier | les deux exemplaires | Nadia | reprendre sans aucun accès réseau au départ | version imprimée = version de `main` (date au pied de page) |

## 2. Règles

- **Séparation** : aucune personne ne détient seule de quoi desceller `kms01` (3 parts sur 5) ni de quoi restaurer **et** déchiffrer (E1, E2 et E4 sont répartis).
- **Rotation** : toute rotation d'un élément (clé PBS, mot de passe d'Ansible Vault, autorité PAR2, départ d'un gardien) met à jour l'enveloppe **le jour même** et ajoute une ligne au journal ci-dessous.
- **Départ d'un gardien** : sa part est **invalidée** par un nouveau partage (*rekey* de `kms01` en cérémonie, M25), pas seulement récupérée.
- **Ouverture** : sur décision de déclenchement du PRA (Claire), pour une répétition planifiée ou une vérification ; chaque ouverture est consignée (date, qui, pourquoi) et suivie d'un rescellement.

## 3. S'il manque un élément le jour J

| Manque | Conséquence | Repli |
|---|---|---|
| < 3 parts Shamir | `kms01` restauré reste scellé, `bao-par2` ne se descelle pas | les Secrets **déjà présents** à PAR2 (ESO en veille) font tourner les applications en mode dégradé tant qu'ils sont valides ; plus d'identifiants dynamiques de base ; nouveau coffre à reconstruire (M25) |
| Clé PBS (E2) | aucune VM de PAR1 restaurable | idem ; reconstruction de `kms01` impossible |
| Mot de passe Ansible Vault « critique » (E4) | ni clé `age` de restauration du coffre, ni identités S3 de PAR2 | l'autorité PAR2 est déjà dans `k8s-par2` (Secret) ; restauration du coffre impossible |
| `admin.conf` (E7) | pas d'administration de `k8s-par2` par l'API | accès `admin` au nœud (E6) et `/etc/kubernetes/admin.conf` du nœud |

## 4. Journal

| Date | Événement | Qui |
|---|---|---|
| <AAAA-MM-JJ> | constitution de l'enveloppe (F5-S05) | <MOI>, Sophie Laurent |
| <AAAA-MM-JJ> | ouverture pour la répétition de restauration du coffre (RB-355), rescellement | <MOI>, Karim Benali, Sophie Laurent |
