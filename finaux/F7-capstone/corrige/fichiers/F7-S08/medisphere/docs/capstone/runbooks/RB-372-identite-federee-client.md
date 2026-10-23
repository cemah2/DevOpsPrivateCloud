# RB-372 — Identité fédérée d'un client

| | |
|---|---|
| Portée | fournisseur d'identité d'un client déclaré dans le royaume `medisphere` (aujourd'hui : `ghsv-idp`), clients Keycloak du client (`ghsv-agents`, `ghsv-api`, `ghsv-dpi`), mandataires OAuth2 Proxy de ses espaces |
| Déclencheurs | raccordement d'un client, rotation d'un secret, agent qui ne peut pas se connecter, IdP du client en panne, départ d'un client |
| Rôles | Plateforme (code `plateforme/identite`, MR relue par Sophie Laurent), support (diagnostic de niveau 2) |
| Références | `docs/capstone/identite-federee.md`, M24 (RB-24x), ESC-04 |
| Créé | F7-S08 (PLAT-3708) |

## 1. Raccorder l'IdP d'un client

1. Obtenir du client : émetteur, client confidentiel (identifiant ; secret par canal séparé), nom de la revendication des groupes et du groupe convenu, un compte de test.
2. Ranger le secret dans OpenBao (`kv/plateforme/keycloak/<client>-idp-courtier`) sans l'afficher ; `outils/charger-acces.sh` l'expose à OpenTofu en variable éphémère.
3. Ouvrir le flux `idp01` → émetteur du client (HTTPS) dans la matrice et la bordure (MR `plateforme/ansible`).
4. MR `plateforme/identite` : fournisseur, mappeurs, groupe des agents, flux `navigateur-<client>`, clients ; plan relu (Sophie Laurent) ; `apply` par le pipeline.
5. Contrôles : `lab/bin/check F7 8`, et le constat de cloisonnement (identite-federee.md §3) avec le compte de test.

## 2. Un agent ne peut pas se connecter

Dans l'ordre :
1. Le symptôme exact : page de l'IdP du client (son problème), page d'erreur de Keycloak (le courtier), 403 d'OAuth2 Proxy (groupe), boucle de redirections (cookie).
2. Événements du royaume `medisphere` pour `ghsv.<identifiant>` (console : Events, ou Loki, journaux d'`idp01`) : `IDENTITY_PROVIDER_LOGIN_ERROR` (échange de jeton : secret, horloge, réseau), `LOGIN_ERROR` + `access_denied` (flux), aucun événement (n'arrive pas jusqu'à nous).
3. Le compte fédéré : groupes (`ghsv-agents` présent ?), rôle `client-externe`, lien vers le fournisseur.
4. La revendication reçue : jeton de l'IdP du client décodé (compte de test) : `groups` contient-il le groupe convenu, sous la **même** forme (nom court, pas de chemin) ?
5. OAuth2 Proxy : journaux du mandataire (`allowed_groups`, cookie expiré, erreur de vérification).
6. Comparer avec le code (`tofu plan` sur `plateforme/identite`) : un écart = une modification hors code, à défaire par `apply`.

## 3. L'IdP du client est indisponible

Les agents ne peuvent plus se connecter (aucun autre moyen, par contrat). Les sessions en cours tiennent au plus 15 min. Ouvrir un incident chez le client (ticket commun) ; message aux secrétariats par le centre de services du client. **Ne pas** créer de comptes locaux d'urgence (ESC-04). Le DPI n'est pas touché (jetons du royaume `medisphere`).

## 4. Rotation des secrets

| Secret | Fréquence | Procédure |
|---|---|---|
| Client du courtier chez le client | annuelle, ou à la demande du client | nouveau secret reçu → OpenBao → incrémenter `secret_courtier_ghsv_version` → MR → `apply` ; vérifier une connexion |
| `ghsv-agents`, `ghsv-api` (OAuth2 Proxy) | annuelle (RB-244 du M24) | nouveau secret dans Keycloak (OpenTofu) → `kv/ghsv/<env>/oauth2-proxy-*` → ESO → redémarrage des mandataires (Reloader) |
| `ghsv-dpi` (DPI) | annuelle, coordonnée avec le client | deux secrets successifs impossibles sur un même client Keycloak : prévoir une fenêtre courte, ou un second client `ghsv-dpi-2` le temps de la bascule |
| Cookies d'OAuth2 Proxy | annuelle | nouveau `cookie-secret` : toutes les sessions tombent (les agents repassent par l'IdP, sans effet visible) |

## 5. Revue mensuelle des comptes fédérés

Comptes `ghsv.*` sans connexion depuis 90 jours : supprimés chez nous (un agent qui revient est recréé à sa connexion suivante, avec les seuls droits que dit l'IdP du GHSV ce jour-là) ; liste jointe au rapport mensuel (section sécurité). Aucun compte `ghsv.*` hors du groupe `ghsv-agents` et sans le rôle `client-externe` : sinon, incident de sécurité.

## 6. Départ d'un client

MR qui retire le fournisseur, ses mappeurs, le groupe, le flux et les clients du client ; suppression des comptes fédérés `ghsv.*` (API d'administration, journalisée) ; secrets retirés d'OpenBao ; flux réseau retiré. Inscrit au procès-verbal de destruction (RB-371 §5).
