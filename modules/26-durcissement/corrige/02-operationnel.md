# Module 26 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `…/ansible/…` = `plateforme/ansible`, `…/politiques/…` = `plateforme/politiques`, `…/gitops/…` = `plateforme/gitops`, `…/infra/…` = `plateforme/infra`, `…/ci-templates/…` = `plateforme/ci-templates`, `…/medisphere/…` = la documentation (`plateforme/medisphere`), `…/essais/` = `~/m26/eXX/`. Le **rôle `durcissement` complet** (tous les domaines, dans leur état de fin d'E13) est dans [`fichiers/M26-E10/ansible/roles/durcissement/`](fichiers/M26-E10/ansible/roles/durcissement/) : E10 en écrit le squelette et les domaines sans effet sur l'accès, E11 à E13 complètent les autres fichiers de tâches ; les dossiers `M26-E11` à `M26-E14` ne contiennent que ce qui s'ajoute **à côté** du rôle (variables d'inventaire, extension du rôle `alloy`, documentation). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Rôle `durcissement`* : `ansible-lint` 26.10 (profil `production`, 0 défaut) sur le rôle et les deux playbooks, `ansible-playbook --syntax-check` ; **exécuté** (ansible-core 2.21.5) sur deux conteneurs systemd privilégiés **Debian 13** et **Rocky Linux 10** (images officielles), domaines `paquets`, `systemd`, `journalisation`, `montages`, `comptes`, `pam`, `sudo`, `ssh`, `aide`, `conformite` : premier passage puis second passage à `changed=0` (idempotence) ; garde-fous essayés (exception sans valideur, exception échue, hôte qui route sans exception : refus) ; domaines `noyau`, `auditd`, `mac` en `--check --diff` seulement (un conteneur partage le noyau de l'hôte : charger des paramètres, des règles d'audit ou des profils AppArmor aurait modifié la machine d'essai elle-même).
- *Ce que ces essais ont montré et qui est dans le corrigé* : Rocky 10 n'a plus de module `NO-SHA1` (DEFAULT refuse déjà SHA-1) ; le flux de données de Rocky est bien `ssg-rl10-ds.xml` (paquet `scap-security-guide-0.1.82-2.el10_2.rocky`) ; `oscap` 1.4.4 **exige** l'attribut `time` de `version` dans un profil adapté, et `oscap info` ne le détecte pas ; Rocky livre `/etc/systemd/system/ctrl-alt-del.target` (lien vers `reboot.target`) qui empêche de masquer l'unité ; `sshd -T` affiche une ligne par groupe d'`AllowGroups` ; `faillock.conf` propose `local_users_only` ; `faillock` verrouille puis `faillock --reset` débloque (essai avec `pamtester`) ; la pile PAM générée par `pam-auth-update` et par `authselect` (fonctions `with-faillock`, `with-pwhistory`) ; la vérification AIDE et le script de nouvelle base (base dans `/var/lib/aide` à exclure, sinon chaque nouvelle base est un écart) ; profils adaptés CIS et ANSSI évalués par `oscap` sur les deux familles (scores rendus par `conformite-mesure.yml`).
- *SSH* : `sshd -t` d'OpenSSH 10.0 (Debian) et 9.9 (Rocky) sur les fichiers produits ; **ssh-audit 3.9** contre les deux conteneurs après durcissement : plus aucun `fail`, seulement des `warn` « non post-quantique » ; politiques `-M` créées, relues, et vérifiées par `-P` (chacune passe sur sa famille, échoue sur l'autre) ; pénalités `PerSourcePenalties` d'OpenSSH rencontrées (« Not allowed at this time »).
- *Profil AppArmor de Mailpit* : analysé par `apparmor_parser` 4.1.0 (Debian 13) en mode *complain* et *enforce* ; **pas** chargé dans un noyau ni confronté à Mailpit.
- *Kyverno* : toutes les politiques validées contre les schémas `v1` des CRD du chart 3.9.2 ; `kyverno test` (CLI **1.19.2**) au vert sur les cinq dossiers de tests d'E16 (20 cas), et rouge quand on casse une attente ; **`ImageValidatingPolicy` éprouvée avec Cosign 3.1.4** : images poussées dans un registre OCI 1.1 local (zot, API *Referrers*, TLS), signées par configuration de signature sans service (*bundle* `application/vnd.dev.sigstore.bundle.v0.3+json` en référent, aucune entrée de journal) et attestées (`spdxjson`) ; `kyverno apply` 1.19.2 : image signée et attestée **admise**, image non signée **refusée**, image signée par une autre clé **refusée** (ou admise pour la signature si cette clé est un second attesteur, puis refusée faute de SBOM), image par étiquette **refusée** (« does not have a digest »), conteneur d'initialisation non signé **refusé**, Deployment refusé (autogénération), espace non visé **ignoré**. Le point « *bundles* Cosign 3 et référents OCI » laissé ouvert par `annexes/versions-bloc-F.md` est donc **vérifié** pour la CLI ; reste à le confirmer dans le contrôleur d'admission contre Harbor.
- *E17* (vérifié hors lab) : les trois fichiers appliqués à un vrai kube-apiserver **1.36.5** (etcd 3.6) : refus `hostPath` dans un espace absent de la ConfigMap et pour un chemin hors liste, `/procfoo` refusé quand `/proc` est permis, `..` refusé par la validation de l'API ; DaemonSet rendus des charts Falco 9.2.1 (`modern_ebpf`), Tetragon 1.7.1 et ceph-csi 3.18.1 **acceptés** avec la ConfigMap du corrigé ; MAP : étiquette ajoutée, valeur existante conservée, rien hors des espaces d'équipe ; VAP d'étiquettes d'espace : refus par emprunt d'identité `oidc:lucas.martin`, passage pour `oidc:plateforme-admins`. Check E17 rejoué contre ce serveur (vert, puis rouge avec un pod `hostPath` posé avant la liaison).
- *E18* (vérifié hors lab) : chart Kyverno 3.9.2 rendu (`features.policyExceptions` → `--enablePolicyException=true --exceptionNamespace=kyverno-exceptions` sur les contrôleurs d'admission, de fond et de rapports ; désactivé par défaut) ; `PolicyException` et `exiger-digest` modifiée acceptées par un kube-apiserver 1.36.5 avec les CRD du chart (`policies.kyverno.io/v1` servie) ; `kyverno test` 1.19.2 vert sur `tests/exiger-digest-exception/` (et `kyverno apply` : 3 échecs sans l'exception, 1 succès et 2 échecs avec) ; code source de Kyverno 1.19.2 lu pour la sémantique (exception partielle par `images` pour les `ValidatingPolicy`, **ignorée** pour les `ImageValidatingPolicy` depuis la 1.19.1 ; échéance évaluée à la lecture des exceptions, donc à la recompilation de la politique ; espace de lecture) ; `verifier-exceptions.sh` exécuté sous `dash` (vert, puis cinq erreurs provoquées) ; règles `promtool check rules` et `promtool test rules` (Prometheus 3.15.1) ; 8 expressions du tableau validées par `promtool`. Image de l'opérateur dans `bootstrap-controller` confirmée dans le code de CloudNativePG 1.30.1 (`OperatorImageName`).
- *E19* (vérifié hors lab) : règles validées par le binaire **Falco 0.45.1** (`falco -V` des règles par défaut puis des nôtres, greffon `container` chargé par `-o 'load_plugins[]=container'`) ; configuration avec `append_output` validée par le schéma de Falco ; `valider-falco.sh` exécuté sous `dash` avec yq 4.54.1 (vert ; rouge sur une règle sans gravité, désactivée ou mal nommée) ; chart falco 9.2.1 rendu avec les valeurs et les règles (ConfigMap `falco-rules`, annotation `checksum/rules`, variables de falcosidekick) ; DaemonSet rendu accepté par la VAP `hostPath` d'E17 ; routage d'Alertmanager rejoué par `amtool` 0.34.1 ; code de falcosidekick 2.31.1 lu (étiquettes = champs de sortie, `extralabels` appliquées **après**, sortie Loki).
- *E20* (vérifié hors lab) : chart Tetragon 1.7.1 rendu avec les valeurs (images par le cache `quay`, `export-allowlist` et `export-denylist` dans la configuration, ServiceMonitor) ; DaemonSet accepté par la VAP `hostPath` d'E17 ; trois `TracingPolicy` acceptées par un kube-apiserver 1.36.5 avec les CRD du chart ; types d'arguments, opérateurs et format de `rateLimit` relus dans le code de Tetragon 1.7.1 ; résolution des chemins par rapport à la racine **du processus** (`fs->root`) relue dans le programme eBPF ; noms des champs JSON (`process_kprobe`, `policy_name`, `linux_binprm_arg`, `file_arg`, `sock_arg`, `namespace_regex`, `policy_names`) relus dans l'API 1.7.1 ; options de `tetra getevents` relues.
- *E21* (vérifié hors lab) : `audit-charges-sures.sh` exécuté contre un kube-apiserver 1.36.5 (pods conformes : aucun écart ; pod non conforme : quinze écarts attendus, dont C6 détecté par le volume projeté injecté par l'admission) ; chart `mediagenda` du M17 rendu avec les gabarits modifiés (`runAsUser`, `appArmorProfile`) et accepté en `restricted` ; gabarit d'image du sous-chart `valkey` 0.12.0 relu (condensé dans `image.tag` accepté) ; code de MédiDoc relu (`r.MultipartReader()`, pas de fichier temporaire).
- *E22* (vérifié hors lab) : manifestes de Lucas valides (`kubectl apply --dry-run=client`) ; version corrigée acceptée à blanc par un kube-apiserver 1.36.5 dans un espace `restricted` ; check E22 vert sur la version corrigée, neuf contrôles rouges sur les fichiers de Lucas.
- **Non rejoués sur le lab réel** (signalés « ⚠️ À vérifier sur ton lab ») : le rôle sur de vraies VMs (noyau, auditd chargé, AppArmor chargé, SELinux en *enforcing*, SSSD et HBAC du M24, certificats step-ca) ; le type de clé de la CA SSH de step-ca ; l'extension du rôle `alloy` (`local.file_match`, `loki.source.file` et son attribut `tail_from_end` : à confronter à la documentation d'Alloy 1.21) ; le refus SELinux de l'étape 6 d'E13 ; le playbook des vagues (`drain`, `noout`, délégations) ; Kyverno dans le cluster (webhook, `credentials.secrets`, droits du robot Harbor sur l'API *Referrers*, `caCertificates`) ; le gabarit de l'`ExternalSecret` ; les rapports `PolicyReport` produits en arrière-plan par une `ImageValidatingPolicy`. **E17 à E22** — *E17* : chemins `hostPath` exacts de node-exporter (kube-prometheus-stack), Alloy et Velero sur **ton** cluster (relevés à l'étape 1, à reprendre) ; rapports de Kyverno sur les VAP (droits de lecture de la ConfigMap de paramètres par Kyverno). *E18* : délai réel entre `expiresAt` et l'arrêt de l'exemption dans le contrôleur (recompilation) ; noms exacts des métriques exportées (suffixe `_total` ajouté par l'exportateur OpenTelemetry : vérifie sur `/metrics` du contrôleur) ; contenu des rapports pour un objet exempté (`skip`). *E19* : déclenchement effectif de chaque règle sur `k8s-par1` (aucun pilote dans le bac à sable) ; champ `extra_fields` à valeur fixe (`gravite: "critique"`) transmis à falcosidekick ; port vu par Falco avec le remplacement de kube-proxy (8000 attendu, pas 80) ; présence de `/etc/falco/falco_rules.yaml` et du greffon dans l'image `falcosecurity/falco:0.45.1` utilisée par la CI. *E20* : chargement des sondes sur le noyau 6.12 des nœuds, coût mesuré, déclenchements ; volume réel après filtrage ; requêtes LogQL sur de vrais événements. *E21* : écarts réels de tes espaces ; mise à jour progressive des instances CNPG au changement d'`imageName` ; UID réel des images de bibliothèque. *E22* : `ExternalSecret` (CRD d'ESO absente du serveur d'essai) et `CiliumNetworkPolicy` (CRD de Cilium absente) ; l'application elle-même (`app/` n'existe pas : c'est un exercice de revue).

**Où lancer les commandes.** `admin@adm01:~/src/ansible$` (projet Ansible, `uv run`), `admin@adm01:~/src/politiques$`, `~/src/infra$`, `~/medisphere$` dans les copies des projets ; `admin@durci-deb:~$`, `[admin@durci-rocky ~]$`, `admin@mon01:~$` sur les hôtes ; `admin@adm01:~$` avec ton kubeconfig personnel (OIDC, M24) pour le cluster. Toute modification passe par une MR relue ; Argo CD synchronise `politiques` (`argocd app get politiques --refresh` pour ne pas attendre).

---

### M26-E10 — Le rôle Ansible `durcissement` sur les VMs d'essai

**Solution**

Fichiers : rôle [`durcissement`](fichiers/M26-E10/ansible/roles/durcissement/) (`defaults/main.yml`, `meta/`, `handlers/main.yml`, `tasks/*.yml`, `templates/`, `files/crypto-policies/`), [playbook des vagues](fichiers/M26-E10/ansible/playbooks/durcissement.yml), [playbook de mesure](fichiers/M26-E10/ansible/playbooks/conformite-mesure.yml), [vagues](fichiers/M26-E10/ansible/inventories/lab/durcissement.yml), [`ansible.cfg`](fichiers/M26-E10/ansible/ansible.cfg.extrait), [exceptions du parc](fichiers/M26-E10/ansible/inventories/lab/group_vars/all/durcissement.yml), groupes SSH en plus (`group_vars/role_gitlab`, `role_ceph`, `role_routeur`, `role_lb`, utilisés en E11).

1. **Conception** (extrait de `~/m26/e10/conception.md`) :

   | Domaine | Règle | Ne doit pas casser |
   |---|---|---|
   | `paquets` | paquets interdits absents, requis présents | rien (aucun paquet du lab n'est dans la liste) |
   | `noyau` | `sysctl.d`, modules interdits | routage (bordure, Cilium, Docker), Cilium (`rp_filter`), Falco/Tetragon (BPF : ils sont privilégiés, `unprivileged_bpf_disabled` ne les gêne pas) |
   | `systemd` | services inutiles masqués, vidages mémoire, Ctrl-Alt-Suppr | services du lab (aucun n'est dans la liste) |
   | `journalisation` | journald persistant, compressé | taille fixée par le rôle `base` (M04) |
   | `montages` | `/tmp`, `/dev/shm` sans exécution | sockets et fichiers vivants dans `/tmp` ; outils qui exécutent depuis `/tmp` |
   | `comptes` | durées, masque, délai d'inactivité, `su` | comptes du rôle `base` (aucun créé ni supprimé) |
   | `pam` | faillock, pwquality, pwhistory | SSSD (M24), console de secours |
   | `sudo` | `use_pty`, journal, réauthentification | sudo d'Ansible (`NOPASSWD` de `admin`), règles sudo de l'annuaire |
   | `ssh` | AllowGroups, algorithmes, bannière | `ssh_durci` (M04), certificats (M06), comptes `git`, `cephadm`, `supervision` |
   | `auditd`, `aide` | trace, intégrité | disque (volume), performances |
   | `mac` | AppArmor, SELinux | services confinés |
   | `conformite` | contenu SCAP, profils adaptés | rien (lecture) |

   Ordre : ce qui ne touche pas l'accès d'abord, **l'accès ensuite** (`comptes`, `pam`, `sudo`, `ssh`), la trace et le confinement après (un refus d'AppArmor ne doit pas empêcher de se reconnecter pour le corriger), la conformité en dernier (elle décrit l'état final).

2. **Squelette.** `tasks/main.yml` **importe** les fichiers de domaine (`ansible.builtin.import_tasks`, étiquette du domaine, condition `'<domaine>' in durcissement_domaines`). Avec un import, chaque tâche garde ses étiquettes : `--tags sysctl_kernel_kptr_restrict` exécute exactement la tâche concernée, `--list-tasks` montre tout le rôle. Avec `include_tasks`, l'inclusion n'aurait lieu que si **elle** portait l'étiquette demandée. Gestionnaires : rechargements seulement (`sysctl -p`, `augenrules --load`, `pkill -HUP -x auditd`, `systemctl reload ssh|sshd`, `apparmor_parser --replace`), jamais un redémarrage de sshd. `meta/argument_specs.yml` documente et contrôle les variables principales à l'entrée du rôle.

3. **Exceptions** (`tasks/main.yml`, toujours exécutées : étiquette `always`). Trois contrôles bloquants (champs complets, valideur dans `durcissement_valideurs`, date de revue non dépassée), puis la liste des exceptions de l'hôte : `hotes` accepte un nom d'hôte, un **nom de groupe d'inventaire** (`role_routeur`, `k8s_par1`) ou `all`. Chaque mesure concernée a `when: "'<règle>' not in _durcissement_exclues"`, et les gabarits (sysctl, modules, sudo, SSH) écrivent en commentaire ce qui n'est pas appliqué et pourquoi. Essai demandé :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 --limit durci-deb --check \
       -e '{"durcissement_exceptions":[{"regle":"sysctl_kernel_kptr_restrict","hotes":["all"],"justification":"Essai de refus du rôle","valideur":"lucas.martin","revue":"2027-01-01"}]}'
   failed: [durci-deb] (item=sysctl_kernel_kptr_restrict) => … "Exception incomplète ou non signée … valideur (sophie.laurent) …"
   ```
   Même essai avec `valideur: sophie.laurent` et `revue: "2026-01-01"` : « devait être revue le 2026-01-01 ».

4. **Domaines d'E10** (lire les fichiers ; points de conception) :
   - `noyau.yml` : un **garde-fou de routage** lit `net.ipv4.ip_forward` en direct ; si l'hôte route et que les **trois** règles de routage (`sysctl_net_ipv4_ip_forward`, `…_conf_all_forwarding`, `…_conf_default_forwarding`) ne sont pas en exception, le rôle s'arrête avant de poser quoi que ce soit (sauf `durcissement_couper_routage: true`, décision explicite). Les trois sont un seul réglage : une exception partielle couperait quand même le routage, d'où le contrôle « toutes ou aucune ». Le gabarit `sysctl-durcissement.conf.j2` écrit une ligne par règle (identifiant en commentaire) ; `rp_filter` en exception passe à 2 (lâche) plutôt que rien. Les modules interdits sont rendus non chargeables (`install … /bin/false` **et** `blacklist`) ; un module déjà chargé est signalé (il reste en mémoire jusqu'au redémarrage).
   - `montages.yml` : `/tmp` devient un tmpfs par une **surcharge** de `tmp.mount` (`/etc/systemd/system/tmp.mount.d/60-durcissement.conf`) ; si `/tmp` est déjà un tmpfs, les options manquantes sont appliquées à chaud (`mount -o remount`, qui ne masque rien) ; sinon le rôle **signale** que le changement attendra le prochain redémarrage : monter un tmpfs vide par-dessus un `/tmp` vivant ferait disparaître les sockets et fichiers des services. `/dev/shm` : ligne `fstab` et remontage si une option manque.
   - `systemd.yml` : services masqués **s'ils existent** (`service_facts`) ; sur Rocky, le lien `/etc/systemd/system/ctrl-alt-del.target → reboot.target` est retiré avant le masquage (sinon `systemctl mask` refuse : « already exists and is a symlink »).
   - `conformite.yml` : Debian, archive amont **vérifiée par empreinte** (`get_url … checksum: sha256:765e84bd…919c`, empreinte calculée après contrôle du `.sha512` publié avec la version), seul le flux `ssg-debian13-ds.xml` (13 Mo) est extrait (`unarchive`, `include`, `-j`), l'archive (183 Mo) est supprimée ; Rocky, le paquet `scap-security-guide` d'AppStream et son flux `ssg-rl10-ds.xml` (le flux RHEL 10 de l'archive amont vérifie la plateforme RHEL : sur Rocky, ses règles seraient « non applicables »). Les **profils adaptés** (`tailoring-cis.xml`, `tailoring-anssi.xml`) déclarent un profil `…_medisphere` qui étend le profil d'origine et désélectionne les exceptions de l'hôte ; seules les règles **présentes dans le flux de l'hôte** sont désélectionnées (le rôle lit les identifiants du flux) : `service_ufw_enabled` n'existe que pour Debian, une exception « all » ne doit pas casser l'évaluation sur Rocky. La version du profil adapté est l'empreinte des exceptions et son `time` la plus lointaine date de revue : le fichier ne change que si les exceptions changent (idempotence). Le chargement est **prouvé** par l'évaluation d'une seule règle bon marché (`--rule …package_sudo_installed` : code 0 ou 2, jamais 1). `exceptions.json` garde la trace machine des exceptions de l'hôte (lue par la mesure, puis par l'analyse hebdomadaire d'E24).

5. **Exceptions initiales** : voir [`group_vars/all/durcissement.yml`](fichiers/M26-E10/ansible/inventories/lab/group_vars/all/durcissement.yml) — routage (`role_routeur`, `k8s_par1`, `runner02`, `reg01`), `rp_filter` (bordure, nœuds K8s), `service_ufw_enabled` (nftables du rôle `pare_feu_local`), services rendus par l'hôte (`service_kea_dhcp4_server_disabled` sur `dns01`/`dns02`, `service_nginx_disabled` sur `nbx01`, `service_dnsmasq_disabled` sur la bordure, `package_httpd_removed` sur `ipa01`, propre à Rocky), `sshd_set_loglevel_info` (VERBOSE du M04, propre au profil Debian), `audit_rules_immutable`. Chaque justification tient en une phrase ; la compensation et le risque résiduel vont dans le registre lisible (E23).

6. **Mesure.** [`conformite-mesure.yml`](fichiers/M26-E10/ansible/playbooks/conformite-mesure.yml) lit `exceptions.json` (flux de l'hôte), évalue les deux profils adaptés (`--results-arf`, `--report`), lit le score (`urn:xccdf:scoring:default`), rapatrie les quatre fichiers dans `~/m26/conformite/<hôte>/` (jamais dans Git) et nettoie l'hôte.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conformite-mesure.yml -e vague=0 -e moment=avant
   "msg": "durci-deb (avant) — CIS : <score> ; ANSSI intermédiaire : <score> ; exceptions : 3"
   ```

7. **Application.** `--check --diff` d'abord (le diff du fichier `sysctl.d` et des surcharges se relit en deux minutes), puis application, puis **second passage** : `changed=0` sur les deux VMs. Si le rôle a signalé « /tmp n'est pas un tmpfs » (cas observé sur l'image Rocky : `/tmp` sur la partition racine), redémarre la VM : `tmp.mount` est activé, `/tmp` devient un tmpfs `noexec` au démarrage (`ssh durci-rocky findmnt /tmp`). Scores après (essai sur conteneurs, à titre d'ordre de grandeur : un conteneur rend une partie des règles « non applicables », les scores de tes VMs seront plus bas avant et différents après) : la progression vient surtout des domaines `noyau`, `montages` et des paquets ; les cinq premières règles en échec restantes sont typiquement celles des domaines d'E11 et E12 (SSH, PAM, sudo, audit) — elles disparaissent aux exercices suivants. ⚠️ À vérifier sur ton lab : les scores réels.

8. **Molecule : non pour ce rôle, oui pour sa syntaxe.** Molecule (M04-E24) crée une instance jetable et rejoue le rôle deux fois : excellent pour l'idempotence d'un rôle applicatif. Ici, la moitié des domaines **touchent le noyau** (sysctl, modules, audit, LSM) et l'**accès** (PAM avec SSSD, sshd avec les certificats de step-ca, HBAC) : un conteneur partage le noyau de l'hôte (essais impossibles ou dangereux), et une instance Molecule n'a ni l'annuaire, ni les certificats, ni les comptes du socle. Ce qui remplace Molecule : `ansible-lint` en CI, `--check --diff` relu, **la vague 0** (deux VMs réelles des deux familles, recréables en cinq minutes par OpenTofu) qui rejoue chaque changement du rôle **deux fois** (idempotence), et la mesure OpenSCAP avant/après. On peut garder un scénario Molecule pour les domaines « sans noyau » (`comptes`, `sudo`, `conformite`) si l'équipe y tient : c'est un plus, pas la preuve.

**Explications**

Un rôle de durcissement n'est pas une liste de commandes : c'est la **traduction d'un référentiel** en mesures, chacune traçable jusqu'à sa règle. Les étiquettes XCCDF font le lien dans les deux sens : du rapport OpenSCAP (« règle X en échec ») vers la tâche (`--tags X`), et de l'exception vers le profil adapté (« règle X désélectionnée sur ces hôtes »). Le score qu'on montre à l'auditeur devient alors « conformité au référentiel **moins** les écarts acceptés et signés », et la liste de ces écarts sort du même fichier que le rôle applique. La mesure (OpenSCAP) et l'application (Ansible) restent deux outils distincts : c'est voulu — on ne demande pas à celui qui applique de se noter lui-même.

**Alternatives**
- *Remédiation générée par ComplianceAsCode* (`oscap xccdf generate fix --fix-type ansible --profile …`, ou les rôles Ansible publiés par le projet) : couverture complète en une commande, mais des centaines de tâches sans le contexte du lab (elles coupent volontiers le routage ou `ufw` partout) ; utile comme **source** de tâches à relire.
- *Rôles communautaires* (`ansible-lockdown` CIS/RHEL, `dev-sec.os-hardening`) : bien faits, mais chacun a son propre modèle d'exceptions et ses propres noms ; on les lit pour les pièges qu'ils documentent.
- *`autotailor`* (paquet `openscap-utils`) pour produire le profil adapté au lieu d'un gabarit : même résultat, une dépendance de plus sur l'hôte.

**Pièges classiques**
- `include_tasks` : `--tags <règle>` n'exécute rien.
- Une exception de routage partielle : le routage est coupé quand même (trois règles, un réglage).
- `rp_filter = 1` sur un nœud Cilium : le `0` posé par Cilium sur ses interfaces ne compte plus (maximum des deux), le trafic des pods tombe.
- Monter un tmpfs sur un `/tmp` vivant à chaud : sockets et fichiers des services disparaissent.
- Profil adapté sans `time` : `oscap` le refuse à l'évaluation, alors qu'`oscap info` l'accepte.
- Le flux RHEL 10 amont sur Rocky : tout « non applicable », score flatteur et faux.
- `ansible_os_family` au lieu de `ansible_facts['os_family']` : `inject_facts_as_vars = False` (M04-E26), la variable n'existe pas.
- Un profil adapté horodaté à chaque passage : jamais idempotent.

**En production chez MédiSphère**
Le rôle vit dans `plateforme/ansible` avec ses tests de non-régression : chaque MR rejoue la vague 0 (recréée par le pipeline) en deux passes, joint la mesure avant/après au fil de la MR, et refuse une baisse du score. Les exceptions ont un propriétaire et une échéance suivie (le rôle échoue le lendemain de la date de revue : c'est voulu, la relance arrive par le pipeline planifié, pas par surprise un jour d'incident).

---

### M26-E11 — Accès : SSH, PAM, sudo et comptes

**Solution**

Fichiers : dans le rôle, [`tasks/ssh.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/ssh.yml), [`templates/sshd-durcissement.conf.j2`](fichiers/M26-E10/ansible/roles/durcissement/templates/sshd-durcissement.conf.j2), [`files/crypto-policies/`](fichiers/M26-E10/ansible/roles/durcissement/files/crypto-policies/), [`tasks/pam.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/pam.yml) et [`templates/pam-configs/`](fichiers/M26-E10/ansible/roles/durcissement/templates/pam-configs/), [`templates/faillock.conf.j2`](fichiers/M26-E10/ansible/roles/durcissement/templates/faillock.conf.j2), [`tasks/sudo.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/sudo.yml), [`tasks/comptes.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/comptes.yml) ; groupes SSH en plus : [`role_gitlab`](fichiers/M26-E10/ansible/inventories/lab/group_vars/role_gitlab/durcissement.yml), [`role_ceph`](fichiers/M26-E10/ansible/inventories/lab/group_vars/role_ceph/durcissement.yml), [`role_routeur`](fichiers/M26-E10/ansible/inventories/lab/group_vars/role_routeur/durcissement.yml), [`role_lb`](fichiers/M26-E10/ansible/inventories/lab/group_vars/role_lb/durcissement.yml) ; politiques ssh-audit [`medisphere-debian13.txt`](fichiers/M26-E11/medisphere/docs/securite/durcissement/ssh-audit/medisphere-debian13.txt) et [`medisphere-rocky10.txt`](fichiers/M26-E11/medisphere/docs/securite/durcissement/ssh-audit/medisphere-rocky10.txt).

1. **État des lieux.**
   ```
   admin@durci-deb:~$ ls /etc/ssh/sshd_config.d/ ; sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|allowgroups|loglevel|trustedusercakeys)'
   admin@adm01:~/src/ansible$ uv run ansible socle -b -m ansible.builtin.shell -a \
       "getent -s files passwd | awk -F: '\$7 !~ /(nologin|false)$/ {print \$1\":\"\$6}' | while IFS=: read u h; do [ -s \"\$h/.ssh/authorized_keys\" ] && echo \"\$u (\$(id -nG \$u))\"; done" -o
   ```
   On retrouve `admin` partout, `git` sur `git01`, `cephadm` sur `ceph01-03`, `supervision` sur la bordure et les répartiteurs, et **`root` partout** : cloud-init a déposé dans `/root/.ssh/authorized_keys` une clé à commande forcée (« Please login as the user admin », M04-E35), que `PermitRootLogin no` refuse déjà ; le rôle déclare donc `root` dans `durcissement_ssh_comptes_sans_ssh` par défaut (sans quoi le premier garde-fou l'arrêterait sur chaque VM issue des images dorées). `01-ssh-durci.conf` fixe déjà `PermitRootLogin`, `PasswordAuthentication`, `KbdInteractiveAuthentication`, `AuthenticationMethods`, les transferts, `ClientAlive*`, `LogLevel VERBOSE` ; `02-`/`03-` (M06) les certificats.

2. **SSH.** Le fichier `00-durcissement.conf` est lu **le premier** (sshd retient la première valeur de chaque mot-clé) : il ne fixe que `AllowGroups`, `MaxSessions`, `Banner`, `HostKeyAlgorithms` et, sur Debian, `KexAlgorithms`, `Ciphers`, `MACs`, `PubkeyAcceptedAlgorithms`, `CASignatureAlgorithms`. Le rôle le prouve à chaque passage : il lit les mots-clés des **autres** fichiers de `sshd_config.d` et refuse tout recouvrement. Les trois autres garde-fous :
   - chaque compte local à clés et à shell doit avoir un groupe dans `AllowGroups` ou figurer dans `durcissement_ssh_comptes_sans_ssh` ; sinon échec **avant** la pose, avec le nom du compte ;
   - le compte de connexion d'Ansible (`admin`) est couvert ;
   - pose dans un `block` : fragment validé seul (`validate: sshd -t -f %s`, avec copie de sauvegarde), puis configuration **complète** (`sshd -t`) ; en cas d'échec, `rescue` remet l'ancien fichier (ou le retire) et arrête sans recharger.
   Après rechargement : `sshd -T` doit montrer une ligne `allowgroups <groupe>` par groupe, `maxsessions 10`, `permitrootlogin no` ; enfin `meta: reset_connection` puis `ping` : **une nouvelle connexion** d'Ansible aboutit (la connexion persistante en cours ne prouvait rien).

3. **Algorithmes.** Debian : listes du gabarit (échanges de clés hybrides post-quantiques `mlkem768x25519-sha256`, `sntrup761x25519-sha512` en tête, puis `curve25519` et DH 16/18 pour les clients plus anciens ; chiffrements AEAD et CTR ; MAC *encrypt-then-MAC*). **Clés d'hôte** : ed25519 (et son certificat step-ca), RSA-SHA2 ; **pas d'ECDSA NIST** (ssh-audit : `fail`). **Clés d'utilisateur et CA** : ECDSA P-256 **reste** dans `PubkeyAcceptedAlgorithms` et `CASignatureAlgorithms` tant que la CA SSH de step-ca peut signer avec une clé ECDSA (vérifie : `step ssh login …` puis `ssh-keygen -L -f ~/.ssh/id_ecdsa-cert.pub | grep 'Signing CA'`, ou le certificat de ton agent : ⚠️ à vérifier sur ton lab). Rocky : trois sous-politiques **limitées à SSH** (`@SSH`) — `NO-SSHCBC` (pas de CBC), `NO-WEAKMAC` (ni HMAC-SHA1 ni UMAC-64, `etm@SSH = DISABLE_NON_ETM`), `NO-SSHNIST` (échange de clés sans courbes NIST ni DH 2048 ; **les signatures ne sont pas touchées**, sinon ECDSA disparaîtrait aussi de `CASignatureAlgorithms`) — et `HostKeyAlgorithms` dans `00-durcissement.conf` pour les seules clés d'hôte (lu avant la politique du système incluse par `50-redhat.conf`). `update-crypto-policies --set DEFAULT:NO-SSHCBC:NO-WEAKMAC:NO-SSHNIST` (Rocky 10 n'a plus de module `NO-SHA1` : DEFAULT refuse déjà SHA-1).

4. **PAM.** `faillock.conf` : `deny = 5`, `fail_interval = 900`, `unlock_time = 900`, `audit`, `silent`, et **`local_users_only`** : les personnes de l'annuaire ont la politique de verrouillage de FreeIPA (6 échecs, M24) ; les compter aussi localement les verrouillerait deux fois, avec deux procédures de déblocage. `root` n'a pas `even_deny_root` : la console reste une voie de secours. Debian : trois profils `pam-auth-update` (`faillock` priorité 0 en `authfail` après les modules d'authentification, `faillock_notify` priorité 1024 en `preauth` et en `account`, `pwhistory` priorité **1022** pour passer **après** `pwquality` 1024 qui demande le mot de passe), puis `pam-auth-update --package --enable faillock faillock_notify pwhistory pwquality` (les profils actifs, dont `sss` de SSSD, sont conservés). Pile obtenue sur Debian 13 :
   ```
   auth     requisite                    pam_faillock.so preauth
   auth     [success=2 default=ignore]   pam_unix.so nullok try_first_pass      (+ pam_sss.so sur un hôte inscrit)
   auth     [default=die]                pam_faillock.so authfail
   password requisite                    pam_pwquality.so retry=3
   password requisite                    pam_pwhistory.so use_authtok
   account  required                     pam_faillock.so
   ```
   Rocky : `authselect enable-feature with-faillock` puis `with-pwhistory` (profil courant conservé : `local`, ou `sssd` sur `ipa01`). Réglages communs : `pwquality.conf.d/60-durcissement.conf`, `pwhistory.conf`.

5. **sudo et comptes.** `/etc/sudoers.d/00-durcissement` (validé par `visudo -cf`) : `use_pty`, `logfile="/var/log/sudo.log"` (rotation par `logrotate`), `timestamp_timeout=5`, `env_reset` ; puis `visudo -c` sur l'ensemble et recherche de toute règle `!authenticate` (refus). Le `NOPASSWD` du compte `admin` est une autre chose (déclarée par le rôle `base`, compte à clé seulement). `comptes.yml` : un seul UID 0, aucun mot de passe vide, `login.defs` (`PASS_MAX_DAYS 365`, `PASS_WARN_AGE 7`, `UMASK 027`), `TMOUT=900` en lecture seule pour les shells interactifs et `umask 027` (profile.d **et** bashrc), groupe `sugroup` vide et `pam_wheel.so use_uid group=sugroup` dans `/etc/pam.d/su` : `su` ne sert plus qu'à `root` (bris de glace), tout le reste passe par sudo, qui journalise.

6. **Application et essais** (sessions de secours ouvertes) :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 --tags ssh,pam,sudo,comptes --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 --tags ssh,pam,sudo,comptes
   admin@adm01:~$ ssh durci-deb true && echo OK                                         # 1. admin, nouvelle session
   admin@adm01:~/src/ansible$ uv run ansible env_m26 -m ansible.builtin.ping                # 2. Ansible
   admin@adm01:~$ step ssh login <toi> --provisioner keycloak && ssh <toi>@durci-deb sudo -l   # 3. personne + sudo de l'annuaire
   admin@adm01:~$ ssh julien.petit@durci-deb                                              # 4. refusé (HBAC du M24, groupe mediagenda) — avec son certificat
   admin@durci-deb:~$ sudo useradd -m essai-faillock ; sudo passwd essai-faillock          # 5. compte local d'essai
   admin@durci-deb:~$ for i in 1 2 3 4 5; do su - essai-faillock -c true </dev/null; done  # (depuis un compte non root : mauvais mot de passe)
   admin@durci-deb:~$ sudo faillock --user essai-faillock ; sudo faillock --user essai-faillock --reset ; sudo userdel -r essai-faillock
   (console Proxmox de la VM 2261 : connexion « secours », sudo -v)                     # 6. secours
   ```
   (Avec `pam_wheel` en place, `su` depuis un compte ordinaire échoue même avec le bon mot de passe : pour l'essai 5, utilise une connexion à la console, ou `pamtester` sur la VM si tu préfères un essai scripté : `pamtester login essai-faillock authenticate`.)

7. **ssh-audit.**
   ```
   admin@adm01:~$ uv tool install 'ssh-audit==3.9.*'
   admin@adm01:~$ ssh-audit durci-deb                       # avant : fail ecdsa-sha2-nistp256 (clé d'hôte), warn « non post-quantique »
   admin@adm01:~$ ssh-audit -M ~/m26/e11/medisphere-debian13.txt durci-deb      # après durcissement
   admin@adm01:~$ ssh-audit -P docs/securite/durcissement/ssh-audit/medisphere-debian13.txt durci-deb
   Result: ✔ Passed
   ```
   Relecture de la politique générée : listes **exactes et ordonnées** (`allow_algorithm_subset_and_reordering = false` : un hôte qui dériverait échoue) ; `optional host keys` pour les certificats d'hôte de step-ca (présentés par les VMs du socle, pas forcément par une VM d'essai) ; bannière commentée (elle change à chaque mise à jour d'OpenSSH). Les **avertissements restants** (`curve25519`, DH 16/18 « non post-quantiques ») sont une **décision écrite** : l'échange hybride post-quantique est en tête de liste et sera choisi par tout client récent ; on garde les autres pour les clients plus anciens du lab ; à revoir quand tous les clients parleront `mlkem768x25519-sha256`. La politique Rocky diffère (ordre et liste imposés par crypto-policies) : d'où une politique par famille — et chacune **échoue** sur l'autre (preuve qu'elles contrôlent vraiment quelque chose).

**Explications**

L'accès se durcit en couches qui ne se marchent pas dessus : **qui** peut se connecter (AllowGroups dans sshd, puis HBAC de FreeIPA hôte par hôte, puis principaux des certificats), **comment** (clés et certificats seulement, algorithmes), **ce qu'on fait après** (sudo journalisé, `su` fermé), et **ce qui arrive aux mots de passe** qui restent (comptes locaux de secours : qualité, historique, verrouillage). Chaque couche a un propriétaire (M04 pour `ssh_durci`, M06 pour les certificats, M24 pour l'annuaire, ce rôle pour le reste) : le durcissement **complète**, il ne réécrit pas, et il le vérifie.

**Alternatives**
- `AllowUsers` au lieu d'`AllowGroups` : plus précis, mais une liste de personnes dans la configuration de chaque hôte ; on préfère des groupes de l'annuaire et HBAC.
- `Match Group`/`Match User` pour des réglages par population (ex. `git` sans pseudo-terminal) : utile, mais chaque bloc `Match` est un endroit de plus où une valeur peut gagner en silence.
- `DisableForwarding yes` : plus court que quatre directives, mais il l'emporte sur l'`AllowTcpForwarding yes` d'`adm01` (bastion).
- Politique crypto `FUTURE` sur Rocky : très stricte pour tout le système (TLS compris : clients anciens, FreeIPA) ; nos sous-politiques ne visent que SSH.

**Pièges classiques**
- Oublier `git` (GitLab en SSH), `cephadm` (orchestrateur Ceph) ou `supervision` dans `AllowGroups` : coupure silencieuse d'un service, découverte des heures plus tard.
- Un mot-clé déjà fixé par `01-ssh-durci.conf` : la valeur de `00-` gagne, l'autre fichier est ignoré sans bruit.
- Retirer ECDSA partout sur conseil de ssh-audit : si la CA de step-ca signe en ECDSA, plus aucun certificat d'utilisateur n'est accepté (`CASignatureAlgorithms`).
- Éditer `common-auth` à la main : le prochain `pam-auth-update` (mise à jour d'un paquet, SSSD) l'écrase.
- `pwhistory … use_authtok` avant `pwquality` : changement de mot de passe impossible.
- `faillock` sans `local_users_only` : double verrouillage des personnes de l'annuaire.
- `UMASK 027` dans `login.defs` sans en mesurer la portée : sur Debian, `pam_umask` (présent dans `common-session` **et** `common-session-noninteractive`) l'applique à **toute** session PAM, y compris la connexion SSH d'Ansible et le `sudo` qui suit. Un fichier ou un dossier qu'un rôle crée **sans `mode:`** devient alors `0640`/`0750` `root:root`, illisible par le compte du service (Prometheus, Alloy, nginx…) au prochain passage de **son** rôle, parfois des semaines plus tard. Parade : `mode:` explicite partout (règle `risky-file-permissions` d'`ansible-lint --profile production`), et un rejeu des rôles de service sur la vague 0 après E11 pour le vérifier (`changed=0`, services actifs). Sur Rocky, `pam_umask` n'est pas dans la pile : le masque ne vient que de `profile.d` et `bashrc` (sessions interactives).
- ssh-audit répété depuis `adm01` : `PerSourcePenalties` d'OpenSSH ≥ 9.8 le bloque (« Not allowed at this time ») ; on espace les essais, ou on exempte `adm01` (`PerSourcePenaltyExemptList`, décision à écrire).
- `allow_larger_keys = false` dans la politique ssh-audit : un hôte avec une clé d'hôte RSA de 4096 bits échoue, alors qu'il est plus fort ; ajuste ou passe à `true` en connaissance de cause.

**En production chez MédiSphère**
La politique ssh-audit est contrôlée chaque semaine sur tout le parc (job planifié depuis `adm01` ou `mon01`, avec exemption de pénalité pour la source), les clés d'hôte RSA disparaissent au profit d'ed25519 seul quand le dernier client ancien est retiré, et les certificats d'hôte de step-ca deviennent obligatoires (pas de clé d'hôte « nue » acceptée par les clients : `@cert-authority` seulement dans `known_hosts`).

---

### M26-E12 — Tracer et détecter : auditd et AIDE

**Solution**

Fichiers : dans le rôle, [`tasks/auditd.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/auditd.yml), [`templates/audit/`](fichiers/M26-E10/ansible/roles/durcissement/templates/audit/), [`tasks/aide.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/aide.yml) et ses gabarits (`aide-*.j2`) ; extension du rôle `alloy` : [défauts](fichiers/M26-E12/ansible/roles/alloy/defaults/main.yml.extrait), [gabarit](fichiers/M26-E12/ansible/roles/alloy/templates/config.alloy.j2.extrait), [variables](fichiers/M26-E12/ansible/inventories/lab/group_vars/all/alloy_audit.yml) ; [requêtes LogQL](fichiers/M26-E12/essais/requetes-logql.md).

1. **auditd.** `auditd.conf` par `lineinfile` : `log_group = adm`, `log_format = ENRICHED` (les identifiants numériques sont suivis de leur nom : `AUID="karim.benali"`, lisible sans l'hôte), 32 Mo × 10 fichiers en rotation, `space_left_action`/`admin_space_left_action = SYSLOG`, `disk_full_action = ROTATE` : on **prévient**, on ne bloque pas l'hôte (le CIS niveau 2 demanderait `halt` : écart écrit). Rechargement par `SIGHUP` (`auditd` refuse un arrêt manuel par systemd : `RefuseManualStop`). Trois fichiers de règles :
   - `30-cis.rules` : heure, identités, PAM, réseau du système, MAC, connexions et sessions, changements de droits, accès refusés, montages, suppressions, `sudo`, modules — toujours avec `-F auid>=1000 -F auid!=unset` pour les appels système (les démons n'ont pas d'auid : pas de bruit) ;
   - `50-medisphere.rules` : `execve`/`execveat` 64 **et** 32 bits des sessions humaines (clé `exec-humain`), surveillances de la liste `durcissement_auditd_surveillances` **seulement si le chemin existe** (`/etc/openbao` sur `vault0x` et `kms01`, `/opt/keycloak/conf` sur `idp01`…) ;
   - `99-fin.rules` : `-e 2` seulement si `durcissement_auditd_immuable` et pas d'exception (ici : exception `audit_rules_immutable`, revue au 31 janvier).
   Chargement `augenrules --load`, contrôle `augenrules --check` (« No change » attendu : les règles chargées sont celles des fichiers).
   ```
   admin@durci-deb:~$ sudo auditctl -l | grep -c . ; sudo auditctl -l | grep exec-humain ; ls -l /var/log/audit/
   ```

2. **AIDE.** Exclusions (`/var/log`, données des services, conteneurs, **`/var/lib/aide`** — sinon les copies horodatées de la base font de chaque nouvelle base un « ajout » : c'est l'essai qui l'a montré), dans `aide.conf.d/99_medisphere_exclusions` sur Debian (nom **sans point** : Debian n'inclut que les noms qui correspondent à `^[a-zA-Z0-9_-]+$`) et dans un bloc géré de `/etc/aide.conf` sur Rocky ; `aide --config-check` ; base initiale **si absente** (`async`/`poll` : plusieurs minutes) puis mise en service ; unité `aide-verification.service` (`Type=oneshot`, `SuccessExitStatus=1 2 3 4 5 6 7` : un écart n'est pas un échec du service, `Nice=19`, E/S en `idle`) et minuterie quotidienne (04:20 + jusqu'à 30 min aléatoires) ; `dailyaidecheck.timer` de Debian **désactivée** (une seule vérification, celle qui écrit la métrique) ; `ExecStopPost=/usr/local/sbin/aide-metrique` traduit `$EXIT_STATUS` en deux métriques, écrites dans un fichier temporaire puis renommées (node_exporter ne lit jamais un fichier à moitié écrit) ; `/usr/local/sbin/aide-nouvelle-base` (`aide --update`, ancienne base gardée, horodatée).

3. **Vers Loki.** Le rôle `alloy` reçoit une liste `alloy_journaux_audit` (fichier, service) : `local.file_match` porte les étiquettes (`job="audit"`, `service`, `host`, `role`, `site`), `loki.source.file` lit le fichier (`tail_from_end = true` : au premier démarrage, pas tout l'historique), un `loki.write "audit"` envoie au locataire `audit`. Alloy lit le fichier grâce au groupe `adm` (journal `0640 root:adm`, dossier `0750 root:adm`). **Pas de masquage** : une ligne d'audit est une preuve, la réécrire la rendrait contestable ; la protection est l'accès (locataire `audit`, organisation Grafana « Sécurité », M22). Le journal de sudo (`/var/log/sudo.log`) n'est pas envoyé : sudo écrit aussi dans journald, déjà collecté. ⚠️ À vérifier sur ton lab : noms et attributs exacts des composants dans la documentation d'Alloy 1.21.

4. **Application.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 --tags auditd,aide --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 --tags auditd,aide
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/journaux-vms.yml --limit env_m26 --check --diff   # playbook du M22
   ```

5. **Essais.**
   ```
   admin@durci-deb:~$ sudo touch /usr/local/bin/essai-aide && sudo systemctl start aide-verification
   admin@durci-deb:~$ curl -s localhost:9100/metrics | grep ^medisphere_aide     # code 1 (ajout)
   admin@durci-deb:~$ journalctl -u aide-verification --since -10min | grep essai-aide
   admin@durci-deb:~$ sudo rm /usr/local/bin/essai-aide && sudo /usr/local/sbin/aide-nouvelle-base && sudo systemctl start aide-verification
   ```
   Dans Grafana (source `loki-audit`) : `{job="audit", service="auditd", host="durci-deb"} |= "key=\"exec-humain\""` montre la session de la personne, `sudo`, puis `visudo -c` et `cat /etc/ssh/sshd_config` exécutés en `uid=0` **avec l'auid de la personne** (`AUID="<toi>"` en fin de ligne, format ENRICHED). La surveillance de `/etc/ssh` est en `-p wa` : elle trace l'écriture et le changement d'attributs, pas la lecture (lire la configuration de sshd n'est pas un événement recherché) ; celle de `/etc/openbao` est en `rwa`, parce que **lire** la configuration du coffre en est un.

6. **Coût** (ordre de grandeur sur une VM peu utilisée ; ⚠️ à mesurer sur ton lab) :
   ```
   sum by (host) (count_over_time({job="audit", service="auditd"} [1h]))
   ```
   La règle `exec-humain` domine pendant un passage d'Ansible (le compte `admin` a un auid ≥ 1000 : chaque module lance plusieurs processus). Décision type : garder (preuve de ce que fait l'automatisation, et c'est le compte de bris de glace), et le dire ; ne pas « exclure admin » sans compensation. Vérification AIDE : quelques minutes par VM, en `idle`.

**Explications**

auditd enregistre **ce que le noyau voit** (appels système, accès aux fichiers) avec l'identité de **connexion** (auid), qui survit à `sudo` et à `su` : c'est ce qui relie une commande root à une personne. AIDE photographie des fichiers (empreintes, droits, propriétaires) et compare : il voit **l'effet** (un binaire changé), pas l'auteur ; auditd voit l'auteur, pas forcément l'effet final. Ensemble : « ce fichier a changé » (AIDE) + « telle personne a écrit dans ce dossier à telle heure » (auditd). Le journal part immédiatement de l'hôte : un attaquant qui efface `audit.log` n'efface pas Loki.

**Alternatives**
- Remontée du journal d'audit **par journald** (`systemd-journald-audit.socket`) : un seul canal, mais doublon possible avec auditd et format moins riche ; on garde le fichier d'auditd comme source.
- `audisp`/`audisp-remote` vers un collecteur syslog : historique, mais un protocole et un serveur de plus.
- Tetragon (E20) pour les exécutions **dans les conteneurs** : auditd voit le processus sur l'hôte, sans le contexte Kubernetes.
- Intégrité : `fs-verity`/IMA (noyau) pour une vérification permanente, plus lourde à mettre en œuvre ; OSSEC/Wazuh pour un agent tout-en-un.

**Pièges classiques**
- Une surveillance sur `/opt/keycloak/conf` partout : chargement interrompu sur toutes les VMs qui n'ont pas Keycloak.
- `-e 2` en phase de mise au point : chaque correction de règle demande un redémarrage.
- `admin_space_left_action = halt` (niveau 2) : la VM s'arrête quand le disque se remplit.
- Oublier le groupe `adm` sur le journal : Alloy ne lit rien, sans erreur visible ailleurs que dans ses propres journaux.
- AIDE qui inclut sa propre base, ou `/var/lib/containerd` : un mur d'écarts chaque jour, que plus personne ne lit.
- Oublier `aide-nouvelle-base` après une vague : le changement voulu reste un écart « pour toujours ».

**En production chez MédiSphère**
Règles d'alerte du ruler Loki sur les clés sensibles (`sudoers`, `openbao`, `modules`) hors des fenêtres d'Ansible (E28), alerte Prometheus sur `medisphere_aide_code_sortie > 0` de plus de 24 h et sur l'absence de vérification (`time() - medisphere_aide_derniere_verification_secondes > 2 * 86400`), base AIDE copiée hors de l'hôte après chaque mise à jour (une base modifiable par l'attaquant ne prouve rien).

---

### M26-E13 — Confiner un service : AppArmor et SELinux

**Solution**

Fichiers : dans le rôle, [`tasks/mac.yml`](fichiers/M26-E10/ansible/roles/durcissement/tasks/mac.yml) et le [profil de Mailpit](fichiers/M26-E10/ansible/roles/durcissement/templates/apparmor/usr.local.bin.mailpit.j2) ; [`host_vars/mon01/durcissement.yml`](fichiers/M26-E13/ansible/inventories/lab/host_vars/mon01/durcissement.yml) ; [modèle de journal](fichiers/M26-E13/essais/journal-mac.md).

1. **Avant.**
   ```
   admin@mon01:~$ sudo aa-status | head -20
   admin@mon01:~$ readlink -f /usr/local/bin/mailpit
   /opt/mailpit/1.31.6/mailpit
   ```
   AppArmor attache un profil au chemin **résolu** de l'exécutable : un profil nommé d'après `/usr/local/bin/mailpit` ne confinerait rien. Le fichier garde le nom fixé par la convention du module (`usr.local.bin.mailpit`), mais le profil (`mailpit`) s'attache à `/opt/mailpit/*/mailpit` : il survit aux montées de version.

2. **Profil en apprentissage.** Gabarit : `abi <abi/4.0>`, `include <tunables/global>`, abstractions `base`, `nameservice`, `ssl_certs` ; `capability net_bind_service` (port 25) ; réseau `inet`/`inet6` `stream` et `unix stream` ; `/etc/mailpit/** r` ; `/var/lib/mailpit/** rwk` (SQLite : base, `-wal`, `-shm`, verrous) ; temporaires de SQLite (`owner /tmp/** rwk`, le `/tmp` privé de l'unité) ; lectures du moteur Go (`/proc/sys/net/core/somaxconn`, `/sys/kernel/mm/transparent_hugepage/hpage_pmd_size`, cgroup) et fuseaux horaires. Le **mode est écrit dans le profil** (`flags=(complain)`) par le gabarit : `aa-complain` modifierait lui-même le fichier, que le rôle réécrirait à chaque passage. Le rôle analyse le profil **avant** de le poser (`validate: apparmor_parser --skip-kernel-load --skip-cache %s`), le charge (`apparmor_parser --replace`), puis vérifie le mode réel (`aa-status --json`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=1 --limit mon01 --tags mac --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=1 --limit mon01 --tags mac
   admin@mon01:~$ sudo aa-status --json | jq '.profiles.mailpit' ; cat /proc/$(pgrep -x mailpit)/attr/current
   "complain"
   mailpit (complain)
   ```
   (`mon01` est dans la vague 1 : on n'applique **que** le domaine `mac`, avec `--tags mac`, avant la vague complète d'E14.)

3. **Une semaine d'usage, puis `aa-logprof`.**
   ```
   admin@mon01:~$ sudo journalctl -k --since -7d | grep 'apparmor="ALLOWED"' | grep 'profile="mailpit"' | sed 's/.*operation=//' | sort | uniq -c
   admin@mon01:~$ sudo aa-logprof
   ```
   Décisions types : accepter ce qui relève du fonctionnement normal (fichiers de la base, lectures de `/proc` par le moteur Go, résolution DNS) ; **refuser** toute exécution (`ix`, `px`) — Mailpit n'a rien à exécuter — et toute lecture hors de `/etc/mailpit` et `/var/lib/mailpit` ; préférer une abstraction à une règle large. `aa-logprof` écrit dans `/etc/apparmor.d/` : on **reporte** ses règles dans le gabarit du rôle (MR), on ne garde pas le fichier modifié à la main (le prochain passage le réécrirait). ⚠️ À vérifier sur ton lab : la liste exacte des accès de Mailpit 1.31.6.

4. **Enforce.** `mode: enforce` dans `host_vars/mon01/durcissement.yml` (MR), application, puis :
   ```
   admin@adm01:~$ swaks --to plateforme@medisphere.internal --server smtp.par1.medisphere.internal --tls   # ou le test d'envoi du M19
   admin@adm01:~$ lab/bin/check 19 03
   admin@mon01:~$ sudo aa-exec -p mailpit -- /bin/sh
   aa-exec: ERROR: … Permission denied
   ```
   Le dernier essai prouve le confinement : un processus sous ce profil ne peut pas lancer de shell. (Si `swaks` n'est pas installé sur `adm01`, l'envoi d'essai du M19 suffit.)

5. **SELinux, lecture.**
   ```
   [admin@ceph01 ~]$ getenforce ; sestatus | grep -E 'mode|policy name'
   [admin@ceph01 ~]$ ps -eZ | awk '{print $1}' | cut -d: -f3 | sort | uniq -c | sort -rn | head
   [admin@durci-rocky ~]$ sudo systemctl start aide-verification & sleep 2; ps -eZ | grep -w aide
   system_u:system_r:aide_t:s0-s0:c0.c1023 … aide
   [admin@ipa01 ~]$ sudo semanage boolean -l -C ; sudo semanage fcontext -l -C
   ```
   Constats : les services installés **hors paquets** dans `/usr/local/bin` (node_exporter, Alloy) tournent en `unconfined_service_t` (un binaire `bin_t` lancé par systemd n'a pas de domaine) : SELinux ne les protège pas — c'est un écart à écrire (un module de politique pour eux est un vrai travail de maintenance). AIDE lancé **directement** par l'unité systemd tourne en `aide_t` (la politique le déclare `init_daemon_domain`) : confiné, il peut lire tout le système de fichiers mais n'écrire que sa base et ses journaux ; c'est pourquoi la métrique est écrite par `ExecStopPost`, pas par AIDE. Sur `ipa01`, les booléens modifiés (`httpd_*`…) et les contextes ajoutés viennent de l'installation de FreeIPA (`ipa-server-install`) : à documenter, pas à « nettoyer ».

6. **Un refus réel** :
   ```
   [admin@durci-rocky ~]$ sudo cp -p /var/lib/aide/aide.db.gz /root/ && sudo mv /root/aide.db.gz /var/lib/aide/aide.db.gz
   [admin@durci-rocky ~]$ ls -Z /var/lib/aide/aide.db.gz ; matchpathcon /var/lib/aide/aide.db.gz
   unconfined_u:object_r:admin_home_t:s0 /var/lib/aide/aide.db.gz
   /var/lib/aide/aide.db.gz        system_u:object_r:aide_db_t:s0
   [admin@durci-rocky ~]$ sudo systemctl start aide-verification ; systemctl status aide-verification --no-pager | tail -3
   [admin@durci-rocky ~]$ sudo ausearch -m AVC -ts recent | audit2why
   type=AVC … denied { read } for … comm="aide" name="aide.db.gz" scontext=system_u:system_r:aide_t:s0 tcontext=unconfined_u:object_r:admin_home_t:s0 …
   Was caused by: Missing type enforcement (TE) allow rule.
   [admin@durci-rocky ~]$ sudo restorecon -v /var/lib/aide/aide.db.gz
   ```
   `mv` garde le contexte du fichier d'origine (`admin_home_t`, celui de `/root`) ; `cp` aurait pris celui du dossier de destination. La règle de contexte existe déjà dans la politique (`semanage fcontext -l | grep aide`) : **réappliquer** (`restorecon`) suffit. Mauvaises réponses : `setenforce 0` (désactive la protection de tout l'hôte pour un fichier mal étiqueté), `audit2allow -M` (autoriserait AIDE à lire tout fichier `admin_home_t` : on élargirait la politique pour couvrir une erreur d'exploitation), `chcon` (correct jusqu'au prochain réétiquetage, qui ne connaît pas `chcon`). ⚠️ À vérifier sur ton lab : le message exact (`audit2why` peut aussi proposer `restorecon` directement).

**Explications**

Un contrôle d'accès **obligatoire** (MAC) s'applique même à root et même au propriétaire des fichiers : ce n'est pas l'identité du processus qui décide, c'est la politique attachée à son **programme** (AppArmor : un profil par chemin d'exécutable) ou à son **domaine** (SELinux : des types sur les processus et les fichiers, des règles entre types). Les deux répondent à la même question — « si ce service est compromis, que peut faire l'attaquant ? » — avec des modèles différents : AppArmor par chemins, simple à écrire pour un service ; SELinux par étiquettes, plus complet, qui suit les fichiers où qu'ils soient copiés… à condition que l'étiquette soit juste.

**Alternatives**
- Durcissement systemd seul (`ProtectSystem`, `SystemCallFilter`, déjà en place sur Mailpit) : complémentaire, pas équivalent (pas de contrôle fin des chemins lus, pas de refus d'exécution).
- Conteneur Podman avec son profil par défaut : confinement « gratuit », mais un moteur de plus sur `mon01`.
- Landlock (le programme se restreint lui-même) : élégant, exige une modification de Mailpit.

**Pièges classiques**
- Profil écrit pour le chemin du lien symbolique : rien n'est confiné, `aa-status` montre le profil chargé mais aucun processus dessous.
- Passer en *enforce* sans semaine d'observation : refus au premier courriel inhabituel (pièce jointe, STARTTLS).
- `aa-complain` à la main sur un hôte géré : le rôle réimpose `enforce` au passage suivant (et inversement).
- `setenforce 0` « le temps de voir » : oublié, et l'hôte reste permissif jusqu'au redémarrage.
- `mv` d'un fichier restauré depuis `/root` ou `/tmp` : contexte faux, refus du service confiné.

**En production chez MédiSphère**
Chaque service exposé d'un hôte Debian a un profil AppArmor (Mailpit d'abord, puis HAProxy, PowerDNS, OAuth2 Proxy), versionné avec son rôle et testé à chaque montée de version (mode *complain* sur une VM d'essai) ; les refus (`apparmor="DENIED"`, `type=AVC`) partent dans Loki et alertent ; les services hors paquets sur Rocky sont listés dans le registre des exceptions avec leur compensation (unité systemd durcie).

---

### M26-E14 — Durcir le socle par vagues

**Solution**

Fichiers : [vagues](fichiers/M26-E10/ansible/inventories/lab/durcissement.yml), [playbook](fichiers/M26-E10/ansible/playbooks/durcissement.yml), [`ansible.cfg`](fichiers/M26-E10/ansible/ansible.cfg.extrait), [RB-263](fichiers/M26-E14/medisphere/docs/securite/durcissement/runbooks/RB-263-durcissement-par-vagues.md), [rapport de la vague 1](fichiers/M26-E14/medisphere/docs/securite/durcissement/rapports/vague-1.md) (modèle des six).

1. **Préparation.** L'inventaire des vagues ne déclare que des **groupes** (`durcissement_vague_0` contient le groupe `env_m26`) ; ajouté à la liste `inventory` d'`ansible.cfg`, il se fond avec NetBox. Contrôle avant tout : `uv run ansible-inventory --graph durcissement_vague_6`. Le playbook :
   - `hosts: durcissement_vague_{{ vague }}` (sans `-e vague`, groupe inexistant : aucun hôte touché) ;
   - `serial: 1` à partir de la vague 4, `max_fail_percentage: 0` : le premier échec arrête tout avant l'hôte suivant ;
   - pré-tâches : session de secours **confirmée** pour `adm01` ; `kubectl drain` d'un nœud K8s (délégué à `adm01`, kubeconfig de la personne : `kubectl auth whoami` juste avant, pour un jeton OIDC frais) ; `ceph osd set noout` **depuis un autre nœud** de la grappe ;
   - post-tâches : sudo d'Ansible, résolution d'une personne de l'annuaire par SSSD (sur les hôtes inscrits), `noout` retiré, `uncordon`.

2. **RB-263** : voir le fichier (règles, vagues, procédure, tableau de contrôles après vague, retour arrière par situation, modèle de rapport).

3. **Vagues.** Pour chacune :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conformite-mesure.yml -e vague=1 -e moment=avant
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=1 --check --diff | tee ~/m26/e14/vague-1-check.txt
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=1 | tee ~/m26/e14/vague-1-application.txt
   admin@adm01:~/src/ansible$ uv run ansible durcissement_vague_1 -b -m ansible.builtin.command -a /usr/local/sbin/aide-nouvelle-base
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conformite-mesure.yml -e vague=1 -e moment=apres
   ```
   Particularités rencontrées (à confronter à ton lab) :
   - **vague 2** : `runner02` et `reg01` routent (Docker) : le garde-fou de routage arrête le rôle si les exceptions ne les couvrent pas — c'est exactement son rôle ;
   - **vague 3** : `git01` : le garde-fou SSH signale le compte `git` si `role_gitlab` n'a pas `durcissement_ssh_groupes_supplementaires: [git]` ; après la vague, `ssh -T git@git01.par1.medisphere.internal` doit répondre « Welcome to GitLab » ;
   - **vague 4** : `ipa01` (Rocky, FreeIPA) : politique cryptographique **limitée à SSH** (sans effet sur Kerberos, LDAPS, Dogtag) ; contrôles après : `kinit`, `ipa ping`, connexion SSO à Grafana (fédération LDAPS de Keycloak) ; `package_httpd_removed` en exception ;
   - **vague 5** : `lb02` puis `lb01`, `gw02` puis `gw01` ; entre deux, `ip -br a | grep 10.10.70.200` et la VIP de chaque VLAN au bon endroit, `ping` à travers la bordure ;
   - **vague 6** : nœuds K8s un par un (`drain` peut prendre plusieurs minutes : PDB de MédiAgenda), `ceph -s` en `HEALTH_OK` (sauf `noout` pendant l'intervention) entre deux nœuds Ceph, `adm01` en dernier avec `-e durcissement_secours_confirme=true`.

4. **Écarts.** Règle de décision : si la règle est juste et que le lab l'enfreint par négligence → **corriger le rôle** (ou le rôle du service) ; si l'hôte a une raison métier → **exception** signée ; si c'est un faux positif du contenu (règle mal évaluée) → exception avec la justification « faux positif » et un ticket au projet ComplianceAsCode. Exemples : `accounts_umask_etc_bashrc` en échec sur les VMs d'essai → corrigé dans `comptes.yml` (masque aussi dans `bash.bashrc`) ; `service_nginx_disabled` sur `nbx01` → exception.

5. **Fin.**
   ```
   admin@adm01:~/src/infra/envs/m26$ tofu plan -destroy       # doit ne lister que durci-deb et durci-rocky (2261, 2262)
   admin@adm01:~/src/infra/envs/m26$ tofu destroy
   admin@adm01:~$ ssh root@pve01 'qm status 2261; qm status 2262'   # « does not exist »
   admin@adm01:~$ rm -f ~/.ssh/known_hosts_env-m26
   ```
   NetBox : si les VMs avaient été déclarées (E04), passe-les en statut « decommissioning » puis supprime-les (ou laisse `medictl netbox sync` du M06 le faire, selon ton flux). Les mesures et rapports restent ; les VMs, non.

**Explications**

Une vague est un **lot de changement** : même rôle, même version, mêmes exceptions, appliqués à des hôtes de criticité voisine, avec un critère d'entrée (la vague précédente est verte depuis une heure, sauvegarde du jour, sessions de secours) et de sortie (contrôles, mesure, nouvelle base AIDE, rapport). L'ordre suit le **rayon d'impact** : on apprend sur ce qui casse peu (supervision, NetBox) et on finit par ce qui porte tout (bordure, cluster, poste d'administration). `serial: 1` sur les paires et les grappes garantit qu'il reste toujours un membre sain.

**Alternatives**
- Vagues par **pourcentage** (`serial: ["1", "25%", "100%"]`) dans un seul playbook : pratique pour un parc homogène ; ici les rôles sont trop différents.
- Application **par rôle de service** (tous les DNS, puis tous les répartiteurs) : mélange criticités et paires, déconseillé.
- **Reconstruction** plutôt que modification : nouvelle image dorée durcie (M03), VMs recréées une à une ; c'est la cible à terme (« immuable »), mais elle suppose que tout l'état des VMs soit reconstruisible.

**Pièges classiques**
- Les deux passerelles dans la même passe : si le rôle casse la bordure, plus aucun accès au lab.
- Vague lancée sans `--check --diff` relu : un diff de `sudoers` ou de `sshd` non vu.
- `drain` avec un kubeconfig dont le jeton OIDC a expiré : le playbook demande une connexion par navigateur au milieu d'une vague.
- Oublier la nouvelle base AIDE : alerte d'intégrité le lendemain sur toute la vague.
- `tofu destroy` dans le mauvais dossier d'état : toujours `tofu plan -destroy` d'abord.

**En production chez MédiSphère**
Le rôle est rejoué **chaque semaine** sur tout le parc en `--check` (dérive détectée = rapport), et appliqué par vagues à chaque nouvelle version, depuis le pipeline protégé ; les vagues sont des données (inventaire), relues comme du code ; la fenêtre de changement est annoncée (CHG-) et l'astreinte a RB-263 sous les yeux.

---

### M26-E15 — Kyverno : n'admettre que les images signées

**Solution**

Fichiers : [`exiger-signature-medisphere.yaml`](fichiers/M26-E15/politiques/kyverno/images/exiger-signature-medisphere.yaml), [`ExternalSecret` `harbor-kyverno`](fichiers/M26-E15/politiques/kyverno/acces/harbor-kyverno.externalsecret.yaml) (rendu par l'Application `politiques`, dont la destination est l'espace `kyverno`), [`kustomization.yaml` (extrait)](fichiers/M26-E15/politiques/kustomization.yaml.extrait), [valeurs du chart (extrait)](fichiers/M26-E15/gitops/valeurs/kyverno/values.yaml.extrait), [robot (OpenTofu)](fichiers/M26-E15/infra/registre/robots.tf.extrait).

1. **Accès au registre.**
   ```
   admin@adm01:~/src/infra/registre$ tofu plan && tofu apply          # robot$medisphere+kyverno (pull, artifact read, accessory list)
   ```
   Le secret est dans l'état (chiffré, M05) : on le passe à OpenBao **sans** l'afficher ni le mettre sur une ligne de commande, par un fichier en mémoire effacé aussitôt :
   ```
   admin@adm01:~/src/infra/registre$ (umask 077; echo 'nonsensitive(random_password.robot_kyverno.result)' | tofu console | tr -d '"\n' > /dev/shm/robot-kyverno)
   admin@adm01:~$ bao kv put kv/plateforme/kyverno/harbor utilisateur='robot$medisphere+kyverno' mot_de_passe=@/dev/shm/robot-kyverno && shred -u /dev/shm/robot-kyverno
   ```
   (`@fichier` : la valeur est lue dans le fichier, jamais sur la ligne de commande ; `'…'` protège le `$` du nom du robot.) L'`ExternalSecret` (ClusterSecretStore `openbao`, réservé aux espaces de plateforme, M25-E12) construit un Secret `kubernetes.io/dockerconfigjson` par gabarit (moteur v2). La racine MédiSphère va dans `global.caCertificates.data` de `valeurs/kyverno/values.yaml` (E07 ; montée dans le magasin de chaque contrôleur) : MR dans `plateforme/gitops` ; l'`ExternalSecret` dans `plateforme/politiques` (MR).
   ```
   admin@adm01:~$ kubectl -n kyverno get externalsecret harbor-kyverno
   NAME             STORETYPE            STORE     REFRESH INTERVAL   STATUS         READY
   harbor-kyverno   ClusterSecretStore   openbao   1h                 SecretSynced   True
   ```

2. **Clés.**
   ```
   admin@adm01:~$ export VAULT_ADDR=$BAO_ADDR VAULT_TOKEN=$(bao print token)        # session OIDC (M25)
   admin@adm01:~$ cosign public-key --key hashivault://cosign-medisphere | diff - ~/medisphere/docs/registre/cosign.pub && echo identique
   admin@adm01:~$ IMG=registry.par1.medisphere.internal/medisphere/mediagenda-api
   admin@adm01:~$ D=$(kubectl -n mediagenda-recette get deploy mediagenda -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*@//')
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true $IMG@$D | jq '.[0].critical.image' \
       || cosign verify --key ~/medisphere/docs/registre/cosign-m13.pub --insecure-ignore-tlog=true $IMG@$D | jq '.[0].critical.image'
   ```
   (Le nom du Deployment ou du Rollout dépend de ton chart, M17-M20 ; prends le condensé du pod si besoin : `status.containerStatuses[].imageID`.) `cosign.pub` est la clé de transit depuis M25-E20 (le `diff` le confirme) ; une image d'avant M25-E20 ne vérifie qu'avec `cosign-m13.pub` : c'est pour elle que la politique garde un second attesteur. Si ton M25-E20 a pris le repli KV, la clé publique reste `cosign.pub` et la commande `hashivault://` ne s'applique pas.

3. **Politique.** Points de conception (le fichier les commente) :
   - `matchConstraints.namespaceSelector` sur `kubernetes.io/metadata.name` (étiquette posée par l'API, qu'une équipe ne peut pas retirer) ; jamais `kube-system`, `kyverno`, `argocd` ;
   - `matchImageReferences` : `registry.par1.medisphere.internal/medisphere/*` (les autres images relèvent de `registres-autorises`) ;
   - `validationConfigurations` : `mutateDigest: false` (sous Argo CD, une image réécrite par l'admission diffère de Git : écart permanent, synchronisations en boucle), `verifyDigest: true` (le condensé est exigé), `required: true` ;
   - deux attesteurs à clé (`cleTransit`, `cleM13` : des identifiants CEL, sans tiret), `ctlog.insecureIgnoreTlog: true` (pas de Rekor, M13) ; validations sur `images.containers` **et** `images.initContainers` ; attestation `intoto.type: https://spdx.dev/Document` vérifiée par `verifyAttestationSignatures` ;
   - `webhookConfiguration.timeoutSeconds: 15` ; `credentials.secrets: [harbor-kyverno]` ; autogénération pour Deployments, StatefulSets, DaemonSets, Jobs, CronJobs (l'erreur s'affiche dans la synchronisation d'Argo CD, pas dans les événements d'un ReplicaSet).
   Première version : `validationActions: [Audit]`, `failurePolicy: Ignore`. Puis :
   ```
   admin@adm01:~$ kubectl get imagevalidatingpolicies exiger-signature-medisphere -o jsonpath='{.status.conditionStatus.ready}'
   true
   ```

4. **Rapports.**
   ```
   admin@adm01:~$ kubectl get policyreports -A -o json | jq -r '.items[] | .metadata.namespace as $n | .results[]? | select(.policy=="exiger-signature-medisphere" and .result!="pass") | "\($n)\t\(.resources[0].name)\t\(.message)"'
   ```
   Cas typiques : une image du M17-M19 encore en service, antérieure à la signature systématique, ou signée **avant** l'attestation SBOM ; un pod qui tire l'image par **étiquette** (overlay `dev` d'avant la promotion par condensé). Correctif : nouvelle version par la chaîne de livraison (signature + attestation) et promotion par MR — jamais un élargissement de la politique.

5. **Essais** (`~/m26/e15/essais.md`) :
   ```
   admin@adm01:~$ E=registry.par1.medisphere.internal/medisphere/essai-signature
   admin@adm01:~$ skopeo copy docker://registry.par1.medisphere.internal/bibliotheque/debian:trixie docker://$E:essai-a   # puis b, c (trois condensés distincts : ajoute une couche, ou copie trois images différentes)
   admin@adm01:~/m26/e15$ COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix jetable
   admin@adm01:~/m26/e15$ cosign sign --key jetable.key --signing-config ~/medisphere/docs/registre/signing-config.json $E@<D-c>
   admin@adm01:~$ kubectl -n wb-essais run essai-a --image=$E@<D-a> --dry-run=server -o name
   ```
   | Essai | Réponse attendue |
   |---|---|
   | (a) signée par la clé MédiSphère, SBOM attestée, par condensé | `pod/essai-a created (server dry run)` |
   | (b) non signée | refus — souvent **avant** Kyverno : Harbor (politique « signature exigée », M13-E14) refuse de servir le manifeste, Kyverno échoue à le lire et refuse (`Fail`) ; message différent de (c) |
   | (c) signée par la clé jetable | refus de Kyverno : « image MédiSphère sans signature valide d'une clé MédiSphère » — c'est **le** cas que Harbor ne voit pas |
   | (a) par étiquette | refus : « … does not have a digest » |
   Signer (a) avec la clé MédiSphère : par la chaîne de CI (pipeline sur une branche protégée d'un projet d'essai, M19) de préférence ; à la main sur `adm01`, avec la clé lue depuis le coffre dans `/dev/shm` et supprimée aussitôt, **et** l'attestation SPDX (`syft … -o spdx-json`, `cosign attest --type spdxjson …`). À la fin : suppression du dépôt `medisphere/essai-signature` dans Harbor (API ou interface).

6. **Refus.** MR : `validationActions: [Deny]`, `failurePolicy: Fail` ; une journée sur `mediagenda-recette` seul (on retire temporairement les autres espaces de la liste), une synchronisation normale d'Argo CD doit passer (redémarre un Rollout de recette pour voir des pods **recréés** admis) ; puis la liste complète.
   ```
   admin@adm01:~$ kubectl get imagevalidatingpolicies exiger-signature-medisphere -o json | jq '{a: .spec.validationActions, f: .spec.failurePolicy}'
   ```

**Explications**

Trois contrôles se complètent, à trois moments : la **CI** signe et vérifie ce qu'elle produit (M13, M19) ; **Harbor** refuse de servir une image sans signature, sans savoir qui l'a signée (M13-E14) ; **l'admission** vérifie, au moment où l'image va tourner, qu'elle est signée par **notre** clé et accompagnée de son SBOM. Le dernier est le seul qui protège contre une image poussée hors chaîne ou signée par une clé étrangère. Cosign 3 range la signature comme un *bundle* Sigstore attaché à l'image par l'API *Referrers* (OCI 1.1) ; Kyverno 1.19 sait le lire (essai du corrigé), avec ou sans journal de transparence. Deux attesteurs = période de recouvrement de rotation de clé : on retire l'ancienne clé **après** avoir re-signé tout ce qui tourne (rapports à zéro).

**Alternatives**
- `ClusterPolicy` avec `verifyImages` : dépréciée en 1.19, **supprimée en 1.20** : à ne plus écrire.
- *Sigstore policy-controller* : spécialisé, sait aussi les signatures sans clé (OIDC) ; une brique de plus.
- Ratify + Gatekeeper : orienté Notation et les signatures OCI ; pertinent si l'on passait à Notation.
- Vérifier à la CI de déploiement (job avant la MR de promotion) : utile, mais ne protège pas d'un `kubectl` hors chaîne.

**Pièges classiques**
- Un nom d'attesteur avec un tiret : l'expression CEL `attestors.cle-m13` est une soustraction.
- `mutateDigest: true` sous Argo CD : écart permanent entre Git et le cluster.
- Oublier les conteneurs d'initialisation : une image non signée passe par la migration de base.
- `failurePolicy: Fail` sans robot valide : tous les pods de production refusés à l'expiration du robot (180 jours) — la rotation du robot est dans le registre des secrets (M25).
- Espaces visés par une étiquette d'équipe modifiable : une équipe qui retire l'étiquette sort de la politique (E36 en fera une panne).
- Croire qu'un refus en (b) prouve la politique : c'est Harbor qui a refusé ; seul (c) prouve Kyverno.

**En production chez MédiSphère**
Alerte sur toute violation de `exiger-signature-medisphere` dans les rapports (E18) et sur les erreurs de vérification du contrôleur (métriques de Kyverno), rotation planifiée de la clé avec deux attesteurs pendant un mois, robot renouvelé par OpenTofu avant échéance, et une `PolicyException` d'urgence prête mais inactive (RB-261) pour un correctif de sécurité qui ne pourrait pas attendre la chaîne.

---

### M26-E16 — Kyverno : muter et générer

**Solution**

Fichiers : [`exiger-limites.yaml`](fichiers/M26-E16/politiques/kyverno/validation/exiger-limites.yaml), [`exiger-digest.yaml`](fichiers/M26-E16/politiques/kyverno/validation/exiger-digest.yaml), [`interdire-identifiants-url.yaml`](fichiers/M26-E16/politiques/kyverno/validation/interdire-identifiants-url.yaml), [`seccomp-par-defaut.yaml`](fichiers/M26-E16/politiques/kyverno/mutation/seccomp-par-defaut.yaml), [`networkpolicy-par-defaut.yaml`](fichiers/M26-E16/politiques/kyverno/generation/networkpolicy-par-defaut.yaml), [tests](fichiers/M26-E16/politiques/kyverno/tests/) (un dossier par politique et `valeurs.yaml`), [`kustomization.yaml` (extrait)](fichiers/M26-E16/politiques/kustomization.yaml.extrait), [`.gitlab-ci.yml` (extrait)](fichiers/M26-E16/politiques/gitlab-ci.yml.extrait).

1. **Validation.**
   - `exiger-limites` : variable `conteneurs` (conteneurs + initialisation), variable `fautifs` (noms des conteneurs sans `requests.cpu`, `requests.memory` ou `limits.memory`), message calculé qui les nomme. **Pas de limite de CPU** : une limite de CPU bride le conteneur même quand le nœud est libre (*throttling* du CFS, latences de MédiAgenda) sans protéger le nœud, que protègent déjà les demandes (ordonnancement) et la limite de mémoire (OOM du conteneur, pas du nœud). `failurePolicy: Ignore` : règle d'hygiène, pas de sécurité dure.
   - `exiger-digest` : espaces `medisphere.internal/environnement: prod` ; condensé exigé par motif `@sha256:[a-f0-9]{64}$` ; `Fail`.
   - `interdire-identifiants-url` : ConfigMaps et pods ; motif RE2 `schéma://utilisateur:motdepasse@` (un `:` **et** un `@` avant le premier `/`) ; variables d'environnement en **valeur** seulement (`valueFrom.secretKeyRef` reste permis) ; les Secrets ne sont pas visés (c'est leur place). Limite assumée : `https://jeton@hôte` (utilisateur seul) n'est pas visé.

2. **Mutation.** `MutatingPolicy` `seccomp-par-defaut` : `matchConditions` « pas de `securityContext.seccompProfile` au niveau du pod » ; mutation `ApplyConfiguration` (objet partiel : `runAsNonRoot` et les autres champs existants sont conservés, test à l'appui) ; espaces d'équipe ; `failurePolicy: Ignore` ; **pas d'autogénération** : muter le gabarit d'un Deployment créerait un écart avec Git (Argo CD verrait l'objet « OutOfSync ») — on mute le **pod**, que personne ne déclare dans Git. Effet : un pod sans profil n'est plus refusé par PSA `restricted` (la mutation passe **avant** la validation).

3. **Génération.** `GeneratingPolicy` `networkpolicy-par-defaut` : déclenchée par la création (et la mise à jour) d'un Namespace portant `medisphere.internal/equipe` (`matchConditions`) ; deux NetworkPolicy construites en CEL (`dyn(…)`), posées par `generator.Apply(<espace>, [objets])`. Décisions : `synchronize: true` (Kyverno rétablit un objet supprimé ou modifié : une équipe ne peut plus remplacer `refus-par-defaut` par un objet de même nom, promesse du M20) ; `generateExisting: false` (les espaces existants ont déjà ces objets, posés par `plateforme/k8s` ; les « reprendre » ferait deux propriétaires — Argo CD et Kyverno — pour le même objet : chantier à part) ; `orphanDownstreamOnPolicyDelete: true` (supprimer la politique ne retire **jamais** le refus réseau d'un espace).

4. **Tests.** Un dossier par politique (`kyverno-test.yaml`, `ressources.yaml`, `attendu.yaml` pour la mutation et la génération), étiquettes d'espaces dans `tests/valeurs.yaml` (`kind: Values`, `namespaceSelector`). Résultats attendus : `pass`, `fail`, `skip` (ressource hors périmètre) ; `patchedResources` pour la mutation, `generatedResource` pour la génération.
   ```
   admin@adm01:~/src/politiques$ kyverno test kyverno/tests/
   …
   Test Summary: 20 tests passed and 0 tests failed
   admin@adm01:~/src/politiques$ sed -i '0,/RuntimeDefault/s//Unconfined/' kyverno/tests/seccomp-par-defaut/attendu.yaml && kyverno test kyverno/tests/seccomp-par-defaut/
   Error: 1 tests failed
   admin@adm01:~/src/politiques$ git checkout kyverno/tests/seccomp-par-defaut/attendu.yaml
   ```
   Chaque politique a au moins un cas qui **doit** échouer : un test qui ne voit que des cas conformes ne prouve rien.

5. **CI.** Le job `kyverno:tests` d'E07 (CLI 1.19.2 téléchargée et vérifiée par son SHA-256 `357eaf1d…bf4a`, celui de `checksums.txt`) reçoit `--require-tests` : un dossier de tests renommé ou vidé ferait sinon un job vert qui ne teste rien. Nouveau job `politiques:types-cel` : aucune `ClusterPolicy`/`Policy`/`*CleanupPolicy` (dépréciées en 1.19, supprimées en 1.20). Les deux tournent sur les MR et sur `main`.

6. **Mise en service et essais.**
   ```
   admin@adm01:~$ kubectl get policyreports -A -o json | jq -r '.items[] | .metadata.namespace as $n | .results[]? | select(.result=="fail") | "\($n)\t\(.policy)\t\(.resources[0].name)"' | sort | uniq -c
   admin@adm01:~$ kubectl create namespace wb-modele-equipe --dry-run=client -o yaml \
       | kubectl label --local -f - medisphere.internal/equipe=plateforme medisphere.internal/environnement=dev -o yaml | kubectl apply -f -
   admin@adm01:~$ kubectl -n wb-modele-equipe get networkpolicies -L app.kubernetes.io/managed-by,medisphere.internal/modele
   admin@adm01:~$ kubectl -n wb-modele-equipe run essai-seccomp --image=registry.par1.medisphere.internal/bibliotheque/debian:trixie \
       --overrides='{"spec":{"containers":[{"name":"essai-seccomp","image":"registry.par1.medisphere.internal/bibliotheque/debian:trixie","command":["sleep","infinity"],"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"memory":"32Mi"}},"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
   admin@adm01:~$ kubectl -n wb-modele-equipe get pod essai-seccomp -o jsonpath='{.spec.securityContext.seccompProfile.type}'
   RuntimeDefault
   admin@adm01:~$ kubectl -n wb-modele-equipe create configmap essai --from-literal=DATABASE_URL='postgresql://u:p@hote/base' --dry-run=server
   error: … ConfigMap : URL avec identifiants dans la ou les clé(s) DATABASE_URL …
   ```
   (`wb-modele-equipe` est un espace d'essai du workbook, créé à la main comme `wb-essais` : la règle « pas de `kubectl apply` » vise les espaces applicatifs. L'espace hérite du niveau PSA par défaut du cluster : le pod d'essai est écrit pour passer `restricted`, sauf seccomp que la mutation ajoute. L'image `bibliotheque/debian` est par étiquette : admise, car `exiger-digest` ne vise que la production.)

**Explications**

Kyverno 1.19 aligne ses politiques sur le modèle de l'admission native de Kubernetes : `matchConstraints`, `matchConditions`, `variables`, expressions **CEL** compilées et vérifiées à l'avance (coût borné), `validationActions` (`Deny`, `Audit`, `Warn`). Il y ajoute ce que l'API ne fait pas seule : vérification d'images, génération d'objets, rapports, exceptions, tests hors cluster. La mutation passe avant la validation dans la chaîne d'admission : c'est ce qui permet de **rendre conforme** (seccomp) plutôt que de refuser. La génération transforme une convention (« tout espace d'équipe a un refus par défaut ») en invariant maintenu.

**Alternatives**
- `LimitRange` par espace pour donner des valeurs par défaut de ressources : complémentaire (valeurs par défaut) mais ne refuse pas un conteneur qui déclare n'importe quoi ; on garde les deux.
- `MutatingAdmissionPolicy` native (GA en 1.36) pour seccomp : pas de webhook à faire tourner ; E17 compare.
- Kyverno `GeneratingPolicy` **clone** d'objets modèles rangés dans un espace de plateforme : un seul modèle à éditer, moins de CEL ; la source devient un objet du cluster.
- Politique Cilium à l'échelle du cluster (refus par défaut pour tout espace d'équipe) : pas d'objet par espace, mais un modèle différent de celui du M15.

**Pièges classiques**
- Muter les contrôleurs sous Argo CD : « OutOfSync » permanent, voire boucle de synchronisation.
- `generateExisting: true` sur des espaces déjà gérés par Git : deux propriétaires, chacun réécrit l'autre.
- `orphanDownstreamOnPolicyDelete: false` (défaut) avec `synchronize` : retirer la politique retire le refus réseau de tous les espaces générés.
- Une expression qui suppose `object.spec.initContainers` présent : erreur d'évaluation, et avec `Ignore` la règle ne s'applique plus, sans bruit (toujours `has(…)`).
- Des tests sans cas en échec : toujours verts, même si la politique ne fait rien.
- Générer un type d'objet que le contrôleur d'arrière-plan de Kyverno n'a pas le droit de créer : la génération échoue (événement sur la politique). Les NetworkPolicy sont dans les droits par défaut du chart 3.9 (`backgroundController.rbac.coreClusterRole.extraResources`) ; un autre type (CiliumNetworkPolicy) demanderait d'étendre ces droits par les valeurs du chart.
- Un motif d'URL trop large (`://.*@`) : refuse des adresses de courriel ou des URL de dépôt Git légitimes.

**En production chez MédiSphère**
Toute nouvelle politique arrive en `Audit` avec son dossier de tests, passe une semaine à lire les rapports (E18), puis `Deny` par MR relue par Karim et Sophie ; les promesses restantes des modules précédents (PDB, sondes, noms d'hôte des HTTPRoute, annotation LB-IPAM réservée, `dnsPolicy`, `CiliumNodeConfig`) sont tenues ici sur le même modèle, une politique par MR.

**Ce qui reste promis (modules précédents, non traité dans E15-E16)** : PDB obligatoire au-delà d'un réplica et sonde de disponibilité exigée (M14), classe de stockage chiffrée pour les espaces de données de santé (M16), noms d'hôte `<espace>.apps…` et annotation `lbipam.cilium.io/ips` réservée à la plateforme, `dnsPolicy` et `CiliumNodeConfig` (M15), RoleBinding `pods/exec` limité à l'équipe (M22), règles sur les `OpenTelemetryCollector` (M23) : chacune s'écrit comme les politiques de cet exercice ; elles sont proposées en « pour aller plus loin » d'E16 et reprises par E18 (exceptions et rapports) et le mini-projet.

---

### M26-E17 — Politiques d'admission natives : ValidatingAdmissionPolicy et MutatingAdmissionPolicy

**Solution**

Fichiers : [`20-interdire-hostpath.yaml`](fichiers/M26-E17/k8s/admission/20-interdire-hostpath.yaml), [`30-etiquette-equipe-par-defaut.yaml`](fichiers/M26-E17/k8s/admission/30-etiquette-equipe-par-defaut.yaml), [`40-etiquettes-espace-protegees.yaml`](fichiers/M26-E17/k8s/admission/40-etiquettes-espace-protegees.yaml) (`plateforme/k8s`) ; essais [`m26-e17/`](fichiers/M26-E17/m26-e17/) ; document [`admission-native-ou-kyverno.md`](fichiers/M26-E17/medisphere/docs/securite/durcissement/admission-native-ou-kyverno.md).

1. **Recensement.**
   ```
   admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns
       | .spec.volumes[]? | select(.hostPath) | "\($ns) \(.hostPath.path)"' | sort -u > ~/m26/e17/hostpath-actuels.txt
   admin@adm01:~$ helm template falco oci://registry.par1.medisphere.internal/charts/falco --version 9.2.1 \
       -f ~/src/gitops/valeurs/falco/values.yaml | yq 'select(.kind=="DaemonSet") | .spec.template.spec.volumes[] | select(has("hostPath")) | .hostPath.path'
   ```
   Falco (chart 9.2.1, `modern_ebpf`) : `/proc`, `/boot`, `/lib/modules`, `/usr`, `/etc`, `/sys/kernel`, `/var/run` et les sockets de tous les moteurs de conteneurs (`/run/containerd`, `/run/crio`, `/run/podman`…) ; avec `driver.kind: auto`, il ajoute `/dev` et `/sys/module`. Tetragon 1.7.1 : `/proc`, `/sys/fs/bpf`, `/var/run/cilium`, `/var/run/cilium/tetragon`, `/var/run/tetragon`. Le node-exporter de kube-prometheus-stack monte la **racine** `/` (en lecture seule) : il voit tout le système de fichiers du nœud, clés de kubelet comprises. C'est la plus large des exceptions, et la VAP ne la réduit pas : elle l'**écrit**.
2. **La VAP.** Même ossature que `medisphere-images` : `variables.specPod` selon le type d'objet, `variables.chemins` (les `hostPath`), `variables.autorises` (lue dans `params.data[request.namespace]` si la clé existe, sinon liste vide), `variables.refuses` avec la règle « chemin exact ou sous-dossier » (`c == a || c.startsWith(a + '/')`). Liaison sur tout le cluster sauf `kube-system` et `cilium` : la couche de base (Cilium, CoreDNS) ne doit jamais dépendre d'une ConfigMap de paramètres.
3. **Essais.** Dans `wb-essais` (Pod Security `baseline`), c'est **Pod Security** qui refuse, et il refuse le premier : `violates PodSecurity "baseline:latest": hostPath volumes (volume "hote")` ; la VAP n'est même pas évaluée (dans la chaîne des contrôleurs de validation intégrés, `PodSecurity` passe avant `ValidatingAdmissionPolicy`). Dans `falco` (`privileged`), Pod Security laisse passer et la VAP refuse :
   ```
   … pods "e17-hostpath" is forbidden: ValidatingAdmissionPolicy 'medisphere-interdire-hostpath' with binding
   'medisphere-interdire-hostpath' denied request: volume(s) hostPath interdit(s) dans l'espace falco : /root
   (autorisés : /proc, /boot, /lib/modules, /usr, /etc, …) — dérogation : RB-261
   ```
   En `[Warn, Audit]`, le même essai est **accepté** avec un `Warning:` ; c'est la mise à jour à blanc des DaemonSet en service (`kubectl get ds … -o yaml | kubectl apply --dry-run=server -f -`) qui dit, sans rien redémarrer, si un agent serait refusé demain.
4. **`Deny` et paramètre absent.** `parameterNotFoundAction: Deny` : sans la ConfigMap, **tout** objet visé est refusé (y compris les pods sans `hostPath` : la politique ne peut pas s'évaluer). C'est le comportement sûr ; la ConfigMap vit dans le même fichier, avant la politique, et la VAP d'E17 B protège… les espaces, pas les ConfigMap : la protection de `kube-system` repose sur RBAC (personne d'autre que les administrateurs n'y écrit). `Allow` ferait d'une suppression de ConfigMap une désactivation silencieuse.
5. **Étiquettes d'espace.** `matchConditions` écarte les administrateurs (évaluée avant tout, pas de coût pour eux), les variables comparent `oldObject.metadata.labels` et `object.metadata.labels` (sur une table CEL, `filter` itère sur les clés). Essais :
   ```
   admin@adm01:~$ kubectl auth whoami                         # Groups: … oidc:plateforme-admins
   admin@adm01:~$ kubectl label ns wb-essais pod-security.kubernetes.io/enforce=privileged --overwrite \
       --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   Error from server (Forbidden): namespaces "wb-essais" is forbidden: User "oidc:lucas.martin" cannot patch resource "namespaces" …
   ```
   RBAC refuse **avant** l'admission (authentification, autorisation, puis mutation et validation) : c'est rassurant (Lucas n'a pas ce droit), mais la VAP n'a pas été évaluée. Pour l'éprouver, il faut une identité qui **a** le droit de modifier un `Namespace` sans être exclue : donne-la **temporairement** et à blanc, puis retire-la.
   ```
   admin@adm01:~$ kubectl create clusterrole e17-essai-ns --verb=get,patch --resource=namespaces
   admin@adm01:~$ kubectl create clusterrolebinding e17-essai-ns --clusterrole=e17-essai-ns --user=oidc:lucas.martin
   admin@adm01:~$ kubectl label ns wb-essais pod-security.kubernetes.io/enforce=privileged --overwrite \
       --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   Error from server (Forbidden): namespaces "wb-essais" is forbidden: ValidatingAdmissionPolicy 'medisphere-etiquettes-espace-protegees'
   with binding 'medisphere-etiquettes-espace-protegees' denied request: étiquette(s) de sécurité de l'espace modifiée(s)
   hors du dépôt plateforme/k8s : pod-security.kubernetes.io/enforce (demande : oidc:lucas.martin)
   admin@adm01:~$ kubectl delete clusterrolebinding,clusterrole e17-essai-ns
   ```
   (Deux objets créés à la main pour un essai de quelques minutes, supprimés aussitôt et notés dans `~/m26/e17/` : c'est l'exception, pas la règle.) Une étiquette `essai=oui` passe.
6. **La MAP.** `failurePolicy: Ignore` (une valeur par défaut n'est pas un contrôle : si elle échoue, rien ne doit être bloqué) ; `reinvocationPolicy: Never` (la mutation ne dépend d'aucune autre). La liaison limite aux espaces qui portent `medisphere.internal/equipe`.
7. **Le piège de l'étape 7.** Écrite avec une seconde `matchCondition` « l'espace porte l'étiquette » (`'medisphere.internal/equipe' in namespaceObject.metadata.labels`), la MAP **ne fait rien**, sans un mot. En `failurePolicy: Fail`, le message apparaît :
   ```
   … policy 'medisphere-etiquette-equipe-par-defaut' … denied request: expression 'has(namespaceObject.metadata.labels) && …'
   resulted in error: no such key: metadata
   ```
   `namespaceObject` n'est pas renseigné à l'évaluation des `matchConditions` (il l'est dans les variables, validations et mutations) ; le sélecteur de la liaison fait déjà ce travail. Après correction :
   ```
   admin@adm01:~$ kubectl create --dry-run=server -n mediagenda-dev -f ~/m26/e17/pod-sans-etiquette.yaml -o jsonpath='{.metadata.labels}{"\n"}'
   {"app.kubernetes.io/name":"e17-essai","medisphere.internal/equipe":"mediagenda"}
   ```
8. **Chaîne d'admission.** Authentification → autorisation (RBAC) → **mutation** (contrôleurs intégrés comme `ServiceAccount`, puis `MutatingAdmissionPolicy`, puis webhooks de mutation : `seccomp-par-defaut` de Kyverno) → validation du schéma → **validation** (contrôleurs intégrés dont `PodSecurity`, puis `ValidatingAdmissionPolicy`, puis webhooks de validation : `ValidatingPolicy` de Kyverno) → écriture dans etcd. Les validations voient donc le pod **muté**. On ne mute que des pods : un Deployment muté diffère de Git, Argo CD le voit `OutOfSync` (ou le « corrige » à chaque synchronisation, et la MAP le re-mute : une boucle).
9. **Rapports.** `kubectl get policyreports -A -o json | jq '[.items[].results[]? | select(.source=="ValidatingAdmissionPolicy") | .policy] | unique'` : Kyverno 1.19 évalue en tâche de fond les VAP (fonction `validatingAdmissionPolicyReports`, active par défaut dans le chart 3.9) et y rapporte `medisphere-images` et `medisphere-interdire-hostpath`. Si les VAP paramétrées n'apparaissent pas, regarde les journaux du contrôleur de rapports (lecture de la ConfigMap de paramètres : ⚠️ à vérifier).
10. **Document** : voir le fichier ; sa règle de choix tient en une ligne : natif quand la règle ne dépend que de la requête, de l'espace et de paramètres et doit tenir sans Kyverno ; Kyverno pour les données externes, les rapports, les exceptions datées, la génération et les tests en CI.

**Explications**

Une VAP est compilée et évaluée **dans** le kube-apiserver : pas de réseau, pas de réplicas, pas de certificat de webhook. `failurePolicy` ne joue que sur les erreurs d'évaluation (expression qui échoue, paramètre introuvable selon `parameterNotFoundAction`), pas sur une indisponibilité. La MAP, GA en 1.36, applique un *apply configuration* (fusion façon *server-side apply*) ou un patch JSON calculé en CEL, sans webhook. Les deux voient `request.userInfo` : ce que Pod Security, qui ne regarde que l'objet et l'étiquette de son espace, ne peut pas faire.

**Alternatives**
- Pod Security avec `exemptions` dans l'`AdmissionConfiguration` du kube-apiserver (utilisateurs, espaces, `RuntimeClass` exemptés) : grossier, et demande de toucher au manifeste statique.
- Kyverno pour les trois règles : possible (même CEL), mais une panne de Kyverno désarmerait aussi la protection des étiquettes d'espace, celle qui protège… les espaces de Kyverno.
- Un espace par agent avec des RBAC plus stricts plutôt qu'une liste `hostPath` : complémentaire, pas suffisant (le chart décide des montages).

**Pièges classiques**
- Liaison sans `matchResources` : `kube-system` compris ; au prochain redémarrage d'un pod de Cilium dont un chemin manque, plus de réseau.
- `startsWith(a)` sans séparateur : `/proc` autorise `/procfoo`.
- `namespaceObject` dans une `matchCondition` + `failurePolicy: Ignore` : une politique qui ne fait rien, sans erreur.
- Tester l'étiquette d'espace avec une identité sans droit RBAC : le refus vient de RBAC, la VAP n'est pas éprouvée.
- Oublier que le contrôleur d'Argo CD applique des `Namespace` versionnés (M22 : `journaux`) : sans son exclusion, la prochaine modification d'étiquette par MR échoue à la synchronisation.

**En production chez MédiSphère**

Les trois politiques vivent avec `medisphere-images` dans `plateforme/k8s/admission/`, appliquées par `task appliquer` et vérifiées par le check à chaque MR. La ConfigMap `medisphere-hostpath` est revue avec le registre des exceptions (EXC-K-003, EXC-K-004) ; réduire les moteurs de conteneurs de Falco (seul containerd) retirerait `/var/run`, `/run/crio`, `/run/podman`. Une alerte sur l'annotation d'audit `validation.policy.admission.k8s.io/validation_failure` (Loki, locataire `audit`, E28) remonte les avertissements des VAP en mode `Warn`.

**Ce qui reste promis** : la VAP qui refuserait les `CiliumNodeConfig` hors du compte d'automatisation (M15) et celle qui refuserait un RoleBinding donnant `pods/exec` à un sujet hors de l'équipe (M22) ne sont pas écrites ici ; elles suivent exactement le modèle de `medisphere-etiquettes-espace-protegees` (`request.userInfo`, `object.subjects`) et sont proposées au mini-projet (E46).

---

### M26-E18 — Exceptions et rapports de politiques

**Solution**

Fichiers : valeurs [`kyverno` (extrait)](fichiers/M26-E18/gitops/valeurs/kyverno/values.yaml.extrait-E18), [AppProject (extrait)](fichiers/M26-E18/gitops/projets/plateforme.extrait-E18.yaml), [espace](fichiers/M26-E18/k8s/espaces/kyverno-exceptions.yaml), [`exiger-digest` (version E18)](fichiers/M26-E18/politiques/kyverno/validation/exiger-digest.yaml), [exception](fichiers/M26-E18/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml), [`kustomization.yaml` des exceptions](fichiers/M26-E18/politiques/kyverno/exceptions/kustomization.yaml) et [ligne de la racine](fichiers/M26-E18/politiques/kustomization.extrait-E18.yaml), [test](fichiers/M26-E18/politiques/kyverno/tests/exiger-digest-exception/), [`verifier-exceptions.sh`](fichiers/M26-E18/politiques/outils/verifier-exceptions.sh), [CI (extrait)](fichiers/M26-E18/politiques/.gitlab-ci.yml.extrait-E18), [valeurs du chart `mediagenda` (extrait)](fichiers/M26-E18/chart/values.yaml.extrait-E18), [règles](fichiers/M26-E18/observabilite/regles/politiques-admission.yaml) et [tests](fichiers/M26-E18/observabilite/tests/politiques-admission.test.yaml), [tableau](fichiers/M26-E18/observabilite/tableaux/plateforme/plateforme-politiques-admission.json) et [entrée du `kustomization`](fichiers/M26-E18/observabilite/tableaux/kustomization.extrait-E18.yaml).

1. **Rapports.** Deux familles d'échecs : `exiger-limites` sur le pod `valkey` de `mediagenda-dev` (conteneur d'initialisation sans ressources), `exiger-digest` sur `mediagenda-db-1..3` de `mediagenda-prod`. Les rapports (`wgpolicyk8s.io/v1alpha2`, un `PolicyReport` par ressource, champ `scope`) sont produits par le contrôleur de rapports à partir de l'analyse de fond ; ils montrent l'**existant**, y compris ce qui a été admis avant le passage en `Deny`.
2. **Valkey : on corrige.** `helm show values oci://registry.par1.medisphere.internal/charts/valkey --version 0.12.0 | grep -n initResources` → la clé existe. MR sur `mediagenda/chart` ([extrait](fichiers/M26-E18/chart/values.yaml.extrait-E18)), version mineure du chart, promotion. Réponse à Julien : « exception refusée : correction disponible (`valkey.initResources`), livrée dans le chart 0.x.y ». Ligne « close / refusée » au registre.
3. **PostgreSQL de la prod : on planifie.**
   ```
   admin@adm01:~$ kubectl -n mediagenda-prod get pod mediagenda-db-1 -o jsonpath='{range .spec.initContainers[*]}{.name}={.image}{"\n"}{end}{range .spec.containers[*]}{.name}={.image}{"\n"}{end}'
   bootstrap-controller=registry.par1.medisphere.internal/ghcr/cloudnative-pg/cloudnative-pg:1.30.1
   postgres=registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:18.6-minimal-trixie
   admin@adm01:~$ kubectl -n cnpg-system get deploy -o jsonpath='{..env[?(@.name=="OPERATOR_IMAGE_NAME")].value}{"\n"}'
   ```
   `postgres` vient du `Cluster` (`spec.imageName`) : corrigeable dans le dépôt de l'application (E21). `bootstrap-controller` vient de l'**opérateur** (`OPERATOR_IMAGE_NAME`) : le corriger, c'est redéployer l'opérateur de la couche de base (Helmfile) avec une image par condensé, ce qui redémarre **toutes** les instances de **tous** les clusters CNPG. Un changement planifié (`CHG-2718`), pas une MR de cinq minutes ; d'ici là, une exception.
4. **Activation.** `features.policyExceptions.enabled: true`, `namespace: kyverno-exceptions`. Sans le drapeau, une `PolicyException` est acceptée par l'API… et ignorée. Avec `*`, Kyverno lirait les exceptions de **tous** les espaces : une équipe qui a `edit` dans son espace pourrait désactiver une politique pour elle-même. Un espace dédié, où seule l'Application `politiques` écrit, fait de chaque exception une MR relue.
5. **Exception partielle.** Le moteur des `ValidatingPolicy` (1.19.2) distingue : exception **sans** `images` ni `allowedValues` → la politique est **sautée** pour l'objet ; exception **avec** `images` → la politique s'évalue, et l'expression peut lire `exceptions.allowedImages`. Une ligne dans `variables.sansCondense` : `&& !(i in exceptions.allowedImages)`. Pour une `ImageValidatingPolicy`, la 1.19.1 a **désactivé** les exceptions partielles (elles exemptaient toutes les images du pod) : seule l'exception totale existe, à manier avec des `matchConditions` serrées.
6. **L'exception** ([fichier](fichiers/M26-E18/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml)) : `policyRefs` (nom **et** `kind`), `matchConditions` (espace `mediagenda-prod`, étiquettes `cnpg.io/cluster` et `cnpg.io/podRole=instance`), `images` (l'image exacte de l'opérateur), `expiresAt` (⚠️ adapte la date : aujourd'hui + 60 à 90 jours, un jour ouvré), `reportResult: skip` (visible dans les rapports, pas maquillé en `pass`), `properties`. Test :
   ```
   admin@adm01:~/src/politiques$ kyverno test kyverno/tests/exiger-digest-exception
   │ 1  │ exiger-digest │ │ v1/Pod/mediagenda-prod/instance-cnpg-postgres-par-condense  │ Pass │ Ok │
   │ 2  │ exiger-digest │ │ v1/Pod/mediagenda-prod/instance-cnpg-postgres-par-etiquette │ Pass │ Ok │
   │ 3  │ exiger-digest │ │ v1/Pod/mediagenda-prod/api-image-operateur                  │ Pass │ Ok │
   Test Summary: 3 tests passed and 0 tests failed
   ```
   (« Pass » dans la colonne RESULT = le résultat attendu est obtenu : `pass` pour le premier, `fail` pour les deux autres.)
7. **CI.** [`verifier-exceptions.sh`](fichiers/M26-E18/politiques/outils/verifier-exceptions.sh) est en sh POSIX (l'image d'E07 est une Alpine sans bash) ; les dates sont comparées comme des chaînes au même format UTC, « dans 92 jours » vient de `date -u -d @<secondes>`. Essai d'échec :
   ```
   ÉCHEC  cnpg-operateur-sans-condense.yaml : échéance 2028-01-01T00:00:00Z au-delà de 92 jours
   ÉCHEC  cnpg-operateur-sans-condense.yaml : aucune matchCondition : l'exception vaudrait pour tout le cluster
   ÉCHEC  cnpg-operateur-sans-condense.yaml : valideur non autorisé : lucas.martin (autorisés : sophie.laurent)
   ```
   Le pipeline planifié du lundi (Build → Pipeline schedules, variable `PLANIFIE=exceptions`) échoue 14 jours avant une échéance : GitLab envoie le courriel d'échec. **La CLI `kyverno` ignore `expiresAt`** : une exception échue est encore appliquée par `kyverno apply` et `kyverno test` (constaté en 1.19.2). C'est une raison de plus de contrôler les dates soi-même.
8. **Constat.**
   ```
   admin@adm01:~$ kubectl get policyreports -n mediagenda-prod -o json | jq -r '.items[] | .scope.name as $o
       | .results[]? | select(.policy=="exiger-digest") | "\($o) \(.result) \(.message)"'
   mediagenda-db-1 skip rule is skipped due to policy exception: kyverno-exceptions/cnpg-operateur-sans-condense
   ```
   (Le texte exact du message dépend du moteur : ⚠️ à relire chez toi.) Si `postgres` est encore par étiquette, le résultat reste `fail` : c'est voulu (E21 le corrige).
9. **Règles.** Le piège : `execution_cause="background_scan"` incrémente le compteur à **chaque** analyse de fond, tant que l'objet reste non conforme (un état déguisé en compteur) ; d'où `increase(...[2h]) > 0` (« encore vu récemment ») plutôt qu'un `rate`. `PolitiqueRefusEnRafale` ne regarde que les politiques en `Deny` (en `Audit`, un échec n'est pas un refus). Tests `promtool` : rafale en recette (alerte), même débit en `Audit` (pas d'alerte), violation de fond en prod (alerte) et en recette (pas d'alerte).
10. **Tableau** : quatre statistiques (refus de l'heure, couples politique/espace de prod non conformes, politiques en erreur, exemptions), puis refus et échecs `Audit` par politique et espace, violations de fond, latence p95 (une politique lente ralentit **toutes** les créations de pods de son périmètre).

**Explications**

Une `PolicyException` CEL est compilée **avec** la politique qu'elle vise : le moteur recompile la politique quand une exception change, et c'est à ce moment qu'il écarte celles qui sont échues. Les `matchConditions` d'une exception s'évaluent sur la même requête que la politique (`object`, `oldObject`, `request`, `namespaceObject`). Sans `images`, l'exemption est totale ; avec, elle est partielle et dépend de la politique. Le registre et la CI donnent ce que Kyverno ne donne pas : qui a validé, pourquoi, jusqu'à quand, et la garantie qu'une exception trop large n'arrive jamais dans le cluster.

**Alternatives**
- Exclure par le `matchConstraints` de la politique (sélecteur d'étiquettes) : invisible dans les rapports, sans échéance ; à réserver aux exclusions de conception (ex. `kube-system`).
- Annotation de dérogation sur l'objet lu par la politique : l'équipe se l'accorde elle-même ; non.
- Policy Reporter (Kyverno) pour les tableaux et notifications des rapports : plus riche par ressource, un composant de plus à exploiter.

**Pièges classiques**
- Oublier `features.policyExceptions.enabled` : l'exception « marche » dans `kyverno test` et pas dans le cluster.
- Exception posée dans un autre espace que `kyverno-exceptions` : acceptée par l'API, ignorée par Kyverno.
- `policyRefs` avec le bon nom et le mauvais `kind` (`ClusterPolicy` au lieu de `ValidatingPolicy`) : aucune correspondance, aucune erreur.
- Exception partielle (`images`) sur une politique qui ne lit pas `exceptions.allowedImages` : sans effet ; sur une `ImageValidatingPolicy` : ignorée depuis la 1.19.1.
- Se fier à `kyverno test` pour l'échéance (la CLI l'ignore).
- Alerter sur un `rate` de `background_scan`.

**En production chez MédiSphère**

Les exceptions sont revues chaque mois avec le registre (E23) ; le tableau `politiques-admission` est projeté à la revue hebdomadaire de la plateforme ; `CHG-2718` (opérateur CNPG par condensé) ferme EXC-K-001. Une alerte sur l'échéance proche pourrait venir de kube-state-metrics (*custom resource state* sur `spec.expiresAt`) plutôt que du pipeline planifié : à évaluer quand les exceptions seront plus nombreuses.

---

### M26-E19 — Falco : règles de MédiSphère et acheminement des alertes

**Solution**

Fichiers : [règles](fichiers/M26-E19/politiques/falco/regles-medisphere.yaml), [`valider-falco.sh`](fichiers/M26-E19/politiques/outils/valider-falco.sh), [CI (extrait)](fichiers/M26-E19/politiques/.gitlab-ci.yml.extrait-E19), [valeurs de Falco (extrait)](fichiers/M26-E19/gitops/valeurs/falco/values.yaml.extrait-E19), [Application `falco`](fichiers/M26-E19/gitops/plateforme/falco.yaml), [routage (extrait)](fichiers/M26-E19/observabilite/kps/alertmanager-falco.extrait-E19.yaml), [RB-260](fichiers/M26-E19/medisphere/docs/securite/durcissement/runbooks/RB-260-alerte-falco.md).

1. **Lire les macros.** `container` : `container.id != host` ; `container_entrypoint` : processus sans parent ou dont le parent est le runtime (`runc`…) ; `open_read`/`open_write` : ouvertures **réussies** (`fd.num>=0`). `outbound` exclut toute destination RFC 1918 : `10.240.x.y → 10.10.20.18:443` n'est **pas** « sortant » pour elle, ni rien d'autre dans le lab. Chemin de l'exécutable : `proc.exepath` ; port de destination : `fd.sport` (port du **serveur**, même vu du client).
2. **Port vu.** Le remplacement de kube-proxy de Cilium traduit l'adresse du Service dans le `connect()` lui-même (programme eBPF de socket) : Falco voit l'adresse et le port du **pod** (8000), pas 80. Les deux sont dans la liste (le 80 pour les Services sans traduction, ex. vers la passerelle). ⚠️ À vérifier sur ton lab avec un événement réel.
3. **Les règles.** Six règles, chacune avec périmètre (`medisphere_espace_applicatif`, `medisphere_production`), exceptions (listes `medisphere_*`, macro `medisphere_exec_prod_attendu` à `never_true`), sortie lisible. Points de conception :
   - jeton : `fd.name pmatch (medisphere_chemins_jeton)` avec `/var/run/…` **et** `/run/…` (le chemin demandé par le processus) ; `manager` (CNPG) dans la liste ;
   - `/etc` : la condition **ne** reprend **pas** `open_write` ; elle prend toute ouverture en écriture (`evt.is_open_write=true`), réussie ou non : avec `readOnlyRootFilesystem`, la tentative échoue (`EROFS`), et c'est elle qui est intéressante ; `%evt.res` dans la sortie ;
   - port non prévu : `evt.type = connect`, sans condition de succès (une tentative bloquée par la politique réseau est un signal) ;
   - `/tmp` : `proc.exepath pmatch (medisphere_repertoires_temporaires)` ; un `emptyDir` n'est pas `noexec` ;
   - exec en production : `container_entrypoint and proc.vpid != 1` (lancé par le runtime, mais pas le processus principal). Une sonde `exec` déclencherait aussi : MédiAgenda et MédiDoc n'ont que des sondes HTTP ; sinon, la macro `medisphere_exec_prod_attendu`.
4. **CI.** Deux jobs : `falco:conventions` (Alpine d'E07 + yq vérifié par empreinte : extraction et conventions, artefact `regles-extraites/`) puis `falco:valider` (image officielle de Falco **de la version du cluster**) :
   ```
   admin@adm01:~/src/politiques$ sh outils/valider-falco.sh conventions
   conventions : OK (6 règles) → regles-extraites/regles-medisphere.yaml
   ```
   Le second temps tourne dans le job `falco:valider` ; en local, avec le binaire de l'archive amont (`falco-0.45.1-x86_64.tar.gz`, dépliée dans `~/m26/e19/falco/`, `library_path` du greffon `container` ajusté dans sa configuration) :
   ```
   admin@adm01:~/src/politiques$ F=~/m26/e19/falco/falco-0.45.1-x86_64
   admin@adm01:~/src/politiques$ FALCO=$F/usr/bin/falco FALCO_CONFIG=$F/etc/falco/falco.yaml \
       FALCO_REGLES_DEFAUT=$F/etc/falco/falco_rules.yaml sh outils/valider-falco.sh moteur
   …/etc/falco/falco_rules.yaml: Ok
   regles-extraites/regles-medisphere.yaml: Ok
   ```
   Sans le greffon : `Error: Plugin requirement not satisfied, must load one of: container (>= 0.4.0)` (les règles par défaut l'exigent). Une faute (`fd.nom`) : `LOAD_ERR_COMPILE_CONDITION`, ligne et colonne.
5. **Livraison.** Application à **trois** sources (chart, `plateforme/gitops` pour les valeurs, `plateforme/politiques` pour les règles) ; `kubectl -n falco get cm falco-rules -o jsonpath='{.data}' | grep -c 'rule: MédiSphère'` → 6 ; les pods redémarrent un à un (somme `checksum/rules`). Valeurs : `append_output` (gravité d'après l'étiquette ; la première entrée reprend le défaut `suggested_output`), `falco.priority: notice`, et côté falcosidekick `extralabels: equipe:plateforme,alertname:AlerteFalco` (**sans** la `gravite` fixe d'E08 : falcosidekick applique ses `extralabels` après les champs de sortie, elle écraserait celle de la règle) et `expireafter: 1800` (une alerte Falco est un événement : sans échéance, elle resterait active).
6. **Essais** (pod `falco-essai` de `wb-essais`) :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec -it falco-essai -- bash
   root@falco-essai:/# cat /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null   # si un jeton est monté
   root@falco-essai:/# touch /etc/essai ; cp /bin/ls /tmp/x && /tmp/x
   root@falco-essai:/# timeout 3 bash -c '</dev/tcp/10.10.20.19/2222'
   ```
   Loki (`loki-audit`) : `{service="falco", rule=~"MédiSphère.*"} | json` ; une ligne par règle, avec `output_fields_k8s_pod_name`. Alertmanager : alertes `AlerteFalco`, `rule="MédiSphère — …"`, `gravite="critique"` pour le jeton, `/etc` et `/tmp`.
7. **Bruit d'une journée** (typique) : « lecture du jeton » par les instances CNPG (`manager`, déjà exclu ; sinon c'est la première exception), « port non prévu » vers `9187` si un exportateur interroge… à toi de lire ; chaque traitement = un élément de liste + une ligne au registre (EXC-D-…).
8. **Routage** (`amtool` 0.34.1 sur la configuration rendue) :
   ```
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco gravite=critique priority=Critical
   astreinte-mail,securite-mail
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco gravite=avertissement priority=Warning
   securite-mail
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco priority=Critical
   astreinte-mail,securite-mail
   ```
9. **RB-260** : voir le fichier ; l'essentiel est la décision en 15 minutes et la règle « on isole, on ne supprime pas » (les preuves sont dans le pod).

**Explications**

Falco évalue chaque événement du noyau contre des conditions compilées ; les macros et listes sont des fragments réutilisables, surchargeables par `override: {items: append}` ou `{condition: append|replace}` dans un fichier chargé après. Garder nos règles dans un fichier à nous, et les exceptions dans **nos** listes, évite d'éditer les règles amont (perdues à la montée de version). falcosidekick reçoit le JSON de Falco (`http_output`) et le distribue : chaque champ de sortie devient une étiquette d'alerte (d'où le regroupement par règle et par pod) et, pour Loki, les champs choisis deviennent des étiquettes (`k8s_ns_name`, `k8s_pod_name`, `rule`, `priority`, `service`).

**Alternatives**
- Laisser falcoctl suivre les règles amont depuis Internet : refusé (E08), les règles changent par MR.
- `customRules` dans les valeurs du dépôt `plateforme/gitops` : possible, mais les règles se relisent avec les politiques (même équipe, même CI).
- ConfigMap générée par Kustomize et montée : sans somme de contrôle, Falco ne redémarre pas de façon fiable au changement.

**Pièges classiques**
- `outbound` dans un réseau privé : ne voit rien.
- `open_write` pour un système de fichiers en lecture seule : ne voit pas les tentatives.
- Désactiver une règle bruyante : la détection disparaît pour tout le monde ; la bonne réponse est une exception ciblée.
- Alertmanager v1 (`/api/v1/alerts`) : 404 depuis la 0.27.
- `extralabels` qui écrase un champ de la règle.

**En production chez MédiSphère**

Une revue mensuelle du bruit par règle (requête de RB-260), un exercice sur table trimestriel (E33), et la règle d'or : aucune MR de règles pendant un incident. Le greffon `k8saudit` (journal d'audit de l'API dans Falco) est une piste pour la règle « exec en production » : il dirait **qui** ; en attendant, E28 le fait par le ruler de Loki.

---

### M26-E20 — Tetragon : observer processus, fichiers et réseau

**Solution**

Fichiers : [Application](fichiers/M26-E20/gitops/plateforme/tetragon.yaml), [valeurs](fichiers/M26-E20/gitops/valeurs/tetragon/values.yaml), [AppProject (extrait)](fichiers/M26-E20/gitops/projets/plateforme.extrait-E20.yaml), [espace](fichiers/M26-E20/k8s/espaces/tetragon.yaml), [`wb-checks-securite` (extrait)](fichiers/M26-E20/k8s/rbac/wb-checks-securite.extrait-E20.yaml), politiques [`observer-exec`](fichiers/M26-E20/politiques/tetragon/observer-exec.yaml), [`fichiers-sensibles`](fichiers/M26-E20/politiques/tetragon/fichiers-sensibles.yaml), [`connexions-sortantes`](fichiers/M26-E20/politiques/tetragon/connexions-sortantes.yaml), [`kustomization.yaml`](fichiers/M26-E20/politiques/tetragon/kustomization.yaml) et [ligne de la racine](fichiers/M26-E20/politiques/kustomization.extrait-E20.yaml), [Alloy (extrait)](fichiers/M26-E20/observabilite/alloy/config.alloy.extrait-E20), [requêtes](fichiers/M26-E20/observabilite/requetes/tetragon-falco.logql).

1. **Rendu.** DaemonSet `tetragon` (conteneurs `tetragon` et `export-stdout`), Deployment `tetragon-operator` (installe et met à jour les CRD : `crds.installMethod: operator`), `hostNetwork: true`, tolérance universelle (`operator: Exists` : nœuds de contrôle compris), montages `/proc`, `/sys/fs/bpf`, `/var/run/cilium`, `/var/run/tetragon` — ceux de la clé `tetragon` d'E17, sinon le DaemonSet serait refusé.
2. **Installation** : espace `privileged`, Application, destination dans l'AppProject. `kubectl -n tetragon get ds tetragon` : six prêts.
3. **Sans politique**, un `process_exec` contient le binaire, les arguments, le répertoire courant, l'UID, le **parent** (et, avec `enableProcessCred`, les capacités), le pod (nom, espace, étiquettes, conteneur, image par condensé). `tetra getevents` interroge l'agent **local** : prends le pod Tetragon du nœud du pod d'essai. Volume brut : de l'ordre de plusieurs milliers de lignes par minute et par travailleur (sondes, scripts des images, CNPG) ; ⚠️ mesure le tien.
4. **Filtre d'export** : exécutions des seuls espaces applicatifs (`namespace_regex`), événements de nos politiques partout (`policy_names`), refus par défaut conservés (l'**hôte** est exclu : c'est le travail d'auditd, E12). Ordre de grandeur attendu : division par 10 à 50.
5. **Les politiques.**
   - `observer-exec` : `security_bprm_check` est le crochet LSM appelé à chaque `execve`, **avant** le chargement du binaire, avec le `linux_binprm` (fichier réellement exécuté, liens résolus) ; l'appel système, lui, ne donne que le chemin demandé. C'est aussi là qu'un `Sigkill` (E29) arrête l'exécution.
   - `fichiers-sensibles` : `security_file_permission(file, mask)` à chaque lecture/écriture. Chemin résolu par rapport à la racine du processus : `/etc/shadow` du conteneur, pas celui de l'hôte. Deux préfixes pour les jetons : si `/var/run` est un lien vers `/run` dans l'image, le runtime a monté le volume sous `/run/secrets/…`, et c'est ce chemin que le noyau rend. `rateLimit: 1m` : un client Kubernetes relit son jeton périodiquement (chaque lecture serait un événement).
   - `connexions-sortantes` : `tcp_connect(sock)`, `NotDAddr` des pods, des Services et de la boucle : reste ce qui **sort** (VMs, Internet). Avec le remplacement de kube-proxy, une destination de Service est déjà traduite en pod.
6. **Essais.** `tetra tracingpolicy list` : trois politiques `enabled`. Événements : `process_kprobe` avec `function_name: security_bprm_check` et `linux_binprm_arg.path: /tmp/x` ; `file_arg.path: /var/run/secrets/kubernetes.io/serviceaccount/..2026_…/token` ; `sock_arg.daddr: 10.10.20.18`, `dport: 443`.
7. **Alloy** : deux règles de `discovery.relabel` sur `espace/conteneur`. Vérification :
   ```
   admin@adm01:~$ logcli query --org-id=audit '{service="tetragon"}' --since=10m --limit=3
   admin@adm01:~$ logcli query --org-id=plateforme '{namespace="tetragon", container="export-stdout"}' --since=10m --limit=3   # vide
   ```
8. **Requêtes** : voir le fichier. La corrélation la plus simple est le nom du pod et la minute ; l'arbre complet se lit en remontant `process_exec_parent_exec_id` (Falco n'a que `proc.pname` et `proc.aname[n]`).
9. **Comparaison** (proposition pour `~/m26/e20/comparaison.md`) :

   | | Falco | Tetragon |
   |---|---|---|
   | Ce qu'il observe | appels système (pilote eBPF) + contexte du conteneur | fonctions du noyau choisies (kprobes, crochets LSM, tracepoints) |
   | Langage | règles (conditions sur des champs) | politiques (fonction, arguments, sélecteurs) |
   | Points forts | catalogue de règles, sorties, sens « métier » des alertes | arbre des processus, identité Kubernetes native, action **dans** le noyau (E29) |
   | Coût mesuré | ⚠️ ton relevé (E08 : 200-300 Mo par nœud) | ⚠️ ton relevé |
   | Rôle chez MédiSphère | **alerter** | **expliquer** (et bloquer, au cas par cas) |

**Explications**

Tetragon attache des programmes eBPF aux fonctions désignées et filtre **dans le noyau** (sélecteurs) avant de remonter l'événement : ce qui n'est pas sélectionné ne coûte presque rien en espace utilisateur. Le cache de processus (`processCacheSize`) relie chaque événement à son `exec_id` et à celui de son parent : c'est ce qui permet l'arbre. L'export est la seule voie vers les journaux : le filtrer, c'est choisir ce qu'on gardera un an.

**Alternatives**
- `TracingPolicyNamespaced` par espace applicatif : périmètre plus étroit, mais une par espace, et le droit d'en créer doit rester à la plateforme.
- Hubble (Cilium) pour le réseau : il voit les flux au niveau L3-L7, pas le processus qui les ouvre ; complémentaire.
- Recevoir les événements par gRPC (`tetra`) plutôt que par fichier : pour un SIEM, l'export JSON suffit.

**Pièges classiques**
- Sélecteur trop large sur `security_file_permission` : charge sur tous les nœuds.
- Un seul préfixe `/var/run/secrets/…` : les images où `/var/run` est un lien échappent.
- Croire que `tetra getevents` voit tout le cluster.
- Oublier la clé `tetragon` dans la ConfigMap `hostPath` d'E17 : DaemonSet refusé.
- Laisser les événements dans le locataire `plateforme` (14 jours) : ils doivent vivre un an dans `audit`.

**En production chez MédiSphère**

Tetragon et Falco restent tous les deux : Falco alerte, Tetragon explique et, au cas par cas, bloque (E29). Les politiques sont revues avec les règles Falco ; le volume exporté est suivi par une alerte de capacité sur le locataire `audit` (M22-E14).

---

### M26-E21 — Des charges sûres par construction

**Solution**

Fichiers : [outil](fichiers/M26-E21/k8s/outils/audit-charges-sures.sh), [norme](fichiers/M26-E21/medisphere/docs/securite/durcissement/charges-sures.md), [gabarits `medisphere-commun` (extrait)](fichiers/M26-E21/chart/charts/medisphere-commun/templates/_commun.tpl.extrait-E21), [valeurs `mediagenda` (extrait)](fichiers/M26-E21/chart/charts/mediagenda/values.yaml.extrait-E21), [overlay de prod (extrait)](fichiers/M26-E21/deploiement/overlays/prod/kustomization.extrait-E21.yaml), [MédiDoc (extrait)](fichiers/M26-E21/medidoc-deploiement/base/deployment.extrait-E21.yaml).

1. **Mesure.**
   ```
   admin@adm01:~/src/k8s$ outils/audit-charges-sures.sh
   mediagenda-prod  mediagenda-db-1   bootstrap-controller  C7 image sans condensé
   mediagenda-prod  mediagenda-db-1   postgres              C7 image sans condensé
   mediagenda-prod  valkey-0          valkey                C7 image sans condensé
   mediagenda-recette …
   ```
   (Extrait type ; tes écarts dépendent de ton histoire.) C6 par le volume projeté : `automountServiceAccountToken` peut être faux sur le **ServiceAccount** et absent du pod ; ce qui compte, c'est le résultat (le contrôleur `ServiceAccount` a-t-il injecté `kube-api-access-*` ?). Classement typique : C7 sur les dépendances (overlay), C5 AppArmor non écrit (gabarits), C6 sur les pods de CNPG (exception), C3 sur les Jobs de test.
2. **Écrit ou par défaut.** Dans le pod en service, `seccompProfile` est là même si le manifeste ne l'écrit pas (`seccomp-par-defaut`, E16), `medisphere.internal/equipe` aussi (MAP, E17), le volume du jeton aussi (si le ServiceAccount ne l'interdit pas). AppArmor : containerd applique son profil par défaut quand AppArmor est actif sur le nœud, mais rien ne le dit dans le pod : on l'écrit (C5).
3. **Norme** : voir le fichier ; elle relie chaque critère à son mécanisme d'application (Pod Security, Kyverno, chart).
4. **MédiAgenda.** `medisphere-commun` 0.2.0 : `runAsUser`/`runAsGroup` (valeur `medisphere.uid`, 10001), `appArmorProfile: RuntimeDefault` ; `/tmp` en `emptyDir` avec `sizeLimit` ; nouvelle version du chart, rendu commité (M17), promotion. Overlay de prod : `images` de Kustomize pour l'API et Valkey (condensé), **patch** pour `spec.imageName` du `Cluster` (le transformateur `images` ne connaît pas ce champ). ⚠️ Changer `imageName` déclenche la mise à jour progressive des instances : fenêtre de changement. Le conteneur `bootstrap-controller` reste couvert par l'exception d'E18 jusqu'à `CHG-2718`.
5. **MédiDoc.** Déjà conforme sur C1-C6 et C8 ; AppArmor écrit. Pas de `/tmp` : l'application lit les téléversements en flux (`MultipartReader`), sans fichier temporaire. Ajouter un `emptyDir` « au cas où » ouvrirait un emplacement inscriptible et exécutable inutile.
6. **Preuves.**
   ```
   admin@adm01:~/src/k8s$ outils/audit-charges-sures.sh
   Aucun écart : toutes les charges des espaces /^(mediagenda|medidoc)-/ respectent la norme.
   admin@adm01:~$ helm template mediagenda ~/src/chart/charts/mediagenda -f … | kubectl apply --dry-run=server -n mediagenda-recette -f -
   ```
   Aucun `Warning: would violate PodSecurity` ; `kubectl get policyreports -n mediagenda-prod` : aucun `fail`.

**Explications**

L'admission dit « pas pire que » ; la norme dit « au moins ». Mesurer les pods **en service** attrape ce que les manifestes ne montrent pas : ajouts de l'admission, pods d'opérateurs, sous-charts, conteneurs d'initialisation. Écrire explicitement ce qui serait appliqué par défaut rend la conformité **vérifiable** par un outil qui lit le manifeste (kube-bench, kubescape, un auditeur).

**Alternatives**
- kubescape en continu (opérateur) : constats plus larges (cadres NSA, MITRE), plus de bruit, un composant de plus.
- Une `ValidatingPolicy` « charge sûre » en `Deny` qui reprend C1-C8 : pertinente une fois les écarts à zéro, en complément de Pod Security.
- Profils seccomp `Localhost` par application : gain réel, entretien coûteux ; plus tard, sur mesure.

**Pièges classiques**
- Juger sur le dépôt et pas sur le pod.
- Un UID explicite différent de celui de l'image : fichiers de l'image illisibles.
- `emptyDir` sans `sizeLimit` : un disque de nœud plein évince tous ses pods.
- Kustomize `images` sur un champ d'une CRD : rien ne change, sans erreur.

**En production chez MédiSphère**

`audit-charges-sures.sh` tourne chaque nuit (CronJob en lecture seule, ou job planifié de `plateforme/k8s`) et alimente une métrique d'écarts par espace ; le gabarit de projet du M28 part de `medisphere-commun` 0.2.0.

---

### M26-E22 — Revue : les manifestes et le Dockerfile du stagiaire

**Proposition** : [`revue.md`](fichiers/M26-E22/revue.md) (19 défauts, gravités, commentaire de revue) et la version corrigée [`inventaire-images/`](fichiers/M26-E22/inventaire-images/) : [Dockerfile](fichiers/M26-E22/inventaire-images/Dockerfile), [values.yaml](fichiers/M26-E22/inventaire-images/values.yaml), [Deployment](fichiers/M26-E22/inventaire-images/manifestes/deployment.yaml), [Service](fichiers/M26-E22/inventaire-images/manifestes/service.yaml), [RBAC](fichiers/M26-E22/inventaire-images/manifestes/rbac.yaml), [politique réseau](fichiers/M26-E22/inventaire-images/manifestes/networkpolicy.yaml), [ExternalSecret](fichiers/M26-E22/inventaire-images/manifestes/externalsecret.yaml), [espace](fichiers/M26-E22/k8s/espaces/inventaire.yaml).

**Les points qui comptent**
1. **Sept bloquants** : jeton en clair dans Git et dans l'image ; socket de containerd ; `privileged` ; rôle `*` ; `hostNetwork` ; page des vulnérabilités publiée sans authentification. Chacun, seul, donne soit le nœud, soit le cluster, soit le registre.
2. **Le besoin réel** de Lucas (« lister les images plus vite ») se satisfait par l'API : `status.containerStatuses[].imageID` donne le condensé exécuté. Tout le reste (socket, privilèges, réseau de l'hôte) disparaît avec ce changement de conception : c'est la correction qui compte, pas la liste de réglages.
3. **Le jeton** : supprimer la ligne ne suffit pas. Il est dans l'historique de Git et dans les couches de l'image poussée. Ordre (RB-250) : révoquer le robot dans Harbor (ou régénérer son secret), créer le nouveau dans OpenBao, vérifier dans le journal d'audit de Harbor que l'ancien n'a pas servi depuis la MR, supprimer l'image exposée et ses copies, puis seulement nettoyer le dépôt (et Gitleaks aurait dû le voir : le composant `qualite` est-il dans la CI de ce projet ?).
4. **Erreurs ou choix** : erreurs = ce qui contredit une règle écrite (normes de conteneurs M12, norme « charge sûre », matrice des flux, politique des secrets) ; choix = la publication de la page, la fréquence d'interrogation de Harbor.
5. **Validation de la version corrigée** : à blanc dans un espace `restricted` et `kyverno apply` avec les politiques de `plateforme/politiques` (`registres-autorises`, `exiger-limites`, `exiger-etiquettes`) : aucun refus.

**Pièges classiques**
- Relever les défauts un par un sans voir qu'ils viennent d'**un** mauvais choix de conception (le socket).
- « Corriger » le rôle en listant toutes les ressources qui donnaient `Forbidden` : c'est le code qui faisait des appels inutiles.
- Une `NetworkPolicy` standard avec `ipBlock` vers l'API : Cilium ne fait pas correspondre par défaut les adresses des nœuds à un CIDR (identités réservées) ; `toEntities: [kube-apiserver]` d'une `CiliumNetworkPolicy` est exact.
- Remplacer `privileged` par une liste de capacités « au cas où ».

**En production chez MédiSphère**

La grille de cette revue rejoint le modèle de MR des projets de la plateforme ; Gitleaks et `kyverno apply` tournent sur chaque MR ; un nouvel outil interne part du gabarit `medisphere-commun` et d'un espace créé par la plateforme, jamais de `default`.

---

### M26-E23 — Registre des exceptions et procédure de dérogation

**Proposition** : [`exceptions.md`](fichiers/M26-E23/medisphere/docs/securite/durcissement/exceptions.md) et [`RB-261-derogation.md`](fichiers/M26-E23/medisphere/docs/securite/durcissement/runbooks/RB-261-derogation.md).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Exhaustivité | Toutes les exceptions codées du module sont au registre : `durcissement_exceptions` (E10-E14), espaces `privileged` et `baseline` (E06), liste `hostPath` (E17), `PolicyException` (E18), listes Falco (E19), norme « charge sûre » (E21) ; et inversement, chaque ligne dit **où** l'exception est codée |
| Précision | Règle exacte (identifiant XCCDF complet, nom de politique et `kind`, nom de règle Falco), périmètre le plus étroit (hôte, espace, étiquettes, image, binaire) |
| Risque et compensation | Le risque résiduel est une phrase concrète (« un pod de ces espaces a les droits de l'hôte »), pas « risque faible » ; chaque risque a une compensation qui existe vraiment (VAP, Tetragon, auditd…) |
| Dates | Revue ≤ 3 mois pour le temporaire, ≤ 12 mois pour le permanent ; aucune exception sans date |
| Validation | Un valideur nommé (Sophie Laurent ; Claire Morel en suppléance) ; la validation **est** l'approbation de la MR |
| Procédure | Avant la demande : chercher la correction ; tableau « mécanisme → où et comment coder » pour les cinq mécanismes ; contrôles de la CI ; vérification après fusion (objet exempté accepté, objet hors périmètre toujours refusé) ; urgence (7 jours max, MR dans l'heure) ; échéance (pipeline planifié, effet à la date) ; retrait (vérifier la conformité **avant**) |
| Revue | Fréquence, participants, comparaison registre ↔ code (commandes), indicateurs (nombre, âge, prolongations) |
| Lien avec l'audit HDS | On peut répondre aux quatre questions de Sophie en ouvrant **un** fichier |

**Explications**

Un auditeur ne reproche pas d'avoir des exceptions ; il reproche de ne pas les connaître. Le registre est la vue humaine, le code est la vérité exécutée : la valeur vient de leur **concordance**, contrôlée chaque mois et, pour Kyverno, à chaque MR. L'échéance oblige à redécider ; la compensation montre que le risque a été pensé.

**Pièges classiques**
- Un registre qui décrit des intentions (« on va exclure… ») au lieu de ce qui est codé.
- Des exceptions « permanentes » sans date de revue.
- Un périmètre par espace quand un sélecteur d'étiquettes ou une image suffirait.
- Une procédure qui ne couvre que Kyverno : les hôtes et Falco ont aussi leurs exceptions.

**En production chez MédiSphère**

Le registre est relu en comité sécurité (indicateurs), joint au dossier de l'audit HDS avec les rapports de conformité (E34) et l'ADR-0260 (E31). F6 (sécurité et conformité) le reprend comme pièce d'entrée.
