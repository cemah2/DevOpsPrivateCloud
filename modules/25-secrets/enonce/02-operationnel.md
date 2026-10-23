# Module 25 — Palier 2 : Opérationnel

Le palier 1 a posé le coffre : OpenBao sur `vault01`, descellé à la main, le moteur `kv/`, les politiques, l'entrée des personnes par le SSO (`oidc`), celle des machines par AppRole (`wb-checks`, `medictl`), et le projet `plateforme/secrets` qui décrit tout cela en OpenTofu. Personne ne s'en sert encore. Ce palier **branche le coffre sur le reste de MédiSphère**, ticket après ticket : les jobs de CI s'authentifient par leur jeton d'identité signé par GitLab, Ansible lit ses mots de passe dans le coffre, les pods reçoivent leurs Secrets par External Secrets Operator (ESO), MédiAgenda obtient des identifiants PostgreSQL qui expirent d'eux-mêmes, les secrets tournent sans que personne ne redémarre quoi que ce soit, et les services de la recette se parlent en TLS mutuel avec des certificats de quelques heures. La seconde moitié du palier fait du coffre un service de chiffrement (transit, SOPS, signature Cosign), compare les autres façons de livrer un secret à Kubernetes, ouvre l'audit, relit les politiques du stagiaire et écrit le runbook de fuite.

Prérequis : palier 1 terminé (`lab/bin/check 25 08` vert : OpenBao en code, jeton racine révoqué) ; module 24 (`identite-v1`) ; module 19 (jetons d'identité `id_tokens`, runner protégé, composants CI/CD) ; module 20 (Argo CD, `secrets-k8s.sh`) ; module 16 (CloudNativePG). Relis [`00-introduction.md`](00-introduction.md), en particulier le chemin d'une demande (identité → méthode d'authentification → politique → moteur) et les **règles du module**.

> **Rappels du module** (introduction) : la configuration d'OpenBao vit dans **`plateforme/secrets`** (clone `~/src/secrets` sur `adm01`) : politiques HCL dans `politiques/`, montages, méthodes et rôles dans `tofu/`, état S3 `secrets` ; on écrit d'abord en code, on applique par `tofu apply` (depuis `adm01` avec un jeton OIDC `plateforme-admin` jusqu'à E10, par le pipeline ensuite) ; une commande `bao write` à la main ne sert qu'à **essayer**, et tout essai réussi est repris en code avant la fin de l'exercice (`tofu plan` vide). Les **valeurs** des secrets ne sont jamais dans Git, ni en clair, ni dans un compte rendu, ni sur une ligne de commande (`ps` les voit) : on les écrit dans le coffre par l'entrée standard (`… | bao kv put -mount=kv <chemin> -`). Tout objet du cluster passe par Git et Argo CD (ou `task appliquer` de `plateforme/k8s` pour la couche d'espaces) ; aucun `kubectl apply` sur les espaces applicatifs ; tout flux réseau par le rôle `pare_feu` et `docs/socle/matrice-flux.md`. Les vérifications (`lab/bin/check 25 XX`) lisent OpenBao avec l'AppRole `wb-checks` (métadonnées et configuration, **jamais** une valeur de secret), le cluster avec le compte `wb-checks` (jamais les Secrets) et GitLab avec le jeton des checks.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Coffre | `https://openbao.par1.medisphere.internal:8200` (`BAO_ADDR` sur `adm01`, racine MédiSphère dans le magasin système) ; jusqu'à E24, ce nom pointe sur `vault01` (10.10.20.21). OpenBao **2.6.x** (montée en 2.7.1 en E29) ; client `bao` de la même version partout (`adm01`, `runner01`, image de CI) |
| Moteurs | `kv/` (KV v2, `max_versions` 10) : `kv/plateforme/<composant>/<secret>`, `kv/<application>/<env>/<secret>` (`<env>` = `dev`, `recette`, `prod`, ou `ci` pour les secrets de pipeline) ; `db-mediagenda/` (E14) ; `pki-services/` (E16) ; `transit/` (E17 : clés `sops-plateforme`, `cosign-medisphere`, `medictl-donnees`) |
| Méthodes d'authentification | `oidc/` (personnes, palier 1) ; `approle/` (`wb-checks`, `medictl`, palier 1) ; **`gitlab/`** de type `jwt` (E10 : émetteur `https://git01.par1.medisphere.internal`, audience **`openbao.medisphere.internal`**, rôles `ci-<groupe>-<projet>`, jetons de 10 min) ; **`k8s-par1/`** de type `kubernetes` (E12 : `https://k8s-api.par1.medisphere.internal:8443`, audience `openbao.medisphere.internal` sur chaque rôle) |
| Politiques ajoutées au palier | `ci-<groupe>-<projet>` et `ci-mediagenda-api-promotion` (E10), `tofu-secrets` (E10), `ansible-lab`, `ansible-critique` (E11), `eso-plateforme`, `eso-<espace>` (E12-E14), `cert-manager-services` (E16), `cosign-signature`, `ci-signature` (E20) ; la politique `wb-checks` est étendue en E10 (lecture de la **configuration** des méthodes, moteurs et rôles, jamais des valeurs) |
| External Secrets Operator | **2.13** (chart `external-secrets` 2.13.0 recopié dans Harbor `charts/`), Application Argo CD `external-secrets`, espace **`external-secrets`**, API `external-secrets.io/v1` ; **ClusterSecretStore `openbao`** (rôle `eso-plateforme`) réservé aux espaces de plateforme ; dans chaque espace applicatif un **SecretStore `openbao`** (compte de service `eso`, rôle `eso-<espace>`) ; `refreshInterval` 1 h par défaut, 5 min pour un secret qu'on fait tourner |
| Où vivent les objets ESO | SecretStore, compte `eso`, générateurs : `plateforme/k8s/espaces/<espace>/` (la plateforme décide comment un espace entre dans le coffre) ; ExternalSecret de plateforme : `plateforme/gitops`, dossier `secrets/<espace>/`, Application `secrets-plateforme` ; ExternalSecret d'application : `…/deploiement` |
| Base de MédiAgenda (E14) | Services `LoadBalancer` **10.10.41.64** (recette) et **10.10.41.65** (prod) devant le primaire CNPG, ouverts à 10.10.20.21-23 seulement ; rôles OpenBao `mediagenda-api-<env>` et `mediagenda-migrateur-<env>`, TTL 1 h, max 24 h ; générateurs ESO `VaultDynamicSecret` rafraîchis toutes les 30 min |
| Redémarrage sur changement (E15) | **Reloader 1.4.22** (stakater, chart 2.2.18), Application `reloader`, espace `reloader` |
| PKI de services (E16) | CA intermédiaire **« MédiSphère Services CA »** (3 ans, signée par la racine pendant une cérémonie), rôle `services-k8s` (`*.svc`, `*.svc.cluster.local`, 72 h au plus), ClusterIssuer cert-manager **`openbao-services`** |
| Chiffrement et signature (E17-E20) | SOPS **3.13.3** (jamais 3.13.2), age **1.3** ; Sealed Secrets **0.40** (chart du projet, images du projet) et Secrets Store CSI Driver **1.6** (fournisseur `openbao`) dans `wb-essais`, désinstallés après comparaison ; Cosign 3 avec `--key hashivault://cosign-medisphere` depuis le runner protégé |
| Audit (E21) | `/var/log/openbao/audit.log` (dispositif `fichier`), envoyé par Alloy vers Loki, locataire **`audit`**, étiquette `service="openbao"` |
| Documentation | `docs/securite/secrets/` de `plateforme/medisphere` : `inventaire-secrets.md` (E02, tenu à jour à chaque migration), `ci-et-openbao.md` (E10), `identifiants-dynamiques.md` (E14-E15), `pki-services.md` (E16), `runbooks/RB-250-fuite-de-secret.md` (E23) ; procès-verbal de cérémonie dans `docs/securite/identite/ceremonie-ca.md` (M24) |
| Tickets | `PLAT-26xx`, `SEC-26xx`, `DEV-26xx`, `CHG-26xx`, `INC-52xx`, `xx` = numéro de l'exercice |
| Travail personnel | `~/m25/eXX/` sur `adm01` (essais, journaux de travail, preuves **sans valeur de secret**) |

> 💡 **Lire un refus.** OpenBao répond `permission denied` sans dire pourquoi : c'est voulu. Pour comprendre, demande-lui ce qu'un jeton peut faire (`bao token capabilities <chemin>`), ce qu'il porte (`bao token lookup`), et ce que dit la politique (`bao policy read <nom>`). Un refus à la **connexion** (rôle, audience, revendication) se lit, lui, dans le message d'erreur de la méthode et dans le journal d'OpenBao (`journalctl -u openbao` sur `vault01`).

> ⚠️ **Mémoire.** Le palier ajoute ESO (≈ 150 Mo), Reloader (≈ 50 Mo), deux conteneurs de relais TLS par pod de la recette en E16, puis des essais temporaires (Sealed Secrets, pilote CSI) : surveille `kubectl top nodes`, retire chaque essai dès qu'il est conclu, et garde `bao-essai` (E30) pour le palier 3.

Durée indicative du palier : 31 à 37 heures. Ordre conseillé :

```
E10 ─ E11                         la CI d'abord : E11 réutilise la méthode jwt et le client bao de E10
E12 ─ E13 ─ E14 ─ E15 ─ E16       ESO, puis les migrations ; E14 et E15 d'une traite (voir E14)
E21 aussitôt que possible         tout ce qui suit sera audité (E21 n'attend rien d'autre que le palier 1)
E17 ─ E18 ; E17 ─ E20             transit avant SOPS et avant Cosign
E19 après E12, à tout moment      comparaison temporaire dans wb-essais
E22, puis E23 en fin de palier    la revue et le runbook s'appuient sur tout le reste
```

---

### M25-E10 — La CI sans secret durable : jetons d'identité de GitLab  `LAB` `★★★`

> **Ticket SEC-2610** — *De : Sophie Laurent*
> L'inventaire du module (E02) le dit en rouge : le jeton du robot Harbor qui publie nos images est une variable de **groupe**, recopiée dans quatre groupes, et le jeton de promotion de MédiAgenda vit dans les variables du projet depuis le M19. Tourner ces jetons tous les 60 jours à la main, c'est accepter qu'ils fuient pendant 60 jours. Au M19, vous avez montré que GitLab signe pour chaque job un jeton d'identité qui dit **qui** il est (projet, branche, protection). Je veux que le coffre s'appuie dessus : plus aucun secret durable dans les variables des projets migrés, un job d'une branche non protégée qui n'obtient rien, et le pipeline de `plateforme/secrets` qui applique lui-même la configuration du coffre.

**Objectifs pédagogiques**
- Configurer la méthode `jwt` d'OpenBao contre la découverte OIDC de GitLab (émetteur, clés, audience).
- Écrire des rôles qui lient un jeton de job à un projet, une référence et sa protection (`bound_claims`), et comprendre pourquoi `sub` seul ne suffit pas.
- Faire présenter le jeton par le job lui-même (`id_tokens` + CLI `bao`) dans un composant CI/CD partagé, sans jamais afficher ni stocker de secret.
- Donner au pipeline de `plateforme/secrets` sa propre identité, sans jeton d'administration stocké.

**Prérequis** : M25-E08 (`plateforme/secrets` en OpenTofu, jeton racine révoqué), M19-E25 (jetons d'identité relevés, `secrets-ci.md` §4), M19-E24 (runner protégé, composants `securite` v2.8.0 et `promotion` v2.7.0).
**Durée indicative** : 4 h 30.

**Contexte technique**
- GitLab 19.5 CE : le mot-clé `secrets:vault` est **Premium**. En CE, le job déclare un jeton d'identité (`id_tokens`, Free) et le présente lui-même à OpenBao avec la CLI. Émetteur : `https://git01.par1.medisphere.internal` ; clés publiques : `https://git01.par1.medisphere.internal/oauth/discovery/keys` ; audience fixée au M19-E25 : **`openbao.medisphere.internal`**. Les revendications ont été relevées dans `docs/livraison/ci/secrets-ci.md` §4 (attention aux **types** : `ref_protected` y est une chaîne).
- Méthode à monter : type `jwt`, chemin **`gitlab/`**. Rôles nommés **`ci-<groupe>-<projet>`** (chemin du projet, `/` remplacé par `-`) : `ci-mediagenda-api`, `ci-medidoc-medidoc`, `ci-plateforme-secrets` ; plus `ci-mediagenda-api-promotion` réservé au job de promotion (environnement `promotion/*`). Jetons émis : 10 minutes, non renouvelables au-delà.
- Secrets à sortir des variables (valeurs actuelles dans GitLab, à recopier dans le coffre sans les afficher) :

| Variable actuelle (M19) | Chemin KV | Clés |
|---|---|---|
| `HARBOR_ROBOT_USER`, `HARBOR_ROBOT_TOKEN` (groupes) | `kv/plateforme/harbor/robot-ci` | `utilisateur`, `jeton` |
| `DEPLOIEMENT_TOKEN` (`mediagenda/api`, portée `promotion/*`) | `kv/mediagenda/ci/promotion` | `jeton` |
| `GITLAB_TOKEN` (`mediagenda/api`, semantic-release) | `kv/mediagenda/ci/release` | `jeton` |
| `DEPLOIEMENT_TOKEN`, `GITLAB_TOKEN` (`medidoc/medidoc`) | `kv/medidoc/ci/promotion`, `kv/medidoc/ci/release` | `jeton` |

- Les identités **en lecture seule** (`*_RO_USER`/`*_RO_TOKEN`, M19-E25 §2) restent des variables masquées non protégées : exception écrite, traitée en « Pour aller plus loin ».
- L'image `plateforme/outils-supply-chain` (M13-E09, construite par `plateforme/ci-templates`) n'a pas de client `bao` : la version **1.1.0** l'ajoute, depuis l'archive `openbao_<version>_linux_amd64.tar.gz` des versions publiées, vérifiée par SHA-256 (fichier `checksums.txt` de la version). Les pipelines de `plateforme/secrets` (et de `plateforme/ansible` en E11) tournent sur `runner01` (exécuteur `shell`) : il lui faut le même client, par un rôle Ansible **`openbao_client`** (même archive, binaire seul) appliqué à `adm01` et `runner01`.
- Flux : `runner01`, `runner02` et `K8S_TRAV` (pods de jobs) → 10.10.20.200:8200 sont prévus au PLAN §4.12 ; `vault01` → `git01` 443 (même VLAN : pare-feu local seulement) pour la découverte et les clés.
- La politique `wb-checks` (palier 1) ne lit que des métadonnées ; pour que les vérifications du palier voient la **configuration** des méthodes et des rôles, elle reçoit la lecture de `sys/auth`, `auth/+/role/*`, `auth/+/config`, des `config/*` et `roles/*` des moteurs, et la liste des baux (`sys/leases/lookup/*`). Jamais `kv/data/*`, `*/creds/*`, `*/issue/*`, `*/sign/*`.

> ⚠️ **Attention** : le pipeline de `plateforme/secrets` reçoit la politique `tofu-secrets`, qui peut **tout** changer dans le coffre (politiques, méthodes). Garde jusqu'à la fin de l'exercice une session OIDC `plateforme-admin` ouverte dans un second terminal (`bao token lookup` valide) : si un `apply` du pipeline retire par erreur la méthode `oidc` ou ta politique, c'est elle qui permet de corriger. Retour arrière : `git revert` de la MR et `tofu apply` depuis `adm01` avec cette session.

**Travail demandé**
1. **Relire avant d'écrire.** Dans `~/m25/e10/conception.md`, pour chaque rôle à créer, la liste des revendications liées et leur valeur (avec leur type), et la réponse à trois questions : pourquoi `project_id` plutôt que `project_path` ; pourquoi `ref_protected` **et** `ref` ; que se passerait-il avec `bound_subject` seul ?
2. **Méthode `gitlab/`.** En code dans `plateforme/secrets` : la méthode `jwt` montée en `gitlab/`, configurée par la **découverte OIDC** de GitLab (et non par une clé recopiée), avec l'émetteur lié et la racine MédiSphère comme autorité de confiance. Vérifie depuis `vault01` que la découverte est joignable. Étends la politique `wb-checks` comme indiqué.
3. **Rôles et politiques.** Écris les politiques `ci-mediagenda-api` (lecture du robot Harbor et du jeton de release), `ci-mediagenda-api-promotion` (lecture du seul jeton de promotion), `ci-medidoc-medidoc`, `tofu-secrets`, et les rôles correspondants : audience liée, jetons de type *service* de 10 minutes, revendication d'utilisateur choisie et justifiée, métadonnées utiles à l'audit (référence, pipeline, job) recopiées dans le jeton. `ci-plateforme-secrets` n'est accepté que pour `main` et les branches protégées `conf/*` de `plateforme/secrets`.
4. **Recopier les secrets.** La plateforme dépose les secrets des applications **sans pouvoir les relire** (la politique `plateforme-admin` du palier 1 ne lit pas `kv/<application>/…`) : ajoute-lui un dépôt en écriture seule pour `mediagenda` et `medidoc`. Pour chaque ligne du tableau, écris la valeur dans le coffre **sans qu'elle apparaisse** à l'écran, dans l'historique du shell ou dans `ps` (pense au jeton de projet `ci-promotion` : l'occasion de le **régénérer** plutôt que de recopier l'ancien).
5. **Le composant.** Dans `plateforme/ci-templates` : image `outils-supply-chain:1.1.0` avec `bao` ; composant `securite` **v2.9.0** avec un job caché `.openbao-connexion` (jeton d'identité d'audience `openbao.medisphere.internal`, connexion au rôle du projet déduit de `CI_PROJECT_PATH` ou passé en entrée, jeton OpenBao jamais affiché et révoqué en fin de job) ; `securite:signature` et `securite:verification` lisent le robot Harbor dans le coffre ; composant `promotion` **v2.8.0** qui lit le jeton de promotion avec le rôle `…-promotion` ; même chose pour le composant de release.
6. **Essai du refus.** Dans `formation/ci-labo`, ajoute temporairement un rôle d'essai `ci-formation-ci-labo` (lecture de `kv/formation/ci/essai`) et un job qui lit ce secret ; lance-le sur une branche **non protégée**, puis sur `main`. Note les deux résultats (message exact du refus) dans `~/m25/e10/essais.md`, puis retire le rôle d'essai.
7. **Migration.** Passe `mediagenda/api` et `medidoc/medidoc` aux nouvelles versions des composants ; quand un pipeline de `main` est vert (signature et promotion comprises), **supprime** les variables devenues inutiles (projets et groupes `mediagenda`, `medidoc`) et révoque l'ancien jeton `ci-promotion`.
8. **`plateforme/secrets` se gère lui-même.** Rôle `openbao_client` sur `runner01` ; pipeline : `tofu plan` sur `main` et sur les MR issues de `conf/*`, `tofu apply` manuel sur `main` (environnement GitLab `lab/secrets`), authentifié par `ci-plateforme-secrets`. Aucune variable de CI du projet ne contient de secret : même les accès à l'état OpenTofu (identité S3, phrase de chiffrement) sont lus dans le coffre (`kv/plateforme/tofu/etat-secrets`). Sur un exécuteur `shell`, où ranges-tu le jeton OpenBao du job, sachant que `$HOME` est partagé par tous les jobs du runner ?
9. **Documenter.** `docs/securite/secrets/ci-et-openbao.md` : schéma du chemin d'un job vers un secret, rôles et revendications, ce qui reste en variables et pourquoi ; mets à jour `docs/livraison/ci/secrets-ci.md` (§1 et §5) et l'inventaire (E02).

**Critères de réussite**
- [ ] La méthode `gitlab/` est de type `jwt`, configurée par découverte OIDC avec l'émetteur lié ; tout est sur `main` de `plateforme/secrets` et `tofu plan` est vide.
- [ ] Le rôle `ci-mediagenda-api` lie l'audience `openbao.medisphere.internal`, le `project_id` réel de `mediagenda/api`, `ref_protected` = `"true"`, et émet des jetons de 10 minutes au plus ; sa politique ne lit que le robot Harbor et le jeton de release (pas le jeton de promotion).
- [ ] Un job d'une branche non protégée est refusé à la connexion, le même job sur `main` lit son secret (`~/m25/e10/essais.md`).
- [ ] Le dernier pipeline de `main` de `mediagenda/api` est vert avec le composant `securite` v2.9.0 ; plus aucune variable `HARBOR_ROBOT_*`, `DEPLOIEMENT_TOKEN`, `GITLAB_TOKEN` ni `COSIGN_*` dans le projet ni dans le groupe `mediagenda`.
- [ ] Le dernier `apply` de `plateforme/secrets` a été fait par son pipeline.

**Vérification** : `lab/bin/check 25 10`

<details><summary>Indice 1</summary>

Une liste de valeurs dans `bound_claims` vaut « l'une d'elles » ; pour accepter `main` **et** toutes les étiquettes `v*`, regarde ce que change `bound_claims_type`. Et compare les types : une revendication JSON `"true"` n'est pas le booléen `true`.
</details>

<details><summary>Indice 2</summary>

`bao write auth/gitlab/login role=… jwt=…` met le jeton d'identité dans les arguments du processus. La CLI sait lire la valeur d'un champ sur l'entrée standard (`champ=-`). Pour la suite du job, la CLI cherche son jeton dans `BAO_TOKEN` **ou** dans le fichier de son assistant de jetons (`~/.vault-token`) : lequel survit à `after_script`, qui tourne dans un autre shell ?
</details>

<details><summary>Indice 3</summary>

Un job qui déclare `environment: {name: promotion/recette, action: prepare}` reçoit une revendication `environment` dans son jeton d'identité : c'est elle qui distingue le job de promotion des autres jobs de `main` du même projet. Vérifie dans `secrets-ci.md` §4 son nom exact.
</details>

**Pour aller plus loin** (facultatif) : faire passer les identités de lecture `*_RO_*` dans le coffre avec un rôle sans contrainte de protection (même exposition, mais plus de valeur durable dans GitLab) ; personnaliser `sub` (`ci_id_token_sub_claim_components`) ; lier le jeton de signature au runner protégé (`runner_id`) en préparation d'E20. Documentation : [méthode JWT/OIDC d'OpenBao](https://openbao.org/docs/auth/jwt/), [API de la méthode](https://openbao.org/api-docs/auth/jwt/), [jetons d'identité de GitLab](https://docs.gitlab.com/ci/secrets/id_token_authentication/), [`id_tokens`](https://docs.gitlab.com/ci/yaml/#id_tokens).

---

### M25-E11 — Ansible lit ses secrets dans OpenBao  `LAB` `★★`

> **Ticket PLAT-2611** — *De : Karim Benali*
> Les deux mots de passe Ansible Vault (`lab` et `critique`) sont dans des fichiers de `~/.config/workbook/` et dans deux variables protégées de `plateforme/ansible`. Quiconque a eu un shell sur `adm01` ou la main sur ces variables peut tout déchiffrer, et on ne saurait pas qu'il l'a fait. Je veux que `vault-pass-client.sh` les demande au coffre avec **ta** session SSO, que le pipeline les obtienne avec **son** identité (comme la CI d'E10), et qu'on arrête d'ajouter des secrets dans des fichiers chiffrés quand le coffre peut les servir directement. Garde un bris de glace pour le jour où le coffre est fermé.

**Objectifs pédagogiques**
- Remplacer une source de mot de passe d'Ansible Vault par le coffre sans changer le contrat du script client (`--vault-id`).
- Comprendre qu'une politique OpenBao protège un **chemin**, pas une clé : découper les secrets en conséquence.
- Lire un secret dans un playbook par les lookups de `community.hashi_vault` (connexion, autorité, jeton).
- Garder une procédure de secours quand le coffre est indisponible.

**Prérequis** : M25-E10 (méthode `gitlab/`, client `bao`), M25-E06 (connexion OIDC), M04-E30 (`vault-pass-client.sh`, pipeline protégé de `plateforme/ansible`).
**Durée indicative** : 3 h.

**Contexte technique**
- `outils/vault-pass-client.sh` (M04-E30) : appelé par Ansible pour chaque identité de `vault_identity_list` (`ansible.cfg`), il cherche aujourd'hui `VAULT_PASS_<ID>` (fichier, CI), `VAULT_MDP_<ID>`, puis `~/.config/workbook/ansible-vault[-<id>].pass`. Le contrat reste le même : mot de passe sur la sortie standard, code 0 ou 1, jamais de mot de passe dans un message.
- Chemins KV : **`kv/plateforme/ansible-vault/lab`** et **`kv/plateforme/ansible-vault/critique`**, clé `mot-de-passe`. Politiques **`ansible-lab`** (lecture du premier) et **`ansible-critique`** (lecture du second et des secrets que les playbooks lisent par lookup, sous `kv/plateforme/mailpit/` pour commencer).
- Le pipeline de `plateforme/ansible` tourne sur `runner01` (exécuteur `shell`, utilisateur `gitlab-runner`) ; `VAULT_PASS_CRITIQUE` n'est remise qu'aux jobs de l'environnement `lab/socle` (M04-E30). Rôles JWT à créer : **`ci-plateforme-ansible`** (`main` et `conf/*` protégées, politique `ansible-lab`) et **`ci-plateforme-ansible-critique`** (`main`, environnement `lab/socle`, politique `ansible-critique`).
- `runner01` a le client `bao` depuis E10 (rôle `openbao_client`) et le script `outils/openbao-ci.sh` de `plateforme/secrets` (connexion par le jeton d'identité, jeton OpenBao dans un fichier du répertoire du job, révocation en fin de job) : recopie-le dans `plateforme/ansible`.
- Collection `community.hashi_vault` **7.1.x** (bibliothèque Python `hvac` dans l'environnement `uv` du projet). Premier secret servi par lookup : les comptes de Mailpit sur `mon01` (`host_vars/mon01/mailpit.yml`, aujourd'hui `vault_mailpit_mdp_*` en Vault `critique`), déplacés vers `kv/plateforme/mailpit/comptes` (clés `moi`, `wb-checks`).

> ⚠️ **Attention** : sans mot de passe Ansible Vault, aucun playbook qui touche au socle ne tourne, y compris celui qui réparerait OpenBao. Avant de supprimer le moindre fichier `.pass` ou la moindre variable : (1) range une copie des deux mots de passe dans le coffre hors ligne du module (support chiffré par `age`, même procédure que les parts de E03) et **essaie** la procédure de secours décrite à l'étape 6 ; (2) garde la variable `VAULT_PASS_CRITIQUE` tant qu'un pipeline `appliquer` n'a pas réussi avec le coffre. Retour arrière : recréer les variables protégées depuis la copie hors ligne et revenir à la version précédente du script (`git revert`).

**Travail demandé**
1. **Le découpage.** Écris dans `~/m25/e11/conception.md` pourquoi un seul secret `kv/plateforme/ansible-vault` portant deux clés `lab` et `critique` ne permettrait pas de donner `lab` sans `critique`. Range ensuite les deux mots de passe aux deux chemins (par l'entrée standard, depuis les fichiers actuels).
2. **Politiques et rôles.** En code : `ansible-lab`, `ansible-critique`, les deux rôles JWT ; le groupe externe `plateforme` (Lucas) reçoit `ansible-lab`, les administrateurs gardent tout par `plateforme-admin`. Vérifie, depuis un job d'essai du pipeline (rôle `ci-plateforme-ansible`), avec `bao token capabilities`, que ce jeton ne lit pas `critique`.
3. **Le script.** Réécris `outils/vault-pass-client.sh` : il demande d'abord le coffre (`bao kv get -field=…`) avec le jeton déjà présent (session OIDC d'un humain, jeton du job en CI) ; il ne lit les anciennes sources que si l'on demande **explicitement** le mode secours ; un coffre fermé ou un jeton expiré donnent un message clair (« connecte-toi : bao login -method=oidc »). `shellcheck` propre.
4. **Le pipeline.** Les jobs `.socle` obtiennent leur jeton par `id_tokens` et le bon rôle (lab, ou critique pour l'environnement `lab/socle`), et le révoquent à la fin. Fais passer un pipeline complet de `main` (dont `appliquer`) **avant** de supprimer `VAULT_PASS_LAB` et `VAULT_PASS_CRITIQUE`.
5. **Bris de glace.** Écris la procédure (OpenBao indisponible : où sont les mots de passe, qui les sort, comment on lance un playbook, comment on referme) dans `docs/securite/secrets/ansible-et-openbao.md`, essaie-la une fois (coffre fermé simulé en coupant `BAO_ADDR`), puis supprime les fichiers `~/.config/workbook/ansible-vault*.pass` (`shred`).
6. **Un lookup.** Ajoute `community.hashi_vault` à `collections/requirements.yml`, `hvac` au projet, la section de connexion dans `ansible.cfg` ; déplace les comptes de Mailpit vers `kv/plateforme/mailpit/comptes` et lis-les dans `host_vars/mon01/mailpit.yml` par `community.hashi_vault.vault_kv2_get`. `--check --diff` sur `mon01` : aucun changement attendu (mêmes valeurs). Retire ensuite les deux variables de `host_vars/mon01/vault.yml`.

**Critères de réussite**
- [ ] `kv/plateforme/ansible-vault/lab` et `…/critique` existent ; les politiques `ansible-lab` et `ansible-critique` sont sur `main`, la première ne mentionne pas `critique`.
- [ ] `outils/vault-pass-client.sh` de `main` lit le coffre ; un `ansible-playbook --check` sur `adm01` fonctionne après `bao login -method=oidc` et échoue proprement sans session.
- [ ] Le dernier pipeline de `main` de `plateforme/ansible` est vert et les variables `VAULT_PASS_LAB` / `VAULT_PASS_CRITIQUE` n'existent plus ; plus aucun fichier `ansible-vault*.pass` sur `adm01`.
- [ ] `host_vars/mon01/mailpit.yml` lit ses mots de passe par `vault_kv2_get` ; la procédure de bris de glace est écrite et datée de son essai.

**Vérification** : `lab/bin/check 25 11`

<details><summary>Indice 1</summary>

Le lookup ne passe pas par la CLI `bao` : il utilise `hvac`, qui a son propre magasin d'autorités (pas celui du système) et sa propre façon de trouver le jeton. Lis les options de connexion communes de la collection (`url`, `ca_cert`, `token_path`, `token_file`) et leurs équivalents dans `ansible.cfg`.
</details>

<details><summary>Indice 2</summary>

Dans le pipeline, `vault-pass-client.sh` est appelé par Ansible, lui-même lancé par le job : la CLI `bao` qu'il appelle hérite de l'environnement du job et lit le même fichier de jeton. Il suffit donc que la connexion soit faite **avant** `ansible-playbook`, dans le `before_script` de `.socle`.
</details>

**Pour aller plus loin** (facultatif) : un mot de passe Ansible Vault ne tourne jamais tout seul. Écris le script qui le fait (`ansible-vault rekey` de tous les fichiers d'une identité, nouvelle version KV, essai, MR) et mesure ce qu'il coûte ; c'est un argument pour déplacer, petit à petit, les secrets des fichiers chiffrés vers des lookups. Documentation : [`community.hashi_vault`](https://docs.ansible.com/ansible/latest/collections/community/hashi_vault/index.html), [lookup `vault_kv2_get`](https://docs.ansible.com/ansible/latest/collections/community/hashi_vault/vault_kv2_get_lookup.html), [scripts clients d'Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/vault_managing_passwords.html).

---

### M25-E12 — Méthode Kubernetes et External Secrets Operator  `LAB` `★★`

> **Ticket PLAT-2612** — *De : Claire Morel*
> Le M20 nous a laissé une dette assumée : les Secrets du cluster sont créés par un script, hors de Git, et personne ne les réconcilie. On a maintenant un coffre. Installe l'opérateur qui fera le lien, donne aux pods une façon de prouver qui ils sont auprès d'OpenBao sans aucun mot de passe, et montre-moi un premier Secret qui arrive tout seul dans `wb-essais` depuis le coffre. La migration des vrais Secrets, ce sera le ticket suivant.

**Objectifs pédagogiques**
- Configurer la méthode `kubernetes` d'OpenBao pour un coffre **hors** du cluster : vérification des jetons par l'API TokenReview, audience, autorité du cluster.
- Choisir entre un jeton de vérification dédié et le jeton du client, et en assumer les conséquences RBAC.
- Installer External Secrets Operator 2.13 par Argo CD, comprendre ses objets (SecretStore, ClusterSecretStore, ExternalSecret) et ce que l'opérateur a le droit de faire dans le cluster.
- Restreindre un ClusterSecretStore à des espaces, et donner un SecretStore propre à un espace.

**Prérequis** : M25-E08, M20-E13 (`plateforme/charts-miroir`), M20-E06 (App of Apps), M14-E10 (jetons de compte de service projetés), M24-E16 (ClusterRole `wb-checks-securite`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Méthode à monter : type `kubernetes`, chemin **`k8s-par1/`** ; `kubernetes_host` = `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200 de l'API) ; autorité : la CA du cluster (`certificate-authority-data` de ton kubeconfig, publique). OpenBao ne tourne pas dans un pod : rien à lire localement.
- Deux façons pour OpenBao d'appeler l'API TokenReview : avec un **jeton dédié** (compte de service `openbao-tokenreview`, jeton de longue durée donné à OpenBao), ou avec **le jeton présenté par le client** (chaque compte de service client doit alors pouvoir créer des TokenReview : ClusterRole `system:auth-delegator`). À choisir et à justifier.
- Flux nouveau : `vault01-03` → 10.10.40.200:8443 (à travers la bordure).
- ESO : chart `external-secrets` **2.13.0** (dépôt `https://charts.external-secrets.io`, empreinte de l'archive dans l'index du dépôt), images `ghcr.io/external-secrets/external-secrets` par le cache `ghcr` de Harbor ; release et compte de service **`external-secrets`** dans l'espace **`external-secrets`** (créé par `plateforme/k8s/espaces/`, PSA `restricted`) ; Application **`external-secrets`** de `plateforme/gitops` (projet `plateforme`), valeurs dans `valeurs/external-secrets/values.yaml`, objets d'accompagnement dans `manifestes/external-secrets/`.
- Objets à créer : rôle OpenBao **`eso-plateforme`** (compte `external-secrets/external-secrets`, politique `eso-plateforme`) et **ClusterSecretStore `openbao`** limité aux espaces de plateforme ; dans `wb-essais` : compte de service **`eso`**, rôle **`eso-wb-essais`**, **SecretStore `openbao`**, et un ExternalSecret **`premier-secret`** qui lit `kv/wb-essais/premier-secret`.
- Les vérifications lisent les objets d'ESO par la ClusterRole agrégée `wb-checks-securite` (à étendre ; jamais les Secrets).

> ⚠️ **Attention** : le contrôleur d'ESO lit et écrit **tous** les Secrets du cluster (c'est son métier). Avant d'installer, lis la ClusterRole que rend le chart (`helm template`) et note ce qu'elle permet dans `~/m25/e12/rbac-eso.md`. Ajouter une politique réseau qui sélectionne les pods d'ESO les fait passer en refus par défaut dans ce sens : liste **toutes** leurs sorties (API du cluster, DNS, coffre) avant de l'appliquer, et vérifie les journaux du contrôleur juste après. Retour arrière : `git revert` de la MR, synchronisation.

**Travail demandé**
1. **La méthode.** Monte et configure `k8s-par1/` en code. Réponds dans `~/m25/e12/conception.md` : quel jeton servira à appeler TokenReview, et qu'est-ce que ce choix demande côté RBAC ? Que vérifie OpenBao lui-même dans le jeton présenté, et que lui dit l'API ? Ouvre le flux.
2. **Premier essai, sans ESO.** Dans `wb-essais`, crée le compte `eso` (par `plateforme/k8s`), le rôle `eso-wb-essais` (audience `openbao.medisphere.internal`) et sa politique (lecture de `kv/wb-essais/*`), puis connecte-toi à la main avec un jeton projeté demandé pour ce compte (`kubectl create token … --audience …`). Essaie aussi : un jeton du compte `default`, un jeton sans l'audience, un jeton du bon compte dans un autre espace. Note les trois messages de refus.
3. **ESO.** Ajoute le chart à `charts-miroir`, écris les valeurs (images par Harbor, ressources, ServiceMonitor si la supervision du M21 l'attend), l'Application, l'espace. Lis le rendu avant de fusionner : CRD installées et versions servies (`v1`, `v1beta1`), contrôleurs, webhook, ClusterRole.
4. **Les magasins.** ClusterSecretStore `openbao` (fournisseur `vault`, KV v2, méthode `k8s-par1`, compte `external-secrets`, racine MédiSphère, limité par `conditions` aux espaces de plateforme qui en auront besoin en E13) ; SecretStore `openbao` dans `wb-essais`. Les deux doivent être `Ready`.
5. **Le premier Secret.** Écris une valeur dans `kv/wb-essais/premier-secret` (par l'entrée standard), puis l'ExternalSecret `premier-secret` dans `wb-essais`. Change la valeur dans le coffre, observe le délai avant que le Secret change, et force une relecture. Supprime ensuite l'ExternalSecret : que devient le Secret ? Pourquoi ?
6. **Les droits des checks.** Étends `wb-checks-securite` aux objets d'ESO (ExternalSecret, SecretStore, ClusterSecretStore, PushSecret, générateurs) en lecture, et vérifie par `kubectl auth can-i --as=…` que `wb-checks` lit les ExternalSecret mais toujours pas les Secrets.

**Critères de réussite**
- [ ] La méthode `k8s-par1/` est de type `kubernetes` ; les rôles `eso-plateforme` et `eso-wb-essais` exigent l'audience `openbao.medisphere.internal` et un seul compte de service dans un seul espace.
- [ ] L'Application `external-secrets` est `Synced` et `Healthy` ; le ClusterSecretStore `openbao` est `Ready` et limité à une liste d'espaces.
- [ ] Le SecretStore `openbao` et l'ExternalSecret `premier-secret` de `wb-essais` sont `Ready` ; `~/m25/e12/conception.md` répond aux questions de l'étape 1 et note les trois refus de l'étape 2.
- [ ] `wb-checks` lit les ExternalSecret mais pas les Secrets.

**Vérification** : `lab/bin/check 25 12`

<details><summary>Indice 1</summary>

`kubectl create token` accepte `--audience` et `--duration`. Décode le jeton obtenu (deuxième segment, base64url) pour voir `aud`, `sub` et la date d'expiration : c'est exactement ce qu'OpenBao compare à son rôle.
</details>

<details><summary>Indice 2</summary>

Dans un SecretStore ESO, la référence de compte de service accepte une liste `audiences` : sans elle, le jeton demandé par ESO porte l'audience par défaut de l'API du cluster. Et le chemin du moteur s'écrit **sans** `data/` : c'est la `version` du fournisseur qui dit à ESO de l'ajouter.
</details>

<details><summary>Indice 3</summary>

Pour forcer une relecture sans attendre `refreshInterval`, ESO surveille une annotation de l'ExternalSecret (voir le guide « Force refresh » de la documentation). Dans `wb-essais`, où tu as le droit d'écrire, c'est permis ; ailleurs, c'est Argo CD qui porte l'objet.
</details>

**Pour aller plus loin** (facultatif) : comparer avec la méthode `jwt` d'OpenBao configurée sur la découverte OIDC du serveur d'API (jetons vérifiés hors ligne, sans TokenReview) : ce qu'on gagne (aucun flux vers l'API, aucun droit RBAC), ce qu'on perd (un jeton d'un compte supprimé reste valable jusqu'à son expiration). Documentation : [méthode Kubernetes d'OpenBao](https://openbao.org/docs/auth/kubernetes/), [ESO : fournisseur HashiCorp Vault](https://external-secrets.io/latest/provider/hashicorp-vault/), [ClusterSecretStore](https://external-secrets.io/latest/api/clustersecretstore/), [cycle de vie des Secrets d'ESO](https://external-secrets.io/latest/guides/ownership-deletion-policy/).

---

### M25-E13 — Migrer les Secrets hors Git vers des ExternalSecret  `LAB` `★★★`

> **Ticket PLAT-2613** — *De : Karim Benali*
> On solde la dette du M20. Tout ce que `secrets-k8s.sh` pousse dans le cluster doit venir du coffre par un ExternalSecret versionné, synchronisé par Argo CD, et aucun pod ne doit s'en apercevoir : même nom de Secret, mêmes clés, mêmes valeurs, aucun redémarrage. Les équipes MédiAgenda et MédiDoc auront leurs propres magasins, pas le nôtre. Je veux la liste de ce qui a migré, de ce qui reste, et pourquoi.

**Objectifs pédagogiques**
- Inventorier ce qu'un script hors Git a créé dans un cluster, et le reprendre sans coupure (adoption d'un Secret existant par l'opérateur).
- Recopier des valeurs d'un endroit à un autre sans jamais les afficher, et prouver qu'elles sont identiques.
- Organiser les ExternalSecret : où ils vivent, qui les synchronise, quel magasin ils utilisent, quel délai de rafraîchissement.
- Donner à chaque équipe un accès au coffre limité à son espace.

**Prérequis** : M25-E12 (ESO, ClusterSecretStore, méthode `k8s-par1`), M20-E06 à E28 (Argo CD, `secrets-k8s.sh` et ses modules), M24-E12, E13, E18 (Secrets `grafana-oidc`, `argocd-oidc`, `oauth2-proxy-oidc`).
**Durée indicative** : 5 h.

**Contexte technique**
- Les Secrets créés par `secrets-k8s.sh` portent l'étiquette `medisphere.internal/source=ansible-vault` (M19-E04, M20-E06) ; d'autres scripts plus anciens (M15, M16) en créent sans cette étiquette : leur liste est au registre des secrets (M16-E23, M17-E15) et dans l'inventaire d'E02.
- Règle de nommage KV : `kv/plateforme/<composant>/<secret>` (ex. `kv/plateforme/argocd/oidc`, `kv/plateforme/grafana/admin`, `kv/plateforme/gitlab-runner/jeton`) ; pour les applications `kv/<application>/<env>/<secret>` (ex. `kv/mediagenda/recette/harbor-pull`, `kv/medidoc/recette/s3`). Dans le coffre, les clés d'un secret sont **celles du Secret Kubernetes** qu'il alimente.
- ExternalSecret de plateforme : `plateforme/gitops`, dossier `secrets/<espace>/`, Application **`secrets-plateforme`** (projet `plateforme`, destinations limitées aux espaces concernés) ; ExternalSecret d'application : `mediagenda/deploiement` et `medidoc/deploiement` (overlays). Chaque espace applicatif reçoit, par `plateforme/k8s/espaces/<espace>/`, un compte de service **`eso`**, un **SecretStore `openbao`**, et dans le coffre un rôle et une politique **`eso-<espace>`** limités à `kv/data/<application>/<env>/*`.
- Les Secrets que lit **Argo CD** (dépôts, OIDC) doivent garder l'étiquette `app.kubernetes.io/part-of: argocd` (ou `argocd.argoproj.io/secret-type`) ; ceux de type `kubernetes.io/dockerconfigjson` gardent leur type.
- Hors périmètre de ce ticket : la clé Cosign (`ci-jobs-protege/cosign-medisphere`, E20), les Secrets d'amorçage (racine MédiSphère `gitlab-runner-certs`), et ce qui n'existe plus (essais retirés, `cluster-lyo-k3s01`). Le retrait du script lui-même est au mini-projet.

> ⚠️ **Attention** : si un ExternalSecret écrit des clés différentes de celles qu'attend un pod, ce pod ne le verra qu'à son prochain redémarrage… et ne démarrera plus. Migre **un Secret à la fois**, compare avant de passer au suivant, et commence par un composant qui se relit à chaud ou que tu peux redémarrer sans risque (Grafana avant Argo CD, la recette avant la prod). Pour Argo CD lui-même, garde ouverte une session `kubectl` avec `admin.conf` (bris de glace, M24) : si ses Secrets de dépôt cassent, il ne peut plus synchroniser l'Application qui les répare. Retour arrière d'un Secret : supprimer l'ExternalSecret avec `--cascade=orphan`, puis `secrets-k8s.sh appliquer <composant>`.

**Travail demandé**
1. **Inventaire.** Liste les Secrets concernés (étiquette, registre, inventaire E02), et pour chacun : espace, nom, clés (jamais les valeurs), qui le consomme et comment (variable d'environnement, fichier, lu par un opérateur), s'il se relit à chaud. Résultat dans `~/m25/e13/inventaire.md`, avec la colonne « chemin KV » et la colonne « migré le ».
2. **Un outil de recopie.** Écris dans `plateforme/k8s` un petit script qui recopie un Secret existant du cluster vers un chemin KV (clés et valeurs identiques), sans rien afficher ni écrire sur le disque, et qui refuse d'écraser un chemin KV qui existe déjà. `shellcheck` propre.
3. **La plateforme.** Pour chaque Secret de plateforme : recopie, ExternalSecret du même nom dans `secrets/<espace>/` de `plateforme/gitops` (magasin `openbao` de cluster), MR, synchronisation de `secrets-plateforme`. Vérifie à chaque fois que l'opérateur a **adopté** le Secret (propriétaire, données inchangées) et qu'aucun pod n'a redémarré.
4. **Les équipes.** Pour `mediagenda-dev/-recette/-prod` et `medidoc-dev/-recette` : compte `eso`, SecretStore, rôle et politique `eso-<espace>`, puis les ExternalSecret (`harbor-pull`, `medidoc-s3`) dans les dépôts de déploiement, par MR relue par l'équipe. Vérifie qu'un ExternalSecret de `mediagenda-recette` qui viserait `kv/medidoc/…` est refusé.
5. **Comparer.** Prouve, Secret par Secret, que la valeur d'après est celle d'avant **sans l'afficher** (empreintes, ou le `verifier` de `secrets-k8s.sh` qui lit toujours le Vault Ansible). Garde les preuves dans `~/m25/e13/comparaison.md`.
6. **Ranger.** Commente les lignes migrées de `secrets-k8s.conf` (et désactive les modules `secrets-k8s.d/` concernés) avec la mention de l'exercice ; mets à jour le registre des secrets, l'inventaire E02, et la liste des ressources orphelines ignorées des AppProjects (`orphanedResources`).

**Critères de réussite**
- [ ] Chaque Secret de plateforme de l'inventaire a son ExternalSecret `Ready` dans `plateforme/gitops` ; l'Application `secrets-plateforme` est `Synced` et `Healthy`.
- [ ] Les espaces `mediagenda-*` et `medidoc-*` ont un SecretStore `openbao` `Ready` et des ExternalSecret `Ready` pour `harbor-pull` (et `medidoc-s3`).
- [ ] `secrets-k8s.conf` ne garde actives que les lignes d'amorçage ; `~/m25/e13/inventaire.md` et `comparaison.md` couvrent chaque Secret, sans aucune valeur.
- [ ] Les Applications de plateforme et de recette sont toutes `Healthy` après la migration.

**Vérification** : `lab/bin/check 25 13`

<details><summary>Indice 1</summary>

Lis dans la documentation d'ESO ce que fait la politique de création par défaut (`Owner`) quand le Secret cible existe déjà **sans** propriétaire. C'est ce qui rend la reprise transparente… à condition que les clés soient exactement les mêmes.
</details>

<details><summary>Indice 2</summary>

`kubectl get secret … -o json | jq '.data | map_values(@base64d)'` donne un objet JSON clé → valeur ; `bao kv put` sait lire un objet JSON sur son entrée standard. Rien ne passe par l'écran si tu ne l'affiches pas. Et `bao kv metadata get` te dit si un chemin existe déjà.
</details>

<details><summary>Indice 3</summary>

Un modèle (`target.template`) qui ne pose que des étiquettes ou un type remplace par défaut **toutes** les données par… rien. Cherche `mergePolicy`.
</details>

**Pour aller plus loin** (facultatif) : `ClusterExternalSecret` pour un Secret identique dans plusieurs espaces (la racine MédiSphère publique, par exemple) ; `PushSecret` (`v1alpha1`) pour le chemin inverse (un Secret généré dans le cluster, sauvegardé dans le coffre). Documentation : [ExternalSecret](https://external-secrets.io/latest/api/externalsecret/), [modèles](https://external-secrets.io/latest/guides/templating/), [générateurs d'ESO](https://external-secrets.io/latest/guides/generator/).

---

### M25-E14 — Identifiants dynamiques PostgreSQL pour MédiAgenda  `LAB` `★★★`

> **Ticket DEV-2614** — *De : Julien Petit*
> Le mot de passe de `mediagenda` en recette n'a pas changé depuis le M16 et il ouvre **tout** : lecture, écriture, `DROP TABLE`. L'API n'a besoin que de lire et d'écrire des lignes ; seules les migrations touchent au schéma. Sophie propose que le coffre fabrique pour chaque instance de l'API un compte PostgreSQL qui expire au bout d'une heure, et un autre, plus puissant, pour le job de migration. Je suis d'accord si les déploiements continuent à marcher et si on peut me montrer, dans la base, les comptes qui naissent et qui meurent.

**Objectifs pédagogiques**
- Configurer le moteur `database` d'OpenBao pour PostgreSQL : connexion, rôle d'administration, rotation de son mot de passe, rôles dynamiques.
- Écrire des instructions de création et de révocation correctes : droits minimaux, objets toujours possédés par le propriétaire de la base, expiration.
- Exposer une base CloudNativePG à un client hors du cluster, au plus juste (adresse, filtrage, TLS vérifié).
- Livrer des identifiants dynamiques à un pod par un générateur ESO, et comprendre ce qui se passe à l'expiration d'un bail.

**Prérequis** : M25-E13 (SecretStore `openbao` de `mediagenda-recette`, rôle `eso-mediagenda-recette`), M16-E18 (Cluster `mediagenda-db` de la recette), M20-E11 (Job de migration en hook), M17-E09 (`database.existingSecret` du chart).
**Durée indicative** : 5 h.

**Contexte technique**
- Bases : recette = Cluster CNPG `mediagenda-db` de `plateforme/k8s/espaces/mediagenda-recette/` (3 instances, PostgreSQL 18) ; prod = Cluster `mediagenda-db` de `mediagenda/deploiement` (`components/dependances`). Base `mediagenda`, propriétaire `mediagenda` ; l'API et le Job de migration lisent aujourd'hui l'URL dans le Secret `mediagenda-db-app` (clé `uri`) que CNPG crée pour le propriétaire.
- Moteur `database` monté en **`db-mediagenda/`**, greffon `postgresql-database-plugin` ; connexions **`mediagenda-recette`** et **`mediagenda-prod`** ; rôles **`mediagenda-api-<env>`** (lire, écrire des lignes) et **`mediagenda-migrateur-<env>`** (schéma), TTL 1 h, max 24 h.
- Côté PostgreSQL : un rôle **`openbao`** déclaré dans `spec.managed.roles` du Cluster (connexion, `CREATEROLE`), dont le mot de passe initial est remplacé par OpenBao dès la configuration (`rotate-root`) ; un rôle de groupe sans connexion **`mediagenda_api`** porteur des droits de l'API. Depuis PostgreSQL 16, un rôle `CREATEROLE` ne peut donner l'appartenance à un rôle que s'il en a l'**option ADMIN**.
- Exposition : Service `LoadBalancer` supplémentaire géré par CNPG (`spec.managed.services.additional`, sélecteur `rw`), adresse demandée **10.10.41.64** (recette) / **10.10.41.65** (prod) par l'annotation de Cilium LB IPAM, `externalTrafficPolicy: Local` ; CiliumNetworkPolicy qui n'ouvre 5432 qu'à 10.10.20.21-23 ; flux `vault01-03` → 10.10.41.64-65:5432 (PLAN §4.12). Le certificat serveur de CNPG est signé par la CA propre au Cluster (Secret `mediagenda-db-ca`, clé publique `ca.crt`), qui ne contient pas l'adresse 10.10.41.64.
- ESO : générateurs **`VaultDynamicSecret`** (`generators.external-secrets.io/v1alpha1`) nommés `mediagenda-api` et `mediagenda-migrateur` dans chaque espace (par `plateforme/k8s`), ExternalSecret **`mediagenda-db-api`** et **`mediagenda-db-migrateur`** (clé `uri` au format attendu par l'application) dans un component `components/identifiants-dynamiques` de `mediagenda/deploiement`, `refreshInterval` 30 min.

> ⚠️ **Attention** : un identifiant dynamique **meurt** à la fin de son bail, et avec lui les sessions ouvertes. Un pod qui a lu l'ancien mot de passe au démarrage perd sa base au plus tard une heure après le premier rafraîchissement d'ESO, tant que rien ne le redémarre : c'est l'objet d'E15. Enchaîne donc E14 et E15 **d'une traite** ; ne bascule la recette (étape 7) qu'au moment où tu peux poursuivre, et ne bascule **pas** la prod dans cet exercice (elle l'est à la fin d'E15). Retour arrière de la recette : `git revert` du component dans `mediagenda/deploiement` (l'API revient au Secret `mediagenda-db-app`, qui n'a pas changé). Le rôle `openbao` ne doit jamais recevoir le droit `SUPERUSER`.

**Travail demandé**
1. **Comprendre sur un banc.** Avant de toucher à la recette, essaie le moteur contre une base jetable de `wb-essais` (Cluster CNPG d'une instance, M16) : connexion, rôle dynamique, `bao read …/creds/…`, connexion `psql` avec l'identifiant obtenu, révocation du bail **pendant** une session ouverte. Note dans `~/m25/e14/banc.md` ce que devient la session.
2. **La base.** Dans le Cluster de recette (MR `plateforme/k8s`) : rôles gérés `openbao` et `mediagenda_api`, Service supplémentaire 10.10.41.64, politique réseau. Puis, une seule fois, le SQL de préparation versionné (droits de `mediagenda_api` sur les tables présentes et futures, option ADMIN de `openbao` sur les deux rôles de groupe **sans** hériter de leurs droits), joué en superutilisateur par `kubectl cnpg psql`. Contrôle `pg_auth_members`.
3. **La connexion.** Le mot de passe initial de `openbao` est produit dans le cluster (générateur ESO `Password`, une seule fois) : passe-le à OpenBao sans l'afficher, puis fais-le tourner aussitôt. La connexion vérifie le certificat de la base : choisis le `sslmode` qui marche avec la CA de CNPG et une adresse IP, et dépose la CA sur `vault01` par Ansible. Retire ensuite `passwordSecret` du rôle géré et le Secret initial : pourquoi ?
4. **Les rôles.** Une politique de mot de passe compatible avec une URL, puis `mediagenda-api-recette` (appartenance à `mediagenda_api`, `VALID UNTIL`) et `mediagenda-migrateur-recette` (objets créés **appartenant à `mediagenda`**, sans que le migrateur soit superutilisateur). Révocation : le compte disparaît. Tout en code dans `plateforme/secrets` (le mot de passe de connexion n'entre jamais dans l'état OpenTofu).
5. **Observer.** Demande trois identifiants, regarde-les dans `pg_roles` (nom, `rolvaliduntil`), liste les baux (`bao list sys/leases/lookup/…`), révoque-en un, renouvelle-en un autre jusqu'à atteindre le maximum. Avec un identifiant `migrateur`, crée une table d'essai : à qui appartient-elle ? Avec un identifiant `api`, essaie de la supprimer.
6. **Prod (préparation).** Même chose côté coffre et base pour la prod (Cluster de `mediagenda/deploiement`, MR relue par Julien, 10.10.41.65), sans changer encore ce que lit l'application.
7. **Recette (bascule).** Générateurs dans `plateforme/k8s/espaces/mediagenda-recette/`, rôle `eso-mediagenda-recette` étendu aux deux chemins `creds`, component `identifiants-dynamiques` (ExternalSecret, et remplacement du Secret lu par l'API et par le Job de migration) inclus dans l'overlay de recette. Après synchronisation : migration réussie, `/pret` en 200, comptes `v-…` visibles dans `pg_stat_activity`.
8. **Documenter** dans `docs/securite/secrets/identifiants-dynamiques.md` : schéma, durées, qui crée et qui supprime chaque compte, ce qui se passe à l'expiration, procédure de retour au compte propriétaire.

**Critères de réussite**
- [ ] `db-mediagenda/` est un moteur `database` ; les connexions `mediagenda-recette` (10.10.41.64, certificat vérifié) et `mediagenda-prod` (10.10.41.65) et les quatre rôles (TTL 1 h, max 24 h) sont en code.
- [ ] Un identifiant `api` peut écrire une ligne mais pas supprimer une table ; une table créée par un identifiant `migrateur` appartient à `mediagenda` (`~/m25/e14/observations.md`).
- [ ] Le Service 10.10.41.64 existe et n'accepte que `vault01-03` ; aucun mot de passe du rôle `openbao` n'est connu d'un humain.
- [ ] En recette, les ExternalSecret `mediagenda-db-api` et `mediagenda-db-migrateur` sont `Ready`, au moins un bail `mediagenda-api-recette` est actif, et `https://mediagenda-recette.apps.par1.medisphere.internal/pret` répond 200.

**Vérification** : `lab/bin/check 25 14`

<details><summary>Indice 1</summary>

Dans les instructions de création, `{{name}}`, `{{password}}` et `{{expiration}}` sont remplacés par OpenBao. PostgreSQL permet de fixer **pour un rôle** la valeur par défaut d'un paramètre de session (`ALTER ROLE … SET …`) : cherche quel paramètre ferait que tout ce qu'une session crée appartienne à un autre rôle.
</details>

<details><summary>Indice 2</summary>

`sslmode=verify-full` compare le nom (ou l'adresse) demandé au certificat ; `verify-ca` ne vérifie que la chaîne. Et regarde **quelles** options de connexion le greffon d'OpenBao 2.6 accepte réellement : une option enregistrée sans erreur n'est pas forcément une option utilisée.
</details>

<details><summary>Indice 3</summary>

Relis la page « déclaration des rôles » de CloudNativePG : quand l'opérateur réapplique-t-il le mot de passe d'un rôle géré, et que fait-il des appartenances non listées dans `inRoles` ? Les deux réponses changent ce que tu dois déclarer, et ce que tu dois retirer après `rotate-root`.
</details>

**Pour aller plus loin** (facultatif) : rôles **statiques** (`static-roles`) pour un compte qui doit garder son nom (un outil d'extraction qui ne sait pas changer d'utilisateur) ; PgBouncer de CNPG (`Pooler`) devant des comptes dynamiques. Documentation : [moteur database d'OpenBao](https://openbao.org/docs/secrets/databases/), [PostgreSQL](https://openbao.org/docs/secrets/databases/postgresql/), [rôles gérés de CloudNativePG](https://cloudnative-pg.io/documentation/current/declarative_role_management/), [générateur VaultDynamicSecret d'ESO](https://external-secrets.io/latest/api/generator/vault/).

---

### M25-E15 — Tourner un secret sans redémarrage manuel  `LAB` `★★★`

> **Ticket SEC-2615** — *De : Sophie Laurent*
> Depuis E14, les comptes de MédiAgenda changent toutes les demi-heures en recette, et quelqu'un doit redémarrer l'API avant que l'ancien compte ne meure : ce n'est pas tenable. Même chose pour les clés S3 de MédiDoc, que l'audit HDS veut voir changer chaque trimestre. Je veux qu'une rotation se fasse **dans le coffre**, et que le reste suive tout seul : le Secret change, les pods qui le lisent redémarrent proprement, sans coupure, et sans que ce redémarrage apparaisse comme une dérive dans Argo CD. Ensuite seulement, la prod passe aux identifiants dynamiques.

**Objectifs pédagogiques**
- Faire suivre à une charge de travail le changement d'un Secret qu'elle ne relit pas à chaud : comparer les solutions (Reloader, empreinte dans le gabarit, relecture par l'application) et en choisir une.
- Redémarrer un `Rollout` d'Argo Rollouts sans créer de nouvelle révision (pas de canary pour un simple changement de secret).
- Tourner une clé à double valeur (deux clés d'accès actives pendant la bascule) sans coupure.
- Tourner le mot de passe d'administration d'une connexion de base, et savoir ce que cela change (ou pas) pour les identifiants déjà délivrés.

**Prérequis** : M25-E14 (recette en identifiants dynamiques), M25-E13 (`medidoc-s3` par ESO), M20-E16 (Rollout `mediagenda` en `workloadRef`), M20-E33 (compte RGW `medidoc-recette`).
**Durée indicative** : 4 h.

**Contexte technique**
- **Reloader 1.4.22** (stakater, chart `reloader` **2.2.18** du dépôt `https://stakater.github.io/stakater-charts`, image `ghcr.io/stakater/reloader:v1.4.22`) : surveille les Secrets et ConfigMaps et redémarre les charges de travail annotées ; prise en charge d'Argo Rollouts à activer, stratégie par Rollout (`reloader.stakater.com/rollout-strategy`), restriction possible à une liste d'espaces (rôles d'espace au lieu d'une ClusterRole). Application `reloader`, espace `reloader`.
- MédiAgenda (recette, prod) : le `Rollout` `mediagenda` ne porte pas de gabarit de pod (`workloadRef` vers le Deployment rendu par le chart) ; toute modification du gabarit du Deployment crée une nouvelle révision et donc un canary complet avec analyses (≈ 8 min).
- MédiDoc (recette) : Deployment `medidoc`, Secret `medidoc-s3` lu en variables d'environnement ; le compte RGW `medidoc-recette` est un utilisateur IAM du RGW (M20-E33) : deux clés d'accès au plus par utilisateur.
- Délais : `refreshInterval` d'ESO 30 min pour les identifiants dynamiques (E14), à ramener à **5 min** pour `medidoc-s3` ; bail des identifiants dynamiques 1 h.

> ⚠️ **Attention** : un redémarrage automatique est aussi un **déclencheur automatique de coupure** si la charge de travail ne survit pas à un redémarrage (une seule réplique, pas de budget de perturbation, sonde de disponibilité fausse). Vérifie, avant d'activer Reloader sur une charge de travail, qu'un `kubectl argo rollouts restart` (ou un `rollout restart`) fait à la main ne coupe rien (requêtes en boucle sur `/pret` pendant l'essai). Retour arrière : retirer l'annotation par `git revert` ; Reloader ne touche plus à la charge de travail.

**Travail demandé**
1. **Choisir.** Dans `~/m25/e15/choix.md`, compare trois façons de redémarrer sur changement d'un Secret : Reloader, une empreinte du Secret dans une annotation du gabarit (calculée où ? par qui ?), une application qui relit ses fichiers. Laquelle convient à un Secret fabriqué **dans** le cluster par ESO ? Laquelle convient à un `Rollout` en `workloadRef` ? Choisis, et note la version et la date de publication de ce que tu retiens.
2. **Installer.** Chart dans `charts-miroir`, valeurs (Argo Rollouts activé, espaces limités à ceux des applications, stratégie de rechargement qui ne touche qu'aux annotations), Application, espace. Lis le rendu : quels droits sur les Secrets ?
3. **MédiAgenda.** Annote le Rollout (dans le component `identifiants-dynamiques`) pour qu'il redémarre quand `mediagenda-db-api` change, **sans nouvelle révision**. Laisse passer un rafraîchissement d'ESO (ou force-le dans `wb-essais` sur un banc identique) et observe : nouveau Secret, redémarrage pod par pod, aucune erreur dans une boucle de requêtes sur `/pret`, anciens comptes révoqués à la fin de leur bail. Chronomètre l'écart entre le rafraîchissement et la fin du redémarrage.
4. **MédiDoc.** Ramène `medidoc-s3` à 5 min, annote le Deployment. Rotation : nouvelle clé d'accès IAM, écrite dans le coffre (nouvelle version KV) sans passer par l'écran ; attends le redémarrage ; prouve que les pods utilisent la nouvelle clé (envoi d'un document de test) ; **puis** supprime l'ancienne clé. Note l'heure de chaque étape.
5. **La racine de la connexion.** Fais tourner le mot de passe de `openbao` (`rotate-root`) en recette : les identifiants déjà délivrés continuent-ils à fonctionner ? Qui connaît désormais ce mot de passe ? Comment la plateforme reprend-elle la main si OpenBao perd cette connexion (bris de glace par le superutilisateur de CNPG) ?
6. **La prod.** Inclus le component `identifiants-dynamiques` dans l'overlay de prod (MR approuvée par Julien et Karim), synchronise à la main, et vérifie `/pret` de la prod.
7. **Journal.** `~/m25/e15/journal.md` : horodatages des deux rotations, délais mesurés, ce qu'on alerterait (E27). Complète `docs/securite/secrets/identifiants-dynamiques.md`.

**Critères de réussite**
- [ ] L'Application `reloader` est `Healthy` ; Reloader ne surveille que les espaces applicatifs choisis.
- [ ] Le Rollout `mediagenda` de la recette redémarre seul quand `mediagenda-db-api` change, sans nouvelle révision ; aucune erreur `/pret` pendant le redémarrage (`~/m25/e15/journal.md`).
- [ ] `kv/medidoc/recette/s3` a une nouvelle version ; l'ancienne clé d'accès est supprimée du RGW ; MédiDoc recette répond.
- [ ] La prod lit `mediagenda-db-api` (ExternalSecret `Ready` dans `mediagenda-prod`) et `/pret` de la prod répond 200.

**Vérification** : `lab/bin/check 25 15`

<details><summary>Indice 1</summary>

Un `Rollout` en `workloadRef` n'a pas de gabarit de pod : un outil qui découvre les Secrets **référencés par le gabarit** ne trouvera rien. Cherche l'annotation de Reloader qui nomme explicitement les Secrets à surveiller, et ce que fait sa stratégie `restart` sur un Rollout (un champ du `spec` d'Argo Rollouts).
</details>

<details><summary>Indice 2</summary>

Pour la clé S3 : tant que l'ancienne clé existe, les pods qui ne l'ont pas encore quittée continuent à fonctionner. L'ordre « créer, distribuer, constater, supprimer » est celui de toute rotation sans coupure ; c'est le **constater** qu'on oublie.
</details>

**Pour aller plus loin** (facultatif) : faire relire à MédiAgenda son URL de base dans un **fichier** monté (le Secret projeté est mis à jour sans redémarrage) et reconnecter son pool à l'erreur d'authentification : plus aucun redémarrage du tout. Documentation : [Reloader](https://github.com/stakater/Reloader), [redémarrer un Rollout](https://argo-rollouts.readthedocs.io/en/stable/features/restart/), [rotation des identifiants racine d'OpenBao](https://openbao.org/api-docs/secret/databases/#rotate-root-credentials), [clés d'accès IAM du RGW](https://docs.ceph.com/en/tentacle/radosgw/account/).

---

### M25-E16 — PKI de services : « MédiSphère Services CA » et cert-manager  `LAB` `★★★`

> **Ticket SEC-2616** — *De : Sophie Laurent*
> Au M23, MédiAgenda a commencé à envoyer les pièces jointes des patients à MédiDoc, en HTTP clair, à l'intérieur du cluster. Une politique réseau dit qui a le droit de parler, mais rien ne prouve **qui** parle, et rien ne chiffre. Je veux du TLS mutuel entre les deux en recette, avec des certificats qui durent quelques heures, émis par une autorité à nous, subordonnée à la racine et signée en cérémonie, comme celle de FreeIPA. Et je veux savoir comment on révoque.

**Objectifs pédagogiques**
- Monter une autorité intermédiaire dans OpenBao dont la clé ne sort jamais du coffre : CSR, cérémonie de signature par la racine hors ligne, import de la chaîne.
- Écrire un rôle d'émission au plus juste (noms, durées, usages) et publier les points de distribution (AIA, CRL, OCSP).
- Faire émettre et renouveler des certificats par cert-manager avec la méthode `kubernetes` (ClusterIssuer `vault`).
- Ajouter le TLS mutuel entre deux applications sans toucher à leur code (relais TLS en conteneur annexe), et vérifier la révocation.

**Prérequis** : M25-E12 (méthode `k8s-par1`), M24-E02 (cérémonie `ceremonie-ca.md`), M06-E02 (`ceremonie-pki.sh`), M15 (cert-manager 1.21, Helmfile), M23-E06 (appel MédiAgenda → MédiDoc et ses politiques réseau).
**Durée indicative** : 5 h.

**Contexte technique**
- Moteur `pki` monté en **`pki-services/`**, durée maximale 3 ans ; CA intermédiaire **« MédiSphère Services CA »** (clé EC P-256 générée **dans** OpenBao), signée par « MédiSphère Root CA » avec `ceremonie-pki.sh signer` (profil `intermediate-ca`, `pathlen:0`), durée **3 ans** (la variable `DUREE_INTERMEDIAIRE` du script) ; CSR et certificat versionnés dans `pki/` de `plateforme/ansible`, procès-verbal ajouté à `docs/securite/identite/ceremonie-ca.md`.
- Points de distribution : `https://openbao.par1.medisphere.internal:8200/v1/pki-services/ca`, `…/crl`, `…/ocsp` ; durée de la CRL 72 h, reconstruction automatique.
- Rôle **`services-k8s`** : noms sous `svc` et `svc.cluster.local` uniquement, pas d'adresse IP, pas de `localhost`, usages serveur **et** client, durée par défaut 24 h, maximum **72 h**, clés EC P-256.
- cert-manager 1.21 (couche de base sous Helmfile, `plateforme/k8s`) : ClusterIssuer **`openbao-services`** (émetteur `vault`, chemin `pki-services/sign/services-k8s`, méthode `kubernetes` montée en `k8s-par1`, compte de service **`openbao-emetteur`** de l'espace `cert-manager`, audience `openbao.medisphere.internal`) ; politique et rôle OpenBao **`cert-manager-services`**.
- Relais TLS : **ghostunnel 1.11.5** (`ghostunnel/ghostunnel:v1.11.5-distroless` par le cache Docker Hub de Harbor), en conteneur annexe natif (`initContainers` avec `restartPolicy: Always`) ; côté MédiDoc en mode `server` (écoute 8443, vers `127.0.0.1:8080`), côté MédiAgenda en mode `client` (écoute `127.0.0.1:8081`, vers `medidoc.medidoc-recette.svc.cluster.local:8443`) ; rechargement périodique des certificats renouvelés.
- MédiAgenda appelle aujourd'hui `MEDIAGENDA_MEDIDOC_URL=http://medidoc.medidoc-recette.svc.cluster.local` ; les politiques réseau du M23 (`mediagenda-sortie-medidoc`, `medidoc-entree-mediagenda`) ouvrent le port 8080.

> ⚠️ **Attention** : la clé de la racine ne sort que pendant la cérémonie, sur `adm01`, hors de toute session partagée, et la phrase de passe se tape au clavier. Ne génère **jamais** la clé de l'intermédiaire hors d'OpenBao (`…/intermediate/generate/internal`, pas `exported`). Côté recette, l'appel MédiAgenda → MédiDoc est coupé si le relais TLS ou le certificat manque : bascule MédiDoc d'abord en **écoutant les deux ports** (8080 et 8443), puis MédiAgenda, puis ferme 8080 à MédiAgenda. Retour arrière : `git revert` dans l'ordre inverse.

**Travail demandé**
1. **La CSR.** Monte `pki-services/` en code (durées, URL), fais générer la clé et la CSR de « MédiSphère Services CA » par OpenBao, versionne la CSR. Que contient-elle, que ne contient-elle pas ?
2. **La cérémonie.** Suis `ceremonie-ca.md` à la lettre (relecture de la CSR par le témoin, signature trois ans, contrôle, archive), importe la chaîne dans OpenBao, vérifie l'émetteur par défaut, remplis le procès-verbal. Contrôle depuis `adm01` que le certificat publié (`…/pki-services/ca/pem`) se vérifie contre la racine.
3. **Le rôle et la CRL.** Rôle `services-k8s` en code ; essaie trois demandes refusées ou réduites (un nom hors de `svc`, une adresse IP, 100 h) et note ce qu'OpenBao répond à chacune. Configure la CRL et le ménage automatique des certificats expirés.
4. **cert-manager.** Politique et rôle `cert-manager-services`, compte `openbao-emetteur` et le droit pour cert-manager de lui demander des jetons, ClusterIssuer `openbao-services` (racine MédiSphère pour joindre OpenBao). Émets un certificat d'essai dans `wb-essais`, regarde la `CertificateRequest`, le Secret, la durée, la chaîne.
5. **Le TLS mutuel.** Certificats `medidoc-mtls` (dans `medidoc-recette`) et `mediagenda-mtls` (dans `mediagenda-recette`) : noms de leurs Services, usages, durée et renouvellement. Relais côté MédiDoc (port `https` 8443 ajouté au Service, client accepté seulement s'il présente un certificat de la Services CA au nom du Service de MédiAgenda), puis côté MédiAgenda (`MEDIAGENDA_MEDIDOC_URL` vers le relais local), puis politiques réseau sur 8443 et retrait de 8080 pour MédiAgenda. Prouve l'appel de bout en bout (création d'un rendez-vous avec pièce jointe en recette) et le refus d'un client sans certificat depuis un pod de `mediagenda-recette`.
6. **Révoquer.** Révoque le certificat courant de MédiAgenda dans OpenBao, relis la CRL (`openssl crl`), et constate ce que fait (ou ne fait pas) le relais de MédiDoc. Conclus dans `docs/securite/secrets/pki-services.md` : à quoi sert la CRL ici, à quoi servent les 72 h, ce qu'il faudrait pour une révocation effective.

**Critères de réussite**
- [ ] `pki-services/` publie une CA « MédiSphère Services CA » vérifiable contre la racine, valable 3 ans ; la CRL est joignable et à jour ; le procès-verbal de cérémonie est sur `main`.
- [ ] Le rôle `services-k8s` limite les noms à `svc`/`svc.cluster.local`, sans IP, avec un maximum de 72 h.
- [ ] Le ClusterIssuer `openbao-services` est `Ready` ; les Certificate `medidoc-mtls` et `mediagenda-mtls` sont `Ready` et durent au plus 72 h.
- [ ] L'appel MédiAgenda → MédiDoc de la recette passe par le TLS mutuel et un client sans certificat est refusé (`~/m25/e16/essais-mtls.md`).

**Vérification** : `lab/bin/check 25 16`

<details><summary>Indice 1</summary>

Le certificat signé seul ne suffit pas à OpenBao pour publier une chaîne complète : regarde ce que tu lui passes à `intermediate/set-signed`, puis `bao read pki-services/config/issuers` et `bao list pki-services/issuers`. Un émetteur sans clé peut-il être l'émetteur par défaut ?
</details>

<details><summary>Indice 2</summary>

Pour une ClusterIssuer, le compte de service référencé doit vivre dans l'espace de « ressources de cluster » de cert-manager, et c'est le contrôleur de cert-manager qui demande le jeton : il lui faut le droit `create` sur `serviceaccounts/token` pour **ce** compte. Regarde aussi quelle audience cert-manager met **toujours** dans le jeton, en plus de celles que tu ajoutes.
</details>

<details><summary>Indice 3</summary>

Le relais de MédiDoc compare un nom du certificat client à ce que tu l'autorises à accepter (`--allow-dns`, `--allow-uri`…) ; il ne lit pas de CRL. Quelle protection te reste-t-il alors contre un certificat volé ?
</details>

**Pour aller plus loin** (facultatif) : faire signer par `openbao-services` le certificat **serveur** de la base CNPG de recette (`spec.certificates.serverTLSSecret`) et passer la connexion d'OpenBao d'E14 en `verify-full` sur un nom stable : la CA de CNPG (90 jours, renouvelée par l'opérateur) n'aurait plus à être recopiée sur `vault01` ; `approver-policy` de cert-manager pour qu'un espace ne puisse demander que les noms de ses propres Services. Documentation : [moteur PKI d'OpenBao](https://openbao.org/docs/secrets/pki/), [CA intermédiaire signée ailleurs](https://openbao.org/docs/secrets/pki/setup/), [cert-manager et Vault](https://cert-manager.io/docs/configuration/vault/), [ghostunnel](https://github.com/ghostunnel/ghostunnel), [conteneurs annexes natifs](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/).

---

### M25-E17 — Transit : le chiffrement comme service  `LAB` `★★`

> **Ticket SEC-2617** — *De : Sophie Laurent*
> Les fiches d'intervention que `medictl` exporte pour InfoGér contiennent les codes d'accès des baies de PAR1 et les numéros d'astreinte des prestataires. Elles finissent en pièce jointe dans des tickets. Je veux ces deux champs chiffrés par le coffre, avec une clé qui n'en sort jamais et qui tourne chaque année. Quand un prestataire part, je veux pouvoir rendre illisibles les anciennes fiches d'un coup. Et Julien va poser la même question pour les données de santé de MédiAgenda : je veux une note qui dise quand on chiffre par le coffre, et quand on ne le fait pas.

**Objectifs pédagogiques**
- Comprendre le moteur `transit` : le client envoie des données, la clé reste dans OpenBao, le chiffré porte la version de la clé (`vault:v<N>:`).
- Faire tourner une clé sans rien casser, rechiffrer (`rewrap`) sans revoir le clair, et distinguer **gel** (`min_decryption_version`) et **destruction** (`trim`) des anciennes versions.
- Donner à une identité machine le droit de chiffrer avec **sa** clé et rien d'autre.
- Comprendre le chiffrement par clé de données (*envelope encryption*) avec le fournisseur de clé `openbao` d'OpenTofu (promesse du M05-E27).

**Prérequis** : M25-E07 (AppRole `medictl`, politique `wb-checks`), M25-E08 (projet `plateforme/secrets`, `outils/charger-acces.sh`) ; M02 (`medictl`, `plateforme/outils`) ; M05-E27 (chiffrement des états OpenTofu).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Moteur | `transit/`, monté par OpenTofu (`plateforme/secrets`, nouveau fichier `tofu/transit.tf`) |
| Clé des fiches | `medictl-donnees` : `aes256-gcm96`, **non exportable**, pas de sauvegarde en clair, suppression interdite, rotation automatique **365 jours** (`auto_rotate_period`, en secondes dans le fournisseur) |
| Clé d'essai | `essai-e17` : mêmes réglages mais suppression **autorisée** ; toutes les manipulations destructrices se font sur elle ; supprimée à la fin |
| Politiques (`politiques/*.hcl`) | `medictl` : chiffrer, déchiffrer et rechiffrer avec `medictl-donnees`, rien sur `transit/keys/…` ; `plateforme-admin` : administrer les clés (créer, régler, tourner), sans `transit/export` ni `transit/backup` ; `wb-checks` : **lister** `transit/keys` et **lire** `transit/keys/+` (métadonnées : type, versions, réglages ; jamais de matériel de clé pour une clé symétrique non exportable) |
| `medictl` | projet `plateforme/outils` (clone `~/src/outils`) ; nouveau module `src/medictl/transit.py` et commandes `medictl transit chiffrer|rechiffrer|dechiffrer FICHIER -c CHAMP…` sur un document JSON (objet ou liste d'objets), réécrit sur place ; jeton : `BAO_TOKEN` (AppRole `medictl`, E07) sinon `~/.vault-token` (écrit par `bao login`) ; adresse `BAO_ADDR` ; autorité du système ou `BAO_CACERT` ; `requests` (comme le client Proxmox du M02) |
| Fiche de travail | `~/m25/e17/fiche-intervention.json` : liste de fiches `{"vm", "baie", "code_baie", "astreinte_tel", "prestataire"}` (valeurs **fictives**) ; `code_baie` et `astreinte_tel` chiffrés |
| Note | `docs/securite/secrets/transit.md` de `plateforme/medisphere` |

> ⚠️ **Attention** : une clé de transit supprimée rend **définitivement** illisible tout ce qu'elle a chiffré, copies et sauvegardes comprises ; `trim` détruit des versions sans retour. Ces deux gestes ne se font que sur `essai-e17`. Garde `deletion_allowed = false` sur toute clé qui a chiffré une donnée réelle.

**Travail demandé**

1. **Lire avant d'écrire.** Dans la documentation du moteur transit d'OpenBao, relève : les types de clés symétriques et asymétriques ; pourquoi le clair est envoyé en base64 ; ce que contient le préfixe d'un chiffré ; ce que font `rotate`, `rewrap`, `min_decryption_version`, `min_encryption_version`, `trim` ; ce qu'est une clé de données (`datakey`). Note tes réponses dans `~/m25/e17/notes.md`.
2. **En code.** Dans `plateforme/secrets`, écris `tofu/transit.tf` (montage et deux clés) et complète les politiques `medictl`, `plateforme-admin` et `wb-checks`. Branche, MR, `tofu plan` depuis `adm01` (session chargée par `outils/charger-acces.sh` après `bao login -method=oidc`), fusion, `tofu apply`, plan vide. Le fournisseur sait-il **tourner** une clé ? Pourquoi est-ce une bonne chose de ne pas gérer `min_decryption_version` dans OpenTofu ?
3. **Premiers chiffrés (`essai-e17`).** Chiffre deux fois la même chaîne avec la CLI :
   ```
   admin@adm01:~$ bao write -field=ciphertext transit/encrypt/essai-e17 plaintext="$(printf 'code 4821' | base64)"
   ```
   Pourquoi les deux chiffrés diffèrent-ils ? Déchiffre-les. Refais la même chose par l'API avec `curl`, le jeton passé par un fichier de configuration de `curl` (jamais sur la ligne de commande), puis chiffre trois valeurs en **une** requête (`batch_input`).
4. **Rotation et rechiffrement (`essai-e17`).** Garde un chiffré `v1` dans un fichier, tourne la clé, chiffre une nouvelle valeur (quelle version ?), déchiffre l'ancien (que se passe-t-il ?), puis rechiffre-le par `rewrap` : as-tu vu le clair à un moment ?
5. **Geler, puis détruire (`essai-e17`).** Règle `min_decryption_version` à 2 et essaie de déchiffrer un chiffré `v1` : quel message ? Reviens à 1 : le chiffré redevient-il lisible ? Qu'en conclus-tu pour la demande de Sophie (« rendre illisibles d'un coup ») ? Essaie ensuite `trim` avec `min_available_version=2` : que demande OpenBao avant de l'accepter, et que devient la version 1 ?
6. **`medictl`.** Ajoute `src/medictl/transit.py` (un client qui parle à l'API de transit, par lots, sans jamais écrire le jeton dans un message) et les trois commandes, avec des tests `pytest` qui simulent l'API (`responses`, déjà utilisé au M02). Contraintes : `https://` obligatoire ; vérification TLS jamais désactivée ; un champ déjà chiffré n'est pas rechiffré par `chiffrer` ; réécriture **atomique** du fichier. MR, pipeline vert, publication comme au M02.
7. **Les fiches.** Écris `~/m25/e17/fiche-intervention.json` (trois fiches fictives), chiffre `code_baie` et `astreinte_tel` **avec l'AppRole `medictl`** (un jeton obtenu comme en E07, dans `BAO_TOKEN` le temps de la commande). Puis, avec ton identité `plateforme-admins`, tourne la vraie clé `medictl-donnees` une fois, et repasse la fiche à la dernière version avec `medictl transit rechiffrer`. Essaie enfin `bao write -f transit/keys/medictl-donnees/rotate` avec le jeton de `medictl` : que répond OpenBao, et pourquoi est-ce voulu ?
8. **Clé de données : un état OpenTofu chiffré par le coffre.** Dans `~/m25/e17/tofu-essai/`, crée un état **local** jetable (une ressource `terraform_data`), puis ajoute un bloc `encryption` avec le fournisseur de clé `openbao` (clé `essai-e17`) et une méthode de repli `unencrypted` pour la migration ; applique, regarde le fichier d'état et ses métadonnées, retire le repli. Quels appels OpenBao a-t-il reçus (lis la documentation du fournisseur) ? Supprime enfin `essai-e17` par OpenTofu (retrait du bloc, MR) et relance `tofu plan` dans l'essai : que se passe-t-il ? Quels états réels de MédiSphère peuvent dépendre du coffre, et lequel **ne doit pas** ?
9. **La note.** Écris `docs/securite/secrets/transit.md` (MR) : quand chiffrer par transit et quand non (KV, secret dynamique, clé de données), règles de nommage et de réglage des clés, rotation et rechiffrement, gel et destruction, ce qu'il faut savoir avant de chiffrer une colonne de MédiAgenda (disponibilité, recherche, volume), et la décision pour les états OpenTofu.

**Critères de réussite**
- [ ] `transit/` est monté ; `medictl-donnees` est en `aes256-gcm96`, non exportable, sans sauvegarde en clair, non supprimable, avec une rotation automatique d'un an, au moins deux versions et `min_decryption_version` à 1.
- [ ] `essai-e17` n'existe plus.
- [ ] La politique `medictl` n'autorise que `encrypt`, `decrypt` et `rewrap` sur `medictl-donnees`.
- [ ] Dans `~/m25/e17/fiche-intervention.json`, tous les `code_baie` et `astreinte_tel` sont chiffrés à la **dernière** version de la clé.
- [ ] `src/medictl/transit.py` et ses tests, `tofu/transit.tf` et `transit.md` sont sur `main` de leurs projets.

**Vérification** : `lab/bin/check 25 17`

<details><summary>Indice 1</summary>

Pour transit, toute opération est un `POST` : dans une politique, c'est la capacité `update` sur `transit/encrypt/<clé>`, `transit/decrypt/<clé>`… Une politique qui donne `update` sur `transit/keys/*` donne aussi `transit/keys/<clé>/config` et `rotate` : regarde ce que deviendrait `exportable` si quelqu'un pouvait le changer.
</details>

<details><summary>Indice 2</summary>

`min_decryption_version` ne supprime rien : les versions sont toujours là, simplement refusées. `trim` exige qu'on ait d'abord interdit le **chiffrement** avec les versions qu'il va supprimer. Lis le message d'erreur de `trim` : il dit quel réglage poser avant.
</details>

<details><summary>Indice 3</summary>

Dans `requests`, une vérification TLS posée sur la session (`session.verify`) peut être remplacée sans bruit par la variable `REQUESTS_CA_BUNDLE` du shell ; le M02-E08 a déjà rencontré ce piège avec `proxmoxer`. Passe `verify=` à chaque requête. Côté OpenTofu, le fournisseur de clé `openbao` lit `BAO_ADDR` et `BAO_TOKEN`.
</details>

**Pour aller plus loin** (facultatif) : chiffrement **dérivé** et **convergent** (`derived`, `convergent_encryption`, `context`) et ce qu'il fait fuir ; empreintes `transit/hmac/<clé>` pour rechercher une valeur chiffrée ; [moteur transit d'OpenBao](https://openbao.org/docs/secrets/transit/), [API transit](https://openbao.org/api-docs/secret/transit/), [chiffrement des états OpenTofu](https://opentofu.org/docs/language/state/encryption/).

---

### M25-E18 — Des secrets chiffrés dans Git : SOPS, age et transit  `LAB` `★★`

> **Ticket PLAT-2618** — *De : Karim Benali*
> On a choisi External Secrets pour le cluster, très bien. Mais à chaque conférence, quelqu'un me demande pourquoi on ne fait pas « tout simplement » du SOPS : les secrets chiffrés dans Git, à côté du reste. Je veux qu'on l'ait pratiqué pour de vrai avant de répondre : avec `age` d'abord, puis avec notre coffre comme gestionnaire de clés. Sur un dépôt d'essai, pas sur nos vrais dépôts. Et à la fin, une comparaison honnête et ce qu'on retient.

**Objectifs pédagogiques**
- Comprendre le chiffrement par enveloppe de SOPS : une clé de données par fichier, chiffrée pour chaque destinataire (`age`, transit d'OpenBao) ; un MAC sur tout le fichier.
- Écrire des règles `.sops.yaml` (chemins, champs chiffrés, destinataires) et travailler sans jamais écrire le clair sur disque (`sops edit`).
- Retirer un destinataire correctement (`updatekeys`, `rotate`) et comprendre ce que l'historique Git garde.
- Brancher SOPS sur le moteur transit (`hc_vault_transit_uri`), borner les adresses de coffre autorisées (`SOPS_HC_VAULT_ALLOWLIST`) et comparer avec External Secrets.

**Prérequis** : M25-E12 (External Secrets, `wb-essais`), M25-E17 (moteur transit) ; M01 (GitLab, MR) ; M14-E05 (rôle `outils_k8s`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Versions | **SOPS 3.13.3** (jamais 3.13.2 : MAC erroné sur les listes YAML commentées) ; **age 1.3.2** (Debian 13 livre 1.2.1) ; installés sur `adm01` par le rôle `outils_k8s` (le binaire de SOPS est publié **sans archive** : le rôle doit apprendre à installer un binaire brut ; vérifie la signature du fichier de sommes de SOPS avec Cosign avant d'en recopier l'empreinte, comme au M13) |
| Dépôt d'essai | projet GitLab **`formation/sops-labo`** (clone `~/src/sops-labo`) : `.sops.yaml`, `.gitattributes`, `k8s/wb-essais/*.sops.yaml`, `outils/verifier-chiffres.sh`, `.gitlab-ci.yml` |
| Clés `age` | la tienne (`~/.config/sops/age/keys.txt`, emplacement lu par défaut par SOPS) ; une clé « Karim » **simulée** que tu génères et que tu retireras ; une clé « secours » de l'équipe, privée **hors ligne** (même traitement que les parts Shamir d'E03), dont seule la publique va dans `.sops.yaml` |
| Coffre | clé de transit **`sops-plateforme`** (`aes256-gcm96`, non exportable, non supprimable) et politique **`sops-plateforme`** (chiffrer et déchiffrer avec elle, rien d'autre), attachée aux groupes externes `plateforme-admins` et `plateforme` (variable `groupes_keycloak`) ; URI SOPS : `https://openbao.par1.medisphere.internal:8200/v1/transit/keys/sops-plateforme` |
| Jeton pour SOPS | SOPS lit `VAULT_TOKEN` ou `~/.vault-token` (pas `BAO_TOKEN`) ; `bao login -method=oidc` écrit `~/.vault-token` |
| Fichier à chiffrer | un Secret Kubernetes **fictif** `essai-sops` de `wb-essais` (clés `mot_de_passe`, `utilisateur`) |
| Comparaison | `docs/securite/secrets/comparatif-livraison-k8s.md` (créé ici, complété en E19) |

> ⚠️ **Attention** : un secret commité en clair, même une seconde, est dans l'historique pour toujours (M01). Dans ce dépôt, n'utilise que des valeurs fictives, et ne commite jamais un fichier avant d'avoir vérifié qu'il est chiffré (`outils/verifier-chiffres.sh`, et un `git diff --cached` qui ne montre que des `ENC[…]`).

**Travail demandé**

1. **Outils.** Étends le rôle `outils_k8s` pour qu'il sache installer un binaire publié sans archive, ajoute `sops` et `age` à sa liste, MR, playbook sur `adm01`. Montre dans la MR la vérification de la signature du fichier de sommes de SOPS (identité du flux de publication du projet, émetteur GitHub).
2. **SOPS + age.** Crée le projet `formation/sops-labo`. Génère ta clé `age` et la clé « Karim » (dans `~/m25/e18/`). Écris un `.sops.yaml` qui chiffre **seulement** `data` et `stringData` des fichiers `k8s/**/*.sops.yaml` pour vous deux. Crée le Secret d'essai avec `sops edit` (où le clair existe-t-il pendant l'édition ?). Ouvre le fichier chiffré : qu'est-ce qui reste lisible, que contient la section `sops`, que protège le MAC ? Modifie une valeur à la main dans le chiffré (sans SOPS) et essaie de déchiffrer.
3. **Lire l'historique.** Ajoute le pilote de différence de `.gitattributes` (`diff=sopsdiffer`, `textconv`) et compare `git log -p` avec et sans lui.
4. **Contrôle en CI.** Écris `outils/verifier-chiffres.sh` (yq v4) qui refuse : un `kind: Secret` hors d'un `*.sops.yaml`, un `*.sops.yaml` sans métadonnées SOPS ou sans destinataire, une valeur en clair sous `data`/`stringData`. Branche-le dans `.gitlab-ci.yml` (MR et `main`). Prouve qu'il échoue sur une MR qui ajoute un Secret en clair (puis ferme cette MR **sans** la fusionner, et supprime la branche).
5. **Retirer Karim.** Il quitte le projet : retire sa clé de `.sops.yaml`, puis `sops updatekeys`. Peut-il encore déchiffrer le fichier de `main` ? Et celui du commit précédent ? Que fait `sops rotate`, et pourquoi ne suffit-il pas non plus ? Que faut-il faire de la **valeur** du secret ?
6. **SOPS + transit.** Ajoute en code (`plateforme/secrets`) la clé `sops-plateforme`, la politique `sops-plateforme` et son attachement aux groupes ; MR, apply. Remplace ta clé personnelle par la clé de transit et la clé « secours » dans `.sops.yaml`, `updatekeys`, `rotate`. Déchiffre après `bao login -method=oidc`, puis sans jeton : quel message ? Ajoute `export SOPS_HC_VAULT_ALLOWLIST=https://openbao.par1.medisphere.internal:8200` à ton `~/.bashrc` et explique contre quoi il protège (pense à un fichier `.sops.yaml` ou chiffré fourni par quelqu'un d'autre). Dans le journal d'audit d'OpenBao (s'il est déjà en place, sinon après E21), qu'apparaît-il quand tu déchiffres ?
7. **Dans le cluster ?** Applique le Secret déchiffré dans `wb-essais` (`sops decrypt … | kubectl apply -n wb-essais -f -`), puis supprime-le. Comment Argo CD pourrait-il le faire lui-même (cherche « KSOPS » et « helm-secrets ») et quel droit faudrait-il lui donner ?
8. **Comparer et décider.** Écris `comparatif-livraison-k8s.md` (MR dans `plateforme/medisphere`) : SOPS face à External Secrets, critère par critère (où vit la valeur, qui déchiffre, rotation, retrait d'un accès, secrets dynamiques, revue de MR, reprise après sinistre), et ce que MédiSphère retient.

**Critères de réussite**
- [ ] `sops` 3.13.3 et `age` sont installés sur `adm01` par le rôle `outils_k8s` ; `SOPS_HC_VAULT_ALLOWLIST` limite SOPS au coffre de MédiSphère.
- [ ] La clé `sops-plateforme` et la politique `sops-plateforme` (chiffrer, déchiffrer, rien d'autre) existent.
- [ ] Sur `main` de `formation/sops-labo`, `.sops.yaml` vise la clé de transit et **une seule** clé `age` (la clé de secours), et au moins un `k8s/**/*.sops.yaml` est chiffré par SOPS 3.13.3 pour ces deux destinataires, sans aucune valeur en clair ; le contrôle de la CI est vert.
- [ ] La comparaison SOPS / ESO est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 25 18`

<details><summary>Indice 1</summary>

Dans une règle `creation_rules`, `age` et `hc_vault_transit_uri` côte à côte forment **un seul** groupe de clés : n'importe quel destinataire suffit à déchiffrer. `encrypted_regex` décide des champs chiffrés ; le MAC, lui, couvre tout le fichier, champs en clair compris : on ne peut pas changer le `namespace` d'un fichier chiffré sans SOPS.
</details>

<details><summary>Indice 2</summary>

`updatekeys` change les destinataires de la **clé de données** du fichier, pas la clé de données elle-même : qui l'a déjà vue (ou qui a l'ancien fichier) peut toujours lire. `rotate` change la clé de données ; ni l'un ni l'autre ne touche à l'historique Git ni à la **valeur** du secret.
</details>

<details><summary>Indice 3</summary>

Pour le rôle : `ansible.builtin.get_url` accepte une somme sous la forme `sha256:<URL du fichier de sommes>` (il y cherche le nom du fichier téléchargé) ou `sha256:<empreinte>` ; un binaire brut n'a pas besoin d'`unarchive`, mais d'un mode exécutable.
</details>

**Pour aller plus loin** (facultatif) : groupes de clés à seuil (`key_groups`, `shamir_threshold`) : exiger deux destinataires pour déchiffrer ; identités `age` post-quantiques et plugins (`age-plugin-*`) pris en charge par SOPS 3.13 ; [documentation de SOPS](https://getsops.io/docs/), [age](https://github.com/FiloSottile/age), [KSOPS](https://github.com/viaduct-ai/kustomize-sops).

---

### M25-E19 — Comparer : Sealed Secrets et Secrets Store CSI  `LAB` `★★`

> **Ticket PLAT-2619** — *De : Claire Morel*
> L'auditeur HDS de l'an prochain demandera pourquoi nous avons choisi External Secrets et pas autre chose. « On a lu des articles » ne suffira pas. Essayez les deux autres approches qu'on nous cite toujours, Sealed Secrets et le pilote CSI avec OpenBao, dans `wb-essais`, mesurez, écrivez la comparaison, puis désinstallez tout : je ne veux pas trois façons de livrer un secret dans le cluster.

**Objectifs pédagogiques**
- Installer temporairement des composants tiers par le chemin normal (chart recopié dans Harbor, Application Argo CD, espace déclaré) et les retirer proprement.
- Comprendre Sealed Secrets : chiffrement asymétrique pour **un** cluster, portées, clé privée du contrôleur et ce qu'elle implique pour la reprise.
- Comprendre le pilote Secrets Store CSI : volume monté au démarrage du pod avec l'identité **du pod**, recopie facultative dans un Secret, rotation.
- Mesurer et comparer avec External Secrets, puis décider par écrit.

**Prérequis** : M25-E12 (méthode `kubernetes` montée en `k8s-par1`, audience `openbao.medisphere.internal`), M25-E18 (comparaison commencée) ; M20-E13 (`plateforme/charts-miroir`), M14-E18 (Pod Security Admission).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Sealed Secrets | **0.40.0**, chart **`sealed-secrets` 2.20.0 du projet** (`https://bitnami.github.io/sealed-secrets`), image publiée par le projet (`docker.io/bitnami/sealed-secrets-controller`, tirée par le cache `dockerhub` de Harbor) — **jamais** le chart `bitnamicharts/sealed-secrets` du catalogue retiré ; espace **`sealed-secrets`** (PSA `restricted`) ; CLI **`kubeseal` 0.40.0** sur `adm01` (rôle `outils_k8s`) |
| Pilote CSI | **Secrets Store CSI Driver 1.6.1** (chart `secrets-store-csi-driver` 1.6.1, images du cache `k8s`) et fournisseur **OpenBao** `openbao-csi-provider` 2.0.3 (chart `openbao` 0.30.4 avec `server` et `injector` désactivés, images du cache `quay`) ; espace **`essai-csi`** (les deux DaemonSets : pilote **privilégié** et `hostPath` → PSA `privileged`, exception écrite) |
| Argo CD | Applications `essai-sealed-secrets`, `essai-csi-driver`, `essai-openbao-csi` dans `plateforme/gitops/plateforme/`, valeurs dans `valeurs/<application>/values.yaml`, projet `plateforme` ; charts ajoutés à `plateforme/charts-miroir` |
| OpenBao | secret de démonstration `kv/plateforme/essais/csi-demo` (clé `message`, valeur sans importance) ; politique `essai-csi` (lecture de ce seul secret) ; rôle `essai-csi` de `k8s-par1` (compte `essai-csi` de `wb-essais`, audience `openbao.medisphere.internal`, 10 min) — dans `plateforme/secrets`, fichiers **temporaires** `tofu/essais-m25.tf` et `politiques/essai-csi.hcl` |
| Objets d'essai | dans `wb-essais` seulement : un `SealedSecret`, une `SecretProviderClass` (`provider: openbao`, API `secrets-store.csi.x-k8s.io/v1`), un compte de service et un pod `essai-csi` |
| Travail | `~/m25/e19/` : garde `sealedsecret.yaml` (le résultat de `kubeseal`) ; le Secret **en clair** que tu scelles est détruit (`shred -u`) dès le scellement |

> ⚠️ **Mémoire et sécurité.** Le pilote CSI et son fournisseur tournent sur **chaque** nœud (deux DaemonSets, dont un privilégié) : profil serré (≈ 111 Go), arrête ce qui ne sert pas pendant l'essai et ne le laisse pas en place plus que nécessaire. La clé privée du contrôleur Sealed Secrets descelle **tout** ce qui a été scellé pour le cluster : ne l'exporte que dans `~/m25/e19/` le temps de l'étape 4, puis détruis la copie.

**Travail demandé**

1. **Recopie des charts.** Ajoute les trois charts à `plateforme/charts-miroir` (versions exactes, empreintes relevées dans les index et contrôlées), MR, pipeline : ils sont dans Harbor, signés. Ajoute `kubeseal` au rôle `outils_k8s`.
2. **Espaces et Applications.** Déclare les espaces `sealed-secrets` et `essai-csi` dans `plateforme/k8s/espaces/` (étiquettes PSA, annotation d'exception pour `essai-csi`, et la racine MédiSphère dont l'agent du fournisseur aura besoin). Écris les valeurs et les trois Applications (avec un finaliseur de suppression en cascade : pourquoi ici, alors qu'on l'a refusé pour kube-prometheus-stack au M21 ?). MR, synchronisation, pods `Running`.
3. **Sealed Secrets.** Récupère le certificat du contrôleur (`kubeseal --fetch-cert --controller-namespace sealed-secrets`), scelle un Secret fictif de `wb-essais` (portée `strict`, par défaut), applique le `SealedSecret` dans `wb-essais` et regarde le Secret produit (propriétaire, étiquettes). Fais-en une copie dont tu changes **seulement le nom** (`metadata.name`), applique-la dans `wb-essais` : que dit le contrôleur (événements du `SealedSecret`) ? Pourquoi ? Qu'en serait-il dans un autre espace ? Que changent les portées `namespace-wide` et `cluster-wide` ?
4. **La clé du contrôleur.** Liste (sans les afficher) les Secrets de clé de l'espace `sealed-secrets` : combien, pourquoi plusieurs avec le temps (`keyrenewperiod`) ? Exporte la clé privée active dans `~/m25/e19/` et descelle ton `SealedSecret` **hors du cluster** (`kubeseal --recovery-unseal`). Qu'en conclus-tu pour la reprise après sinistre et pour la protection de cette clé ? Détruis la copie.
5. **Pilote CSI.** Écris le secret de démonstration, la politique et le rôle d'essai (MR dans `plateforme/secrets`). Applique la `SecretProviderClass`, le compte et le pod d'essai : le pod lit le secret dans un **fichier** et (par `secretObjects`) dans une variable d'environnement. Puis :
   - change la valeur dans OpenBao : au bout de combien de temps le fichier change-t-il ? la variable ? (règle de rotation du pilote : 2 min) ;
   - retire temporairement la politique au rôle (MR, ou essai noté puis rétabli) et recrée le pod : dans quel état reste-t-il, et que disent ses événements ? Comparez avec un pod qui lit un Secret d'ESO quand le coffre ne répond pas ;
   - dans le journal d'audit (après E21, ou dans les journaux de l'agent avant), quelle identité a lu le secret ?
6. **Mesurer.** Relève la mémoire des composants de chaque approche (Prometheus, `container_memory_working_set_bytes`), le délai de rotation, le comportement quand OpenBao est injoignable, et ce que contient etcd dans chaque cas.
7. **Écrire et décider.** Complète `comparatif-livraison-k8s.md` : tableau des quatre approches (ESO, SOPS, Sealed Secrets, CSI), mesures, décision argumentée pour chacune, et critère de réexamen.
8. **Désinstaller.** Dans l'ordre : objets de `wb-essais`, Applications (MR : la cascade supprime CRD et contrôleurs), espaces, politique et rôle d'essai et secret de démonstration (MR), entrées de `charts-miroir` et de `kubeseal` (MR). Vérifie qu'il ne reste ni CRD, ni espace, ni politique.

**Critères de réussite**
- [ ] La comparaison complète (quatre approches, mesures, décision) est sur `main` de `plateforme/medisphere`.
- [ ] L'historique de `plateforme/gitops` montre l'ajout **puis** le retrait des trois Applications ; aucune n'existe plus dans Argo CD.
- [ ] Les espaces `sealed-secrets` et `essai-csi`, les CRD `sealedsecrets.bitnami.com` et `secretproviderclasses.secrets-store.csi.x-k8s.io` et la politique OpenBao `essai-csi` n'existent plus.
- [ ] `~/m25/e19/sealedsecret.yaml` est un `SealedSecret` de `wb-essais` en portée stricte ; le Secret en clair de l'essai a été détruit.

**Vérification** : `lab/bin/check 25 19` (à la fin, après la désinstallation)

<details><summary>Indice 1</summary>

Le fournisseur CSI demande lui-même au cluster (API *TokenRequest*) un jeton du compte de service **du pod**, avec l'audience écrite dans la `SecretProviderClass` (`audience`) : elle doit être celle qu'exige le rôle OpenBao. Le montage de la méthode se donne par `baoAuthMountPath`. Les journaux utiles sont ceux du conteneur `openbao-agent` du DaemonSet du fournisseur et les événements du pod.
</details>

<details><summary>Indice 2</summary>

Un `SealedSecret` en portée stricte a été chiffré avec, en données associées, l'espace **et** le nom : le contrôleur refuse de le desceller ailleurs. La clé privée active et les anciennes sont des Secrets de l'espace du contrôleur, étiquetés `sealedsecrets.bitnami.com/sealed-secrets-key`.
</details>

<details><summary>Indice 3</summary>

Pour l'agent OpenBao du fournisseur, le chart ne propose pas de réglage d'autorité de certification : il propose `csi.volumes` et `csi.volumeMounts`, montés dans les deux conteneurs du DaemonSet. Un client Go lit `/etc/ssl/certs/ca-certificates.crt`.
</details>

**Pour aller plus loin** (facultatif) : l'injecteur d'agent d'OpenBao (`openbao-k8s`, annotations de pod) comme quatrième approche ; le chiffrement d'etcd et pourquoi aucun plugin KMS v2 n'est disponible pour OpenBao (ADR-0251, E31) ; [Sealed Secrets](https://github.com/bitnami/sealed-secrets), [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/), [fournisseur CSI d'OpenBao](https://openbao.org/docs/platform/k8s/csi/).

---

### M25-E20 — Signer avec une clé qui ne sort jamais du coffre  `LAB` `★★★`

> **Ticket SEC-2620** — *De : Sophie Laurent*
> La clé qui signe nos images vit aujourd'hui dans un Secret Kubernetes monté par le runner protégé, dans un fichier Ansible Vault, et elle a passé des mois dans des variables de CI. Au M26, Kyverno refusera tout ce qui n'est pas signé par elle : elle devient la clé la plus précieuse du cluster. Je veux qu'elle soit dans le coffre, que personne ne puisse l'en sortir, que chaque signature soit tracée avec le projet et le pipeline qui l'ont demandée, et qu'on sache ce qu'on fait des signatures existantes.

**Objectifs pédagogiques**
- Utiliser une clé asymétrique du moteur transit comme clé de signature Cosign (`hashivault://`), et vérifier ce qu'OpenBao reçoit vraiment.
- Donner le droit de signer à un job de CI **par son identité** (jeton GitLab) avec des conditions précises : référence protégée, groupe, runner.
- Découvrir une limite du fournisseur OpenTofu et la contourner proprement.
- Décider du sort de l'ancienne clé et des signatures existantes, en pensant aux vérificateurs (porte de déploiement, Kyverno au M26).

**Prérequis** : M25-E10 (méthode `jwt` montée en `gitlab`, composant `securite` v2.9.0 avec `bao` dans l'image outillée), M25-E17 (transit) ; M19-E24 et E29 (runner protégé, composant `securite` v2.8.0, attestations), M20-E13 (`charts-miroir`), M13-E09 et E14 (Cosign, `docs/registre/cosign.pub`).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Cosign | 3.1.x (image `outils-supply-chain`, `adm01`) : référence de clé **`hashivault://cosign-medisphere`** ; l'adresse et le jeton viennent de `VAULT_ADDR`/`VAULT_TOKEN` **ou** `BAO_ADDR`/`BAO_TOKEN` (à vérifier dans la documentation KMS de Cosign et dans ton essai) ; configuration de signature sans service `/etc/medisphere/signing-config.json` (M13) |
| Clé | transit **`cosign-medisphere`** : `ecdsa-p256`, non exportable, sans sauvegarde en clair, non supprimable, **sans** rotation automatique ; **générée** dans le coffre (pas d'import de l'ancienne : décision à justifier) |
| Politique | **`cosign-signature`** : ce dont Cosign a besoin, et rien d'autre — à déterminer **dans le journal d'audit** ou la documentation, pas au jugé |
| Rôle CI | **`ci-signature`** de la méthode `gitlab` : audience `openbao.medisphere.internal`, référence protégée, groupes `mediagenda`, `medidoc`, `medinotif`, `plateforme`, runner **`k8s-par1-protege`** (son identifiant numérique : *Admin → CI/CD → Runners*), jeton de 10 min, politique `cosign-signature` seule ; projet, référence et pipeline recopiés dans les métadonnées du jeton (`claim_mappings`) pour l'audit |
| Composant | `securite` **v2.10.0** de `plateforme/ci-templates` : `securite:signature` se connecte au coffre par `id_tokens` puis signe et atteste par la clé de transit ; plus aucun fichier de clé ; nouvelle version de l'image outillée avec la **nouvelle** clé publique dans `/etc/medisphere/cosign.pub` |
| Autre signataire | `plateforme/charts-miroir` (`outils/signer.sh`, job `signer`, M20-E13) |
| Publication | `docs/registre/cosign.pub` = nouvelle clé publique ; ancienne gardée sous `docs/registre/cosign-m13.pub` ; décision et procédures dans `docs/securite/secrets/cle-signature.md` |
| À retirer à la fin | Secret `ci-jobs-protege/cosign-medisphere`, son montage dans le runner protégé (`composants/gitlab-runner-protege/values.yaml`), sa ligne de `outils/secrets-k8s.conf`, `secrets/cosign-ci.yml`, les variables Cosign qui resteraient (groupe `plateforme`, `charts-miroir`) |

> ⚠️ **Attention** : changer de clé de signature casse toute vérification qui ne connaît que l'ancienne (porte de déploiement de `…/deploiement`, `securite:verification`, et Kyverno au M26). Ordre imposé : publier la nouvelle clé publique **et** l'embarquer dans les vérificateurs, signer avec la nouvelle, re-signer ce qui est déployé, **puis** retirer l'ancienne. Retour arrière tant que l'ancienne n'est pas détruite : revenir au composant v2.8.0 et à l'ancienne image outillée. Le runner protégé reste le seul à signer : ne retire pas son montage avant que la v2.10.0 ait signé une version avec succès.

**Travail demandé**

1. **Essai à blanc.** Lis la page KMS de la documentation de Cosign. Sur un OpenBao de développement local (`bao server -dev` sur `adm01`, arrêté ensuite), crée une clé `ecdsa-p256`, active un audit vers un fichier (en mode `-dev`, comment fait-on depuis OpenBao 2.4 ?), puis : `cosign public-key --key hashivault://…`, `cosign sign-blob` d'un fichier, `cosign verify-blob` avec la clé publique. Relève dans l'audit les **chemins** appelés : ce sera ta politique. Essaie avec `BAO_ADDR`/`BAO_TOKEN` seuls, puis avec `VAULT_*` seuls.
2. **En code.** Dans `plateforme/secrets` : la clé, la politique, le rôle `ci-signature`. Écris d'abord le rôle avec `vault_jwt_auth_backend_role` et teste une connexion (un job d'essai de `formation/ci-labo` sur `main` et sur une branche, dont tu lis le jeton comme au M19-E25 ; ou, contre ton OpenBao de développement, un jeton que tu signes toi-même avec une clé RSA d'essai déclarée par `jwt_validation_pubkeys`) : la condition sur le runner passe-t-elle ? Lis le rôle tel qu'OpenBao l'a enregistré (`bao read auth/gitlab/role/ci-signature`) et compare avec le type de la revendication `runner_id` dans un jeton GitLab. Trouve un moyen d'écrire le rôle en code **avec les bons types**.
3. **Le composant.** Publie la v2.10.0 de `securite` : connexion au coffre par le jeton d'identité (le JWT ne passe jamais en argument d'une commande), signature et attestations par `hashivault://`, révocation du jeton à la fin du job. Nouvelle version de l'image outillée avec la nouvelle clé publique (et l'empreinte attendue dans la porte du composant `deploiement`). Fais de même pour `charts-miroir`.
4. **Bascule.** Publie `docs/registre/cosign.pub` (nouvelle) et `cosign-m13.pub` (ancienne). Passe `mediagenda/api` sur `@v2.10.0`, pose une étiquette de version : le job tourne-t-il sur le runner protégé ? `cosign verify` avec la **nouvelle** clé publique réussit-il, avec l'**ancienne** échoue-t-il ? Relance le pipeline planifié de `charts-miroir` : que fait `signer.sh` des charts signés par l'ancienne clé ?
5. **Re-signer ce qui est déployé.** Liste les images en `recette` et `prod` (Applications Argo CD, `kustomize build` des overlays), re-signe celles qui ne vérifient pas avec la nouvelle clé (ton identité `plateforme-admins`, ticket CHG-2620 dans le message de chaque commande notée), vérifie.
6. **Retirer l'ancienne clé.** Supprime le montage du runner protégé, la ligne de `secrets-k8s.conf` et le Secret du cluster, puis `secrets/cosign-ci.yml` et les variables Cosign restantes ; décris dans un procès-verbal la destruction des copies de l'ancienne clé privée. Un job sur une branche non protégée, ou sur `main` d'un projet d'un autre groupe, peut-il signer ? Prouve-le (connexion refusée : quel message ?).
7. **Écrire.** `docs/securite/secrets/cle-signature.md` : état avant/après, pourquoi une nouvelle clé plutôt qu'un import, conséquences pour les vérificateurs et pour Kyverno au M26, procédure de rotation future (que devient la clé publique après un `rotate` de transit ?), repli si `hashivault://` cessait de fonctionner avec OpenBao.

**Critères de réussite**
- [ ] `cosign-medisphere` est `ecdsa-p256`, non exportable, sans sauvegarde en clair, non supprimable ; `docs/registre/cosign.pub` est **sa** clé publique, l'ancienne est dans `cosign-m13.pub`.
- [ ] `cosign-signature` permet de signer et de lire la clé publique, rien d'autre ; `ci-signature` n'accepte que l'audience `openbao.medisphere.internal`, les références protégées, le runner protégé (identifiant numérique), pour 15 min au plus.
- [ ] `securite` v2.10.0 et `charts-miroir` signent par `hashivault://cosign-medisphere` ; le runner protégé ne monte plus de clé ; `secrets-k8s.conf` n'a plus de ligne `cosign-ci`.
- [ ] La dernière version de `mediagenda-api` se vérifie avec la nouvelle clé publique ; `cle-signature.md` est sur `main`.

**Vérification** : `lab/bin/check 25 20`

<details><summary>Indice 1</summary>

Cosign lit la clé de transit (`transit/keys/<clé>`, pour la clé publique et la dernière version) puis demande une signature d'empreinte : le chemin exact contient l'algorithme de hachage. Une politique `transit/sign/<clé>` sans ce suffixe ne suffit pas, `transit/sign/*` en donne trop.
</details>

<details><summary>Indice 2</summary>

Dans un jeton GitLab, `ref_protected` est une **chaîne** (`"true"`) mais `runner_id` est un **nombre**. Le fournisseur `hashicorp/vault` décrit `bound_claims` comme une table de chaînes. Le type de comparaison `glob` n'accepte que des chaînes ; `string`, si la valeur liée est elle-même un nombre. La ressource `vault_generic_endpoint` écrit un JSON tel quel.
</details>

<details><summary>Indice 3</summary>

Avec `token_no_default_policy`, le jeton n'a plus la politique `default`… qui donnait `auth/token/revoke-self`. Et en mode `-dev`, un dispositif d'audit se déclare dans un fichier de configuration passé en plus (`-config`).
</details>

**Pour aller plus loin** (facultatif) : signature sans clé (*keyless*) avec Fulcio et un émetteur OIDC interne, et ce qu'il faudrait héberger ; clés ML-DSA du transit d'OpenBao 2.7 et leur prise en charge par Cosign ; [Cosign, gestion des clés KMS](https://docs.sigstore.dev/cosign/key_management/overview/), [jetons d'identité de GitLab](https://docs.gitlab.com/ci/secrets/id_token_authentication/), [méthode JWT d'OpenBao](https://openbao.org/docs/auth/jwt/).

---

### M25-E21 — Audit : qui a lu quel secret  `LAB` `★★`

> **Ticket SEC-2621** — *De : Sophie Laurent*
> Quand Lucas a collé son fichier `.env` dans un ticket, personne n'a su dire qui avait lu ces secrets avant lui, ni après. Avec le coffre, je veux pouvoir répondre en cinq minutes à « qui a lu le mot de passe de la base de prod de MédiAgenda cette semaine », avec des preuves conservées un an. Et je veux être prévenue si quelqu'un se sert d'un jeton racine ou modifie une politique.

**Objectifs pédagogiques**
- Activer l'audit d'OpenBao de façon **déclarative** et comprendre pourquoi l'API ne le permet plus.
- Comprendre ce que contient une ligne d'audit (requête, réponse, identité, HMAC) et ce qui n'y est pas.
- Faire tourner le journal sans perte, l'acheminer vers le bon locataire de Loki, et l'interroger en LogQL.
- Alerter sur les événements qui comptent, et savoir pourquoi un audit en panne arrête le coffre.

**Prérequis** : M25-E08 (`plateforme/secrets`), M25-E17 et E20 (événements à retrouver) ; M22-E05 (rôle `alloy`), M22-E08 (ruler de Loki, règles par locataire), M22 (locataire `audit`, 1 an).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Dispositif | type `file`, chemin `fichier`, fichier **`/var/log/openbao/audit.log`** (dossier `openbao:openbao` 0750 créé par le rôle depuis E03), mode `0640`, **accessors en clair** (`hmac_accessor`) ; déclaré dans `openbao.hcl` par une nouvelle variable du rôle `openbao` (liste de dispositifs) |
| Rotation | `logrotate` (`/etc/logrotate.d/openbao-audit`, gabarit du rôle) : quotidienne, 14 jours, compression, puis **SIGHUP** (`systemctl reload openbao`, `ExecReload` de l'unité du paquet) |
| Acheminement | rôle `alloy` (M22) étendu : le fichier est lu par Alloy (membre du groupe `openbao`) et envoyé au locataire **`audit`** de Loki avec l'étiquette **`service="openbao"`** (liste fermée : `job`, `host`, `site`, `service`) ; variables dans `group_vars/role_coffre/alloy.yml` |
| Alertes | règles du ruler de Loki dans `plateforme/observabilite` : `loki/regles/audit/openbao.yaml` (`OpenBaoJetonRacineUtilise` critique, `OpenBaoPolitiqueModifiee`, `OpenBaoCleTransitModifiee`) et `loki/regles/plateforme/openbao.yaml` (`OpenBaoAuditImpossible`, sur le journal du **service**) ; même mécanisme qu'au M22-E08 (`configMapGenerator` par locataire) |
| Droits | `securite-audit` a déjà `sys/audit` et `sys/audit-hash/*` ; donne-les aussi à `plateforme-admin` (astreinte) |
| Documentation | `docs/securite/secrets/audit-openbao.md` : chaîne, requêtes LogQL, `sys/audit-hash`, alertes, panne de l'audit |

> ⚠️ **Attention** : si **aucun** dispositif d'audit ne peut écrire, OpenBao **refuse toutes les requêtes** — ESO, CI, Ansible, identifiants dynamiques s'arrêtent. Avant d'activer l'audit, vérifie la place libre de `/var/log` sur `vault01`, et n'essaie la panne (étape 6) que sur un OpenBao de développement local, jamais sur `vault01`. Le rechargement (`systemctl reload openbao`) ne scelle pas le coffre ; un **redémarrage**, si : ne redémarre pas `vault01` pour cet exercice.

**Travail demandé**

1. **Essayer l'API.** Avec ton jeton `plateforme-admins`, essaie `bao audit enable file file_path=/var/log/openbao/audit.log`. Quel message ? Lis dans les notes de version d'OpenBao 2.4 la raison (CVE-2025-6000) et la page de configuration `audit` : comment déclare-t-on un dispositif, quand est-il créé, que se passe-t-il si on change une option ou si on retire le bloc ?
2. **Déclarer.** Étends le rôle `openbao` : variable de dispositifs d'audit, bloc `audit` dans le gabarit de `openbao.hcl`, gabarit `logrotate`. MR, playbook sur `vault01`. Le rôle annonce qu'un redémarrage serait nécessaire : pourquoi un **rechargement** suffit-il ici ? Recharge, puis `bao audit list -detailed`. Essaie `bao audit disable fichier` : réponse ?
3. **Lire une ligne.** Fais une lecture KV, une écriture, un refus (`permission denied`), une connexion OIDC. Pour chacune, lis les lignes `request` et `response` (`sudo jq` sur `vault01`) : identité (`auth.display_name`, `auth.metadata`), chemin, opération, adresse, ce qui est en HMAC et ce qui est en clair. Calcule le HMAC d'une valeur connue avec `sys/audit-hash/fichier` (valeur jamais en argument) et retrouve-la. Quels chemins ne sont **jamais** audités ?
4. **Acheminer.** Étends le rôle `alloy` (fichiers d'audit vers le locataire `audit`, étiquette `service`), donne à Alloy la lecture du fichier par le groupe `openbao`, MR, playbook. Dans Grafana (Explore, locataire `audit`), retrouve tes requêtes de l'étape 3. Force une rotation (`sudo logrotate -f /etc/logrotate.d/openbao-audit`) : manque-t-il des lignes dans Loki ?
5. **Interroger.** Écris et range dans `audit-openbao.md` les requêtes LogQL : qui a lu `kv/data/mediagenda/prod/*` ces 7 derniers jours ; tout ce qu'une identité a lu ; les refus ; les modifications de politique ; les signatures Cosign d'E20 avec leur projet et leur pipeline ; tout ce qu'a fait un jeton dont on connaît l'accessor.
6. **La panne de l'audit (OpenBao de développement local).** Démarre un `bao server -dev` avec un dispositif déclaré (fichier passé par `-config`), fais une requête, puis rends le fichier impossible à écrire (remplace-le par un dossier) et recharge : que répond OpenBao aux requêtes, que dit son journal ? Rétablis. Qu'en conclus-tu pour la supervision et pour un second dispositif ?
7. **Alerter.** Écris les règles du ruler (locataires `audit` et `plateforme`), MR, synchronisation : santé `ok` dans l'API du ruler. Déclenche `OpenBaoPolitiqueModifiee` par une MR de `plateforme/secrets` (une politique réelle, par exemple les droits de l'étape « Droits »), et vérifie le courriel dans Mailpit.

**Critères de réussite**
- [ ] Sur `vault01` (et sur chaque nœud qui existe), `openbao.hcl` déclare le dispositif `file` vers `/var/log/openbao/audit.log` avec les accessors en clair ; le fichier est en `0640 openbao` et s'écrit ; `logrotate` le tourne avec un rechargement, sans `copytruncate` ; Alloy le lit.
- [ ] Le locataire `audit` de Loki reçoit `{service="openbao"}` (accessors en clair), le locataire `plateforme` ne le reçoit pas.
- [ ] Les quatre règles sont chargées et saines dans le ruler.
- [ ] `audit-openbao.md` est sur `main`.

**Vérification** : `lab/bin/check 25 21`

<details><summary>Indice 1</summary>

Un dispositif déclaré est créé (ou retiré) sur le nœud actif au démarrage **et à chaque SIGHUP**. Une option modifiée sur un chemin existant est refusée au rechargement et l'ancien dispositif reste actif : pour changer une option, on déclare un nouveau chemin. Lis le journal du service après chaque rechargement.
</details>

<details><summary>Indice 2</summary>

`| json` de LogQL aplatit `request.path` en `request_path` ; avec des expressions (`| json chemin="request.path", qui="auth.display_name"`), tu choisis les noms. Chaque requête produit deux lignes : filtre `type="response"` pour compter une fois. Un jeton racine se repère par ses politiques (`"policies":["root"]`).
</details>

<details><summary>Indice 3</summary>

Quand l'audit ne peut plus écrire, ce n'est pas l'audit qui le dit (il ne peut pas) : c'est le journal du **service** (`journalctl -u openbao`), que le rôle `alloy` envoie déjà au locataire `plateforme` (unité en métadonnée structurée `unite`).
</details>

**Pour aller plus loin** (facultatif) : second dispositif (`syslog` ou `socket` vers Alloy) avec un filtre qui le garde hors du locataire `plateforme` ; options communes des dispositifs (`elide_list_responses`, `skip_test` ; et pourquoi `log_raw` reste à faux) ; [dispositifs d'audit d'OpenBao](https://openbao.org/docs/audit/), [configuration déclarative](https://openbao.org/docs/configuration/audit/), [`sys/audit-hash`](https://openbao.org/api-docs/system/audit-hash/), [requêtes de journaux LogQL](https://grafana.com/docs/loki/latest/query/log_queries/).

---

### M25-E22 — Revue : les politiques du stagiaire  `REV` `★★`

> **Ticket PLAT-2622** — *De : Karim Benali*
> Lucas a ouvert la MR !214 sur `plateforme/secrets` : les accès de l'équipe MédiDoc au coffre. `tofu validate` passe, le plan est propre, et il demande s'il peut fusionner. Fais-en la revue comme si c'était la prod : tout ce qui ne va pas, du plus grave au plus anodin, avec la correction. Et explique-lui, il apprendra plus de ta revue que de la mienne.

**Objectifs pédagogiques**
- Lire une politique HCL comme OpenBao la lit : correspondance des chemins (`*`, `+`), `data/` et `metadata/` du KV v2, capacités, `deny`, `sudo`.
- Relire un rôle d'authentification : ce qui lie un jeton à une identité (revendications, audience, compte de service, CIDR, `secret_id`) et sa durée de vie.
- Distinguer un défaut de sécurité, un défaut de fonctionnement et un choix discutable ; ne pas signaler ce qui est correct.

**Prérequis** : M25-E05 (politiques), M25-E07 (AppRole), M25-E10 (JWT de GitLab), M25-E12 (méthode `kubernetes`), M25-E14 (identifiants dynamiques).
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers de la MR : `modules/25-secrets/ressources/M25-E22/` (`MR-description.md`, `politiques/medidoc-dev.hcl`, `politiques/medidoc-ci.hcl`, `tofu/medidoc.tf`).
- Conventions du coffre (PLAN §4.12 et fichiers des exercices précédents) : `kv/<application>/<env>/<secret>` (MédiDoc : `kv/medidoc/dev/<composant>/<secret>`, `kv/medidoc/prod/…`) ; un rôle JWT `ci-<projet>` par projet ; un rôle Kubernetes et une politique `eso-<espace>` par espace applicatif, compte de service `eso` ; moteur `db-medidoc/` sur le modèle de `db-mediagenda/` (E14) ; audience `openbao.medisphere.internal` partout ; le script de purge de MédiDoc tourne sur `runner02` (10.10.20.17).
- Tu peux charger les politiques dans un OpenBao de développement local et interroger `bao token capabilities` ; ne les applique **pas** sur `vault01`.

**Travail demandé**
1. Lis la description de la MR, puis chaque fichier. Pour chaque défaut : fichier et bloc, gravité (**bloquant** : sécurité ou fonctionnement ; **à corriger** ; **remarque**), ce qui ne va pas, un scénario concret qui le montre (qui obtient quoi), la correction.
2. Vérifie tes affirmations sur les politiques avec un OpenBao de développement : un jeton par politique, `bao token capabilities` sur des chemins bien choisis (dont des chemins d'**autres** équipes).
3. Repère aussi ce qui est **correct** dans la MR (au moins un bloc) : une revue qui signale tout n'aide personne.
4. Écris la revue dans `~/m25/e22/revue.md` sous forme de commentaires de MR (un par défaut), puis les fichiers corrigés dans `~/m25/e22/corrige/`.
5. Termine par un paragraphe pour Lucas : les trois règles qu'il doit retenir.

**Critères de réussite**
- [ ] Au moins dix défauts réels identifiés et classés, chacun avec un scénario et une correction.
- [ ] Les affirmations sur les politiques sont étayées par `bao token capabilities` (sorties dans la revue).
- [ ] Les fichiers corrigés passent `bao policy fmt` et `tofu validate`, et ne gardent aucun des défauts.

*Auto-évaluation avec le corrigé (pas de vérification automatique).*

<details><summary>Indice 1</summary>

Dans le KV v2, `kv/data/…` porte les valeurs, `kv/metadata/…` les versions et la suppression **définitive** ; `+` remplace exactement **un** segment ; un `deny` l'emporte sur les capacités accordées au **même** chemin (même chaîne), pas sur une règle plus précise d'une autre politique ; `sudo` ne sert que sur les chemins qui l'exigent (et il y donne beaucoup).
</details>

<details><summary>Indice 2</summary>

Pour chaque rôle, pose la question : « qui, exactement, peut obtenir ce jeton ? » — quelle branche de quel projet, quel pod de quel espace, quelle machine avec quel secret. Puis : « combien de temps ce jeton vit-il après la fin de son usage ? ». Regarde aussi quelle **politique** chaque rôle reçoit.
</details>

---

### M25-E23 — Runbook : un secret a fuité  `RED` `★★`

> **Ticket INC-5223** — *De : Nadia Roussel*
> Hier soir, un développeur de MédiDoc a collé dans le canal de l'équipe la sortie d'un job de CI qui contenait un jeton OpenBao et le mot de passe d'un compte de service. Personne n'a su quoi faire dans l'ordre : on a supprimé le message, on a hésité, on a appelé Karim à 23 h. Je veux un runbook que la personne d'astreinte suit seule, pour **tout** type de secret du coffre, et qui laisse des preuves exploitables par Sophie.

**Objectifs pédagogiques**
- Organiser la réponse à une fuite : contenir, qualifier, tourner, vérifier, enquêter, prouver, communiquer, clôturer.
- Connaître le geste de contention et de rotation propre à chaque type de secret du coffre (jeton, `secret_id`, KV, dynamique, certificat, clé de transit, clé de signature, secrets d'autres systèmes).
- S'appuyer sur l'audit (E21) pour l'enquête, sans exposer davantage le secret.

**Prérequis** : M25-E07, E10, E14, E16, E17, E20, E21 ; M19-E40 (RB-198, fuite d'un secret de CI) ; M22 (post-mortems).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Emplacement : `docs/securite/secrets/runbooks/RB-250-fuite-de-secret.md` de `plateforme/medisphere`. RB-198 (M19) reste le runbook des secrets **de GitLab** ; RB-250 couvre le coffre et ce qu'il délivre, et renvoie à RB-198 pour la partie GitLab.
- Inventaire des secrets (propriétaire, emplacement, consommateurs) : `docs/securite/secrets/inventaire-secrets.md` (E02).
- Les gestes de révocation par préfixe exigent `sudo` : le runbook dit **qui** les détient (et propose la MR de politique si personne ne les a).
- MédiSphère est hébergeur de données de santé : la RSSI décide de la notification d'une violation de données personnelles (CNIL, 72 h) ; le runbook lui fournit les faits.

**Travail demandé**
1. Écris RB-250 avec au moins : déclencheurs ; rôles ; les dix premières minutes ; une échelle de gravité avec délais ; un tableau « type de secret → contenir → tourner » couvrant tous les types délivrés par le coffre aux exercices précédents ; les vérifications de retour à la normale ; l'enquête (questions dans l'ordre, requêtes de `audit-openbao.md`, recherche par HMAC et par accessor) ; la conservation des preuves (où, comment, sans recopier le secret) ; la communication ; une liste de clôture ; les commandes de référence (aucun secret en argument).
2. Rejoue mentalement l'incident de Nadia avec ton runbook : jeton OpenBao d'un job de CI de MédiDoc + mot de passe d'un compte de service rangé dans le KV. Écris dans `~/m25/e23/rejeu.md` la chronologie que tu aurais suivie, minute par minute, et les endroits où ton runbook t'a manqué (corrige-le).
3. Si un geste exige un droit que personne n'a (par exemple la révocation par préfixe), propose la MR de politique et justifie-la.
4. MR, relue par Nadia (astreinte) et Sophie (RSSI) : chacune doit pouvoir dire « je saurais le suivre seule ».

**Critères de réussite**
- [ ] RB-250 est sur `main` et couvre chaque type de secret du coffre avec un geste de contention et de rotation.
- [ ] L'enquête s'appuie sur des requêtes LogQL précises et sur `sys/audit-hash`, sans recopier le secret.
- [ ] Le rejeu de l'incident tient en moins de 60 minutes jusqu'à la fin de la rotation, et les manques trouvés sont corrigés dans le runbook.

*Auto-évaluation avec le corrigé ; le runbook sert au M25-E34 (rotation d'urgence chronométrée).*

<details><summary>Indice 1</summary>

Un jeton vu en clair se révoque par son **accessor** (en clair dans l'audit depuis E21), ce qui révoque aussi ses jetons enfants et leurs baux. Un `secret_id` d'AppRole se détruit par son propre accessor. Pour un secret statique, l'ordre compte : nouvelle valeur dans le système cible, puis dans le coffre, puis vérification que l'ancienne est **refusée**.
</details>

<details><summary>Indice 2</summary>

« Qui a lu » se demande au coffre (audit) ; « qui a **utilisé** la valeur fuitée » se demande au système cible (journaux de PostgreSQL, de GitLab, de Keycloak…). Les deux questions n'ont pas la même réponse.
</details>

**Pour aller plus loin** (facultatif) : un exercice de table (*tabletop*) avec Nadia et Sophie sur un scénario G1 (jeton `plateforme-admin` fuité) ; [baux et révocation](https://openbao.org/docs/concepts/lease/), [jetons et accessors](https://openbao.org/docs/concepts/tokens/), guide de la CNIL sur la notification des violations de données personnelles.
