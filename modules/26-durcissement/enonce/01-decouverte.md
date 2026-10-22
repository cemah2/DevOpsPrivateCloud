# Module 26 — Palier 1 : Découverte

On ne durcit pas ce qu'on n'a pas mesuré. Ce palier établit l'état initial : le modèle de menace de la plateforme, un relevé Lynis et ssh-audit du socle, une évaluation OpenSCAP contre CIS et ANSSI sur deux VMs d'essai, kube-bench et kubescape sur `k8s-par1`. Puis il pose les trois premiers dispositifs du cluster dans leur mode le plus doux : Pod Security d'abord en avertissement, ensuite imposé là où rien ne casse ; Kyverno en audit ; Falco en détection. Il s'ouvre et se ferme sur un questionnaire.

Prérequis : module 25 terminé (`lab/bin/check 25 46` vert) ; module 24 (identité, comptes de bris de glace) ; module 14 (Pod Security et ValidatingAdmissionPolicy en E18, audit en E27, `wb-diagnostic` en E20) ; module 20 (Argo CD, `plateforme/charts-miroir`) ; modules 21 et 22 (Alertmanager, Loki locataire `audit`) ; module 12 (VMs DHCP sur `vsandbox`). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les **règles du module**.

**Rappels du module**
- Mesurer n'est pas modifier : au palier 1, aucune VM du socle n'est modifiée (Lynis audite, ssh-audit se connecte).
- Auditer avant d'imposer, un espace à la fois ; jamais d'étiquette ni de politique sur `kube-system`, `kyverno`, `argocd`.
- Aucun secret dans les commandes, les dépôts ou les rapports ; les rapports de mesure sont relus avant le commit.
- Mémoire : `durci-deb` et `durci-rocky` ajoutent 4 Go ; aucune autre VM temporaire en même temps.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| VMs mesurées (E03) | `gw01`, `git01`, `mon01`, `ipa01` (Rocky) ; rapport Lynis dans `/var/log/lynis-report.dat` de chaque VM |
| VMs d'essai (E04) | `durci-deb` (2261, Debian 13), `durci-rocky` (2262, Rocky 10) ; `vsandbox` DHCP, MAC `bc:24:11:99:26:01` et `…:02` ; état `envs/m26` |
| Contenu SCAP | Debian : `/usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml` ; Rocky : `/usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml` ; résultats dans `/var/lib/conformite/essais/` |
| Cluster | `k8s-par1` : `k8s-cp01-03` (10.10.40.51-53), `k8s-w01-03` (10.10.40.61-63) ; Kubernetes 1.36 |
| Espaces créés | `kyverno` (E07, `restricted`), `falco` (E08, `privileged`, exception écrite) |
| Projet créé | **`plateforme/politiques`** (E07) |
| Documentation | `docs/securite/durcissement/` : `modele-menace.md`, `etat-initial.md`, `referentiels.md`, `mesure-k8s-par1.md`, `mesures/k8s-par1/`, `pod-security.md` |

> **Mémoire** : E04 à E14 font tourner deux VMs de 2 Go. Si `pve01` manque de mémoire, arrête `durci-rocky` entre deux mesures ; n'arrête jamais une VM du socle ni un nœud de `k8s-par1` pour faire de la place (E05 à E08 ont besoin du cluster complet).

**Durée** : 15 à 19 heures. **Ordre conseillé** : celui de la carte, E01 → E09 (voir l'introduction).

---

### M26-E01 — Test de positionnement : sécurité des systèmes et de Kubernetes  `Q` `★★`

> **Ticket SEC-2701** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Une heure, par écrit, sans moteur de recherche ni IA. On va passer six semaines à « durcir » : je veux savoir si tu sais ce que ce mot recouvre, et ce qu'un conteneur protège vraiment. Sophie veut aussi savoir si tu sais lire un référentiel. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur la sécurité des systèmes Linux (surface d'attaque, privilèges, confinement) et de Kubernetes (isolation, admission, détection).
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 14 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Principes*

1. Qu'appelle-t-on la **surface d'attaque** d'une VM ? Donne cinq éléments qui la composent sur `git01`, et pour chacun une façon de la réduire.

2. Énonce le principe du **moindre privilège**, puis applique-le à deux cas du lab : le compte de service d'un pod de MédiAgenda, et le compte `admin` des VMs utilisé par Ansible.

3. Qu'est-ce que la **défense en profondeur** ? Pour l'attaque « un attaquant exécute du code dans le conteneur de l'API de MédiAgenda par une faille de l'application », cite quatre couches différentes qui peuvent l'empêcher d'aller plus loin, et dis ce que fait chacune.

4. *(QCM)* Classe ces contrôles. Lequel est **détectif** ?
   - A. Un montage de `/tmp` en `noexec`
   - B. Une règle Falco qui signale un shell interactif dans un conteneur
   - C. Une politique d'admission en refus qui exige `runAsNonRoot`
   - D. La restauration d'une VM depuis PBS

*Conteneurs et noyau*

5. « Un conteneur, c'est une petite VM. » Explique pourquoi c'est faux du point de vue de la sécurité. Quelles sont les briques du noyau qui isolent un conteneur, et qu'est-ce que tous les conteneurs d'un nœud partagent ?

6. Qu'est-ce qu'une **capacité** Linux (*capability*) ? Donne deux exemples de capacités dangereuses à laisser à un conteneur, avec ce qu'elles permettent. Que fait `capabilities: {drop: [ALL]}` ?

7. *(QCM)* Un pod est lancé avec `securityContext.privileged: true`. Quelle affirmation est vraie ?
   - A. Il a seulement le droit d'écouter sur un port inférieur à 1024
   - B. Il reçoit toutes les capacités, voit les périphériques de l'hôte et échappe aux confinements seccomp et LSM : la frontière avec le nœud devient très mince
   - C. Il tourne en root, mais reste confiné par seccomp
   - D. Rien de particulier tant que l'image ne tourne pas en root

8. À quoi sert **seccomp** ? Que fait le profil `RuntimeDefault`, et pourquoi Kubernetes ne l'applique-t-il pas par défaut à tous les pods (sans réglage du kubelet) ?

9. AppArmor et SELinux sont deux **LSM**. Quel est leur point commun, et quelle est la différence de fond dans leur façon de désigner ce qu'ils protègent (chemins ou étiquettes) ? Lequel trouveras-tu sur `ipa01`, lequel sur `git01` ?

*Kubernetes*

10. Décris dans l'ordre les étapes que franchit une requête `kubectl apply` d'un Deployment avant d'être écrite dans etcd. À quel moment Pod Security et Kyverno interviennent-ils ? Et pourquoi un Deployment accepté peut-il ne produire **aucun** pod ?

11. *(QCM)* Un espace porte `pod-security.kubernetes.io/enforce: restricted`. Un pod y tourne depuis hier en root, sans contexte de sécurité. Que se passe-t-il quand on pose l'étiquette ?
    - A. Le pod est tué immédiatement
    - B. Le pod continue de tourner ; l'API avertit que des pods existants violent le profil ; il sera refusé à sa prochaine recréation
    - C. L'étiquette est refusée tant que le pod existe
    - D. Le pod est modifié pour devenir conforme

12. Un attaquant a obtenu un shell dans un pod. Cite trois choses qu'il cherchera **dans le pod lui-même** pour aller plus loin dans le cluster, et ce qui, dans la configuration du pod, les lui aurait refusées.

*Référentiels*

13. CIS, ANSSI-BP-028, STIG de la DISA : qui publie chacun, à quoi sert-il, et pourquoi MédiSphère, éditeur français hébergeant des données de santé, retient-il les deux premiers ?

14. Un rapport dit « 92 % de conformité au CIS niveau 1 ». Cite trois raisons pour lesquelles ce chiffre ne suffit pas à dire que le serveur est sûr, et trois questions que tu poserais avant de le croire.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 28.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions sur les conteneurs, pars de ce qui est **partagé** : le noyau. Tout ce qui sépare deux conteneurs est un mécanisme de ce noyau, et chacun peut être affaibli par un réglage du pod.
</details>

<details><summary>Indice 2</summary>

Pour la question 12, pense à ce que Kubernetes monte par défaut dans un pod, à ce qu'un processus voit du réseau, et à ce que le nœud expose.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M26-E46), sans relire le corrigé, et compare. Parcours la matrice *Containers* de MITRE ATT&CK : <https://attack.mitre.org/matrices/enterprise/containers/>.

---

### M26-E02 — Modèle de menace de la plateforme  `RED` `★★`

> **Ticket SEC-2702** — *De : Sophie Laurent*
> Avant de durcir quoi que ce soit, je veux savoir **contre quoi**. L'auditeur nous demandera notre analyse de risques ; je ne veux pas d'un catalogue de 300 menaces génériques, mais les dix qui comptent pour nous, avec ce qui nous en protège déjà et ce qui manque. Chaque manque doit pointer vers un exercice du module ou un ticket. Deux pages, pas plus, relues en MR.

**Objectifs pédagogiques**
- Construire un modèle de menace simple : actifs, acteurs, frontières de confiance, menaces par composant (STRIDE).
- Prioriser les menaces et relier chacune à des contrôles existants et manquants.
- Écrire un document court, défendable devant un auditeur.

**Prérequis** : modules 00 à 25 (tu connais le lab) ; lecture de l'introduction du module.
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Livrable | `docs/securite/durcissement/modele-menace.md` de `plateforme/medisphere`, par MR relue par Sophie |
| Méthode | STRIDE (*Spoofing*, *Tampering*, *Repudiation*, *Information disclosure*, *Denial of service*, *Elevation of privilege*), appliqué par composant ; une échelle de risque simple (vraisemblance × impact, de 1 à 3 chacun) |
| Sources | `docs/socle/matrice-flux.md`, `docs/kubernetes/reseau/matrice-flux-cluster.md`, `docs/securite/secrets/inventaire-secrets.md` (M25-E02), `docs/securite/identite/` (M24), schémas du socle |

**Travail demandé**

1. **Actifs.** Liste ce qui a de la valeur, en partant des données de santé (bases de MédiAgenda, documents de MédiDoc, sauvegardes), des secrets (racine de la PKI, parts de descellement d'OpenBao, clé de signature Cosign, `admin.conf`), des identités (annuaire, Keycloak, comptes de bris de glace) et de la chaîne de livraison (GitLab, runners, Harbor, Argo CD). Pour chacun : où il vit, qui y accède.
2. **Acteurs.** Décris quatre à six acteurs avec leurs moyens : attaquant externe opportuniste, attaquant ciblé (rançongiciel visant la santé), compte de développeur compromis, initié malveillant, dépendance tierce compromise (image, chart, paquet), erreur humaine d'un administrateur.
3. **Frontières de confiance.** Dessine (ASCII ou Mermaid) les frontières du lab : Internet ↔ `gw01`/`gw02` ; DMZ ↔ INFRA ; MGMT ↔ le reste ; cluster ↔ VMs ; espace applicatif ↔ espace de plateforme ; conteneur ↔ nœud. Pour chaque frontière, ce qui la traverse et ce qui la contrôle.
4. **STRIDE par composant.** Pour six composants au moins (`gw01`, `git01` et les runners, Harbor, l'API de `k8s-par1`, un nœud travailleur, un pod de MédiAgenda, OpenBao), une ligne par lettre de STRIDE pertinente.
5. **Les dix menaces prioritaires.** Un tableau : menace, composant, vraisemblance, impact, risque, contrôles **existants** (avec le module qui les a posés), contrôles **manquants**, exercice de ce module (ou ticket) qui les traite.
6. **Hors périmètre et hypothèses.** Ce que le modèle ne couvre pas (sécurité physique, poste de l'apprenant…) et les hypothèses (l'hyperviseur est sain, la racine hors ligne n'a pas fui…).
7. MR, relecture par Sophie (toi-même, avec la grille du corrigé), fusion.

**Critères de réussite**
- [ ] `modele-menace.md` est sur `main` de `plateforme/medisphere` et tient en deux pages environ (hors schéma).
- [ ] Il contient les actifs, les acteurs, un schéma des frontières de confiance, une analyse STRIDE d'au moins six composants et un tableau de **dix** menaces priorisées.
- [ ] Chaque menace prioritaire cite au moins un contrôle existant (ou « aucun ») et renvoie à un exercice du module ou à un ticket.
- [ ] Aucun secret, aucune adresse de poste personnel, aucune information de vulnérabilité non corrigée exploitable telle quelle.

<details><summary>Indice 1</summary>

Commence par la question « qu'est-ce qui ferait la une du journal ? » : fuite de dossiers patients, rançongiciel qui chiffre les sauvegardes, image piégée en production. Remonte ensuite le chemin de l'attaquant jusqu'à l'actif.
</details>

<details><summary>Indice 2</summary>

Pour les contrôles existants, relis les modules : PSA posée par espace (M14-E18), images restreintes à Harbor par une VAP (M14-E18), signatures Cosign (M13), NetworkPolicy par défaut des équipes (M15), audit de l'API (M14-E27, M22), secrets dans OpenBao (M25), SSO et OTP (M24). Ce qui manque est souvent « personne ne regarde ce qui se passe » : c'est la détection.
</details>

**Pour aller plus loin** (facultatif) : compare ta liste avec la *Threat Matrix for Kubernetes* de Microsoft et avec les menaces de l'OWASP Kubernetes Top 10. [OWASP Kubernetes Top Ten](https://owasp.org/www-project-kubernetes-top-ten/) · [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/)

---

### M26-E03 — Mesurer avant d'agir : Lynis et ssh-audit  `LAB` `★`

> **Ticket SEC-2703** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Premier relevé, sans rien toucher. Lynis sur quatre VMs représentatives (la bordure, GitLab, la supervision et l'annuaire, qui est notre seule Rocky du socle), ssh-audit sur leurs serveurs SSH. Je veux l'indice de durcissement de chacune, les avertissements, et tes trois premières constatations. Ce sera la ligne de départ du rapport à l'auditeur : on la refera à la fin du module.

**Objectifs pédagogiques**
- Lancer un audit Lynis sans l'installer ni modifier la VM, lire son indice, ses avertissements et ses suggestions.
- Auditer la configuration cryptographique d'un serveur SSH avec ssh-audit et une politique de référence.
- Distinguer une constatation qui compte d'un bruit de l'outil.

**Prérequis** : M00 (accès SSH en `admin` aux VMs) ; M06-E19 (certificats SSH d'hôte) ; préparation de l'introduction (ssh-audit installé).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Lynis | **3.1.7**, archive `https://downloads.cisofy.com/lynis/lynis-3.1.7.tar.gz` ; empreinte SHA-256 publiée sur la page de téléchargement de CISOfy. Debian 13 n'empaquette que la 3.1.4, que Lynis lui-même juge périmée |
| Exécution | en root, **depuis le dossier déplié** (Lynis cherche ses fichiers à côté de lui) ; rapport machine dans `/var/log/lynis-report.dat`, journal détaillé dans `/var/log/lynis.log` |
| ssh-audit | **3.9.0** sur `adm01` (`uv tool`) ; politiques intégrées `Hardened Debian 13 (version 1)` et `Hardened Rocky Linux 10 (version 1)` |
| VMs | `gw01` (Debian, bordure), `git01` (Debian, GitLab), `mon01` (Debian, supervision), `ipa01` (Rocky 10, annuaire) |
| Livrable | `docs/securite/durcissement/etat-initial.md` de `plateforme/medisphere` |

> ⚠️ **Attention** : sur `gw01`, l'audit ne change rien au routage ni au pare-feu, mais il lance quelques centaines de commandes en root et lit beaucoup de fichiers. Lance-le hors de toute autre intervention sur la bordure, et vérifie après coup que `gw01` route toujours (`ping` d'Internet depuis une VM, VIP VRRP au bon endroit).

**Travail demandé**

1. Télécharge l'archive de Lynis dans `~/m26/e03/` sur `adm01` et vérifie son empreinte contre celle de la page de CISOfy. Lis `lynis/README` et la liste des options (`./lynis show options`, depuis le dossier).
2. Pour chaque VM : dépose l'archive dans `/root/` (sans la mettre dans un dossier accessible à tous), déplie-la, lance l'audit avec ton nom d'auditeur, sans attente entre les sections et sans couleurs. Récupère l'**indice de durcissement** (`hardening_index`), le nombre d'avertissements (`warning[]`) et de suggestions (`suggestion[]`) dans le rapport. Supprime ensuite le dossier déplié ; laisse le rapport et le journal dans `/var/log`.
3. Lis trois avertissements en détail (`./lynis show details <ID>` avant de supprimer le dossier, ou le journal) : de quoi s'agit-il, est-ce un vrai problème, quel contrôle CIS ou ANSSI y correspond probablement ?
4. Lance ssh-audit sur les quatre VMs, d'abord en lecture libre, puis contre la politique intégrée qui correspond à leur système :
   ```
   admin@adm01:~$ ssh-audit -L | grep -E 'Debian 13|Rocky Linux 10'
   admin@adm01:~$ ssh-audit git01.par1.medisphere.internal
   admin@adm01:~$ ssh-audit -P "Hardened Debian 13 (version 1)" git01.par1.medisphere.internal
   ```
   Relève les algorithmes signalés (échange de clés, chiffrement, MAC, clés d'hôte) et dis lesquels viennent d'un choix du lab (certificats d'hôte du M06, durcissement SSH des rôles communs) et lesquels sont des valeurs par défaut d'OpenSSH.
5. Écris `etat-initial.md` : date, versions des outils, un tableau par VM (système, indice Lynis, avertissements, suggestions, résultat de la politique ssh-audit), puis **trois constatations** classées (ce qui compte, pourquoi, ce que le module en fera). Relis-le : pas de nom de paquet vulnérable avec sa version exacte s'il n'est pas corrigé, pas de nom de compte personnel. MR, fusion.

**Critères de réussite**
- [ ] Les quatre VMs ont un rapport `/var/log/lynis-report.dat` produit par Lynis **3.1.7**, avec un indice de durcissement.
- [ ] Aucun dossier `lynis` déplié ne reste sur les VMs ; leur configuration n'a pas changé.
- [ ] `etat-initial.md` est sur `main` : indice Lynis et résultat ssh-audit des quatre VMs, trois constatations argumentées.

**Vérification** : `lab/bin/check 26 03`

<details><summary>Indice 1</summary>

Lynis refuse de démarrer s'il ne trouve pas son dossier `include/` à côté de lui : place-toi dans le dossier déplié avant de le lancer. En root, il vérifie aussi que ses fichiers appartiennent à root (sinon il s'arrête pour te le signaler) : déplie l'archive en root.
</details>

<details><summary>Indice 2</summary>

Le rapport `lynis-report.dat` est un fichier texte `clé=valeur` ; les tableaux s'écrivent `clé[]=valeur`, une ligne par élément. Un `grep -c` et un `grep '^hardening_index='` suffisent à remplir ton tableau. Pour ssh-audit, la sortie de `-P` se termine par un verdict `PASS` ou `FAIL` et la liste des écarts à la politique.
</details>

**Pour aller plus loin** (facultatif) : `ssh-audit --get-hardening-guide "Debian 13"` affiche le guide de durcissement correspondant à la politique : compare-le à ce que fera le rôle `durcissement` en E11. Relance Lynis avec `--profile` et un fichier `custom.prf` qui ignore un test hors sujet (par exemple les antivirus) : l'indice change, la sécurité non. [Lynis](https://cisofy.com/documentation/lynis/) · [ssh-audit](https://github.com/jtesta/ssh-audit)

---

### M26-E04 — OpenSCAP et ComplianceAsCode : évaluer une VM contre CIS et ANSSI  `LAB` `★★`

> **Ticket SEC-2704** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Lynis donne une tendance ; l'auditeur veut un **référentiel**. On retient CIS (niveau 1 serveur) et ANSSI-BP-028 (niveau intermédiaire), mesurés par OpenSCAP avec le contenu ComplianceAsCode. Pas sur le socle pour l'instant : deux VMs d'essai, une Debian et une Rocky, issues de nos images dorées. Je veux le score de départ de chacune, le rapport HTML, et une page qui dit quels profils on retient et pourquoi.

**Objectifs pédagogiques**
- Créer un environnement d'essai jetable par OpenTofu.
- Comprendre le contenu SCAP : *datastream*, profils, règles, OVAL ; savoir d'où il vient pour chaque distribution.
- Évaluer une VM contre un profil, produire un rapport ARF et HTML, lire une règle en échec.
- Choisir des profils et l'écrire.

**Prérequis** : M12-E02 (module `vm-noeud` avec cartes DHCP, état d'environnement) ; M03 (images dorées `deb13-gold`, `rocky10-gold`) ; M26-E03.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | `durci-deb` : VMID **2261**, famille `debian13` ; `durci-rocky` : **2262**, `rocky10` ; 2 vCPU, 2 Go, 32 Gio, `local-nvme` ; une carte `vsandbox` en **DHCP**, MAC `bc:24:11:99:26:01` et `bc:24:11:99:26:02` ; étiquettes `env-m26`, `role-durcissement` ; démarrage manuel |
| OpenTofu | `plateforme/infra`, dossier **`envs/m26`**, état S3 `envs/m26/terraform.tfstate` (compartiment `tofu-state`), même schéma que `envs/m12` |
| Debian 13 | `openscap-scanner` 1.4.2 (dépôt Debian) ; contenu : archive **`scap-security-guide-0.1.82.zip`** de la publication GitHub de ComplianceAsCode (`https://github.com/ComplianceAsCode/content/releases/tag/v0.1.82`), empreinte SHA-512 dans `scap-security-guide-0.1.82.zip.sha512` à côté ; à déplier dans **`/usr/local/share/scap/ssg-0.1.82/`** |
| Rocky 10 | paquets `openscap-scanner` et `scap-security-guide` (AppStream, 0.1.82) |
| Résultats | **`/var/lib/conformite/essais/`** sur chaque VM : `<profil>-<AAAAMMJJ>.arf.xml` et `<profil>-<AAAAMMJJ>.html` |
| Livrable | `docs/securite/durcissement/referentiels.md` de `plateforme/medisphere` |

> ⚠️ **Attention** : les deux VMs restent jusqu'à la fin d'E14 (4 Go). Ne lance pas cet exercice si une autre VM temporaire (`idp02`, `bao-essai`, `bao-restauration`) existe encore : détruis-la d'abord par son état OpenTofu.

**Travail demandé**

*A. Les VMs d'essai*

1. Écris `envs/m26/` dans `plateforme/infra` sur le modèle d'`envs/m12` : `versions.tf` (backend S3, clé `envs/m26/terraform.tfstate`), `providers.tf`, `variables.tf`, `durci.tf` (les deux VMs par le module `vm-noeud`, cartes DHCP à MAC imposée), `terraform.tfvars.exemple`. MR, plan relu, apply.
2. Vérifie que les deux VMs démarrent, prennent un bail de Kea et répondent en SSH par leur nom :
   ```
   admin@adm01:~$ ssh admin@durci-deb 'hostnamectl --static; cat /etc/debian_version'
   admin@adm01:~$ ssh admin@durci-rocky 'hostnamectl --static; cat /etc/rocky-release'
   ```

*B. Le contenu SCAP*

3. Sur `durci-rocky`, installe `openscap-scanner` et `scap-security-guide`, puis liste les *datastreams* fournis et leurs profils :
   ```
   [admin@durci-rocky ~]$ ls /usr/share/xml/scap/ssg/content/
   [admin@durci-rocky ~]$ oscap info --profiles /usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml
   ```
   Le paquet livre aussi `ssg-rhel10-ds.xml`. Cherche dans chacun des deux fichiers les plates-formes déclarées (élément `cpe-item` du dictionnaire CPE) : pourquoi faut-il évaluer une Rocky avec le premier, et que donnerait le second ?
4. Sur `durci-deb`, installe `openscap-scanner` et regarde ce que propose Debian : `apt show ssg-debian` (version, produits couverts). Télécharge l'archive 0.1.82 sur `adm01`, vérifie sa SHA-512, copie-la sur `durci-deb` et déplie-la dans `/usr/local/share/scap/ssg-0.1.82/` (propriétaire root, lecture pour tous). Liste les profils de `ssg-debian13-ds.xml`, et relève l'avertissement qu'affiche `oscap info` à propos d'une ressource distante : de quoi s'agit-il ?
5. Choisis, pour chaque système, le profil CIS niveau 1 **serveur** et le profil ANSSI-BP-028 **intermédiaire** (identifiants complets). Compte le nombre de règles de chaque profil (`oscap info --profile <id> <datastream>` ou un guide HTML) ; génère le guide du profil CIS de Debian pour le lire hors ligne :
   ```
   admin@durci-deb:~$ oscap xccdf generate guide --profile <ID-PROFIL> <DATASTREAM> > ~/guide-cis.html
   ```

*C. L'évaluation*

6. Crée `/var/lib/conformite/essais/` (root, 0750) sur les deux VMs. Évalue chaque VM contre ses deux profils, avec un résultat ARF et un rapport HTML nommés selon la convention (consulte `oscap xccdf eval --help` : options de profil, de résultats ARF et de rapport). Note la durée de chaque évaluation et le code de retour d'`oscap` : que signifie-t-il ?
7. Rapatrie les rapports HTML sur `adm01` (`~/m26/e04/`) et ouvre-les dans ton navigateur. Pour chaque évaluation, relève le **score**, le nombre de règles `pass`, `fail`, `notapplicable`, `notchecked`. Choisis **trois règles en échec** sur Debian et **deux** sur Rocky ; pour chacune : ce qu'elle vérifie, pourquoi elle échoue sur notre image dorée, et si la correction proposée par le contenu (Bash ou Ansible) pourrait casser quelque chose chez nous.
8. Écris `referentiels.md` : référentiels retenus et leur version (CIS Debian 13 v1.0.0, CIS RHEL 10, ANSSI-BP-028), profils retenus avec leurs identifiants exacts et leur *datastream*, d'où vient le contenu pour chaque système et pourquoi, profils écartés (niveau 2, ANSSI renforcé/élevé, STIG) et pourquoi, scores de départ des deux VMs, ce qu'on ne mesure **pas** avec ces profils. MR, fusion.

**Critères de réussite**
- [ ] `durci-deb` (2261) et `durci-rocky` (2262) existent dans Proxmox, avec l'étiquette `env-m26`, créées par l'état `envs/m26` ; elles répondent en SSH.
- [ ] `/usr/local/share/scap/ssg-0.1.82/ssg-debian13-ds.xml` est présent sur `durci-deb` ; `ssg-rl10-ds.xml` sur `durci-rocky`.
- [ ] Chaque VM a, dans `/var/lib/conformite/essais/`, un résultat ARF et un rapport HTML pour son profil CIS niveau 1 serveur et pour ANSSI-BP-028 intermédiaire.
- [ ] `referentiels.md` est sur `main` : profils retenus (identifiants exacts), origine du contenu, scores de départ.

**Vérification** : `lab/bin/check 26 04` (après E14, quand les VMs d'essai sont détruites, le check ne contrôle plus que la documentation).

<details><summary>Indice 1</summary>

Un *datastream* (fichier `ssg-<produit>-ds.xml`) regroupe tout : la liste des règles (XCCDF), leurs vérifications (OVAL), les profils, le dictionnaire CPE qui dit sur quel système il s'applique. Une règle évaluée sur un système que le CPE ne reconnaît pas est `notapplicable`, pas `fail` : un score de 100 % sur une évaluation où tout est « non applicable » ne mesure rien.
</details>

<details><summary>Indice 2</summary>

`oscap` accepte l'identifiant complet du profil (`xccdf_org.ssgproject.content_profile_…`) ou sa fin. Les options utiles d'`oscap xccdf eval` : `--profile`, `--results-arf`, `--report`. Le code de retour distingue « aucune règle en échec » de « au moins une règle en échec » de « erreur ».
</details>

<details><summary>Indice 3</summary>

Sur Debian, la règle des correctifs de sécurité s'appuie sur le flux OVAL de Debian, publié sur `www.debian.org` et référencé à distance par le *datastream* : sans `--fetch-remote-resources`, `oscap` ne le télécharge pas et la règle ne peut pas conclure. Décide (et écris dans `referentiels.md`) si l'analyse doit sortir sur Internet pour cela, ou si l'information viendra d'ailleurs (E30).
</details>

**Pour aller plus loin** (facultatif) : génère la remédiation Ansible d'un profil (`oscap xccdf generate fix --fix-type ansible --profile … --result-id …`) à partir du résultat ARF et lis-la : ce sera la tentation de E10, et la raison pour laquelle le module écrit son propre rôle. [ComplianceAsCode, profils et produits](https://complianceascode.readthedocs.io/en/latest/) · [OpenSCAP, manuel](https://static.open-scap.org/openscap-1.3/oscap_user_manual.html)

---

### M26-E05 — kube-bench et kubescape : évaluer `k8s-par1`  `LAB` `★★`

> **Ticket SEC-2705** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Même exercice pour le cluster. kube-bench pour le CIS Kubernetes sur un nœud de contrôle et un travailleur, kubescape pour une vue plus large (NSA, MITRE). Au M18, on avait vu que kube-bench n'a pas de référentiel pour notre version : je veux savoir lequel tu utilises, pourquoi, et ce que ça change pour la lecture. Et je veux une lecture **critique** : kubeadm fait certains choix exprès, je ne veux pas cinquante « FAIL » dont la moitié sont des faux positifs.

**Objectifs pédagogiques**
- Lancer kube-bench comme un Job sur un nœud précis, avec un référentiel choisi, et en récupérer le résultat.
- Lancer kubescape contre le cluster avec plusieurs cadres et lire un score par contrôle.
- Classer chaque écart : vrai écart, faux positif (chemin, version, choix de kubeadm), contrôle manuel.

**Prérequis** : M14-E20 (`wb-diagnostic`, espace `privileged` réservé aux administrateurs) ; M18-E15 (kube-bench en aperçu) ; M24-E16 (accès `kubectl` par OIDC, `admin.conf` en secours).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| kube-bench | **0.16.0**, image `registry.par1.medisphere.internal/dockerhub/aquasec/kube-bench:v0.16.0` ; manifestes de départ `job-master.yaml` et `job-node.yaml` de l'étiquette `v0.16.0` du dépôt `aquasecurity/kube-bench` |
| Référentiels | le plus récent est `cis-1.12`, associé à Kubernetes 1.32 à 1.34 dans `cfg/config.yaml` ; cibles de `cis-1.12` : `master`, `controlplane`, `etcd`, `node`, `policies` |
| Où | espace **`wb-diagnostic`** (le Job demande `hostPID` et des montages `hostPath` en lecture) ; nœuds `k8s-cp01` et `k8s-w01` |
| kubescape | CLI **4.0.x** sur `adm01`, cadres `nsa`, `mitre`, `cis-v1.12.0` (`kubescape list frameworks`) |
| Livrables | `docs/securite/durcissement/mesure-k8s-par1.md` et `docs/securite/durcissement/mesures/k8s-par1/` (`kube-bench-k8s-cp01.json`, `kube-bench-k8s-w01.json`, `kubescape-resume.json`) de `plateforme/medisphere` |

**Travail demandé**

1. Lis `cfg/config.yaml` de kube-bench 0.16.0 (correspondance des versions) et explique en deux phrases pourquoi la détection automatique ne choisira rien de satisfaisant sur 1.36.
2. Récupère `job-master.yaml` et `job-node.yaml` de l'étiquette `v0.16.0` dans `~/m26/e05/`. Adapte-les :
   - espace `wb-diagnostic`, nom de Job explicite, **un nœud imposé** (`k8s-cp01` pour le premier, `k8s-w01` pour le second) ;
   - image du cache Harbor, à la version exacte (jamais `latest`) ;
   - commande `kube-bench run` avec le référentiel `cis-1.12` **forcé**, les cibles qui concernent chaque nœud, une sortie JSON ;
   - un nettoyage automatique du Job une heure après sa fin.
   Relis les montages : tous en lecture seule ? Lesquels ne servent à rien sur un nœud kubeadm Debian (chemins d'autres distributions) ?
3. Lance les deux Jobs, attends leur fin, récupère la sortie JSON de chacun (`kubectl logs`) dans `mesures/k8s-par1/`. Compte PASS, FAIL, WARN, INFO par nœud (`jq '.Totals'`).
4. Classe **chaque FAIL** du nœud de contrôle et du travailleur dans un tableau : identifiant, intitulé court, classement (*vrai écart* / *faux positif de chemin ou de version* / *choix assumé de kubeadm ou du lab* / *à vérifier à la main*), justification, exercice du module qui le traite (E25 kubelets, E28 audit…). Au moins trois écarts doivent être vérifiés **sur le nœud** (ligne de commande du processus, fichier de configuration, droits d'un fichier).
5. Lance kubescape depuis `adm01`, avec ton accès OIDC, sans rien envoyer à un service externe :
   ```
   admin@adm01:~/m26/e05$ kubescape scan framework nsa,mitre,cis-v1.12.0 --keep-local --format json --output kubescape.json
   ```
   Relève le score de chaque cadre, puis les cinq contrôles les plus mal notés et les espaces qui en sont responsables. Extrais un résumé (cadre, score, contrôles en échec avec leur nombre de ressources) dans `kubescape-resume.json` : le rapport complet, trop gros et trop bavard (noms d'objets, images), reste dans `~/m26/e05/`.
6. Écris `mesure-k8s-par1.md` : versions et référentiels, scores, tableau de classement des FAIL de kube-bench, cinq constatations de kubescape, et ce que l'absence de référentiel 1.36 implique (écart écrit pour l'auditeur). MR, fusion.

**Critères de réussite**
- [ ] `mesures/k8s-par1/kube-bench-k8s-cp01.json` et `kube-bench-k8s-w01.json` sont sur `main`, produits par kube-bench avec le référentiel `cis-1.12`, et `kubescape-resume.json` aussi.
- [ ] `mesure-k8s-par1.md` classe chaque FAIL de kube-bench et cite les scores de kubescape par cadre.
- [ ] Plus aucun pod `kube-bench` ne reste dans `wb-diagnostic` après une heure.

**Vérification** : `lab/bin/check 26 05`

<details><summary>Indice 1</summary>

`kube-bench run --help` liste les options globales : le référentiel se force par une option qui exclut la version de Kubernetes ; la sortie machine et la liste des cibles ont chacune la leur. Un Job se nettoie seul avec un champ de sa `spec` (*TTL after finished*).
</details>

<details><summary>Indice 2</summary>

Pour un nœud imposé, `nodeName` dans la spécification du pod suffit (il court-circuite l'ordonnanceur, donc aussi les *taints* : pas besoin de tolérance pour `k8s-cp01`). Les FAIL de kubeadm les plus fréquents portent sur l'utilisateur et les droits du dossier d'etcd, les drapeaux du kube-apiserver qui ne sont pas posés (`--profiling`, profils d'audit…), et des fichiers que kubeadm range ailleurs que là où le référentiel les attend.
</details>

<details><summary>Indice 3</summary>

kubescape sans l'opérateur ne voit que l'API : les contrôles qui demandent de lire les fichiers des nœuds sont « ignorés » ou évalués sur des informations partielles. Note-les à part ; c'est la raison d'être de kube-bench, qui tourne **sur** le nœud.
</details>

**Pour aller plus loin** (facultatif) : planifie kube-bench en CronJob qui écrit son résultat dans un compartiment S3 (préfiguration d'E24) ; regarde ce qu'apporte l'opérateur kubescape (node-agent, analyse continue) et son coût en mémoire. [kube-bench](https://github.com/aquasecurity/kube-bench/blob/main/docs/running.md) · [kubescape, cadres](https://kubescape.io/docs/frameworks-and-controls/frameworks/)

---

### M26-E06 — Pod Security Admission : auditer puis imposer `restricted`  `LAB` `★★`

> **Ticket SEC-2706** — *De : Sophie Laurent* — *Copie : Julien Petit, Nadia Roussel*
> Au M14, on a posé Pod Security espace par espace, au fil des besoins. Résultat : des versions de profil différentes, des espaces sans étiquette, des exceptions dont personne ne sait plus pourquoi elles existent. Je veux `restricted` imposé partout où c'est possible, en version figée, et un **registre** : chaque espace qui ne l'est pas a une raison écrite et un responsable. Julien demande une chose : que ses déploiements ne s'arrêtent pas un matin sans prévenir.

**Objectifs pédagogiques**
- Inventorier l'état de Pod Security de tous les espaces d'un cluster.
- Mesurer l'effet d'un durcissement avant de l'imposer (`warn`, `audit`, `--dry-run=server`).
- Corriger une charge non conforme plutôt qu'affaiblir l'espace.
- Tenir un registre d'exceptions et le refléter dans le code.

**Prérequis** : M14-E18 (Pod Security, étiquettes d'espace) ; M14-E27 (journal d'audit) ; M22 (journal d'audit dans Loki, locataire `audit`) ; M20 (`plateforme/k8s/espaces/`, `task appliquer`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Où vivent les espaces | `plateforme/k8s/espaces/` (un fichier ou un dossier par espace), appliqués par `task appliquer` |
| Cible | tous les espaces applicatifs et de plateforme : `enforce: restricted`, `enforce-version: v1.36`, `audit: restricted`, `warn: restricted` (`audit-version` et `warn-version` à `latest`, pour voir venir la prochaine version) |
| Hors périmètre | `kube-system`, `kube-public`, `kube-node-lease` (composants du cluster, gérés par kubeadm et Cilium) |
| Exceptions | profil `baseline` ou `privileged` en `enforce`, mais `audit` et `warn` en `restricted`, et l'annotation **`medisphere.internal/exception-psa`** (raison courte et ADR ou ticket), comme `supervision-noeuds` au M21 |
| Livrables | `plateforme/k8s/outils/psa-inventaire.sh` (outil en lecture), étiquettes mises à jour dans `espaces/`, registre `docs/securite/durcissement/pod-security.md` |

**Travail demandé**

1. **Inventaire.** Écris `outils/psa-inventaire.sh` dans `plateforme/k8s` : pour chaque espace, les six étiquettes `pod-security.kubernetes.io/*` (ou « absent »), l'annotation d'exception, le nombre de pods. Sortie en tableau, triée. Option `--essai <profil>` : pour chaque espace, simule la pose de `enforce=<profil>` avec `kubectl label --dry-run=server --overwrite` et affiche les avertissements de l'API (rien n'est modifié). Le script ne fait que lire ; `shellcheck` propre.
2. Lance l'inventaire, puis l'essai `restricted`. Classe chaque espace : (a) déjà conforme, version à aligner ; (b) non conforme à cause d'**une charge corrigeable** ; (c) non conforme **par nature** (accès à l'hôte, privilèges) ; (d) sans étiquette du tout (l'espace `default`, qui ne doit rien héberger, en fait partie : il sera verrouillé en `restricted`).
3. Pour les espaces (b) : trouve la charge fautive (l'avertissement nomme le pod et la règle), corrige-la **dans son dépôt** (values d'un chart dans `plateforme/gitops` ou `plateforme/observabilite`, manifeste dans `plateforme/k8s`…) par une MR, et vérifie que l'essai ne la signale plus. Si la correction relève d'une équipe applicative, ouvre-lui un ticket et laisse l'espace en (c) **provisoirement**, avec une date.
4. Lis, dans Loki (locataire `audit`, organisation « Sécurité » de Grafana), les annotations que l'API pose déjà dans le journal d'audit quand un pod viole le profil `audit` d'un espace (`pod-security.kubernetes.io/audit-violations`) sur les sept derniers jours : quels espaces, quels pods ?
5. **Imposer.** Mets à jour les fichiers d'`espaces/` : cible pour (a) et (b) ; exception écrite pour (c) ; étiquettes complètes pour (d). Procède **par lots** (d'abord les espaces `wb-*` et de plateforme, ensuite les espaces applicatifs `mediagenda-*` et `medidoc-*`), chaque lot par une MR et `task appliquer`, avec un essai `--dry-run=server` juste avant.
   > ⚠️ **Attention** : `enforce` ne tue aucun pod, mais refuse leurs remplaçants. Après chaque lot, provoque un redémarrage d'une charge de l'espace (`kubectl -n <espace> rollout restart deployment/<nom>` dans un espace de plateforme ; pour MédiAgenda, une synchronisation Argo CD qui recrée un pod) et vérifie que le nouveau pod démarre. Retour arrière : l'ancienne étiquette dans `espaces/` et `task appliquer` (règle 2 de l'introduction).
6. Écris `pod-security.md` : un tableau de **tous** les espaces (profil imposé, version, exception, raison, responsable, date de revue), la procédure pour créer un nouvel espace, et la façon de demander une exception (en attendant le RB-261 d'E23).

**Critères de réussite**
- [ ] Tout espace hors `kube-system`, `kube-public` et `kube-node-lease` porte les étiquettes `enforce`, `audit` et `warn` de Pod Security.
- [ ] Tout espace dont `enforce` n'est pas `restricted` porte l'annotation `medisphere.internal/exception-psa` et a `audit` et `warn` en `restricted` ; les espaces `mediagenda-*` et `medidoc-*` sont tous en `restricted` sans exception.
- [ ] Les espaces en `restricted` ont `enforce-version: v1.36` ; l'espace `default` est en `restricted`.
- [ ] `outils/psa-inventaire.sh` et `pod-security.md` sont sur `main` de leurs projets.

**Vérification** : `lab/bin/check 26 06`

<details><summary>Indice 1</summary>

`kubectl label --dry-run=server` envoie la requête jusqu'au contrôleur d'admission : c'est lui qui renvoie l'avertissement `existing pods in namespace … violate the new PodSecurity enforce level`, suivi d'une ligne par pod fautif et par règle. Rien n'est écrit. Il te faut le droit de modifier les espaces : ton compte d'administrateur, pas celui des checks.
</details>

<details><summary>Indice 2</summary>

Les violations « corrigeables » les plus fréquentes : un conteneur sans `seccompProfile`, un `allowPrivilegeEscalation` absent, des capacités non retirées, un conteneur d'initialisation oublié (qui tourne en root pour un `chown`). Les violations « par nature » : `hostNetwork`, `hostPID`, `hostPath`, `privileged` (agents de nœud, pilotes CSI, collecteurs de journaux, outils de diagnostic).
</details>

**Pour aller plus loin** (facultatif) : la configuration d'admission du kube-apiserver (`AdmissionConfiguration`, plugin `PodSecurity`) permet de poser un profil **par défaut** pour les espaces sans étiquette et des **exemptions** par utilisateur ou par *RuntimeClass* : lis la page et dis ce que cela changerait chez nous (rôle `k8s_plan_controle`, un nœud de contrôle à la fois). [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) · [Migrer vers Pod Security](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

---

### M26-E07 — Kyverno : installation et premières politiques CEL  `LAB` `★★`

> **Ticket PLAT-2707** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Pod Security ne sait dire que « privilégié ou pas ». Pour le reste (registres, étiquettes, signatures, limites), on installe Kyverno. Règle de la maison : **uniquement** les nouveaux types CEL, la 1.20 supprimera les `ClusterPolicy`. Un dépôt à part pour les politiques, avec des tests, appliqué par Argo CD. Et rien en refus pour l'instant : deux politiques en audit, qu'on lise les rapports pendant une semaine avant de décider quoi que ce soit.

**Objectifs pédagogiques**
- Installer un contrôleur d'admission à webhook de façon sûre (réplicas, exclusions, `failurePolicy`).
- Écrire des `ValidatingPolicy` en CEL, les tester hors cluster avec la CLI `kyverno`, les livrer par GitOps.
- Lire des `PolicyReport` et en tirer une décision.

**Prérequis** : M26-E06 ; M20-E13 (`plateforme/charts-miroir`), M20-E15 (Applications de plateforme) ; M14-E18 (VAP `medisphere-images`) ; M17 (étiquettes `medisphere.internal/*` des charts).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `kyverno/kyverno` **3.9.2** (Kyverno 1.19.2) de `https://kyverno.github.io/kyverno/`, empreinte de l'index `sha256:f6fe7184544d5e2ee33a77808c09e67aa603ce6560cc197038fde31d727c861e` ; il installe ses CRD (sous-chart `kyverno-api`) |
| Images | publiées sur `reg.kyverno.io` **et** `ghcr.io/kyverno/*` ; Harbor n'a pas de cache pour le premier : passe par le cache `ghcr` (`registry.par1.medisphere.internal/ghcr`) |
| Espace | **`kyverno`**, PSA `restricted` (les conteneurs du chart sont conformes : vérifie-le au rendu) |
| Exigences | contrôleur d'admission **×3** (budget de perturbation), contrôleur d'arrière-plan ×2 ; webhooks **exclus** de `kube-system`, `kyverno`, `argocd`, `cilium` ; métriques collectées par Prometheus (étiquette `medisphere.internal/supervision: "oui"`) ; aucune image `latest`, même pour les *hooks* |
| Projet | **`plateforme/politiques`** (groupe `plateforme`, `main` protégée) : `kyverno/validation/`, `kyverno/tests/`, `kustomization.yaml` à la racine (seules les politiques y figurent, jamais les ressources de test), `.gitlab-ci.yml` |
| Politiques | `registres-autorises` : toute image d'un pod vient de `registry.par1.medisphere.internal/` ; `exiger-etiquettes` : tout Deployment, StatefulSet, DaemonSet et CronJob porte `medisphere.internal/equipe`, égale à celle de son espace ; les deux sur les espaces d'équipes (étiquette `medisphere.internal/equipe`), en **`[Audit, Warn]`** |
| Applications | `plateforme/gitops` : `plateforme/kyverno.yaml` (chart + `valeurs/kyverno/values.yaml`), `plateforme/politiques.yaml` (Kustomize, dépôt `plateforme/politiques`) |
| Checks | ClusterRole agrégée **`wb-checks-securite`** (`plateforme/k8s/rbac/`) étendue : `policies.kyverno.io` (toutes les politiques et exceptions) et `wgpolicyk8s.io` (`policyreports`, `clusterpolicyreports`) en lecture |

**Travail demandé**

*A. Le contrôleur*

1. Ajoute le chart à `charts.yaml` de `plateforme/charts-miroir` (vérifie l'empreinte sur l'index amont et sur l'archive). Rends-le en local avec tes values et inspecte : liste des CRD (repère les groupes `policies.kyverno.io` et `kyverno.io`, et les versions servies), images de **tous** les objets, y compris les *hooks* Helm (pods de test, Jobs de suppression), contextes de sécurité des Deployments.
2. Écris `espaces/kyverno.yaml` (PSA `restricted`, `v1.36`), `valeurs/kyverno/values.yaml` et l'Application `plateforme/kyverno.yaml` (synchronisation automatique, `ServerSideApply` : les CRD sont trop grosses pour l'application côté client). Complète l'AppProject `plateforme` : destination `kyverno`, types sans espace que le chart crée. MR, synchronisation.
   > ⚠️ **Attention** : à partir de là, chaque requête d'écriture des espaces non exclus passe par les webhooks de Kyverno. Garde un œil sur `kubectl get --raw /readyz` et sur Argo CD pendant la première heure. Si l'API ralentit ou refuse (`failed calling webhook "…kyverno…"`), le retour arrière est de supprimer l'Application **avec** ses ressources (Kyverno retire ses configurations de webhooks à l'arrêt ; sinon, `kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l webhook.kyverno.io/managed-by=kyverno` avec `admin.conf`).
3. Vérifie : trois pods d'admission prêts sur des nœuds différents, les configurations de webhooks créées par Kyverno (`kubectl get validatingwebhookconfigurations`), leur `namespaceSelector` et leur `failurePolicy`, les cibles Kyverno `up` dans Prometheus.

*B. Les politiques*

4. Crée le projet `plateforme/politiques` (README : contenu, règles, comment une politique passe d'`Audit` à `Deny`). Écris les deux `ValidatingPolicy` (`policies.kyverno.io/v1`) dans `kyverno/validation/` :
   - `registres-autorises` vise les **pods** (laisse l'*autogen* de Kyverno générer les règles des contrôleurs) et lit aussi les conteneurs d'initialisation et éphémères ;
   - `exiger-etiquettes` vise directement les contrôleurs et compare l'étiquette de l'objet à celle de son espace (variable `namespaceObject`) ;
   - `failurePolicy: Ignore` (une politique d'audit ne doit jamais bloquer l'API), message d'erreur qui nomme l'objet et la valeur fautive.
5. Écris un test par politique dans `kyverno/tests/<politique>/` (`kyverno-test.yaml`, ressources conformes et non conformes, valeurs qui simulent l'étiquette de l'espace) et fais-les passer en local :
   ```
   admin@adm01:~/src/politiques$ kyverno test kyverno/tests/
   ```
   Ajoute un `.gitlab-ci.yml` qui lance ces tests sur chaque MR (image de la CLI `kyverno` par le cache `ghcr`, version exacte).
6. Écris `kustomization.yaml` et l'Application `plateforme/politiques.yaml` (les politiques n'existent qu'une fois les CRD installées : prévois-le). MR, synchronisation, `kubectl get validatingpolicies` : les deux politiques sont prêtes.

*C. Les rapports*

7. Essaie en simulation dans un espace d'équipe (rien n'est créé), d'abord avec une image de Harbor, puis avec une image de Docker Hub :
   ```
   admin@adm01:~$ kubectl -n mediagenda-dev create deployment essai-kyverno --dry-run=server -o name \
   >   --image=registry.par1.medisphere.internal/dockerhub/library/nginx:1.29
   admin@adm01:~$ kubectl -n mediagenda-dev create deployment essai-kyverno --dry-run=server -o name \
   >   --image=docker.io/library/nginx:1.29
   ```
   Lis les avertissements (`Warning:`) et les refus. Qui parle dans chaque cas : Kyverno ou la VAP `medisphere-images` du M14 (en `Deny`) ? Pourquoi le second essai ne montre-t-il **pas** l'avertissement de `registres-autorises` ? (Pense à l'ordre des étapes de l'admission.)
8. Attends un cycle d'analyse en arrière-plan, puis lis les rapports : `kubectl get policyreports -A`, puis le détail d'un rapport en échec. Combien d'objets violent chaque politique, dans quels espaces ? Lesquels sont de vrais écarts, lesquels sont des oublis de chart (par exemple un StatefulSet d'un sous-chart sans l'étiquette d'équipe) ?
9. Étends `wb-checks-securite` (lecture seule de `policies.kyverno.io`, de `wgpolicyk8s.io`, des anciennes `ClusterPolicy`/`Policy` de `kyverno.io` pour pouvoir prouver qu'il n'y en a pas, et des configurations de webhooks d'admission) dans `plateforme/k8s/rbac/`, `task appliquer`. Note dans le README de `plateforme/politiques` ta proposition pour chaque politique : passer en refus (quand, où) ou rester en audit, et pourquoi.

**Critères de réussite**
- [ ] L'Application `kyverno` est `Synced` et `Healthy` ; trois pods du contrôleur d'admission sont prêts ; aucune image du chart ne vient d'ailleurs que de `registry.par1.medisphere.internal/`.
- [ ] Les webhooks de Kyverno excluent `kube-system`, `kyverno` et `argocd`.
- [ ] `registres-autorises` et `exiger-etiquettes` existent en `policies.kyverno.io/v1`, prêtes, en `[Audit, Warn]` ; aucune `ClusterPolicy` dans le cluster.
- [ ] Des `PolicyReport` contiennent des résultats pour les deux politiques.
- [ ] Le dernier pipeline de `main` de `plateforme/politiques` a réussi (tests `kyverno test`).

**Vérification** : `lab/bin/check 26 07`

<details><summary>Indice 1</summary>

Le chart a une valeur `global.image.registry` qui remplace le registre de **presque** toutes les images ; les *hooks* (tests, nettoyage des webhooks à la suppression) ont leurs propres valeurs `test.image` et `webhooksCleanup.image`, avec une étiquette par défaut à `latest`. Le sélecteur d'espaces des webhooks se règle dans `config.webhooks` ; l'espace `kyverno` est exclu par `config.excludeKyvernoNamespace`.
</details>

<details><summary>Indice 2</summary>

En CEL, un champ facultatif se lit sans erreur avec l'opérateur `?` et `orValue()` : `object.spec.?initContainers.orValue([])`. Une étiquette dont le nom contient des points et une barre se lit par indexation : `object.metadata.?labels[?'medisphere.internal/equipe'].orValue('')`. Dans un `messageExpression`, les chaînes CEL ne connaissent pas le doublement de l'apostrophe : écris le message entre guillemets doubles ou utilise l'apostrophe typographique.
</details>

<details><summary>Indice 3</summary>

Dans un test de la CLI, la politique ne voit pas de cluster : les étiquettes de l'espace se donnent dans un fichier de valeurs (`kind: Values`, liste `namespaceSelector` avec `name` et `labels`). Pour l'Application `politiques`, l'option de synchronisation qui évite l'échec de la simulation sur un type encore inconnu est `SkipDryRunOnMissingResource=true` ; un `retry` fait le reste.
</details>

**Pour aller plus loin** (facultatif) : `kyverno apply` accepte un cluster en cible (`--cluster`) : lance tes deux politiques contre tout le cluster depuis `adm01` et compare au contenu des rapports. Lis la page sur la haute disponibilité de Kyverno et sur les métriques de latence des webhooks (`kyverno_admission_review_duration_seconds`). [Kyverno, ValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/) · [Installation par Helm](https://kyverno.io/docs/installation/methods/) · [CLI : tests](https://kyverno.io/docs/kyverno-cli/)

---

### M26-E08 — Falco : installation et premières détections  `LAB` `★★`

> **Ticket SEC-2708** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Aujourd'hui, si quelqu'un ouvre un shell dans un pod de production et lit des fichiers qu'il ne devrait pas, on le saura… jamais. Installe Falco sur tous les nœuds, avec les règles par défaut pour commencer, et branche ses sorties : les alertes sérieuses vers Alertmanager, tout le reste dans Loki, chez nous, dans le locataire `audit`. Fais-moi une démonstration dans `wb-essais` : un shell, une lecture de `/etc/shadow`, et je veux voir les deux. Nadia veut savoir combien ça coûte en mémoire.

**Objectifs pédagogiques**
- Installer un capteur eBPF en DaemonSet sur tous les nœuds, y compris les nœuds de contrôle.
- Comprendre une règle Falco (condition, sortie, priorité) et le chemin d'un événement jusqu'à l'astreinte.
- Brancher falcosidekick vers Alertmanager et Loki, et ouvrir les flux nécessaires.

**Prérequis** : M26-E06 ; M21-E02 (Alertmanager `kps`, politique `alertmanager-entree`) ; M22-E02 et M22-E16 (Loki multi-locataire, politique `loki-entree`, source « Loki — audit » dans l'organisation « Sécurité ») ; M20-E15.
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `falcosecurity/falco` **9.2.1** (Falco 0.45.1) de `https://falcosecurity.github.io/charts`, empreinte de l'index `sha256:726c1fe08c3fd3e2789d4072b34f9eee94ecccad734fee471cc7546124570c6c` ; sous-chart `falcosidekick` 0.14.1 inclus dans l'archive |
| Images | `falcosecurity/falco:0.45.1`, `falcosecurity/falcosidekick` : par le cache `dockerhub` de Harbor. Le sous-chart 0.14.1 a pour version applicative 2.31.1 mais tire par défaut l'image **2.32.0** : impose l'étiquette **2.31.1** (version de référence) |
| Pilote | **`modern_ebpf`** (sonde eBPF intégrée au binaire, noyau ≥ 5.8 avec BTF : Debian 13 a un 6.12) |
| Règles | celles livrées **dans l'image** (`/etc/falco/falco_rules.yaml`) ; falcoctl (téléchargement et suivi des règles depuis Internet) **désactivé** : les règles changent par une montée de version relue, pas en douce |
| Espace | **`falco`** : PSA `privileged` (le capteur a besoin des privilèges), `audit`/`warn` en `restricted`, exception écrite dans `pod-security.md` |
| Sorties | Falco → falcosidekick (`http_output`, en JSON) ; falcosidekick → Alertmanager **`http://kps-alertmanager.supervision.svc:9093`**, chemin **`/api/v2/alerts`**, priorité ≥ `warning`, étiquettes `equipe: plateforme`, `gravite: avertissement` (affiné en E19) ; → Loki **`http://loki.journaux.svc:3100`**, locataire **`audit`**, priorité ≥ `notice` ; champ personnalisé `service: falco` (devient une étiquette dans Loki et dans Alertmanager) |
| Pod d'essai | `falco-essai` dans **`wb-essais`** (PSA `baseline`) : image `registry.par1.medisphere.internal/dockerhub/library/debian:13-slim`, commande `sleep 3600` |

**Travail demandé**

*A. Le capteur*

1. Ajoute le chart à `charts.yaml` de `plateforme/charts-miroir`. Rends-le en local avec tes values et vérifie : un DaemonSet `falco` et ses tolérances (nœuds de contrôle), le contexte de sécurité du conteneur, les montages de l'hôte, la configuration générée (`falco.yaml` dans la ConfigMap : pilote, fichiers de règles, `http_output`), l'absence de conteneur falcoctl, les images.
2. Écris `espaces/falco.yaml` (exception écrite) et ajoute la ligne de l'espace au registre `pod-security.md`. Écris `valeurs/falco/values.yaml` (pilote, registres, falcoctl désactivé, falcosidekick et ses deux sorties, ressources réservées raisonnables pour nos nœuds de 4 Go, collecte des métriques de falcosidekick par Prometheus) et l'Application `plateforme/falco.yaml` ; complète l'AppProject `plateforme`.
3. **Flux.** falcosidekick doit joindre Alertmanager et Loki, que des CiliumNetworkPolicy protègent en entrée (M21-E02, M22-E16). Ajoute une règle à chacune (source : pods de falcosidekick de l'espace `falco` ; vers Loki, uniquement `POST /loki/api/v1/push`) dans leurs dépôts, et reporte les deux flux dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.
4. MR, synchronisation. Vérifie : un pod `falco` prêt **par nœud** (six), la ligne de démarrage qui annonce le pilote et le nombre de règles chargées (`kubectl -n falco logs <pod> | head`), falcosidekick prêt, et la mémoire réellement consommée (`kubectl top pods -n falco`) comparée à ce que tu as réservé.

*B. Les détections*

5. Lis dans `falco_rules.yaml` (dans le pod : `/etc/falco/falco_rules.yaml`) les règles « Terminal shell in container » et « Read sensitive file untrusted » : condition, sortie, priorité, macros et listes utilisées. Prédis ce qui déclenchera chacune.
6. Crée le pod d'essai, ouvre un shell interactif dedans, et lis `/etc/shadow` :
   ```
   admin@adm01:~$ kubectl -n wb-essais run falco-essai --image=registry.par1.medisphere.internal/dockerhub/library/debian:13-slim --restart=Never -- sleep 3600
   admin@adm01:~$ kubectl -n wb-essais exec -it falco-essai -- bash
   root@falco-essai:/# cat /etc/shadow > /dev/null; exit
   ```
   Retrouve les deux événements : dans le journal du pod `falco` du **même nœud**, puis dans Grafana (organisation « Sécurité », source « Loki — audit », requête `{service="falco"}`), puis dans Alertmanager (laquelle des deux y arrive, et pourquoi ?).
7. Refais la lecture avec `kubectl exec falco-essai -- cat /etc/shadow` (sans `-it`) : quelles règles se déclenchent cette fois ? Puis supprime le pod.
8. Note dans `~/m26/e08/notes.md` : mémoire et CPU de Falco par nœud, nombre d'événements par heure sur un nœud travailleur au repos (requête LogQL), les deux événements avec leurs champs utiles (espace, pod, image, utilisateur, commande), et ce qu'il manque pour qu'une alerte réveille la bonne personne (sera traité en E19).

**Critères de réussite**
- [ ] L'Application `falco` est `Synced` et `Healthy` ; un pod `falco` prêt sur chacun des six nœuds, pilote `modern_ebpf`.
- [ ] Loki (locataire `audit`) contient, sur les sept derniers jours, les événements « Terminal shell in container » et « Read sensitive file untrusted » étiquetés `service="falco"`.
- [ ] falcosidekick a livré au moins une alerte à Alertmanager et des événements à Loki sans erreur (métriques `falcosecurity_falcosidekick_outputs_total`).
- [ ] L'espace `falco` porte l'annotation `medisphere.internal/exception-psa` ; le pod `falco-essai` n'existe plus.

**Vérification** : `lab/bin/check 26 08`

<details><summary>Indice 1</summary>

Alertmanager 0.27 a retiré son API v1 : falcosidekick envoie par défaut sur `/api/v1/alerts` et reçoit une erreur. Le champ à changer est dans `falcosidekick.config.alertmanager`. Le locataire de Loki se règle dans `falcosidekick.config.loki` ; un champ ajouté à tous les événements se déclare dans `falcosidekick.config.customfields` (`clé:valeur`).
</details>

<details><summary>Indice 2</summary>

« Terminal shell in container » exige un terminal (`proc.tty != 0`) : sans `-it`, pas d'alerte de ce type. « Read sensitive file untrusted » ne compte que les ouvertures **réussies** et exclut les shells eux-mêmes : c'est `cat` qui lit, pas `bash`. Un pod qui tourne en non-root ne pourrait pas ouvrir `/etc/shadow` : pas d'événement, ce qui est aussi une information.
</details>

<details><summary>Indice 3</summary>

Si les pods `falco` des nœuds de contrôle restent en attente, compare les *taints* des nœuds (`kubectl describe node k8s-cp01`) aux tolérances du DaemonSet rendu. Si un pod redémarre en boucle, lis la fin de son journal : un pilote qui ne se charge pas l'annonce clairement (noyau, BTF, droits).
</details>

**Pour aller plus loin** (facultatif) : rends le chart en local avec `driver.modernEbpf.leastPrivileged: true` (capacités au lieu de `privileged`) et compare le contexte de sécurité produit ; lis dans la documentation ce qu'il faut en plus avec AppArmor, et dis si l'espace `falco` pourrait alors quitter `privileged`. Regarde le tableau de bord de falcosidekick (`falcosidekick.webui`) sans l'installer : ce qu'il apporte face à Grafana. [Falco, pilotes](https://falco.org/docs/concepts/event-sources/kernel/) · [Règles par défaut](https://falco.org/docs/reference/rules/default-rules/) · [falcosidekick, sorties](https://github.com/falcosecurity/falcosidekick/tree/master/docs/outputs)

---

### M26-E09 — Questions : référentiels, contrôles et défense en profondeur  `Q` `★★`

> **Ticket SEC-2709** — *De : Sophie Laurent*
> Tu as mesuré le parc et le cluster, et posé trois dispositifs. Avant le palier 2, où l'on va **modifier** le socle, je veux être sûre que tu sais défendre nos choix devant l'auditeur, et lire un écart sans paniquer ni l'ignorer. Par écrit, avec ce que tu as observé.

**Objectifs pédagogiques**
- Expliquer les niveaux des référentiels et le choix d'un profil.
- Classer des contrôles et en voir les limites.
- Raisonner sur le coût d'une exception et d'un faux positif.

**Prérequis** : M26-E02 à M26-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 11 questions.

1. CIS distingue les niveaux 1 et 2, et « serveur » de « poste de travail ». Qu'est-ce qui sépare les niveaux ? Donne deux règles du niveau 2 qui gêneraient l'exploitation de MédiSphère, et dis pourquoi nos VMs sont des « serveurs ».

2. ANSSI-BP-028 a quatre niveaux (minimal, intermédiaire, renforcé, élevé). Comment sont-ils construits les uns par rapport aux autres ? Pourquoi « intermédiaire » pour le socle ? Quel composant du lab justifierait le niveau renforcé, et à quel prix ?

3. *(QCM)* Une règle OpenSCAP sort `notapplicable` sur toutes les VMs. Cela signifie :
   - A. que la règle est respectée
   - B. que la règle ne s'applique pas à ce système (plate-forme CPE ou condition d'applicabilité non remplie) : elle n'entre pas dans le score, et ne prouve rien
   - C. que la vérification a échoué pour une raison technique
   - D. que la règle a été désactivée par une exception

4. Sur `durci-deb`, le profil CIS donne un score de départ bas. Avant de le présenter à l'auditeur, quelles vérifications fais-tu sur le résultat lui-même (contenu utilisé, profil, règles `notchecked` ou en erreur) ?

5. kube-bench n'a pas de référentiel pour Kubernetes 1.36. Que fais-tu et qu'écris-tu, plutôt que de ne rien mesurer ou de prétendre être conforme au CIS 1.12 ?

6. *(QCM)* Classe ces dispositifs du palier : Pod Security en `enforce`, Kyverno en `[Audit, Warn]`, Falco, l'analyse OpenSCAP hebdomadaire à venir. Lequel est **préventif** ?
   - A. Kyverno en `[Audit, Warn]`
   - B. Falco
   - C. Pod Security en `enforce`
   - D. L'analyse OpenSCAP

7. Donne un exemple de **faux positif** rencontré dans ce palier (Lynis, OpenSCAP, kube-bench, Kyverno ou Falco), son coût s'il n'est pas traité, et la bonne façon de le traiter (et la mauvaise).

8. Une équipe demande une exception à `restricted` pour son espace « juste pour une semaine ». Qu'est-ce qu'une exception coûte vraiment (sécurité, suivi, audit) ? Quels champs doit contenir sa trace écrite ?

9. « Conformité n'est pas sécurité. » Donne une attaque réaliste contre MédiSphère qui réussirait sur un parc conforme à 100 % au CIS niveau 1, et le dispositif du module qui la verrait.

10. Pourquoi Kyverno et Pod Security plutôt que l'un des deux ? Et pourquoi garder la VAP `medisphere-images` du M14 alors que `registres-autorises` fait la même chose ?

11. Falco détecte, il ne bloque pas. Cite deux raisons de **ne pas** bloquer à l'exécution dès le premier jour, et la condition pour commencer à le faire (Tetragon, E29).

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 11 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) et calculé ton score sur 22.
- [ ] Pour chaque réponse fausse, tu as relu l'exercice du palier où tu l'as observé.

<details><summary>Indice 1</summary>

Pour chaque question sur un outil, reprends ton propre rapport : `referentiels.md`, `mesure-k8s-par1.md`, les rapports Kyverno, tes notes de Falco. Les réponses attendues s'appuient sur ce que tu as vu, pas sur la documentation seule.
</details>

<details><summary>Indice 2</summary>

Pour les exceptions, demande-toi ce que l'auditeur voudra voir dans six mois : qui a demandé, qui a accepté, jusqu'à quand, ce qui compense le risque, et la preuve qu'on l'a revue.
</details>

**Pour aller plus loin** (facultatif) : lis le chapitre « Principes » du guide BP-028 de l'ANSSI (une quinzaine de pages) et le *Kubernetes Hardening Guide* de la NSA/CISA ; repère trois recommandations que le module ne traitera pas, et dis pourquoi. [ANSSI BP-028](https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux)
