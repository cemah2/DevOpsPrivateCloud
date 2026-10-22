# Accès SSH aux machines du socle

*Version M24-E20 (SEC-2520). Responsable : équipe Plateforme. Relu par : Sophie Laurent.*

## Qui entre, comment

| Qui | Compte | Preuve présentée | Délivrée par | Durée | Où |
|---|---|---|---|---|---|
| Une personne de l'annuaire | **son** compte (`lucas.martin`…), résolu par SSSD | certificat SSH d'utilisateur, principal = identifiant de l'annuaire | step-ca, provisioner OIDC `keycloak`, après SSO (et OTP pour `plateforme-admins`, `securite`) : `step ssh login <identifiant>@medisphere.internal --provisioner keycloak` | 16 h | machines inscrites dans l'annuaire, si une règle HBAC le permet (`hbac-plateforme`, `hbac-support`) |
| Automatisation (Ansible, pipelines) | `admin` (local) | clé `ansible-ci` (restreinte à `runner01`) ou clé d'`adm01` | — | permanente | toutes |
| Astreinte, bris de glace | `admin` (local) | certificat `admin`/`astreinte` signé par le provisioner `admin` (`ms-ssh-cert`, mot de passe au Vault `critique`) | step-ca, provisioner JWK `admin` | 16 h | toutes, y compris la bordure (`gw01`, `gw02`) |

## Décision sur `ms-ssh-cert` (M06-E20)

**Gardé, réservé au bris de glace.** Il ne dépend ni de Keycloak ni de l'annuaire : si l'un des deux tombe, c'est la seule façon d'entrer sous `admin` avec un certificat court. En contrepartie : son mot de passe quitte le gestionnaire personnel pour le Vault `critique` (deux personnes), chaque certificat qu'il signe est journalisé par step-ca et alerte (M24-E26/E28), et il n'est plus utilisé pour le travail courant (RB-240). Le travail courant se fait sous son nom (traçabilité HDS).

## Sécurité du dispositif

- Les principaux d'un certificat de personne sont fixés par le gabarit du provisioner (`preferred_username`) : personne ne peut demander `admin` ou `root` (aucun administrateur déclaré dans le provisioner).
- sshd accepte un certificat pour un compte de l'annuaire par `AuthorizedPrincipalsCommand` (`/usr/local/sbin/principaux-annuaire`), jamais pour un compte local ; les comptes locaux ne dépendent que de `/etc/ssh/principaux/<compte>`.
- HBAC décide après le certificat : un certificat valide ne suffit pas (`julien.petit` est refusé partout).
- Un certificat ne se révoque pas chez nous (sshd ne consulte pas de liste de révocation) : il expire en 16 h au plus. Un départ coupe le compte immédiatement (annuaire, SSSD : RB-242), ce qui rend le certificat inutile.
- Bordure (`gw01`, `gw02`) : hors annuaire, comptes locaux seulement.
