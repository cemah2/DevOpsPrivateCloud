# Module 26 — Palier 2 : Opérationnel

Le palier 1 a mesuré : Lynis et ssh-audit sur quelques VMs, OpenSCAP et ComplianceAsCode sur `durci-deb` et `durci-rocky`, kube-bench et kubescape sur `k8s-par1` ; il a posé Pod Security Admission, Kyverno avec deux politiques en audit et Falco. Ce palier **agit**. D'abord sur les hôtes : un rôle Ansible `durcissement` écrit une fois, essayé sur les deux VMs d'essai, qui règle l'accès (SSH, PAM, sudo), la trace (auditd, AIDE), le confinement (AppArmor, SELinux), puis passe sur tout le socle **par vagues**, avec des exceptions écrites et signées. Ensuite sur le cluster : Kyverno passe de l'observation au refus (signatures d'images, limites, condensés, secrets dans les URL), mute et génère ; l'admission native de Kubernetes est mise en regard ; les exceptions et les rapports deviennent un processus ; Falco et Tetragon regardent ce que font réellement les processus ; les charges de MédiAgenda et de MédiDoc deviennent sûres par construction. Tu termines en relisant le travail de Lucas et en écrivant la procédure de dérogation que l'auditeur HDS demandera.

> **Rappels du module** (introduction) : un hôte se configure par Ansible (`plateforme/ansible`, clone `~/src/ansible`, pipeline protégé ou `adm01`, **toujours `--check --diff` d'abord**) ; le cluster par Git et Argo CD (`plateforme/politiques` → Application `politiques` ; composants par leurs Applications, charts recopiés dans Harbor par `plateforme/charts-miroir`) ; aucun `kubectl apply` sur les espaces applicatifs ; tout flux par le rôle `pare_feu` et `docs/socle/matrice-flux.md`. Avant de toucher à l'accès d'un hôte : **session de secours ouverte** sur l'hôte, console Proxmox vérifiée, comptes de bris de glace du M24 testés (RB-240). Les vérifications (`lab/bin/check 26 XX`) lisent les hôtes en SSH (consultation, `sudo -n` en lecture), le cluster avec le compte `wb-checks` (ClusterRole `wb-checks-securite`), GitLab, Prometheus et Loki (locataire `audit`).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| VMs d'essai | `durci-deb` (2261, Debian 13) et `durci-rocky` (2262, Rocky 10), `vsandbox` (DHCP), créées en E04 (état OpenTofu `envs/m26`, étiquette `env-m26`, groupe d'inventaire `env_m26`) ; **détruites à la fin d'E14** |
| Rôle | `plateforme/ansible/roles/durcissement` : domaines `paquets`, `noyau`, `systemd`, `journalisation`, `montages`, `comptes`, `pam`, `sudo`, `ssh`, `auditd`, `aide`, `mac`, `conformite` (un fichier de tâches chacun, une étiquette Ansible chacun) ; chaque mesure étiquetée aussi par l'identifiant XCCDF de sa règle (`sshd_disable_root_login`, `sysctl_kernel_kptr_restrict`…) |
| Playbooks | `playbooks/durcissement.yml -e vague=N` (`serial: 1` à partir de la vague 4) ; `playbooks/conformite-mesure.yml -e vague=N -e moment=avant\|apres` (scores CIS et ANSSI à la demande ; l'analyse hebdomadaire arrive en E24) |
| Vagues | `inventories/lab/durcissement.yml`, groupes `durcissement_vague_0` à `_6` : 0 `env_m26` ; 1 `mon01`, `nbx01`, `s3-01` ; 2 `dns02`, `runner01`, `runner02`, `reg01` ; 3 `dns01`, `ca01`, `git01`, `idp01`, `vault01` ; 4 `vault02`, `vault03`, `kms01`, `ipa01` ; 5 `lb02`, `lb01`, `gw02`, `gw01` ; 6 `k8s-w01..03`, `k8s-cp01..03`, `ceph01..03`, `adm01` en dernier |
| Exceptions | `durcissement_exceptions` (`group_vars/all/durcissement.yml`) et `durcissement_exceptions_locales` (groupes, hôtes) : `{regle, hotes, justification, valideur: sophie.laurent, revue: AAAA-MM-JJ}` ; registre lisible `docs/securite/durcissement/exceptions.md` et procédure RB-261 (E23) |
| Sur chaque hôte durci | `/etc/medisphere/conformite/` : `tailoring-cis.xml`, `tailoring-anssi.xml` (profils adaptés, exceptions désélectionnées), `exceptions.json` ; contenu SCAP : `/usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml` (Debian, archive amont), `/usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml` (Rocky, paquet `scap-security-guide` 0.1.82 d'AppStream) |
| Fichiers posés | `sshd_config.d/00-durcissement.conf` (lu **avant** `01-ssh-durci.conf` du M04), `/etc/sudoers.d/00-durcissement`, `/etc/sysctl.d/60-durcissement.conf`, `/etc/modprobe.d/60-durcissement.conf`, `/etc/audit/rules.d/{30-cis,50-medisphere,99-fin}.rules`, minuterie `aide-verification.timer`, métriques `aide.prom` dans le dossier du collecteur *textfile* de node_exporter (`/var/lib/prometheus/node-exporter`, M21) |
| Journaux d'audit | `auditd` → `/var/log/audit/audit.log` (groupe `adm`) → rôle `alloy` (M22) → Loki locataire **`audit`**, étiquettes `job="audit"`, `service="auditd"`, `host` |
| Kyverno | Politiques `policies.kyverno.io/v1` uniquement, dans `plateforme/politiques` : `kyverno/validation/`, `kyverno/images/`, `kyverno/mutation/`, `kyverno/generation/`, `kyverno/exceptions/`, `kyverno/tests/<politique>/` (tests `kyverno test`) ; noms : `registres-autorises`, `exiger-etiquettes` (E07), `exiger-signature-medisphere` (E15), `exiger-limites`, `exiger-digest`, `interdire-identifiants-url`, `seccomp-par-defaut`, `networkpolicy-par-defaut` (E16) |
| Admission native (E17) | `ValidatingAdmissionPolicy` `medisphere-interdire-hostpath` (+ liaison) ; `MutatingAdmissionPolicy` `medisphere-etiquette-equipe-par-defaut` |
| Falco, Tetragon (E19, E20) | Règles `plateforme/politiques/falco/regles-medisphere.yaml` ; `TracingPolicy` `observer-exec`, `fichiers-sensibles`, `connexions-sortantes` dans `plateforme/politiques/tetragon/` ; événements dans Loki `audit` (`service="falco"`, `service="tetragon"`) ; RB-260 |
| Signature | Clé publique MédiSphère `docs/registre/cosign.pub` (M13) et, si M25-E20 en a créé une, celle de `transit/cosign-medisphere` ; signatures Cosign 3 au format *bundle*, rangées comme référents OCI dans Harbor, **sans** journal de transparence |
| Documentation | `docs/securite/durcissement/` : `referentiels.md` (E04), `exceptions.md` (E23), `runbooks/RB-260-alerte-falco.md` (E19), `RB-261-derogation.md` (E23), `RB-263-durcissement-par-vagues.md` (E14), `rapports/vague-N.md` (E14), `ssh-audit/medisphere-{debian13,rocky10}.txt` (E11) |
| Travail personnel | `~/m26/eXX/` sur `adm01` ; résultats OpenSCAP rapatriés dans `~/m26/conformite/<hôte>/` (jamais dans Git : ils décrivent les faiblesses des hôtes) |

> 💡 **Où vivent les fichiers.** Ce qui se règle **sur un hôte** (noyau, PAM, SSH, audit) vit dans le rôle `durcissement` et ses variables ; ce qui est **propre à un hôte** (un profil AppArmor, un groupe SSH en plus, une exception) vit dans `host_vars`/`group_vars`, jamais dans le rôle. Ce qui s'**admet ou se refuse dans le cluster** vit dans `plateforme/politiques`. Ce que les **applications** doivent porter (contextes de sécurité, limites) vit dans leurs charts et dépôts `…/deploiement` (E21).

> ⚠️ **Mémoire et prudence.** `durci-deb` et `durci-rocky` (2 Go chacune) s'ajoutent au profil de travail (≈ 111 Go) jusqu'à la fin d'E14 : arrête ce qui ne sert pas pendant ce temps (aucune autre VM temporaire). Les vagues d'E14 touchent tout le socle : **sauvegarde PBS du jour** de chaque VM de la vague avant de commencer, et jamais deux vagues le même jour sans que la première soit verte depuis une heure.

Durée indicative du palier : 30 à 36 heures. Ordre conseillé :

```
E10 ─ E11 ─ E12 ─ E13 ─ E14          (hôtes : rôle, accès, trace, confinement, puis le socle)
E15 ─ E16 ─ E17 ─ E18                (admission : signatures, mutation/génération, natif, exceptions)
E19 ─ E20                            (exécution : Falco puis Tetragon)
E21 (après E16 et E18) ─ E22 ─ E23   (charges sûres, revue, registre des exceptions)
Les deux colonnes « hôtes » et « cluster » sont indépendantes : on peut les mener en parallèle,
mais E23 se fait en dernier (il recense les exceptions des deux).
```

---

### M26-E10 — Le rôle Ansible `durcissement` sur les VMs d'essai  `LAB` `★★★`

> **Ticket SEC-2710** — *De : Sophie Laurent*
> Les mesures du palier 1 sont claires : une VM sortie de nos images dorées échoue à des dizaines de règles du CIS niveau 1, et chaque VM du socle a été « un peu durcie » à sa manière. Je veux **un seul rôle**, qui applique CIS niveau 1 serveur et ce qu'on retient de l'ANSSI, sur Debian comme sur Rocky, avec la trace de chaque règle. Les écarts qu'on accepte, je les signe, avec une date de revue, et ils ne doivent pas faire baisser le score à tort : l'auditeur veut voir l'écart **non justifié**. On commence sur les deux VMs d'essai, nulle part ailleurs.

**Objectifs pédagogiques**
- Organiser un rôle de durcissement par domaines, utilisable règle par règle (étiquettes = identifiants XCCDF).
- Traiter les deux familles (Debian 13, Rocky 10) dans le même rôle sans dupliquer la logique.
- Coder une exception comme une donnée contrôlée (complète, signée, datée), reportée dans le profil adapté d'OpenSCAP.
- Mesurer avant et après, et prouver l'idempotence.
- Décider, argument à l'appui, de l'usage (ou non) de Molecule pour un tel rôle.

**Prérequis** : M26-E04 (VMs d'essai, contenu ComplianceAsCode, `referentiels.md`), M04 (rôles, `ansible-lint`, Molecule), M21-E08 (rôle `node_exporter`).
**Durée indicative** : 5 h.

**Contexte technique**
- Profils XCCDF (relevés en E04 par `oscap info`) : Debian 13 `cis_level1_server`, `anssi_bp28_intermediary` ; Rocky 10 `cis_server_l1`, `anssi_bp28_intermediary`. Contenu : archive amont `scap-security-guide-0.1.82.zip` (Debian, empreinte SHA-512 publiée à côté de l'archive), paquet `scap-security-guide` d'AppStream (Rocky : il fournit un flux adapté à Rocky).
- Le projet `plateforme/ansible` a `inject_facts_as_vars = False` (M04-E26) : les faits se lisent dans `ansible_facts['…']`. L'inventaire par défaut est NetBox ; les vagues sont un inventaire statique de **groupes** ajouté à la liste `inventory` d'`ansible.cfg`.
- Ce qui existe déjà et que le rôle ne doit **pas** contredire : `ssh_durci` (M04-E11, `01-ssh-durci.conf`), certificats SSH (M06, `02-…`, `03-…`), comptes du rôle `base` (M04-E14), SSSD et HBAC (M24-E19), `node_exporter` (M21), `alloy` (M22), `pare_feu_local` (M06, nftables).
- E10 n'applique que les domaines **sans effet sur l'accès** : `paquets`, `noyau`, `systemd`, `journalisation`, `montages`, `conformite` ; E11 à E13 ajoutent les autres.

> ⚠️ **Attention** : un paramètre du noyau se charge **à chaud**. `net.ipv4.ip_forward = 0` posé par erreur sur une passerelle, un nœud Kubernetes ou un hôte Docker coupe immédiatement une partie du lab. En E10, seules `durci-deb` et `durci-rocky` sont visées (`-e vague=0`) ; le rôle doit refuser de couper le routage d'un hôte qui route sans exception déclarée. Retour arrière sur une VM d'essai : `tofu apply` la recrée (E04).

**Travail demandé**
1. **Conception** (`~/m26/e10/conception.md`). Liste les domaines, ce que chacun règle, les fichiers qu'il pose, et pour chaque domaine **ce qu'il ne doit pas casser** dans le lab (un tableau suffit). Décide de l'ordre d'exécution des domaines et justifie-le.
2. **Squelette du rôle** : `defaults/main.yml` (toutes les valeurs, commentées), `meta/main.yml`, `meta/argument_specs.yml`, `handlers/main.yml` (rechargements, jamais de redémarrage de sshd), `tasks/main.yml` qui importe un fichier par domaine. Pourquoi `import_tasks` plutôt qu'`include_tasks` si l'on veut lancer `--tags sysctl_kernel_kptr_restrict` ?
3. **Exceptions** : dans `tasks/main.yml`, contrôle chaque exception (champs présents, valideur reconnu, date de revue non dépassée : sinon **échec**), puis calcule les règles exclues sur l'hôte (noms d'hôtes, noms de groupes d'inventaire et `all` acceptés). Chaque mesure concernée teste cette liste.
4. **Domaines d'E10** : `paquets` (interdits absents, requis présents), `noyau` (un fichier `sysctl.d` généré, une ligne par règle, modules interdits ; garde-fou de routage), `systemd` (services inutiles masqués s'ils existent, vidages mémoire, Ctrl-Alt-Suppr), `journalisation` (journald persistant et compressé), `montages` (`/tmp` en tmpfs `nodev,nosuid,noexec` par surcharge de `tmp.mount`, `/dev/shm` ; ne jamais masquer un `/tmp` vivant), `conformite` (contenu SCAP vérifié par empreinte, **profils adaptés** CIS et ANSSI qui désélectionnent les exceptions, registre `exceptions.json`).
5. **Exceptions initiales** dans `group_vars/all/durcissement.yml` : au moins le routage (passerelles, nœuds Kubernetes, hôtes Docker), `rp_filter` là où il casse quelque chose, le pare-feu local (nftables au lieu d'ufw), et une exception propre à une seule famille. Pour chacune, une justification qui tient en une phrase et que Sophie peut signer.
6. **Mesure avant** : écris `playbooks/conformite-mesure.yml` (évaluation avec les profils adaptés, rapatriement des résultats ARF et HTML dans `~/m26/conformite/<hôte>/`, affichage du score) et lance-le avec `-e vague=0 -e moment=avant`.
7. **Application** :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-lint --profile production roles/durcissement playbooks/durcissement.yml
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 \
       --tags paquets,noyau,systemd,journalisation,montages,conformite --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=0 \
       --tags paquets,noyau,systemd,journalisation,montages,conformite
   ```
   Relance la même commande : combien de tâches `changed` ? Il en faut **zéro**. Puis `conformite-mesure.yml … -e moment=apres`, et consigne les scores avant/après dans `~/m26/e10/scores.md` avec les cinq règles en échec qui restent les plus importantes.
8. **Molecule ?** Dans `~/m26/e10/conception.md`, tranche : Molecule (M04-E24) pour ce rôle, oui ou non, pour quels domaines, et qu'est-ce qui le remplace sinon ?

**Critères de réussite**
- [ ] `ansible-lint --profile production` passe sur le rôle et les deux playbooks ; le rôle et les exceptions sont sur `main` de `plateforme/ansible`.
- [ ] Sur `durci-deb` et `durci-rocky` : `/etc/sysctl.d/60-durcissement.conf` est appliqué (`kernel.kptr_restrict = 2`), `/tmp` est monté `noexec`, et `/etc/medisphere/conformite/` contient les deux profils adaptés et `exceptions.json`.
- [ ] Une exception sans valideur, ou dont la date de revue est passée, fait **échouer** le rôle (essai consigné dans `~/m26/e10/conception.md`).
- [ ] Un second passage ne change rien (`changed=0`).
- [ ] `~/m26/e10/scores.md` donne les scores CIS et ANSSI avant/après des deux VMs, et le score après est supérieur.

**Vérification** : `lab/bin/check 26 10`

<details><summary>Indice 1</summary>

Un fichier de tâches inclus dynamiquement n'est « vu » par `--tags` que si l'inclusion elle-même porte l'étiquette demandée ; un import, lui, est résolu avant l'exécution et chaque tâche garde ses propres étiquettes. Pour l'ordre des domaines : qu'est-ce qui doit être en place avant qu'on touche à SSH ?
</details>

<details><summary>Indice 2</summary>

Un profil adapté (*tailoring*) XCCDF 1.2 est un petit fichier qui déclare un nouveau profil (`extends` le profil d'origine) et des `select idref="…" selected="false"`. `oscap` exige un attribut `time` sur l'élément `version`, et `oscap info` ne suffit pas à prouver qu'il se charge : évalue une seule règle avec `--rule`. Une exception qui vise une règle absente du flux de l'hôte (ufw sur Rocky) doit être ignorée, pas faire échouer l'évaluation.
</details>

<details><summary>Indice 3</summary>

`net.ipv4.ip_forward`, `net.ipv4.conf.all.forwarding` et `net.ipv4.conf.default.forwarding` sont trois règles du référentiel mais un seul réglage du noyau : une exception partielle coupe quand même le routage. Pour `rp_filter`, la valeur effective d'une interface est le **maximum** de `all` et de la sienne : que devient le `0` que Cilium pose sur ses interfaces si `all` vaut `1` ?
</details>

**Pour aller plus loin** (facultatif) : [profils et règles de ComplianceAsCode](https://complianceascode.readthedocs.io/en/latest/), [`oscap` et le *tailoring*](https://static.open-scap.org/openscap-1.4/oscap_user_manual.html) ; compare ton profil adapté à celui que produit `autotailor` (paquet `openscap-utils`) ; génère le playbook de remédiation d'une règle (`oscap xccdf generate fix --fix-type ansible --rule …`) et compare-le à ta tâche.

---

### M26-E11 — Accès : SSH, PAM, sudo et comptes  `LAB` `★★`

> **Ticket SEC-2711** — *De : Sophie Laurent, copie Nadia Roussel*
> Le CIS veut une liste explicite de qui peut se connecter, des algorithmes SSH propres, un verrouillage après échecs, sudo journalisé dans un pseudo-terminal, `su` fermé. Nadia a une seule exigence, et je la partage : à la fin, l'astreinte se connecte **comme avant** (SSO, certificat SSH, SSSD, sudo de l'annuaire), Ansible aussi, et le compte de secours marche à la console. Et je veux un ssh-audit vert, contre **notre** politique, pas contre un guide trouvé sur Internet.

**Objectifs pédagogiques**
- Compléter un durcissement SSH existant sans le contredire (ordre de lecture de `sshd_config.d`, première valeur gagnante).
- Restreindre l'accès (AllowGroups) sans couper un compte de service oublié.
- Durcir PAM par les outils de la distribution (`pam-auth-update`, `authselect`) sans casser SSSD.
- Écrire une politique ssh-audit et la vérifier.

**Prérequis** : M26-E10, M04-E11 (`ssh_durci`), M06-E19/E20 (certificats SSH), M24-E19/E20 (SSSD, HBAC, sudo de l'annuaire, `step ssh login`), M24-E28 (bris de glace testés).
**Durée indicative** : 4 h.

**Contexte technique**
- Debian 13 : OpenSSH 10.0 ; Rocky 10 : OpenSSH 9.9, algorithmes fixés par la **politique cryptographique du système** (`update-crypto-policies`, inclus par `50-redhat.conf`).
- ssh-audit **3.9** sur `adm01` (`uv tool install ssh-audit`) ; sa version Debian (3.3) est trop ancienne.
- Comptes locaux qui se connectent par clé : `admin` (Ansible, bris de glace) partout ; `git` sur `git01` (clones en SSH) ; `cephadm` sur `ceph01-03` ; `supervision` sur `gw01`/`gw02`/`lb01`/`lb02` (M07-E29). Personnes : groupes `plateforme-admins`, `plateforme`, `support` de l'annuaire. Compte `secours` : console seulement, mot de passe (M04-E12).
- La CA SSH de step-ca (M06) signe les certificats d'hôte et d'utilisateur : regarde le type de sa clé (`ssh-keygen -L -f <certificat>`, ligne *Signing CA*) avant de choisir les algorithmes.
- FreeIPA verrouille déjà les comptes de l'annuaire après 6 échecs (M24).

> ⚠️ **Attention** : ce domaine peut couper l'accès à l'hôte. Avant **chaque** application : une session root ouverte sur la VM (`sudo -i`, elle survit au rechargement de sshd), la console Proxmox de la VM ouverte, et `--check --diff` relu. Retour arrière dans la session ouverte : déplacer `/etc/ssh/sshd_config.d/00-durcissement.conf` et recharger sshd ; `faillock --user <compte> --reset` ; retirer `/etc/sudoers.d/00-durcissement`. Ici, seulement `durci-deb` et `durci-rocky`. Pour que les essais d'accès des personnes soient réalistes, inscris `durci-deb` dans l'annuaire avec le rôle `freeipa_client` du M24 (si E04 ne l'a pas fait) ; sur `durci-rocky`, contente-toi des comptes locaux.

**Travail demandé**
1. **État des lieux** (`~/m26/e11/acces.md`) : sur une VM d'essai, `sudo sshd -T` et la liste des fichiers de `sshd_config.d` ; quels mots-clés fixe chaque fichier ? Quels comptes locaux ont des clés autorisées et un shell (tous les hôtes du socle : une commande Ansible ad hoc en lecture suffit) ?
2. **SSH** (`tasks/ssh.yml`, `templates/sshd-durcissement.conf.j2`) : un fichier `00-durcissement.conf` qui ne fixe **que** ce que les autres ne fixent pas (AllowGroups, MaxSessions, bannière, algorithmes) ; trois garde-fous avant de le poser : chaque compte à clés couvert par AllowGroups (ou déclaré sans SSH), le compte d'Ansible couvert, aucun mot-clé déjà fixé ailleurs. Fragment validé (`sshd -t -f`), puis configuration **complète** validée (`sshd -t`) avec retour au fichier précédent si elle échoue ; contrôle sur `sshd -T` ; et une **nouvelle** connexion d'Ansible pour finir. Groupes en plus par `group_vars` (`role_gitlab`, `role_ceph`, `role_routeur`, `role_lb`).
3. **Algorithmes** : Debian par la configuration de sshd ; Rocky par des sous-politiques cryptographiques (`/etc/crypto-policies/policies/modules/*.pmod`) limitées à SSH. Les certificats de step-ca doivent rester acceptés.
4. **PAM** (`tasks/pam.yml`) : `faillock` (comptes **locaux** seulement), `pwquality`, `pwhistory` ; Debian par des profils `pam-auth-update`, Rocky par `authselect enable-feature`. Jamais d'édition directe de `common-auth` ou `system-auth`.
5. **sudo et comptes** (`tasks/sudo.yml`, `tasks/comptes.yml`) : `use_pty`, journal dédié, délai de réauthentification, aucune règle `!authenticate` ; `login.defs`, délai d'inactivité des shells, masque `027`, `su` réservé à un groupe vide.
6. **Application** sur la vague 0 (`--tags ssh,pam,sudo,comptes`, d'abord `--check --diff`). Puis **les essais d'accès**, un par un, consignés : connexion `admin` (nouvelle session), `ansible -m ping`, `step ssh login` + connexion d'une personne de `plateforme-admins` à `durci-deb` + `sudo -l`, connexion refusée d'une personne de `mediagenda` (HBAC), compte local d'essai verrouillé après 5 mauvais mots de passe puis déverrouillé (`faillock`), compte `secours` à la console.
7. **ssh-audit** : `ssh-audit durci-deb` puis `durci-rocky` ; lis les `fail`, `warn` et les recommandations. Crée la politique MédiSphère de chaque famille (`ssh-audit -M`), relis-la, range-la dans `docs/securite/durcissement/ssh-audit/` (MR), et vérifie chaque VM avec `-P`. Que deviennent les avertissements « non post-quantique » : correction ou décision écrite ?

**Critères de réussite**
- [ ] Sur les deux VMs d'essai, `sshd -T` montre `allowgroups` (au moins `admin` et `plateforme-admins`), les algorithmes choisis, `permitrootlogin no` ; `/etc/sudoers.d/00-durcissement` contient `use_pty` ; la pile PAM contient `pam_faillock` et `faillock.conf` vise les comptes locaux seulement.
- [ ] Les six essais d'accès de l'étape 6 sont consignés dans `~/m26/e11/acces.md`, avec leur résultat attendu.
- [ ] `ssh-audit -P docs/securite/durcissement/ssh-audit/medisphere-<famille>.txt <vm>` passe pour les deux VMs, et la politique d'une famille **échoue** sur l'autre.
- [ ] Les politiques ssh-audit sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 26 11`

<details><summary>Indice 1</summary>

`sshd -T` affiche une ligne `allowgroups <groupe>` **par** groupe. Une directive `DisableForwarding` dans ton fichier l'emporterait sur l'`AllowTcpForwarding yes` que le M04 donne à `adm01` (rebond) : regarde ce que fixe déjà `01-ssh-durci.conf` avant d'ajouter quoi que ce soit.
</details>

<details><summary>Indice 2</summary>

`faillock.conf` a une option qui limite le comptage aux comptes de `/etc/passwd` : lis le commentaire qui l'accompagne, il décrit exactement le cas d'un annuaire central. Pour `pam-auth-update`, l'ordre des modules d'un même type vient du champ `Priority` des profils : `pam_pwhistory … use_authtok` doit passer **après** `pam_pwquality`, qui demande le mot de passe.
</details>

<details><summary>Indice 3</summary>

ssh-audit ouvre plusieurs connexions sans s'authentifier : OpenSSH ≥ 9.8 pénalise ce comportement (`PerSourcePenalties`) et finit par refuser `adm01` (« Not allowed at this time »). Espace tes essais, ou étudie `PerSourcePenaltyExemptList`. Sur Rocky, retirer les signatures ECDSA de la politique du système retire aussi ECDSA de `CASignatureAlgorithms` : vérifie avec quelle clé signe la CA de step-ca avant de le faire, et préfère `HostKeyAlgorithms` dans le fichier de sshd pour les seules clés d'hôte.
</details>

**Pour aller plus loin** (facultatif) : [ssh-audit](https://github.com/jtesta/ssh-audit) et ses politiques intégrées (`ssh-audit -L`), [crypto-policies](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/security_hardening/using-the-system-wide-cryptographic-policies), [pam_faillock(8)](https://man7.org/linux/man-pages/man8/pam_faillock.8.html) ; mesure ce que coûte la suppression des échanges de clés non post-quantiques pour les clients du lab (PuTTY, clients SSH des postes, `pve01`).

---

### M26-E12 — Tracer et détecter : auditd et AIDE  `LAB` `★★`

> **Ticket SEC-2712** — *De : Sophie Laurent*
> Quand l'auditeur me demandera « qui a modifié sudoers sur `git01` le 3 mars, et quelle commande a suivi », je veux répondre en deux minutes, depuis Grafana, pas en me connectant à la VM (elle aura peut-être été effacée). Et je veux savoir **dans les 24 heures** si un binaire ou un fichier de configuration a changé sans qu'on l'ait voulu.

**Objectifs pédagogiques**
- Écrire des règles auditd lisibles (clés `-k`), les charger avec `augenrules` et vérifier qu'elles sont actives.
- Envoyer le journal d'audit vers un locataire Loki dédié et l'interroger en LogQL.
- Mettre en place AIDE : base, vérification quotidienne, métrique, nouvelle base après un changement voulu.
- Mesurer le coût (volume d'événements, durée de vérification) et ajuster.

**Prérequis** : M26-E11, M22-E05 (rôle `alloy`, locataire `audit`), M21-E08 (node_exporter, collecteur *textfile*).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Debian 13 : `auditd` 4.0.2, AIDE 0.19.1 (`/etc/aide/aide.conf` et `/etc/aide/aide.conf.d/`, base `/var/lib/aide/aide.db`) ; Rocky 10 : `audit` 4.0.3, AIDE 0.19.2 (`/etc/aide.conf`, base `/var/lib/aide/aide.db.gz`). Debian livre sa propre minuterie quotidienne d'AIDE.
- Règles demandées par la RSSI (`/etc/audit/rules.d/50-medisphere.rules`) : `execve` des sessions humaines (y compris après `sudo` : c'est l'*auid* qui compte), écriture de `/etc/sudoers*` et `/etc/ssh`, accès à `/etc/openbao` et `/opt/keycloak/conf` là où ils existent. Les règles inspirées du CIS vont dans `30-cis.rules` (le CIS niveau 1 serveur n'impose pas auditd : c'est une exigence HDS de MédiSphère).
- Le rôle `alloy` (M22) lit journald et envoie au locataire `plateforme` ; auditd n'écrit **pas** dans journald. Le locataire `audit` (rétention 1 an) est lisible dans Grafana par l'organisation « Sécurité ».
- Le collecteur *textfile* de node_exporter lit `/var/lib/prometheus/node-exporter` (variable `node_exporter_dossier_textfile`, M21).

> ⚠️ **Attention** : une règle d'audit trop large (tous les `open` de tous les comptes) peut saturer le disque et ralentir l'hôte ; `-e 2` (règles immuables) empêche toute correction sans redémarrage. Essaie sur les VMs d'essai, mesure le volume, et ne passe jamais `-e 2` pendant ce module (exception écrite). Une réaction `halt` sur disque plein arrêterait la VM : interdit ici.

**Travail demandé**
1. **auditd** (`tasks/auditd.yml`, gabarits `templates/audit/*.rules.j2`) : réglages d'`auditd.conf` (taille et rotation, format `ENRICHED`, groupe `adm` du journal, réactions qui préviennent sans bloquer), règles CIS et MédiSphère avec des clés explicites, surveillances posées **seulement** si le chemin existe, chargement par `augenrules --load`, contrôle `augenrules --check`.
2. **AIDE** (`tasks/aide.yml`) : exclusions de ce qui change par nature (journaux, données des services, conteneurs, la base d'AIDE elle-même), base initiale si absente (tâche asynchrone), unité et minuterie `aide-verification` (une seule vérification quotidienne : que fais-tu de celle de Debian ?), un écart n'est **pas** un échec du service, métriques `medisphere_aide_code_sortie` et `medisphere_aide_derniere_verification_secondes` écrites de façon atomique, script `/usr/local/sbin/aide-nouvelle-base`.
3. **Vers Loki** : étends le rôle `alloy` (variable `alloy_journaux_audit`, liste de fichiers et de services) pour envoyer `/var/log/audit/audit.log` au locataire `audit` avec `job="audit"` et `service="auditd"`, sans renvoyer tout l'historique au premier démarrage. Pourquoi pas de masquage ici, alors que le M22 en a posé pour les journaux d'application ?
4. **Application** sur la vague 0 (`--tags auditd,aide`), puis `alloy` (playbook du M22, `--limit env_m26`).
5. **Essais** : sur `durci-deb`, connecte-toi comme personne de l'annuaire, `sudo visudo -c`, `sudo cat /etc/ssh/sshd_config` ; crée `/usr/local/bin/essai-aide` ; lance `sudo systemctl start aide-verification`. Retrouve dans Grafana (source `loki-audit`) : la commande, la personne derrière `sudo`, l'écart signalé par AIDE (journal) et la métrique (`curl -s http://localhost:9100/metrics | grep medisphere_aide` sur la VM). Supprime le fichier, refais la base.
6. **Coût** : nombre d'événements par heure et par hôte (LogQL), taille de `audit.log` après une journée, durée d'une vérification AIDE ; une ligne de conclusion par mesure dans `~/m26/e12/cout.md`. Écris tes requêtes LogQL d'investigation dans `~/m26/e12/requetes-logql.md` (au moins cinq questions de l'auditeur).

**Critères de réussite**
- [ ] Sur les VMs d'essai : `auditd` actif, règles chargées identiques aux fichiers (`augenrules --check`), règle `exec-humain` présente, `audit.log` lisible par le groupe `adm`.
- [ ] `aide-verification.timer` actif ; `aide.prom` présent ; un fichier ajouté sous `/usr/local/bin` fait passer `medisphere_aide_code_sortie` à une valeur non nulle, puis à 0 après la nouvelle base.
- [ ] Loki (locataire `audit`) contient des événements `service="auditd"` des deux VMs, dont la commande de l'étape 5.
- [ ] `~/m26/e12/cout.md` et `~/m26/e12/requetes-logql.md` existent ; l'extension du rôle `alloy` est sur `main`.

**Vérification** : `lab/bin/check 26 12`

<details><summary>Indice 1</summary>

Une surveillance `-w` dont le **dossier parent** n'existe pas est refusée, et le chargement s'arrête à la première erreur : `/opt/keycloak/conf` n'existe que sur `idp01`. Pour lire un événement d'exécution, regroupe les lignes qui partagent le même `msg=audit(<horodatage>:<numéro>)` : SYSCALL, EXECVE, CWD, PATH, PROCTITLE.
</details>

<details><summary>Indice 2</summary>

Les codes de sortie d'AIDE sont des bits (1 ajouts, 2 suppressions, 4 modifications) ; 14 et au-delà signalent une erreur. `SuccessExitStatus=` d'une unité systemd accepte une liste. Les commandes `ExecStopPost=` reçoivent `$EXIT_STATUS`. Si ta base contient ses propres copies horodatées, chaque nouvelle base sera un « écart ».
</details>

<details><summary>Indice 3</summary>

Dans Alloy, `local.file_match` transforme chaque cible en étiquettes (tout ce qui ne commence pas par `__`) ; `loki.source.file` a un attribut pour partir de la fin d'un fichier jamais lu. Un second `loki.write` (locataire `audit`) évite de mélanger les locataires dans le même composant.
</details>

**Pour aller plus loin** (facultatif) : [auditd.conf(5)](https://man7.org/linux/man-pages/man5/auditd.conf.5.html), [audit.rules(7)](https://man7.org/linux/man-pages/man7/audit.rules.7.html), [AIDE](https://aide.github.io/) ; écris une règle d'alerte du ruler Loki (M22) « modification de sudoers hors d'une exécution d'Ansible » ; compare avec la remontée native du noyau vers journald (`systemd-journald-audit.socket`).

---

### M26-E13 — Confiner un service : AppArmor et SELinux  `LAB` `★★★`

> **Ticket SEC-2713** — *De : Sophie Laurent*
> Mailpit reçoit tous les courriels du lab, y compris des alertes qui citent des hôtes et des comptes. Il tourne sous un compte dédié avec une unité systemd durcie, très bien ; s'il est compromis, il peut encore lire tout ce que ce compte peut lire et exécuter n'importe quoi. Je veux qu'il soit **confiné** : ce qu'il a le droit de faire, rien de plus. Côté Rocky, je veux la preuve que SELinux est en *enforcing* partout et que personne ne l'a contourné, et que chacun dans l'équipe sache lire un refus.

**Objectifs pédagogiques**
- Écrire un profil AppArmor par apprentissage (mode *complain*, `aa-logprof`), puis l'imposer.
- Comprendre à quel chemin s'attache un profil (exécutable résolu, liens symboliques).
- Lire l'état de SELinux (modes, domaines confinés ou non, booléens et contextes modifiés localement) et diagnostiquer un refus (`ausearch`, `audit2why`).
- Corriger un refus par la bonne mesure (contexte, booléen), jamais par `setenforce 0`.

**Prérequis** : M26-E12, M19-E03 (Mailpit, rôle `mailpit`), M24 (`ipa01`), M08 (`ceph01-03`).
**Durée indicative** : 3 h 30, plus une semaine d'observation en mode *complain* (en parallèle des autres exercices).

**Contexte technique**
- `mon01` (Debian 13) : AppArmor 4.1 actif. Mailpit 1.31.6 : binaire `/usr/local/bin/mailpit`, lien vers `/opt/mailpit/<version>/mailpit` ; configuration `/etc/mailpit/` (dont le certificat dans `tls/`), base SQLite `/var/lib/mailpit/` ; SMTP 25 (capacité `CAP_NET_BIND_SERVICE` donnée par l'unité), interface et API 8025, OAuth2 Proxy devant l'interface sur 8443 (M24-E18).
- Profil : fichier `/etc/apparmor.d/usr.local.bin.mailpit`, profil nommé `mailpit`, posé par le rôle `durcissement` (domaine `mac`, gabarit `templates/apparmor/usr.local.bin.mailpit.j2`, mode choisi dans `host_vars/mon01/durcissement.yml`).
- Rocky 10 : `ipa01` (FreeIPA, critique : lecture seule ici), `ceph01-03`, `durci-rocky`. SELinux *enforcing*, politique *targeted* attendus.
- Le rôle `durcissement` lance la vérification AIDE par une unité systemd ; sur Rocky, la politique SELinux a un domaine pour AIDE (`aide_t`).

> ⚠️ **Attention** : un profil en *enforce* incomplet empêche Mailpit de démarrer ou de recevoir : plus aucun courriel d'alerte du lab. Passe en *enforce* hors heures d'essais, garde une session ouverte sur `mon01`, vérifie la réception tout de suite (courriel de test, check M19). Retour arrière immédiat : `sudo aa-complain /etc/apparmor.d/usr.local.bin.mailpit`, puis la MR qui remet `complain` dans `host_vars` (sinon Ansible le réimposera). Sur `ipa01` : **aucune** modification dans cet exercice.

**Travail demandé**
1. **Avant** : `sudo aa-status` sur `mon01` ; quels profils sont chargés, lesquels confinent un processus ? `readlink -f /usr/local/bin/mailpit` : à quel chemin le profil doit-il s'attacher, et pourquoi ?
2. **Profil en apprentissage** : écris le gabarit du profil (abstractions de base, capacité, réseau, configuration en lecture, données en lecture/écriture/verrou, lectures du moteur Go), mode `complain`, domaine `mac` du rôle (`--limit mon01 --tags mac`, après `--check --diff`). Vérifie que le processus de Mailpit est bien sous le profil (`aa-status`, `ps -eZ` ou `/proc/<pid>/attr/current`).
3. **Une semaine d'usage** (le lab envoie des courriels tous les jours ; ajoute des essais : interface, API, réception STARTTLS) ; puis `aa-logprof`. Pour chaque règle proposée : acceptée, refusée, et pourquoi (`~/m26/e13/journal-mac.md`). Reporte les règles retenues dans le gabarit (MR).
4. **Enforce** : `mode: enforce` dans `host_vars/mon01/durcissement.yml`, application, essais complets (réception, interface par 8443, API des checks par 8025, check du M19), puis l'essai qui prouve le confinement : `sudo aa-exec -p mailpit -- /bin/sh` doit échouer.
5. **SELinux, lecture** sur `durci-rocky`, `ceph01` et `ipa01` : `getenforce`, `sestatus` ; répartition des domaines (`ps -eZ`) — quels services tournent en `unconfined_service_t`, et pourquoi (pense à la façon dont node_exporter et Alloy ont été installés) ? Pendant une vérification AIDE (`systemctl start aide-verification`), dans quel domaine tourne `aide` ? Sur `ipa01` : booléens et contextes modifiés localement (`semanage boolean -l -C`, `semanage fcontext -l -C`) : qui les a posés ?
6. **SELinux, un refus réel** sur `durci-rocky` : simule l'erreur classique d'une restauration — copie la base d'AIDE vers `/root`, puis **déplace**-la (`mv`) à sa place ; lance une vérification. Lis le refus (`ausearch -m AVC -ts recent`, `audit2why`), explique-le (`ls -Z`, `matchpathcon`), corrige-le par la bonne commande, et explique pourquoi `setenforce 0`, `audit2allow -M` ou `chcon` seraient de mauvaises réponses ici.

**Critères de réussite**
- [ ] Sur `mon01`, le profil `mailpit` est chargé en `enforce`, le processus de Mailpit est confiné par lui, Mailpit reçoit (port 25) et répond (8025).
- [ ] `host_vars/mon01/durcissement.yml` (mode `enforce`) et le gabarit du profil sont sur `main` de `plateforme/ansible`.
- [ ] `durci-rocky`, `ceph01` et `ipa01` sont en *enforcing* (mode courant et configuré), politique *targeted*.
- [ ] `~/m26/e13/journal-mac.md` contient les décisions d'`aa-logprof`, la répartition des domaines SELinux et l'analyse du refus de l'étape 6.

**Vérification** : `lab/bin/check 26 13`

<details><summary>Indice 1</summary>

AppArmor attache un profil au chemin **réel** de l'exécutable (après résolution des liens) : un profil écrit pour `/usr/local/bin/mailpit` ne confinerait rien. Un motif avec `*` à la place du numéro de version évite de réécrire le profil à chaque montée de Mailpit. Le mode peut s'écrire **dans** le profil (`flags=(complain)`) : sinon `aa-complain` modifie le fichier et Ansible le réécrit à chaque passage.
</details>

<details><summary>Indice 2</summary>

`mv` garde le contexte SELinux d'origine ; `cp` prend celui du dossier de destination. La règle de contexte d'un chemin standard existe déjà dans la politique (`semanage fcontext -l | grep aide`) : il n'y a rien à ajouter, seulement à réappliquer.
</details>

<details><summary>Indice 3</summary>

Un service lancé par systemd depuis un binaire étiqueté `bin_t` (installé à la main dans `/usr/local/bin`) n'a pas de domaine à lui : il tourne `unconfined_service_t`. SELinux ne le protège pas plus qu'un processus root ordinaire. C'est un constat à écrire, pas à corriger aujourd'hui.
</details>

**Pour aller plus loin** (facultatif) : [AppArmor — langage des profils](https://gitlab.com/apparmor/apparmor/-/wikis/QuickProfileLanguage), [SELinux sur RHEL 10](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_selinux/index) ; écris une politique SELinux minimale pour node_exporter (`sepolicy generate --init`) sur `durci-rocky` et mesure ce qu'elle coûte à maintenir ; dans Kubernetes, `securityContext.appArmorProfile` (GA depuis 1.30).

---

### M26-E14 — Durcir le socle par vagues  `LAB` `★★★`

> **Ticket CHG-2714** — *De : Claire Morel, copie Nadia Roussel et Sophie Laurent*
> Le rôle a fait ses preuves sur les VMs d'essai. On l'applique à tout le socle, **par vagues**, sans coupure visible : d'abord ce qui casse peu, ensuite ce qui porte tout. Une vague à la fois, un rapport par vague, un runbook que Nadia pourra suivre seule la prochaine fois. Jamais deux passerelles, deux répartiteurs ou deux nœuds d'une même grappe en même temps. `adm01` en dernier. Et à la fin, les deux VMs d'essai disparaissent.

**Objectifs pédagogiques**
- Planifier un changement de masse par vagues de criticité croissante, avec critères d'entrée et de sortie.
- Appliquer un rôle un hôte à la fois sur les grappes et les paires (`serial`, `max_fail_percentage`), avec mise hors charge (`drain`, `noout`).
- Mesurer avant et après chaque vague, traiter les écarts (corriger le rôle, ou exception signée).
- Écrire le runbook et les rapports qui serviront à l'auditeur.

**Prérequis** : M26-E10 à E13, M24-E28 (bris de glace testés), M07 (VRRP de la bordure et des répartiteurs), M14 (`drain`), M08 (`noout`), M25-E24 (grappe OpenBao).
**Durée indicative** : 8 h, réparties sur plusieurs jours (une vague par séance).

**Contexte technique**
- Vagues : voir les faits communs. Le playbook passe un hôte à la fois à partir de la vague 4, met les nœuds Kubernetes hors charge (`kubectl drain` puis `uncordon`, kubeconfig de la personne qui lance) et pose `noout` sur Ceph pendant l'intervention d'un nœud.
- Exceptions prévisibles : relis le profil CIS de chaque famille contre ce que fait chaque hôte (Kea sur `dns01`/`dns02`, nginx sur `nbx01`, dnsmasq sur la bordure, Apache httpd de FreeIPA sur `ipa01`, Docker sur `runner02` et `reg01`…).
- Les VMs d'essai sont décrites dans l'état OpenTofu `envs/m26` de `plateforme/infra`.

> ⚠️ **Attention** : chaque vague peut couper un service du lab, voire l'accès. Avant chaque vague : **instantané PBS du jour** de chaque VM de la vague, session de secours ouverte sur chaque hôte de la passe, console Proxmox prête, `--check --diff` relu (par une seconde personne à partir de la vague 3). Vague 5 : le membre **en attente** de chaque paire d'abord, bascule VRRP vérifiée avant l'autre. Vague 6 : `adm01` seulement avec une session de secours (`-e durcissement_secours_confirme=true`). Retour arrière : RB-263 (retirer le fichier fautif dans la session ouverte, `git revert` et rejeu, restauration PBS).

**Travail demandé**
1. **Préparation** : `inventories/lab/durcissement.yml` (groupes de vagues ; l'inventaire ne déclare que des groupes), ajout à `ansible.cfg` ; pré- et post-tâches du playbook (session de secours d'`adm01`, `drain`/`uncordon`, `noout`, contrôle de résolution d'une personne de l'annuaire par SSSD après la vague).
2. **RB-263** (`docs/securite/durcissement/runbooks/RB-263-durcissement-par-vagues.md`) : règles, tableau des vagues, procédure d'une vague (mesure avant, `--check --diff`, application, contrôles après, mesure après, nouvelle base AIDE, rapport), contrôles après une vague (tableau commande/attendu), retour arrière par situation.
3. **Vagues 1 à 6**, une par séance, en suivant RB-263. Après chacune : `rapports/vague-N.md` (scores avant/après par hôte, incidents, écarts restants et décision, exceptions ajoutées), MR.
4. Pour chaque **écart** découvert pendant une vague : corrige le rôle (MR, rejeu sur la vague 0 d'abord tant qu'elle existe) ou fais signer une exception (justification, date de revue). Note dans le rapport lequel des deux et pourquoi.
5. **Fin** : quand la vague 6 est verte, détruis `durci-deb` et `durci-rocky` (`tofu destroy` de l'état `envs/m26`, après `--check` de ce qui sera détruit), retire-les de NetBox s'il le faut, et vérifie qu'aucune ressource temporaire ne reste (VMID 2261-2262, entrées DNS, clés d'hôte dans `~/.ssh/known_hosts_env-m26`).

**Critères de réussite**
- [ ] Sur chaque VM du socle (vagues 1 à 6), `00-durcissement.conf`, `60-durcissement.conf` (sysctl) et `/etc/medisphere/conformite/exceptions.json` sont présents ; `auditd` est actif.
- [ ] Les services du lab répondent comme avant (checks des modules 21 à 25 verts) ; aucune alerte ouverte liée au durcissement.
- [ ] RB-263 et les six rapports de vague sont sur `main` de `plateforme/medisphere`.
- [ ] Les VMID 2261 et 2262 n'existent plus.

**Vérification** : `lab/bin/check 26 14`

<details><summary>Indice 1</summary>

Un inventaire statique qui ne déclare que des **groupes** et des noms d'hôtes se fond avec les inventaires dynamiques : les variables (dont `ansible_host`) viennent de NetBox. Vérifie avec `ansible-inventory --graph durcissement_vague_4` avant de lancer quoi que ce soit.
</details>

<details><summary>Indice 2</summary>

`serial` accepte une expression ; un `drain` et un `noout` se lancent ailleurs que sur l'hôte durci (`delegate_to`). `noout` se pose depuis un **autre** nœud de la grappe, celui qu'on durcit pouvant redémarrer des services.
</details>

<details><summary>Indice 3</summary>

Un `/tmp` qui n'était pas un tmpfs ne le devient qu'au prochain redémarrage : le rôle le signale au lieu de le monter à chaud (sinon il masquerait les fichiers et sockets des services). Planifie ces redémarrages, un hôte à la fois, et note-les dans le rapport de vague.
</details>

**Pour aller plus loin** (facultatif) : [stratégies d'exécution d'Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html) (`serial` en liste de pourcentages, `throttle`, `run_once`) ; proposer une vague « canari » (un hôte de chaque rôle) avant la vague 1 pour les prochaines versions du rôle.

---

### M26-E15 — Kyverno : n'admettre que les images signées  `LAB` `★★★`

> **Ticket SEC-2715** — *De : Sophie Laurent*
> Depuis le M13, la CI signe chaque image MédiSphère, et la CI vérifie sa propre signature. Mais rien n'empêche quelqu'un de déployer en recette une image poussée à la main, ou signée avec la clé d'un stagiaire : Harbor vérifie qu'une signature **existe**, pas **qui** a signé. Je veux que le cluster refuse, en recette et en production, toute image MédiSphère qui n'est pas signée par **notre** clé, avec son SBOM attesté. D'abord en observation, ensuite en refus.

**Objectifs pédagogiques**
- Écrire une `ImageValidatingPolicy` (Kyverno 1.19, `policies.kyverno.io/v1`) : images visées, attesteurs à clé, attestation in-toto, condensé obligatoire.
- Vérifier des signatures Cosign 3 au format *bundle*, rangées comme référents OCI, sans journal de transparence.
- Donner à Kyverno l'accès en lecture au registre privé (robot, ExternalSecret) et la confiance dans la racine MédiSphère.
- Passer d'`Audit` à `Deny`, choisir `failurePolicy` et en assumer les conséquences.

**Prérequis** : M26-E07 (Kyverno, `plateforme/politiques`), M13-E07 à E14 (Cosign, clé MédiSphère, attestations, politique de Harbor), M25-E12 (ESO), M25-E20 (clé de transit `cosign-medisphere`), M20 (Argo CD).
**Durée indicative** : 4 h.

**Contexte technique**
- Images visées : `registry.par1.medisphere.internal/medisphere/*`. Espaces visés : `mediagenda-recette`, `mediagenda-prod`, `medidoc-dev`, `medidoc-recette`, et `wb-essais` pour les essais.
- Signatures : Cosign 3 signe par configuration **sans service** (`docs/registre/signing-config.json`, M13-E07) : ni Rekor ni horodatage. Le *bundle* (`application/vnd.dev.sigstore.bundle.v0.3+json`) est rangé comme référent de l'image (API *Referrers* de Harbor 2.15). Attestation SBOM SPDX (`--type spdxjson`, `predicateType` `https://spdx.dev/Document`), exigée en production (M13-E08).
- Clés : `docs/registre/cosign.pub` (M13) ; si M25-E20 a introduit une clé de transit, sa clé publique s'exporte par `cosign public-key --key hashivault://cosign-medisphere` (variables `VAULT_ADDR`/`VAULT_TOKEN` vers OpenBao). Les images en service peuvent être signées par l'une **ou** l'autre.
- Projet Harbor `medisphere` privé ; robots dans l'état OpenTofu `registre/` du M13 (`plateforme/infra`). Secrets de plateforme dans OpenBao (`kv/plateforme/<composant>/…`), livrés par le ClusterSecretStore `openbao`. Les secrets que Kyverno utilise pour lire un registre vivent dans l'espace `kyverno`.
- Kyverno 1.19 : le champ `credentials` d'une politique d'images cite des Secrets de l'espace de Kyverno ; la racine des contrôleurs se règle dans les valeurs du chart (`caCertificates`).

> ⚠️ **Attention** : en `Deny` avec `failurePolicy: Fail`, si Kyverno ne peut pas vérifier (Harbor arrêté, robot expiré, Kyverno indisponible), **aucun pod** des espaces visés ne démarre, y compris les pods recréés après un `drain` ou une panne de nœud. Passe en refus d'abord sur `mediagenda-recette` seul, une journée, puis la production. Retour arrière : MR qui remet `validationActions: [Audit]` (Argo CD synchronise en moins d'une minute) ; si Argo CD lui-même est indisponible, la procédure d'urgence est celle de RB-261 (E23). Ne vise jamais `kube-system`, `kyverno`, `argocd`.

**Travail demandé**
1. **Accès au registre** : robot `robot$medisphere+kyverno` en lecture (tirage, artefacts, accessoires) par OpenTofu (état `registre/`) ; son secret dans OpenBao (`kv/plateforme/kyverno/harbor`, sans le faire passer par la ligne de commande) ; `ExternalSecret` `harbor-kyverno` (type `kubernetes.io/dockerconfigjson`) dans l'espace `kyverno` ; racine MédiSphère dans les valeurs du chart si E07 ne l'a pas fait.
2. **Clés** : rassemble les clés publiques en service (M13, M25-E20) et vérifie à la main qu'une image de MédiAgenda en recette est signée par l'une d'elles : `cosign verify --key … --insecure-ignore-tlog=true <image>@<condensé>`. Note le condensé.
3. **Politique** `kyverno/images/exiger-signature-medisphere.yaml` : espaces et images visés, condensé exigé sans mutation (pourquoi pas de mutation sous GitOps ?), deux attesteurs à clé sans journal, attestation SPDX, validations sur les conteneurs **et** les conteneurs d'initialisation, délai du webhook adapté, autogénération pour les contrôleurs. Commence en `validationActions: [Audit]` et `failurePolicy: Ignore`. MR, synchronisation de l'Application `politiques`, état `ready` de la politique.
4. **Lecture des rapports** : `kubectl get policyreports -A` ; une image en service échoue-t-elle ? Laquelle et pourquoi (ancienne image d'avant M13 ? signée par une clé retirée ?) Corrige par la chaîne de livraison, pas par la politique.
5. **Essais** dans `wb-essais` (`kubectl run … --dry-run=server`, ou un pod jetable) avec trois images de `medisphere/essai-signature` que tu pousses avec ton compte Harbor : (a) signée par la clé MédiSphère **avec** SBOM attestée (par la chaîne de CI ou à la main sur `adm01` avec la clé, sans la laisser sur le disque) ; (b) **non signée** ; (c) signée par une clé jetable (`cosign generate-key-pair` dans `~/m26/e15/`, configuration de signature sans service). Puis la même image (a) désignée par son **étiquette**. Note la réponse de l'API pour chacune.
6. **Refus** : `validationActions: [Deny]`, `failurePolicy: Fail` ; recette une journée (un déploiement normal par Argo CD doit passer), puis production. Supprime le dépôt `medisphere/essai-signature` de Harbor à la fin.

**Critères de réussite**
- [ ] L'`ImageValidatingPolicy` `exiger-signature-medisphere` est `ready`, en `Deny` et `Fail`, et vise `mediagenda-prod` et `mediagenda-recette`.
- [ ] L'`ExternalSecret` `harbor-kyverno` de l'espace `kyverno` est synchronisé.
- [ ] Aucun rapport de politique en échec pour cette politique dans `mediagenda-prod` et `mediagenda-recette`.
- [ ] Les quatre essais de l'étape 5 sont consignés (`~/m26/e15/essais.md`) : seule l'image (a) par condensé est admise.

**Vérification** : `lab/bin/check 26 15`

<details><summary>Indice 1</summary>

Dans une `ImageValidatingPolicy`, les images à contrôler se choisissent par `matchImageReferences` (motifs `glob`), les attesteurs se déclarent dans `attestors` avec un nom qui doit être un **identifiant CEL** (pas de tiret), et la décision s'écrit en CEL : `images.containers.map(image, verifyImageSignatures(image, [attestors.<nom>])).all(e, e > 0)`. Sans journal de transparence, il faut le dire à l'attesteur (`ctlog`).
</details>

<details><summary>Indice 2</summary>

`validationConfigurations` règle trois comportements : remplacer l'étiquette par le condensé, exiger le condensé, exiger que toute image visée soit vérifiée. Sous Argo CD, une mutation de l'image crée un écart permanent avec Git. L'attestation SBOM se décrit dans `attestations` (`intoto.type` = le `predicateType`) et se vérifie avec `verifyAttestationSignatures(image, attestations.<nom>, [attesteurs])`.
</details>

<details><summary>Indice 3</summary>

Harbor (M13-E14) refuse de **servir** une image non signée du projet `medisphere` : l'essai (b) échoue donc avant même la vérification de signature, avec un autre message. C'est l'essai (c) qui montre ce que Kyverno ajoute. Pour comprendre une réponse, `kubectl get events -n wb-essais` et les journaux du contrôleur d'admission (`kubectl -n kyverno logs deploy/kyverno-admission-controller`).
</details>

**Pour aller plus loin** (facultatif) : [ImageValidatingPolicy](https://kyverno.io/docs/policy-types/image-validating-policy/), [Cosign — format bundle](https://docs.sigstore.dev/cosign/) ; ajoute la vérification de l'attestation de provenance SLSA (M13) ; essaie la `NamespacedImageValidatingPolicy` pour qu'une équipe déclare ses propres exigences dans son espace.

---

### M26-E16 — Kyverno : muter et générer  `LAB` `★★`

> **Ticket PLAT-2716** — *De : Karim Benali, copie Julien Petit*
> Les règles qu'on écrit dans nos guides depuis le M14 doivent devenir des règles du cluster : profil seccomp par défaut (sinon PSA `restricted` refuse le pod et le développeur ne comprend pas pourquoi), demandes et limite de mémoire sur tout conteneur d'équipe, images par condensé en production, jamais d'identifiants dans une URL en clair (promesse du M17), et tout **nouvel** espace d'équipe qui naît avec notre refus réseau par défaut (promesse du M15). Et comme pour du code : des tests, joués à chaque MR.

**Objectifs pédagogiques**
- Écrire des `ValidatingPolicy` en CEL (variables, messages calculés, sélection par espace).
- Muter avec une `MutatingPolicy` (*apply configuration*), sans réécrire ce que l'auteur a choisi, et sans créer d'écart avec Git.
- Générer des objets avec une `GeneratingPolicy` (synchronisation, objets orphelins, espaces existants).
- Tester des politiques avec `kyverno test` (résultats attendus, ressources mutées et générées) et l'intégrer en CI.

**Prérequis** : M26-E15, M26-E06 (PSA), M15-E17 (`refus-par-defaut`, `sortie-dns`), M17 (chart `mediagenda`), M19 (CI).
**Durée indicative** : 4 h.

**Contexte technique**
- Espaces d'équipe : étiquette `medisphere.internal/equipe` ; environnement : `medisphere.internal/environnement` (`dev`, `recette`, `prod`) ; ces étiquettes sont posées par `plateforme/k8s/espaces/`.
- Modèle réseau du M15 : `NetworkPolicy` `refus-par-defaut` (rien n'entre ni ne sort) et `sortie-dns` (vers CoreDNS, `kube-system`, `k8s-app: kube-dns`, UDP et TCP 53).
- Contrôle d'admission dans l'ordre : mutation (webhooks), **puis** validation (dont PSA et les webhooks de validation). Le kubelet aura `seccompDefault: true` au palier 3 (E25).
- Kyverno CLI 1.19.2 : `kyverno test <dossier>` lit les `kyverno-test.yaml` (`apiVersion: cli.kyverno.io/v1alpha1`, `kind: Test`) ; valeurs (étiquettes d'espaces) par un fichier `kind: Values`. Le pipeline de `plateforme/politiques` a déjà un job `kyverno:tests` (E07) ; la racine `kustomization.yaml` du projet liste les politiques que l'Application `politiques` applique (jamais les dossiers de tests).

> ⚠️ **Attention** : une politique en `Deny` mal ciblée bloque les déploiements de toutes les équipes. Chaque politique de validation commence en `Audit`, on lit les rapports, on corrige les charges, puis `Deny`. Une `GeneratingPolicy` qui supprime ce qu'elle a généré quand on la retire laisserait des espaces sans refus réseau : choisis le comportement à la suppression. Retour arrière : MR (Argo CD synchronise) ; jamais `kubectl delete` d'une politique à la main hors RB-261.

**Travail demandé**
1. **Validation** (`kyverno/validation/`) : `exiger-limites` (demandes CPU et mémoire, limite de mémoire ; pas de limite de CPU exigée : pourquoi ?), `exiger-digest` (production seulement), `interdire-identifiants-url` (ConfigMaps et variables d'environnement en clair ; motif RE2). Messages qui disent **quoi** corriger.
2. **Mutation** (`kyverno/mutation/seccomp-par-defaut.yaml`) : profil `RuntimeDefault` au niveau du **pod** quand rien n'est déclaré, pods des espaces d'équipe seulement, rien n'est touché si un profil existe ; pas de mutation des Deployments (pourquoi, sous Argo CD ?).
3. **Génération** (`kyverno/generation/networkpolicy-par-defaut.yaml`) : à la création d'un espace portant `medisphere.internal/equipe`, les deux politiques du modèle réseau, synchronisées. Décide : espaces existants (oui/non), comportement si la politique est supprimée.
4. **Tests** (`kyverno/tests/<politique>/`) : pour chaque politique, des ressources qui passent, qui échouent et qui ne sont pas concernées ; pour la mutation, la ressource attendue après mutation ; pour la génération, les objets attendus. `kyverno test kyverno/tests/` doit passer en local, puis **échouer** si tu casses volontairement une attente (montre-le).
5. **CI** : complète le pipeline de `plateforme/politiques` : le job `kyverno:tests` doit échouer s'il ne trouve **aucun** test, et un nouveau job refuse toute politique d'ancien type (`ClusterPolicy`, `Policy`, `*CleanupPolicy`).
6. **Mise en service** : MR, `Audit` d'abord pour `exiger-limites` et `interdire-identifiants-url`, lecture des rapports, corrections des charges si besoin (MR dans les dépôts d'équipes), puis `Deny`. **Essais** : crée l'espace `wb-modele-equipe` (étiquettes `medisphere.internal/equipe: plateforme`, `medisphere.internal/environnement: dev`) ; les deux NetworkPolicy y apparaissent ; un pod `essai-seccomp` (image de `bibliotheque/`, ressources déclarées, sans profil seccomp) y est admis avec `RuntimeDefault` ; une ConfigMap `postgresql://u:p@hôte/base` y est refusée (`--dry-run=server`).

**Critères de réussite**
- [ ] Les cinq politiques sont `ready` dans le cluster ; `exiger-limites`, `exiger-digest` et `interdire-identifiants-url` sont en `Deny`.
- [ ] L'espace `wb-modele-equipe` contient `refus-par-defaut` et `sortie-dns` générées par Kyverno, et le pod `essai-seccomp` porte `seccompProfile.type: RuntimeDefault` au niveau du pod.
- [ ] Le dernier pipeline de `main` de `plateforme/politiques` a réussi, avec le job `kyverno:tests`.
- [ ] `~/m26/e16/decisions.md` répond aux quatre « pourquoi » des étapes 1 à 3.

**Vérification** : `lab/bin/check 26 16`

<details><summary>Indice 1</summary>

Dans une `ValidatingPolicy`, `variables` évite de répéter la même expression ; `messageExpression` construit un message à partir d'elles. Les conteneurs d'initialisation ne sont pas dans `object.spec.containers`. Pour viser des espaces, `matchConstraints.namespaceSelector` ; dans un test hors cluster, les étiquettes des espaces viennent du fichier de valeurs (`namespaceSelector`).
</details>

<details><summary>Indice 2</summary>

Une mutation `ApplyConfiguration` s'écrit comme un objet partiel : `Object{spec: Object.spec{securityContext: Object.spec.securityContext{…}}}`. Les champs non cités sont conservés. `matchConditions` filtre **avant** la mutation : c'est là qu'on dit « seulement si aucun profil de pod n'est déclaré ». L'autogénération pour les contrôleurs se règle par `autogen.podControllers.controllers`.
</details>

<details><summary>Indice 3</summary>

Une `GeneratingPolicy` construit ses objets en CEL avec `dyn(…)` et les pose par `generator.Apply(<espace>, [objets])`. `evaluation.synchronize`, `evaluation.generateExisting` et `evaluation.orphanDownstreamOnPolicyDelete` règlent les trois questions de l'étape 3. Dans un `kyverno-test.yaml`, une ressource mutée se compare avec `patchedResources`, une ressource générée avec `generatedResource`.
</details>

**Pour aller plus loin** (facultatif) : [ValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/), [MutatingPolicy](https://kyverno.io/docs/policy-types/mutating-policy/), [GeneratingPolicy](https://kyverno.io/docs/policy-types/generating-policy/), [kyverno test](https://kyverno.io/docs/kyverno-cli/reference/kyverno_test/) ; promesses restantes des modules précédents (PDB obligatoire au-delà d'un réplica, sondes de disponibilité, noms d'hôte `<espace>.apps…` des HTTPRoute, annotation `lbipam.cilium.io/ips` réservée à la plateforme) : choisis-en une et écris sa politique avec ses tests.
