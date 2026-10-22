# Procédure : jeton racine d'OpenBao

> `docs/securite/secrets/procedure-jeton-racine.md` — M25-E28 (SEC-2628). Propriétaire : Sophie Laurent (RSSI). Dernière répétition : `<DATE>` (participants : `<NOMS>`).

## Principe

Il n'existe **aucun** jeton racine en temps normal (le jeton initial a été révoqué au M25-E08). L'administration courante passe par `plateforme-admin` (OIDC + OTP) et par OpenTofu. Un jeton racine se **régénère** pour une action précise qu'aucune politique ne permet, puis se **révoque** dans la minute.

Cas prévus : politique `plateforme-admin` cassée ou supprimée (plus personne ne peut la réparer) ; méthode OIDC inutilisable (Keycloak perdu) ; administration de `kms01` (pas de méthode d'authentification humaine) ; opérations sur la barrière (`sys/rotate`, E44).

## Qui

- **Lancer** la génération : un membre de `plateforme-admins` (politique : `sys/generate-root-token/attempt` et `…/update`, sans `sudo`). Pour `kms01` : le jeton `vault_kms01_jeton_generation` (Vault `critique`, politique `generation-racine`), seul moyen d'y lancer la procédure.
- **Fournir les parts** : trois dépositaires distincts, chacun avec **sa** clé de récupération (grappe : `secrets/openbao-init.yml` ; `kms01` : `secrets/kms01-init.yml`) et **son** identité `age`. L'officiant ne voit aucune part.
- **Témoin** : Sophie Laurent ou, en son absence, Claire Morel (ticket `SEC-` ouvert avant, refermé après).

## Comment (depuis `adm01`, clone de `plateforme/ansible`)

1. Ouvrir le ticket (motif, action prévue, participants). `bao login -method=oidc` (officiant).
2. `BAO_ADDR=https://openbao.par1.medisphere.internal:8200 outils/openbao-parts-p3.sh racine-debut` → nonce affiché, **OTP** rangé dans `$XDG_RUNTIME_DIR/openbao-otp` (600, mémoire). L'OTP ne quitte pas le poste de l'officiant.
3. Chaque dépositaire (sa session, son identité) : `outils/openbao-parts-p3.sh racine-part <N> <IDENTITÉ-AGE> <NONCE>` → « part acceptée 1/3 », « 2/3 », puis « terminé : jeton encodé = … ». L'encodé seul ne vaut rien sans l'OTP.
4. Officiant : `outils/openbao-parts-p3.sh racine-fin <ENCODÉ>` → le jeton est décodé localement et chargé par `bao login` (jamais affiché).
5. **L'action prévue, et elle seule**, puis `bao token revoke -self`. Puis `bao login -method=oidc` pour revenir à l'identité nominative.
6. Annulation à tout moment : `outils/openbao-parts-p3.sh racine-annuler`.

## Preuves (à joindre au ticket)

Requêtes LogQL sur le locataire `audit` (Grafana, Explore) :
- lancement et parts : `{service="openbao"} | json chemin="request.path", qui="auth.display_name" | chemin=~"sys/generate-root-token/.*"` ;
- usage du jeton : `{service="openbao"} |= `"policies":["root"]`` (alerte `OpenBaoJetonRacineUtilise` attendue : elle est le témoin, on ne la fait pas taire) ;
- révocation : `… | chemin="auth/token/revoke-self"`.
L'alerte `OpenBaoJetonRacineUtilise` (M25-E21) a sonné pendant la séance et s'est éteinte après la révocation.

## Répétition

Une fois par semestre, avec trois dépositaires différents de la fois précédente : l'action est `bao token lookup` (sans effet), la preuve est le ticket.
