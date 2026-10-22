### M24-E17 — RBAC Kubernetes par groupes de l'annuaire  `LAB` `★★`

> **Ticket SEC-2517** — *De : Sophie Laurent* — *Copie : Karim Benali, Julien Petit*
> Depuis E16, `kubectl` sait dire **qui** se connecte. Il ne sait pas encore ce qu'on a le droit de faire : à part toi, personne n'a de droit, et les liaisons du M14 visent toujours les groupes de vos certificats de sept jours. Je veux que les droits du cluster découlent des groupes de l'annuaire, exactement comme dans le modèle d'autorisation d'E10, sans un seul nom de personne dans le RBAC. Et je veux qu'à la fin de la semaine plus aucun certificat personnel ne donne le moindre droit : un certificat ne se révoque pas, une liaison si.

**Objectifs pédagogiques**
- Traduire un modèle d'autorisation en liaisons RBAC par groupes, préfixés, sans liaison nominative.
- Vérifier des droits sans être la personne : usurpation d'identité (`--as`, `--as-group`), `kubectl auth can-i`, `kubectl auth whoami`.
- Basculer l'exploitation quotidienne sur OIDC et retirer les droits des certificats personnels, sans s'enfermer dehors.

**Prérequis** : M24-E16 (authentification structurée, contexte `k8s-par1-oidc`), M24-E10 (modèle d'autorisation) ; M14-E06 et M14-E11 (rôles agrégés, matrice de droits).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Identités vues par kube-apiserver (E16) | utilisateur `oidc:<preferred_username>` (ex. `oidc:lucas.martin`), groupes `oidc:<groupe de l'annuaire>` (ex. `oidc:plateforme`), plus `system:authenticated` |
| RBAC existant (M14) | `plateforme/k8s/rbac/` : ClusterRoles agrégées `medisphere-lecture`, `medisphere-developpeur`, `medisphere-lecture-charges`, `medisphere-lecture-cluster`, `medisphere-secrets-edition` ; liaisons aux groupes de **certificats** `medisphere:plateforme-admins`, `medisphere:lecture`, `medisphere:mediagenda-devs`, `medisphere:medidoc-devs` ; appliqué par `task appliquer` (couche de base, hors Argo CD) |
| Fichier à écrire | `rbac/oidc.yaml` de `plateforme/k8s` ; liaisons nommées **`oidc-*`** |
| Droits attendus | `oidc:plateforme-admins` → `cluster-admin` ; `oidc:plateforme` → tout lire sauf les Secrets (y compris les objets des composants : Argo CD, supervision, Gateway…) et écrire dans `wb-essais` ; `oidc:mediagenda` → `edit` dans `mediagenda-dev`, `view` dans `mediagenda-dev`, `-recette` et `-prod` ; `oidc:medidoc` → `view` dans `medidoc-dev` et `medidoc-recette` ; `oidc:support` → lecture sans Secrets (comme `medisphere:lecture`) ; `oidc:securite` → ClusterRole `medisphere-securite` : lecture sans Secrets **et** lecture du RBAC ; `oidc:direction` → rien (modèle d'autorisation d'E10) |
| Contextes de `~/.kube/config` | `k8s-par1` (ton certificat personnel de 7 jours, M14) ; `k8s-par1-oidc` (utilisateur `oidc`, kubelogin, E16). De nombreux outils de `plateforme/k8s` (Taskfile, Helmfile, `outils/*.sh`) visent **le nom** `k8s-par1` |
| Bris de glace | `admin.conf` (Ansible Vault `critique`, M14) : groupe `kubeadm:cluster-admins`, indépendant de Keycloak et de ce fichier |
| Brouillons | `~/m24/e17/` |

**Travail demandé**

*A. Inventaire*

1. Liste toutes les liaisons qui visent un groupe ou un utilisateur **humain** (ni compte de service, ni `system:*`) :
   ```
   admin@adm01:~$ kubectl get clusterrolebindings,rolebindings -A -o json | jq -r '.items[]
   >   | . as $l | .subjects[]? | select(.kind != "ServiceAccount" and (.name | startswith("system:") | not))
   >   | "\($l.kind)\t\($l.metadata.namespace // "-")\t\($l.metadata.name)\t\(.kind)\t\(.name)\t\($l.roleRef.name)"' | column -t
   ```
   Note dans `~/m24/e17/inventaire.md` chaque liaison et la ligne du modèle d'autorisation (E10) qui lui correspond. Y a-t-il des droits du M14 que le modèle ne prévoit plus, ou l'inverse ?

*B. Les liaisons par groupes*

2. Écris `rbac/oidc.yaml` selon le contexte technique. Réutilise les ClusterRoles du M14 ; crée seulement ce qui manque (une ClusterRole agrégée pour l'équipe Plateforme, une pour la Sécurité qui ajoute la lecture du RBAC). Contraintes : aucun sujet de type `User`, aucun accès aux Secrets hors de `wb-essais` et de `mediagenda-dev`, aucun groupe sans le préfixe `oidc:`. Pourquoi lire « tous les groupes d'API sauf le cœur » ne donne-t-il pas accès aux Secrets ?
3. MR sur `plateforme/k8s`, relecture, fusion, puis application par la procédure habituelle (`task valider`, `task diff`, `task appliquer`).

*C. Vérifier sans être la personne*

4. Rejoue l'identité de quelqu'un d'autre ; regarde d'abord ce que voit kube-apiserver, puis ce qu'il autorise :
   ```
   admin@adm01:~$ kubectl auth whoami --as=oidc:julien.petit --as-group=oidc:mediagenda
   admin@adm01:~$ kubectl auth can-i --list -n mediagenda-dev --as=oidc:julien.petit --as-group=oidc:mediagenda
   admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-prod --as=oidc:julien.petit --as-group=oidc:mediagenda
   ```
   Pourquoi faut-il donner **les deux** options ? Qui a le droit d'usurper une identité, et pourquoi ce droit est-il lui-même sensible ?
5. Écris `outils/matrice-droits-oidc.sh` dans `plateforme/k8s` sur le modèle de `matrice-droits.sh` du M14-E11 : une trentaine de cas (au moins trois par groupe, dont des refus), sortie `OK`/`ÉCART`, code 1 au moindre écart, contexte en paramètre. Ajoute un cas pour un groupe nommé `system:masters` dans l'annuaire : que devient-il dans Kubernetes ?
6. Un vrai jeton, enfin. Avec **ton** identité, `kubectl --context k8s-par1-oidc auth whoami`. Puis connecte-toi comme `lucas.martin` (mot de passe d'E03) **sans toucher à ton propre cache de jetons** : copie de ton kubeconfig dans `~/m24/e17/essai.kubeconfig`, dont l'utilisateur `oidc` ajoute à ses arguments kubelogin un dossier de cache dédié (cherche l'option dans `kubectl oidc-login get-token --help`), fenêtre privée du navigateur (méthode d'E16). Avec ce fichier : `auth whoami`, `get pods -n kube-system`, `get secrets -n kube-system`, `create configmap essai -n wb-essais`. Supprime ensuite le fichier, le dossier de cache et la ConfigMap.

*D. La bascule*

> ⚠️ **Attention** : à partir de l'étape 7, ton certificat personnel ne te donne plus aucun droit. Avant de commencer : (1) `kubectl --context k8s-par1-oidc auth can-i '*' '*'` répond `yes` ; (2) le bris de glace marche **maintenant** : extrais `admin.conf` du Vault dans un fichier temporaire en 600 hors de tout dépôt, `kubectl --kubeconfig <FICHIER> auth whoami` (groupe `kubeadm:cluster-admins`), puis supprime le fichier. Retour arrière si tu perds l'accès : `admin.conf` du Vault, puis `kubectl apply` des fichiers du M14 retirés (ils restent dans l'historique Git).

7. Fais pointer le contexte **`k8s-par1`** vers l'utilisateur `oidc` (tous les outils qui visent ce nom passent ainsi à OIDC sans modification), fais de `k8s-par1-oidc` le contexte courant, et retire de `~/.kube/config` l'utilisateur à certificat (sauvegarde d'abord le fichier, en 600). Relance `task diff` et `helmfile -e par1 diff` : sous quelle identité tournent-ils maintenant ?
8. Retire les liaisons aux groupes de certificats (`medisphere:*`) : `kubectl delete -f` des fichiers concernés, **puis** leur suppression dans une MR (pourquoi dans cet ordre ? que ferait `task appliquer` seul ?). Retire aussi les scripts qui émettaient des certificats personnels. Rejoue ta matrice.
9. Mets à jour `docs/kubernetes/acces.md` de `plateforme/medisphere` : identités humaines (OIDC), groupes et droits (renvoi au modèle d'autorisation), bris de glace, ce qui a disparu.

**Critères de réussite**
- [ ] `rbac/oidc.yaml` est sur `main` de `plateforme/k8s` et appliqué ; chaque groupe de l'annuaire a exactement les droits du contexte technique (contrôlés par SubjectAccessReview).
- [ ] Aucune liaison ne vise un utilisateur nommé, ni un groupe `medisphere:*` de certificat ; toutes les liaisons des personnes s'appellent `oidc-*`.
- [ ] `outils/matrice-droits-oidc.sh` est sur `main` et passe sans écart.
- [ ] Dans ton `~/.kube/config`, le contexte courant est `k8s-par1-oidc`, le contexte `k8s-par1` utilise le même utilisateur OIDC, plus aucun utilisateur n'a de certificat client.
- [ ] `docs/kubernetes/acces.md` décrit les identités OIDC et le bris de glace.

**Vérification** : `lab/bin/check 24 17`

<details><summary>Indice 1</summary>

RBAC n'a pas de « sauf » : pour « tout sauf les Secrets », on énumère. Les Secrets sont dans le groupe d'API du cœur (`""`) ; un `*` sur une liste explicite d'autres groupes (`apps`, `argoproj.io`, `monitoring.coreos.com`…) ne les touche donc pas. C'est ce que fait déjà `wb-checks-base` (M14-E06). Une ClusterRole agrégée évite de recopier ce que `medisphere-lecture` sait déjà.
</details>

<details><summary>Indice 2</summary>

Avec `--as` seul, kube-apiserver ne connaît que l'utilisateur, sans ses groupes : tes liaisons par groupe ne s'appliquent pas, et tout est refusé. kubelogin range ses jetons dans un dossier de cache dont le nom de fichier dépend de l'émetteur et du client : deux personnes sur le même compte Unix partagent ce cache, sauf option contraire.
</details>

<details><summary>Indice 3</summary>

`task appliquer` applique ce qui est dans le dépôt ; il ne supprime pas ce qui n'y est plus (pas d'élagage). Un fichier retiré de Git laisse ses objets dans le cluster. `kubectl config set-context <NOM> --user=<UTILISATEUR>` change l'utilisateur d'un contexte existant.
</details>

**Pour aller plus loin** (facultatif) : lance la matrice dans le pipeline de `plateforme/k8s` à chaque MR qui touche `rbac/`, avec un compte de service qui n'a que le droit de créer des `SubjectAccessReview` (pas `impersonate`). [Kubernetes : *Using RBAC Authorization*](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [*User impersonation*](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation) · [`kubectl auth whoami`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_whoami/)

---

### M24-E18 — OAuth2 Proxy devant Hubble, Pyroscope et Mailpit  `LAB` `★★`

> **Ticket PLAT-2518** — *De : Karim Benali* — *Copie : Sophie Laurent, Nadia Roussel*
> Trois interfaces ne savent pas faire de SSO : Hubble UI (protégée seulement par le réseau depuis le M15), Pyroscope (pas publiée du tout, on passe par Grafana) et Mailpit (un mot de passe partagé). Mets OAuth2 Proxy devant les trois. Une seule application cliente dans Keycloak, des groupes autorisés par interface : Hubble pour la Plateforme et le support, Pyroscope en plus pour les équipes de développement, Mailpit comme Hubble. L'API de Mailpit doit rester joignable par les vérifications, en authentification basique, depuis MGMT seulement. Version 7.15.5 au moins : Sophie a lu les deux avis critiques.

**Objectifs pédagogiques**
- Placer un mandataire d'authentification (*authentication proxy*) devant une application qui n'a pas de SSO, dans le cluster et sur une VM.
- Régler un client OIDC partagé par plusieurs instances : URI de retour exactes, PKCE, portées, groupes autorisés par instance.
- Protéger les cookies de session et la confiance dans les en-têtes `X-Forwarded-*`.
- Fermer les chemins de contournement (route directe, politique réseau, port de l'application).

**Prérequis** : M24-E08 (OpenTofu), M24-E10 ; M15-E26 (Hubble UI, `gw-par1`), M20-E13 (`charts-miroir`), M23-E14 (Pyroscope), M19-E03 (Mailpit).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Version | OAuth2 Proxy **7.15.5** ; chart `oauth2-proxy/oauth2-proxy` **10.7.1** (dépôt `https://oauth2-proxy.github.io/manifests`), image `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5` par le cache Harbor `registry.par1.medisphere.internal/quay` |
| Client Keycloak | `oauth2-proxy` (confidentiel, flux standard seul, PKCE `S256`), fichier `tofu/clients-oauth2-proxy.tf` ; URI de retour `https://hubble.apps.par1.medisphere.internal/oauth2/callback`, `https://pyroscope.apps.par1.medisphere.internal/oauth2/callback`, `https://mon01.par1.medisphere.internal:8443/oauth2/callback` ; secret en Vault `critique` (`secrets/identite.yml` de `plateforme/ansible`, `keycloak_secrets_clients.oauth2_proxy`, rangé par `outils/ranger-secret-client.sh`, E11) |
| Dans le cluster | espace **`oauth2-proxy`** (créé par `plateforme/k8s`, PSA `restricted`, étiquette d'exposition de `gw-par1`) ; Application Argo CD **`oauth2-proxy`** (`plateforme/gitops`) avec **deux** releases : `oauth2-proxy-hubble` (amont `hubble-ui.kube-system:80`) et `oauth2-proxy-pyroscope` (amont `pyroscope.traces:4040`) ; valeurs et manifestes dans `oauth2-proxy/` de **`plateforme/identite`** ; Secret **`oauth2-proxy-oidc`** (clés `client-id`, `client-secret`, `cookie-secret`) par `outils/secrets-k8s.sh` |
| Groupes autorisés | Hubble : `plateforme-admins`, `plateforme`, `support` ; Pyroscope : les mêmes + `mediagenda`, `medidoc` ; Mailpit : `plateforme-admins`, `plateforme`, `support` |
| Routes | `hubble.apps.par1.medisphere.internal` (route actuelle `hubble-ui` dans `passerelles`, M15-E26, à remplacer) ; `pyroscope.apps.par1.medisphere.internal` (nouvelle) ; certificat joker de `gw-par1` |
| Sur `mon01` | rôle **`oauth2_proxy`** (nouveau, `plateforme/ansible`) : binaire épinglé par empreinte, unité **`oauth2-proxy-mailpit.service`**, HTTPS sur **8443** (certificat ACME), amont l'interface de Mailpit sur 8025 (HTTPS) ; Mailpit garde son authentification basique sur 8025 (compte `wb-checks` des vérifications) |
| Flux | `K8S_TRAV` et `mon01` → VIP `lb` 10.10.70.200:443 (`sso`) : déjà dans la matrice du bloc F ; `mon01` 8443 depuis MGMT et le VPN ; `mon01` 8025 depuis MGMT seulement |
| Réseau des pods | 10.240.0.0/16 (Envoy de la Gateway Cilium compris) |

**Travail demandé**

*A. Lire avant d'installer*

1. Lis la documentation d'OAuth2 Proxy : fournisseur `keycloak-oidc`, options de session et de cookie, configuration « alpha » (structurée), et les deux avis de sécurité critiques corrigés en 7.15.5. Note dans `~/m24/e18/notes.md` : les portées que `keycloak-oidc` demande par défaut (et ce que Keycloak répondra, sachant que notre portée de groupes s'appelle `groupes`), ce que garantit le préfixe de cookie `__Host-`, le rôle de `cookie_refresh`, ce que `reverse_proxy` fait croire et pourquoi 7.15.5 ajoute une liste de mandataires de confiance.

*B. Le client et le cluster*

2. Écris `tofu/clients-oauth2-proxy.tf` ; MR, plan, apply. Range le secret du client dans le Vault (`secrets/identite.yml`), sans l'afficher.
3. Ajoute le chart à `plateforme/charts-miroir` (empreinte relevée par toi) ; crée l'espace `oauth2-proxy` dans `plateforme/k8s` ; étends le composant `oauth2-proxy` de `secrets-k8s.sh` (secret du cookie : 32 caractères aléatoires, `openssl rand -hex 16`).
4. Écris les valeurs (communes, Hubble, Pyroscope) et les manifestes (racine MédiSphère pour joindre `sso`, politique d'entrée Cilium des pods d'OAuth2 Proxy) dans `plateforme/identite/oauth2-proxy/`, et l'Application dans `plateforme/gitops` ; adapte l'AppProject `plateforme`. Exigences : options **non secrètes** dans le fichier de configuration du chart, secrets par le Secret seulement ; cookie `__Host-` ; PKCE ; groupes autorisés par release ; X-Forwarded-* crus seulement depuis le réseau des pods ; deux réplicas ; HTTPRoute rendue par le chart.
5. Synchronise. Pour Pyroscope, ajoute à la politique `traces-pyroscope` (`plateforme/observabilite`) l'entrée depuis `oauth2-proxy-pyroscope`. Essaie `https://pyroscope.apps…` dans une fenêtre privée en `lucas.martin`.
6. Pour Hubble, la route du M15 est toujours là. Que se passe-t-il quand deux HTTPRoute réclament le même nom et le même chemin ? Remplace l'accès : politique `hubble-ui-entree` qui n'accepte plus que `oauth2-proxy-hubble`, suppression de la route et du ReferenceGrant du M15 (`kubectl delete -f`, puis MR). Essaie en `lucas.martin`, puis avec une personne d'un groupe non autorisé (`julien.petit`, si tu lui as donné un mot de passe) : quel code, quelle page ?

*C. Mailpit sur `mon01`*

> ⚠️ **Attention** : tu vas retirer le compte personnel de Mailpit et fermer 8025 au VPN. Garde une session SSH ouverte sur `mon01` et vérifie **avant** que `wb-checks` lit l'API depuis `adm01` (`lab/bin/check 19 03`). Retour arrière : remettre `host_vars/mon01/mailpit.yml` et `pare_feu_local.yml` de `main~1` et rejouer `playbooks/supervision.yml`.

7. Écris le rôle `oauth2_proxy` : archive vérifiée par empreinte avant extraction, binaire non modifiable par le service, une instance = une unité systemd durcie, secrets dans des fichiers 0640 lus par OAuth2 Proxy (jamais en argument, jamais dans l'unité), configuration structurée pour le serveur TLS, l'amont et le fournisseur. Mailpit exigeant son authentification basique, OAuth2 Proxy présentera à l'amont un compte technique `sso` de Mailpit, **après** avoir authentifié et autorisé la personne : trouve dans la documentation de la configuration structurée comment injecter un en-tête dont la valeur vient d'un fichier, et comment empêcher qu'un en-tête `Authorization` envoyé par le navigateur arrive à Mailpit.
8. Inventaire de `mon01` : certificat ACME de l'instance, compte `sso` dans Mailpit (et plus de compte de personne), nom `mon01…:8443` dans les noms autorisés de Mailpit (pourquoi ?), règles de `pare_feu_local`. Applique par le pipeline protégé.
9. Contrôle depuis `adm01` :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://mon01.par1.medisphere.internal:8443/ | sed 's/state=[^&]*/state=…/'
   admin@adm01:~$ lab/bin/check 19 03
   ```

**Critères de réussite**
- [ ] Le client `oauth2-proxy` est confidentiel, en flux standard seul, PKCE `S256`, avec exactement les trois URI de retour.
- [ ] Dans `oauth2-proxy`, les deux releases (7.15.5) sont disponibles, à deux réplicas, synchronisées par Argo CD ; chacune n'autorise que ses groupes.
- [ ] `https://hubble.apps…`, `https://pyroscope.apps…` et `https://mon01…:8443` renvoient tout visiteur sans session vers le royaume `medisphere` (client `oauth2-proxy`, PKCE) ; plus aucune route ne mène directement à `hubble-ui`.
- [ ] Sur `mon01`, `oauth2-proxy-mailpit.service` est actif ; l'API de Mailpit répond toujours à `wb-checks` sur 8025 depuis MGMT.

**Vérification** : `lab/bin/check 24 18`

<details><summary>Indice 1</summary>

Keycloak refuse une demande d'autorisation qui contient une portée qu'il ne connaît pas (`invalid_scope`). Une portée **par défaut** du royaume s'applique sans être demandée : il suffit de ne pas demander celle qui n'existe pas.
</details>

<details><summary>Indice 2</summary>

La configuration structurée (`--alpha-config`) décrit `server`, `upstreamConfig`, `injectRequestHeaders` et `providers` ; les options du même domaine sont alors interdites dans le fichier historique (`--config`), qui garde les cookies et le reste. Une valeur d'en-tête peut venir d'une `secretSource` (`value`, `fromEnv`, `fromFile`). Lu depuis un fichier, un secret est pris **tel quel** : pas de retour à la ligne final, pas de décodage base64.
</details>

<details><summary>Indice 3</summary>

Deux HTTPRoute en conflit sur le même nom et le même chemin : la plus ancienne l'emporte (règles de précédence de la Gateway API). Mailpit vérifie l'en-tête `Host` contre sa liste de noms autorisés ; OAuth2 Proxy transmet celui du navigateur si on le lui demande.
</details>

**Pour aller plus loin** (facultatif) : mets Prometheus et Thanos Query (M21) derrière OAuth2 Proxy et mesure ce que deviennent les accès non humains (sonde du témoin de `mon01`, Grafana) ; compare avec l'authentification externe de la Gateway (filtre `ext_authz` d'Envoy). [OAuth2 Proxy : configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview) · [Keycloak OIDC](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc) · [Configuration alpha](https://oauth2-proxy.github.io/oauth2-proxy/configuration/alpha-config) · [Avis de sécurité](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories)

---

### M24-E19 — Inscrire les VMs dans FreeIPA : SSSD, HBAC et sudo  `LAB` `★★★`

> **Ticket PLAT-2519** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Sur les VMs, tout le monde est encore `admin`, avec la même clé ou le même certificat d'astreinte. Inscris les VMs du socle et les nœuds du cluster dans l'annuaire : chacun se connecte sous son nom, l'annuaire dit qui peut entrer où (HBAC) et qui peut faire quoi en root (sudo). Sophie veut la règle « tout le monde partout » de FreeIPA désactivée, mais **après** avoir prouvé que personne n'en a besoin. Le compte local `admin` reste : c'est celui d'Ansible et notre bris de glace. Pas les passerelles : la bordure garde ses comptes locaux.

**Objectifs pédagogiques**
- Inscrire des hôtes Debian dans FreeIPA par Ansible, avec un mot de passe à usage unique, sans jamais donner le mot de passe d'`admin` aux clients.
- Comprendre ce que l'inscription change sur un hôte (Kerberos, SSSD, NSS, PAM, sudo) et les conflits avec les comptes locaux.
- Décrire en code des règles HBAC et sudo par groupes ; tester avant de couper (`ipa hbactest`, `sssctl`).
- Appliquer par vagues, sans jamais perdre l'accès `admin`.

**Prérequis** : M24-E03 (annuaire en code), M24-E02 (flux vers `ipa01`) ; M04 (rôles, pipeline protégé) ; M14 (nœuds du cluster).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client | `freeipa-client` **4.12.4** (Debian 13), SSSD 2.10 ; serveur 4.13 : client plus ancien que le serveur, cas normal *(inscription Debian 13 → 4.13 non testée à la rédaction : signale tout écart)* |
| Rôle | **`freeipa_client`** (nouveau, `plateforme/ansible`), qui s'appuie sur le rôle **`ipaclient`** de `freeipa.ansible_freeipa` 1.17.0 ; playbook `playbooks/inscription-ipa.yml` |
| Hôtes inscrits | groupes `socle` et `k8s_par1`, **sauf** `role_routeur` (`gw01`, `gw02`) et `role_annuaire` (`ipa01`, qui est le serveur) |
| Inscription | mot de passe à usage unique généré sur `ipa01` pour **chaque** hôte (`ipa host-add --random` ou module `ipahost`, option `random`) ; le mot de passe d'`admin` de l'annuaire ne quitte jamais `ipa01` et le contrôleur |
| Réglages | `--mkhomedir` (dossier créé à la première connexion), pas de NTP (chrony vers les passerelles reste), pas de SSHFP, sshd **non** reconfiguré par FreeIPA (l'authentification SSH par certificat est l'objet d'E20) |
| Compte local | `admin` (UID local, clé d'Ansible, sudo sans mot de passe) : **même nom** qu'un compte de l'annuaire (`admin` de FreeIPA) |
| HBAC (dans `plateforme/identite/annuaire/hbac.yml`) | `hbac-plateforme` : groupes `plateforme-admins`, `plateforme` → tous les hôtes, service `sshd` ; `hbac-support` : groupe `support` → `mon01`, `nbx01`, service `sshd` ; règle `allow_all` **désactivée** (pas supprimée) ; `allow_systemd-user` inchangée |
| sudo (dans `annuaire/sudo.yml`) | `sudo-plateforme-admins` : groupe `plateforme-admins`, toutes commandes, tous hôtes, comme n'importe qui ; `sudo-plateforme` : groupe `plateforme`, consultation des journaux (`journalctl`, `systemctl status`) avec le groupe local `systemd-journal`, sans changer d'utilisateur |
| Vagues | 1 : `mon01` ; 2 : INFRA sans redondance (`ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `runner02`, `reg01`, `idp01`) ; 3 : `dns01` puis `dns02` ; 4 : `lb02` puis `lb01` ; 5 : `adm01` ; 6 : nœuds K8s **un par un** (contrôle puis travailleurs) |

**Travail demandé**

*A. Comprendre*

1. Lis le `README` du rôle `ipaclient` (variables `ipaclient_use_otp`, `ipaclient_otp`, `ipaclient_mkhomedir`, `ipaclient_no_ntp`, `ipaclient_no_sshd`, `ipaclient_servers`) et le guide FreeIPA sur HBAC et sudo. Sur une VM jetable ou sur `mon01` avant inscription, relève l'état de référence : `/etc/nsswitch.conf`, `pam-auth-update --list` (ou les fichiers `common-*`), `getent passwd admin`, `id admin`.
2. Le compte local `admin` et le compte `admin` de l'annuaire portent le même nom. Après inscription, quand sshd demande à PAM si `admin` a le droit d'entrer, qui répond ? Lis l'option `filter_users` de `sssd.conf` (section `[nss]`) et décide comment garantir que SSSD ne répond **jamais** pour `admin` (ni `root`). Note ta réponse dans `~/m24/e19/notes.md` : c'est le piège qui enferme dehors.

*B. L'inscription*

3. Écris le rôle `freeipa_client`. Exigences :
   - il refuse un autre système que Debian 13, un nom complet incohérent, une horloge non synchronisée, un hôte qui ne résout pas `_ldap._tcp` du domaine ;
   - si l'hôte est déjà inscrit, il ne fait rien (et ne génère surtout pas de mot de passe) ; sinon il fait générer un mot de passe à usage unique **sur `ipa01`** puis inscrit l'hôte avec ;
   - il pose le filtrage des comptes locaux dans SSSD et vérifie que `admin` et `root` restent résolus par les fichiers locaux ;
   - contrôles finaux : `sssd` actif, une personne de l'annuaire résolue, un ticket d'hôte obtenu par le keytab.
4. Écris `playbooks/inscription-ipa.yml` (un hôte à la fois, arrêt à la première erreur). Ajoute à la matrice des flux ce qui manquerait (INFRA, MGMT, VLAN 40, DMZ → `ipa01` 88, 464, 389, 636, 443 : E02).
   > ⚠️ **Attention** : l'inscription réécrit NSS et PAM de l'hôte. Pour chaque vague : une session SSH `admin` **ouverte** sur l'hôte, la console Proxmox à portée de main ; après inscription, **nouvelle** connexion `ssh admin@<hôte>` et `sudo -n true` avant de passer à l'hôte suivant. Retour arrière sur un hôte : `sudo ipa-client-install --uninstall -U` depuis la session ouverte (ou la console), puis `ipa host-del` côté annuaire.
5. Vague 1 (`mon01`). Contrôle sur l'hôte : `getent passwd lucas.martin`, `id lucas.martin`, `getent passwd admin`, `sudo klist -k`, `sudo sssctl domain-status par1.medisphere.internal`. Puis les vagues suivantes. Pour `lb01`/`lb02` (DMZ), les flux de la bordure existent-ils ?

*C. HBAC et sudo*

6. Écris `annuaire/hbac.yml` et `annuaire/sudo.yml` dans `plateforme/identite`, et les tâches correspondantes dans `annuaire.yml` (modules `ipahbacrule`, `ipasudocmd`, `ipasudocmdgroup`, `ipasudorule`). `allow_all` reste **activée** dans cette première MR. Applique.
7. Prouve avant de couper. Sur `ipa01` (ticket `admin` dans un cache temporaire), simule l'annuaire **sans** `allow_all` :
   ```
   [admin@ipa01 ~]$ ipa hbactest --user=lucas.martin --host=git01.par1.medisphere.internal --service=sshd \
   >   --rules=hbac-plateforme --rules=hbac-support
   [admin@ipa01 ~]$ ipa hbactest --user=nadia.roussel --host=git01.par1.medisphere.internal --service=sshd \
   >   --rules=hbac-plateforme --rules=hbac-support
   ```
   Fais une table : chaque groupe × trois hôtes représentatifs, résultat attendu, résultat obtenu. Qui perdrait un accès qu'il a aujourd'hui ?
8. Seconde MR : `allow_all` désactivée. Applique, puis sur `mon01` :
   ```
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd lucas.martin
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd julien.petit
   admin@mon01:~$ sudo sssctl user-checks -a acct -s sshd admin
   ```
   Interprète les trois réponses. **Nouvelle** connexion `ssh admin@mon01`, `ssh admin@git01`, `ssh admin@k8s-w01` : toutes passent-elles ? Que montre `sudo -l -U lucas.martin` sur `mon01` ?

**Critères de réussite**
- [ ] Les VMs du socle (hors `gw01`, `gw02`, `ipa01`) et les six nœuds de `k8s-par1` sont inscrits (entrée d'hôte dans l'annuaire, `/etc/ipa/default.conf`, SSSD actif) ; `gw01` et `gw02` ne le sont pas.
- [ ] Sur un hôte inscrit, une personne de l'annuaire est résolue par SSSD ; `admin` et `root` ne le sont jamais par SSSD ; la connexion `admin` par clé et `sudo -n` fonctionnent toujours.
- [ ] `allow_all` est désactivée ; `hbac-plateforme` et `hbac-support` sont actives avec le contenu du contexte technique ; `julien.petit` est refusé, `lucas.martin` accepté sur `mon01`.
- [ ] `sudo-plateforme-admins` et `sudo-plateforme` existent, actives, déclarées dans `annuaire/sudo.yml` sur `main`.

**Vérification** : `lab/bin/check 24 19`

<details><summary>Indice 1</summary>

Avec `ipaclient_use_otp`, le rôle de la collection fait générer le mot de passe à usage unique en se connectant à `ipaclient_servers[0]` **sous ce nom-là**, qui doit donc être joignable par Ansible tel quel. Générer toi-même le mot de passe sur l'hôte d'inventaire `ipa01` (module `ipahost`, `random: true`, `update_password: on_create`), puis le passer au rôle par `ipaclient_otp`, évite cette dépendance.
</details>

<details><summary>Indice 2</summary>

Sur Debian, `pam-auth-update` place `pam_sss` dans `common-account` avec `[default=bad success=ok user_unknown=ignore]` : tout dépend de ce que SSSD répond pour l'utilisateur. Si SSSD connaît un `admin`, il évalue HBAC pour lui. `filter_users` (section `[nss]`) fait répondre « inconnu » ; `getent -s sss passwd admin` doit alors ne rien rendre.
</details>

<details><summary>Indice 3</summary>

`journalctl` ouvre un afficheur paginé qui sait lancer un shell : en root, c'est un shell root. systemd active de lui-même le mode sûr de l'afficheur sous sudo, mais le plus simple est de ne pas devenir root du tout : `sudo -g systemd-journal journalctl …` lit le journal avec le seul groupe qui y donne accès. Dans FreeIPA, c'est un « RunAs group » de la règle.
</details>

**Pour aller plus loin** (facultatif) : remplace la clé SSH d'Ansible par un compte de service de l'annuaire avec une règle HBAC et sudo dédiée, et liste ce que deviendrait le bris de glace. [FreeIPA : *Configuring host-based access control*](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10) · [Rôle `ipaclient`](https://github.com/freeipa/ansible-freeipa/blob/master/roles/ipaclient/README.md) · [`sssd.conf(5)`](https://manpages.debian.org/trixie/sssd-common/sssd.conf.5.en.html)

---

### M24-E20 — SSH par certificats courts après SSO  `LAB` `★★★`

> **Ticket SEC-2520** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Les VMs savent maintenant qui est qui, mais on entre toujours par `admin` avec un certificat que `ms-ssh-cert` signe pour qui connaît le mot de passe du provisioner. Je veux l'inverse : chacun entre **sous son nom**, avec un certificat de 16 heures que step-ca ne délivre qu'après une connexion au SSO (et donc l'OTP pour les administrateurs, E21). Personne ne choisit ses principaux. Le certificat expiré ne sert plus à rien, et l'annuaire garde le dernier mot (HBAC) : un certificat valide ne suffit pas pour entrer là où on n'a rien à faire.

**Objectifs pédagogiques**
- Configurer un provisioner OIDC de step-ca et le client Keycloak correspondant.
- Imposer les principaux d'un certificat par un gabarit, à partir d'une revendication du jeton.
- Faire accepter par sshd les certificats des personnes de l'annuaire sans fichier par personne (`AuthorizedPrincipalsCommand`).
- Prouver les refus : certificat expiré, principal étranger, personne sans règle HBAC.

**Prérequis** : M24-E19 ; M06-E19 et M06-E20 (CA SSH d'hôtes et d'utilisateurs, rôle `ssh_ca_utilisateur`), M06-E27 (politique de durées de step-ca).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| step-ca | 0.30 sur `ca01`, rôle `step_ca` (`group_vars/role_pki/step_ca.yml`) ; CA SSH d'utilisateurs déjà approuvée par les hôtes (M06-E20), certificats d'utilisateur **16 h** au plus |
| Provisioner | **`keycloak`**, type OIDC, configuration de découverte de l'émetteur `https://sso.par1.medisphere.internal/realms/medisphere` ; domaine de courriel `medisphere.internal` ; **aucun administrateur** ; adresse d'écoute de la CLI `127.0.0.1:10000` ; certificats X.509 refusés |
| Client Keycloak | **`step-ca`** (`tofu/clients-step-ca.tf`), flux standard seul, PKCE `S256`, URI de retour exacte `http://127.0.0.1:10000`. Confidentiel ou public : à toi de le décider en lisant ce que publie `https://ca01.par1.medisphere.internal/provisioners` |
| Principaux | **un seul** : `preferred_username` de l'ID token (l'identifiant de l'annuaire). Attention : les principaux par défaut d'un provisioner OIDC dérivent du **courriel** |
| sshd | rôle `ssh_ca_utilisateur` : `AuthorizedPrincipalsFile /etc/ssh/principaux/%u` (comptes locaux : `admin` → `admin`, `astreinte`) ; à compléter, sur les hôtes inscrits, par une commande qui accepte pour un compte **de l'annuaire** le principal égal à son nom, et rien pour un compte local |
| Poste | `step` sur `adm01` (`step ca bootstrap` fait au M06) ; navigateur de ton poste, port 10000 d'`adm01` atteint par un tunnel SSH (comme kubelogin en E16) |
| Personnes d'essai | toi (`plateforme-admins`), `lucas.martin` (`plateforme`), `julien.petit` (`mediagenda`, aucune règle HBAC : donne-lui un mot de passe provisoire comme en E03) |

**Travail demandé**

*A. Le client et le provisioner*

1. Lis la documentation du provisioner OIDC de step-ca (`clientID`, `clientSecret`, `configurationEndpoint`, `admins`, `domains`, `listenAddress`, gabarits SSH et la variable `.Token`). Puis :
   ```
   admin@adm01:~$ curl -s https://ca01.par1.medisphere.internal/provisioners | jq '.provisioners[] | {type, name}'
   ```
   Si le provisioner `keycloak` avait un `clientSecret`, qui pourrait le lire ? Décide du type de client Keycloak et justifie-le dans `~/m24/e20/notes.md`.
2. Écris `tofu/clients-step-ca.tf` ; MR, plan, apply.
3. Ajoute le provisioner `keycloak` à `step_ca_provisioners` : durée maximale 16 h, aucun administrateur, domaine `medisphere.internal`, adresse d'écoute fixe, un **gabarit SSH** qui fixe le seul principal à `preferred_username` (et échoue explicitement si la revendication manque), et un gabarit X.509 qui refuse tout certificat. MR, pipeline. Que se passerait-il, avec les principaux par défaut, pour `lucas.martin@medisphere.internal` ?

*B. sshd*

4. Étends le rôle `ssh_ca_utilisateur` : sur les hôtes inscrits seulement (une variable), une commande `AuthorizedPrincipalsCommand` (script en lecture seule, propriété de root, exécuté par un utilisateur sans droit) qui imprime le nom du compte **si et seulement si** SSSD le résout, et rien sinon. Relis dans `sshd_config(5)` ce qui se passe quand le fichier **et** la commande sont configurés. Applique par vagues (comme E19), `sshd -T` et une **nouvelle** connexion `admin` à chaque hôte.
   > ⚠️ **Attention** : une erreur dans la configuration de sshd coupe toutes les nouvelles connexions. Le rôle valide (`sshd -t`) avant de poser ; garde une session ouverte par hôte pendant la vague. Retour arrière : variable à `false`, rejeu du rôle.
5. Sur `mon01` : `/usr/local/sbin/<TON-SCRIPT> lucas.martin`, puis `admin`, puis `root`. Que doit afficher chacun ?

*C. Les certificats*

6. Tunnel du port 10000, puis :
   ```
   admin@adm01:~$ eval "$(ssh-agent)"
   admin@adm01:~$ step ssh login <MOI>@medisphere.internal --provisioner keycloak
   admin@adm01:~$ ssh-add -L | grep cert | step ssh inspect
   admin@adm01:~$ ssh <MOI>@mon01.par1.medisphere.internal 'id; pwd'
   ```
   Relève les principaux, la validité, l'identifiant de clé. Ton dossier personnel existe-t-il ? Essaie `ssh admin@mon01` **avec ce seul certificat** (agent vidé de toute autre clé) : refusé, et c'est voulu, pourquoi ?
7. Les refus. (a) Certificat de 5 minutes (`--not-after 5m`), connexion, attente, nouvelle connexion. (b) `julien.petit` (agent vidé, nouvelle connexion au SSO dans une fenêtre privée) vers `mon01`. Pour chaque cas, relève le message côté client et la ligne correspondante dans `journalctl -u ssh` de `mon01` : à quelle étape (certificat, principal, compte PAM) le refus a-t-il lieu ?
8. `ms-ssh-cert` (M06) signe toujours, par le provisioner `admin`, des certificats `admin`/`astreinte`. Que décides-tu de lui (garder pour le bris de glace, restreindre, retirer) ? Écris la décision et sa raison dans `docs/socle/acces-ssh.md` de `plateforme/medisphere` (crée le document s'il n'existe pas : qui entre comment, durée, bris de glace).

**Critères de réussite**
- [ ] Le client `step-ca` existe (PKCE `S256`, seule URI `http://127.0.0.1:10000`, sans *Direct Access Grants*).
- [ ] `ca01` publie un provisioner OIDC `keycloak` (client `step-ca`, émetteur du royaume `medisphere`, aucun administrateur, 16 h au plus, gabarit SSH qui fixe le principal à `preferred_username`).
- [ ] Sur les hôtes inscrits, sshd consulte la commande de principaux ; elle répond le nom pour une personne de l'annuaire et rien pour `admin` ou `root`.
- [ ] Le journal de `mon01` montre une connexion par certificat sous ton nom ; `julien.petit` est refusé au compte (HBAC).
- [ ] `docs/socle/acces-ssh.md` est sur `main`.

**Vérification** : `lab/bin/check 24 20`

<details><summary>Indice 1</summary>

La CLI `step` est le client OIDC : elle lit la configuration du provisioner sur `ca01` (secret compris), ouvre le navigateur, reçoit le code sur une adresse de bouclage et l'échange elle-même. step-ca vérifie ensuite l'ID token : signature, émetteur, **audience = clientID**, `azp`. La CLI envoie un défi PKCE.
</details>

<details><summary>Indice 2</summary>

Sans gabarit, les principaux d'un certificat OIDC viennent du courriel : partie locale « nettoyée » (les points sont **retirés**), partie locale brute, courriel complet. Dans un gabarit SSH de step-ca, `.Token` contient les revendications de l'ID token, et la fonction `fail` arrête l'émission avec un message.
</details>

<details><summary>Indice 3</summary>

sshd consulte d'abord `AuthorizedPrincipalsFile`, puis, s'il n'y a rien trouvé, `AuthorizedPrincipalsCommand` ; il refuse de démarrer si la commande n'a pas d'`AuthorizedPrincipalsCommandUser`. `getent -s sss passwd <compte>` n'interroge que SSSD.
</details>

**Pour aller plus loin** (facultatif) : faites porter au certificat l'extension `permit-port-forwarding` seulement pour `plateforme-admins` (gabarit et `.Token.groups`) ; mesurez ce que change une CA SSH sous HSM. [step-ca : *OIDC provisioner*](https://smallstep.com/docs/step-ca/provisioners/#oauthoidc-single-sign-on) · [*Templates*](https://smallstep.com/docs/step-ca/templates/) · [`sshd_config(5)`](https://man.openbsd.org/sshd_config)

---

### M24-E21 — Authentification forte : OTP obligatoire, WebAuthn en option  `LAB` `★★`

> **Ticket SEC-2521** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Tout ce qui administre passe désormais par le SSO : console Argo CD, Proxmox, `kubectl`, SSH. Un mot de passe volé à un membre de `plateforme-admins`, c'est la plateforme entière. Second facteur **obligatoire** pour `plateforme-admins` et `securite`, enrôlement imposé à leur prochaine connexion. Pour les autres, je ne l'impose pas encore, mais ceux qui ont une clé de sécurité doivent pouvoir l'utiliser. Ni les comptes de service ni le bris de glace ne doivent pouvoir être bloqués par ce changement.

**Objectifs pédagogiques**
- Construire en code un flux d'authentification conditionnel de Keycloak (sous-flux, conditions, exécutions, liaison au royaume).
- Rattacher une exigence de sécurité à des **groupes** de l'annuaire par un rôle.
- Mesurer l'effet d'un second facteur sur les accès en ligne de commande (kubelogin, `step ssh login`) et sur les comptes non interactifs.

**Prérequis** : M24-E08 (royaume en code), M24-E04 (administrateurs de `master`), M24-E16 (kubelogin), M24-E20 (`step ssh login`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichier | `tofu/flux.tf` de `plateforme/identite` |
| Flux | **`navigateur-medisphere`**, même structure que `browser` (cookie, puis formulaire), écrit exécution par exécution ; lié comme flux de navigateur du royaume `medisphere` |
| Qui | rôle de royaume `second-facteur-obligatoire`, attribué aux **groupes** `plateforme-admins` et `securite` (importés de l'annuaire) |
| OTP | TOTP, réglages par défaut du royaume (6 chiffres, 30 s) ; applications : FreeOTP, Aegis, Google Authenticator… |
| WebAuthn | second facteur **volontaire** pour les autres personnes : demandé seulement à qui a enregistré une clé (console de compte) |
| Hors champ | royaume `master` (`<MOI>-admin` a déjà son OTP, `kc-secours` n'en a pas : E04) ; comptes de service (`client_credentials`) ; *Direct Access Grants* désactivés partout |

**Travail demandé**

*A. Comprendre les flux*

1. Dans la console (lecture seule), ouvre *Authentication* → `browser` du royaume `medisphere` : dessine l'arbre (sous-flux, exigences `ALTERNATIVE`, `REQUIRED`, `CONDITIONAL`). Liste les conditions disponibles : laquelle permet de viser un **groupe** ? Comment, à défaut, viser les membres d'un groupe ?
2. Lis dans la documentation du fournisseur les ressources `keycloak_authentication_flow`, `keycloak_authentication_subflow`, `keycloak_authentication_execution` (attribut `priority`), `keycloak_authentication_execution_config`, `keycloak_authentication_bindings`, `keycloak_role`, `keycloak_group_roles`, `keycloak_required_action`. Pourquoi ne pas utiliser `copy_from` ?

*B. Le flux en code*

3. Écris `tofu/flux.tf` : le rôle et son attribution aux deux groupes ; le flux (cookie `ALTERNATIVE` ; sous-flux de formulaires `ALTERNATIVE` avec identifiant et mot de passe `REQUIRED`, un sous-flux conditionnel OTP pour les porteurs du rôle, un sous-flux conditionnel WebAuthn pour les **autres** personnes qui ont une clé) ; la liaison au royaume **après** les exécutions ; les actions requises d'enrôlement activées sans être imposées à tous.
4. MR : relis le plan ligne à ligne. Combien d'objets, et lequel change le comportement pour tout le monde ?
   > ⚠️ **Attention** : la liaison du flux s'applique à **toutes** les connexions du royaume `medisphere`, donc à tous les services. Avant l'apply : une session ouverte dans la console d'administration (royaume `master`, `<MOI>-admin`), et une fenêtre privée prête pour l'essai. Retour arrière en une minute : dans la console, *Authentication* → `browser` → *Bind flow* → *Browser flow* ; puis MR qui rétablit le code. Le pipeline n'est pas touché (compte de service).
5. Apply, puis essais dans des fenêtres privées sur la console de compte (`/realms/medisphere/account/`) : `lucas.martin` (aucun second facteur), toi (enrôlement OTP imposé, puis code demandé). Relève dans *Events* du royaume (si les événements sont enregistrés) ou dans le journal de `idp01` ce qui distingue les deux connexions.

*C. Les effets*

6. `kubectl` : `kubectl oidc-login clean`, puis `kubectl --context k8s-par1-oidc get nodes`. Où l'OTP est-il demandé ? Combien de temps dure ensuite l'accès sans nouveau code, et de quoi cela dépend-il ? Même question pour `step ssh login`.
7. WebAuthn (facultatif si tu n'as pas de clé ou d'authentificateur de plateforme) : en `lucas.martin`, enregistre une clé dans la console de compte (*Account security* → *Signing in*), déconnecte-toi, reconnecte-toi.
8. Contrôle que rien de non interactif n'est bloqué : `lab/bin/check 24 05` (client `wb-checks`), un `tofu plan` du pipeline de `plateforme/identite`, et la connexion de `kc-secours` dans le royaume `master` (fenêtre privée). Note dans `~/m24/e21/notes.md` la liste des comptes qui n'ont **pas** de second facteur et pourquoi c'est acceptable (ou pas).

**Critères de réussite**
- [ ] Le flux de navigateur du royaume `medisphere` est `navigateur-medisphere`, décrit dans `tofu/flux.tf` sur `main` (plan vide).
- [ ] Le sous-flux conditionnel exige l'OTP pour le rôle `second-facteur-obligatoire`, porté par les groupes `plateforme-admins` et `securite` (et par eux seuls).
- [ ] Ton compte du royaume `medisphere` a un OTP enregistré ; aucune personne n'a l'enrôlement imposé par défaut.
- [ ] Aucun client du royaume n'a les *Direct Access Grants* activés.

**Vérification** : `lab/bin/check 24 21`

<details><summary>Indice 1</summary>

Keycloak 26.7 propose les conditions *user role*, *user configured*, *user attribute*, *client scope*, *credential*, *sub-flow executed* et *level of authentication* : aucune ne porte sur un groupe. Un rôle de royaume attribué à un groupe est **hérité** par ses membres, et la condition *user role* tient compte de cet héritage. Les membres d'un groupe importé de l'annuaire en `READ_ONLY` ne se changent pas dans Keycloak, ses rôles si.
</details>

<details><summary>Indice 2</summary>

Dans un sous-flux `CONDITIONAL`, toutes les conditions `REQUIRED` doivent être vraies pour que les exécutions suivantes s'appliquent ; une condition se règle par une configuration d'exécution (clés `condUserRole` et `negate` pour *user role*). Quand l'OTP est `REQUIRED` et que la personne n'en a pas, Keycloak lui impose l'action *Configure OTP*.
</details>

**Pour aller plus loin** (facultatif) : codes de récupération (*Recovery Authentication Codes*) pour les administrateurs ; politique d'OTP (algorithme, fenêtre) et son effet sur les applications mobiles ; niveaux d'authentification (LoA, `acr`) pour exiger l'OTP **par service** plutôt que par personne. [Keycloak : *Conditions in conditional flows*](https://www.keycloak.org/docs/latest/server_admin/#conditions-in-conditional-flows) · [*W3C Web Authentication*](https://www.keycloak.org/docs/latest/server_admin/#webauthn_server_administration_guide)

---

### M24-E22 — Revue : la configuration Keycloak du stagiaire  `REV` `★★`

> **Ticket PLAT-2522** — *De : Karim Benali*
> Lucas a ouvert la MR !41 sur `plateforme/identite` : un royaume `medisphere-recette` pour que l'équipe de Julien teste l'authentification de MédiAgenda et de MédiStat sans toucher au royaume de production. L'idée est bonne. Le code, je n'en suis pas sûr : il m'a dit « j'ai suivi les tutoriels et tout marche sur mon Keycloak d'essai ». Fais la revue avant moi, par écrit, comme si elle partait demain en production. Ce qui marche n'est pas forcément ce qui est sûr.

**Objectifs pédagogiques**
- Relire une configuration d'IdP en code et y trouver les défauts de sécurité et de fonctionnement.
- Classer les défauts par gravité et proposer pour chacun une correction précise.
- Distinguer ce qui est dangereux de ce qui est seulement inhabituel.

**Prérequis** : M24-E05 à M24-E08, M24-E21.
**Durée indicative** : 1 h 30.

**Contexte technique** : les fichiers de la MR sont dans [`ressources/M24-E22/`](../ressources/M24-E22/) : `README.md` (description de la MR par Lucas), `royaume-recette.tf`, `clients-recette.tf`. Ils s'ajoutent à `tofu/` (même fournisseur, même état). La recette de MédiAgenda n'est pas exposée sur Internet, mais elle est joignable de tout le réseau du lab, et ses données sont des copies **anonymisées** de la production.

**Travail demandé**

1. Lis les trois fichiers sans rien exécuter. Pour chaque défaut trouvé : fichier et ligne, ce qui est faux, ce qu'un attaquant (ou un incident) en tirerait concrètement, gravité (critique, majeure, mineure), correction exacte (attribut et valeur, ou objet à ajouter ou retirer).
2. Repère aussi ce qui **manque** (ce que le royaume `medisphere` a et que celui-ci n'a pas) et ce qui est inutile mais sans danger.
3. Une question de conception : un royaume de recette qui fédère le **même** annuaire que la production est-il une bonne idée ? Propose une alternative et ses conséquences.
4. Rédige la revue dans `~/m24/e22/revue-mr41.md`, sous la forme d'un commentaire de MR : un résumé (fusionnable ou non, et pourquoi), puis les défauts du plus grave au moins grave. Facultatif : applique le code sur un Keycloak jetable (`kc.sh start-dev` sur ton poste) pour **prouver** deux défauts.

**Critères de réussite**
- [ ] Au moins 10 défauts identifiés, chacun avec une conséquence concrète et une correction précise.
- [ ] Les trois défauts critiques sont en tête et expliqués de façon qu'un stagiaire comprenne le risque.
- [ ] La revue conclut clairement (fusion refusée ou acceptée sous conditions) et répond à la question de conception.

<details><summary>Indice 1</summary>

Relis chaque attribut contre ce que tu as fait (et pourquoi) en E05-E08 et E21 : flux autorisés, URI de retour, type de client, durées, mode de la fédération, secrets dans le code. Puis regarde d'où viennent les **groupes** dans les jetons : tous les services en déduisent les droits.
</details>

<details><summary>Indice 2</summary>

Cherche aussi les défauts **par omission** : une liste de portées par défaut remplace la liste du royaume pour ce client ; un attribut que Keycloak ignore pour un type de client donne un plan qui n'est jamais vide.
</details>

**Pour aller plus loin** (facultatif) : écris une règle de lint (Conftest/OPA sur `tofu show -json`, ou un script `jq`) qui refuse en CI les trois défauts les plus graves. [Keycloak : *Server Administration Guide*, chapitres *Managing OpenID Connect clients* et *Threat model mitigation*](https://www.keycloak.org/docs/latest/server_admin/) · [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700)

---

### M24-E23 — Arrivées, mobilités et départs  `RED` `★★`

> **Ticket SEC-2523** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Claire Morel*
> L'auditeur HDS nous demandera deux choses : comment une personne obtient ses accès (et qui l'a décidé), et la preuve qu'un départ coupe **tout** en moins d'une heure. Pour InfoGér, il nous a fallu trois semaines. Écris les deux runbooks : RB-241 (arrivée), RB-242 (départ et mobilité). Ils doivent pouvoir être suivis par Nadia un vendredi à 17 h, sans toi, et produire des preuves que je peux montrer.

**Objectifs pédagogiques**
- Décrire le cycle de vie d'une identité de bout en bout, de l'annuaire à chaque service.
- Distinguer ce que le SSO coupe d'un coup de ce qu'il faut couper un par un (sessions, jetons, clés, comptes locaux).
- Rédiger des procédures exécutables, chronométrées, avec preuves et retour arrière.

**Prérequis** : M24-E10 à M24-E21 (tous les services branchés au palier 2).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichiers | `docs/securite/identite/runbooks/RB-241-arrivee.md` et `RB-242-depart-mobilite.md` de `plateforme/medisphere` |
| Source de vérité | `annuaire/personnes.yml` et `groupes.yml` de `plateforme/identite` (MR, job manuel protégé) ; un départ = `etat: disabled`, jamais une suppression |
| Ce qui suit l'annuaire seul | connexion à tous les services en SSO (liaison LDAP à chaque connexion) ; groupes dans les jetons ; HBAC et sudo des VMs (SSSD, avec son cache) |
| Ce qui a sa vie propre | sessions SSO de Keycloak (10 h) et sessions de chaque service ; jetons de rafraîchissement (kubelogin, Argo CD, Grafana) ; jetons personnels (GitLab, Grafana, Harbor, Argo CD) ; clés SSH et certificats SSH déjà émis (16 h) ; comptes GitLab (liaison OIDC, appartenances par `synchro-gitlab.py`, E11) ; ACL par utilisateur de PBS (E15) ; comptes de robot Harbor créés par une personne ; secrets qu'elle connaissait |
| Délais | arrivée : accès prêts le premier jour à 9 h ; départ : tout coupé en **moins de 60 minutes** après l'appel des RH (cible du mini-projet : 15 min) ; mobilité : anciens droits retirés le jour du changement |
| Outils | job `annuaire:appliquer` ; console d'administration de Keycloak (royaume `medisphere` : *Users* → *Sessions*) ; API GitLab ; `kubectl` ; `ipa` sur `ipa01` ; journaux dans Loki (locataire `audit`, M22) |

**Travail demandé**

1. Pour chaque service branché au palier 2 (GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, Kubernetes, Hubble, Pyroscope, Mailpit, SSH, sudo), établis dans un tableau : comment une personne y obtient ses droits (groupe, synchronisation, attribution locale), ce qui reste actif après la désactivation dans l'annuaire, combien de temps, et comment le couper.
2. Rédige **RB-241** : déclencheur (demande RH et responsable, qui valide les groupes), prérequis, étapes (MR dans `personnes.yml` et `groupes.yml`, premier mot de passe, premier accès, enrôlement OTP si groupe concerné, droits qui ne découlent pas des groupes), contrôles, preuves conservées (MR, pipeline, événements), délais.
3. Rédige **RB-242** en trois parties : **départ normal** (planifié), **départ immédiat** (licenciement, compromission : la course contre la montre, chronométrée étape par étape, dans l'ordre qui ferme d'abord ce qui donne le plus de pouvoir), **mobilité** (changement d'équipe : retirer avant d'ajouter, sessions à fermer pour que les nouveaux groupes et surtout les **anciens** disparaissent des jetons). Pour chaque étape : commande ou écran, contrôle, preuve.
4. Ajoute à RB-242 la vérification finale : comment prouves-tu, une heure après, que la personne n'a plus aucun accès (liste de contrôles, requêtes LogQL sur le locataire `audit`, revue des jetons) ? Que mets-tu dans le ticket de clôture ?
5. Fais relire mentalement chaque runbook par Nadia : chaque commande est complète, chaque valeur à adapter est notée `<EN-MAJUSCULES>`, aucun secret n'apparaît, chaque étape dit quoi faire si elle échoue.

**Critères de réussite**
- [ ] RB-241 et RB-242 sont sur `main` de `plateforme/medisphere`, au format des runbooks du workbook (déclencheur, prérequis, étapes, contrôles, retour arrière, preuves).
- [ ] RB-242 traite les trois cas, avec un ordre justifié pour le départ immédiat et un temps cible par étape (total < 60 min).
- [ ] Les accès qui survivent à la désactivation dans l'annuaire (sessions, jetons de rafraîchissement, jetons personnels, certificats SSH, ACL locales) sont tous traités un par un.
- [ ] Chaque runbook dit quelles preuves sont conservées et où.

<details><summary>Indice 1</summary>

Désactiver la personne dans l'annuaire empêche toute **nouvelle** connexion par mot de passe, partout, immédiatement. Tout ce qui a été délivré **avant** (session SSO, session d'un service, jeton de rafraîchissement, jeton personnel, certificat SSH) vit jusqu'à son expiration ou jusqu'à ce qu'on le révoque. La question à poser pour chaque service : « qu'est-ce qu'elle a encore en poche ? ».
</details>

<details><summary>Indice 2</summary>

Dans Keycloak, fermer les sessions d'une personne (*Users* → la personne → *Sessions* → *Sign out*, ou l'API d'administration) invalide ses jetons de rafraîchissement : kubelogin, Argo CD, Grafana et OAuth2 Proxy ne pourront plus rafraîchir. Un certificat SSH ne se révoque pas (pas de liste de révocation consultée par sshd chez nous) : il expire, d'où les 16 h ; mais le compte, lui, est refusé par SSSD et HBAC dès que l'annuaire le dit (cache compris : `sss_cache`).
</details>

**Pour aller plus loin** (facultatif) : automatise la partie « départ immédiat » dans un job manuel protégé de `plateforme/identite` (sessions Keycloak, jetons GitLab, sessions Argo CD), qui produit lui-même le rapport de preuve ; c'est l'objet de la démonstration du mini-projet (M24-E46). [ANSSI : *Recommandations relatives à l'administration sécurisée des SI*](https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-systemes-dinformation) · [Keycloak : *Managing user sessions*](https://www.keycloak.org/docs/latest/server_admin/#managing-user-sessions)
