<!-- Partie C du corrigé du palier 2 (M24-E17 à M24-E23) : à fusionner après la partie B. Le bloc
     « vérifié / non testé » ci-dessous rejoint celui de l'en-tête du palier. -->

**Ce qui a été vérifié à la rédaction (E17 à E23).**
- *RBAC* (E17) : `rbac/oidc.yaml` appliqué avec les rôles du M14 sur un **kube-apiserver 1.36.0 réel** (etcd 3.6.5, contrôleur d'agrégation de kube-controller-manager 1.36.0) : agrégation de `medisphere-plateforme` et `medisphere-securite` constatée ; `matrice-droits-oidc.sh` sans écart (hors deux cas qui visent des CRD absentes de ce plan de contrôle d'essai, autorisés par une SubjectAccessReview directe) ; `check-E17.sh` exécuté avec un vrai jeton du compte `wb-checks` (contrôles au vert, puis au rouge tant que les liaisons `medisphere:*` existaient et avec un kubeconfig à certificat).
- *Keycloak 26.7.5 réel* (`start-dev`) et fournisseur `keycloak/keycloak` 5.10.0, OpenTofu 1.13.2 : `flux.tf`, `clients-oauth2-proxy.tf`, `clients-step-ca.tf` appliqués, **plan vide** ensuite ; le flux joué de bout en bout : `lucas.martin` reçoit son code sans second facteur, un membre de `plateforme-admins` est envoyé sur l'action requise `CONFIGURE_TOTP` ; une exécution passée à la main en `ALTERNATIVE` est vue par le plan (dérive) et par `check-E21.sh` (rouge). Les sept conditions disponibles relevées dans la distribution (`conditional-user-role`, `conditional-user-configured`, `conditional-user-attribute`, `conditional-client-scope`, `conditional-credential`, `conditional-sub-flow-executed`, `conditional-level-of-authentication`) : aucune ne vise un groupe.
- *OAuth2 Proxy 7.15.5 réel* (binaire officiel, empreinte vérifiée) contre ce Keycloak : configuration de `mon01` (rôle `oauth2_proxy` rendu par Ansible, `--config` + `--alpha-config`) : connexion complète, en-tête `Authorization` du navigateur **remplacé** par le compte technique, `Host` transmis ; refus `invalid_scope` de Keycloak quand la portée `groups` est demandée (défaut de `keycloak-oidc`), d'où `scope` explicite ; secret de cookie lu **tel quel** depuis un fichier (44 caractères base64 refusés, 32 acceptés) ; aucune écoute HTTP 4180 avec la configuration structurée ; configuration du chart (fichier `oauth2_proxy.cfg`) chargée par le même binaire. Chart **10.7.1** rendu par `helm template` avec les valeurs (HTTPRoute, cookie `__Host-`, Secret existant, image du cache Harbor) ; empreinte de l'archive égale au `digest` de l'index.
- *step-ca* (E20) : code de `certificates` 0.30.2 et de la CLI `step` 0.30.2 relu (principaux OIDC par défaut dérivés du courriel avec les **points retirés**, `.Token` dans les gabarits, PKCE envoyé par la CLI, `listenAddress`, `clientSecret` vide permis) ; le gabarit SSH du provisioner exécuté avec `sshutil` de `go.step.sm/crypto` (principal `lucas.martin`, échec explicite sans `preferred_username`, gabarit X.509 toujours en échec).
- *OpenSSH* (E20) : `auth2-pubkey.c` de 10.0p1 relu : `AuthorizedPrincipalsFile` d'abord, `AuthorizedPrincipalsCommand` ensuite si rien n'a été trouvé ; refus de démarrer sans `AuthorizedPrincipalsCommandUser`.
- *E22* : le code de Lucas appliqué tel quel sur le Keycloak d'essai : plan jamais vide (secret d'un client public ignoré par Keycloak), création d'utilisateur refusée (400) par la fédération `WRITABLE` sans annuaire, puis, fédération coupée, un compte d'essai qui se donne `plateforme-admins` par l'attribut `equipe` et reçoit un jeton de 24 h **sans `sub`** par le flux par mot de passe.
- *Ansible* : `ansible-lint` 26.10 (profil `production`) et `--syntax-check` sur les rôles `oauth2_proxy`, `freeipa_client` et `playbooks/inscription-ipa.yml` ; modules de `freeipa.ansible_freeipa` 1.17.0 relus (`ipahost` `random`/`update_password`, `ipaclient_otp`, `ipahbacrule`, `ipasudorule`, `ipasudocmdgroup`).
- *Scripts* : `shellcheck -x` et `bash -n` (checks, `matrice-droits-oidc.sh`, `principaux-annuaire`).

**Points non testés en conditions réelles (E17 à E23)**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- **Inscription Debian 13 → FreeIPA 4.13** par le rôle `ipaclient` 1.17 (`ipaclient_otp`, `ipaclient_no_sshd`), et le comportement de **`filter_users`** de SSSD 2.10 sur l'étape *account* de PAM pour le compte local `admin` (la protection repose dessus : refais le test d'une nouvelle connexion `admin` à **chaque** hôte) ; messages exacts de `sssctl user-checks`.
- Règle sudo avec un **groupe d'exécution local** (`systemd-journal`, non défini dans l'annuaire) par `ipasudorule` `runasgroup` : si le module refuse un groupe inconnu de FreeIPA, ajoute-le en groupe externe à la main (`ipa sudorule-add-runasgroup`) ou remplace la règle par des commandes de consultation exécutées en root (et dis-le dans le modèle d'autorisation).
- **Gateway API** : bascule de la route de Hubble (deux HTTPRoute sur le même nom) ; plage source vue par OAuth2 Proxy derrière l'Envoy de Cilium (`trusted_proxy_ips`).
- **Mailpit 1.31** derrière OAuth2 Proxy : liste des noms autorisés et WebSocket des mises à jour en direct.
- Connexion réelle par **`step ssh login`** (tunnel du port 10000, navigateur), `getent -s sss` sous `nobody` dans la commande de principaux ; ligne exacte de `pam_sss` dans le journal pour un refus HBAC.
- Effet de l'OTP sur **kubelogin** et la durée réelle sans nouveau code (dépend de la session SSO de Keycloak et du cache de kubelogin).

**Où lancer les commandes.** Comme pour la partie B ; en plus `admin@mon01:~$`, `[admin@ipa01 ~]$` (Rocky), `admin@<hôte>:~$` sur les VMs inscrites.

---

### M24-E17 — RBAC Kubernetes par groupes de l'annuaire

**Solution**

Fichiers : [`rbac/oidc.yaml`](fichiers/M24-E17/k8s/rbac/oidc.yaml), [`outils/matrice-droits-oidc.sh`](fichiers/M24-E17/k8s/outils/matrice-droits-oidc.sh), [`docs/kubernetes/acces.md`](fichiers/M24-E17/medisphere/docs/kubernetes/acces.md).

*A. Inventaire.* La commande de l'énoncé (avec le RBAC du M14) donne :

```
ClusterRoleBinding  -                   medisphere:plateforme-admins  Group  medisphere:plateforme-admins  cluster-admin
ClusterRoleBinding  -                   medisphere-lecture            Group  medisphere:lecture            medisphere-lecture
RoleBinding         mediagenda-dev      mediagenda-devs-developpeur   Group  medisphere:mediagenda-devs    medisphere-developpeur
RoleBinding         mediagenda-dev      mediagenda-devs-secrets       Group  medisphere:mediagenda-devs    medisphere-secrets-edition
RoleBinding         mediagenda-recette  mediagenda-devs-lecture       Group  medisphere:mediagenda-devs    medisphere-lecture-charges
RoleBinding         medidoc-dev         medidoc-devs-developpeur      Group  medisphere:medidoc-devs       medisphere-developpeur
RoleBinding         medidoc-dev         medidoc-devs-secrets          Group  medisphere:medidoc-devs       medisphere-secrets-edition
…                   (liaisons des agents, d'Argo CD, des comptes de service : hors sujet)
```

Écarts avec le modèle d'autorisation : l'équipe Plateforme (hors administrateurs) n'avait **aucun** droit propre au M14 (elle avait le certificat `plateforme-admins`) ; `mediagenda` n'avait rien en production ; MédiDoc écrivait à la main dans `medidoc-dev` (le modèle ne le prévoit plus : Argo CD) ; personne n'avait la lecture du RBAC hors administrateurs.

*B. Les liaisons.* `oidc.yaml` ajoute trois ClusterRoles : `medisphere-plateforme` (agrégée : la lecture du M14 + `medisphere-plateforme-composants`, qui lit **tous** les objets d'une liste explicite de groupes d'API autres que le cœur), `medisphere-securite` (agrégée : la lecture du M14 + `medisphere-securite-rbac`) ; puis les liaisons `oidc-*` du modèle. Les Secrets sont dans le groupe d'API du cœur (`""`) : un `*` sur `apps`, `argoproj.io`, `monitoring.coreos.com`… ne les atteint pas, et le cœur n'est accordé que ressource par ressource (`medisphere-lecture-charges`, sans `secrets`).

```
admin@adm01:~/src/k8s$ task valider && task diff
admin@adm01:~/src/k8s$ git switch -c rbac-oidc && git add rbac/oidc.yaml && git commit -m "feat(rbac): droits des groupes de l'annuaire (SEC-2517)"
admin@adm01:~/src/k8s$ git push -u origin rbac-oidc        # MR, relecture, fusion
admin@adm01:~/src/k8s$ git switch main && git pull && task appliquer
admin@adm01:~$ kubectl get clusterrole medisphere-plateforme -o jsonpath='{.rules[*].apiGroups}' | tr ' ' '\n' | sort -u | head
```

*C. Vérifier.*

```
admin@adm01:~$ kubectl auth whoami --as=oidc:julien.petit --as-group=oidc:mediagenda
ATTRIBUTE   VALUE
Username    oidc:julien.petit
Groups      [oidc:mediagenda system:authenticated]
admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-prod --as=oidc:julien.petit --as-group=oidc:mediagenda
no
admin@adm01:~/src/k8s$ outils/matrice-droits-oidc.sh
OK     karim.benali    plateforme-admins  kube-system         delete  pods                               yes
…
OK     intrus          system:masters     kube-system         list    secrets                            no

Matrice conforme au modèle d'autorisation.
```

`--as` seul n'apporte que l'utilisateur ; kube-apiserver n'invente pas ses groupes (ils viendraient du jeton) : il faut `--as-group` pour chacun (`system:authenticated` est ajouté d'office). Usurper une identité exige le verbe `impersonate` sur `users` et `groups` : `cluster-admin` l'a ; c'est un droit d'administration complet (on devient n'importe qui, `system:masters` compris), à ne donner qu'aux administrateurs. Le cas `system:masters` : un groupe de ce nom dans l'annuaire arrive **préfixé** (`oidc:system:masters`), n'a aucune liaison, donc aucun droit ; et la règle CEL d'E16 refuse de toute façon un groupe qui commence par `system:`.

Le jeton réel de Lucas sans toucher au tien :

```
admin@adm01:~$ mkdir -p ~/m24/e17 && umask 077
admin@adm01:~$ kubectl config view --raw --minify --context k8s-par1-oidc > ~/m24/e17/essai.kubeconfig
admin@adm01:~$ kubectl --kubeconfig ~/m24/e17/essai.kubeconfig config set-credentials oidc \
>   --exec-arg=--token-cache-dir=$HOME/m24/e17/cache-essai                                  # voir la remarque ci-dessous
admin@adm01:~$ kubectl --kubeconfig ~/m24/e17/essai.kubeconfig auth whoami      # fenêtre privée, lucas.martin
Username    oidc:lucas.martin
Groups      [oidc:plateforme system:authenticated]
admin@adm01:~$ kubectl --kubeconfig ~/m24/e17/essai.kubeconfig get secrets -n kube-system
Error from server (Forbidden): secrets is forbidden: User "oidc:lucas.martin" cannot list resource "secrets" …
admin@adm01:~$ kubectl --kubeconfig ~/m24/e17/essai.kubeconfig -n wb-essais create configmap essai --from-literal=a=b
admin@adm01:~$ kubectl -n wb-essais delete configmap essai && rm -rf ~/m24/e17/essai.kubeconfig ~/m24/e17/cache-essai
```

(Selon ta version de kubectl, `set-credentials --exec-arg` **remplace** la liste : relis `kubectl config view --minify` et, au besoin, édite le fichier pour ajouter `--token-cache-dir=…` aux arguments existants de `kubectl oidc-login get-token`.)

*D. La bascule.* Contrôles préalables de l'avertissement, puis :

```
admin@adm01:~$ install -m 600 ~/.kube/config ~/.kube/config.avant-e17
admin@adm01:~$ kubectl config set-context k8s-par1 --user=oidc
admin@adm01:~$ kubectl config use-context k8s-par1-oidc
admin@adm01:~$ kubectl config get-users                       # l'utilisateur à certificat du M14
admin@adm01:~$ kubectl config delete-user <UTILISATEUR-CERTIFICAT>
admin@adm01:~/src/k8s$ task diff && helmfile -e par1 diff      # s'authentifient comme oidc:<MOI>
admin@adm01:~/src/k8s$ kubectl delete -f rbac/plateforme-admins.yaml -f rbac/20-liaisons-cluster.yaml \
>   -f rbac/30-mediagenda.yaml -f rbac/40-medidoc.yaml
admin@adm01:~/src/k8s$ git rm rbac/plateforme-admins.yaml rbac/20-liaisons-cluster.yaml rbac/30-mediagenda.yaml \
>   rbac/40-medidoc.yaml outils/kubeconfig-personnel.sh outils/kubeconfig-csr.sh   # + Taskfile/README qui les citent
admin@adm01:~/src/k8s$ outils/matrice-droits-oidc.sh
```

`kubectl delete` **avant** la MR : `task appliquer` n'élague pas ; un fichier retiré de Git laisserait ses liaisons vivantes dans le cluster, et ton certificat (encore valide quelques jours) garderait `cluster-admin`. Dans l'autre ordre, un `task appliquer` lancé entre-temps les recréerait. Garde `~/.kube/config.avant-e17` (600) une semaine, puis supprime-le : il contient la clé privée du certificat.

**Explications**

- **Le préfixe `oidc:`** sépare deux espaces de noms : ce que l'annuaire appelle `plateforme` ne peut jamais rencontrer un groupe interne de Kubernetes (`system:*`, `kubeadm:*`) ni un groupe de certificat (`medisphere:*`). Sans préfixe, quiconque peut créer un groupe dans l'annuaire peut créer `system:masters`.
- **Pourquoi retirer les liaisons des certificats** : un certificat client ne se révoque pas (kube-apiserver ne consulte pas de liste de révocation) ; tant que la liaison existe, le certificat garde son pouvoir jusqu'à son expiration. La liaison, elle, se supprime en une seconde.
- **Repointer `k8s-par1`** plutôt que réécrire les outils : le Taskfile, `releases/_communs.yaml` (`kubeContext`), `secrets-k8s.sh` (`KUBE_CONTEXTE`), `verifier-cluster.sh`, `comparer-releases.sh`… visent ce **nom** de contexte ; changer l'utilisateur derrière le nom les fait passer à OIDC sans une ligne de code, et ils restent explicites sur le cluster visé.
- **Agrégation** : `medisphere-plateforme` et `medisphere-securite` n'ont pas de `rules` écrites ; le contrôleur y recopie les règles des petits rôles étiquetés. Un composant ajouté plus tard (Kyverno au M26) devient lisible par une MR qui ajoute **son** groupe d'API à `medisphere-plateforme-composants`, sans toucher aux liaisons.
- **`edit` dans `mediagenda-dev`** (modèle d'autorisation) inclut les Secrets de l'espace et `exec` : c'est l'espace de développement, et Argo CD y remet ce qui est dans Git (`selfHeal`) ; en recette et en production, `view` (ni Secrets, ni `exec`).

**Alternatives**

- *Pinniped* (M24-E32) : un « concierge » qui échange les jetons de l'IdP contre des identités de cluster, sans toucher à kube-apiserver ; utile pour plusieurs clusters ou un cluster géré.
- *Liaisons gérées par Argo CD* plutôt que par `task appliquer` : élagage automatique (le piège de l'étape 8 disparaît), mais le RBAC de la plateforme dépendrait d'Argo CD, qui dépend lui-même de ce RBAC pour ses administrateurs ; la couche de base reste hors Argo CD (M20).
- *Rôles par équipe générés* (gabarit `nouvelle-equipe.sh` du M14 adapté aux groupes `oidc:`) quand les équipes se multiplient.

**Pièges classiques**

- Oublier `--as-group` et conclure que « le RBAC ne marche pas ».
- Lier un groupe sans le préfixe (`plateforme`) : la liaison est valide, ne correspond à aucun jeton, et le symptôme est un refus silencieux (c'est la panne M24-E36).
- `git rm` sans `kubectl delete` : liaisons orphelines, certificats encore puissants.
- `kubectl oidc-login clean` pendant les essais : efface **ton** cache, d'où le dossier de cache séparé pour Lucas.
- Supprimer l'utilisateur à certificat **avant** d'avoir vérifié que le contexte OIDC est `cluster-admin` et que `admin.conf` fonctionne.
- Les checks du M14 (`lab/bin/check 14 11`) qui lisent les liaisons `medisphere:*` passent au rouge : normal, ils décrivent l'état du M14.

**En production chez MédiSphère**

Matrice dans le pipeline de `plateforme/k8s` à chaque MR de `rbac/` (compte de service qui ne peut que créer des `SubjectAccessReview`, sans `impersonate`) ; revue trimestrielle des liaisons par Sophie (rapport de M24-E30) ; journal d'audit de l'API filtré sur les refus (`Forbidden`) des utilisateurs `oidc:*` pour repérer un droit manquant ou une tentative ; `exec` dans les espaces de données de production réservé au bris de glace, ce que le RBAC seul ne sait pas exprimer pour `cluster-admin` : politique d'admission au M26 (promesse du M23 tenue en partie ici : aucune équipe n'a `exec` en production).

---

### M24-E18 — OAuth2 Proxy devant Hubble, Pyroscope et Mailpit

**Solution**

Fichiers : client [`tofu/clients-oauth2-proxy.tf`](fichiers/M24-E18/identite/tofu/clients-oauth2-proxy.tf) ; valeurs [`valeurs-communes.yaml`](fichiers/M24-E18/identite/oauth2-proxy/valeurs-communes.yaml), [`valeurs-hubble.yaml`](fichiers/M24-E18/identite/oauth2-proxy/valeurs-hubble.yaml), [`valeurs-pyroscope.yaml`](fichiers/M24-E18/identite/oauth2-proxy/valeurs-pyroscope.yaml) et [`manifestes/`](fichiers/M24-E18/identite/oauth2-proxy/manifestes/) (ajoute à côté une copie de `pki/medisphere-root-ca.crt`) ; [Application](fichiers/M24-E18/gitops/plateforme/oauth2-proxy.yaml) et [AppProject (extrait)](fichiers/M24-E18/gitops/projets/plateforme.extrait.yaml) ; [entrée de `charts-miroir`](fichiers/M24-E18/charts-miroir/charts.extrait.yaml) ; [`espaces/oauth2-proxy.yaml`](fichiers/M24-E18/k8s/espaces/oauth2-proxy.yaml), [`secrets-k8s.conf` (extrait)](fichiers/M24-E18/k8s/outils/secrets-k8s.conf.extrait), [`secrets/identite.yml` (extrait)](fichiers/M24-E18/ansible/secrets/identite.extrait.yml.exemple), [politique de `hubble-ui`](fichiers/M24-E18/k8s/composants/reseau/hubble-ui/cnp-hubble-ui.yaml), [politique de Pyroscope (extrait)](fichiers/M24-E18/observabilite/otel/politiques.extrait.yaml) ; rôle [`oauth2_proxy`](fichiers/M24-E18/ansible/roles/oauth2_proxy/), [`host_vars/mon01/`](fichiers/M24-E18/ansible/inventories/lab/host_vars/mon01/), [`playbooks/supervision.yml` (extrait)](fichiers/M24-E18/ansible/playbooks/supervision.extrait.yml).

*A. Notes.* `keycloak-oidc` demande par défaut `openid email profile groups` ; notre royaume n'a pas de portée `groups` (elle s'appelle `groupes`, E06), et Keycloak refuse **toute** la demande (`error=invalid_scope`) : on fixe `scope = "openid email profile"`, la portée par défaut `groupes` s'ajoute seule. Le préfixe `__Host-` impose au navigateur un cookie `Secure`, `Path=/`, **sans** `Domain` : il ne part que vers l'hôte exact qui l'a posé (ni `pyroscope.apps…` ni un sous-domaine ne le reçoivent). `cookie_refresh` : au-delà de ce délai, OAuth2 Proxy rafraîchit la session auprès de Keycloak ; une personne désactivée ou déconnectée (RB-242) perd l'accès au rafraîchissement suivant. `reverse_proxy` fait croire les en-têtes `X-Forwarded-*` (adresse du client, hôte, schéma) ; jusqu'à 7.15.4, de **n'importe qui** : une adresse usurpée contournait les règles fondées sur l'IP (GHSA-wr5q-7wxw-x568) ; 7.15.5 ajoute `trusted_proxy_ips` (et durcit l'interprétation des chemins `skip_auth_*`, GHSA-63jm-59jj-478j).

*B. Le cluster.*

```
admin@adm01:~/src/identite$ tofu -chdir=tofu plan        # puis MR, apply par le pipeline
admin@adm01:~/src/identite$ outils/ranger-secret-client.sh oauth2-proxy
admin@adm01:~/src/ansible$ uv run ansible-vault edit secrets/identite.yml   # oauth2_proxy_client_id, oauth2_proxy_cookie_secret_cluster
admin@adm01:~/src/k8s$ task espaces && outils/secrets-k8s.sh appliquer identite && outils/secrets-k8s.sh verifier identite
admin@adm01:~/src/gitops$ git add plateforme/oauth2-proxy.yaml projets/plateforme.yaml   # MR, fusion
admin@adm01:~$ kubectl -n oauth2-proxy get deploy,httproute
NAME                                     READY   UP-TO-DATE   AVAILABLE
deployment.apps/oauth2-proxy-hubble      2/2     2            2
deployment.apps/oauth2-proxy-pyroscope   2/2     2            2
NAME                                                         HOSTNAMES
httproute.gateway.networking.k8s.io/oauth2-proxy-hubble      ["hubble.apps.par1.medisphere.internal"]
httproute.gateway.networking.k8s.io/oauth2-proxy-pyroscope   ["pyroscope.apps.par1.medisphere.internal"]
```

Pyroscope répond tout de suite (pas de route concurrente) une fois la politique `traces-pyroscope` étendue. Pour Hubble, les deux routes réclament `hubble.apps…` et `/` : la Gateway API donne la priorité à la plus **ancienne** (celle du M15), la nouvelle est acceptée mais ne reçoit rien : le SSO « ne marche pas » sans erreur. Bascule :

```
admin@adm01:~/src/k8s$ kubectl apply -f composants/reseau/hubble-ui/cnp-hubble-ui.yaml       # après MR
admin@adm01:~/src/k8s$ kubectl delete -f composants/reseau/hubble-ui/httproute.yaml -f composants/reseau/hubble-ui/referencegrant.yaml
admin@adm01:~/src/k8s$ git rm composants/reseau/hubble-ui/httproute.yaml composants/reseau/hubble-ui/referencegrant.yaml
```

La politique d'abord : à partir de là, l'ancienne route ne mène plus nulle part (Envoy n'est plus accepté par `hubble-ui`), la nouvelle prend le relais dès la suppression. `julien.petit` sur Hubble : connexion Keycloak réussie, puis **403** d'OAuth2 Proxy (« Forbidden »), parce que son groupe n'est pas dans `allowed_groups` : l'authentification est faite, l'autorisation refusée par l'instance.

*C. `mon01`.* Le rôle télécharge l'archive par empreinte, pose une unité par instance, écrit `client-secret`, `cookie-secret` et `autorisation-amont` en 0640 `root:oauth2-proxy` **sans retour à la ligne** (`copy` avec `content`), et la configuration en deux fichiers : `oauth2-proxy.cfg` (cookies, redirection) et `alpha.yaml` (serveur TLS sur 8443, amont, fournisseur, en-têtes). L'en-tête vers Mailpit :

```yaml
injectRequestHeaders:
  - name: Authorization
    preserveRequestValue: false        # l'en-tête du navigateur est retiré, jamais transmis
    values:
      - secretSource:
          fromFile: /etc/oauth2-proxy/mailpit/autorisation-amont   # « Basic base64(sso:…) »
```

Mailpit vérifie l'en-tête `Host` (`MP_ALLOWED_HOSTS`, M19) : OAuth2 Proxy transmet celui du navigateur (`passHostHeader: true`, nécessaire pour que l'origine des WebSocket corresponde), donc `mon01.par1.medisphere.internal:8443` s'ajoute à la liste. L'amont est appelé **par son nom** (`https://mon01.par1.medisphere.internal:8025`) : le certificat de Mailpit ne couvre pas `127.0.0.1`, et le trafic vers sa propre adresse passe par `lo`.

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://mon01.par1.medisphere.internal:8443/ | sed 's/state=[^&]*/state=…/'
302 https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth?client_id=oauth2-proxy&code_challenge=…&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fmon01.par1.medisphere.internal%3A8443%2Foauth2%2Fcallback&response_type=code&scope=openid+email+profile&state=…
```

**Explications**

- **Un client, plusieurs instances** : Keycloak authentifie et vérifie l'URI de retour ; l'**autorisation** (quels groupes) est décidée par chaque instance. Un client par instance serait aussi juste (secrets séparés, révocation fine) ; un seul simplifie la rotation (RB-244) et le modèle d'autorisation.
- **Le cookie de session porte la session** (chiffrée par `cookie-secret`) : pas de stockage partagé, deux réplicas suffisent. Des groupes nombreux grossissent le cookie (OAuth2 Proxy le découpe au-delà de 4 Ko) : panne M24-E41.
- **Fermer les contournements** compte autant qu'ajouter OAuth2 Proxy : la politique Cilium de `hubble-ui` (seul OAuth2 Proxy entre), celle des pods d'OAuth2 Proxy (seul l'Envoy de la Gateway), le port 8025 de Mailpit fermé au VPN.
- **L'API de Mailpit en basique** reste une exception (compte `wb-checks` avec tous les droits de Mailpit, qui n'a pas de rôles), compensée par le filtrage à MGMT et inscrite au registre des comptes locaux (E10).

**Alternatives**

- *Authentification externe de la Gateway* (filtre `ext_authz` d'Envoy vers OAuth2 Proxy en mode `/oauth2/auth`) : une seule instance pour toutes les routes, mais une dépendance de la Gateway entière à OAuth2 Proxy, et Cilium ne l'expose pas aussi simplement qu'Envoy Gateway.
- *Pomerium*, *Authelia* : mandataires d'accès plus riches (politiques par route, appareils) ; une brique de plus à exploiter.
- *SSO natif* quand il existe (Grafana, Argo CD) : toujours préférable.

**Pièges classiques**

- `invalid_scope` au premier essai (portée `groups` demandée par défaut).
- Secret de cookie de 44 caractères base64 dans un **fichier** : refusé (« must be 16, 24, or 32 bytes ») ; le même dans une variable d'environnement est décodé. `openssl rand -hex 16` (32 caractères) marche dans les deux cas.
- Un retour à la ligne final dans `client-secret` : `invalid_client` sans autre indice.
- Deux HTTPRoute sur le même nom : l'ancienne gagne, sans erreur visible.
- `cookie_domain` posé avec `__Host-` : le navigateur rejette le cookie, boucle de redirection (panne M24-E41).
- Oublier `trusted_proxy_ips` : 7.15.5 croit encore tout le monde par compatibilité.

**En production chez MédiSphère**

Prometheus, Thanos Query et Alertmanager derrière OAuth2 Proxy (promesse du M21) une fois les accès non humains recensés (sonde du témoin de `mon01`, Grafana, `wb-checks`), avec un second client pour les accès machine ; métriques d'OAuth2 Proxy (`44180`) dans Prometheus et alerte sur les 5xx ; journaux d'accès (identifiant de la personne) vers le locataire `audit`.

---

### M24-E19 — Inscrire les VMs dans FreeIPA : SSSD, HBAC et sudo

**Solution**

Fichiers : rôle [`freeipa_client`](fichiers/M24-E19/ansible/roles/freeipa_client/), [`playbooks/inscription-ipa.yml`](fichiers/M24-E19/ansible/playbooks/inscription-ipa.yml), [`annuaire/hbac.yml`](fichiers/M24-E19/identite/annuaire/hbac.yml), [`annuaire/sudo.yml`](fichiers/M24-E19/identite/annuaire/sudo.yml), [`annuaire.yml` (ajouts)](fichiers/M24-E19/identite/annuaire/annuaire.extrait.yml).

*A. Comprendre.* Avant inscription : `passwd: files systemd`, pas de `pam_sss`, `getent passwd admin` → l'entrée locale (UID 1000). L'inscription ajoute `sss` à `passwd`, `group`, `sudoers` (et `netgroup`, `automount`) et `pam_sss` aux fichiers `common-*` par `pam-auth-update`. Le compte `admin` existe **deux fois** : localement et dans l'annuaire (le compte d'administration de FreeIPA, membre de `admins`). sshd demande à PAM, étape *account* ; sur Debian, `pam_sss` y est en `[default=bad success=ok user_unknown=ignore]` : si SSSD **connaît** un `admin`, il évalue HBAC pour lui, et le jour où `allow_all` est désactivée, aucune règle ne laisse passer `admin`. Ansible et l'astreinte sont dehors. `filter_users = root, admin` (section `[nss]`) fait répondre « inconnu » par SSSD pour ces noms : `pam_sss` rend `user_unknown`, ignoré, et seuls les fichiers locaux comptent.

*B. Inscription.*

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/inscription-ipa.yml --limit mon01
admin@adm01:~$ ssh admin@mon01 'sudo -n true && getent passwd lucas.martin && getent -s sss passwd admin; echo "sss admin: $?"'
lucas.martin:*:1234500005:1234500005:Lucas Martin:/home/lucas.martin:/bin/sh
sss admin: 2
admin@mon01:~$ sudo klist -k | head -n 4
admin@mon01:~$ sudo sssctl domain-status par1.medisphere.internal
Online status: Online
…
```

Le rôle ne fait générer le mot de passe à usage unique **que** si l'hôte n'est pas inscrit (`/etc/ipa/default.conf` absent), sur l'hôte d'inventaire `ipa01` (module `ipahost`, `random: true`, `update_password: on_create`), puis le passe au rôle `ipaclient` par `ipaclient_otp`. Le mot de passe d'`admin` de l'annuaire ne sert que sur `ipa01`. Le seul « secret » qui passe en argument sur l'hôte est ce mot de passe à usage unique, que `ipa-join` consomme aussitôt : il ne vaut plus rien une seconde après. Vagues : `mon01`, puis INFRA, puis `dns01` et `dns02` séparément, `lb02` puis `lb01` (flux DMZ → `ipa01` ouverts en E02), `adm01`, puis chaque nœud (contrôle, puis travailleurs ; `kubectl get nodes` entre deux).

*C. HBAC et sudo.* Première MR (`allow_all` encore `enabled`), application, puis les essais :

```
[admin@ipa01 ~]$ ipa hbactest --user=lucas.martin --host=git01.par1.medisphere.internal --service=sshd \
>   --rules=hbac-plateforme --rules=hbac-support
--------------------
Access granted: True
--------------------
  Matched rules: hbac-plateforme
  Not matched rules: hbac-support
[admin@ipa01 ~]$ ipa hbactest --user=nadia.roussel --host=git01.par1.medisphere.internal --service=sshd \
>   --rules=hbac-plateforme --rules=hbac-support
---------------------
Access granted: False
---------------------
```

| Groupe | `mon01` | `git01` | `k8s-w01` |
|---|---|---|---|
| `plateforme-admins`, `plateforme` | oui | oui | oui |
| `support` | oui | **non** | **non** |
| `mediagenda`, `medidoc`, `securite`, `direction` | non | non | non |

Ce qui disparaît avec `allow_all` : tout le monde avait accès partout (en théorie : personne n'avait encore de moyen de s'authentifier par SSH avant E20, d'où le bon moment pour couper). Seconde MR (`annuaire_hbac_allow_all: disabled`), application, puis :

```
admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd lucas.martin | tail -n 2
pam_acct_mgmt: Success
admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd julien.petit | tail -n 2
pam_acct_mgmt: Permission denied
admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd admin | tail -n 2
pam_acct_mgmt: User not known to the underlying authentication module
admin@mon01:~$ sudo -l -U lucas.martin
```

`sudo -l` liste pour Lucas les deux commandes de `consultation-journaux`, avec `systemd-journal` comme seul groupe d'exécution (pas d'utilisateur cible : il reste lui-même) ; pour toi, la règle `sudo-plateforme-admins` (`ALL`).

`admin` « inconnu » de SSSD : c'est exactement ce que `filter_users` garantit ; les nouvelles connexions `ssh admin@…` passent partout.

**Explications**

- **Mot de passe à usage unique** : l'hôte prouve une fois qu'il a le droit de s'inscrire, puis reçoit son keytab (`/etc/krb5.keytab`) ; ensuite il s'authentifie par Kerberos (le contrôle final obtient un ticket `host/…` avec le keytab). Rejouer le rôle ne génère rien (hôte déjà inscrit).
- **HBAC** est évalué par SSSD contre l'annuaire (avec un cache) à chaque connexion PAM ; il ne remplace ni l'authentification (certificat en E20) ni les droits (sudo) : il répond à « cette personne peut-elle **entrer** sur cette machine par ce service ? ».
- **`ipa hbactest --rules`** simule un jeu de règles sans toucher à l'annuaire : la preuve **avant** la coupure. `allow_systemd-user` reste active (service `systemd-user`, nécessaire aux sessions).
- **sudo par groupe d'exécution** : `sudo -g systemd-journal journalctl -u ssh` lit le journal avec le seul groupe qui y donne accès, sous l'identité de la personne : ni shell root par l'afficheur (`less !sh`), ni `--vacuum` (les fichiers appartiennent à root).
- **Le mot de passe demandé par `sudo`** est celui de l'annuaire (SSSD) : une session laissée ouverte ne donne pas root sans lui.

**Alternatives**

- `ipa-client-install` lancé à la main, ou le rôle `ipaclient` avec `ipaclient_use_otp: yes` : ce dernier se connecte à `ipaclient_servers[0]` **sous ce nom**, qu'Ansible doit savoir joindre tel quel ; générer le mot de passe sur l'hôte d'inventaire évite cette dépendance.
- *Kerberos pour SSH* (GSSAPI) au lieu des certificats : connexion sans rien à faire après un `kinit`, mais tickets de 24 h et postes à inscrire.
- *Règles sudo en fichiers* déployés par Ansible : plus simples, mais une seconde source des droits ; l'annuaire garde la vérité et la revue d'accès (E30) n'a qu'un endroit à lire.

**Pièges classiques**

- **Le compte local homonyme** (`admin`) : tout le monde enfermé dehors à la désactivation d'`allow_all`. C'est le piège de l'exercice.
- Désactiver `allow_all` avant d'avoir inscrit les hôtes visés par `hbac-support` : le module refuse un hôte inconnu.
- Supprimer `allow_all` au lieu de la désactiver : le retour arrière n'est plus un interrupteur.
- Inscrire `dns01` et `dns02` (ou `lb01` et `lb02`) dans la même vague : une erreur de PAM en coupe les deux.
- `sudo journalctl` en root : l'afficheur permet un shell root ; systemd active bien le mode sûr de l'afficheur sous sudo, mais la règle `systemctl status *` sans groupe d'exécution laisserait encore `systemctl status` devenir root.
- Le cache de SSSD : une personne retirée d'un groupe peut encore entrer quelques minutes ; `sss_cache -u <IDENTIFIANT>` (RB-242).

**En production chez MédiSphère**

Inscription intégrée à la création des VMs (cloud-init + mot de passe à usage unique généré par le pipeline d'OpenTofu) ; réplica FreeIPA sur PAR2 (ADR-0240) pour que l'authentification des machines ne dépende pas d'un seul serveur ; journaux `sssd` et `sudo` vers le locataire `audit` (M24-E26) ; revue des règles HBAC et sudo dans la revue d'accès mensuelle (M24-E30).

---

### M24-E20 — SSH par certificats courts après SSO

**Solution**

Fichiers : [`tofu/clients-step-ca.tf`](fichiers/M24-E20/identite/tofu/clients-step-ca.tf), [`group_vars/role_pki/step_ca.yml` (extrait)](fichiers/M24-E20/ansible/inventories/lab/group_vars/role_pki/step_ca.extrait.yml), rôle `ssh_ca_utilisateur` modifié : [gabarit](fichiers/M24-E20/ansible/roles/ssh_ca_utilisateur/templates/ssh-ca-utilisateur.conf.j2), [`defaults` (ajouts)](fichiers/M24-E20/ansible/roles/ssh_ca_utilisateur/defaults/main.extrait.yml), [`tasks` (ajouts)](fichiers/M24-E20/ansible/roles/ssh_ca_utilisateur/tasks/main.extrait.yml), [`principaux-annuaire`](fichiers/M24-E20/ansible/roles/ssh_ca_utilisateur/files/principaux-annuaire) ; [`group_vars/all/ssh_ca.yml` (ajout)](fichiers/M24-E20/ansible/inventories/lab/group_vars/all/ssh_ca.extrait.yml), [`group_vars/role_routeur/ssh_ca.yml`](fichiers/M24-E20/ansible/inventories/lab/group_vars/role_routeur/ssh_ca.yml) ; [`docs/socle/acces-ssh.md`](fichiers/M24-E20/medisphere/docs/socle/acces-ssh.md).

*A.* `GET /provisioners` est **public** et renvoie la configuration complète de chaque provisioner, `clientSecret` compris : la CLI de chaque personne en a besoin pour jouer le client OIDC. Un « secret » que tout le monde lit ne protège rien ; le client `step-ca` est donc **public**, avec PKCE (la CLI l'envoie) et une URI de retour exacte sur l'adresse de bouclage. Le provisioner : client `step-ca`, `clientSecret: ""` (permis), domaine `medisphere.internal`, `listenAddress: 127.0.0.1:10000`, 16 h au plus, **aucun** `admins`, et deux gabarits : SSH (un principal, `{{ toJson .Token.preferred_username }}`, `fail` si la revendication manque) et X.509 (toujours `fail`). Dans `group_vars`, les gabarits sont marqués `!unsafe` : sans cela, Ansible interpréterait `{{ … }}` comme du Jinja2. Avec les principaux par défaut, `lucas.martin@medisphere.internal` aurait reçu `lucasmartin` (points **retirés** par le nettoyage de step-ca), `lucas.martin` et l'adresse complète : un nom de compte inexistant, et un principal choisi par le format du courriel plutôt que par l'annuaire.

*B.* Sur un hôte inscrit, `03-ssh-ca-utilisateur.conf` gagne `AuthorizedPrincipalsCommand /usr/local/sbin/principaux-annuaire %u` et `AuthorizedPrincipalsCommandUser nobody`. sshd lit d'abord `/etc/ssh/principaux/<compte>` ; s'il n'y trouve rien (fichier absent pour une personne), il exécute la commande, qui imprime le nom du compte si `getent -s sss passwd` le résout, rien sinon. Le compte `admin` garde donc **seulement** ses principaux locaux (`admin`, `astreinte`), une personne seulement son propre nom.

```
admin@mon01:~$ sudo sshd -T | grep -E '^authorizedprincipals'
authorizedprincipalsfile /etc/ssh/principaux/%u
authorizedprincipalscommand /usr/local/sbin/principaux-annuaire %u
authorizedprincipalscommanduser nobody
admin@mon01:~$ /usr/local/sbin/principaux-annuaire lucas.martin; /usr/local/sbin/principaux-annuaire admin; echo "[fin]"
lucas.martin
[fin]
```

*C.*

```
poste:~$ ssh -L 10000:127.0.0.1:10000 adm01
admin@adm01:~$ eval "$(ssh-agent)" && step ssh login <MOI>@medisphere.internal --provisioner keycloak
admin@adm01:~$ ssh-add -L | grep cert | step ssh inspect
admin@adm01:~$ ssh <MOI>@mon01.par1.medisphere.internal 'id; pwd'
uid=1234500001(<MOI>) gid=1234500001(<MOI>) groupes=…,1234500003(plateforme-admins),1234500004(plateforme)
/home/<MOI>
```

La CLI affiche l'URL d'autorisation (ouverte dans le navigateur de ton poste par le tunnel), reçoit le code sur 127.0.0.1:10000, puis ajoute la clé et le certificat à l'agent. `step ssh inspect` montre un certificat d'**utilisateur**, identifiant de clé = ton adresse, **un seul** principal `<MOI>`, validité de 16 h, extensions `permit-pty`, `permit-port-forwarding`… (gabarit par défaut des extensions). Le dossier personnel est créé à la première connexion (`mkhomedir`). `ssh admin@mon01` avec ce seul certificat : refusé, le principal `<MOI>` n'est pas dans `/etc/ssh/principaux/admin` et la commande ne répond rien pour un compte local. Refus :

| Cas | Client | `journalctl -u ssh` de `mon01` | Étape |
|---|---|---|---|
| Certificat de 5 min expiré | `Permission denied (publickey)` | `… Certificate invalid: expired` | certificat |
| `julien.petit`, certificat valide | `Connection closed by … port 22` | `pam_sss(sshd:account): Access denied for user julien.petit: 6 (Permission denied)` | compte (HBAC) |

*D.* `ms-ssh-cert` est **gardé pour le bris de glace** : indépendant de Keycloak et de l'annuaire, il est la seule façon d'entrer sous `admin` par certificat si l'un des deux tombe ; son mot de passe passe au Vault `critique`, son usage est journalisé et alerté (E26, E28).

**Explications**

- **Trois verrous, dans l'ordre** : la CA signe seulement après SSO (et OTP, E21) et seulement le principal de l'annuaire ; sshd n'accepte ce principal que pour **le** compte du même nom ; PAM (SSSD, HBAC) décide si ce compte peut entrer **ici**.
- **Pourquoi pas de révocation** : sshd ne consulte pas de liste de révocation chez nous (`RevokedKeys` serait à distribuer partout) ; la durée courte (16 h) et le verrou de l'annuaire (RB-242) en tiennent lieu.
- **`nobody`** pour la commande : elle ne lit que NSS ; l'exécuter en root donnerait à un défaut du script les droits de root.

**Alternatives**

- *Principaux tirés des groupes* (`.Token.groups`) avec des comptes partagés par groupe (`plateforme`) : moins de comptes, mais retour aux comptes partagés que le module élimine (imputabilité HDS).
- *Teleport* (bastion, enregistrement des sessions, certificats courts) : licence CE interdite chez MédiSphère (M24-E32) ; à compiler soi-même ou en Enterprise.
- *`AuthorizedKeysCommand`* et clés publiques dans l'annuaire (`sss_ssh_authorizedkeys`) : clés éternelles, ce que Sophie refuse.

**Pièges classiques**

- Principaux par défaut (points retirés) : « Certificate does not contain an authorized principal ».
- `listenAddress` absent : port aléatoire, URI de retour refusée par Keycloak (`Invalid parameter: redirect_uri`).
- Accolades du gabarit interprétées par Ansible (erreur de gabarit ou gabarit vide dans `ca.json`).
- `AuthorizedPrincipalsCommand` sans `AuthorizedPrincipalsCommandUser` : sshd refuse de démarrer ; le rôle valide par `sshd -t` avant de poser, ne retire jamais la session ouverte.
- Un vieux certificat `admin` dans l'agent : présenté avant le bon, il consomme un des `MaxAuthTries` (M06-E20) ; `ssh-add -D` avant les essais.

**En production chez MédiSphère**

CA SSH d'utilisateurs sous HSM (promesse du M06) ; extension `permit-port-forwarding` seulement pour `plateforme-admins` (gabarit et `.Token.groups`) ; alerte sur toute signature par le provisioner `admin` ; durée réduite à 8 h pour les administrateurs ; principaux par groupe pour les comptes de rôle si un jour il en faut (jamais pour des personnes).

---

### M24-E21 — Authentification forte : OTP obligatoire, WebAuthn en option

**Solution**

Fichier : [`tofu/flux.tf`](fichiers/M24-E21/identite/tofu/flux.tf).

*A.* `browser` : *Cookie* (`ALTERNATIVE`), *Identity Provider Redirector* (`ALTERNATIVE`), sous-flux *forms* (`ALTERNATIVE`) avec *Username Password Form* (`REQUIRED`) et un sous-flux conditionnel de second facteur (`CONDITIONAL` : *Condition - user configured*, puis l'OTP). Aucune condition ne porte sur un groupe : on crée un rôle de royaume `second-facteur-obligatoire`, attribué aux **groupes** `plateforme-admins` et `securite` ; leurs membres l'héritent, et *Condition - user role* en tient compte. Les membres de ces groupes viennent de l'annuaire (`READ_ONLY`) ; les rôles d'un groupe, eux, sont stockés dans Keycloak et se gèrent en code. `copy_from` créerait des sous-flux et exécutions qui ne seraient décrits nulle part : le plan ne les verrait pas, on ne pourrait pas les relire en MR.

*B.* Le plan de la MR : 19 objets (le rôle, deux attributions aux groupes, le flux, trois sous-flux, sept exécutions, deux configurations de condition, deux actions requises, la liaison). Seule la **liaison** (`keycloak_authentication_bindings`) change le comportement pour tout le monde ; elle dépend explicitement de toutes les exécutions, pour qu'un flux à moitié construit ne soit jamais lié.

Essais (fenêtres privées, console de compte) : `lucas.martin` entre avec son mot de passe seul ; toi, après le mot de passe, l'écran *Mobile Authenticator Setup* (QR code) puis, aux connexions suivantes, le code. Dans le journal de `idp01` (`journalctl -u keycloak`, journaux JSON) ou dans *Events* si l'enregistrement des événements est activé (E26) : `UPDATE_TOTP` puis `LOGIN` pour toi, `LOGIN` seul pour Lucas.

*C.* `kubectl oidc-login clean` puis `kubectl get nodes` : le navigateur (tunnel d'E16) affiche le formulaire, puis l'OTP. Ensuite, aucun code tant que kubelogin peut **rafraîchir** son jeton : la session SSO de Keycloak (30 min d'inactivité, 10 h au plus) borne cette durée. `step ssh login` : même chose, un code par certificat de 16 h (sauf session SSO encore ouverte dans le navigateur : le cookie suffit, pas de nouveau code). Ce qui n'est **pas** concerné : `wb-checks`, `svc-tofu-keycloak`, `svc-synchro-identite` et tous les clients en `client_credentials` (pas de navigateur) ; `kc-secours` et `<MOI>-admin` (royaume `master`) ; les comptes locaux de bris de glace des services. Acceptable parce que ce sont des **comptes de service** à secret fort rangé au Vault (pas de personne derrière un mot de passe devinable) et des comptes de **secours** dont l'usage est rare, journalisé et alerté (E28) ; `kc-secours` sans OTP est voulu (E04) : il doit marcher le jour où le téléphone de l'administrateur est perdu.

**Explications**

- **Exigences** : dans un sous-flux `CONDITIONAL`, si toutes les conditions `REQUIRED` sont vraies, les autres exécutions s'appliquent ; sinon le sous-flux est sauté. `OTP Form` en `REQUIRED` impose l'action *Configure OTP* à qui n'a pas d'OTP.
- **WebAuthn volontaire** : second sous-flux, condition *user role* **inversée** (`negate: true`) **et** *user configured* : seulement les autres personnes, et seulement celles qui ont enregistré une clé. Un administrateur qui enregistre une clé n'est pas dispensé d'OTP (choix simple ; un sous-flux `ALTERNATIVE` OTP-ou-WebAuthn est possible, à tester avec l'enrôlement).
- **Les *Direct Access Grants*** contournent le flux de navigateur : désactivés sur tous nos clients (E05-E20) ; le client intégré `admin-cli` du royaume les garde, mais son flux `direct grant` par défaut exige l'OTP de qui en a un (traité au durcissement, E27).

**Alternatives**

- *Niveaux d'authentification* (*LoA*, revendication `acr`) : l'OTP exigé **par service** (Proxmox, Argo CD) plutôt que par personne ; plus fin, plus complexe à tester.
- *OTP de FreeIPA* (jetons TOTP de l'annuaire) : le second facteur vivrait dans l'annuaire, utilisable aussi par `sudo` et Kerberos ; mais Keycloak en fédération LDAP ne sait pas le demander séparément du mot de passe.
- *Passkeys sans mot de passe* (flux `webauthn-passwordless`, 26.x) : la cible à terme pour les administrateurs.

**Pièges classiques**

- Lier le flux avant d'en avoir créé les exécutions : plus personne ne se connecte.
- Attribuer le rôle aux **personnes** plutôt qu'aux groupes : un départ ou une arrivée dans `plateforme-admins` ne suit plus l'annuaire.
- Une politique OTP en SHA-256 ou à 8 chiffres : refusée par certaines applications mobiles ; garder les valeurs par défaut.
- Imposer *Configure OTP* comme action par défaut (`default_action = true`) : tout le monde, y compris les comptes de service qui ont un utilisateur, est concerné.
- Oublier que l'OTP ne protège pas un **jeton** volé : durées courtes (E27) et révocation de session (RB-242).

**En production chez MédiSphère**

Passkeys pour les administrateurs, codes de récupération imprimés et rangés au coffre, procédure de perte de téléphone (RB-242), alerte sur `REMOVE_TOTP` et sur les échecs d'OTP répétés (E26), OTP étendu à tout le personnel quand le support est prêt.

---

### M24-E22 — Revue : la configuration Keycloak du stagiaire

**Solution**

Revue modèle : [`revue-mr41.md`](fichiers/M24-E22/revue-mr41.md). Les défauts, du plus grave au moins grave :

| # | Fichier : ligne | Défaut | Gravité |
|---|---|---|---|
| 1 | `royaume-recette.tf:13`, `:78-80` | inscription libre **et** groupe par défaut `plateforme-admins` : tout inconnu est administrateur | critique |
| 2 | `clients-recette.tf:52-60`, `:103-112` | `groups` tiré d'un attribut que **l'utilisateur** modifie (élévation de privilèges en libre-service) | critique |
| 3 | `royaume-recette.tf:38`, `clients-recette.tf:10`, `:28` | secrets en clair dans Git, dont le mot de passe du compte de **production** `svc-keycloak` (à faire tourner) | critique |
| 4 | `royaume-recette.tf:48-49` | fédération `WRITABLE` + `sync_registrations` : écriture dans l'annuaire de production | majeure |
| 5 | `royaume-recette.tf:21-23` | jeton d'accès de 24 h, sessions de 30 jours | majeure |
| 6 | `clients-recette.tf:17-18` | URI de retour et origines `*` | majeure |
| 7 | `clients-recette.tf:13` | flux implicite | majeure |
| 8 | `clients-recette.tf:8-10` | client public avec un secret (ignoré, plan jamais vide) et sans PKCE | majeure |
| 9 | `clients-recette.tf:32` | *Direct Access Grants* (mot de passe dans un script, contourne l'OTP) | majeure |
| 10 | `royaume-recette.tf:18` | `ssl_required = "none"` | majeure |
| 11 | `clients-recette.tf:118`, `:124` | portées par défaut sans `basic` : plus de `sub` dans les jetons | mineure |
| 12 | `clients-recette.tf:40` | `full_scope_allowed = true` | mineure |
| 13 | `clients-recette.tf:70-101` | courriel et identifiant modifiables par l'utilisateur, sans vérification | mineure |

Manquent aussi : protection contre la force brute, OTP des administrateurs, filtres de la fédération (`admin` de FreeIPA et groupes internes importés). Conclusion : **fusion refusée** ; un royaume de recette, oui, mais **sans** l'annuaire de production (comptes d'essai locaux créés par OpenTofu, groupes aux mêmes noms).

**Explications**

Le « ça marche » de Lucas est vrai : chaque défaut **facilite** quelque chose (s'inscrire, se donner des droits, tester avec un mot de passe, ne pas gérer d'URI). La revue consiste à demander, pour chaque attribut, « qui peut s'en servir, et contre qui ? ». Les trois critiques partagent une cause : la recette a été pensée comme un bac à sable isolé, alors qu'elle partage l'annuaire, les noms de groupes et le réseau de la production.

**Alternatives**

Revue outillée : `tofu show -json plan.out` et une règle `jq` ou Conftest qui refuse en CI les motifs connus (`valid_redirect_uris` contenant `*`, `implicit_flow_enabled = true`, `direct_access_grants_enabled = true`, `edit_mode != READ_ONLY`, secret littéral dans un `.tf` : aussi le travail de Gitleaks, M19).

**Pièges classiques**

- Ne relever que ce qui est **écrit** : les défauts par omission (portées par défaut, durées, force brute) sont aussi graves.
- Classer le secret en clair « mineur parce que c'est la recette » : c'est le compte de production.
- Proposer « mettre `*.medisphere.internal` » pour les URI : toujours un joker, et tout hôte du domaine (une recette de branche compromise) reçoit les codes.

**En production chez MédiSphère**

Règle d'approbation : toute MR qui touche `tofu/` de `plateforme/identite` est relue par Sophie ; contrôle automatique des motifs interdits dans le pipeline ; un royaume de recette jetable recréé chaque semaine par OpenTofu.

---

### M24-E23 — Arrivées, mobilités et départs

**Solution**

Runbooks modèles : [`RB-241-arrivee.md`](fichiers/M24-E23/medisphere/docs/securite/identite/runbooks/RB-241-arrivee.md), [`RB-242-depart-mobilite.md`](fichiers/M24-E23/medisphere/docs/securite/identite/runbooks/RB-242-depart-mobilite.md).

Tableau de l'étape 1 (ce que le SSO coupe, ce qu'il faut couper) :

| Service | Droits obtenus par | Après désactivation dans l'annuaire, reste actif | Pendant | Comment couper |
|---|---|---|---|---|
| Keycloak (tous services) | annuaire (liaison LDAP) | sessions SSO, jetons de rafraîchissement | 30 min d'inactivité, 10 h au plus | *Sessions* → *Sign out* (API `users/{id}/logout`) |
| GitLab | OIDC + `synchro-gitlab.py` | session web, jetons personnels, clés SSH, jetons de déploiement créés | jetons : jusqu'à leur expiration | bloquer le compte, révoquer jetons et clés |
| Grafana | `groups` → rôles | session Grafana | jusqu'au rafraîchissement OAuth | `logout` et `disable` par l'API d'administration |
| Argo CD | `groups` → `policy.csv` | jeton OIDC en session | ≤ 5 min (rafraîchissement refusé) | sessions Keycloak |
| Harbor | `groups` → membres | secret CLI (`docker login`), robots qu'elle connaît | secret CLI : tant que le jeton se rafraîchit | supprimer l'utilisateur ; renouveler les robots qu'elle connaissait |
| Proxmox VE | `groups` → ACL | ticket PVE, jetons d'API personnels | ticket : 2 h ; jetons : sans fin | `--enable 0`, `token remove` |
| PBS | ACL **par personne** | ACL, ticket | sans fin pour l'ACL | `user update --enable false`, ACL retirées |
| NetBox | OIDC + groupe local | session, jetons d'API | jetons : sans fin | `is_active: false`, jetons supprimés |
| Kubernetes | `groups` → RBAC | jeton OIDC déjà émis | ≤ 5 min | sessions Keycloak (rien d'autre) |
| Hubble, Pyroscope, Mailpit | `groups` → OAuth2 Proxy | cookie de session | ≤ 5 min (`cookie_refresh`) | sessions Keycloak |
| SSH | certificat + HBAC | sessions ouvertes ; certificat (16 h) | tant que la session est ouverte | `loginctl terminate-user` ; le compte est refusé (SSSD) |
| sudo | règles de l'annuaire | cache SSSD | quelques minutes | `sss_cache -u` |

Points attendus dans RB-242 : la **désactivation à la main** dans l'annuaire comme première étape d'un départ immédiat (seule exception au « tout en code », régularisée par MR dans l'heure), parce que le job protégé et la relecture prennent du temps ; l'ordre « nouvelles entrées → sessions SSO → jetons hors SSO → sessions ouvertes → caches → secrets connus » ; pour la mobilité, retirer **et** ajouter dans la même MR, puis fermer les sessions pour que les **anciens** groupes disparaissent des jetons ; un contrôle final fait par une autre personne, avec les requêtes Loki du locataire `audit`.

**Explications**

Le SSO déplace le problème : il rend la coupure **possible** en un point (l'annuaire) pour tout ce qui passe par lui, mais tout ce qui a été délivré avant (session, jeton, certificat) et tout ce qui ne passe pas par lui (jetons d'API, clés, comptes locaux, ACL par personne) a sa propre durée de vie. Un runbook de départ est d'abord l'**inventaire** de ces durées de vie. C'est aussi ce que la revue d'accès (E30) vérifie chaque mois, et ce que la démonstration du mini-projet (E46) chronomètre.

**Alternatives**

- Automatiser le départ immédiat (job manuel protégé qui enchaîne Keycloak, GitLab, Grafana, Proxmox, NetBox par leurs API et produit le rapport de preuve) : moins d'erreurs sous stress ; c'est l'objet du mini-projet.
- SCIM (Keycloak 26.8 l'active) pour propager les désactivations aux services qui le prennent en charge : peu de nos outils le font en édition libre.

**Pièges classiques**

- Supprimer la personne au lieu de la désactiver : l'identifiant pourra être réattribué, les journaux perdent leur sens, et Keycloak oublie son lien.
- Désactiver dans Keycloak seulement : l'annuaire laisse encore entrer en SSH et sudo.
- Oublier les jetons personnels de GitLab et Proxmox : ils ne passent jamais par le SSO.
- Mobilité par ajout seul : cumul des droits de l'ancienne et de la nouvelle équipe.
- Une preuve qui contient un secret (jeton copié dans le ticket).

**En production chez MédiSphère**

Déclenchement automatique depuis l'outil RH (fin de contrat → ticket → job), alerte si une connexion réussie d'une personne désactivée apparaît dans le locataire `audit` (E26), revue mensuelle des comptes et jetons (E30), et exercice de départ chronométré une fois par an avec Sophie.
