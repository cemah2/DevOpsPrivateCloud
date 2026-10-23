# RB-250 — Un secret a fuité

> Propriétaire : équipe Plateforme · Validé par : Sophie Laurent (RSSI), Nadia Roussel (astreinte) · Ticket : INC-5223 (M25-E23)
> Dernier exercice : `<DATE>` (M25-E34) · Prochaine revue : après chaque usage réel, au plus tard dans 6 mois

**Déclencheurs** : un secret vu là où il ne devait pas être (ticket, canal de discussion, journal de CI, dépôt Git, capture d'écran, poste perdu), une alerte `OpenBaoJetonRacineUtilise`, un signalement de Gitleaks (M19), un départ conflictuel, un doute.
**Règle d'or** : un secret qui **a pu** être lu est un secret **fuité**. On ne cherche pas à prouver qu'il a été exploité avant d'agir : on contient, on tourne, puis on enquête.

## 0. Rôles

| Rôle | Qui | Fait |
|---|---|---|
| Responsable de l'incident | personne d'astreinte Plateforme | mène le runbook, tient la chronologie, décide des gestes |
| RSSI | Sophie Laurent (suppléant : Claire Morel) | qualifie (données de santé ? données personnelles ?), décide de la communication externe |
| Propriétaire du secret | équipe désignée dans `inventaire-secrets.md` | tourne le secret côté application, confirme le retour à la normale |
| Scribe | un second membre de l'équipe | horodate tout dans le ticket INC (UTC), garde les preuves |

Ouvrir un ticket **INC** (gravité selon § 2) et un fil dédié ; rien dans un canal public.

## 1. Les dix premières minutes : contenir

1. **Retirer la fuite de la vue** si c'est possible sans détruire la preuve : masquer le message, rendre le ticket privé, supprimer le journal de job (GitLab : *Erase job log*) **après** en avoir exporté une copie dans le dossier de preuves (§ 6).
2. **Identifier le secret exactement** : quel chemin dans OpenBao (`inventaire-secrets.md`, colonne « où »), quel type (§ 3), quelle portée (qui peut l'utiliser, depuis où).
3. **Couper l'usage du secret fuité** selon son type (§ 3, colonne « contenir ») — avant de le remplacer si l'attaquant peut s'en servir maintenant ; après, si le couper arrête la production et qu'aucun usage malveillant n'est constaté (décision du responsable, notée).
4. Si **plusieurs** secrets, ou un jeton à large portée (politique `plateforme-admin`, jeton racine), ou un doute sur le coffre lui-même : prévenir la RSSI tout de suite ; en dernier recours, **sceller** le coffre (`bao operator seal`, droit `sys/seal` de `plateforme-admin`). ⚠️ Sceller arrête **tout** ce qui lit le coffre (ESO, CI, Ansible, identifiants dynamiques) : décision de la RSSI ou de Claire Morel, jamais seul.

## 2. Qualifier (gravité)

| Gravité | Exemples | Délai de rotation |
|---|---|---|
| **G1** | jeton racine, jeton `plateforme-admin`, clé de transit exportée, parts Shamir ou clés de récupération, clé privée d'une autorité, accès à des données de santé | immédiat, astreinte réveillée |
| **G2** | secret de production d'une application, identifiant de base de prod, jeton de CI de déploiement, `secret_id` d'AppRole, secret d'un client OIDC | dans l'heure |
| **G3** | secret de recette, de dev, d'un outil interne sans donnée sensible | dans la journée ouvrée |

Données de santé ou personnelles **possiblement consultées** grâce au secret : la RSSI évalue s'il s'agit d'une **violation de données personnelles** (notification à la CNIL sous 72 h si un risque existe pour les personnes, RGPD art. 33 ; information de l'hébergeur et des clients selon les contrats HDS). Le runbook ne décide pas à sa place : il lui donne les faits (§ 5).

## 3. Contenir et tourner, par type de secret

| Type | Contenir (couper l'usage du secret fuité) | Tourner (nouvelle valeur, sans coupure) |
|---|---|---|
| **Jeton OpenBao** (vu en clair) | `bao token revoke -accessor <ACCESSOR>` (l'accessor est en clair dans l'audit, ou `bao token lookup -accessor`) ; révoque aussi les jetons **enfants** et leurs baux | rien à tourner : l'identité se reconnecte ; chercher **comment** le jeton est sorti (§ 5) |
| **Jeton racine** | `bao token revoke -accessor …` ; vérifier qu'il n'en existe pas d'autre (`bao list auth/token/accessors` + `lookup-accessor`, politique `root`) | aucun jeton racine permanent (E08, E28) ; cérémonie `generate-root` seulement si nécessaire |
| **`secret_id` d'AppRole** | `bao write auth/approle/role/<rôle>/secret-id-accessor/destroy secret_id_accessor=<…>` (ou tous : `bao list auth/approle/role/<rôle>/secret-id`) ; révoquer les jetons émis (audit : `auth.metadata.role_name`) | nouveau `secret_id` remis par enveloppement de réponse (E28) |
| **Secret KV** (mot de passe, clé d'API) | si le système cible le permet : désactiver l'ancienne valeur (autre compte, autre clé) | nouvelle valeur dans le système cible **puis** `bao kv put` (nouvelle version) ; ESO rafraîchit (E15) ; redémarrage contrôlé ; vérifier que l'ancienne valeur est refusée par la cible ; `bao kv metadata` montre la version |
| **Identifiants dynamiques** (`db-mediagenda/creds/…`) | `bao lease revoke <LEASE_ID>` (un bail) ou `bao lease revoke -prefix db-mediagenda/creds/<rôle>` (tous : `sudo`) ; le rôle PostgreSQL est supprimé par OpenBao | rien : l'application en reçoit de nouveaux (générateur ESO, E14) ; si c'est le **compte racine** de la connexion (`openbao`) qui a fui : `bao write -f db-mediagenda/rotate-root/<connexion>` |
| **Certificat de service** (`pki-services`) | `bao write pki-services/revoke serial_number=<…>` ; CRL republiée | cert-manager en réémet un (E16) |
| **Clé de transit** (exportée, ou jeton qui pouvait déchiffrer) | révoquer le jeton ; si la clé elle-même est sortie : nouvelle version (`rotate`) | `rewrap` de toutes les données ; puis `min_decryption_version` relevé (gel) et, après vérification, `trim` (destruction) ; données chiffrées par l'ancienne version à considérer comme exposées |
| **Clé de signature** (`cosign-medisphere`) | révoquer le jeton ; retirer la confiance dans la clé publique compromise (Kyverno, porte de déploiement) | procédure de changement de clé (`cle-signature.md` § 3) ; re-signature de ce qui est déployé ; inventaire de ce qui a été signé pendant la fenêtre (audit `transit/sign/…`) |
| **Jeton GitLab, robot Harbor, secret de client Keycloak** | révoquer dans le système émetteur (jetons et variables GitLab : RB-198, `docs/livraison/ci/runbooks/`) | nouvelle valeur dans le système, puis dans OpenBao (`kv/plateforme/…`), ESO propage (M25-E33 automatise) |
| **Clé `age`** (instantanés, SOPS) | retirer le destinataire | `sops updatekeys` + `sops rotate` ; instantanés : nouvelle clé pour les prochains, les anciens restent lisibles par l'ancienne clé (les détruire ou les rechiffrer) |

Après chaque geste : vérifier l'effet (le jeton est refusé : `bao token lookup -accessor` → erreur ; la base refuse l'ancien mot de passe ; l'ancien certificat est dans la CRL…) et noter l'heure.

## 4. Vérifier qu'on n'a rien cassé

- Applications : santé dans Argo CD, sondes blackbox de `mon01`, tableaux de bord MédiAgenda (taux d'erreur, M21) ;
- ESO : `kubectl get externalsecrets -A` (toutes `SecretSynced`) ;
- CI : un pipeline témoin de chaque projet touché ;
- Coffre : `bao status`, alertes `OpenBao*` muettes.

## 5. Enquêter : qui a lu, qui a utilisé

Requêtes dans `docs/securite/secrets/audit-openbao.md` (locataire Loki `audit`, conservation 1 an). Questions dans l'ordre :

1. **Depuis quand** le secret était-il exposé ? (date du message, du commit, du journal de job) → borne de la fenêtre.
2. **Qui a lu le secret dans le coffre** pendant la fenêtre ? Requête « qui a lu `<chemin>` » ; toute identité inattendue est une piste.
3. **La valeur fuitée a-t-elle été utilisée ?** Dans le système cible (journaux de PostgreSQL, de GitLab, de Harbor, de Keycloak) ; pour un jeton OpenBao : requête par **accessor** (`|= "<ACCESSOR>"`), depuis quelles adresses, sur quels chemins.
4. **Retrouver où une valeur a circulé** : HMAC de la valeur (`sys/audit-hash/fichier`, § 3 de `audit-openbao.md`) puis recherche dans Loki.
5. **Comment** le secret est-il sorti ? (`set -x` dans un job, `env` dans un ticket, fichier `.env` copié, capture d'écran) → c'est la cause racine du post-mortem.

## 6. Preuves

Dossier `preuves/INC-<NUMÉRO>/` dans le compartiment `s3-01` **`incidents`** (accès RSSI et responsable seulement), jamais dans Git ni dans le ticket :
- copie de l'endroit de la fuite (le secret **caviardé** : seuls les 4 derniers caractères) ;
- exports des requêtes LogQL (JSON de l'API, avec la requête et la plage) ;
- sorties horodatées des gestes de révocation et de rotation ;
- chronologie (UTC) : détection, contention, rotation, vérification, clôture.
Empreinte SHA-256 de chaque fichier notée dans le ticket : on prouve qu'ils n'ont pas changé.

## 7. Communiquer

| Quand | Qui | À qui | Quoi |
|---|---|---|---|
| Dès la qualification | responsable | RSSI, Claire Morel | gravité, secret, fenêtre, gestes en cours |
| G1 ou données de santé | RSSI | direction ; CNIL (72 h) et clients si violation avérée | selon la procédure de gestion des violations |
| Fin de rotation | responsable | équipes propriétaires | ce qui a changé, ce qu'elles doivent vérifier |
| Clôture | responsable | équipe Plateforme, RSSI | post-mortem (modèle `docs/socle/post-mortems/`), actions |

Ne jamais : citer la valeur, même partielle au-delà de 4 caractères ; accuser une personne (post-mortem sans reproche).

## 8. Clôturer

- [ ] Toutes les valeurs exposées sont tournées et l'ancienne est **refusée** par le système cible.
- [ ] Les jetons et baux concernés sont révoqués (vérifié).
- [ ] L'enquête (§ 5) est écrite, avec ses requêtes et ses résultats.
- [ ] `inventaire-secrets.md` est à jour (date de rotation).
- [ ] Le post-mortem est planifié sous 5 jours ouvrés ; les actions (prévention de la cause racine) ont un propriétaire et une date.
- [ ] Les gestes « exceptionnels » (préfixes révoqués, coffre scellé, jeton racine régénéré) sont justifiés dans le ticket (ils déclenchent des alertes d'audit : on les relie à l'incident).

## Annexe — gestes de référence

```
# Révoquer un jeton vu dans l'audit (et ses enfants)
admin@adm01:~$ bao token revoke -accessor <ACCESSOR>
# Révoquer tous les identifiants dynamiques d'un rôle (sudo, plateforme-admin)
admin@adm01:~$ bao lease revoke -prefix db-mediagenda/creds/<RÔLE>
# Nouvelle version d'un secret statique, par l'identité qui a le droit d'écrire ce chemin
# (inventaire-secrets.md, colonne « propriétaire ») ; valeur saisie sans écho, jamais en argument
admin@adm01:~$ read -rs v; printf '%s' "$v" | jq -Rs '{data: {mot_de_passe: .}}' | bao write kv/data/<CHEMIN> - ; unset v
# Détruire un secret_id d'AppRole par son accessor
admin@adm01:~$ bao write auth/approle/role/medictl/secret-id-accessor/destroy secret_id_accessor=<ACCESSOR-SECRET-ID>
```
