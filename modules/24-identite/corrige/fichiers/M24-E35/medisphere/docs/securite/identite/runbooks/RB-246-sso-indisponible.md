# RB-246 — SSO indisponible ou refusé

*Propriétaire : équipe Plateforme. Relu par : Nadia Roussel (support, astreinte), Sophie Laurent (RSSI). Commencé en M24-E35 (INC-5135), une section par panne du palier 4 (E35 à E42) ; annonce, arbre de décision complet et post-mortem en M24-E43. État : sections E35 à E39.*

> Extrait du corrigé : état intermédiaire du runbook après M24-E39 (méthode et sections 1 à 5, identiques à la version finale). Version de référence, complète : `corrige/fichiers/M24-E43/medisphere/docs/securite/identite/runbooks/RB-246-sso-indisponible.md`.

| | |
|---|---|
| Déclencheurs | ticket « je n'arrive plus à me connecter à… » ; alertes `KeycloakIndisponible`, `KeycloakEchecsConnexion`, `FederationLdapEnEchec`, `ClientSsoEnEchec`, `HorlogeDecalee`, `KubeApiJetonsOidcRefuses`, `ConfigurationArgoCDModifiee` |
| Accès de secours | RB-240 (avant tout changement : session `<MOI>-admin` ouverte, `kc-secours` essayé, `admin.conf` au Vault) |
| Liens | RB-240, RB-241, RB-243, RB-244, RB-245, ADR-0240 |

## 0. Méthode (toutes les sections)

1. **Qui, quoi, depuis quand** : un service ou tous ? une personne, un groupe, tout le monde ? `401`/« Login failed » (pas reconnu) ou `403`/vide (reconnu, sans droit) ?
2. **Suivre le jeton** : demande d'autorisation → formulaire (annuaire, OTP) → échange du code → vérification par le service (signature, `iss`, `aud`, `exp`) → revendications (`groups`) → autorisation dans le service.
3. **Témoins** : événements de Keycloak (Loki `audit` : `{service="keycloak"} | json | loggerName="org.keycloak.events"`) ; *Admin events* (qui a changé quoi, avec quel client) ; journal du service ; jeton décodé (*Clients* → client → *Client scopes* → *Evaluate*).
4. **Dérive** : `tofu plan` (`plateforme/identite`), `helmfile -e par1 -l composant=argocd diff` (`plateforme/k8s`), `ansible-playbook … --check --diff` (`plateforme/ansible`).
5. **Corriger par l'outil qui applique le code** ; jamais à la main sans reporter ; jamais en élargissant un droit « le temps de ».
6. **Clore** : preuve par une vraie connexion, journal de diagnostic dans `docs/socle/journal/`, ligne au procès-verbal de RB-240 si un compte de secours a servi.

## 1. Un service refuse le retour du SSO (M24-E35)

| Ce qu'on voit | Événement Keycloak | Cause probable | Correctif |
|---|---|---|---|
| Page d'erreur Keycloak sans formulaire, « Invalid parameter: redirect_uri » | `LOGIN_ERROR`, `error="invalid_redirect_uri"` | URI de redirection du client modifiée | `tofu plan` la montre : pipeline `main`, `tofu:apply` |
| Formulaire, puis « Login failed » dans le service | `CODE_TO_TOKEN_ERROR`, `error="invalid_client_credentials"` | secret du client différent entre Keycloak et le service | **invisible au plan** (`client_secret_wo`) : introspection avec le secret du Vault (RB-244) ; si le Vault et le service sont d'accord, version du secret + 1 (MR, apply) |
| Formulaire, `CODE_TO_TOKEN` réussi, refus dans le service (Grafana : `role_attribute_strict`) | aucun | revendication manquante (portée `groupes` retirée du client) | *Evaluate* ; `tofu plan` ; apply |

Toujours : *Admin events* (client utilisé : `svc-tofu-keycloak` hors `runner01` = usage manuel du secret d'OpenTofu → rotation de ce secret, RB-244).

## 2. kubectl refuse les jetons (M24-E36)

1. `kubectl auth whoami` : répond (→ 403, RBAC ou préfixes) ou `Unauthorized` (→ 401, jeton refusé).
2. Raison du 401 : journal de kube-apiserver de chaque nœud (`sudo crictl logs --since 30m <id> 2>&1 | grep 'Unable to authenticate'`) ; métriques `apiserver_authentication_jwt_authenticator_latency_seconds_count{result}`, `apiserver_authentication_config_controller_*` dans la vue globale.
3. Fichier : `sha256sum /etc/kubernetes/authentification/config.yaml` sur les trois nœuds ; `ansible-playbook playbooks/k8s-api-fichiers.yml --check --diff`.
4. Correctif : le playbook (écriture par renommage, dossier monté, rechargement en une minute) ; **jamais** une liaison RBAC qui s'adapte à un préfixe faux, jamais de redémarrage de kube-apiserver.
5. Si ton propre accès est coupé : SSH sur les nœuds, vue globale ; `admin.conf` seulement pour lire un objet, en le déclarant (RB-240).

## 3. Une personne de l'annuaire n'existe pas dans Keycloak (M24-E37)

1. Annuaire : `ipa user-show <uid> --all` (création, groupes, désactivation).
2. Étendue : une personne ancienne se connecte-t-elle ? Les membres du même groupe ont-ils le groupe dans un jeton évalué ? `FederationLdapEnEchec` ?
3. *User federation* → `ipa01` : *Test authentication* (liaison de `svc-keycloak`) ; filtre des personnes ; mappeur `groupes-ipa` (filtre des groupes).
4. `ipa01`, journal d'accès de 389-ds : `BIND dn="uid=svc-keycloak…"` → `RESULT err=49` (mot de passe) ; `SRCH … filter=…` (le filtre réel, à rejouer avec `ldapsearch -Y GSSAPI`) ; `MOD` sur `cn=sysaccounts` (qui a changé un compte système).
5. Correctif : mot de passe de `svc-keycloak` = valeur du Vault `critique` (RB-244 §4, LDAPI, descripteur) ; filtres : `tofu plan`, apply. Puis *Sync changed users*, *Evaluate*.
6. Jamais de personne créée à la main dans Keycloak.

## 4. Jeton expiré dès l'émission (M24-E38)

1. Décoder un jeton neuf : `iat`, `exp`, `exp − iat`, comparés à l'heure d'`adm01`.
2. `exp − iat` anormal → *Realm settings* → *Tokens* ; `tofu plan` ; apply.
3. `iat` décalé → horloge de l'émetteur (`idp01`) ; jeton normal refusé par un seul vérificateur → horloge de ce vérificateur (interroger chaque kube-apiserver directement).
4. `date +%s` simultané sur les machines ; `timedatectl` ; `chronyc tracking` ; `journalctl -u chrony` (ou `chronyd`).
5. Correctif : `systemctl enable --now chrony` puis `chronyc -a makestep` ; rôle de base rejoué ; jamais `date -s` ; jamais l'heure de `pve01` ou des passerelles.

## 5. Droits faux dans un service (M24-E39)

1. Groupes vus par le service (`argocd account get-user-info`, profil Grafana, `kubectl auth whoami`) : forme attendue (`plateforme-admins`) ou non (`/plateforme-admins` → mappeur `groups` de la portée `groupes` : **tous** les services touchés ; `tofu plan`, apply ; reconnexion des personnes).
2. Groupes justes, droits faux → politique du service : `argocd admin settings rbac can <groupe> … --namespace argocd` (en place) contre `--policy-file releases/argocd/policy.csv` (dépôt) ; `helmfile diff` ; `managedFields` ; audit `{job="kubernetes-audit"}`.
3. Correctif : `helmfile apply` de la release `argocd`.
4. **Droits trop larges** (ex. `policy.default: role:admin`) : c'est un incident de sécurité. Établir la fenêtre, les personnes connectées (événements `LOGIN` du client), les actions faites (`argocd app history`, événements des Applications, audit), prévenir Sophie avant de clore.
