# RB-244 — Rotation des secrets des clients, des clés de signature et des mots de passe de service

| | |
|---|---|
| Ticket | SEC-2529 (M24-E29) |
| Calendrier | clés de signature : **annuelle** (octobre) ; secrets des clients : annuelle **et** après toute fuite ; mot de passe de `svc-keycloak` : annuelle |
| Dernière rotation | clé `rsa-2026-10` le <AAAA-MM-JJ> ; secret de `grafana` le <AAAA-MM-JJ> (fenêtre mesurée : <N> s) |
| Prérequis | sauvegarde de la base de moins d'une heure (`identite-sauvegarde.service`, RB-243) ; session `<MOI>-admin` ouverte ; `kc-secours` essayé (RB-240) |

## 1. Inventaire des secrets concernés

| Secret | Où il vit | Qui le lit | Comment il change |
|---|---|---|---|
| Secret d'un client confidentiel (`gitlab`, `grafana`, `argocd`, `harbor`, `proxmox`, `pbs`, `netbox`, `oauth2-proxy`) | Vault `critique` `secrets/identite.yml` (`keycloak_secrets_clients.<client>`) ; côté Keycloak : généré puis rangé par `outils/ranger-secret-client.sh` (E11 à E18), ou **imposé** par `client_secret_wo` (à partir d'E29, client par client) ; côté service (Secret Kubernetes par `secrets-k8s.sh`, ou configuration Ansible/`gitlab.rb`) | le service, à l'échange du code | §2 |
| Clés de signature du royaume (RS256) | base de Keycloak (`component_config`), publiques dans le JWKS | tous les services (vérification des jetons) | §3 |
| Mot de passe de `svc-keycloak` (fédération) | Vault `critique` `annuaire/vault-critique.yml` → annuaire (job) et Keycloak (`bind_credential_wo`) | Keycloak, à chaque liaison | §4 |
| Secret de `wb-checks`, de `svc-tofu-keycloak` | `~/.config/workbook/*.env`, variables protégées de CI | checks, pipeline | régénération dans la console (`Credentials` → *Regenerate*), puis fichier/variable ; pas de fenêtre visible par les utilisateurs |

## 2. Secret d'un client confidentiel

**Keycloak 26.7 (fonction de rotation en préversion désactivée) : fenêtre courte.** Mesurée pour `grafana` : <N> s pendant lesquelles les **nouvelles** connexions échouent ; les sessions déjà ouvertes ne sont pas touchées (Grafana garde sa propre session).

1. Nouveau secret au Vault, sans l'afficher :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-vault edit secrets/identite.yml   # keycloak_secrets_clients.grafana: <openssl rand -hex 32, collé>
   ```
2. `plateforme/identite` : `versions_secrets_clients.grafana` + 1 (MR) ; `. outils/charger-acces.sh` ; `tofu -chdir=tofu plan` → une seule modification attendue : `client_secret_wo_version` du client (le secret lui-même n'apparaît jamais).
3. Enchaîner en moins d'une minute, **service d'abord prêt, Keycloak ensuite** :
   - `plateforme/k8s/outils/secrets-k8s.sh identite` (composant « identite » d'E12 : le Secret `grafana-oidc` change ; le pod lit encore l'ancien) ;
   - `tofu apply` du plan (Keycloak n'accepte plus que le nouveau : début de la fenêtre) ;
   - `kubectl -n supervision rollout restart deployment kps-grafana` avec ton identité OIDC (`plateforme-admins`, jamais `admin.conf` pour une opération prévue), puis `rollout status` (fin de la fenêtre).
4. Preuves : connexion OIDC à Grafana ; introspection avec l'**ancien** secret → `401` (`invalid_client`/`unauthorized_client`), avec le nouveau → `200`.

**Keycloak ≥ 26.8 (rotation des secrets active par défaut) : sans fenêtre.** Politique de clients (*Client policies* → profil avec l'exécuteur `secret-rotation` : durée de vie du secret, durée de validité du secret **précédent**) ; une rotation garde l'ancien secret valable le temps du recouvrement : changer le Secret du service, redémarrer, puis laisser l'ancien expirer. À essayer après E33 ; tant que les secrets sont imposés par OpenTofu (`client_secret_wo`), la rotation reste pilotée par le code.

## 3. Clés de signature (annuelle)

1. Ajouter la clé de l'année dans `tofu/cles.tf` (`rsa-<AAAA-MM>`, RS256, 4096 bits, priorité supérieure à la précédente, active) ; MR, apply. Contrôles : le JWKS publie **deux** clés RS256 ; un nouveau jeton porte le nouveau `kid` ; un jeton d'avant est toujours accepté (introspection active, `kubectl` toujours bon).
2. Passer l'ancienne en **passive** (`active = false`) dans la même MR ou juste après.
3. **Attendre** la plus longue durée de vie d'un jeton signé par l'ancienne : jeton d'accès 5 min, ID token 5 min, jeton de rafraîchissement ≤ session SSO maximale (10 h ; plafonné par l'inactivité de session en 26.8). On attend **24 h** (marge, et les jetons de la console de compte).
4. Désactiver l'ancienne (`enabled = false`) ; MR, apply. Contrôles : JWKS à **une** clé RS256 ; connexion à Grafana, Argo CD (navigateur et CLI), `kubectl` après `kubectl oidc-login clean`, `step ssh login`.
5. L'année suivante : supprimer le bloc de la clé désactivée (la clé est détruite) en ajoutant la nouvelle.

Caches de clés des services : kube-apiserver (authentification structurée) relit le JWKS lorsqu'il rencontre un `kid` inconnu (et périodiquement) ; Argo CD, Grafana, OAuth2 Proxy vérifient l'ID token **à la connexion** avec un JWKS relu au besoin. L'ordre « ajouter, attendre, retirer » rend ces caches sans effet.

Retour arrière : réactiver l'ancienne (`enabled = true`, `active = true`) ; une clé désactivée n'est pas détruite.

## 4. Mot de passe de `svc-keycloak`

1. Nouveau mot de passe dans `annuaire/vault-critique.yml`. Le job `annuaire:appliquer` ne le pose **pas** (mot de passe des comptes système posé à la création seulement, E03) : on le change sur `ipa01`, en root, par le socket LDAPI (liaison automatique de root en *Directory Manager*), le nouveau mot de passe lu sur un descripteur, jamais en argument :
   ```
   [admin@ipa01 ~]$ sudo ldappasswd -H ldapi://%2Frun%2Fslapd-PAR1-MEDISPHERE-INTERNAL.socket -Y EXTERNAL \
   >   -T <(…mot de passe…) uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal
   ```
   (le mot de passe arrive par un descripteur alimenté depuis `adm01`, par exemple `ssh ipa01 'sudo ldappasswd … -T /dev/stdin …' < <(…)`).
2. Aussitôt : `svc_keycloak_version_mot_de_passe` + 1 dans `tofu/variables.tf` (MR), apply : Keycloak reçoit le nouveau (`bind_credential_wo`).
3. Fenêtre : entre 1 et 2, les connexions des personnes échouent (`FederationLdapEnEchec` se déclenche : c'est attendu, annonce-le). Mesurée : <N> s.

## 5. Contrôles après toute rotation

`lab/bin/check 24 29` ; `tofu plan` vide ; alertes d'E26 muettes ; essai de connexion d'un personnage par service ; ligne dans le journal des changements (CHG-…).
