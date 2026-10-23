# Module 25 — Palier 4 : Expert

Le coffre de MédiSphère est en production : trois nœuds OpenBao 2.7.1 en grappe Raft derrière la VIP `openbao.par1.medisphere.internal`, un auto-descellement par `kms01`, des instantanés chiffrés éprouvés, un audit déclaré dans la configuration et envoyé dans Loki, des alertes, une unité durcie, et tout le reste de la plateforme qui en dépend : la CI qui s'y connecte par ses jetons d'identité, ESO qui y lit les Secrets du cluster, MédiAgenda qui y reçoit des identifiants PostgreSQL d'une heure, cert-manager qui y fait signer les certificats de service. Nadia Roussel résume la situation : « Avant, un mot de passe perdu bloquait une équipe. Maintenant, si le coffre tousse, la CI, les déploiements et les rendez-vous des patients s'arrêtent dans l'heure. » Une panne de coffre est rarement franche. Elle se présente comme un nœud « scellé » qui ne l'est pas, un job de CI qui ne se connecte plus, un ExternalSecret en erreur, une application qui perd sa base toutes les heures, une grappe sans leader, un `permission denied` inexplicable, un certificat refusé, un nœud qui ne revient pas après un redémarrage. Karim Benali a préparé huit pannes de ce genre, et une astreinte qui en combine trois. Puis tu ouvriras le capot (barrière, trousseau, Raft, baux) et tu répondras aux questions de l'auditeur sur les attaques.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au coffre :
- **Le coffre d'abord, les consommateurs ensuite.** Avant toute autre question : le coffre répond-il, et avec quelle **marge** ? `sys/health` de chaque nœud par son nom (200 actif, 429 en attente, 503 scellé, 000 injoignable), puis `bao operator raft autopilot state` (tolérance aux pannes). Un coffre qui répond par la VIP peut n'avoir plus aucun nœud de marge : c'est l'information qui décide de tout ce que tu as le droit de faire ensuite.
- **Connexion ou autorisation ?** Un refus **à la connexion** (méthode, rôle, audience, revendication, compte de service) arrive avant qu'un jeton existe : il se lit dans le message de la méthode et dans le journal d'OpenBao. Un `permission denied` **après** la connexion vient des politiques du jeton : il se lit avec `sys/capabilities-accessor`, `bao token lookup -accessor` et l'audit. Ce ne sont ni les mêmes maillons, ni les mêmes outils.
- **Le code fait foi, la dérive se mesure.** La configuration du coffre est dans `plateforme/secrets` (OpenTofu), celle des nœuds dans `plateforme/ansible`, celle du cluster dans `plateforme/k8s`, `plateforme/gitops` et les dépôts de déploiement. Les pannes de ce palier ne passent **pas** par une MR : comme un geste fait à la main en urgence, elles changent la réalité sans changer le code. `tofu plan`, `ansible-playbook --check --diff`, `task diff` et Argo CD sont donc tes premiers outils de diagnostic, et la correction passe par l'outil qui applique le code.

> **Rappels** : tout se lance depuis `adm01`, avec ta session `bao login -method=oidc` (politique `plateforme-admin`) et ton kubeconfig personnel. `BAO_ADDR=https://openbao.par1.medisphere.internal:8200` ; pour parler à un nœud précis : `BAO_ADDR=https://vault02.par1.medisphere.internal:8200 bao …`. Nœuds : SSH `admin` puis `sudo`. Audit : Loki, locataire **`audit`**, `{service="openbao"}` (M25-E21). Métriques et alertes : `job="openbao"`, `regles/secrets.yaml` (M25-E27). Aucun secret sur une ligne de commande, dans un journal de diagnostic, un ticket ou un post-mortem : un jeton se désigne par son **accesseur** (tronqué dans les écrits), une valeur ne se lit jamais pour diagnostiquer.

## Règles du jeu des pannes (M25-E35 à M25-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 25 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle).
- **Comment les pannes agissent.** Comme une erreur humaine, sans MR : l'API d'OpenBao avec **ton jeton d'administration** (l'audit te désignera donc comme auteur : en production, ce serait le jeton de quelqu'un d'autre, et c'est une question pour le post-mortem), le cluster avec ton kubeconfig (`WB_K8S_ADMIN_KUBECONFIG`, défaut `~/.kube/config`), les nœuds en SSH (`admin` + `sudo`). Avant chaque modification, l'objet est sauvegardé (JSON dans `~/.local/state/workbook/M25-EXX/` sur `adm01`, copie dans `/var/lib/workbook/` sur le nœud), pour l'annulation.
- **Le jeton d'administration.** Le script prend `BAO_TOKEN` s'il est exporté, sinon le jeton de ta session (`~/.vault-token`, écrit par `bao login`). Il doit porter `plateforme-admin` (en politique directe ou d'identité) et vivre encore au moins 20 minutes ; sinon le script le dit et **rien n'est cassé** : reconnecte-toi et relance. Le jeton n'est jamais passé en argument, affiché ni écrit sur disque.
- **`kms01`.** Certaines variantes de M25-E42 (et donc de l'astreinte M25-E43) modifient la configuration de `kms01` : elles exigent un jeton d'administration de `kms01` (jeton racine régénéré par la procédure de M25-E28) dans la variable **`BAO_KMS_TOKEN`**, exportée dans ton shell sans passer par l'écran ni l'historique (`read -rs BAO_KMS_TOKEN && export BAO_KMS_TOKEN`). Sans elle, le script tire une variante qui ne touche pas à `kms01`. Révoque ce jeton dès l'injection faite : l'annulation n'en a pas besoin.
- **Ce que les pannes ne touchent jamais** (PLAN §4.12) : `kms01` n'est jamais scellé ni redémarré ; ni les parts, ni les clés de récupération, ni la clé racine, ni `/var/lib/openbao` (aucune donnée Raft n'est modifiée ou supprimée) ; la production de MédiAgenda ; ton compte et les comptes de bris de glace (`root` de GitLab, `root@pam`, `admin.conf`, `admin` local des VMs) ; `kube-system`, `argocd`. Une panne n'arrête **jamais plus d'un nœud** de la grappe, et toujours un nœud **en attente**, sauf M25-E39, qui assume la perte de quorum sans toucher aux données, après avoir vérifié la santé de la grappe et l'existence d'un instantané récent.
- **Avant d'injecter**, lance le contrôle indiqué dans les prérequis de l'exercice : il doit être vert. Le script refuse de casser un coffre qui ne va pas bien (pas exactement un actif et deux en attente, `kms01` scellé, jeton manquant) ou un état qui diffère de celui du corrigé, et le dit.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause. L'audit d'OpenBao, les journaux des nœuds, l'historique Git et `metadata.managedFields` sont, eux, des outils de diagnostic légitimes : ils disent qui a changé quoi, et quand.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 25 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M25-E43 et le mini-projet) : l'annulation ne revient jamais sur ta réparation.
- **Tiens un journal de diagnostic** par panne : `docs/socle/journal/AAAA-MM-JJ-INC-52XX.md` de `~/medisphere` (le numéro du ticket dans le nom, publié par MR) : heure, hypothèse, commande, résultat, conclusion, et qui a fait le changement fautif. Le post-mortem de l'astreinte va dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-5243.md`. Le runbook du palier est **RB-255** « coffre fermé » (`docs/securite/secrets/runbooks/RB-255-coffre-ferme.md`), écrit en M25-E43 à partir des fiches réflexes et des journaux des pannes précédentes.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre, ou en ouvrant plus grand qu'avant, en est un.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : sceller ou redémarrer `kms01` ; `bao operator raft remove-peer`, `bao operator init`, effacer ou déplacer quoi que ce soit sous `/var/lib/openbao`, restaurer un instantané sur la grappe de production ; redémarrer un nœud ou faire `bao operator step-down` tant que la tolérance d'autopilot est à 0 ou que tu n'as pas de cause ; élargir une politique, un rôle ou un `bound_claims` « pour débloquer » ; retirer le dispositif d'audit de `openbao.hcl` ; désactiver la vérification TLS (`tls_skip_verify`, `curl -k`, `BAO_SKIP_VERIFY`) ; activer `CI_DEBUG_TRACE` ou `set -x` dans un job qui lit le coffre ; afficher un jeton, un `secret_id`, un mot de passe ou le contenu d'un Secret ; garder un jeton racine régénéré au-delà de l'opération qui l'exige ; corriger à la main un objet décrit dans le code et en rester là.

> ⚠️ **Accès de secours** : M25-E39 et l'astreinte peuvent rendre le coffre muet, donc la CI de `plateforme/secrets` aussi. Avant le palier, vérifie le bris de glace de M25-E10 (`tofu apply` de `plateforme/secrets` depuis `adm01` avec ta session `plateforme-admin`), la procédure `generate-root` de M25-E28 (trois clés de récupération, révocation aussitôt) et ton accès SSH `admin` aux trois nœuds et à `kms01`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Grappe | `vault01` (10.10.20.21), `vault02` (.22), `vault03` (.23) : OpenBao **2.7.1**, Raft `/var/lib/openbao`, API **8200**, grappe **8201** (Raft et transmission des requêtes, ouvert seulement entre les trois nœuds par `pare_feu_local`, table `inet filtre_local`) ; autopilot `cleanup_dead_servers = true`, `min_quorum = 3` |
| VIP | 10.10.20.200 `openbao.par1.medisphere.internal`, keepalived VRID 120, script `chk_openbao_actif` (`sys/health` du nœud local : 200 seulement) |
| Seal | `transit` vers `https://kms01.par1.medisphere.internal:8200` (10.10.20.24), clé `autodescellement-par1`, jeton périodique orphelin (politique `kms-autodescellement`) dans `/etc/openbao/kms.env` (root, 600), surcharge systemd `medisphere.conf` ; `kms01` scellé par Shamir (trois dépositaires) |
| Configuration | `plateforme/secrets` (OpenTofu, pipeline authentifié par le rôle `ci-plateforme-secrets` ; bris de glace : `tofu apply` depuis `adm01`, M25-E10) ; `plateforme/ansible` (`playbooks/coffre.yml`, rôles `openbao`, `openbao_kms`, `pare_feu_local`, `keepalived`, `certificats_acme`) |
| Audit | dispositif déclaratif `audit "file" "fichier"` dans `openbao.hcl`, **identique sur les trois nœuds**, `/var/log/openbao/audit.log` → Alloy → Loki (`audit`, `{service="openbao"}`) ; règles du ruler de M25-E21 (`OpenBaoPolitiqueModifiee`…) |
| Alertes | `regles/secrets.yaml` (M25-E27) : `OpenBaoScelle`, `OpenBaoSansLeader`, `OpenBaoToleranceNulle`, `OpenBaoAuditEnEchec`, `OpenBaoBauxNombreux`, `OpenBaoInstantaneEnRetard`, `CertificatServicesExpireBientot` |
| Consommateurs | CI : méthode `gitlab/` (`jwt`), rôles `ci-<groupe>-<projet>`, composant `securite` v2.10.0 (job caché `.openbao-connexion` de la v2.9.0, signature par `transit` depuis M25-E20) ; ESO 2.13 : ClusterSecretStore `openbao`, SecretStore `openbao` par espace (rôles `eso-<espace>`, méthode `k8s-par1`) ; MédiAgenda : `db-mediagenda/`, baux d'1 h, ExternalSecret rafraîchis toutes les 30 min, Reloader ; PKI : `pki-services/`, rôle `services-k8s`, ClusterIssuer `openbao-services`, certificats de 48 h |
| Jetons des pannes | `BAO_TOKEN` exporté, sinon `~/.vault-token` (`plateforme-admin`, ≥ 20 min) ; `BAO_KMS_TOKEN` (facultatif, M25-E42 et E43) |
| Documentation | journaux `docs/socle/journal/AAAA-MM-JJ-INC-52XX.md`, post-mortem `docs/socle/post-mortems/AAAA-MM-JJ-INC-5243.md` ; fiches réflexes dans `docs/securite/secrets/` ; RB-250 (fuite), RB-251 (descellement), RB-252 (restauration), RB-255 (coffre fermé, M25-E43) |
| Tickets | INC-5235 à INC-5243 (pannes), PLAT-2644 (E44), SEC-2645 (E45) |
| Variables de `lab/lab.env` | `WB_OPENBAO_URL`, `WB_M25_NOEUDS` (défaut `vault01 vault02 vault03`), `WB_M25_KMS` (défaut `kms01`), `WB_M25_KMS_IP` (défaut `10.10.20.24`), `WB_M25_DOMAINE` (défaut `par1.medisphere.internal`), `WB_M25_PORT` (défaut `8200`), `WB_K8S_ADMIN_KUBECONFIG` |

Durée indicative du palier : 12 à 15 heures. Ordre conseillé :

```
E35 ─ E39 ─ E42          le coffre lui-même : un nœud, le quorum, le seal (E42 réutilise RB-251)
E36 ─ E40                les identités : connexion de la CI, puis politiques
E37 ─ E38 ─ E41          les consommateurs du cluster : ESO, identifiants dynamiques, PKI
E43                      après au moins une variante de chacune de E35 à E42
E44 ─ E45                hors de toute panne active ; E45 en dernier
```

---

### M25-E35 — Panne : le coffre est scellé après un redémarrage  `BF` `★★`

> **Ticket INC-5235** — *De : Nadia Roussel*
> Cette nuit, Lucas a fait la maintenance des nœuds du coffre : mises à jour, un redémarrage par nœud, « deux ou trois réglages ». Depuis, le coffre répond mal : mon contrôle du matin (`sys/health` sur `vault01`, `vault02`, `vault03` et sur `openbao.par1.medisphere.internal:8200`) rate une requête sur trois, et une alerte parle d'un nœud scellé. Lucas redémarre le nœud actif cet après-midi pour le noyau : est-ce que tout va tomber ? *(Le détail s'affiche à l'injection ; selon le cas, le contrôle est encore vert et Lucas signale seulement un « réglage d'essai » oublié sur un des nœuds.)*

**Objectifs pédagogiques**
- Mener un diagnostic méthodique sur une grappe : observer depuis les clients, mesurer depuis le nœud, comparer avec Git, sans rien toucher avant d'avoir une cause.
- Distinguer quatre états qui se ressemblent vus de loin : nœud **scellé**, processus **arrêté**, nœud **injoignable** (écoute, filtrage) et nœud **refusé** (TLS), et savoir lequel une alerte désigne vraiment.
- Lire la configuration **effective** d'un service (`systemctl cat`, `systemctl show`, `/proc/<PID>/limits`, `ss`, certificat présenté) et pas seulement les fichiers qu'on croit en place.
- Évaluer le risque d'une bascule vers un nœud malade et corriger à la racine, par le rôle Ansible, un nœud en attente à la fois.

**Prérequis** : M25-E24 (grappe, VIP, `chk_openbao_actif`), M25-E25 (seal `transit`), M25-E27 (supervision, `OpenBaoScelle`), M25-E28 (gabarit final du rôle `openbao`, surcharge `medisphere.conf`), M04-E29 (job `derive`) ; `lab/bin/check 25 28` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique**
- Grappe de trois nœuds (`vault01-03`) : **un** actif (`sys/health` = 200), deux en attente (429). La VIP `openbao.par1.medisphere.internal` (10.10.20.200) ne suit que l'actif. Le script `chk_openbao_actif` de keepalived interroge **le nœud local**, sous son nom, par la boucle locale (`--resolve <nœud>:8200:127.0.0.1`).
- Raft et le transfert de requêtes passent par le port de grappe **8201** (`cluster_address`). Les clients, la supervision et keepalived passent par l'API **8200** (`address` de l'écouteur).
- Référence : `/etc/openbao/openbao.hcl` (gabarit `openbao.hcl.j2`), `/etc/systemd/system/openbao.service.d/medisphere.conf` (`LimitNOFILE=65536`, durcissement), certificat ACME `/etc/openbao/tls/{cert,key}.pem` émis pour le nœud **et** le nom du service, relu par SIGHUP (`systemctl reload openbao`). Tout vient de `plateforme/ansible` (`playbooks/coffre.yml`).
- Prometheus (`job="openbao"`) interroge chaque nœud **par son nom** ; `OpenBaoScelle` (M25-E27) sonne sur `vault_core_unsealed == 0` **ou** `up == 0`.
- La panne touche **un seul nœud en attente**, ni les données ni le seal. Elle ne passe pas par OpenBao : c'est le système du nœud qui a changé.

> ⚠️ **Attention** : tant que tu n'as pas de cause, **pas** de `bao operator step-down`, **pas** de redémarrage du nœud actif : un nœud malade peut prendre la main, et alors c'est tout le coffre qui tombe. Ne lance jamais `bao operator unseal` ni de procédure de clés de récupération sur un nœud que tu n'as pas **vu** scellé depuis le nœud lui-même. Ne touche ni à `kms01`, ni à `/var/lib/openbao`. Ne copie jamais une clé privée d'un nœud à l'autre pour « réparer vite ».

**Injection** : `lab/bin/break 25 35` (3 variantes).

**Travail demandé**
1. **Observe depuis les clients.** Relève, pour chaque nœud et pour la VIP, le code HTTP **et** le message d'erreur de `curl` (pas seulement « ça marche / ça ne marche pas »). Quelle alerte a sonné, sur quelle série ? Formule tes hypothèses (scellé, arrêté, injoignable, refusé, limité en ressources, sorti de Raft) et dis lesquelles ces premiers relevés écartent.
2. **Mesure depuis le nœud.** Sur le nœud suspect : état du service et journal depuis la maintenance, `seal-status` **par la boucle locale**, adresses d'écoute, certificat présenté, limites effectives du processus. Vu de la grappe : `bao operator raft list-peers` et l'état d'autopilot. Le nœud est-il scellé ?
3. **Compare avec Git.** `playbooks/coffre.yml --limit <NŒUD> --check --diff` : qu'est-ce qu'Ansible voit, et qu'est-ce qu'il **ne voit pas** ? Complète la comparaison par la configuration effective (`systemctl cat`, comparaison avec un nœud sain). Énonce la cause en une phrase.
4. **Réponds à Nadia** : la requête sur trois, d'où vient-elle ? Et si l'actif redémarre cet après-midi avant ta réparation, que se passe-t-il, selon la cause trouvée ? Justifie à partir de `chk_openbao_actif`.
5. **Corrige à la racine**, sur le seul nœud touché (en attente), par le rôle Ansible ; si le rôle ne sait pas corriger cet écart, corrige à la main **et** corrige le rôle. Vérifie depuis les clients.
6. **Préviens** : fais en sorte que le job `derive` voie ce type d'écart, que l'alerte dise ce qu'elle a vraiment constaté, et propose la règle de revue qui aurait arrêté cette modification. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] Les trois nœuds répondent **par leur nom**, TLS vérifié : un actif, deux en attente, tous descellés ; la VIP répond.
- [ ] Sur chaque nœud : l'API écoute sur le réseau, aucune surcharge systemd hors `medisphere.conf`, limite de descripteurs du processus ≥ 65536, certificat présenté émis pour le nœud et pour `openbao.par1.medisphere.internal`.
- [ ] Le rôle `openbao` retire les surcharges systemd non déclarées ; une alerte « nœud injoignable » distincte de `OpenBaoScelle` est chargée dans Prometheus.
- [ ] Ton journal de diagnostic (un fichier dont le nom contient `INC-5235`, dans `docs/socle/journal/` de `plateforme/medisphere`) cite les relevés, la cause et la réponse à la question de Nadia.

**Vérification** : `lab/bin/check 25 35`

<details><summary>Indice 1</summary>

`curl -w '%{http_code} %{errormsg}\n'` dit **pourquoi** une requête échoue : `Connection refused` (rien n'écoute à cette adresse), délai dépassé (filtrage, processus figé), erreur de certificat (`SSL: no alternative certificate subject name matches`), ou un vrai code HTTP (503 : scellé). Un nœud scellé **répond** : il dit lui-même qu'il est scellé.
</details>

<details><summary>Indice 2</summary>

Depuis le nœud, interroge-le comme le fait keepalived : `curl --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt --resolve <NŒUD>.par1.medisphere.internal:8200:127.0.0.1 https://<NŒUD>.par1.medisphere.internal:8200/v1/sys/seal-status`. S'il répond là et pas depuis `adm01`, le problème est entre les deux : écoute, filtrage ou certificat.
</details>

<details><summary>Indice 3</summary>

`systemctl cat openbao` affiche l'unité **et toutes ses surcharges**, dans l'ordre où systemd les applique : la dernière valeur d'un réglage l'emporte. Compare `systemctl show -p LimitNOFILE openbao` et la ligne `Max open files` de `/proc/<PID>/limits` sur le nœud suspect et sur un nœud sain. Ansible ne signale que les fichiers qu'il gère.
</details>

**Pour aller plus loin** (facultatif) : sur un `bao server -dev` jetable de ton poste, lancé par `systemd-run --user -p LimitNOFILE=<N>`, cherche la plus petite limite qui laisse démarrer le serveur, puis ouvre des connexions en parallèle et note le message du journal. Documentation : [écouteur TCP](https://openbao.org/docs/configuration/listener/tcp/), [`sys/health`](https://openbao.org/api-docs/system/health/), [rechargement par SIGHUP](https://openbao.org/docs/commands/server/), [`systemd.unit` : surcharges](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html).

---

### M25-E36 — Panne : la CI ne lit plus ses secrets  `BF` `★★★`

> **Ticket INC-5236** — *De : Julien Petit*
> Le pipeline de `main` de `mediagenda/api` est rouge depuis ce matin : `securite:verification` s'arrête à l'étape OpenBao, avant même de vérifier les signatures. On n'a rien poussé depuis hier midi, le composant `securite` n'a pas changé de version, et relancer le job ne change rien. On a une mise en recette prévue à 14 h. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Lire un échec de connexion par jeton d'identité : distinguer un refus **à la connexion** (méthode, rôle, revendications) d'un refus **à la lecture** (politique), à partir du seul journal du job.
- Suivre la chaîne de validation de la méthode `jwt` : clés de signature (découverte OIDC ou `jwks_url`), émetteur, audience, revendications liées et leur **type**, puis politiques du jeton émis.
- Délimiter la panne (un rôle, une méthode, tous les projets ?) avant de toucher à quoi que ce soit, et retrouver l'écriture fautive dans l'audit.
- Corriger par le code, y compris quand le pipeline qui applique la configuration est lui-même touché, et mettre en place un contrôle de dérive.

**Prérequis** : M25-E10 (méthode `gitlab/`, job `.openbao-connexion` du composant `securite`), M25-E20, M25-E21 (audit dans Loki) ; `lab/bin/check 25 10` vert et dernier pipeline de `main` de `mediagenda/api` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique**
- Chaîne en place depuis M25-E10 : le job déclare un jeton d'identité (`id_tokens`, audience `openbao.medisphere.internal`) ; le job caché `.openbao-connexion` du composant `securite` le présente à `auth/gitlab/login` avec le rôle `ci-mediagenda-api` et affiche, s'il réussit, `OpenBao : connecté au rôle … (<politiques>)` ; le job lit ensuite le robot Harbor (`kv/plateforme/harbor/robot-ci`).
- La méthode `gitlab/` est de type `jwt`, configurée par la **découverte OIDC** de `git01` (racine MédiSphère comme autorité), émetteur lié. Les rôles `ci-<groupe>-<projet>` lient l'audience, `project_id`, `ref_protected`, `ref` et `ref_type` avec `bound_claims_type = "glob"`. Référence : `tofu/auth-gitlab.tf` de `plateforme/secrets` et `docs/securite/secrets/ci-et-openbao.md`.
- Ton jeton `plateforme-admin` lit la configuration de la méthode (`auth/gitlab/config`) et de ses rôles (`auth/gitlab/role/<rôle>`). Le journal d'audit est dans Loki (locataire `audit`, `{service="openbao"}`) : les connexions refusées y figurent comme les autres requêtes.
- La panne modifie la configuration **directement dans OpenBao**, avec **ton** jeton d'administration : `plateforme/secrets` n'a pas changé, le coffre si.

> ⚠️ **Attention** : n'active **jamais** `CI_DEBUG_TRACE` ni `set -x` pour « voir ce qui se passe » : le journal du job contiendrait le jeton d'identité, le jeton OpenBao et le jeton du robot Harbor, lisibles par tous les développeurs du projet. Ne recopie pas non plus le jeton d'identité d'un job dans un décodeur en ligne. Tout ce qu'il te faut est dans le journal normal du job, dans la configuration du coffre et dans l'audit.

**Injection** : `lab/bin/break 25 36` (4 variantes).

**Travail demandé**
1. **Lis l'échec.** Dans le journal du job `securite:verification`, relève le message exact renvoyé par OpenBao (code HTTP compris). La connexion a-t-elle réussi ? Si oui, avec quelles politiques ? Formule une hypothèse par **étape** de la chaîne (clés, émetteur, audience, revendications, politiques) et dis laquelle le message désigne.
2. **Délimite.** Les autres projets migrés en M25-E10 (`medidoc/medidoc`, le pipeline de `plateforme/secrets`) se connectent-ils encore ? Relance au besoin un job qui lit le coffre. Conclus : panne de la **méthode** ou d'un **rôle** ? Vérifie aussi que le coffre est descellé et que `main` est toujours protégée dans `mediagenda/api`.
3. **Compare la configuration à la référence.** Lis la méthode et le rôle **au format JSON** (pas en tableau), confronte chaque champ à `tofu/auth-gitlab.tf` et lance `tofu plan` en lecture. Pour l'écart trouvé, explique **pourquoi** il produit exactement ce message (ou ce refus de lecture).
4. **Trouve l'écriture.** Dans l'audit, retrouve la requête qui a modifié la méthode ou le rôle : heure, chemin, auteur (ici ton propre jeton : l'injection l'utilise). L'alerte `OpenBaoPolitiqueModifiee` d'E21 a-t-elle sonné ? Pourquoi ?
5. **Corrige par le code** : ramène le coffre à l'état de `plateforme/secrets` par le pipeline, ou par le bris de glace d'E10 si le pipeline ne peut pas s'en charger (dis pourquoi). Relance le pipeline de `main` de `mediagenda/api` jusqu'au vert.
6. **Préviens** : un script `outils/verifier-roles-ci.sh` dans `plateforme/secrets` qui contrôle, sur le coffre réel et en lecture seule, la méthode `gitlab/` et chaque rôle `ci-*` (audience, type des revendications liées, `ref_protected`, politiques existantes et utiles), lancé par un job après chaque apply et chaque nuit. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] La méthode `gitlab/` est configurée par la découverte OIDC de `git01`, sans `jwks_url` ni clé recopiée, émetteur lié.
- [ ] Le rôle `ci-mediagenda-api` lie l'audience `openbao.medisphere.internal`, `ref_protected` à la **chaîne** `"true"` avec le type `glob`, accepte `main` et `v*`, et porte la politique `ci-mediagenda-api` ; les autres rôles `ci-*` de M25-E10 lient la même audience et la même chaîne.
- [ ] Le dernier pipeline de `main` de `mediagenda/api` est vert, signature et vérification comprises.
- [ ] Le contrôle de dérive des rôles tourne dans la CI de `plateforme/secrets` ; ton journal de diagnostic (un fichier dont le nom contient `INC-5236`, dans `docs/socle/journal/`) cite le message exact du job et la cause.

**Vérification** : `lab/bin/check 25 36`

<details><summary>Indice 1</summary>

Un job qui affiche `OpenBao : connecté au rôle …` puis `permission denied` (403) **a** obtenu un jeton : le problème est dans ce que ce jeton peut faire, pas dans la connexion. Un code 400 avec `error validating claims` ou une erreur de vérification de signature arrive **avant** l'émission du jeton : regarde la méthode et le rôle, pas les politiques.
</details>

<details><summary>Indice 2</summary>

`bao read auth/gitlab/role/ci-mediagenda-api` affiche les valeurs **sans leur type** : `true` et `"true"` s'y ressemblent. `bao read -format=json … | jq '.data | {bound_audiences, bound_claims_type, bound_claims}'` les distingue. Compare ensuite avec ce que GitLab met dans le jeton (relevé dans `docs/livraison/ci/secrets-ci.md` §4, M19-E25).
</details>

<details><summary>Indice 3</summary>

Si **tous** les rôles de `gitlab/` sont refusés, le pipeline de `plateforme/secrets` l'est aussi : il ne peut pas réparer la méthode qui l'authentifie. C'est le cas prévu par l'avertissement et le bris de glace de M25-E10 (`tofu apply` depuis `adm01` avec ta session `plateforme-admin`). Pense aussi à `bao read auth/gitlab/config` : quelle source de clés la méthode utilise-t-elle, et cette URL répond-elle depuis `vault01` ?
</details>

**Pour aller plus loin** (facultatif) : sur un `bao server -dev` jetable de ton poste, monte une méthode `jwt` avec une clé que tu génères, signe toi-même des jetons (`ref_protected` en chaîne puis en booléen, audience juste puis fausse) et note le message de chaque refus, avec `bound_claims_type` à `string` puis à `glob`. Documentation : [méthode JWT/OIDC d'OpenBao](https://openbao.org/docs/auth/jwt/), [API de la méthode](https://openbao.org/api-docs/auth/jwt/) (`skip_jwks_validation`, `bound_claims_type`), [jetons d'identité de GitLab](https://docs.gitlab.com/ci/secrets/id_token_authentication/).

---

### M25-E37 — Panne : un ExternalSecret en erreur  `BF` `★★`

> **Ticket INC-5237** — *De : Julien Petit*
> En recette, Argo CD affiche `mediagenda-recette` en *Degraded* : l'ExternalSecret `harbor-pull` est en `SecretSyncedError` et le Secret n'est plus mis à jour depuis le coffre. On n'a rien changé dans l'overlay de recette (vous pouvez vérifier l'historique). Tant que ça ne bouge pas, je bloque la rotation du robot Harbor de recette. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer une synchronisation d'ESO en échec **sans lire les données du Secret** : condition, événements de l'ExternalSecret **et** du magasin, journaux du contrôleur, audit d'OpenBao.
- Situer la panne dans la chaîne ExternalSecret → SecretStore → connexion `k8s-par1` (compte de service, rôle, audience) → réseau → chemin KV lu dans le coffre, en commençant par la **portée** (un objet, un espace, tout le cluster).
- Comprendre deux mécanismes d'ESO qui trompent le diagnostic : le message générique de la condition (le détail n'est que dans les événements) et le **cache de jetons** OpenBao (un changement côté coffre peut ne se voir qu'au bout d'un quart d'heure).
- Corriger par le bon dépôt (`plateforme/k8s`, `plateforme/secrets` ou `plateforme/gitops`) et ajouter l'alerte qui aurait prévenu avant Julien.

**Prérequis** : M25-E12, M25-E13, M25-E14 ; `lab/bin/check 25 13` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique**
- ESO 2.13 (espace `external-secrets`, un seul contrôleur pour tout le cluster, cache de jetons OpenBao activé : `vault.enableTokenCache`, jetons de 15 min). Dans chaque espace applicatif, le compte `eso` et le SecretStore `openbao` sont posés par **`plateforme/k8s`** (`espaces/<espace>/80-openbao.yaml`, `task appliquer`, gestionnaire de champs `plateforme-k8s`) ; les ExternalSecret sont dans les overlays de `mediagenda/deploiement`, synchronisés par Argo CD (`selfHeal`).
- Côté coffre (**`plateforme/secrets`**, `tofu/eso-espaces.tf`) : rôle `eso-mediagenda-recette` de la méthode `k8s-par1` (compte `eso`, espace `mediagenda-recette`, audience `openbao.medisphere.internal`), politique `eso-mediagenda-recette` (lecture de `kv/data/mediagenda/recette/*` et des chemins `creds` de M25-E14).
- Réseau : la CiliumNetworkPolicy `external-secrets-sorties` (**`plateforme/gitops`**, `manifestes/external-secrets/`) n'autorise en sortie d'ESO que l'API, le DNS et `10.10.20.200:8200`. Hubble est disponible (M15).
- `harbor-pull` se rafraîchit toutes les heures ; les deux ExternalSecret d'identifiants dynamiques (`mediagenda-db-api`, `mediagenda-db-migrateur`) toutes les 30 min, pour des baux d'une heure.
- La panne peut toucher le cluster (objets **hors** de leur dépôt) ou le coffre. L'injection pose sur `harbor-pull` l'annotation `force-sync` pour que l'erreur apparaisse tout de suite : c'est une métadonnée, pas la cause.

> ⚠️ **Attention** : ne lis pas le contenu des Secrets (`kubectl get secret -o yaml`, `-o jsonpath='{.data}'`) pour diagnostiquer : statuts, événements et métadonnées suffisent. Ne corrige pas en modifiant l'ExternalSecret à la main : Argo CD le remettrait, et la cause resterait.

**Injection** : `lab/bin/break 25 37` (4 variantes ; jusqu'à 6 min d'attente pour constater la panne).

**Travail demandé**
1. **Mesure la portée.** ExternalSecret de `mediagenda-recette`, puis de tout le cluster ; état de **tous** les magasins (SecretStore de chaque espace, ClusterSecretStore `openbao`). Un objet, un espace, ou tout le cluster ? Note l'heure du dernier `refreshTime` réussi.
2. **Lis le vrai message.** La condition `Ready` ne donne qu'un message générique : trouve le détail dans les événements de l'ExternalSecret, puis dans ceux du magasin, puis dans les journaux du contrôleur d'ESO. Classe-le : refus du coffre sur un chemin, connexion refusée, compte introuvable, délai réseau.
3. **Remonte la chaîne** selon ce message, en comparant chaque maillon à son dépôt : `task diff` dans `plateforme/k8s` (magasin), `tofu plan` dans `plateforme/secrets` (rôle), les politiques Cilium de l'espace d'ESO face à `plateforme/gitops`. Si le coffre refuse, retrouve dans l'audit (Loki, locataire `audit`) le **chemin exact** que lit ESO et compare-le à ce que la politique `eso-mediagenda-recette` ouvre.
4. **Corrige par le bon dépôt**, puis obtiens une synchronisation immédiate sans toucher à la spec de l'ExternalSecret. Vérifie : magasin `Valid`, `harbor-pull` `SecretSynced` avec un `refreshTime` récent, application Argo CD saine, et que les identifiants dynamiques de recette ont repris leur rotation.
5. **Préviens** : alerte sur les ExternalSecret et les magasins en erreur dans `plateforme/observabilite` (règle testée par `promtool`), fiche réflexe « ExternalSecret en erreur » dans `docs/securite/secrets/`. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] Le SecretStore `openbao` de `mediagenda-recette` est identique au dépôt (KV v2, montage `kv`, méthode `k8s-par1`, rôle `eso-mediagenda-recette`, compte `eso`, audience `openbao.medisphere.internal`) et `Ready` ; le rôle d'OpenBao attend la même audience ; aucun `egressDeny` ne vise la sortie d'ESO.
- [ ] Aucun magasin du cluster en erreur ; tous les ExternalSecret de `mediagenda-recette` `SecretSynced`, `harbor-pull` synchronisé depuis moins de 70 min.
- [ ] Une alerte sur `externalsecret_status_condition` est chargée dans Prometheus ; ton journal de diagnostic (un fichier dont le nom contient `INC-5237`, dans `docs/socle/journal/`) cite le message exact (sans valeur de secret) et la cause.

**Vérification** : `lab/bin/check 25 37`

<details><summary>Indice 1</summary>

`kubectl -n mediagenda-recette describe externalsecret harbor-pull` montre les événements `UpdateFailed`. S'ils disent seulement « SecretStore "openbao" is not ready », le détail est dans `kubectl -n mediagenda-recette describe secretstore openbao`. Si **tous** les magasins du cluster sont en erreur en même temps, l'overlay de recette n'y est pour rien.
</details>

<details><summary>Indice 2</summary>

Dans le SecretStore, `path` désigne le **moteur** (`kv`) et `version` dit à ESO comment construire le chemin : en `v2`, il insère `data/`. Un 403 sur `…/v1/kv/mediagenda/recette/…` n'est pas un problème de politique trop étroite. Côté connexion, OpenBao compare l'audience du jeton projeté (`serviceAccountRef.audiences`) à l'`audience` du rôle : `bao read auth/k8s-par1/role/eso-mediagenda-recette`.
</details>

<details><summary>Indice 3</summary>

Dans Cilium, un `egressDeny` l'emporte sur toute autorisation, quelle que soit la politique qui la donne. `kubectl -n external-secrets get cnp` liste aussi ce qu'Argo CD ne gère pas ; `hubble observe -n external-secrets --to-ip 10.10.20.200 --verdict DROPPED` montre les paquets refusés. Pense à calculer les plages : quelles adresses couvre un `/26` ?
</details>

**Pour aller plus loin** (facultatif) : la [référence du fournisseur Vault d'ESO](https://external-secrets.io/latest/provider/hashicorp-vault/) (cache de jetons, `version`, méthode `kubernetes`) et la page [Metrics](https://external-secrets.io/latest/api/metrics/) d'ESO ; les [politiques de refus de Cilium](https://docs.cilium.io/en/stable/security/policy/deny/). Mesure le délai entre une modification de l'audience du rôle dans un coffre d'essai et la première erreur d'un magasin qui l'utilise, avec et sans cache de jetons.

---

### M25-E38 — Panne : MédiAgenda perd sa base  `BF` `★★★`

> **Ticket INC-5238** — *De : Julien Petit*
> En recette, toutes les heures environ, l'API renvoie des 500 pendant un moment ; les journaux disent `password authentication failed for user "v-…"`. Parfois ça revient seul, parfois non. Personne n'a livré, la base répond quand je m'y connecte avec mon compte de lecture. La prod va bien, mais elle tourne sur les mêmes identifiants dynamiques depuis E15 : je veux comprendre avant que ça lui arrive. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre de bout en bout la vie d'un identifiant dynamique : générateur `VaultDynamicSecret` → ExternalSecret → Secret → Reloader → pod ; bail dans OpenBao → compte `v-…` et `VALID UNTIL` dans PostgreSQL → révocation (`DROP ROLE`).
- Situer une panne d'identifiants dans le temps : **quand** le compte est né, **quand** il devait mourir, **quand** il a été remplacé — et en déduire la cause.
- Distinguer quatre familles de cause : durée du rôle, révocation, connexion d'administration du coffre (`openbao`), réseau entre le coffre et la base.
- Reprendre la main sur la connexion d'un moteur `database` sans qu'aucun humain ne connaisse le mot de passe, et réapprovisionner les consommateurs sans attendre.

**Prérequis** : M25-E14, M25-E15, M25-E21 (audit dans Loki), M25-E23 (RB-250) ; `lab/bin/check 25 14` et `lab/bin/check 25 15` verts avant l'injection.
**Durée indicative** : 50 min (temps cible), prévention comprise.

**Contexte technique**
- Recette : moteur `db-mediagenda/`, connexion **`mediagenda-recette`** (`postgresql://…@10.10.41.64:5432/mediagenda`, `sslmode=verify-ca`, compte PostgreSQL **`openbao`** dont seul OpenBao connaît le mot de passe depuis `rotate-root`), rôle **`mediagenda-api-recette`** (`default_ttl` 1 h, `max_ttl` 24 h, `CREATE ROLE … VALID UNTIL '{{expiration}}' IN ROLE mediagenda_api`, révocation `DROP ROLE`). Code : `plateforme/secrets`, `tofu/db-mediagenda.tf`.
- Cluster CNPG **`mediagenda-db`** de l'espace **`mediagenda-recette`** : rôles gérés `openbao` et `mediagenda_api`, Service **`mediagenda-db-openbao`** (LoadBalancer 10.10.41.64, `externalTrafficPolicy: Local`), CiliumNetworkPolicy **`mediagenda-db-depuis-openbao`** (5432 ouvert à 10.10.20.21-23).
- ESO : générateur **`mediagenda-api`** (`db-mediagenda/creds/mediagenda-api-recette`), ExternalSecret **`mediagenda-db-api`** (`refreshInterval` 30 min, clés `uri` et `username`), Rollout `mediagenda` redémarré par **Reloader** quand le Secret change (≈ 2 min, E15).
- Ton jeton `plateforme-admin` lit la configuration du moteur, demande des identifiants **de recette**, liste les baux, fait `rotate-root`, révoque. `kubectl cnpg psql` te donne le superutilisateur local de la base. Audit : Loki, locataire `audit`, `{service="openbao"}` ; journal d'OpenBao : `journalctl -u openbao` sur le nœud actif. Hubble est disponible (`hubble observe`).
- La panne ne touche **que** la recette ; elle agit avec ton jeton d'administration et ton kubeconfig.

> ⚠️ **Attention** :
> - **Rien sur la prod** pendant le diagnostic : ni `rotate-root`, ni révocation, ni `force-sync` sur `mediagenda-prod`. Si tu dois comparer, **lis** seulement.
> - Ne révoque **jamais** des baux « pour voir » ou « pour nettoyer » : chaque bail révoqué est un compte supprimé, et les sessions ouvertes avec lui meurent. Un `bao read …/creds/…` d'essai crée un vrai compte : révoque **ce** bail-là (`bao lease revoke <BAIL>`) dès l'essai fini.
> - Si tu dois redonner un mot de passe au compte `openbao`, garde ta session `kubectl cnpg psql` ouverte jusqu'au `rotate-root` réussi (c'est ton accès de secours), et qu'aucun mot de passe n'apparaisse ni à l'écran, ni dans l'historique, ni en argument d'une commande (tubes seulement). Retour arrière : la même procédure, rejouée (`identifiants-dynamiques.md` § 4).
> - Ne modifie pas une CiliumNetworkPolicy à la main : MR `plateforme/k8s`.

**Injection** : `lab/bin/break 25 38` (4 variantes).

**Travail demandé**
1. **Date le symptôme.** Dans les journaux de l'API, relève le nom exact du compte refusé et l'heure des premiers refus. Compare avec : l'heure du dernier rafraîchissement de l'ExternalSecret (`status.refreshTime`, événements), les redémarrages du Rollout, et, dans PostgreSQL, l'existence de ce compte et son `rolvaliduntil`. Écris une phrase : « le compte X, né à …, devait vivre jusqu'à …, a cessé de marcher à … ».
2. **Interroge le coffre.** Baux actifs sous `db-mediagenda/creds/mediagenda-api-recette` (combien, quelle durée à l'émission), configuration du rôle et de la connexion, et l'audit : demandes d'identifiants en erreur, révocations, écritures sur `db-mediagenda/roles/*` ou `config/*`. Lis aussi le journal d'OpenBao du nœud actif (révocations en échec).
3. **Interroge le chemin réseau** si le coffre ne joint plus la base : depuis le nœud actif, un test TCP vers 10.10.41.64:5432 ; dans le cluster, les politiques de l'espace et les flux refusés (Hubble).
4. **Conclus et corrige** par le bon canal : `plateforme/secrets` (pipeline) pour le coffre, `plateforme/k8s` pour la base et le réseau, procédure de bris de glace de `identifiants-dynamiques.md` § 4 pour une connexion perdue. Puis **réapprovisionne** l'API sans attendre le cycle d'ESO, et vérifie `/pret` en continu pendant le redémarrage.
5. **Explique** pour chaque cause pourquoi le symptôme est **périodique**, **unique** ou **permanent**, et combien de temps la prod aurait tenu dans la même situation.
6. **Préviens** : des règles d'audit dans le ruler de Loki qui auraient sonné avant Julien — **`IdentifiantsDynamiquesEnEchec`** (demandes `creds` en erreur) et **`OpenBaoBauxRevoquesEnMasse`** (révocation par préfixe réussie) ; une section « Quand l'application perd sa base » dans `docs/securite/secrets/identifiants-dynamiques.md` (dont une règle liant la durée des identifiants à l'intervalle de rafraîchissement) ; ton journal de diagnostic.

**Critères de réussite**
- [ ] Le rôle `mediagenda-api-recette` a de nouveau `default_ttl` 1 h et `max_ttl` 24 h, et un identifiant vit au moins un cycle d'ESO plus 10 min.
- [ ] En recette, l'ExternalSecret `mediagenda-db-api` est `Ready` et rafraîchi depuis moins de 35 min, au moins un bail `mediagenda-api-recette` est actif, `/pret` répond 200.
- [ ] Aucune CiliumNetworkPolicy de `mediagenda-recette` ne refuse 10.10.20.21-23 sur 5432 ; `mediagenda-db-depuis-openbao` est intacte ; aucun humain ne connaît le mot de passe d'`openbao`.
- [ ] Les règles `IdentifiantsDynamiquesEnEchec` et `OpenBaoBauxRevoquesEnMasse` sont chargées par le ruler de Loki (locataire `audit`) ; ton journal de diagnostic (un fichier dont le nom contient `INC-5238`, dans `docs/socle/journal/`) date la naissance et la mort du compte refusé et nomme la cause.

**Vérification** : `lab/bin/check 25 38`

<details><summary>Indice 1</summary>

Le Secret `mediagenda-db-api` a une clé `username` : lis-la seule (`kubectl get secret … -o jsonpath='{.data.username}' | base64 -d`), jamais `uri`. Ce nom, cherché dans `pg_roles`, répond à deux questions d'un coup : le compte existe-t-il encore, et jusqu'à quand était-il valable ? Un compte **absent** et un compte **expiré** ne racontent pas la même histoire.
</details>

<details><summary>Indice 2</summary>

Trois horloges tournent : le bail (durée = la plus petite entre `default_ttl` et `max_ttl` du rôle, plafonnée par le montage), le cycle d'ESO (30 min) et le redémarrage par Reloader. Si la première est plus courte que la deuxième, le trou revient à **chaque** cycle. Si ESO n'arrive plus à obtenir un identifiant, l'ancien Secret reste en place et l'application tient… jusqu'au `VALID UNTIL` de son compte.
</details>

<details><summary>Indice 3</summary>

Une connexion déjà ouverte survit à un changement de mot de passe comme à une nouvelle politique réseau : OpenBao ne voit la panne qu'à sa **prochaine** connexion. Pour savoir lequel des deux, le message d'erreur d'OpenBao suffit souvent (`password authentication failed for user "openbao"` ou un délai dépassé). Et si OpenBao ne peut plus s'authentifier, il ne peut pas non plus faire `rotate-root` : quelqu'un d'autre doit lui redonner un mot de passe, sans le connaître.
</details>

**Pour aller plus loin** (facultatif) : mesure sur un banc (`wb-essais`) ce que devient une session PostgreSQL **ouverte** quand son compte atteint `VALID UNTIL` sans être supprimé (la vérification du mot de passe n'a lieu qu'à la connexion) ; compare avec un `DROP ROLE`. Lis la [documentation des baux](https://openbao.org/docs/concepts/lease/), de l'[API des baux](https://openbao.org/api-docs/system/leases/) (`revoke-prefix`, `revoke-force`) et du [moteur database](https://openbao.org/api-docs/secret/databases/#rotate-root-credentials) ; le [rafraîchissement forcé d'ESO](https://external-secrets.io/latest/introduction/faq/) ; les [politiques de refus de Cilium](https://docs.cilium.io/en/stable/security/policy/deny/).

---

### M25-E39 — Panne : la grappe n'a plus de leader  `BF` `★★★`

> **Ticket INC-5239** — *De : Nadia Roussel* — *Copie : Karim Benali*
> 6 h 52 : l'alerte `OpenBaoSansLeader` a sonné. Depuis, plus rien ne passe par `openbao.par1.medisphere.internal` : les pipelines échouent sur `bao kv get`, ESO met ses `ExternalSecret` en erreur, et MédiAgenda recette n'aura plus d'identifiants de base dans moins d'une heure. Lucas a fait cette nuit la maintenance des nœuds du coffre ; il est en congé jusqu'à lundi et ne répond pas. Remets le coffre en route **sans rien perdre**, puis explique-moi ce qui s'est passé. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Comprendre le **quorum** d'une grappe Raft (majorité des électeurs : 2 sur 3) et pourquoi un nœud vivant, descellé et à jour ne sert **rien** quand il est seul.
- Diagnostiquer un coffre sans nœud actif **sans** la CLI habituelle : codes de `sys/health` nœud par nœud, `sys/leader`, journaux d'élection, état des services, pare-feu local, flux du port de grappe 8201 testés **entre** nœuds.
- Distinguer dans les journaux un pair **arrêté** d'un pair **injoignable** (connexion refusée contre délai dépassé).
- Rétablir le quorum par le geste le **moins** risqué, un geste à la fois, puis rétablir la **marge** ; savoir ce qu'on ne fait **pas** (retrait de pair, réinitialisation, restauration) et quand la procédure de récupération par `peers.json` devient légitime.

**Prérequis** : M25-E24 (grappe, VIP, autopilot), M25-E25 (seal `transit`, RB-251), M25-E26 (instantanés horaires), M25-E27 (alertes du coffre) ; `lab/bin/check 25 24` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique**
- Grappe : `vault01` (10.10.20.21), `vault02` (.22), `vault03` (.23), stockage Raft dans `/var/lib/openbao`, API 8200, **grappe 8201** (Raft et transfert de requêtes, TLS interne), trois électeurs ; VIP 10.10.20.200 portée par keepalived sur le **seul** nœud qui répond 200 à `sys/health`. Auto-descellement par `kms01` (10.10.20.24). Autopilot : `cleanup_dead_servers = true`, `min_quorum = 3`.
- Pare-feu local des nœuds : table `inet filtre_local` produite par le rôle `pare_feu_local` (M06-E30, flux du coffre au M25-E24) ; le 8201 n'y est ouvert qu'**entre** les trois nœuds : il ne se teste pas depuis `adm01`.
- La panne ne touche **ni** les données Raft, **ni** la configuration Raft, **ni** `kms01`, ni les VMs (elles restent allumées). Avant d'agir, le script vérifie que la grappe est saine, qu'un instantané de moins de 2 h existe et que les nœuds qu'il arrête sauront se desceller seuls.
- Documentation à garder ouverte : [stockage intégré et quorum](https://openbao.org/docs/concepts/integrated-storage/), [`bao operator raft`](https://openbao.org/docs/commands/operator/raft/), [`/sys/health`](https://openbao.org/api-docs/system/health/), [`/sys/leader`](https://openbao.org/api-docs/system/leader/), RB-251, ton `grappe.md` (M25-E24).

> ⚠️ **Attention** : ici, chaque geste de trop peut coûter des données ou des heures. **Ne fais jamais**, pendant cet exercice : `bao operator raft remove-peer`, `bao operator init`, effacement ou déplacement de quoi que ce soit sous `/var/lib/openbao`, restauration d'un instantané, redémarrage ou scellement de `kms01`, arrêt d'un nœud qui tourne. Ne crée pas de fichier `peers.json` : la question 6 le **décrit**, elle ne le fait pas exécuter. Retour arrière à tout moment : `lab/bin/break 25 39 --annuler` (relance les services, retire le filtrage, attend une grappe saine).

**Injection** : `lab/bin/break 25 39` (3 variantes ; compte 1 à 3 minutes : le script attend la perte effective du leader).

**Travail demandé**
1. **Constate sans rien changer.** Pour chaque nœud (adresse propre, pas la VIP) : code de `sys/health`, `seal-status`, réponse de `sys/leader`. Puis essaie `bao operator raft list-peers` et `bao operator raft autopilot state` (avec `BAO_ADDR` sur un nœud). Note les erreurs exactes et explique-les : pourquoi un nœud **descellé** ne sait-il plus répondre ? Que vaut `leader_address` sur chaque nœud, et peux-tu t'y fier ? Où est passée la VIP ? Note l'heure : c'est le T0 de ton journal.
2. **Lis les nœuds.** Sur chacun : état du service `openbao` depuis quand et pourquoi, journal d'`openbao` depuis le début de la nuit (élections, candidats, erreurs vers les pairs), règles nftables **complètes**, écoute du 8201. Teste le flux 8201 d'un nœud vers chacun des deux autres. Range chaque pair dans une case : *vivant et joignable*, *arrêté*, *vivant mais injoignable*.
3. **Raisonne avant d'agir.** Combien de nœuds faut-il pour élire un leader ? Lesquels peux-tu rendre à la grappe, par quel geste, avec quel risque ? Écris l'ordre de tes gestes dans ton journal **avant** le premier. Explique aussi pourquoi aucune écriture n'a pu être perdue pendant la panne.
4. **Rétablis le quorum**, un geste à la fois, en observant entre deux gestes (`sys/health` des trois nœuds, VIP). Un geste sur un nœud passe par ce qu'il est (service, pare-feu) : avant de retirer un filtrage, établis s'il vient du rôle `pare_feu_local` (compare la règle active avec `/etc/nftables.conf` et avec Git) ou d'ailleurs : on ne défait pas à la main ce que Git a voulu.
5. **Rétablis la marge.** Le service rendu ne suffit pas : `autopilot state` doit être sain avec une tolérance d'au moins une panne, chaque serveur sain. Vérifie une écriture et une lecture par la VIP (`kv/wb-essais/…`), relance un pipeline et force le rafraîchissement d'un `ExternalSecret`.
6. **Dernier recours, sur le papier.** Supposons que `vault02` et `vault03` aient été **détruits** (disques perdus, pas de sauvegarde utilisable). Décris, d'après la documentation d'OpenBao (et ce qu'elle hérite de Vault), comment remettre `vault01` seul en service : quel fichier, où, avec quel contenu (identifiants et adresses de **ta** grappe), dans quel état doivent être les nœuds, ce que le serveur fait du fichier, ce qu'on risque de perdre, et ce qui distingue cette situation de celle d'aujourd'hui.
7. **Préviens.** Une fiche « maintenance de la grappe » dans `docs/securite/secrets/` : la vérification à faire avant **chaque** geste sur un nœud, l'ordre des nœuds, ce qu'on ne fait jamais, la procédure de la question 6 en dernier recours. Dis si les alertes du M25-E27 ont sonné au bon moment (et lesquelles sont restées muettes, et pourquoi).

**Critères de réussite**
- [ ] Les trois nœuds répondent, descellés ; un seul actif (200), deux en attente (429) ; `sys/leader` lu par la VIP désigne le nœud qui la porte.
- [ ] `vault01`, `vault02` et `vault03` sont toujours les trois pairs Raft, tous électeurs, avec un leader ; autopilot sain, tolérance d'au moins une panne, chaque serveur sain.
- [ ] `openbao` est actif et activé au démarrage sur les trois nœuds ; plus aucune règle nftables ne bloque le port 8201.
- [ ] Ton journal de diagnostic (un fichier dont le nom contient `INC-5239`, dans `docs/socle/journal/` de `plateforme/medisphere`) donne la chronologie de la panne lue dans les journaux des nœuds, la cause par nœud, tes gestes dans l'ordre et la réponse à la question 6.

**Vérification** : `lab/bin/check 25 39`

<details><summary>Indice 1</summary>

`sys/health` ne dépend pas d'un actif : chaque nœud répond pour lui-même (lis la page de l'API pour la signification de 200, 429, 503 et des paramètres qui changent ces codes). Un nœud en attente sert lui-même certaines **lectures** depuis sa copie locale de l'état (`list-peers` en fait partie : regarde bien la colonne `State`) ; tout ce qui écrit ou exige l'actif (`autopilot state`, une connexion, une écriture) est **transmis** à l'actif. Et `sys/leader` d'un nœud en attente lit une information que ce nœud garde **localement** : demande-toi si elle a pu être mise à jour depuis que la grappe a perdu sa majorité.
</details>

<details><summary>Indice 2</summary>

Dans `journalctl -u openbao`, cherche les lignes de la bibliothèque Raft : passage en candidat, élection relancée, échec des demandes de vote vers chaque pair, et sur l'ancien leader le moment où il renonce faute de majorité. L'erreur réseau qui suit chaque échec dit **pourquoi** le pair ne répond pas : une connexion refusée (rien n'écoute sur ce port) n'a pas la même cause qu'un délai dépassé (rien ne revient). Pour le second cas, `nft list ruleset` en entier : le rôle `pare_feu_local` ne produit qu'une table.
</details>

<details><summary>Indice 3</summary>

Pour élire un leader, il faut deux électeurs **vivants qui se parlent** sur le 8201. Le geste le plus sûr est celui qui ne fait que **rendre** à la grappe ce qu'elle avait : un service relancé (il se descelle seul par `kms01`) ou un filtrage parasite retiré. Après le premier geste, regarde `autopilot state` : si le service revient avec une tolérance de 0, il te reste un nœud à rendre. Pour la question 6, cherche « *lost quorum* » et « *peers.json* » dans la documentation du stockage Raft (celle de Vault détaille le format ; vérifie l'emplacement attendu par OpenBao).
</details>

**Pour aller plus loin** (facultatif) : mesure, sur la grappe saine et par la boucle d'écriture du M25-E24, le temps entre le retour du deuxième électeur et la première écriture réussie par la VIP ; décompose-le (élection Raft, prise du verrou d'actif, script de keepalived). Lis la page [*Integrated storage*](https://openbao.org/docs/concepts/integrated-storage/) sur les non-électeurs et l'option `performance_multiplier` du [stockage Raft](https://openbao.org/docs/configuration/storage/raft/) : qu'est-ce que changerait une grappe de **cinq** électeurs, ici, sur un seul hyperviseur ?

---

### M25-E40 — Panne : « permission denied »  `BF` `★★`

> **Ticket INC-5240** — *De : Julien Petit*
> Depuis ce matin, impossible de toucher aux secrets de développement de MédiAgenda : `bao kv put -mount=kv mediagenda/dev/…` et l'interface web répondent `permission denied`, alors que je suis bien dans le groupe `mediagenda` et que rien n'a changé de mon côté. Hier soir ça marchait. Lucas a « rangé les politiques » cette semaine. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer un refus d'OpenBao **sans** se connecter à la place de l'utilisateur ni lui demander son jeton : `sys/capabilities-accessor` sur l'accesseur de son jeton, `bao token lookup -accessor`, audit (`error: "permission denied"`, `auth.policies`, `auth.identity_policies`).
- Maîtriser les règles de correspondance des politiques : `*` (préfixe) contre `+` (un seul segment), chemins `data/` et `metadata/` du KV v2, règle **la plus précise** entre politiques, capacité `deny` qui l'emporte **sur un motif identique**.
- Suivre la chaîne identité → groupe externe → alias de groupe → politiques, et savoir **quand** un changement de groupe prend effet (immédiatement, ou à la prochaine connexion).
- Corriger par le code (`plateforme/secrets`) et écrire le test qui aurait arrêté l'erreur.

**Prérequis** : M25-E05, M25-E06, M25-E08, M25-E21 ; `lab/bin/check 25 40` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique**
- Julien (`julien.petit`, groupe `mediagenda` de l'annuaire) se connecte par OIDC (rôle `personne`, politique `default`) ; ses droits viennent du **groupe externe** `mediagenda` d'OpenBao, relié à la revendication `groups` de Keycloak par un **alias de groupe** sur le montage `oidc/`, qui porte la politique `mediagenda-dev` (`politiques/mediagenda-dev.hcl` de `plateforme/secrets`). Son compte d'essai a un mot de passe provisoire depuis le M24.
- Ton jeton `plateforme-admin` peut lister les accesseurs (`auth/token/accessors`), lire un jeton par son accesseur (`auth/token/lookup-accessor`), calculer les capacités d'un jeton par son accesseur (`sys/capabilities-accessor`) et lire les politiques et les groupes (`identity/*`). Le journal d'audit est dans Loki (locataire `audit`, `{service="openbao"}`).
- La panne modifie la configuration **directement dans OpenBao**, comme une « réparation » faite à la main en urgence : `plateforme/secrets` n'a pas changé, le coffre si. L'injection agit avec **ton** jeton d'administration : l'audit te désignera comme auteur (en production, ce serait celui de quelqu'un d'autre ; c'est une question pour le post-mortem).

> ⚠️ **Attention** : ne te connecte pas en `julien.petit` dans ton terminal de travail : `bao login` écraserait ton jeton d'administration dans `~/.vault-token`. Si tu veux reproduire avec son compte, utilise une fenêtre privée du navigateur, ou `bao login -no-store` dans un second terminal, sans jamais afficher le jeton obtenu.

**Injection** : `lab/bin/break 25 40` (4 variantes).

**Travail demandé**
1. **Reproduis sans usurper.** Retrouve un jeton récent de Julien par son **accesseur** (liste des accesseurs, `bao token lookup -accessor`, champ `display_name`), puis demande à OpenBao ce que ce jeton peut faire sur `kv/data/mediagenda/dev/<un secret>` et sur `kv/metadata/mediagenda/dev/`. Note `policies` **et** `identity_policies` du jeton. S'il n'a pas de jeton vivant, demande-lui de se reconnecter (ou fais-le en fenêtre privée), puis recommence.
2. **Lis l'audit.** Dans Loki, retrouve les refus de Julien : chemin exact demandé (`request.path`), opération, politiques portées. Le chemin demandé par la CLI ou l'interface est-il celui que tu crois ?
3. **Remonte la chaîne.** Groupe externe `mediagenda` (politiques, alias, montage de l'alias), contenu **actuel** de chaque politique qu'il porte, et comparaison avec `plateforme/secrets` (`tofu plan` en lecture : quelle ressource dérive ?). Pour chaque écart, explique **pourquoi** il produit exactement ce refus (motif trop court, mauvais préfixe, `deny` qui l'emporte, groupe qui ne correspond plus à la revendication).
4. **Corrige par le code** : ramène le coffre à l'état de `plateforme/secrets` par le pipeline (ou, si l'intention de Lucas était légitime, écris-la correctement dans une MR). Vérifie avec les capacités par accesseur, puis demande à Julien de réessayer. Explique si un **nouveau** jeton est nécessaire ou non selon la cause.
5. **Préviens** : un test automatique des politiques dans la CI de `plateforme/secrets` (des chemins et les capacités attendues pour chaque politique, évalués sur un OpenBao jetable) ; une fiche réflexe « permission denied » dans `docs/securite/secrets/`. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] `mediagenda-dev` accorde de nouveau la création, la lecture, la mise à jour et la suppression sous `kv/data/mediagenda/dev/` (tout niveau de profondeur), la liste sous `kv/metadata/mediagenda/dev/`, et rien en dehors.
- [ ] Le groupe externe `mediagenda` ne porte que `mediagenda-dev`, son alias s'appelle exactement `mediagenda` sur le montage `oidc/` ; aucune politique ne pose de `deny` sur les chemins de développement de MédiAgenda.
- [ ] Le test des politiques tourne dans la CI de `plateforme/secrets` ; ton journal de diagnostic (un fichier dont le nom contient `INC-5240`, dans `docs/socle/journal/`) cite le refus exact (ligne d'audit résumée, sans valeur) et la cause.

**Vérification** : `lab/bin/check 25 40`

<details><summary>Indice 1</summary>

`bao list auth/token/accessors` puis, pour chacun, `bao token lookup -format=json -accessor <ACCESSEUR> | jq '.data.display_name'` : un jeton OIDC de Julien s'appelle `oidc-julien.petit`. Ensuite, `bao write sys/capabilities-accessor accessor=<ACCESSEUR> paths=<CHEMIN>` répond pour **son** jeton, avec **ses** politiques d'identité du moment.
</details>

<details><summary>Indice 2</summary>

Avec le KV v2, `bao kv put -mount=kv mediagenda/dev/x` écrit sur `kv/data/mediagenda/dev/x` et `bao kv list` lit `kv/metadata/…`. Dans une politique, `+` remplace **un** segment et `*` n'est permis qu'**en fin** de motif, où il couvre tout le reste. Entre deux politiques, OpenBao ne retient que la règle au motif **le plus précis** ; deux motifs **identiques** voient leurs capacités réunies, et `deny` l'emporte alors sur tout.
</details>

<details><summary>Indice 3</summary>

Un groupe externe ne se remplit qu'**à la connexion** (et au renouvellement) : OpenBao compare chaque valeur de la revendication `groups` aux **noms d'alias** des groupes du montage. Si aucun alias ne s'appelle exactement comme le groupe de Keycloak, l'entité sort du groupe à sa prochaine connexion, et ses jetons suivants n'ont plus que `default`. Une politique ajoutée à un groupe s'applique au contraire **tout de suite** aux jetons existants.
</details>

**Pour aller plus loin** (facultatif) : la [documentation des politiques](https://openbao.org/docs/concepts/policies/) détaille l'ordre de priorité entre motifs. Écris trois paires de motifs dont tu prédis le gagnant, puis vérifie-les sur un `bao server -dev` jetable de ton poste. Compare avec la façon dont l'interface web liste un dossier qu'on ne peut pas lister (et le paramètre `listing_visibility` des montages).

---

### M25-E41 — Panne : les certificats de service sont refusés  `BF` `★★`

> **Ticket INC-5241** — *De : Julien Petit* — *Copie : Sophie Laurent*
> En recette, quelque chose ne va plus avec les certificats de service : selon le moment, c'est cert-manager qui affiche des certificats en échec, les pièces jointes de MédiAgenda vers MédiDoc qui tombent (poignée de main TLS refusée), ou le contrôle hebdomadaire de Sophie (`openssl verify -crl_check`) qui rejette nos certificats. Rien n'a été déployé de notre côté. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre une émission de bout en bout : `Certificate` → `CertificateRequest` → ClusterIssuer `openbao-services` → méthode `k8s-par1` → `pki-services/sign/services-k8s` → émetteur → certificat → relais ghostunnel → CRL.
- Lire un refus de signature d'OpenBao (domaines autorisés du rôle, **usage** de l'émetteur) et distinguer ce qui **refuse** de ce qui **réduit** (une durée au-delà de `max_ttl` est ramenée au maximum, avec un avertissement).
- Lire un certificat émis : extensions d'usage (*Extended Key Usage*), noms, durée, et comprendre pourquoi un serveur TLS refuse un certificat client sans l'usage `clientAuth`.
- Lire une CRL (`lastUpdate`, `nextUpdate`) et la configuration qui la reconstruit.

**Prérequis** : M25-E16, M25-E27 ; M15 (cert-manager, `cmctl` sur `adm01`) ; `lab/bin/check 25 41` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique**
- PKI de services : montage `pki-services/`, émetteur `services-2026` (« MédiSphère Services CA », clé dans OpenBao), rôle `services-k8s` (domaines `svc` et `svc.cluster.local` avec sous-domaines, client **et** serveur, 72 h au plus), CRL de 72 h reconstruite automatiquement, configuration dans `plateforme/secrets` (`tofu/pki-services.tf`). Points publics : `…/v1/pki-services/ca/pem`, `…/v1/pki-services/crl/pem`.
- Recette : `Certificate` `medidoc-mtls` (espace `medidoc-recette`) et `mediagenda-mtls` (espace `mediagenda-recette`), 48 h, renouvelés 16 h avant l'échéance ; relais ghostunnel (serveur dans MédiDoc, port 8443, client dans MédiAgenda), certificats relus toutes les 5 minutes.
- Le contrôle de Sophie (à rejouer toi-même) : `openssl verify -crl_check -CRLfile <CRL> -CAfile <racine> -untrusted <Services CA> <certificat>`.
- Les vérifications de ce palier lisent aussi la configuration de l'émetteur et de la CRL : ajoute à la politique `wb-checks` la lecture de `pki-services/issuer/+`, `pki-services/config/crl` et `pki-services/config/issuers` (configuration, aucune clé), par MR dans `plateforme/secrets`.

**Injection** : `lab/bin/break 25 41` (4 variantes). Certaines variantes forcent le renouvellement d'un certificat de la recette (`cmctl renew`) pour que la panne se voie tout de suite au lieu d'attendre l'échéance.

**Travail demandé**
1. **Où ça casse ?** `kubectl get certificates,certificaterequests -A | grep -E 'mtls|False'`, `kubectl describe` de la demande en échec ; journal du relais de MédiDoc (`kubectl -n medidoc-recette logs deploy/medidoc -c relais-tls --since=30m`) ; CRL publiée (`curl … | openssl crl -noout -lastupdate -nextupdate`). Classe le symptôme : la signature est **refusée**, le certificat est **émis mais inutilisable**, ou la **CRL** n'est plus valable.
2. **Lis les objets.** Le certificat en service (`kubectl get secret … -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -ext extendedKeyUsage,subjectAltName -dates`), le rôle (`bao read pki-services/roles/services-k8s`), l'émetteur (`bao read pki-services/issuer/services-2026`), la configuration de la CRL (`bao read pki-services/config/crl`). Compare avec `plateforme/secrets`.
3. **Reproduis à froid** : une CSR d'essai pour un nom de Service, signée par le rôle (`bao write pki-services/sign/services-k8s csr=@… ttl=48h`) ; lis l'erreur ou le certificat obtenu. Essaie aussi `ttl=100h` : refus ou réduction ?
4. **Corrige par le code** (pipeline de `plateforme/secrets`) ; puis fais réémettre ce qui doit l'être (`cmctl renew`), reconstruis la CRL si nécessaire, et vérifie de bout en bout : les deux `Certificate` `Ready`, un appel MédiAgenda → MédiDoc qui passe, le contrôle de Sophie qui répond `OK`.
5. **Préviens** : une alerte sur un certificat de service non prêt et une sur une CRL bientôt périmée (`nextUpdate`) ; dis dans ton journal laquelle des variantes **aucune** supervision ne pouvait voir avant l'échéance des certificats, et ce qui l'aurait vue.

**Critères de réussite**
- [ ] Le rôle `services-k8s` est conforme au code (domaines, client **et** serveur) ; l'émetteur par défaut a l'usage `issuing-certificates` ; la configuration de la CRL est celle du code et la CRL publiée n'est pas périmée.
- [ ] `medidoc-mtls` et `mediagenda-mtls` sont `Ready` ; deux alertes sont chargées (certificat de service non prêt, CRL bientôt périmée) ; ton journal (`INC-5241`) cite l'erreur exacte (OpenBao, ghostunnel ou `openssl verify`) et la cause.

**Vérification** : `lab/bin/check 25 41`

<details><summary>Indice 1</summary>

Une `CertificateRequest` en échec porte le message renvoyé par OpenBao dans sa condition `Ready` : lis-le en entier. Un certificat émis mais refusé par le relais se lit, lui, dans le journal de ghostunnel côté **serveur** (MédiDoc) : c'est le serveur qui vérifie le certificat du client.
</details>

<details><summary>Indice 2</summary>

`openssl x509 -noout -ext extendedKeyUsage` : un certificat client doit porter `TLS Web Client Authentication`. Dans un rôle PKI, les usages viennent des drapeaux `server_flag` et `client_flag`, pas de la CSR. Un émetteur a une liste d'**usages** (`read-only`, `issuing-certificates`, `crl-signing`, `ocsp-signing`) : sans `issuing-certificates`, il ne signe plus rien.
</details>

<details><summary>Indice 3</summary>

Une CRL a une date de **prochaine mise à jour** : passé ce moment, un client qui la vérifie la considère comme périmée et refuse. Qui la reconstruit chez nous, et à quel rythme ? Compare `expiry`, `auto_rebuild` et `auto_rebuild_grace_period` avec le code. `bao read pki-services/crl/rotate` la reconstruit tout de suite, mais ne corrige pas la cause.
</details>

**Pour aller plus loin** (facultatif) : active l'OCSP côté client sur un essai (`openssl ocsp -url …/v1/pki-services/ocsp`) et compare avec la CRL : fraîcheur, charge, ce qui se passe quand OpenBao ne répond pas (*fail-open* ou *fail-closed* ?). Lis la [documentation de la PKI](https://openbao.org/docs/secrets/pki/) sur les émetteurs multiples : comment prépareras-tu la succession de `services-2026` sans casser un seul certificat ?

---

### M25-E42 — Panne : l'auto-descellement échoue  `BF` `★★★`

> **Ticket INC-5242** — *De : Nadia Roussel* — priorité P2
> Un nœud du coffre a été redémarré (mise à jour du noyau) et il ne revient pas : l'alerte `OpenBaoScelle` est partie, autopilot annonce une tolérance aux pannes de zéro. Les deux autres nœuds servent toujours, mais si on en perd un de plus, le coffre s'arrête. `kms01` a l'air de répondre. Je veux le nœud de retour **sans** personne qui tape des parts, et l'explication. *(Le nœud concerné s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer un seal `transit` qui échoue, en séparant les quatre maillons : **réseau** (le nœud joint-il `kms01:8200` ?), **jeton** (valide, non révoqué, renouvelé ?), **politique** (encrypt **et** decrypt sur la bonne clé ?), **clé** (`min_decryption_version`).
- Lire ce que chaque maillon produit : processus qui s'arrête au démarrage (`Error configuring seal "transit"`) et `start-limit-hit` de systemd, ou processus vivant mais scellé, qui réessaie toutes les cinq secondes (`failed to unseal core`).
- Réparer sans clé de récupération ni jeton racine de la grappe, sans sceller `kms01`, un nœud à la fois.

**Prérequis** : M25-E25, M25-E27, M25-E28 (procédure `generate-root` de `kms01`) ; RB-251 ; `lab/bin/check 25 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique**
- Seal `transit` des nœuds : `https://kms01.par1.medisphere.internal:8200`, clé `autodescellement-par1`, montage `transit/`, jeton périodique orphelin (politique `kms-autodescellement`) dans `/etc/openbao/kms.env` (root, 600), lu par l'unité (surcharge `medisphere.conf`). Filtrage local des nœuds : rôle `pare_feu_local` (table `inet filtre_local`).
- Administrer `kms01` exige un jeton racine régénéré à trois dépositaires (procédure d'E28, jeton `generation-racine`), révoqué aussitôt après. Tu n'en as besoin que si la cause est sur `kms01`.
- Pour les variantes qui modifient la configuration de `kms01`, le script de panne a besoin d'un jeton d'administration de `kms01` dans la variable **`BAO_KMS_TOKEN`** (exportée dans ton shell, jamais en argument). Sans elle, il tire une variante qui ne touche pas à `kms01`.

> ⚠️ **Attention** : (1) ne redémarre **aucun autre** nœud tant que celui-ci n'est pas revenu : la grappe n'a plus de marge ; (2) ne scelle jamais `kms01` et ne le redémarre pas « pour voir » : il reviendrait scellé et la grappe entière dépendrait de trois dépositaires ; (3) ne touche ni aux clés de récupération ni à `/var/lib/openbao` ; (4) une rotation ou un réglage de la clé `autodescellement-par1` se décide en cérémonie : lis, ne modifie qu'en connaissance de cause.

**Injection** : facultativement `read -rs BAO_KMS_TOKEN && export BAO_KMS_TOKEN` (le jeton tapé ou collé n'apparaît ni à l'écran ni dans l'historique ; voir ci-dessus), puis `lab/bin/break 25 42` (4 variantes). Révoque ce jeton de `kms01` dès l'injection faite : l'annulation n'en a pas besoin.

**Travail demandé**
1. **État des lieux** sans rien toucher : `sys/health` et `sys/seal-status` des trois nœuds (sur leur adresse propre), `bao operator raft autopilot state`, `systemctl status openbao` et `journalctl -u openbao -b` du nœud en panne. Le processus tourne-t-il ? Depuis quand, combien de redémarrages ?
2. **Le réseau** depuis le nœud lui-même (pas depuis `adm01`) : `curl -s https://kms01.par1.medisphere.internal:8200/v1/sys/health`. Compare avec la même requête depuis un nœud sain. Si ça diffère : `sudo nft list ruleset` sur le nœud en panne.
3. **Le jeton** : sans l'afficher, vérifie que le jeton de `kms.env` du nœud en panne est le même que celui d'un nœud sain (empreinte `sha256sum` des deux fichiers), puis demande à `kms01` s'il existe encore (`auth/token/lookup-self` avec ce jeton, par un fichier d'en-tête, jamais en argument). Quand a-t-il été renouvelé pour la dernière fois ?
4. **La politique et la clé** (jeton racine de `kms01` régénéré si nécessaire) : `bao policy read kms-autodescellement`, `bao read transit/keys/autodescellement-par1` (versions, `min_decryption_version`). Rapproche de l'erreur exacte du journal (`403`, `disallowed by policy (too old)`, `connection refused`).
5. **Répare** à la source, par le canal qui porte l'objet en cause (rôle Ansible pour un nœud, fichier consigné et jeton racine régénéré pour `kms01`, cérémonie pour la clé), puis rétablis le nœud : selon la cause, il réessaie seul ou systemd doit être relancé ; explique pourquoi. Révoque le jeton racine de `kms01` si tu en as régénéré un.
6. **Préviens** : un essai **quotidien** de l'auto-descellement depuis chaque nœud (chiffrer puis déchiffrer une valeur témoin avec le jeton du nœud, jamais la clé racine), exposé en métrique et alerté, pour apprendre la panne **avant** le prochain redémarrage ; complète RB-251.

**Critères de réussite**
- [ ] Les trois nœuds sont descellés (seal `transit`), un seul actif ; autopilot est sain avec une tolérance d'au moins un ; `kms01` est descellé.
- [ ] Sur chaque nœud, `kms.env` est identique (empreinte) et en 600 ; aucune règle locale ne filtre la sortie vers `kms01:8200` ; l'unité n'est pas en échec.
- [ ] L'essai quotidien de l'auto-descellement tourne sur les trois nœuds et son résultat est collecté et alerté ; ton journal (`INC-5242`) cite la ligne d'erreur exacte et le maillon en cause.

**Vérification** : `lab/bin/check 25 42`

<details><summary>Indice 1</summary>

Deux familles de symptômes. Si le processus **s'arrête** au démarrage, l'erreur est au **chiffrement d'essai** que fait le seal en se configurant (`Error configuring seal "transit": … transit/encrypt/…`) : réseau ou jeton. Si le processus **tourne** mais reste scellé avec `failed to unseal core` toutes les cinq secondes, le seal s'est configuré mais le **déchiffrement** de la clé racine échoue : politique ou version de clé. Le second cas se répare souvent sans redémarrer.
</details>

<details><summary>Indice 2</summary>

`curl -s -o /dev/null -w '%{http_code}' -K <(printf 'header = "X-Vault-Token: %s"\n' "$(sudo sed -n 's/^BAO_TOKEN=//p' /etc/openbao/kms.env)") https://kms01…:8200/v1/auth/token/lookup-self` sur le nœud : 200 ou 403 ? Le jeton n'apparaît ni à l'écran ni dans `ps`. Sur `kms01`, `transit/keys/<clé>` donne `latest_version` et `min_decryption_version` : un texte chiffré `vault:v1:…` n'est plus déchiffrable si le minimum vaut 2.
</details>

<details><summary>Indice 3</summary>

`systemctl status openbao` affiche `start-limit-hit` : systemd a renoncé après `StartLimitBurst` essais. Une fois la cause corrigée, il faut lui dire de réessayer (`reset-failed`). Pour la politique : compare-la mot à mot avec le fichier versionné ; une politique peut aussi être **trop** restrictive pour le renouvellement du jeton lui-même (que fait le serveur pour garder son jeton vivant, et avec quel droit ?).
</details>

**Pour aller plus loin** (facultatif) : OpenBao 2.7 n'accepte qu'un seal actif (un second bloc ne sert qu'à une migration, voir la page [seal](https://openbao.org/docs/concepts/seal/)) ; lis la description du *Seal High Availability* de Vault Enterprise et chiffre ce qu'aurait apporté un second seal (un second `kms`, ou un seal `static` de secours gardé hors des nœuds) dans chacune des quatre variantes. Lequel des quatre maillons resterait un point unique ?

---

### M25-E43 — Astreinte : la nuit où le coffre s'est fermé  `BF` `★★★★`

> **Ticket INC-5243** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> Tu es d'astreinte. Nuit de vendredi à samedi, 2 h 10 : plusieurs alertes autour du coffre en quelques minutes (le détail s'affiche à l'injection). La CI de nuit, les ExternalSecret, MédiAgenda recette et prod : tout dépend d'OpenBao. À 7 h, les centres de santé ouvrent les rendez-vous ; d'ici là, je veux le coffre complet et les consommateurs rétablis, sans avoir réveillé trois dépositaires si on peut l'éviter, et sans avoir rien ouvert qu'on regrettera lundi.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur le composant **dont tout dépend** : trier ce qui menace la **disponibilité du coffre** (scellé, quorum, auto-descellement) de ce qui touche **un consommateur** (CI, ESO, base, PKI, politique).
- Ne pas aggraver : ni redémarrage en série, ni `kms01` scellé, ni politique élargie « pour débloquer », ni jeton racine qui traîne ; un nœud à la fois.
- Communiquer pendant l'incident, puis écrire le post-mortem et le runbook **RB-255 « coffre fermé »** (le coffre ne répond plus du tout : que faire, dans quel ordre, avec qui).

**Prérequis** : M25-E35 à M25-E42 (au moins une variante de chacun) ; RB-250, RB-251, RB-252.
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem et de runbook.

**Contexte technique** : le script tire **trois** pannes distinctes : **une** qui touche le coffre lui-même (parmi M25-E35, E39, E42) et **deux** qui touchent ses consommateurs (parmi M25-E36, E37, E38, E40, E41), chacune avec une variante au hasard. Les pannes des consommateurs sont posées d'abord, celle du coffre en dernier. `--variante N` force le trio (pas les variantes) ; `--annuler` retire tout. Si une variante a besoin de `BAO_KMS_TOKEN` (M25-E42) et qu'il est absent, une autre est tirée. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

> ⚠️ **Attention** : la tentation de la nuit, c'est « tout redémarrer » : un redémarrage de plus peut coûter le quorum ou laisser un nœud scellé faute d'auto-descellement. Avant toute action sur un nœud : un instantané récent existe-t-il (E26) ? Combien de nœuds peut-on perdre **maintenant** (`autopilot state`) ? Et ne contourne jamais une panne de consommateur en élargissant une politique ou un rôle (un `*` posé à 3 h du matin reste en production des mois).

**Injection** : `lab/bin/break 25 43` (compte 5 à 15 minutes d'injection : certaines pannes attendent une synchronisation d'Argo CD ou un renouvellement).

**Travail demandé**
1. **Triage (15 min au plus)** : liste les symptômes et leur impact. Première question : **le coffre répond-il** (par la VIP, puis nœud par nœud : `sys/health`, `sys/seal-status`, `raft list-peers`, `autopilot state`) ? Seconde : qui est bloqué, depuis quand, et que se passe-t-il dans une heure (baux PostgreSQL, certificats, jetons de CI) ? Envoie la première communication (modèle de RB-250).
2. **Rétablis d'abord le coffre** (quorum, descellement, nœud actif, VIP), puis les consommateurs, dans un ordre que tu justifies par l'échéance de chaque impact. Tiens ton journal horodaté ; garde les sorties qui prouvent chaque cause.
3. **Corrige à la racine et par le code** chaque cause (`plateforme/secrets`, `plateforme/ansible`, dépôts de déploiement) ; après chaque correction, rejoue le contrôle de l'exercice concerné (`lab/bin/check 25 <xx>`).
4. **Clôture** : communication de fin, `lab/bin/break 25 43 --annuler` pour clore, puis :
   - le post-mortem `docs/socle/post-mortems/AAAA-MM-JJ-INC-5243.md` (publié par MR), avec la chronologie, les causes, les extraits de diagnostic (sans aucun secret ni jeton), une section **Détection** (pour chaque cause : ce qui a sonné, ce qui aurait dû sonner) ;
   - **RB-255** `docs/securite/secrets/runbooks/RB-255-coffre-ferme.md` : le coffre ne répond plus (VIP, nœuds scellés, plus de leader, `kms01` injoignable ou scellé, audit bloquant) ; arbre de décision, ordre des gestes, qui appeler (dépositaires, astreinte), ce qu'on ne fait **jamais**, et ce que deviennent les consommateurs pendant ce temps (baux, certificats, ESO, CI).

**Critères de réussite**
- [ ] Les contrôles de M25-E35 à M25-E42 sont verts (le contrôle les rejoue) et aucune panne M25 n'est encore marquée active.
- [ ] Le post-mortem existe (chronologie, causes, extraits, section Détection) sans aucun secret ; RB-255 est sur `main` et couvre les cas listés.

**Vérification** : `lab/bin/check 25 43`

<details><summary>Indice 1</summary>

Ordre de confiance : les réponses brutes des nœuds (`curl https://vault0N…:8200/v1/sys/health`) et leurs journaux avant la VIP, la VIP avant les tableaux de bord. Un coffre qui répond par la VIP peut n'avoir qu'**un** nœud de marge, ou aucun ; c'est l'information la plus importante de la nuit.
</details>

<details><summary>Indice 2</summary>

Les échéances des consommateurs ne sont pas les mêmes : un bail PostgreSQL d'une heure, un certificat de service de 48 h, un ExternalSecret rafraîchi toutes les heures (et dont le Secret **reste** en place si le rafraîchissement échoue), un job de CI qui échoue tout de suite. Classe-les : ce qui casse à 3 h, ce qui casse à 7 h, ce qui peut attendre lundi.
</details>

**Pour aller plus loin** (facultatif) : chronomètre, à froid et sur le papier, le pire scénario de RB-255 : grappe arrêtée **et** `kms01` scellé un samedi à 3 h. Combien de dépositaires faut-il joindre, en combien de temps, et dans quel ordre de commandes ? Propose une mesure qui réduit ce délai sans affaiblir la garde des clés.

---

### M25-E44 — Sous le capot : barrière, trousseau, Raft et baux  `LAB` `★★★★`

> **Ticket PLAT-2644** — *De : Karim Benali*
> On dit « barrière », « clé racine », « trousseau », « Raft », « bail », « nœud en attente » comme des formules magiques. Je veux que tu ouvres le capot et que tu **montres**, sur notre grappe, en lecture autant que possible : ce qui chiffre quoi, ce qu'il y a vraiment sur le disque d'un nœud, ce que fait un nœud en attente d'une requête, ce qu'est un bail et qui le révoque. Une seule écriture : la rotation du trousseau, en cérémonie, parce qu'elle doit être faite un jour et qu'on veut savoir la faire. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Décrire la hiérarchie des clés d'OpenBao (seal → clé racine → trousseau → données) et la relier à ce qu'on observe : `sys/seal-status`, `sys/key-status` (terme, date d'installation, nombre de chiffrements), rotation automatique du trousseau (`sys/rotate/config`).
- Faire tourner le trousseau (`bao operator rotate`) en cérémonie, avec un jeton racine régénéré puis révoqué, et constater que rien ne s'interrompt ; distinguer cette rotation de celle de la clé racine et des clés de récupération (`bao operator rotate-keys`).
- Lire le stockage Raft d'un nœud : fichiers, structure des clés de stockage, ce qui est en clair (structure, identifiants de montages) et ce qui ne l'est pas (valeurs, noms des secrets KV v2, jetons) ; pairs, index, autopilot.
- Observer les baux (`sys/leases/lookup`, révocation par le gestionnaire d'expiration) et le comportement d'un nœud en attente : lecture servie localement, écriture **transmise** au nœud actif par le port de grappe, ou **redirection** (307) si on la demande.

**Prérequis** : M25-E09, M25-E14, M25-E24, M25-E25, M25-E26, M25-E28.
**Durée indicative** : 3 h.

**Contexte technique**
- Travaille sur `adm01` dans `~/m25/e44/` (700, sans secret). Compte rendu : `docs/securite/secrets/analyses/sous-le-capot-openbao.md` de `plateforme/medisphere`, par MR.
- `plateforme-admin` ne porte **pas** `sys/rotate` (qui exige `sudo`) : c'est voulu (commentaire de `plateforme-admin.hcl`). La rotation du trousseau se fait avec un jeton racine régénéré par la procédure d'E28 (trois clés de récupération), utilisé pour **cette seule** opération, puis révoqué.
- Les vérifications lisent `sys/key-status` : ajoute à `wb-checks` la lecture de ce chemin (métadonnées du trousseau, aucune clé) par MR.
- Données Raft d'un nœud : `/var/lib/openbao` (lisible par root seulement). Tu y lis **sans copier** (pas de fichier extrait du nœud) : `ls`, `strings` filtré, comptages.

> ⚠️ **Attention** : (1) tout est en **lecture**, sauf la rotation du trousseau ; ne lance ni `rotate-keys`, ni `rekey`, ni `raft remove-peer`, ni `step-down` hors de la mesure demandée au point 5 ; (2) sur un nœud, ne copie aucun fichier de `/var/lib/openbao` hors de la machine ni ailleurs sur son disque ; (3) le jeton racine régénéré est révoqué **dans la minute** qui suit la rotation, et la séance est consignée dans `docs/securite/secrets/procedure-jeton-racine.md`.

**Travail demandé**
1. **Les clés.** `bao status` (type de seal, seal de récupération), `bao read sys/key-status`, `bao read sys/rotate/config`. Que signifient `term`, `install_time`, `encryptions` ? Pourquoi une rotation **automatique** au-delà d'un certain nombre de chiffrements (rapproche le seuil de la limite d'usage d'une clé AES-GCM) ? Dessine la hiérarchie : `kms01` (clé `autodescellement-par1`) → clé racine → trousseau → données, et place les clés de récupération.
2. **La rotation du trousseau.** Régénère un jeton racine (procédure d'E28), lance `bao operator rotate`, relis `sys/key-status`, révoque le jeton. Pendant l'opération, une boucle de lecture et d'écriture (E24) tourne : a-t-elle vu quoi que ce soit ? Les données anciennes sont-elles réécrites ? Qu'est-ce qui, dans le **stockage**, porte le trousseau (cherche `core/keyring`) ?
3. **Le disque d'un nœud en attente.** `sudo ls -la /var/lib/openbao /var/lib/openbao/raft`, puis comptages : combien de clés de stockage commencent par `core/`, `sys/`, `logical/` (`sudo strings … | grep -c`) ? Le nom d'un de tes secrets KV (`mediagenda`), une valeur connue de toi, un accesseur, un jeton apparaissent-ils ? Qu'est-ce que `core/hsm/barrier-unseal-keys` ? Conclus sur ce qu'un voleur du disque (ou d'un instantané) apprend sans `kms01`.
4. **Raft.** `bao operator raft list-peers`, `bao operator raft autopilot state` (index appliqué par nœud, `last_contact`, `healthy`), `bao read sys/leader` (`raft_committed_index`, `raft_applied_index`). Que se passe-t-il pour un nœud dont l'index prend du retard ?
5. **Le nœud en attente.** Sur un nœud **en attente**, par son adresse propre : une lecture (`kv/metadata/…`), une écriture (`kv/wb-essais/…`), puis la même écriture avec l'en-tête `X-Vault-No-Request-Forwarding: true`. Codes HTTP, en-têtes (`Location`), journal du nœud. Qu'est-ce qui passe par le port 8201, et que se passerait-il pour un client si ce port était filtré entre deux nœuds ?
6. **Les baux.** `bao list sys/leases/lookup/db-mediagenda/creds/` et descends jusqu'à un bail : `ttl`, `expire_time`, renouvelable ou non ; rapproche du rôle PostgreSQL créé (M25-E14). Qui révoque le rôle PostgreSQL à l'échéance, et sur quel nœud tourne ce gestionnaire d'expiration ? Que devient un bail quand le nœud actif change ?
7. **Compte rendu** avec les sections `## Les clés`, `## La rotation du trousseau`, `## Le disque d'un nœud`, `## Raft`, `## Le nœud en attente`, `## Les baux`, `## Réponses aux questions` ; chiffres **relevés** (terme avant/après, comptages, index, codes HTTP) ; aucun secret, aucun jeton, aucun accesseur complet.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi deux niveaux (clé racine **et** trousseau) plutôt qu'une seule clé ? Qu'est-ce que chacun permet de faire tourner sans réécrire toutes les données ?
2. Rotation du trousseau, rotation de la clé racine, renouvellement des clés de récupération, rotation de la clé `autodescellement-par1` sur `kms01` : qu'est-ce que chacune protège, qui doit être présent, à quelle fréquence MédiSphère devrait-elle les faire ?
3. Avec le seal `transit`, où est la clé racine quand le nœud tourne, quand il est arrêté, dans un instantané ? Que faut-il **en plus** d'un instantané volé pour lire un secret ?
4. Pourquoi les noms des secrets KV v2 ne sont-ils pas lisibles dans le stockage, alors que la structure (`core/mounts`, `sys/token/…`) l'est ? Qu'est-ce qu'un attaquant peut quand même déduire ?
5. Un nœud en attente sert-il les lectures dans nos versions ? Qu'est-ce qui garantit qu'il ne sert pas une valeur périmée juste après une écriture (et dans quelle mesure) ?
6. Transmission (*forwarding*) contre redirection : avantages, exigences (port, TLS mutuel), comportement d'un client qui ne suit pas les redirections.
7. Un bail est-il le secret lui-même ? Que se passe-t-il si OpenBao ne peut pas joindre PostgreSQL au moment de révoquer ? Où le voit-on ?
8. Si tu devais prouver à un auditeur que les données d'un nœud volé sont illisibles, quelles trois preuves montrerais-tu, et quelle hypothèse resterait à défendre ?

**Critères de réussite**
- [ ] Le trousseau a tourné (terme supérieur à 1) ; la génération du jeton racine et la rotation sont tracées dans l'audit, et aucun jeton portant la politique `root` n'existe plus.
- [ ] Le compte rendu est sur `main` avec les sections demandées, les chiffres relevés (terme, comptages, index, codes HTTP), les huit questions traitées, et aucun secret.

**Vérification** : `lab/bin/check 25 44`

<details><summary>Indice 1</summary>

`bao operator key-status` et `bao operator rotate` sont les formes CLI de `sys/key-status` et `sys/rotate`. Le premier se lit avec un simple droit `read` ; le second exige `update` **et** `sudo`. La rotation installe un nouveau terme : les nouvelles écritures l'utilisent, les anciennes données restent chiffrées par les termes précédents, gardés dans le trousseau.
</details>

<details><summary>Indice 2</summary>

Le stockage Raft est un fichier BoltDB (`vault.db`) et un journal (`raft/raft.db`) : des clés en clair (des chemins de stockage) et des valeurs chiffrées par la barrière. Le moteur KV v2 n'utilise pas tes chemins comme clés de stockage, et les jetons sont rangés par empreinte salée. `sudo strings /var/lib/openbao/vault.db | grep -E '^.?(core|sys|logical)/' | cut -d/ -f1-2 | sort | uniq -c` donne une première carte.
</details>

<details><summary>Indice 3</summary>

`curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H 'X-Vault-No-Request-Forwarding: true' …` sur un nœud en attente. La [page sur la haute disponibilité](https://openbao.org/docs/concepts/ha/) décrit la transmission (par défaut) et la redirection (repli). Depuis la 2.5, OpenBao laisse les nœuds en attente servir certaines lectures (`disable_standby_reads` pour l'interdire) : lis la page sur la [cohérence](https://openbao.org/docs/concepts/consistency/).
</details>

**Pour aller plus loin** (facultatif) : sur un `bao server -dev` jetable de ton poste, refais le point 3 avec des données connues, puis lis un instantané Raft (E26) déchiffré **sur ton poste seulement** : `tar -tzf`, puis cherche les mêmes chemins de stockage. Compare avec ce qu'un instantané de PBS de la VM (E26) contiendrait de plus.

---

### M25-E45 — Questions expert : secrets  `Q` `★★★`

> **Ticket SEC-2645** — *De : Sophie Laurent*
> Avant la recette `secrets-v1`, l'auditeur HDS m'enverra ses questions sur les attaques contre un coffre et nos défenses. Je veux tes réponses écrites et argumentées, pour notre configuration. Pas de recherche à la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur. Pour chaque attaque, je veux : le mécanisme en deux phrases, la défense, et **la commande ou la preuve** qui montre que notre configuration l'applique.

**Objectifs pédagogiques**
- Raisonner en défenseur sur les menaces qui pèsent sur un coffre de secrets et ses clients : vol de jeton, rejeu, élévation par politique, prolifération des secrets, compromission d'un nœud, mémoire, sauvegardes, confusion d'audience, initié.
- Relier chaque menace à une défense **vérifiable** dans la configuration de MédiSphère, et nommer ce qui reste un risque résiduel.

**Prérequis** : paliers 1 à 3, M25-E44.
**Durée indicative** : 2 h 30.

**Questions**
1. **Jeton volé.** Un jeton OpenBao d'un job de CI apparaît dans un journal de job. Qu'est-ce qui borne ce que l'attaquant peut en faire (durée, politiques, liaisons, usage) ? Comment le retrouves-tu et le révoques-tu sans le connaître ? Quelle preuve montrerais-tu que nos jetons de CI sont courts et étroits ?
2. **Rejeu d'un jeton d'identité de CI.** Le JWT d'un job (`OPENBAO_ID_TOKEN`) est copié. Pourquoi ne vaut-il pas un jeton OpenBao ? Qu'est-ce qui limite sa réutilisation (expiration, `bound_audiences`, `bound_claims`, `ref_protected`) ? Quelle faiblesse resterait si un rôle `ci-*` n'exigeait pas `ref_protected = "true"` ?
3. **QCM — confusion d'audience.** Le rôle `k8s-par1` d'un espace accepte les jetons de compte de service **sans** contrainte d'audience. Quel est le risque principal ?
   a) aucun, le jeton est signé par l'API Kubernetes ; b) un jeton émis pour **un autre destinataire** (une application, un autre service qui le reçoit légitimement) peut être rejoué contre OpenBao ; c) le jeton expire trop vite ; d) ESO ne pourra plus se connecter. (Explique chacune.)
4. **Élévation par politique.** Donne trois façons dont une identité qui a un droit d'écriture **sur la configuration** du coffre peut s'élever (écrire une politique, s'ajouter à un groupe, créer un rôle de méthode lié à une identité qu'elle contrôle, créer un jeton enfant…). Quels chemins `plateforme-admin` ne doit-il jamais avoir pour que cette élévation reste visible et bornée ? Comment l'audit et l'alerte `OpenBaoPolitiqueModifiee` ferment-ils la boucle ?
5. **QCM — `deny`.** Une politique `gel` contient `path "kv/data/mediagenda/*" { capabilities = ["deny"] }` ; `mediagenda-dev` contient `path "kv/data/mediagenda/dev/*"` en lecture et écriture. Un jeton porte les deux. Julien peut-il lire `kv/data/mediagenda/dev/valkey` ?
   a) non, `deny` l'emporte toujours ; b) oui, la règle au motif le plus précis s'applique seule ; c) non, les deux politiques s'annulent ; d) cela dépend de l'ordre des politiques sur le jeton. (Explique, et dis comment écrire un vrai gel.)
6. ***Secret sprawl*** (prolifération). Le coffre est en place, mais des copies des secrets vivent encore ailleurs. Cite cinq endroits où un secret de MédiSphère peut se retrouver **en dehors** d'OpenBao malgré tout (Secret Kubernetes, variables de CI, `.env` local, historique de shell, sauvegardes, journaux…) et la défense pour chacun. Pourquoi les identifiants **dynamiques** changent-ils la nature du problème ?
7. **Attaque d'un nœud.** Un attaquant obtient root sur `vault02` (nœud en attente). Que peut-il obtenir : immédiatement, en lisant le disque, en lisant la mémoire du processus, en attendant que le nœud devienne actif ? Quelles défenses de notre configuration jouent (seal `transit`, unité durcie, `LimitCORE=0`, `MemorySwapMax=0`, TLS, audit, pare-feu local), et lesquelles ne peuvent rien contre root ?
8. **Extraction mémoire.** Pourquoi la clé racine et le trousseau sont-ils forcément en mémoire d'un nœud descellé ? Quels mécanismes réduisent l'exposition (pas d'échange, pas de vidage mémoire, `ProtectProc`, `PrivateDevices`, hyperviseur maîtrisé) et quelle attaque reste hors de portée de toute configuration logicielle ? Que changerait un HSM (seal PKCS#11) ?
9. **Sauvegarde volée.** Un instantané Raft chiffré `age` est dérobé dans `s3-01`. Que faut-il en plus pour en tirer un secret (clé `age`, `kms01` et son jeton, ou les clés de récupération) ? Et une sauvegarde PBS de `vault01` **et** de `kms01` volées ensemble ? Quelle séparation de pouvoirs protège MédiSphère, et où est-elle écrite ?
10. **Le jeton du seal.** Le jeton de `kms.env` fuit. Que peut faire son détenteur (et que ne peut-il pas faire) ? Quel droit **en plus** de `encrypt`/`decrypt` lui faut-il pour rester vivant, et pourquoi ce détail est-il un risque de disponibilité plutôt que de confidentialité ?
11. **Initié malveillant.** Un administrateur de la plateforme veut lire en cachette `kv/data/mediagenda/prod/*`. Décris ce qui l'en empêche, ce qui le **trace** s'il y parvient par un détour (politique modifiée, `generate-root`, accès au nœud), et ce qui manque encore à MédiSphère (contrôle à deux personnes, *Control Groups*, séparation des rôles, revue des accès).
12. **QCM — audit.** Le dispositif d'audit unique ne peut plus écrire (disque plein). OpenBao :
    a) continue et perd les traces ; b) refuse les requêtes (erreur 500) tant qu'aucun dispositif n'écrit ; c) bascule automatiquement sur syslog ; d) se scelle. (Explique, et dis ce que cela implique pour la disponibilité et pour un attaquant qui voudrait agir sans trace.)
13. **Rotation sous menace.** Une clé de transit (`sops-plateforme`) est soupçonnée exposée **en tant que clé** (pas une donnée). Pourquoi `rotate` puis `rewrap` ne suffisent-ils pas tant que `min_decryption_version` n'est pas relevée, et quel est le coût de ce relèvement ? Comparer avec la panne M25-E42 (même réglage, autre clé).
14. **Phishing de l'OIDC.** Un attaquant envoie à Julien un lien de connexion OpenBao qui renvoie vers une adresse de rappel qu'il contrôle. Qu'est-ce qui l'en empêche dans notre configuration (`allowed_redirect_uris`, client Keycloak, PKCE, OTP pour les administrateurs) ? Que ne protège pas l'OTP ?
15. **Défense en profondeur.** Classe les défenses du module en trois colonnes : **empêcher** (politiques, liaisons, TLS…), **limiter** (durées, dynamiques, enveloppement…), **détecter et prouver** (audit, alertes, essais). Quelle colonne est la plus faible chez MédiSphère, et quelle mesure du M26 ou d'un final la renforcera ?

**Critères de réussite**
- [ ] Les 15 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses), chacune avec la commande ou la preuve qui vérifie la défense sur notre configuration.
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 5 : tes politiques (`plateforme/secrets/politiques/`), les rôles JWT (`ci-*`) et Kubernetes (`eso-*`), la documentation des [jetons](https://openbao.org/docs/concepts/tokens/), des [politiques](https://openbao.org/docs/concepts/policies/), de la méthode [JWT/OIDC](https://openbao.org/docs/auth/jwt/) et [Kubernetes](https://openbao.org/docs/auth/kubernetes/) ; ton travail de M25-E05, E10, E12, E22, E40.
</details>

<details><summary>Indice 2</summary>

Pour 6 à 15 : RB-250 (fuite), ADR-0250 (coffre, seal, sauvegarde), M25-E21 (audit), E25-E28 (seal, instantanés, durcissement), E44 (sous le capot) ; le modèle de menace d'OpenBao dans la [documentation de sécurité](https://openbao.org/docs/internals/security/) et l'*OWASP Secrets Management Cheat Sheet*.
</details>

**Pour aller plus loin** (facultatif) : choisis trois questions et transforme chacune en **preuve reproductible** pour l'auditeur (une commande en lecture, sa sortie attendue, ce qu'elle démontre), à ranger dans `docs/securite/secrets/preuves-audit.md`.
