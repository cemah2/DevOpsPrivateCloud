# ADR-0372 — Identité : agents fédérés, patients locaux, DPI en compte de service

| | |
|---|---|
| Statut | **Accepté** (<DATE>) |
| Décideurs | Karim Benali, Sophie Laurent (RSSI), Thomas Renaud (DPO), Julien Petit |
| Ticket | PLAT-3704 (F7-S04) |
| Exigences | ESC-04, ESC-05, EF-04, EF-05, EF-09 ; réponses R-16, R-07 |
| Complète | ADR-0240 (architecture d'identité, M24), ADR-0241 (haute disponibilité de Keycloak, M24) |

## Contexte

Trois populations, trois risques :

| Population | Volume | Exigence | Risque principal |
|---|---|---|---|
| Agents du GHSV | ≈ 9 200 (dont quelques centaines d'utilisateurs actifs de l'interface) | ESC-04 : **exclusivement** l'IdP OIDC du GHSV, MFA, aucun compte local, droits par groupes, désactivation ≤ 15 min | compte d'agent créé chez nous à côté de la fédération ; droits trop larges ; agent parti encore connecté |
| Patients | ≈ 400 000 actifs, 540 000 comptes à 5 ans | EF-09, ESC-05 : comptes locaux, MFA proposée, protection contre la force brute et le bourrage d'identifiants | attaques massives et automatisées sur la page de connexion ; données de santé derrière |
| DPI | 1 client machine | EF-05 : OAuth 2.0 *client credentials*, portées `rdv:lecture` et `rdv:ecriture` | secret du client volé ; portées trop larges |

La plateforme a un Keycloak 26.8 (M24) avec le royaume `medisphere` (personnels de MédiSphère, fédérés depuis FreeIPA). Dans le lab, l'IdP du GHSV est **simulé** par le royaume `ghsv-idp` sur `idp01`, déclaré comme fournisseur d'identité OIDC du royaume `medisphere` (F7-S08).

## Décision

1. **Agents** : fournisseur d'identité OIDC `ghsv` (courtier d'identité) dans le royaume **`medisphere`**, pointant l'émetteur du GHSV (`https://idp.ghsv.example`, simulé dans le lab par `ghsv-idp`).
   - Premier passage : création automatique d'un utilisateur **lié** (pas de mot de passe, pas d'OTP local, pas de réinitialisation possible), avec un attribut `client=ghsv` ; synchronisation des groupes du GHSV à **chaque** connexion (mappeur de revendication → groupes préfixés `ghsv-…`).
   - Le fournisseur `ghsv` est le **seul** chemin : les clients de l'interface des agents du GHSV n'acceptent que lui (redirection directe vers le fournisseur, sans formulaire de connexion local) ; contrôle mensuel : aucun utilisateur `client=ghsv` n'a d'identifiant local (ESC-04).
   - Désactivation ≤ 15 min (NF-14) : jetons d'accès de 5 min, sessions limitées à la durée de la session de l'IdP du GHSV, déconnexion par canal arrière si le GHSV la propose.
   - Autorisation : groupes `ghsv-<service>` → périmètre d'agendas dans l'application (EF-04, développement) ; la route « agents » de l'API est protégée (OAuth2 Proxy ou validation du jeton à la Gateway) et n'accepte que des jetons dont l'utilisateur porte `client=ghsv`.
   - MFA : responsabilité du GHSV (R-16), écrite dans le contrat ; nous ne proposons aucun autre moyen d'authentification.
2. **Patients** : royaume **dédié `ghsv-patients`** (comptes locaux, inscription libre avec vérification du courriel, OTP proposé, détection de force brute, politique de mots de passe conforme aux recommandations de la CNIL, thème aux couleurs du GHSV). Séparé des personnels : une fuite ou une mauvaise configuration de ce royaume ne touche ni nos administrateurs ni les agents. Reprise des 140 000 comptes de l'outil actuel sans mot de passe (EF-08) : comptes créés avec action « définir le mot de passe » à la première connexion.
3. **DPI** : client confidentiel `ghsv-dpi` dans le royaume `medisphere`, flux *client credentials* seulement, portées `rdv:lecture` et `rdv:ecriture`, authentification du client par **clé privée signée** (JWT, `private_key_jwt`) plutôt que par secret partagé si le DPI le permet, liste d'adresses sources sur les répartiteurs, jeton de 5 min.

## Options étudiées

| Option | Pour | Contre | Décision |
|---|---|---|---|
| Royaume dédié `ghsv` pour les agents (courtier vers l'IdP du GHSV) | isolation maximale des agents | un émetteur de plus pour l'API et les outils ; dans le lab, contraire à la structure figée (courtier dans `medisphere`) | **écartée en v1** ; **révision au deuxième client** (un royaume par client deviendra la règle) |
| Fédération directe de l'application avec l'IdP du GHSV (sans Keycloak) | une brique de moins | chaque application gère l'IdP, pas de groupes normalisés, pas d'attribut `client`, désactivation et journaux dispersés | **écartée** |
| Comptes locaux d'agents synchronisés depuis l'annuaire du GHSV (LDAP) | indépendance vis-à-vis de l'IdP du GHSV | **interdit** par ESC-04 ; ouvrirait un flux d'annuaire vers nous | **écartée** |
| Patients dans le royaume `medisphere` | un seul royaume | 540 000 comptes externes à côté des administrateurs de la plateforme, règles de sécurité contradictoires (inscription libre contre OTP obligatoire) | **écartée** |
| Patients dans un IdP du GHSV | le GHSV maîtrise | hors périmètre (§2.2 du CCTP) ; EF-09 demande des comptes locaux | **écartée** |

## Conséquences

- Keycloak devient critique pour la prise de rendez-vous (patients, agents, DPI) : grappe de 3 nœuds à PAR1 et instance de repli à PAR2 (architecture, §3-§4), au lieu d'`idp01` seul.
- Dimensionnement : le hachage des mots de passe des patients coûte du processeur à chaque connexion : à mesurer (F7-S10), avec limites de débit sur la connexion.
- L'indisponibilité de l'IdP du GHSV empêche les agents de se connecter : exclue de NF-01, supervisée.
- Dans le lab : `ghsv-idp` simulé, courtier dans `medisphere`, royaume `ghsv-patients` **non construit** (hors démonstration, écrit comme écart).

## Révision

Au deuxième client (royaume par client) ; si le GHSV ne fournit pas de déconnexion par canal arrière et que NF-14 n'est pas tenue ; après le test d'intrusion.
