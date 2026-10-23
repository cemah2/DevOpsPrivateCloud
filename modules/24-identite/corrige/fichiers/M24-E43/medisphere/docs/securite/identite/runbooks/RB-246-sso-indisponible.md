# RB-246 — SSO indisponible ou refusé

*Propriétaire : équipe Plateforme. Relu par : Nadia Roussel (support, astreinte), Sophie Laurent (RSSI). Commencé en M24-E35 (INC-5135), une section par panne du palier 4 (E35 à E42), terminé en M24-E43 (INC-5143) : annonce, cinq premières minutes, retour à la normale. État : complet (version de livraison `identite-v1`).*

| | |
|---|---|
| Déclencheurs | ticket « je n'arrive plus à me connecter à… » ; alertes `KeycloakIndisponible`, `KeycloakEchecsConnexion`, `FederationLdapEnEchec`, `ClientSsoEnEchec`, `HorlogeDecalee`, `KubeApiJetonsOidcRefuses`, `ConfigurationArgoCDModifiee`, `SssdArrete`, `SsoSansServeur`, `KeycloakBaseSaturee`, sonde `oidc` du témoin de `mon01` |
| Accès de secours | RB-240 (avant tout changement : session `<MOI>-admin` ouverte, `kc-secours` essayé, `admin.conf` au Vault) |
| Liens | RB-240, RB-241, RB-243, RB-244, RB-245, ADR-0240 |

## A. Annonce (les dix premières minutes, avant tout diagnostic)

1. **Déclarer** : ticket `INC-`, priorité P1 si **tous** les services ou toute une équipe sont touchés, P2 sinon. Une personne pilote (l'astreinte), une personne communique si deux sont disponibles.
2. **Premier message** (canal de l'équipe et `plateforme@`), puis **toutes les 30 minutes** jusqu'à la fin :
   > *[INC-51xx] HH:MM — SSO dégradé.* Touché : <services, personnes>. Non touché : les applications des patients (MédiAgenda, MédiDoc n'utilisent pas le SSO pour les patients). Accès de secours : RB-240 si un geste urgent est nécessaire, en prévenant l'astreinte. Diagnostic en cours. Prochain point : HH:MM.
3. **Fin d'incident** : ce qui a été réparé, ce que chacun doit faire (se reconnecter ; `kubectl oidc-login clean` ; nouveau `step ssh login` ; vider les cookies de `mon01:8443` si OAuth2 Proxy était en cause), comptes de secours refermés, lien vers le post-mortem (`docs/securite/identite/post-mortems/`).

## B. Les cinq premières minutes (quelle couche ?)

| # | Commande (depuis `adm01`, sauf mention) | Si… | Alors |
|---|---|---|---|
| 1 | `curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration` | `503` | publication : §8 (HAProxy, TLS) |
| 2 | même URL, `jq -r .issuer` | autre que `https://sso.par1.medisphere.internal/realms/medisphere` | nom public de Keycloak : §8 |
| 3 | `ssh idp01 'systemctl is-active keycloak; curl -sk https://127.0.0.1:9000/health/ready'` | `inactive`, `DOWN` | Keycloak ou sa base : §8 ; restauration : RB-243 |
| 4 | réponse lente, `500` par moments | — | base saturée : §8 |
| 5 | `ldapsearch` par `wb-checks` ; *Test authentication* de la fédération | refus, `err=49` | annuaire, fédération : §3 |
| 6 | un jeton neuf décodé (`iat`, `exp`) | décalé | horloges : §4 |
| 7 | tout va bien côté fournisseur | un seul service | §1 (retour refusé), §2 (kubectl), §5 (droits), §6 (SSH, sudo), §7 (OAuth2 Proxy) |

Les contrôles du workbook passent par `sso` : tant que 1 à 3 échouent, `lab/bin/check 24 …` ne lit plus Keycloak (ce n'est pas une panne de plus).

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

## 6. SSH ou sudo refusé sur les VMs (M24-E40)

| Ce que voit la personne | Étape | Preuve (sur la VM en `admin`, ou sur `ipa01`) | Cause fréquente | Correctif |
|---|---|---|---|---|
| `Permission denied (publickey)`, sshd : `Certificate does not contain an authorized principal` | principal | `step ssh inspect` (certificat de la personne) ; `/usr/local/sbin/principaux-annuaire <id>` ; `curl …/provisioners` (gabarit) | gabarit du provisioner `keycloak` modifié hors Ansible | rôle `step_ca` (`--check --diff --limit ca01`), puis nouveau `step ssh login`, `ssh-add -D` |
| `Invalid user`, une seule VM | compte (NSS) | `systemctl status sssd`, `journalctl -u sssd -b`, `stat /etc/sssd/sssd.conf`, `getent -s sss passwd <id>` | SSSD arrêté ou refusant sa configuration (droits ≠ 0600) | rôle `freeipa_client` sur la VM, `systemctl restart sssd`, `sssctl domain-status` |
| `Connection closed` juste après l'authentification | accès (HBAC) | `sudo sssctl user-checks -a acct -s sshd <id>` ; `ipa hbactest --user=<id> --host=<fqdn> --service=sshd` ; `ipa hbacrule-show <règle> --all --raw` (`modifytimestamp`) | règle désactivée ou modifiée hors code | job `annuaire:appliquer` ; `sss_cache -E` si urgent |
| entre, mais `sudo` refusé | élévation | `sudo -l -U <id>` ; `ipa sudorule-show <règle>` | règle restreinte à un hôte, désactivée | job `annuaire:appliquer` ; `sss_cache -R` |

Jamais : réactiver `allow_all`, ajouter une règle HBAC ou sudo « temporaire », donner le mot de passe d'`admin`. Détection : `annuaire:derive` (nuit), `SssdArrete`.

## 7. OAuth2 Proxy : boucle ou « Login Failed » (M24-E41)

1. `curl -s -o /dev/null -D - <URL de l'instance>/` : `Location` (le `redirect_uri` est-il celui **de cette instance** ?) et `Set-Cookie` (`__Host-…` : `Secure`, `Path=/`, **pas** de `Domain`).
2. Keycloak refuse avant le formulaire (`invalid_redirect_uri`) → client `oauth2-proxy` : `tofu plan`, apply. Keycloak accepte mais le retour arrive sur **une autre** instance → `redirect_url` de l'instance. Retour au bon endroit puis « Login Failed: Unable to find a valid CSRF token » → cookie refusé par le navigateur (outils de développement, onglet Réseau : cookie bloqué).
3. Journal de l'instance (`journalctl -u oauth2-proxy-<nom>`, ou pods de l'espace `oauth2-proxy`) : raison de chaque échec.
4. Correctif : rôle `oauth2_proxy` (`--check --diff --limit mon01`) ou valeurs de l'Application `oauth2-proxy` (Argo CD) ; jamais de `cookie_secure = false`, jamais de joker dans les URI de retour.
5. Autres causes connues : cookie trop gros (`_0`, `_1`… puis `431` chez un mandataire en amont : `session_store_type = "redis"` ou moins de revendications) ; `trusted_proxy_ips` qui ne contient plus la plage de l'Envoy (adresses et schéma faux).

## 8. Le fournisseur d'identité répond mal (M24-E42)

| Découverte | `/health/ready` sur `idp01` | HAProxy (`journalctl -u haproxy`) | Cause | Correctif |
|---|---|---|---|---|
| `200`, émetteur avec un port ou un autre nom | `UP` | UP | `hostname` de `keycloak.conf` (`kc.sh show-config`) | rôle `keycloak` ; chaque service redemande un jeton |
| `503` | `UP` | `Layer6 … SSL handshake failure` | certificat de Keycloak (`openssl s_client` **depuis un répartiteur**, avec la racine et `-verify_hostname idp01…`) | rôle `certificats_acme` sur `idp01`, redémarrage de Keycloak |
| `503` | `UP` | `Layer7 wrong status, code: 404` | contrôle de santé hors du port de gestion 9000 | rôle `haproxy`, un répartiteur à la fois, `haproxy -c` |
| lente, `500` par moments | `DOWN` par moments | DOWN par moments | base : `pg_stat_activity`, `SELECT name, setting, sourcefile FROM pg_settings WHERE name = 'max_connections'`, refus `too many clients` dans le journal de Keycloak | fichier fautif retiré, réglage dimensionné par le rôle (`keycloak_pg_conf`), PostgreSQL puis Keycloak redémarrés |
| `000` / délai | — | — | Keycloak arrêté, `idp01` éteint | `systemctl status keycloak` ; console Proxmox (`root@pam`) ; RB-243 si la VM est perdue |

Détection : `KeycloakIndisponible`, `SsoSansServeur`, `KeycloakBaseSaturee`, sonde `oidc` du témoin (émetteur exact).

## C. Retour à la normale

- [ ] Découverte saine (§B 1-2), `/health/ready` `UP`, `be_sso` UP sur `lb01` **et** `lb02`.
- [ ] Une vraie connexion par famille : un service web (Grafana), `kubectl` (après `kubectl oidc-login clean`), `step ssh login` puis SSH, une interface derrière OAuth2 Proxy.
- [ ] `tofu plan` vide, `annuaire:derive` vert, rôles concernés en `--check` sans changement.
- [ ] Comptes de secours **refermés** (RB-240 : mot de passe changé si le protocole l'exige), ligne au procès-verbal, alertes `BrisDeGlace*` expliquées à Sophie.
- [ ] Message de fin d'incident (§A.3) ; post-mortem sous cinq jours ouvrés (`docs/securite/identite/post-mortems/AAAA-MM-JJ-INC-51xx.md`, modèle de M00-E46).
