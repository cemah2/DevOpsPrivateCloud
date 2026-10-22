# Module 26 — Introduction : durcissement et sécurité à l'exécution

## Six semaines avant l'auditeur

Lundi, 8 h 30. La lettre de mission de l'auditeur HDS est arrivée vendredi soir. Sophie Laurent l'a annotée tout le week-end ; Claire Morel la transmet à l'équipe avec sa décision.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
> **Objet** : Audit HDS dans six semaines — durcir, mesurer, détecter
>
> Bonjour,
>
> L'auditeur posera quatre questions, Sophie les a soulignées : *quel référentiel appliquez-vous ? comment prouvez-vous que vous l'appliquez ? quels écarts avez-vous acceptés, et qui les a signés ? que se passe-t-il quand un conteneur est compromis ?* Aujourd'hui, nous répondrions « un peu de tout, au fil des modules », « nous ne le mesurons pas », « nous ne savons pas » et « nous l'apprendrions par hasard ». Le cluster accepte n'importe quel pod que l'API veut bien créer, rien ne regarde ce que font les processus, et les nœuds se parlent en clair.
>
> Ce que je veux à la fin du module :
> 1. **CIS et ANSSI** comme référentiels, **mesurés chaque semaine**, appliqués par le code, avec des **exceptions écrites et signées** ;
> 2. une **admission** qui refuse ce qui n'est pas conforme (privilèges, images non signées, pods sans limites) ;
> 3. une **détection à l'exécution** qui alerte en minutes, et des règles qui savent aussi bloquer ;
> 4. des nœuds qui se parlent **chiffré**, des hôtes **filtrés**, des kubelets dont on vérifie le certificat ;
> 5. une **réponse à incident** préparée et répétée.
>
> Nadia pose une condition, et je la fais mienne : **le durcissement ne casse pas l'astreinte**. On mesure avant d'agir, on essaie sur des VMs jetables, on applique par vagues, une passerelle et un nœud à la fois, avec un accès de secours ouvert. Les règles de la maison s'appliquent : Git et MR pour tout, Ansible pour les VMs, Argo CD pour le cluster, charts tiers par notre miroir, aucun secret en clair.
>
> Premier jalon : savoir où nous en sommes. Les mesures du parc et du cluster, notre modèle de menace, Pod Security imposé là où c'est possible, Kyverno et Falco installés et observés. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 26, MédiSphère est **durcie v1** (étiquette `durcissement-v1` de `plateforme/medisphere`), état que reprennent les modules 27 à 29 et le workbook final F6 (sécurité et conformité) :

- un rôle Ansible **`durcissement`** (CIS niveau 1 serveur, ANSSI-BP-028 intermédiaire) appliqué à tout le socle par **vagues**, avec ses exceptions déclarées, et une analyse **OpenSCAP hebdomadaire** dont le score est supervisé ;
- **Pod Security Admission** `restricted` imposé, **Kyverno 1.19** (politiques CEL : validation, signatures d'images, mutation, génération) et des politiques d'admission natives ;
- **Falco 0.45** et **Tetragon 1.7** : détection, acheminement vers Alertmanager et Loki, blocage ciblé ;
- **Cilium** : chiffrement WireGuard entre nœuds et pare-feu d'hôte ; kubelets à certificats de service vérifiés ;
- le projet **`plateforme/politiques`**, la documentation `docs/securite/durcissement/` (modèle de menace, référentiels, registre des exceptions, ADR-0260, runbooks RB-260 à RB-265).

Le **palier 1** (ce fichier et `01-decouverte.md`) **mesure et observe** : Lynis et ssh-audit sur le socle, OpenSCAP sur deux VMs d'essai, kube-bench et kubescape sur `k8s-par1`, le modèle de menace, puis trois premiers dispositifs du cluster, choisis parce qu'ils se mettent en place **sans rien refuser** au départ : Pod Security en avertissement puis en application, Kyverno en audit, Falco en détection. Aucune VM du socle n'est modifiée dans ce palier : c'est le palier 2. Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module (fin du palier 1)

```
 adm01 (MGMT 10.10.10.10) : ssh-audit 3.9 · kyverno 1.19 (CLI) · kubescape 4.0 · kubectl · tofu · ansible
   │ SSH (lecture) : Lynis 3.1.7 lancé depuis une archive vérifiée, rapport rapatrié
   ├──────────────► gw01 · git01 · mon01 · ipa01 (Rocky)        ← mesure seule (E03)
   │
   │ OpenTofu envs/m26 (vsandbox, DHCP Kea)
   ├──────────────► durci-deb   (2261, Debian 13, 2 Go)  OpenSCAP 1.4 + ComplianceAsCode 0.1.82 (archive amont)
   └──────────────► durci-rocky (2262, Rocky 10, 2 Go)   OpenSCAP 1.4 + scap-security-guide 0.1.82 (AppStream)
                    résultats ARF + HTML dans /var/lib/conformite/essais/                      (E04)

 ┌───────────────────────────────── k8s-par1 (Kubernetes 1.36, Cilium 1.20) ─────────────────────────────┐
 │ kube-apiserver ─► authentification ─► autorisation ─► admission mutante ─► admission validante ─► etcd │
 │                                                       │                    ├ PodSecurity (étiquettes   │
 │                                                       │                    │  d'espace, E06)           │
 │                                                       │                    ├ VAP medisphere-images (M14)│
 │                                                       └ webhooks Kyverno ──┴ webhooks Kyverno (E07)     │
 │ kyverno (restricted) : admission ×3, background ×2, reports, cleanup ─► PolicyReport par objet        │
 │ falco (privileged) : DaemonSet falco (modern_ebpf, 6 nœuds) ─http─► falcosidekick ─┬► Alertmanager  │
 │                                                                                    └► Loki « audit » │
 │ wb-diagnostic (privileged) : Jobs kube-bench (cis-1.12) sur un nœud de contrôle et un travailleur (E05)│
 └────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 git01 : plateforme/politiques (ValidatingPolicy, tests) · plateforme/gitops (Applications kyverno, falco,
         politiques) · plateforme/k8s (espaces, RBAC des checks) · plateforme/infra (envs/m26)
         plateforme/medisphere : docs/securite/durcissement/ (menace, état initial, référentiels, PSA)
```

### Où agit chaque dispositif

Une même attaque (« un processus d'un conteneur de MédiAgenda lit le jeton de son compte de service et parle à l'API ») traverse plusieurs couches. Chacune a son outil et son moment :

| Couche | Ce qu'on protège | Moment | Outil du module | Exercices |
|---|---|---|---|---|
| Hôte | noyau, comptes, SSH, journaux de la VM | en continu | rôle `durcissement`, auditd, AIDE, AppArmor, SELinux | E03, E04, E10-E14 |
| Image | ce qui entre dans le registre | à la construction | Harbor, Trivy, Cosign (M13) | rappel |
| Admission | ce que le cluster accepte de créer | à l'écriture dans l'API | Pod Security, Kyverno, VAP/MAP | E06, E07, E15-E18 |
| Exécution | ce que font réellement les processus | pendant que ça tourne | Falco (détecte), Tetragon (observe, bloque) | E08, E19, E20, E29 |
| Réseau | qui parle à qui, en clair ou non | à chaque paquet | Cilium (politiques, WireGuard, pare-feu d'hôte) | E26, E27 |
| Réponse | limiter, comprendre, réparer | après la détection | quarantaine, preuves, runbooks | E33, E42 |

Aucune couche ne suffit seule. Une admission parfaite ne voit pas un conteneur compromis par une faille de l'application ; une détection parfaite arrive après le fait ; un hôte durci ne sait rien de ce qu'un pod a le droit de faire. C'est la **défense en profondeur**.

---

## Le chemin imposé

1. **Mesurer avant d'agir.** Chaque réglage du module est précédé d'une mesure (Lynis, OpenSCAP, kube-bench, rapports de Kyverno, avertissements de Pod Security) et suivi d'une seconde : le score avant/après est la preuve qu'attend l'auditeur.
2. **Essayer sur du jetable.** Les mesures d'OpenSCAP et le rôle `durcissement` (palier 2) passent d'abord par `durci-deb` et `durci-rocky` (état OpenTofu `envs/m26`), seules VMs modifiées avant que le rôle ne soit éprouvé.
3. **Auditer avant d'imposer.** Pod Security en `warn`/`audit` avant `enforce` ; politiques Kyverno en `Audit` avant `Deny` ; Falco et Tetragon en détection avant tout blocage.
4. **Tout en code.** Espaces et RBAC dans `plateforme/k8s` (`espaces/`, `rbac/`, `task appliquer`) ; composants du cluster par Argo CD (`plateforme/gitops`, charts recopiés par `plateforme/charts-miroir`) ; politiques et règles dans **`plateforme/politiques`** (créé en E07) ; VMs par `plateforme/infra` et `plateforme/ansible` ; documentation dans `docs/securite/durcissement/` de `plateforme/medisphere`.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Surface d'attaque et moindre privilège.** La surface d'attaque est tout ce qu'un attaquant peut toucher : ports ouverts, comptes, paquets installés, appels système permis, droits d'un compte de service. Durcir, c'est la **réduire** (retirer ce qui ne sert pas) et donner à chaque composant le **moindre privilège** (les droits dont il a besoin, pas un de plus). Un service qui n'existe pas n'a pas de faille.

**Prévenir, détecter, répondre.** Un contrôle **préventif** empêche (pare-feu, admission qui refuse, `noexec`) ; un contrôle **détectif** signale (Falco, AIDE, auditd, analyse OpenSCAP) ; un contrôle **correctif** répare ou limite (quarantaine, retour arrière, correctif). Un dispositif peut changer de catégorie : Kyverno en `Audit` détecte, en `Deny` prévient.

**Un conteneur n'est pas une frontière de sécurité.** Les conteneurs d'un nœud partagent **le même noyau**. Ce qui les sépare : les espaces de noms (*namespaces*) du noyau (ce que le processus voit), les *cgroups* (ce qu'il consomme), les **capacités** (*capabilities* : morceaux du pouvoir de root, comme `NET_ADMIN` ou `SYS_ADMIN`), **seccomp** (filtre des appels système), et un **LSM** (*Linux Security Module* : AppArmor sur Debian, SELinux sur Rocky) qui confine les accès aux fichiers et aux ressources. Retirer une de ces barrières (`privileged: true`, `hostPID`, un montage `hostPath` de `/`, le socket de containerd) donne souvent la main sur le nœud entier.

**Pod Security Admission.** Contrôleur intégré au kube-apiserver, configuré par **étiquettes d'espace** : trois profils (`privileged` : rien n'est interdit ; `baseline` : pas d'accès à l'hôte ni de privilège ; `restricted` : non-root, capacités retirées, seccomp, pas d'escalade), trois modes (`enforce` refuse, `warn` avertit le client, `audit` annote le journal d'audit), chacun avec une **version** de profil. Simple et sans dépendance, mais grossier : un espace entier, trois niveaux, aucune exception par pod.

**Moteurs de politiques.** Pour le reste (registres autorisés, étiquettes obligatoires, signatures, limites, valeurs par défaut), un **moteur de politiques** reçoit chaque requête d'écriture par un *webhook* d'admission et répond « oui », « non » ou « oui, mais modifié ». **Kyverno** décrit ses politiques en YAML et, depuis la 1.14, en **CEL** (le langage d'expressions des politiques natives de Kubernetes) ; il produit aussi des **rapports** (`PolicyReport`) en réévaluant l'existant. En 1.19, les anciennes `ClusterPolicy` sont **dépréciées** (supprimées en 1.20) : le module n'écrit que des `ValidatingPolicy`, `ImageValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy` et `PolicyException` (`policies.kyverno.io/v1`). Kubernetes a aussi ses politiques **natives** en CEL (ValidatingAdmissionPolicy depuis 1.30, MutatingAdmissionPolicy GA en 1.36), sans webhook : comparées en E17. Un webhook a un coût : s'il ne répond pas, l'API applique sa `failurePolicy` (`Fail` refuse tout ce qu'il couvre, `Ignore` laisse tout passer).

**Détection à l'exécution.** **Falco** observe les appels système de tous les processus du nœud (sonde eBPF `modern_ebpf`, chargée dans le noyau), les enrichit du contexte du conteneur et du pod, et les confronte à des **règles** (« un shell avec terminal a été lancé dans un conteneur », « un fichier sensible a été lu par un programme inattendu »). Il ne bloque rien. **Tetragon** (palier 2) observe aussi, au niveau du noyau, et peut **tuer** un processus ou **refuser** un appel au moment où il se produit.

**Référentiels.** Un **référentiel** (*benchmark*) liste des réglages vérifiables. **CIS** publie des *Benchmarks* par système (Debian 13, RHEL 10, Kubernetes) en deux niveaux (1 : raisonnable partout ; 2 : défense renforcée, au prix de fonctionnalités) ; l'**ANSSI** publie le guide **BP-028** (configuration de GNU/Linux) en quatre niveaux (minimal, intermédiaire, renforcé, élevé) ; la **DISA** publie des STIG pour l'administration américaine. **ComplianceAsCode** (projet libre, ex-SCAP Security Guide) traduit ces référentiels en contenu **SCAP** exécutable par **OpenSCAP** : un *datastream* par système, des **profils** (une sélection de règles par référentiel et niveau), des règles avec leur vérification (OVAL) et leur correction (Bash, Ansible). **Conformité n'est pas sécurité** : un score de 100 % prouve qu'on a appliqué une liste, pas qu'on est à l'abri.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | **Lynis 3.1.7** (archive amont vérifiée ; Debian 13 n'a que la 3.1.4) ; **ssh-audit 3.9** (`uv tool`) ; **OpenSCAP 1.4** (`openscap-scanner` 1.4.2 Debian, 1.4.4 Rocky) ; **ComplianceAsCode 0.1.82** ; **kube-bench 0.16.0** ; **kubescape 4.0** (CLI) ; **Kyverno 1.19.2** (chart `kyverno/kyverno` **3.9.2**) et sa CLI ; **Falco 0.45.1** (chart `falcosecurity/falco` **9.2.1**), falcosidekick **2.31.1** (sous-chart 0.14.1) |
| Changements de version | [`annexes/versions-bloc-F.md`](../../../annexes/versions-bloc-F.md), section « Durcissement et sécurité runtime » : `ClusterPolicy` dépréciée, kube-bench sans référentiel pour 1.36, Falco sans gRPC ni sonde eBPF historique, contenu SCAP de Debian 13 absent des paquets |
| Contenu SCAP | **Debian 13** : archive amont `scap-security-guide-0.1.82.zip` (SHA-512 publiée à côté), dépliée dans **`/usr/local/share/scap/ssg-0.1.82/`**, *datastream* **`ssg-debian13-ds.xml`** ; **Rocky 10** : paquet `scap-security-guide` 0.1.82 d'AppStream, *datastream* **`/usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml`** (le `ssg-rhel10-ds.xml` ne s'applique pas à Rocky : plate-forme CPE de RHEL seulement) |
| Profils retenus | Debian 13 : `xccdf_org.ssgproject.content_profile_cis_level1_server` (CIS Debian 13 v1.0.0, niveau 1 serveur) et `…_anssi_bp28_intermediary` ; Rocky 10 : `…_cis_server_l1` (CIS RHEL 10, niveau 1 serveur) et `…_anssi_bp28_intermediary` |
| VMs d'essai | **`durci-deb`** (VMID **2261**, Debian 13 `deb13-gold` `current`) et **`durci-rocky`** (**2262**, `rocky10-gold` `current`) ; `vsandbox`, DHCP (noms par le DDNS de Kea), 2 vCPU, **2 Go**, 32 Gio ; état OpenTofu **`envs/m26`** de `plateforme/infra` ; étiquettes `env-m26`, `role-durcissement` ; créées en E04, **détruites à la fin d'E14** |
| Résultats OpenSCAP | sur la VM : **`/var/lib/conformite/essais/`** (`<profil>-<AAAAMMJJ>.arf.xml` et `.html`) ; copie et synthèse sur `adm01` dans `~/m26/e04/` |
| Kyverno | Application Argo CD **`kyverno`**, espace **`kyverno`** (PSA `restricted`), contrôleur d'admission ×3 ; images par le cache `ghcr` de Harbor ; politiques dans **`plateforme/politiques`** (`kyverno/validation/`, `kyverno/tests/`…), Application **`politiques`** (Kustomize) |
| Falco | Application Argo CD **`falco`**, espace **`falco`** (PSA `privileged`, exception écrite), pilote **`modern_ebpf`**, règles par défaut de l'image ; falcosidekick vers **Alertmanager** (`http://kps-alertmanager.supervision.svc:9093`, `/api/v2/alerts`) et **Loki** (`http://loki.journaux.svc:3100`, locataire **`audit`**, étiquette `service="falco"`) |
| Documentation | `docs/securite/durcissement/` de `plateforme/medisphere` : `modele-menace.md` (E02), `etat-initial.md` (E03), `referentiels.md` (E04), `mesure-k8s-par1.md` et `mesures/k8s-par1/` (E05), `pod-security.md` (E06) ; puis `exceptions.md`, ADR-0260 et RB-260 à RB-265 aux paliers suivants |
| Tickets | PLAT-27xx, SEC-27xx, DEV-27xx, CHG-27xx, INC-53xx (xx = exercice) |
| Brouillons | `~/m26/eXX/` sur `adm01` (non versionnés, **sans secret**) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton identifiant (GitLab, annuaire) |
| `<NOEUD>` | Le nœud Proxmox (`pve01`) |
| `<VERSION-TOFU-MODULES>` | La dernière étiquette publiée de `plateforme/tofu-modules` (module `vm-noeud` avec cartes DHCP, M12-E02) |
| `<AAAAMMJJ>` | La date du jour, dans les noms de rapports |

### Variables de `lab/lab.env`

Toutes **facultatives** : ne les définis que si ton lab s'écarte des valeurs par défaut.

```
#WB_M26_HOTES_MESURE="gw01 git01 mon01 ipa01"   # VMs mesurées par Lynis en E03 (alias SSH)
#WB_M26_DURCI_DEB=durci-deb                     # alias SSH de la VM d'essai Debian (E04)
#WB_M26_DURCI_ROCKY=durci-rocky                 # alias SSH de la VM d'essai Rocky (E04)
#WB_M26_NOEUDS=6                                # nœuds de k8s-par1 (DaemonSet de Falco)
```

---

## Règles du module

1. **Mesurer n'est pas modifier.** Au palier 1, sur les VMs du socle, tu ne lances que des commandes de consultation (Lynis audite sans corriger ; ssh-audit se connecte comme un client). Toute modification du socle attend le rôle `durcissement` éprouvé sur les VMs d'essai (palier 2).
2. **Auditer avant d'imposer, un espace à la fois.** Aucune étiquette `enforce` de Pod Security, aucune politique en `Deny`, aucun blocage sans avoir lu, avant, ce qui serait refusé. Jamais de politique ni d'étiquette sur `kube-system`, `kyverno` ou `argocd`.
   > ⚠️ **Attention** : une admission qui refuse arrête les **déploiements**, pas les pods déjà en marche ; mais au premier redémarrage, au premier nœud drainé, les pods recréés sont refusés. Retour arrière d'une étiquette Pod Security : remettre l'ancienne valeur dans `plateforme/k8s/espaces/` et `task appliquer` (ou, en urgence, `kubectl label ns <espace> pod-security.kubernetes.io/enforce=<ancien niveau> --overwrite`, puis la MR). Retour arrière d'une politique Kyverno : repasser `validationActions` à `[Audit]` par une MR (Argo CD synchronise en une minute) ; si Argo CD lui-même est bloqué, `kubectl delete validatingpolicy <nom>` avec `admin.conf` et la MR ensuite.
3. **Un accès de secours ouvert.** Les paliers suivants touchent SSH, sudo, PAM, le pare-feu des nœuds : comptes de bris de glace du M24 (RB-240) **essayés** et accès console Proxmox (`root@pam`) vérifié avant chaque vague. Au palier 1, prépare-les (voir ci-dessous).
4. **Aucun secret** sur une ligne de commande, dans Git ou dans un rapport. Les rapports de Lynis, d'OpenSCAP et de kubescape peuvent contenir des noms de comptes, des chemins et des versions vulnérables : ils vont dans le dépôt de documentation (accès restreint), jamais dans un ticket public, et sont **relus** avant le commit.
5. **Mémoire.** Profil du bloc F ≈ 111 Go sur 128 Go. Les VMs d'essai ajoutent **4 Go** (deux fois 2 Go) d'E04 à E14 : rien d'autre de temporaire ne tourne pendant ce temps (pas de `idp02`, `bao-essai`, `bao-restauration`), et tu arrêtes `durci-rocky` quand tu ne t'en sers pas. Kyverno ajoute environ 1 Go dans le cluster (sept pods), Falco de 200 à 300 Mo par nœud (ses valeurs par défaut en *réservent* 512 Mo : E08 les ajuste).

---

## Préparer `adm01` et le lab

Vérifie d'abord l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 25 46        # mini-projet du M25 : secrets-v1
admin@adm01:~$ lab/bin/check 24 46        # identité-v1 : SSO, bris de glace
admin@adm01:~$ kubectl get nodes          # six nœuds Ready, v1.36.x
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

**Sauvegardes avant le palier 2.** Le palier 1 ne modifie pas le socle, mais le palier 2 le fera. Pendant ce palier, assure-toi que **toutes** les VMs du socle ont une sauvegarde PBS de moins de 24 heures (`proxmox-backup-client` ou l'interface de PBS, espaces `par1/…`) et note la date dans `~/m26/preparation.md`. Une restauration est le retour arrière ultime d'une vague ratée (RB-263).

**Accès de secours.** Ouvre une fois la console Proxmox de `adm01` et d'une VM du socle (`root@pam`, interface web de `pve01`) ; reprends la liste des comptes de bris de glace du M24 (RB-240 : `admin` local des VMs, `root` de GitLab, `kc-secours`, `admin.conf`, `root@pam`) et vérifie que tu sais où chacun est rangé. Note le résultat dans `~/m26/preparation.md`.

**Outils.** Installe ceux du palier sur `adm01` (versions exactes ; empreintes à vérifier sur la page de publication de chaque projet) :

```
admin@adm01:~$ uv tool install ssh-audit==3.9.0 && ssh-audit -h | head -n 3
admin@adm01:~$ kyverno version            # binaire kyverno-cli_v1.19.2_linux_x86_64.tar.gz de la publication GitHub
admin@adm01:~$ kubescape version          # 4.0.x, binaire de la publication GitHub
admin@adm01:~$ helm version --short && jq --version && yq --version
```

Si un rôle de `plateforme/ansible` gère les outils d'`adm01` (rôle `outils_k8s` du M14, enrichi aux modules suivants), ajoute plutôt les binaires `kyverno` et `kubescape` à ce rôle, avec leur empreinte.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 26 <XX>`. Elles sont en lecture seule : SSH en consultation (`sudo -n` de lecture) sur les VMs mesurées, `qm config` sur `pve01`, API du cluster par le compte `wb-checks` (ClusterRole agrégée `wb-checks-securite`, étendue en E07 aux politiques et rapports de Kyverno), requêtes Loki (locataire `audit`) et Prometheus, fichiers des dépôts par l'API de GitLab.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M26-EXX/` : `infra/` reproduit `plateforme/infra`, `k8s/` `plateforme/k8s`, `gitops/` `plateforme/gitops`, `charts-miroir/` `plateforme/charts-miroir`, `politiques/` `plateforme/politiques`, `observabilite/` `plateforme/observabilite`, `medisphere/` la documentation ; `m26-eXX/` contient des outils et manifestes de travail pour `~/m26/eXX/`.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
              └ E04 et E05 sont indépendants : E05 peut se faire pendant une évaluation OpenSCAP
```

L'ordre de la carte est l'ordre de travail. E02 (modèle de menace) se relit après E05 : les mesures confirment ou corrigent tes hypothèses. E06 doit précéder E07 et E08 : les espaces `kyverno` et `falco` y trouvent leur place dans le registre de Pod Security.

Durée indicative du palier 1 : 15 à 19 heures.

## Pour aller plus loin

- CIS Benchmarks (Debian, RHEL, Kubernetes ; téléchargement après inscription) : <https://www.cisecurity.org/cis-benchmarks> · ANSSI, *Recommandations de configuration d'un système GNU/Linux* (BP-028) : <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux>
- ComplianceAsCode : <https://github.com/ComplianceAsCode/content> · OpenSCAP, manuel de l'utilisateur : <https://static.open-scap.org/openscap-1.3/oscap_user_manual.html>
- Kubernetes, *Pod Security Standards* et *Pod Security Admission* : <https://kubernetes.io/docs/concepts/security/pod-security-standards/> · *Security Checklist* : <https://kubernetes.io/docs/concepts/security/security-checklist/>
- Kyverno, politiques CEL : <https://kyverno.io/docs/policy-types/> · Falco : <https://falco.org/docs/> · kube-bench : <https://github.com/aquasecurity/kube-bench> · kubescape : <https://kubescape.io/docs/>
- NSA/CISA, *Kubernetes Hardening Guide* : <https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF> · MITRE ATT&CK, matrice *Containers* : <https://attack.mitre.org/matrices/enterprise/containers/>
