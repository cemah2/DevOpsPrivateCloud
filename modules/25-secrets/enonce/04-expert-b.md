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
- [ ] Le test des politiques tourne dans la CI de `plateforme/secrets` ; ton journal de diagnostic (un fichier dont le nom contient `INC-5240`, dans le dossier des journaux du palier) cite le refus exact (ligne d'audit résumée, sans valeur) et la cause.

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
5. **Répare** à la source et rétablis le nœud : configuration du pare-feu local rejouée par Ansible, jeton remis par le rôle (`vault_openbao_kms_jeton`), politique de `kms01` rétablie à l'identique de `kms01/kms-autodescellement.hcl`, ou `min_decryption_version` ramenée à la version qui a chiffré la clé racine ; puis, selon le cas, rien (il réessaie seul) ou `systemctl reset-failed openbao && systemctl start openbao`. Révoque le jeton racine de `kms01`.
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

**Pour aller plus loin** (facultatif) : lis la page [*Seal High Availability*](https://openbao.org/docs/concepts/seal/) et chiffre ce qu'aurait apporté un second seal (un second `kms`, ou un seal `static` de secours gardé hors des nœuds) dans chacune des quatre variantes. Lequel des quatre maillons resterait un point unique ?

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
   - le post-mortem `AAAA-MM-JJ-INC-5243.md` dans le dossier des post-mortems du palier (publié par MR), avec la chronologie, les causes, les extraits de diagnostic (sans aucun secret ni jeton), une section **Détection** (pour chaque cause : ce qui a sonné, ce qui aurait dû sonner) ;
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
