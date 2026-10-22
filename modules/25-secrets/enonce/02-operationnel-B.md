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
- [ ] Le rôle `ci-mediagenda-api` lie l'audience `openbao.medisphere.internal`, le `project_id` réel de `mediagenda/api`, `ref_protected` = `"true"`, et émet des jetons de 10 minutes au plus ; sa politique ne lit que `mediagenda/ci/*` et le robot Harbor.
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
