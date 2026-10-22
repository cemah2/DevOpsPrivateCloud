# Module 26 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `infra/` pour `plateforme/infra`, `k8s/` pour `plateforme/k8s`, `gitops/` pour `plateforme/gitops`, `charts-miroir/` pour `plateforme/charts-miroir`, `politiques/` pour `plateforme/politiques`, `observabilite/` pour `plateforme/observabilite`, `medisphere/` pour la documentation ; `m26-eXX/` contient les outils et manifestes de travail de `~/m26/eXX/`. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie ; un nom en `.extrait.yaml` ou `.extrait.md` ne montre que ce qui s'ajoute à un fichier existant.

**Ce qui a été vérifié à la rédaction** :
- **ComplianceAsCode 0.1.82** : archive `scap-security-guide-0.1.82.zip` de la publication GitHub, SHA-512 identique à `scap-security-guide-0.1.82.zip.sha512` ; liste des *datastreams* (pas de `ssg-rl10` ni d'AlmaLinux 10 dans l'archive amont) ; paquet `scap-security-guide-0.1.82-2.el10_2.rocky.1.1` d'AppStream de Rocky 10 déballé : il livre `ssg-rl10-ds.xml` **et** `ssg-rhel10-ds.xml` ; dictionnaires CPE comparés (`cpe:/o:rocky:rocky:10` dans le premier seulement) ; `oscap info --profiles` sur `ssg-debian13-ds.xml`, `ssg-rl10-ds.xml` et `ssg-rhel10-ds.xml` (identifiants de profils repris tels quels dans ce corrigé) ; décompte des règles par profil (`oscap xccdf generate fix`) ; `oscap xccdf eval --profile <id court> --results-arf --report` (OpenSCAP 1.3.9 du bac à sable, pas 1.4 : syntaxe identique), format de l'ARF (`<result>…</result>`, `<score system="urn:xccdf:scoring:default">`), avertissement sur la ressource OVAL distante de Debian ;
- **Lynis 3.1.7** : archive téléchargée, SHA-256 identique à celle de la page de CISOfy ; audit réel (`--quick --no-colors --auditor --report-file`), clés du rapport (`lynis_version`, `hardening_index`, `warning[]`, `suggestion[]`), liste des options ; la partie distante de `lynis-mesurer.sh` exécutée localement (dépliage, audit, nettoyage, rapport) ;
- **ssh-audit 3.9.0** (PyPI) : options `-P`, `-L`, `--get-hardening-guide`, politiques intégrées `Hardened Debian 13 (version 1)` et `Hardened Rocky Linux 10 (version 1)` ;
- **kube-bench 0.16.0** (module Go à l'étiquette) : `cfg/config.yaml` (`cis-1.12` ↔ 1.32-1.34, cibles), options `--benchmark`, `--targets`, `--json`, structure JSON (`Controls[].version`, `node_type`, `Totals.total_*`), identifiants et intitulés des contrôles cités ; image `aquasec/kube-bench:v0.16.0` présente sur Docker Hub ; Jobs validés par kubeconform 0.7 ;
- **kubescape 4.0.16** : archive vérifiée (`checksums.sha256`), `kubescape list frameworks` (`NSA`, `MITRE`, `cis-v1.12.0`…), options de `scan framework` (`--keep-local`, `--format json`, `--output`), structure du JSON produit, `kubescape-resume.sh` exécuté sur un rapport réel ;
- **Kyverno** : chart 3.9.2 (empreinte de l'index recalculée) rendu avec les values du corrigé : CRD et versions servies (`v1` servie, `v1beta1` stockée), images (toutes par Harbor, *hooks* compris), contextes de sécurité conformes à `restricted`, ServiceMonitor ; images `ghcr.io/kyverno/*:v1.19.2` présentes ; dans le code de Kyverno 1.19.2 : étiquette `webhook.kyverno.io/managed-by`, nom `kyverno-resource-validating-webhook-cfg`, webhooks `vpol.validate.kyverno.svc-ignore|fail`, fusion du `namespaceSelector` de la politique avec `config.webhooks` ; **CLI 1.19.2** : les deux politiques passent `kyverno test` (9 assertions, dont l'*autogen* sur un Deployment et un espace hors périmètre) et `kyverno apply` (messages cités) ; l'image de la CLI n'a pas de shell (d'où le job de CI) ;
- **kube-apiserver 1.36** : ordre des greffons d'admission dans `pkg/kubeapiserver/options/plugins.go` (PodSecurity, …, MutatingAdmissionPolicy, MutatingAdmissionWebhook, ValidatingAdmissionPolicy, ValidatingAdmissionWebhook) ;
- **Falco** : chart 9.2.1 (empreinte recalculée) rendu avec les values du corrigé (`falco.yaml` généré, DaemonSet, tolérances, ressources, Secret de falcosidekick) ; image `falcosecurity/falco:0.45.1` inspectée couche par couche : `/etc/falco/falco_rules.yaml`, greffon `libcontainer.so`, `config.d/falco.container_plugin.yaml` ; conditions des règles « Terminal shell in container » (NOTICE, `proc.tty != 0`) et « Read sensitive file untrusted » (WARNING, `open_read` = ouverture réussie, shells exclus) ; **falcosidekick 2.31.1** (code à l'étiquette) : chemin par défaut `/api/v1/alerts`, étiquettes Loki (`rule`, `source`, `priority`, `k8s_ns_name`, `k8s_pod_name`, champs personnalisés), `customfields` injectés dans les champs de sortie, métriques `falcosecurity_falcosidekick_outputs_total{destination,status}` ; le sous-chart 0.14.1 tire 2.32.0 par défaut ;
- **OpenTofu 1.13.2** : `envs/m26` validé (`tofu validate`) avec un module factice ayant les variables du `vm-noeud` du M12, `tofu fmt` propre ;
- `psa-inventaire.sh` exécuté contre un `kubectl` simulé ; tous les scripts (checks, outils) : `bash -n` et `shellcheck -x` ; checks exécutés dans un banc qui simule des réponses vides et des réponses conformes.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- **Rien n'a tourné sur un vrai `k8s-par1`** : l'installation de Kyverno et de Falco par Argo CD, l'état `ready` des `ValidatingPolicy` (`status.conditionStatus.ready`), le contenu exact des `PolicyReport`, l'affichage par `kubectl` des avertissements `Warn` de Kyverno, le chargement de la sonde `modern_ebpf` sur Debian 13 et les métadonnées de conteneur par le greffon `container` (socket `/run/containerd/containerd.sock`), le fonctionnement de falcosidekick avec `readOnlyRootFilesystem`, et le fait qu'Argo CD ignore le pod de test Helm du sous-chart falcosidekick ;
- **OpenSCAP 1.4 sur Debian 13** : les vérifications SCE du contenu Debian (moteur SCE de `libopenscap`), la durée d'une évaluation, le résultat exact (`notchecked` ou `error`) de la règle qui lit le flux OVAL distant de Debian ; la présence de `ssg-rl10` dans l'ARF produit sur Rocky (le check s'en sert) ;
- les **résultats** de kube-bench sur nos nœuds kubeadm (le tableau du corrigé est celui qu'on attend, pas un relevé) et la création par containerd des dossiers `hostPath` absents ;
- les noms DDNS des VMs d'essai (`durci-deb`, `durci-rocky`) dans la zone que Kea met à jour (comme au M12) ;
- Lynis sur `gw01` et sur `ipa01` (Rocky) : indices et durées.

---

### M26-E01 — Test de positionnement : sécurité des systèmes et de Kubernetes

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 28. En dessous de 14, relis les « Concepts clés » de l'introduction avant E06 ; les questions 5 à 9 sont reprises en E13, E21 et E44, 10 à 12 en E06, E07 et E17, 13 et 14 en E04 et E09.

**1. Surface d'attaque.** Tout ce par quoi on peut atteindre la VM ou y agir. Sur `git01` : (a) les **ports ouverts** (22, 443, 5050 du registre si activé…) → n'écouter que sur l'interface utile, pare-feu local et de bordure ; (b) les **comptes** (locaux, de service, clés SSH autorisées) → comptes nominatifs SSO, plus de mot de passe SSH, `AllowGroups` ; (c) les **paquets installés** (compilateurs, outils de débogage) → image minimale, retrait de ce qui ne sert pas ; (d) les **services** actifs (`avahi`, `cups`, serveur de courrier local) → désactivation ; (e) l'**application** elle-même (GitLab, ses greffons, ses jetons) → mises à jour, fonctionnalités inutiles coupées, jetons à durée courte. Les droits des fichiers sensibles et le noyau (modules chargeables, `sysctl`) en font aussi partie.

**2. Moindre privilège.** Chacun ne reçoit que les droits nécessaires à sa tâche, pour la durée nécessaire. Pod de MédiAgenda : un compte de service dédié, **sans** jeton monté s'il ne parle pas à l'API (`automountServiceAccountToken: false`), aucun `Role` hors besoin, non-root, capacités retirées, système de fichiers en lecture seule. Compte `admin` d'Ansible : il a besoin de sudo sans mot de passe pour automatiser, donc on restreint **qui peut l'utiliser** (clé SSH du seul pipeline et d'`adm01`, pas de mot de passe), on journalise tout ce qu'il fait (auditd, E12) et on le garde comme bris de glace ; les personnes passent par leur compte SSO et sudo par groupe (M24).

**3. Défense en profondeur.** Superposer des contrôles indépendants pour qu'une défaillance n'ouvre pas tout. Pour l'exécution de code dans l'API : (a) **le conteneur** non-root, sans capacité, seccomp `RuntimeDefault`, système de fichiers en lecture seule : l'attaquant ne peut ni installer d'outil ni monter des privilèges ; (b) **l'admission** (Pod Security, Kyverno) a empêché qu'un pod privilégié ou un `hostPath` existe dans l'espace ; (c) **le réseau** : la NetworkPolicy par défaut de l'équipe (M15) l'empêche de joindre autre chose que la base et Valkey ; (d) **la détection** : Falco et Tetragon voient un shell, un binaire déposé, une connexion inattendue, et alertent ; (e) **le RBAC** : le jeton du pod (s'il existe) ne permet rien. Les **secrets dynamiques** (M25) limitent la durée de vie de ce qu'il pourrait voler.

**4. Réponse B.** Falco **signale** (détectif). A est **préventif** (empêche l'exécution depuis `/tmp`). C est préventif (l'admission refuse). D est **correctif** (rétablit). Un même outil change de catégorie selon son mode : Kyverno en `Audit` est détectif.

**5. Pas une petite VM.** Une VM a son **propre noyau**, isolé par l'hyperviseur (matériel virtualisé, frontière étroite et éprouvée). Un conteneur est un **processus** de l'hôte, isolé par des mécanismes du noyau partagé : les *namespaces* (PID, réseau, montages, utilisateurs, UTS, IPC : ce que le processus voit), les *cgroups* (ce qu'il consomme), les **capacités**, **seccomp** et un **LSM**. Tous les conteneurs du nœud partagent **le noyau** (une faille du noyau est une évasion), mais aussi souvent le runtime (containerd), le kubelet et ses jetons, le système de fichiers de l'hôte s'il est monté.

**6. Capacités.** Root est découpé en une quarantaine de **capacités** que le noyau vérifie une par une. Dangereuses pour un conteneur : `CAP_SYS_ADMIN` (monter des systèmes de fichiers, manipuler les espaces de noms : proche de root complet, chemin classique d'évasion), `CAP_NET_ADMIN` (modifier les interfaces, les règles de filtrage, écouter le trafic), `CAP_SYS_PTRACE` (s'attacher aux autres processus, lire leur mémoire), `CAP_SYS_MODULE` (charger un module noyau). `capabilities: {drop: [ALL]}` retire toutes les capacités, y compris celles que containerd donne par défaut (`CHOWN`, `NET_RAW`, `SETUID`…) ; `restricted` n'autorise ensuite à rajouter que `NET_BIND_SERVICE`.

**7. Réponse B.** `privileged: true` donne toutes les capacités, l'accès aux périphériques (`/dev`), lève les filtres seccomp et le confinement AppArmor/SELinux, et rend `/sys` inscriptible : depuis un tel conteneur, monter le disque de l'hôte ou charger un module suffit à prendre le nœud. A décrit `NET_BIND_SERVICE`. C est faux : seccomp est levé. D est faux : même un utilisateur non-root d'un conteneur privilégié garde les périphériques et l'absence de confinement (et l'escalade vers root y est souvent triviale).

**8. seccomp.** Un filtre (BPF) des **appels système** qu'un processus peut faire : un appel refusé échoue (`EPERM`) ou tue le processus. `RuntimeDefault` est le profil du runtime (containerd) : il bloque une soixantaine d'appels rares et dangereux (`keyctl`, `bpf`, `mount` hors capacité, `unshare` de certains espaces, chargement de modules…) sans gêner les applications courantes. Kubernetes ne l'applique pas à tous les pods par défaut par **compatibilité** : historiquement les pods tournaient `Unconfined`, et l'imposer d'un coup aurait cassé des charges ; le kubelet peut le faire avec `seccompDefault: true` (E25), et `restricted` l'exige explicitement dans la spécification du pod.

**9. AppArmor et SELinux.** Deux **LSM** de **contrôle d'accès obligatoire** : des règles que root lui-même ne contourne pas, en plus des droits Unix. AppArmor désigne les objets par leurs **chemins** (`/var/lib/mailpit/** rw`) dans un profil attaché à un programme ; simple à écrire, mais un lien ou un autre chemin vers le même fichier change tout. SELinux étiquette **chaque objet et chaque processus** d'un contexte (`system_u:object_r:httpd_sys_content_t:s0`) et décide par des règles entre types ; plus fin et plus robuste (l'étiquette suit le fichier), plus difficile à maîtriser. `ipa01` (Rocky 10) : SELinux *enforcing* ; `git01` (Debian 13) : AppArmor.

**10. Le chemin d'un `kubectl apply`.** Authentification (qui ?) → autorisation (RBAC : a-t-il le droit de créer un Deployment ici ?) → **admission mutante** (contrôleurs intégrés comme `ServiceAccount` ou `LimitRanger`, MutatingAdmissionPolicy, webhooks mutants dont ceux de Kyverno) → validation du schéma → **admission validante** (**PodSecurity**, ValidatingAdmissionPolicy, webhooks validants dont **Kyverno**, `ResourceQuota`) → écriture dans etcd. Pod Security évalue les **pods** : pour un Deployment, il ne fait qu'avertir. Le Deployment est donc accepté ; son ReplicaSet est créé ; c'est quand le contrôleur de ReplicaSet crée les **pods** que Pod Security les refuse (événement `FailedCreate`) : aucun pod, et `kubectl apply` a pourtant « réussi ». C'est pourquoi Kyverno génère aussi les règles des contrôleurs (*autogen*).

**11. Réponse B.** L'admission n'agit qu'à l'**écriture** : poser l'étiquette ne touche pas aux pods en marche ; l'API renvoie un avertissement qui liste les pods existants non conformes ; le jour où le pod est recréé (redémarrage du nœud, `rollout restart`, éviction), le nouveau est refusé. A et D sont faux (Pod Security ne tue ni ne modifie rien), C aussi (l'étiquette est acceptée, avec un avertissement). D'où la démarche d'E06 : essai à blanc, correction, puis application.

**12. Depuis un shell dans un pod.** (a) Le **jeton du compte de service** monté dans `/var/run/secrets/kubernetes.io/serviceaccount/token` → s'il a des droits, il parle à l'API ; refusé par `automountServiceAccountToken: false` et un RBAC minimal. (b) Les **variables d'environnement** et fichiers montés (secrets de base de données, clés d'API) → secrets courts et dynamiques (M25), montés seulement dans le conteneur qui en a besoin. (c) Le **réseau** : l'API (`kubernetes.default`), le kubelet des nœuds (10250), les métadonnées, les autres services → NetworkPolicy de sortie par défaut, pare-feu d'hôte (E27). (d) L'**hôte** si un montage `hostPath`, le socket de containerd, des capacités ou `hostPID` existent → refusés par `restricted`. (e) Des outils dans l'image (`curl`, shell, gestionnaire de paquets) → image minimale, système de fichiers en lecture seule.

**13. Référentiels.** **CIS** (*Center for Internet Security*, organisme américain à but non lucratif, consensus de praticiens) : *Benchmarks* par produit (Debian 13, RHEL 10, Kubernetes…), niveaux 1 et 2, reconnus internationalement et outillés (OpenSCAP, kube-bench). **ANSSI-BP-028** (agence nationale française) : recommandations de configuration de GNU/Linux, quatre niveaux, attendues des organismes français et des hébergeurs sensibles ; plus orientées principes que réglages exacts. **STIG** (DISA, Défense américaine) : très prescriptifs, obligatoires pour les systèmes du département de la Défense, sans valeur particulière pour un auditeur HDS. MédiSphère retient CIS (outillage, reconnaissance par les auditeurs ISO 27001/HDS) et ANSSI (référence nationale, attendue en santé), les deux étant couverts par ComplianceAsCode.

**14. 92 % de conformité.** (a) Le score dit qu'on respecte **une liste**, pas qu'on résiste à une attaque (une application vulnérable sur un serveur « conforme » reste vulnérable) ; (b) les règles `notapplicable` ou `notchecked` n'entrent pas dans le score (un mauvais contenu peut donner 100 % sans rien mesurer) ; (c) les 8 % manquants peuvent être les plus graves ; (d) le niveau 1 laisse de côté des mesures fortes ; (e) c'est une photo : la dérive arrive le lendemain. Questions à poser : *quel contenu et quel profil, dans quelle version ?* ; *combien de règles non applicables ou non vérifiées ?* ; *quelles sont les règles en échec et sont-elles des exceptions signées ?* ; *quand a eu lieu la mesure, et est-elle automatique ?* ; *qu'est-ce qui n'est pas mesuré (application, réseau, Kubernetes) ?*

---

### M26-E02 — Modèle de menace de la plateforme

**Solution**

Document complet : [`modele-menace.md`](fichiers/M26-E02/medisphere/docs/securite/durcissement/modele-menace.md). Sa construction suit l'énoncé : périmètre et hypothèses, actifs (avec criticité), six acteurs, schéma des sept frontières de confiance et tableau de leurs contrôles, STRIDE pour sept composants, dix menaces notées V × I, et ce que le modèle ne dit pas.

Grille de relecture (celle de Sophie) :
- les dix menaces sont **les nôtres** (elles nomment un composant du lab et un chemin réaliste), pas des généralités ;
- chaque menace a un contrôle existant **avec son module** (« PSA posée en M14-E18 sur une partie des espaces »), ce qui montre qu'on connaît sa plateforme ;
- chaque manque renvoie à un exercice : le module devient le **plan de traitement** des risques, ce qu'attend l'auditeur ;
- les priorités se défendent : le risque 7 (écoute du VLAN 40) est noté bas en vraisemblance (il faut déjà être sur le VLAN), haut en impact (données de santé en clair) ;
- aucune information exploitable : pas de version vulnérable non corrigée, pas d'adresse personnelle, pas de secret.

**Explications**

Un modèle de menace répond à quatre questions (*Threat Modeling Manifesto*) : sur quoi travaille-t-on, qu'est-ce qui peut mal tourner, que fait-on contre, a-t-on bien travaillé ? STRIDE sert de **liste de contrôle** par composant pour ne rien oublier ; la notation V × I sert à **ordonner**, pas à calculer un risque exact. Les frontières de confiance sont là où une donnée ou une requête passe d'un niveau de confiance à un autre : c'est là qu'on place les contrôles (authentification, filtrage, validation). Partir des **actifs** (données de santé) plutôt que des outils évite de durcir ce qui n'a pas de valeur et d'oublier ce qui en a (les sauvegardes, la clé de signature).

**Alternatives**

- *Arbres d'attaque* : partir d'un objectif de l'attaquant (« lire les dossiers patients ») et dérouler les chemins ; excellent pour une menace précise, lourd pour une plateforme entière.
- *MITRE ATT&CK* (matrice *Containers*) et la *Threat Matrix for Kubernetes* : catalogues de techniques observées ; utiles pour vérifier qu'aucune tactique n'est oubliée, et pour relier menaces et détections (E19).
- *EBIOS Risk Manager* (ANSSI) : méthode française d'analyse de risques, attendue dans certains contextes publics et de santé ; plus complète (scénarios stratégiques et opérationnels, parties prenantes), plus lourde. Le modèle d'E02 en est un bon point de départ pour l'atelier technique.
- *PASTA*, *LINDDUN* (vie privée) : cités ; LINDDUN est pertinent pour les données de santé (identifiabilité, divulgation).

**Pièges classiques**

- Un catalogue de 80 menaces génériques que personne ne lira ni ne traitera.
- Oublier la **chaîne de livraison** : le runner et la clé de signature sont des actifs critiques (qui signe une image piégée a la production).
- Oublier les **sauvegardes** (cible première d'un rançongiciel) et les **comptes de bris de glace**.
- Noter tout à 9 : sans priorité, pas de plan.
- Écrire dans le document une faiblesse non corrigée de façon exploitable (« le port X de Y accepte Z sans authentification ») : un modèle de menace se diffuse, il doit rester utile sans devenir un mode d'emploi.

**En production chez MédiSphère**

Le modèle est revu à chaque nouveau composant exposé (revue d'architecture de Karim), à chaque incident (post-mortem → nouvelle menace ou contrôle défaillant) et une fois par an avec l'analyse de risques ISO 27005 de la RSSI. Ses dix menaces deviennent des **indicateurs** : pour chacune, un contrôle mesurable (score de conformité, couverture de l'admission, délai de détection Falco) suivi dans le tableau de bord de la sécurité (E34, E46).

---

### M26-E03 — Mesurer avant d'agir : Lynis et ssh-audit

**Solution**

1. Archive et vérification :
   ```
   admin@adm01:~/m26/e03$ curl -fsSLO https://downloads.cisofy.com/lynis/lynis-3.1.7.tar.gz
   admin@adm01:~/m26/e03$ sha256sum lynis-3.1.7.tar.gz
   b5314a07fd85fa3ffc7da57b508f0108ec3280d84e4af823f805d95cbbc2428c  lynis-3.1.7.tar.gz
   ```
   L'empreinte se compare à celle affichée sur `https://cisofy.com/downloads/lynis/` (c'est la valeur ci-dessus au moment de la rédaction ; relève-la toi-même, ne la recopie pas de ce corrigé).
2. Audit des quatre VMs par [`lynis-mesurer.sh`](fichiers/M26-E03/m26-e03/lynis-mesurer.sh), ou à la main pour la première :
   ```
   admin@adm01:~/m26/e03$ ssh admin@mon01 'd=$(sudo mktemp -d /root/lynis.XXXXXX) && sudo tar -xzf - -C "$d" && echo "$d"' < lynis-3.1.7.tar.gz
   /root/lynis.Ab12Cd
   admin@adm01:~/m26/e03$ ssh -t admin@mon01 'sudo sh -c "cd /root/lynis.Ab12Cd/lynis && ./lynis audit system --quick --no-colors --auditor <MOI>"'
   …
     Hardening index : 63 [############        ]
     Tests performed : 2xx
   admin@adm01:~/m26/e03$ ssh admin@mon01 'sudo sh -c "cd /root/lynis.Ab12Cd/lynis && ./lynis show details SSH-7408"'
   admin@adm01:~/m26/e03$ ssh admin@mon01 'sudo rm -rf /root/lynis.Ab12Cd'
   admin@adm01:~/m26/e03$ ./lynis-mesurer.sh lynis-3.1.7.tar.gz b5314a07…428c gw01 git01 mon01 ipa01
   gw01     Lynis 3.1.7  indice 6x   avertissements x   suggestions 3x
   …
   ```
   Le script envoie l'archive par l'entrée standard de SSH (rien ne transite par un dossier partagé), la déplie en root dans un dossier temporaire de `/root` (Lynis exige des fichiers appartenant à root quand il tourne en root), lance l'audit depuis ce dossier, le supprime, puis rapatrie `/var/log/lynis-report.dat`.
3. Lecture des avertissements. Typiquement (à confronter à tes rapports) :
   - `PKGS-7392` « vulnerable packages » : des mises à jour de sécurité en attente (selon la date de ton image dorée) → vrai sujet, traité par E30 ; CIS 1.2.x (« mises à jour appliquées »), ANSSI R61 ;
   - `FIRE-4512` ou équivalent sur une VM sans pare-feu local actif : sur `gw01`, nftables est actif (pas d'alerte) ; ailleurs, le filtrage est à la bordure → décision de défense en profondeur (pare-feu local par le rôle `pare_feu_local` existant ou non) ;
   - `AUTH-9230`/`AUTH-9286` (durée de vie et hachage des mots de passe), `ACCT-9628` (auditd absent), `FINT-4350` (pas d'outil d'intégrité) : vrais écarts au regard de CIS et ANSSI → E11, E12 ;
   - sur `ipa01`, des suggestions sur Apache, Kerberos ou le LDAP (`HTTP-6640`…) : souvent hors sujet (FreeIPA gère sa configuration) → à noter comme bruit, pas comme écart.
4. ssh-audit :
   ```
   admin@adm01:~$ ssh-audit -P "Hardened Debian 13 (version 1)" git01.par1.medisphere.internal
   …
   Host:   git01.par1.medisphere.internal
   Policy: Hardened Debian 13 (version 1)
   Result: ❌ Failed!
   Errors:
     * Key exchanges did not match. …
   admin@adm01:~$ ssh-audit -P "Hardened Rocky Linux 10 (version 1)" ipa01.par1.medisphere.internal
   ```
   Le verdict exact dépend de ce que les rôles communs du socle ont posé (`ssh_durci` du bloc A). Ce qui vient du lab : les **certificats d'hôte** `ssh-ed25519-cert-v01@openssh.com` (M06), la désactivation éventuelle de clés d'hôte RSA ; ce qui vient d'OpenSSH par défaut : des échanges de clés et des MAC que les politiques « Hardened » retirent, l'absence de limite de débit de connexion (la politique la teste, d'où un message sur le *connection rate*).
5. Document : [`etat-initial.md`](fichiers/M26-E03/medisphere/docs/securite/durcissement/etat-initial.md), avec trois constatations (hétérogénéité, SSH à aligner, absence de traçabilité locale) chacune reliée à un exercice.

**Explications**

- **Pourquoi l'archive et pas le paquet.** Mesurer ne doit pas modifier : installer un paquet ou ajouter le dépôt CISOfy sur `gw01` est un changement (sources apt, clé de dépôt). L'archive dépliée dans un dossier temporaire de `/root` et supprimée après laisse seulement le rapport et le journal dans `/var/log`. Debian 13 empaquette la 3.1.4, que Lynis considère comme ancienne (il le signale lui-même) : ses tests sont moins à jour. Le rôle `durcissement` (E24) installera Lynis durablement, par le dépôt CISOfy ou par l'archive épinglée.
- **L'indice de durcissement** est une moyenne pondérée des tests réussis, propre à Lynis : il sert à **comparer une VM à elle-même** dans le temps (et entre VMs de même rôle), pas à prouver une conformité. Changer le profil de Lynis (tests ignorés) change l'indice sans changer la sécurité.
- **ssh-audit** se connecte comme un client et lit ce que le serveur annonce (algorithmes, clés d'hôte, bannière), puis teste le débit de connexion. Il ne voit **pas** la configuration d'authentification (`PermitRootLogin`, `AllowGroups`, certificats d'utilisateur) : c'est le rôle de Lynis, d'OpenSCAP et de la revue de configuration.

**Alternatives**

- Lancer Lynis **à distance** sans rien copier : impossible, il s'exécute localement ; `lynis audit system remote` n'imprime que la marche à suivre.
- **OpenSCAP directement** sur le socle (E04) : mesure de conformité plus rigoureuse, mais demande d'installer `openscap-scanner` et le contenu ; réservé d'abord aux VMs d'essai.
- **Lynis Enterprise**, **Wazuh** (SCA), **Ansible-lockdown audit** (goss) : cités ; Wazuh apporte un agent permanent et une console, au prix d'une infrastructure de plus.

**Pièges classiques**

- Lancer `./lynis` hors de son dossier : « can't find include directory ».
- Déplier l'archive en `admin` puis lancer en root : Lynis s'arrête sur des fichiers qui n'appartiennent pas à root.
- Laisser l'archive dépliée sur la VM (outil d'audit = outil de reconnaissance pour un attaquant), ou la déposer dans `/tmp` lisible par tous.
- Copier `lynis-report.dat` tel quel dans le dépôt : il contient des noms de comptes, des versions de paquets vulnérables, des chemins ; seules les synthèses vont dans `etat-initial.md`.
- Conclure de l'indice : « 63, c'est mauvais ». Un indice se compare à lui-même après durcissement (E14, E46).

**En production chez MédiSphère**

Lynis tourne chaque semaine par le rôle (`/var/log/lynis-report.dat` → métrique `medisphere_lynis_indice`, E24) et ssh-audit en CI contre tous les hôtes après chaque changement du rôle SSH (E11), avec la politique MédiSphère générée par `ssh-audit -M` sur une VM de référence. Les rapports bruts sont conservés dans le compartiment `conformite` (accès restreint), pas dans GitLab.

---

### M26-E04 — OpenSCAP et ComplianceAsCode : évaluer une VM contre CIS et ANSSI

**Solution**

*A. Les VMs d'essai.* Environnement [`envs/m26/`](fichiers/M26-E04/infra/envs/m26/) : [`versions.tf`](fichiers/M26-E04/infra/envs/m26/versions.tf) (backend S3 `envs/m26/terraform.tfstate`), [`providers.tf`](fichiers/M26-E04/infra/envs/m26/providers.tf), [`variables.tf`](fichiers/M26-E04/infra/envs/m26/variables.tf) (carte `vms_essai`), [`durci.tf`](fichiers/M26-E04/infra/envs/m26/durci.tf) (module `vm-noeud` à cartes DHCP, MAC `bc:24:11:99:26:0n`, étiquettes `env-m26` et `role-durcissement`), [`terraform.tfvars.exemple`](fichiers/M26-E04/infra/envs/m26/terraform.tfvars.exemple).

```
admin@adm01:~/src/infra/envs/m26$ set -a; . ~/.config/workbook/pve-tofu.env; . ~/.config/workbook/netbox-tofu.env; set +a
admin@adm01:~/src/infra/envs/m26$ tofu init && tofu plan -out m26.plan
Plan: 6 to add, 0 to change, 0 to destroy.          # 2 VMs + leurs objets NetBox (selon la version du module)
admin@adm01:~/src/infra/envs/m26$ tofu apply m26.plan   # ou par le pipeline, selon ta pratique du M05
admin@adm01:~$ ssh admin@durci-deb 'hostnamectl --static; cat /etc/debian_version'
durci-deb
13.x
```

*B. Le contenu.* Sur Rocky :

```
[admin@durci-rocky ~]$ sudo dnf install -y openscap-scanner scap-security-guide
[admin@durci-rocky ~]$ rpm -q scap-security-guide
scap-security-guide-0.1.82-2.el10_2.rocky.1.1.noarch
[admin@durci-rocky ~]$ ls /usr/share/xml/scap/ssg/content/
ssg-rhel10-ds.xml  ssg-rl10-ds.xml
[admin@durci-rocky ~]$ oscap info --profiles /usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml
xccdf_org.ssgproject.content_profile_anssi_bp28_enhanced:ANSSI-BP-028 (enhanced)
xccdf_org.ssgproject.content_profile_anssi_bp28_high:ANSSI-BP-028 (high)
xccdf_org.ssgproject.content_profile_anssi_bp28_intermediary:ANSSI-BP-028 (intermediary)
xccdf_org.ssgproject.content_profile_anssi_bp28_minimal:ANSSI-BP-028 (minimal)
xccdf_org.ssgproject.content_profile_bsi:BSI SYS.1.1 and SYS.1.3
xccdf_org.ssgproject.content_profile_cis:CIS Red Hat Enterprise Linux 10 Benchmark for Level 2 - Server
xccdf_org.ssgproject.content_profile_cis_server_l1:CIS Red Hat Enterprise Linux 10 Benchmark for Level 1 - Server
xccdf_org.ssgproject.content_profile_cis_workstation_l1:CIS Red Hat Enterprise Linux 10 Benchmark for Level 1 - Workstation
xccdf_org.ssgproject.content_profile_cis_workstation_l2:CIS Red Hat Enterprise Linux 10 Benchmark for Level 2 - Workstation
xccdf_org.ssgproject.content_profile_e8:Australian Cyber Security Centre (ACSC) Essential Eight
xccdf_org.ssgproject.content_profile_hipaa:Health Insurance Portability and Accountability Act (HIPAA)
…
xccdf_org.ssgproject.content_profile_stig:DISA STIG for Red Hat Enterprise Linux 10
[admin@durci-rocky ~]$ grep -o 'cpe-item name="cpe:/o:[^"]*"' /usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml | sort -u
cpe-item name="cpe:/o:redhat:enterprise_linux:10"
cpe-item name="cpe:/o:rocky:rocky:10"
[admin@durci-rocky ~]$ grep -o 'cpe-item name="cpe:/o:[^"]*"' /usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml | sort -u
cpe-item name="cpe:/o:redhat:enterprise_linux:10"
```

Note bien le piège : dans le contenu RHEL 10, le profil CIS **niveau 2** s'appelle `…_cis` (sans suffixe) ; le niveau 1 serveur est `…_cis_server_l1`. Le `ssg-rhel10-ds.xml` ne déclare que la plate-forme RHEL : évalué sur Rocky, presque toutes les règles sortent `notapplicable` et le score ne mesure rien.

Sur Debian :

```
admin@durci-deb:~$ sudo apt install -y openscap-scanner unzip
admin@durci-deb:~$ apt show ssg-debian 2>/dev/null | grep -E '^(Version|Description)'
Version: 0.1.76-…                               # produits debian11 et debian12 seulement
admin@adm01:~/m26/e04$ curl -fsSLO https://github.com/ComplianceAsCode/content/releases/download/v0.1.82/scap-security-guide-0.1.82.zip
admin@adm01:~/m26/e04$ curl -fsSLO https://github.com/ComplianceAsCode/content/releases/download/v0.1.82/scap-security-guide-0.1.82.zip.sha512
admin@adm01:~/m26/e04$ sha512sum -c scap-security-guide-0.1.82.zip.sha512
scap-security-guide-0.1.82.zip: OK
admin@adm01:~/m26/e04$ scp scap-security-guide-0.1.82.zip admin@durci-deb:
admin@durci-deb:~$ sudo install -d -m 0755 /usr/local/share/scap
admin@durci-deb:~$ sudo unzip -q scap-security-guide-0.1.82.zip -d /usr/local/share/scap/
admin@durci-deb:~$ sudo mv /usr/local/share/scap/scap-security-guide-0.1.82 /usr/local/share/scap/ssg-0.1.82
admin@durci-deb:~$ oscap info --profiles /usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml
WARNING: Datastream component 'scap_org.open-scap_cref_security-oval-oval-definitions-trixie.xml.bz2' points out to the remote 'https://www.debian.org/security/oval/oval-definitions-trixie.xml.bz2'. Use '--fetch-remote-resources' option to download it.
xccdf_org.ssgproject.content_profile_anssi_bp28_enhanced:ANSSI-BP-028 (enhanced)
xccdf_org.ssgproject.content_profile_anssi_bp28_high:ANSSI-BP-028 (high)
xccdf_org.ssgproject.content_profile_anssi_bp28_intermediary:ANSSI-BP-028 (intermediary)
xccdf_org.ssgproject.content_profile_anssi_bp28_minimal:ANSSI-BP-028 (minimal)
xccdf_org.ssgproject.content_profile_cis_level1_server:CIS Debian Benchmark for Level 1 - Server
xccdf_org.ssgproject.content_profile_cis_level1_workstation:CIS Debian Benchmark for Level 1 - Workstation
xccdf_org.ssgproject.content_profile_cis_level2_server:CIS Debian Benchmark for Level 2 - Server
xccdf_org.ssgproject.content_profile_cis_level2_workstation:CIS Debian Benchmark for Level 2 - Workstation
xccdf_org.ssgproject.content_profile_standard:Standard System Security Profile for Debian 13
admin@durci-deb:~$ oscap info --profile xccdf_org.ssgproject.content_profile_cis_level1_server /usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml | grep Description
	Description: This profile defines a baseline that aligns to the "Level 1 - Server" configuration from the Center for Internet Security® Debian 13 Benchmark™, v1.0.0, released 2025-12-16. …
```

L'avertissement : le *datastream* référence le flux OVAL **des avis de sécurité de Debian** (paquets vulnérables), publié en ligne et non embarqué ; sans `--fetch-remote-resources`, la règle qui en dépend ne peut pas conclure. Décision du corrigé (écrite dans `referentiels.md`) : pas de sortie Internet pour l'analyse ; les correctifs sont suivis par E30.

Décompte des règles (ComplianceAsCode 0.1.82) : CIS niveau 1 serveur ≈ 400 règles sur Debian 13, ≈ 320 sur Rocky 10 ; ANSSI intermédiaire ≈ 230 sur chacun ; ANSSI minimal ≈ 36 sur Debian.

*C. L'évaluation.* Avec [`oscap-evaluer.sh`](fichiers/M26-E04/m26-e04/oscap-evaluer.sh) (ou à la main) :

```
admin@durci-deb:~$ sudo install -d -m 0750 /var/lib/conformite/essais
admin@durci-deb:~$ sudo oscap xccdf eval --profile cis_level1_server \
>   --results-arf /var/lib/conformite/essais/cis_level1_server-<AAAAMMJJ>.arf.xml \
>   --report /var/lib/conformite/essais/cis_level1_server-<AAAAMMJJ>.html \
>   /usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml > /dev/null; echo "code $?"
code 2
admin@adm01:~/m26/e04$ ./oscap-evaluer.sh durci-deb anssi_bp28_intermediary
admin@adm01:~/m26/e04$ ./oscap-evaluer.sh durci-rocky cis_server_l1
admin@adm01:~/m26/e04$ ./oscap-evaluer.sh durci-rocky anssi_bp28_intermediary
```

Code de retour d'`oscap xccdf eval` : **0** aucune règle en échec, **2** au moins une règle en échec (le cas normal avant durcissement), **1** erreur d'exécution. Un script qui teste « code ≠ 0 = échec » confond les deux derniers.

Règles en échec typiques sur l'image dorée, et ce qu'en ferait la correction automatique :

| Règle (Debian) | Ce qu'elle vérifie | Pourquoi elle échoue chez nous | Risque de la correction automatique |
|---|---|---|---|
| `partition_for_tmp` / `mount_option_tmp_noexec` | `/tmp` séparé, monté `nodev,nosuid,noexec` | image à partition unique | `noexec` casse les outils qui exécutent dans `/tmp` (installateurs, certains modules Ansible) : exception connue (E10) |
| `sshd_set_max_auth_tries`, `sshd_disable_*` | paramètres de `sshd_config` | valeurs par défaut d'OpenSSH | faible, mais une correction qui touche `AllowGroups` sans les groupes de l'annuaire coupe le SSO (E11) |
| `package_aide_installed`, `aide_periodic_cron_checking` | intégrité des fichiers | AIDE absent | base initiale à construire après le durcissement, sinon alertes permanentes (E12) |
| `audit_rules_*` | règles auditd | auditd absent | volume de journaux important vers Loki : à calibrer (E12) |
| `sysctl_net_ipv4_ip_forward` | routage désactivé | — | **casse `gw01`/`gw02` et les nœuds Kubernetes** : exception obligatoire |

Sur Rocky, ajoute par exemple `selinux_policytype`, `configure_crypto_policy` (politique cryptographique `DEFAULT` au lieu de celle exigée), `firewalld_loopback_traffic_restricted`.

Document : [`referentiels.md`](fichiers/M26-E04/medisphere/docs/securite/durcissement/referentiels.md).

**Explications**

- **Contenu SCAP.** Un *datastream* (SCAP 1.3) emballe le XCCDF (règles, profils, textes, liens vers les référentiels), les vérifications OVAL (tests sur paquets, fichiers, `sysctl`…), les questionnaires OCIL (contrôles manuels), le dictionnaire **CPE** (sur quels systèmes le contenu s'applique) et, pour Debian, des scripts **SCE** (vérifications en shell). Un **profil** est une sélection de règles et de valeurs (longueur minimale du mot de passe…) ; *tailoring* (E10, E24) en dérive un sans modifier le contenu.
- **Pourquoi deux origines.** Le contenu suit les distributions avec retard : Debian 13 empaquette une version sans produit Debian 13 ; l'amont 0.1.82 l'a. Rocky reconstruit le paquet de RHEL et **ajoute** un produit `rl10` dont le CPE reconnaît Rocky ; l'archive amont n'a pas de `rl10`. Épingler une version et une empreinte, c'est pouvoir dire à l'auditeur « mesuré avec ComplianceAsCode 0.1.82, contenu vérifié ».
- **Résultats.** `pass`, `fail`, `notapplicable` (la règle ne vise pas ce système), `notchecked` (pas de vérification automatique, ou ressource absente), `notselected` (hors profil), `error`, `informational`. Le **score** par défaut (`urn:xccdf:scoring:default`) est une moyenne pondérée ; il n'est comparable qu'à profil et contenu identiques.

**Alternatives**

- *`scap-workbench`* (interface graphique) : pratique pour explorer et adapter un profil, inutile en production.
- *`ansible-lockdown`* (rôles CIS de la communauté pour RHEL et Debian) et leur audit `goss` : rapides à appliquer, mais ce sont des rôles tiers dont il faut suivre les choix ; le module écrit le sien (E10) en s'appuyant sur les identifiants de règles ComplianceAsCode.
- *Remédiation générée* (`oscap xccdf generate fix --fix-type ansible`) : tentante, mais elle applique **tout** le profil sans connaître nos exceptions (routage, `/tmp`, SSO) ; utile comme source d'inspiration.
- *Construire le contenu* depuis le code source (`./build_product debian13`) : nécessaire seulement pour corriger une règle ; l'archive publiée suffit.

**Pièges classiques**

- Évaluer Rocky avec `ssg-rhel10-ds.xml` (ou Debian 13 avec le `ssg-debian12-ds.xml` du paquet) : score flatteur fait de `notapplicable`.
- Confondre `…_cis` (niveau 2 serveur sur RHEL 10) et `…_cis_server_l1`.
- Lancer `oscap xccdf eval` sans `sudo` : des centaines de règles en `error` ou `fail` faute de pouvoir lire `/etc/shadow`, `/etc/sudoers.d`…
- Laisser les rapports HTML lisibles par tous sur la VM, ou les publier : ils décrivent précisément chaque faiblesse.
- Appliquer la correction Bash du rapport sur une VM du socle « pour voir ».

**En production chez MédiSphère**

Le contenu est déployé par le rôle (`durcissement`, tâche `conformite.yml`) à version et empreinte fixes, l'analyse tourne chaque semaine avec un profil adapté qui écarte les exceptions signées, ses résultats partent dans le compartiment `conformite` et son score dans Prometheus (E24). Une nouvelle version de ComplianceAsCode est d'abord évaluée sur une VM d'essai et donne lieu à une MR qui met à jour `referentiels.md` (les règles changent, le score aussi).

---

### M26-E05 — kube-bench et kubescape : évaluer `k8s-par1`

**Solution**

1. `cfg/config.yaml` de kube-bench 0.16.0 associe `cis-1.12` aux versions **1.32, 1.33 et 1.34** ; aucune entrée pour 1.35 ou 1.36. La détection automatique lit la version du kubelet (1.36) et ne trouve pas de correspondance (selon la version, elle s'arrête en erreur ou prend un référentiel inadapté) : on force `--benchmark cis-1.12` et on documente l'écart.
2. Jobs adaptés : [`kube-bench-k8s-cp01.yaml`](fichiers/M26-E05/m26-e05/kube-bench-k8s-cp01.yaml) (cibles `master,controlplane,etcd,node,policies`) et [`kube-bench-k8s-w01.yaml`](fichiers/M26-E05/m26-e05/kube-bench-k8s-w01.yaml) (cible `node`). Changements par rapport aux manifestes amont : espace `wb-diagnostic`, `nodeName`, image `registry.par1.medisphere.internal/dockerhub/aquasec/kube-bench:v0.16.0`, `--benchmark cis-1.12 --json`, `ttlSecondsAfterFinished: 3600`, `backoffLimit: 0`, pas de jeton de compte de service, `hostPath` typés (`Directory`, `File`) et montages inutiles retirés (`/srv/kubernetes`, `/var/lib/kube-scheduler`, `/var/lib/kube-controller-manager` n'existent pas sur un nœud kubeadm : avec un `hostPath` non typé, le runtime les créerait vides sur l'hôte ; avec `type: Directory`, le pod refuserait de démarrer, ce qui est plus honnête).
3. Exécution :
   ```
   admin@adm01:~/m26/e05$ kubectl apply -f kube-bench-k8s-cp01.yaml -f kube-bench-k8s-w01.yaml
   admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic wait --for=condition=complete job/kube-bench-k8s-cp01 job/kube-bench-k8s-w01 --timeout=5m
   admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic logs job/kube-bench-k8s-cp01 | jq . > kube-bench-k8s-cp01.json
   admin@adm01:~/m26/e05$ kubectl -n wb-diagnostic logs job/kube-bench-k8s-w01 | jq . > kube-bench-k8s-w01.json
   admin@adm01:~/m26/e05$ jq '.Totals' kube-bench-k8s-cp01.json
   { "total_pass": …, "total_fail": …, "total_warn": …, "total_info": … }
   admin@adm01:~/m26/e05$ jq -r '.Controls[] | .node_type as $t | .tests[].results[] | select(.status == "FAIL") | "\($t)\t\(.test_number)\t\(.test_desc)"' kube-bench-k8s-cp01.json
   ```
   (`jq .` sert aussi de contrôle : si un message s'est glissé avant le JSON dans le journal, il échoue ; nettoie alors la sortie.)
4. Vérifications sur le nœud, par exemple :
   ```
   admin@adm01:~$ ssh k8s-cp01 'sudo -n stat -c "%U:%G %a" /var/lib/etcd; ps -o args= -C kube-apiserver | tr " " "\n" | grep -E "^--(profiling|kubelet-certificate-authority|audit-log)"'
   root:root 700
   --audit-log-path=…
   --audit-log-maxage=…
   admin@adm01:~$ ssh k8s-w01 'sudo -n grep -E "^(readOnlyPort|seccompDefault|serverTLSBootstrap|rotateCertificates)" /var/lib/kubelet/config.yaml; ls -l /lib/systemd/system/kubelet.service /usr/lib/systemd/system/kubelet.service.d/'
   rotateCertificates: true
   ```
   Classement complet dans [`mesure-k8s-par1.md`](fichiers/M26-E05/medisphere/docs/securite/durcissement/mesure-k8s-par1.md) : `1.1.12` (etcd en root : choix de kubeadm), `1.2.15`/`1.3.2`/`1.4.1` (profilage : vrais écarts), `1.2.5` et `4.2.11` (certificats de service des kubelets : vrais écarts, E25), `4.1.1` (fichier d'unité du paquet en 644 : écart mineur ; drop-in à un chemin inconnu de kube-bench), `4.2.14` (`seccompDefault` : E25)…
5. kubescape :
   ```
   admin@adm01:~/m26/e05$ kubescape scan framework nsa,mitre,cis-v1.12.0 --keep-local --format json --output kubescape.json
   admin@adm01:~/m26/e05$ jq -r '.summaryDetails.frameworks[] | "\(.name)\t\(.complianceScore)"' kubescape.json
   admin@adm01:~/m26/e05$ ./kubescape-resume.sh kubescape.json > kubescape-resume.json
   ```
   [`kubescape-resume.sh`](fichiers/M26-E05/m26-e05/kubescape-resume.sh) ne garde que les cadres, leurs scores et, par contrôle en échec, son identifiant, son nom, sa gravité et le **nombre** de ressources fautives.
6. Copie de `kube-bench-k8s-cp01.json`, `kube-bench-k8s-w01.json` et `kubescape-resume.json` dans `docs/securite/durcissement/mesures/k8s-par1/`, et `mesure-k8s-par1.md` ; MR.

**Explications**

- **Pourquoi un Job sur le nœud.** kube-bench lit des **fichiers** (manifestes des pods statiques, configuration du kubelet, droits et propriétaires) et la **ligne de commande des processus** (`ps`, d'où `hostPID`) : il doit tourner sur le nœud mesuré, avec ses dossiers montés. C'est aussi pourquoi il demande l'espace `privileged` : `wb-diagnostic` (M14-E20) est fait pour cela et vide le reste du temps.
- **Référentiel et version.** Un CIS Benchmark décrit des réglages d'une version ; les options changent peu d'une mineure à l'autre, mais certaines disparaissent ou changent de défaut. Forcer `cis-1.12` sur 1.36 est défendable **si c'est écrit** et que chaque FAIL est lu.
- **Faux positifs de kubeadm.** Le référentiel suppose souvent des binaires lancés par systemd avec des drapeaux ; kubeadm lance le plan de contrôle en **pods statiques** et règle le kubelet par **fichier** (`/var/lib/kubelet/config.yaml`). Les contrôles bien écrits lisent les deux ; d'autres ne voient que les drapeaux, ou des chemins d'une autre distribution.
- **kubescape** évalue des **objets de l'API** (en Rego) contre des cadres plus larges (NSA/CISA, MITRE ATT&CK) : il voit les charges, le RBAC, les politiques réseau, mais sans son opérateur (node-agent, kubescape 4), pas les fichiers des nœuds. Les deux outils sont complémentaires.

**Alternatives**

- kube-bench **en local** sur le nœud (binaire de l'archive, comme au M18-E15) : évite l'espace privilégié, mais suppose de copier un binaire sur chaque nœud et ne s'industrialise pas aussi bien qu'un CronJob.
- **Opérateur kubescape** (chart 1.40) : analyse continue, résultats en CRD, détection à l'exécution ; ≈ 1 Go de mémoire de plus : écarté pour l'instant (budget), réexaminé au F6.
- **Trivy** (`trivy k8s --compliance k8s-cis-1.23`) ou **Trivy Operator** : rapports de conformité et de vulnérabilités ; cité (E30).
- *`compliance-operator`* (OpenShift, ou de Rancher pour RKE2) : spécifique à ces distributions.

**Pièges classiques**

- Laisser `latest` dans l'image du Job (le résultat d'aujourd'hui ne sera pas reproductible demain).
- Oublier `--benchmark` et croire au rapport d'un référentiel choisi au hasard.
- Recopier le journal du pod sans vérifier que c'est du JSON valide.
- Compter les FAIL sans les lire : « 23 FAIL » ne dit rien ; « 6 vrais écarts, dont 2 traités en E25 » dit tout.
- Lancer kubescape avec un compte qui ne voit pas tout (le compte des checks, par exemple) : contrôles « ignorés » qui ressemblent à des réussites.
- Laisser le Job et ses pods : un pod `hostPID` qui traîne dans `wb-diagnostic` est exactement ce que la détection d'E08 doit signaler.

**En production chez MédiSphère**

kube-bench devient un CronJob hebdomadaire (un Job par nœud, dans un espace dédié et privilégié, résultat poussé vers `conformite` et transformé en métrique), et kubescape une analyse en CI des manifestes avant fusion (`kubescape scan framework nsa <dossier>`) plus une analyse hebdomadaire du cluster. Chaque FAIL accepté devient une exception écrite (E23). La veille du CIS Kubernetes Benchmark pour 1.36 est une tâche du calendrier de conformité (E43).

---

### M26-E06 — Pod Security Admission : auditer puis imposer `restricted`

**Solution**

1. Outil : [`outils/psa-inventaire.sh`](fichiers/M26-E06/k8s/outils/psa-inventaire.sh) (lecture des espaces et des pods, puis simulation par `kubectl label --dry-run=server`).
2. Inventaire et essai :
   ```
   admin@adm01:~/src/k8s$ outils/psa-inventaire.sh
   ESPACE                     ENFORCE     VERSION  AUDIT       WARN        PODS  EXCEPTION
   argocd                     restricted  v1.36    restricted  restricted  7
   ceph-csi                   privileged  -        baseline    baseline    9
   journaux                   privileged  -        absent      absent      7
   mediagenda-recette         restricted  v1.35    restricted  restricted  6
   supervision-noeuds         privileged  -        restricted  restricted  6     node-exporter : hostNetwork…
   wb-diagnostic              privileged  -        baseline    baseline    0
   wb-essais                  baseline    v1.35    restricted  restricted  2
   …
   admin@adm01:~/src/k8s$ outils/psa-inventaire.sh --essai restricted
   -- ceph-csi : NON CONFORME
        Warning: existing pods in namespace "ceph-csi" violate the new PodSecurity enforce level "restricted:v1.36"
        Warning: csi-rbdplugin-xxxxx: host namespaces, privileged, hostPath volumes, …
   -- mediagenda-recette : conforme
   -- wb-essais : NON CONFORME
        Warning: … runAsNonRoot != true, seccompProfile …
   ```
   Classement typique : **(a)** les espaces des équipes et la plupart des espaces de plateforme (version à aligner sur v1.36) ; **(b)** un espace dont une charge oublie `seccompProfile` ou un conteneur d'initialisation (à corriger dans ses values) ; **(c)** `ceph-csi`, `velero`, `journaux`, `supervision-noeuds`, `buildkit`, `wb-diagnostic` (et bientôt `falco`) ; **(d)** les espaces créés par un chart ou un outil sans étiquettes (et `default`).
3. Correction d'une charge (b), exemple d'un conteneur d'initialisation de chart : dans les values, `initContainers[].securityContext` avec `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault` (ou, s'il fait un `chown`, le remplacer par `fsGroup` au niveau du pod) ; MR dans le dépôt de la charge, synchronisation, nouvel essai sans avertissement.
4. Journal d'audit, dans Grafana (organisation « Sécurité », source « Loki — audit ») :
   ```
   {job="kubernetes-audit"} |= "pod-security.kubernetes.io/audit-violations" | json
     | line_format "{{.objectRef_namespace}} {{.objectRef_name}} {{.annotations_pod_security_kubernetes_io_audit_violations}}"
   ```
   (adapte le sélecteur d'étiquettes à celui de ton M22 ; les noms de champs aplatis par le filtre `json` dépendent du format de l'événement). L'annotation est posée par l'API à **chaque** création de pod qui viole le profil `audit` de son espace, même quand `enforce` l'accepte : c'est la mesure de ce qui casserait.
5. Fichiers d'espaces : [`wb-essais.yaml`](fichiers/M26-E06/k8s/espaces/wb-essais.yaml) (exception `baseline` écrite), [`wb-diagnostic.yaml`](fichiers/M26-E06/k8s/espaces/wb-diagnostic.yaml) (exception `privileged`, `audit` et `warn` passés en `restricted`), [`default.yaml`](fichiers/M26-E06/k8s/espaces/default.yaml) (verrouillé), [`mediagenda-recette/00-namespace.extrait.yaml`](fichiers/M26-E06/k8s/espaces/mediagenda-recette/00-namespace.extrait.yaml) (passage en v1.36, même chose pour les quatre autres espaces d'équipes) ; pour `journaux`, `ceph-csi`, `velero`, `buildkit` : `audit` et `warn` en `restricted` et l'annotation `medisphere.internal/exception-psa` sur le modèle de `supervision-noeuds` (M21). Par lots :
   ```
   admin@adm01:~/src/k8s$ outils/psa-inventaire.sh --essai restricted --espace mediagenda-recette
   -- mediagenda-recette : conforme
   admin@adm01:~/src/k8s$ task diff && task appliquer
   admin@adm01:~$ kubectl -n supervision rollout restart deployment/kps-kube-state-metrics && kubectl -n supervision rollout status deployment/kps-kube-state-metrics
   ```
6. Registre : [`pod-security.md`](fichiers/M26-E06/medisphere/docs/securite/durcissement/pod-security.md).

**Explications**

- **Trois modes, trois usages.** `enforce` refuse les **pods** (les contrôleurs ne sont qu'avertis) ; `warn` renvoie un avertissement au client qui crée l'objet (pods **et** contrôleurs) ; `audit` ajoute une annotation à l'événement d'audit. `warn` et `audit` en `restricted` sur un espace d'exception rendent l'exception **visible** : tout nouvel objet non conforme y laisse une trace.
- **Version figée.** Le contenu d'un profil peut se durcir d'une version à l'autre (de nouvelles règles apparaissent) ; `enforce-version: v1.36` garantit qu'une montée du cluster ne change pas la règle sans MR, `warn-version: latest` montre d'avance ce qui casserait. On aligne sur la version du cluster après un essai.
- **Pourquoi l'essai `--dry-run=server`.** La requête de modification de l'espace traverse l'admission ; le contrôleur PodSecurity évalue alors les pods existants contre le nouveau niveau et renvoie la liste des violations. C'est la seule façon fiable de savoir ce qui serait refusé demain. Il faut le droit `patch` sur `namespaces` : ton compte, pas celui des checks.
- **Espace d'exception dédié.** Pod Security est grossier (un espace entier) : mettre un DaemonSet privilégié dans l'espace de son application (Grafana, Loki) affaiblit toute l'application. D'où les espaces `supervision-noeuds`, `falco`, et la recommandation pour `journaux`.

**Alternatives**

- *Profil par défaut dans le kube-apiserver* (`AdmissionConfiguration`, plugin `PodSecurity`, `defaults` et `exemptions`) : tout espace sans étiquette reçoit `restricted` d'office ; exemptions par utilisateur, *RuntimeClass* ou espace. Plus sûr (un espace oublié est protégé), mais un fichier de plus sur chaque nœud de contrôle, appliqué un nœud à la fois (rôle `k8s_plan_controle`). Bon candidat pour E46.
- *Kyverno à la place de PSA* : règles par pod, exceptions fines (`PolicyException`), rapports ; mais un webhook (donc une disponibilité) pour une protection que l'API fait seule. On garde les deux : PSA comme plancher sans dépendance, Kyverno pour le détail.
- *`kubectl label` direct* : rapide, mais hors du code ; le prochain `task appliquer` l'écrase, ou pire, ne l'écrase pas et personne ne sait d'où vient la valeur.

**Pièges classiques**

- Poser `enforce` sans essai : rien ne casse… jusqu'au prochain redémarrage de nœud, où les pods recréés sont refusés en série.
- Corriger en abaissant l'espace à `baseline` « le temps de régler » : l'exception devient permanente.
- Oublier les **conteneurs d'initialisation** et éphémères : `restricted` les évalue aussi.
- `enforce-version: latest` sur un espace d'équipe : la montée de Kubernetes change la règle sans prévenir.
- Lire les avertissements de `kubectl apply` d'un Deployment et croire que les pods passeront : l'avertissement **est** le refus de demain.

**En production chez MédiSphère**

Profil `restricted` par défaut au niveau du kube-apiserver avec exemptions explicites, revue trimestrielle du registre (`psa-inventaire.sh` en CI planifiée qui échoue si un espace sort du registre), alerte Loki sur l'annotation `audit-violations` dans les espaces d'équipes, et création des espaces par un modèle (E16 : la `GeneratingPolicy` posera aussi la NetworkPolicy par défaut).

---

### M26-E07 — Kyverno : installation et premières politiques CEL

**Solution**

*A. Le contrôleur.* Fichiers : [`charts.extrait.yaml`](fichiers/M26-E07/charts-miroir/charts.extrait.yaml), [`espaces/kyverno.yaml`](fichiers/M26-E07/k8s/espaces/kyverno.yaml), [`valeurs/kyverno/values.yaml`](fichiers/M26-E07/gitops/valeurs/kyverno/values.yaml), [`plateforme/kyverno.yaml`](fichiers/M26-E07/gitops/plateforme/kyverno.yaml), [`projets/plateforme.extrait-E07.yaml`](fichiers/M26-E07/gitops/projets/plateforme.extrait-E07.yaml).

```
admin@adm01:~/m26/e07$ helm show values oci://registry.par1.medisphere.internal/charts/kyverno --version 3.9.2 > defauts.yaml
admin@adm01:~/m26/e07$ helm template kyverno oci://registry.par1.medisphere.internal/charts/kyverno --version 3.9.2 -n kyverno \
>   -f ~/src/gitops/valeurs/kyverno/values.yaml --api-versions monitoring.coreos.com/v1 > rendu.yaml
admin@adm01:~/m26/e07$ yq -r 'select(.kind == "CustomResourceDefinition" and .spec.group == "policies.kyverno.io")
>   | .metadata.name + " " + ([.spec.versions[] | .name + (if .storage then "*" else "" end)] | join(","))' rendu.yaml
validatingpolicies.policies.kyverno.io v1,v1alpha1,v1beta1*
imagevalidatingpolicies.policies.kyverno.io v1,v1alpha1,v1beta1*
…
admin@adm01:~/m26/e07$ grep -hoE 'image: "?[^" ]+' rendu.yaml | sort -u
image: "registry.par1.medisphere.internal/ghcr/kyverno/background-controller:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/cleanup-controller:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/kyverno-cli:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/kyverno:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/kyvernopre:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/readiness-checker:v1.19.2
image: "registry.par1.medisphere.internal/ghcr/kyverno/reports-controller:v1.19.2
```

Sans `test.image` et `webhooksCleanup.image`, deux *hooks* resteraient sur `ghcr.io/kyverno/readiness-checker` en `latest` (pods de test) et `v1.19.2` (Jobs `kyverno-scale-to-zero` et `kyverno-rm-webhooks`, exécutés à la **suppression** de la release). Les CRD servent `v1` et stockent `v1beta1` : on écrit en `v1`, l'API convertit.

Après fusion :

```
admin@adm01:~$ kubectl -n kyverno get deploy
NAME                            READY   UP-TO-DATE   AVAILABLE
kyverno-admission-controller    3/3     3            3
kyverno-background-controller   2/2     2            2
kyverno-cleanup-controller      1/1     1            1
kyverno-reports-controller      1/1     1            1
admin@adm01:~$ kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o wide   # trois nœuds différents
admin@adm01:~$ kubectl get validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno
kyverno-cleanup-validating-webhook-cfg, kyverno-exception-validating-webhook-cfg, kyverno-policy-validating-webhook-cfg,
kyverno-resource-validating-webhook-cfg, …
admin@adm01:~$ kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg \
>   -o jsonpath='{range .webhooks[*]}{.name}{" "}{.failurePolicy}{" "}{.namespaceSelector}{"\n"}{end}'
```

Les configurations de webhooks ne sont **pas** dans le chart : Kyverno les écrit lui-même au démarrage et à chaque changement de politique, en fusionnant le `namespaceSelector` de chaque politique avec `config.webhooks` (donc l'exclusion de `kube-system`, `argocd`, `cilium` et `kyverno` s'applique à toutes). Une politique en `failurePolicy: Ignore` est servie par un webhook `…-ignore`, une politique en `Fail` par un webhook `…-fail`.

*B. Les politiques.* Projet `plateforme/politiques` : [`README.md`](fichiers/M26-E07/politiques/README.md), [`kustomization.yaml`](fichiers/M26-E07/politiques/kustomization.yaml), [`.gitlab-ci.yml`](fichiers/M26-E07/politiques/.gitlab-ci.yml), [`registres-autorises.yaml`](fichiers/M26-E07/politiques/kyverno/validation/registres-autorises.yaml), [`exiger-etiquettes.yaml`](fichiers/M26-E07/politiques/kyverno/validation/exiger-etiquettes.yaml), tests dans [`kyverno/tests/`](fichiers/M26-E07/politiques/kyverno/tests/) ; Application [`plateforme/politiques.yaml`](fichiers/M26-E07/gitops/plateforme/politiques.yaml).

```
admin@adm01:~/src/politiques$ kyverno test kyverno/tests/
…
│ 3  │ registres-autorises │      │ apps/v1/Deployment/mediagenda-recette/init-hors-registre │ Pass   │ Excluded │
│ 4  │ registres-autorises │      │ apps/v1/Deployment/mediagenda-recette/init-hors-registre │ Pass   │ Ok       │
│ 5  │ registres-autorises │      │ v1/Pod/wb-essais/hors-espace-equipe                      │ Pass   │ Excluded │
Test Summary: 9 tests passed and 0 tests failed
admin@adm01:~/src/politiques$ kyverno apply kyverno/validation/ -r kyverno/tests/exiger-etiquettes/ressources.yaml \
>   -f kyverno/tests/exiger-etiquettes/valeurs.yaml
policy exiger-etiquettes -> resource mediagenda-recette/StatefulSet/autre-equipe failed:
1 -  StatefulSet autre-equipe : medisphere.internal/equipe=medidoc ne correspond pas à l’équipe de l’espace (mediagenda)
…
pass: 5, fail: 3, warn: 0, error: 0, skip: 0
```

Le Deployment `init-hors-registre` apparaît deux fois : une ligne « Excluded » (la règle du **pod** ne vise pas un Deployment), une ligne « Ok » (la règle **générée** pour les contrôleurs le refuse, comme attendu).

Le job de CI ne peut pas utiliser l'image `ghcr.io/kyverno/kyverno-cli` : elle n'a **pas de shell**, et le runner Kubernetes exécute le script par un shell dans l'image. Il prend donc une petite image (`curlimages/curl` du cache) et y dépose la CLI de la publication, vérifiée par son empreinte (`checksums.txt` de la v1.19.2) ; les jobs de `ci-jobs` ont droit à Internet en 443 (M19-E24).

*C. Les rapports.*

```
admin@adm01:~$ kubectl -n mediagenda-dev create deployment essai-kyverno --dry-run=server -o name \
>   --image=registry.par1.medisphere.internal/dockerhub/library/nginx:1.29
Warning: … exiger-etiquettes … Deployment essai-kyverno : étiquette medisphere.internal/equipe absente
deployment.apps/essai-kyverno
admin@adm01:~$ kubectl -n mediagenda-dev create deployment essai-kyverno --dry-run=server -o name \
>   --image=docker.io/library/nginx:1.29
error: failed to create deployment: deployments.apps "essai-kyverno" is forbidden: ValidatingAdmissionPolicy 'medisphere-images'
with binding 'medisphere-images' denied request: image(s) hors du registre MédiSphère : docker.io/library/nginx:1.29 …
```

Le premier essai passe la VAP (image de Harbor) et Kyverno avertit pour l'étiquette (`Warn`). Le second est refusé par la VAP **avant** que Kyverno soit appelé : dans le kube-apiserver, le greffon `ValidatingAdmissionPolicy` passe avant `ValidatingAdmissionWebhook`, et la chaîne s'arrête au premier refus. D'où l'absence de l'avertissement de `registres-autorises` : les deux règles se recouvrent dans les espaces d'équipes, la VAP refuse, Kyverno documente l'existant.

```
admin@adm01:~$ kubectl get validatingpolicies
NAME                  AGE   READY
exiger-etiquettes     5m    true
registres-autorises   5m    true
admin@adm01:~$ kubectl get policyreports -A
NAMESPACE           NAME                                   KIND          NAME                   PASS   FAIL   WARN   ERROR   SKIP
mediagenda-recette  0b8c…                                  StatefulSet   mediagenda-db-…        0      1      0      0       0
…
admin@adm01:~$ kubectl get policyreports -A -o json | jq -r '.items[] | .metadata.namespace as $n | .scope.kind as $k | .scope.name as $o
>   | .results[]? | select(.result == "fail") | "\($n)\t\($k)/\($o)\t\(.policy)\t\(.message)"'
```

Écarts typiques : des StatefulSet et CronJob de dépendances (Valkey, sauvegardes, `mediagenda-db` si un opérateur crée ses objets) sans l'étiquette d'équipe (vrais oublis de chart ou objets créés par un opérateur : à corriger ou à exclure explicitement) ; aucun écart de registre (la VAP du M14 refusait déjà). RBAC des checks : [`wb-checks-securite.extrait-E07.yaml`](fichiers/M26-E07/k8s/rbac/wb-checks-securite.extrait-E07.yaml).

**Explications**

- **Un webhook, des conséquences.** Kyverno reçoit chaque requête d'écriture des espaces qu'il couvre ; s'il ne répond pas (pods arrêtés, réseau, surcharge), l'API applique la `failurePolicy` de la politique : `Ignore` laisse tout passer (bon pour l'audit), `Fail` refuse tout ce que la politique couvre (indispensable pour une règle de sécurité stricte comme la signature, E15, mais alors trois réplicas et un budget de perturbation sont une condition de disponibilité du cluster). Exclure `kube-system` et `argocd` garantit que le cluster et l'outil qui répare les politiques ne dépendent jamais de Kyverno.
- **CEL plutôt que les anciennes politiques.** Les `ValidatingPolicy` reprennent le modèle des ValidatingAdmissionPolicy de Kubernetes (`matchConstraints`, `variables`, `validations`, `validationActions`) en y ajoutant ce que l'API seule ne sait pas faire : l'**analyse en arrière-plan** de l'existant et ses rapports, l'*autogen* pour les contrôleurs, des bibliothèques (appels à l'API, aux registres d'images), les exceptions. Kyverno peut même générer une VAP native à partir d'une `ValidatingPolicy` simple (`autogen.validatingAdmissionPolicy`).
- **Rapports.** Le contrôleur d'arrière-plan évalue régulièrement les objets existants et le contrôleur de rapports agrège les résultats en `PolicyReport` (un par objet évalué, dans son espace) et `ClusterPolicyReport` (objets sans espace) : c'est la liste de travail avant de passer en refus.

**Alternatives**

- *OPA Gatekeeper* (3.23) : politiques en Rego, *ConstraintTemplates*, audit ; très puissant, mais un langage de plus et pas de mutation/génération aussi intégrées. Comparé en E17.
- *VAP natives seules* : aucune dépendance, mais ni rapports de l'existant, ni vérification de signature, ni génération.
- *Kyverno en `ClusterPolicy`* (YAML, motifs) : ce que montrent la plupart des tutoriels ; déprécié en 1.19, supprimé en 1.20 : à proscrire pour un dispositif durable.
- *Installer par Helmfile dans la couche de base* : défendable pour un composant dont dépend l'admission ; le lab garde Argo CD pour les services de plateforme (M20), en excluant `argocd` des webhooks pour ne jamais se bloquer soi-même.

**Pièges classiques**

- Une politique en `Deny` avec `failurePolicy: Fail` dès le premier jour (E35 en est la panne).
- Mettre les ressources de test dans le dossier que l'Application applique : Argo CD crée des pods non conformes exprès dans les espaces d'équipes.
- Oublier `ServerSideApply` : les CRD de Kyverno dépassent la taille de l'annotation `last-applied-configuration`.
- Doubler l'apostrophe dans un message CEL (`'l''équipe'`) : erreur de compilation de la politique.
- Lire `kubectl get policyreports` comme une liste de violations : chaque rapport compte aussi les `pass`.
- Croire qu'une politique `Audit` protège : elle ne refuse rien.

**En production chez MédiSphère**

Kyverno a ses alertes (latence et erreurs des webhooks, `kyverno_admission_review_duration_seconds`, contrôleur d'admission indisponible : E18), un tableau de bord des violations par équipe, une revue hebdomadaire des rapports par l'équipe Plateforme, et un calendrier de passage en refus validé avec les équipes (Julien a sa semaine de prévenance). Les montées de version suivent les notes de version **avant** la 1.20 : vérifier qu'aucune `ClusterPolicy` ne reste (`kyverno migrate` pour les objets stockés).

---

### M26-E08 — Falco : installation et premières détections

**Solution**

*A. Le capteur.* Fichiers : [`charts.extrait.yaml`](fichiers/M26-E08/charts-miroir/charts.extrait.yaml), [`espaces/falco.yaml`](fichiers/M26-E08/k8s/espaces/falco.yaml), [`valeurs/falco/values.yaml`](fichiers/M26-E08/gitops/valeurs/falco/values.yaml), [`plateforme/falco.yaml`](fichiers/M26-E08/gitops/plateforme/falco.yaml), [`projets/plateforme.extrait-E08.yaml`](fichiers/M26-E08/gitops/projets/plateforme.extrait-E08.yaml) ; flux : [`politique-reseau.extrait.yaml`](fichiers/M26-E08/observabilite/loki/manifestes/politique-reseau.extrait.yaml) (Loki), [`values.extrait.yaml`](fichiers/M26-E08/observabilite/kps/values.extrait.yaml) (Alertmanager), [`matrice-flux-cluster.extrait.md`](fichiers/M26-E08/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait.md). Ajoute la ligne `falco` au registre `pod-security.md`.

```
admin@adm01:~/m26/e08$ helm template falco oci://registry.par1.medisphere.internal/charts/falco --version 9.2.1 -n falco \
>   -f ~/src/gitops/valeurs/falco/values.yaml --api-versions monitoring.coreos.com/v1 > rendu.yaml
admin@adm01:~/m26/e08$ yq -r 'select(.kind) | .kind + " " + .metadata.name' rendu.yaml
ServiceAccount falco-falcosidekick
ServiceAccount falco
Secret falco-falcosidekick
ConfigMap falco
Role falco-falcosidekick
RoleBinding falco-falcosidekick
Service falco-falcosidekick
DaemonSet falco
Deployment falco-falcosidekick
ServiceMonitor falco-falcosidekick
Pod falco-falcosidekick-test-connection          # hook « test-success » : ignoré par Argo CD
admin@adm01:~/m26/e08$ yq -r 'select(.kind == "ConfigMap" and .metadata.name == "falco") | .data["falco.yaml"]' rendu.yaml \
>   | yq -c '.engine.kind, .rules_files, .load_plugins, .http_output.url'
"modern_ebpf"
["/etc/falco/falco_rules.yaml","/etc/falco/falco_rules.local.yaml","/etc/falco/rules.d"]
["container"]
"http://falco-falcosidekick:2801"
admin@adm01:~/m26/e08$ yq -c 'select(.kind == "DaemonSet") | .spec.template.spec | {tol: .tolerations, sc: .containers[0].securityContext}' rendu.yaml
{"tol":[{"effect":"NoSchedule","key":"node-role.kubernetes.io/master"},{"effect":"NoSchedule","key":"node-role.kubernetes.io/control-plane"}],"sc":{"privileged":true}}
```

Après fusion et synchronisation :

```
admin@adm01:~$ kubectl -n falco get ds falco
NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
falco   6         6         6       6            6
admin@adm01:~$ kubectl -n falco logs ds/falco | head -n 20
… Falco version: 0.45.1 …
… Loading plugin 'container' from file /usr/share/falco/plugins/libcontainer.so
… Loading rules from: /etc/falco/falco_rules.yaml …
… Opening 'syscall' source with modern BPF probe.
admin@adm01:~$ kubectl top pods -n falco
```

*B. Les détections.* Les deux règles :
- « Terminal shell in container » : `spawned_process and container and shell_procs and proc.tty != 0 and container_entrypoint`, priorité **NOTICE** ; un shell **avec terminal** lancé comme point d'entrée dans un conteneur (cas de `kubectl exec -it … -- bash`) ;
- « Read sensitive file untrusted » : `open_read and sensitive_files and proc_name_exists and not proc.name in (…, shell_binaries, …)`, priorité **WARNING** ; `open_read` n'est vrai que pour une ouverture **réussie** en lecture ; les shells, gestionnaires de paquets et outils de gestion des comptes sont exclus, `cat` ne l'est pas.

```
admin@adm01:~$ kubectl -n wb-essais run falco-essai --image=registry.par1.medisphere.internal/dockerhub/library/debian:13-slim --restart=Never -- sleep 3600
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false, …   # warn de wb-essais : attendu
admin@adm01:~$ kubectl -n wb-essais exec -it falco-essai -- bash
root@falco-essai:/# cat /etc/shadow > /dev/null; exit
admin@adm01:~$ noeud=$(kubectl -n wb-essais get pod falco-essai -o jsonpath='{.spec.nodeName}')
admin@adm01:~$ capteur=$(kubectl -n falco get pods -l app.kubernetes.io/name=falco --field-selector spec.nodeName=$noeud -o name)
admin@adm01:~$ kubectl -n falco logs "$capteur" --tail=50 | grep -E 'Terminal shell|Read sensitive'
{"hostname":"k8s-w02","output":"… Notice A shell was spawned in a container with an attached terminal | … k8s_pod_name=falco-essai …","priority":"Notice","rule":"Terminal shell in container",…}
{"hostname":"k8s-w02","output":"… Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow … process=cat …","priority":"Warning","rule":"Read sensitive file untrusted",…}
```

(Le capteur qui voit l'événement est celui du **nœud** du pod : chaque pod `falco` n'observe que son noyau. Le texte exact des sorties dépend de la version des règles.)

Dans Grafana, organisation « Sécurité », Explore, source « Loki — audit » : `{service="falco"}` puis `{service="falco", rule="Read sensitive file untrusted"} | json`. Les étiquettes du flux : `rule`, `priority`, `source`, `k8s_ns_name`, `k8s_pod_name`, `hostname`, `tags`, `service`, `cluster`. Dans Alertmanager (`amtool alert query source=falco` ou l'interface) : **seule** la lecture de `/etc/shadow` (WARNING) arrive, le shell (NOTICE) est sous le seuil `minimumpriority: warning` ; l'alerte porte `source="falco"`, `rule`, `priority`, `severity` (calculée par falcosidekick), et nos `equipe` et `gravite`.

Sans `-it` (`kubectl exec falco-essai -- cat /etc/shadow`) : pas de terminal, donc pas de « Terminal shell in container » ; la lecture déclenche toujours « Read sensitive file untrusted ». (Selon ta version des règles, d'autres règles de priorité inférieure peuvent apparaître si tu as baissé `priority`.)

```
admin@adm01:~$ kubectl -n wb-essais delete pod falco-essai
```

Notes attendues : 200 à 300 Mo et quelques millicœurs par pod `falco` au repos ; le nombre d'événements par heure (`sum(count_over_time({service="falco"}[1h]))`) au repos doit être **faible** sur un travailleur (sinon une règle bruyante est à régler en E19) ; ce qui manque pour réveiller la bonne personne : routage d'Alertmanager par `source="falco"`, gravité selon la priorité et l'espace, runbook RB-260, règles propres à MédiSphère (E19).

**Explications**

- **eBPF et `modern_ebpf`.** Falco attache des programmes eBPF aux points de traçage des appels système du noyau ; la sonde « moderne » est compilée dans le binaire et s'adapte au noyau grâce à BTF (CO-RE) : pas de module noyau, pas de compilation sur le nœud, pas de téléchargement. Elle remplit un tampon circulaire que Falco lit en espace utilisateur, enrichit (greffon `container` pour le conteneur et le pod) et confronte aux règles. Un tampon plein = des événements perdus (Falco le signale, falcosidekick aussi par `dropeventdefaultpriority`).
- **Pourquoi `privileged`.** Charger des programmes eBPF, lire `/proc` de tous les processus, ouvrir les sockets des runtimes demandent des capacités que seul `privileged` (ou une liste de capacités, `leastPrivileged`) donne. C'est le prix d'un capteur : il est lui-même une cible, d'où un espace dédié où personne n'écrit hors Argo CD.
- **falcoctl désactivé.** Par défaut, le chart télécharge les règles et le greffon depuis Internet au démarrage, puis **suit** les nouvelles versions chaque semaine : des règles qui changent en production sans revue, et une dépendance réseau au démarrage. L'image 0.45.1 contient déjà `falco_rules.yaml` et `libcontainer.so` ; les règles évoluent avec l'image, par MR.
- **falcosidekick** reçoit les événements (`http_output` de Falco, en JSON) et les distribue vers des dizaines de sorties avec un seuil de priorité par sortie. Ses `customfields` s'ajoutent à chaque événement : ils deviennent des étiquettes dans Loki et dans Alertmanager, d'où `service="falco"` dans le locataire `audit`.

**Alternatives**

- *Sortie directe de Falco vers Loki* (pas de sortie Loki native dans Falco ; il faudrait collecter le journal du pod par Alloy et le parser) : moins de pièces, mais pas de seuil par destination ni de métriques de livraison. Alloy reste un bon second chemin (le journal de Falco est déjà collecté par le DaemonSet du M22).
- *Pilote `kmod`* : module noyau, pour les noyaux sans BTF ; à éviter quand l'eBPF moderne est possible.
- *Tetragon* (E20) : observation et **application** au niveau du noyau, politiques par CRD ; Falco reste plus riche en règles prêtes à l'emploi.
- *Source `k8saudit`* de Falco (greffon qui lit le journal d'audit de l'API) : promise au M14 comme piste ; le lab traite l'audit de l'API par les règles du *ruler* de Loki (E28), ce qui évite un webhook d'audit de plus sur les nœuds de contrôle.

**Pièges classiques**

- Laisser le chemin `/api/v1/alerts` par défaut : Alertmanager ≥ 0.27 répond 404, falcosidekick compte des erreurs, aucune alerte n'arrive.
- Oublier les flux : les politiques `loki-entree` et `alertmanager-entree` refusent falcosidekick tant qu'on ne l'ajoute pas ; symptôme : `falcosecurity_falcosidekick_outputs_total{status="error"}` qui monte.
- Tester la lecture de `/etc/shadow` depuis un pod non-root : l'ouverture échoue, aucune alerte (et on croit Falco aveugle).
- Tester le shell avec `kubectl exec` **sans** `-it` : pas de terminal, pas d'alerte « Terminal shell ».
- Garder les 512 Mo réservés par défaut sur six nœuds : 3 Go bloqués pour l'ordonnanceur sur un cluster serré.
- Abaisser `priority` à `debug` « pour voir » : volume énorme dans Loki, et l'astreinte apprend à ignorer.

**Ce qui reste promis**

La source `k8saudit` évoquée au M14 n'est pas installée (choix expliqué ci-dessus : E28 traite l'audit de l'API par Loki) ; les règles propres à MédiSphère, le routage fin et le runbook sont l'objet d'E19.

**En production chez MédiSphère**

Falco a ses propres alertes (pod absent sur un nœud, événements perdus, falcosidekick en erreur), ses règles sont versionnées et testées en CI (E19), chaque alerte a un propriétaire et un runbook (RB-260), et la volumétrie dans Loki est suivie (budget du locataire `audit`, rétention d'un an). La montée de version de Falco passe par une MR qui relit les changements des règles par défaut.

---

### M26-E09 — Questions : référentiels, contrôles et défense en profondeur

**Barème** : 2 points par question, total sur 22. Les questions 1 à 5 reprennent E04 et E05, 6 à 8 E06 à E08, 9 à 11 préparent les paliers 2 et 3.

**1. Niveaux CIS.** Le **niveau 1** regroupe des réglages prudents, applicables à presque tout serveur sans perte notable de fonction ; le **niveau 2** (cumulatif) ajoute une défense renforcée qui coûte en fonctionnalités ou en exploitation. Exemples gênants du niveau 2 : partitions séparées pour `/var`, `/var/log`, `/var/log/audit`, `/home` (nos images ont une partition unique, refaire le partitionnement du parc est un projet en soi) ; auditd qui **arrête** le système quand son disque est plein (`admin_space_left_action = halt`) ; désactivation de fonctions réseau ou de modules utiles. « Serveur » plutôt que « poste » : pas d'interface graphique, pas d'utilisateurs interactifs locaux, des services exposés ; le profil poste ajoute des règles d'environnement de bureau (écran de veille, GNOME).

**2. ANSSI-BP-028.** Niveaux **cumulatifs** : minimal (à appliquer partout), intermédiaire (ajoute la majorité des recommandations raisonnables : comptes, droits, journalisation, réseau), renforcé (systèmes sensibles, mesures plus contraignantes : partitionnement, durcissement du noyau, restrictions de modules), élevé (systèmes très sensibles, avec des moyens et des compétences dédiés, mesures matérielles). Intermédiaire pour le socle : bon rapport sécurité / coût d'exploitation, atteignable sur VM. Renforcé se justifierait pour `kms01`, `vault01-03` ou `ca01` (clés de tout le parc) ; prix : partitions et options de montage dédiées, noyau et démarrage durcis, exploitation plus lourde, exceptions plus nombreuses à documenter.

**3. Réponse B.** `notapplicable` : la règle ne s'applique pas à ce système (plate-forme CPE ou condition d'applicabilité, par exemple un paquet absent) ; elle n'entre pas dans le score. Elle ne prouve donc rien : c'est le symptôme d'un mauvais contenu quand elle concerne presque toutes les règles. A est faux (ce serait `pass`), C décrit `error`, D décrit une règle exclue par un profil adapté (`notselected`).

**4. Avant de présenter le score.** Contrôler : (a) le **contenu** (version de ComplianceAsCode, empreinte, produit `debian13`) et le **profil** exact (`cis_level1_server`, pas le poste ni le niveau 2) ; (b) la répartition des résultats : peu de `notapplicable`, aucune règle en `error` (sinon l'évaluation n'a pas tout vu : droits, SCE), les `notchecked` expliqués (flux OVAL distant non téléchargé) ; (c) que l'évaluation a tourné **en root** sur la bonne machine, à la bonne date ; (d) que le score se compare à une évaluation du même profil et du même contenu. Puis présenter le score **avec** la liste des écarts et le plan.

**5. kube-bench sans référentiel 1.36.** Mesurer contre le référentiel le plus récent (`cis-1.12`), le **forcer** et l'écrire ; classer chaque FAIL (vrai écart, faux positif de version ou de chemin, choix assumé) en le vérifiant sur le nœud ; compléter par kubescape (cadres indépendants de la version) ; écrire dans le rapport : « mesuré contre CIS Kubernetes 1.12, dernier publié ; aucun référentiel ne couvre 1.36 ; écarts classés et traités » ; surveiller la publication d'un référentiel 1.36. Ne pas écrire « conforme au CIS ».

**6. Réponse C.** Pod Security en `enforce` **refuse** les pods non conformes : préventif. A détecte et avertit sans refuser ; B détecte à l'exécution ; D mesure périodiquement (détectif).

**7. Faux positif.** Exemples : kube-bench `4.1.1` sur le chemin du *drop-in* de kubeadm que l'outil ne connaît pas ; kube-bench `1.1.12` (etcd en root, choix de kubeadm) ; Lynis qui suggère un antivirus sur un serveur Linux ; OpenSCAP `sysctl_net_ipv4_ip_forward` sur une passerelle. Coût s'il n'est pas traité : bruit qui masque les vrais écarts, perte de confiance dans l'outil (« de toute façon c'est toujours rouge »), et la tentation de corriger aveuglément (couper le routage de `gw01`). Bonne façon : le classer, le **justifier** par une vérification, l'inscrire comme exception (avec date de revue) ou corriger la règle (profil adapté, macro Falco) ; mauvaise : désactiver l'outil, supprimer la règle sans trace, ou « corriger » le système pour faire plaisir à l'outil.

**8. Le coût d'une exception.** Sécurité : la protection n'existe plus pour cet espace (et « une semaine » devient souvent un an) ; suivi : quelqu'un doit la revoir et la retirer ; audit : chaque exception doit être justifiée, validée et datée, sinon c'est un écart non maîtrisé. Champs de la trace : règle concernée, périmètre exact (espace, charge, hôte), justification, risque résiduel, mesures compensatoires, demandeur, valideur, date de début, **date de revue ou d'expiration**, référence (ticket, ADR). C'est le registre d'E23.

**9. Conforme mais compromis.** Exemple : une faille de l'application MédiAgenda (injection, dépendance vulnérable) donne un shell dans le conteneur ; tout le CIS niveau 1 des VMs est respecté, le pod est même `restricted` ; l'attaquant lit les variables d'environnement, le jeton de compte de service, et tente des connexions vers la base d'une autre équipe. Ce qui le voit : **Falco** (shell, lecture du jeton, binaire déposé), Tetragon (connexion sortante inattendue), l'audit de l'API (utilisation du jeton), la NetworkPolicy qui refuse (et Hubble qui le montre). La conformité réduit la surface ; elle ne voit pas l'attaque.

**10. Kyverno et Pod Security ; VAP et Kyverno.** Pod Security est intégré à l'API, sans dépendance, impossible à « faire tomber » : c'est le **plancher**. Kyverno ajoute ce que PSA ne sait pas exprimer (registres, étiquettes, signatures, limites, génération) et les rapports de l'existant, au prix d'un webhook à maintenir disponible. La VAP `medisphere-images` est **dans** l'API (pas de webhook) et refuse en `Deny` ; `registres-autorises` produit les **rapports** de l'existant et prépare les règles de signature. Si Kyverno tombe (`failurePolicy: Ignore`), la VAP continue de protéger : défense en profondeur, à condition de garder les deux règles alignées (même liste de registres).

**11. Ne pas bloquer tout de suite.** (a) **Faux positifs** : une règle de blocage mal calibrée tue un processus légitime en production (une sauvegarde, un hook de migration) : panne causée par la sécurité ; (b) on ne connaît pas encore le **comportement normal** des charges (quels processus, quels fichiers, quelles connexions) : il faut l'observer ; (c) un blocage contourné rend le pod instable sans alerte claire. Condition pour commencer : une règle **étroite** (un binaire, un chemin, un espace), observée plusieurs jours sans faux positif, essayée d'abord dans `wb-essais`, avec un retour arrière connu et une alerte quand elle agit (E29).
