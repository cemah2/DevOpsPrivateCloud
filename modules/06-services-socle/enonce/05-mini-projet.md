# Module 06 — Palier 5 : Mini-projet

Fin du bloc A. En six modules, le socle est passé de trois VMs montées à la main à une plateforme décrite par du code : une forge et sa CI, des outils testés, des images dorées, une configuration Ansible qui converge et détecte la dérive, une infrastructure déclarée dans OpenTofu avec un état partagé, et maintenant des services d'infrastructure de production. Il reste à **livrer** ces services comme un tout : chaque hôte du socle a une adresse attribuée par NetBox, un nom publié par PowerDNS, un certificat délivré par step-ca, une clé d'hôte signée, et tout cela sans geste manuel. Le bloc B (réseau de datacenter, Ceph, cluster Proxmox, OpenStack) partira de cet état : ses nœuds prendront leurs adresses dans NetBox, leurs noms dans PowerDNS, leurs certificats chez step-ca. Ce mini-projet est ce que Claire Morel présentera à la DSI et à l'auditeur HDS comme « socle MédiSphère v1 ».

---

### M06-E46 — Mini-projet : socle MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-790** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du socle v1 dans deux semaines. Je veux un socle qui passe le contrôle global sans un seul rouge, dans lequel **aucun service provisoire ne subsiste** (ni dnsmasq sur `dns01`, ni la CA bricolée), et qu'on sache étendre sans toi : Julien ajoutera lui-même un hôte au socle avec le runbook RB-060, de la source de vérité jusqu'au certificat, pendant la revue. Sophie relira la politique de certification, le registre des secrets et la matrice des flux ; Nadia testera la restauration d'un service socle avec ta procédure ; Karim fera la revue du code. Format habituel : 10 minutes de présentation, la démonstration de Julien, nos questions.

**Objectifs pédagogiques**
- Consolider les services socle du module (PKI, source de vérité, DNS, DHCP, temps, accès SSH) en un ensemble cohérent, piloté par le code et sans dette provisoire.
- Démontrer la chaîne d'automatisation complète « ajouter un hôte au socle » : NetBox → OpenTofu → DNS → Ansible → certificats TLS et SSH.
- Livrer l'état d'entrée du bloc B : documentation, flux, sauvegardes, supervision et étiquette de version.

**Prérequis** : M06-E01 à M06-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; les mini-projets des modules 01 à 05.
**Durée indicative** : 14 à 20 h, plus 30 min de revue.

**Contexte technique**
- Hôtes du socle v1 (PLAN.md §4.5) : `gw01` (1000), `adm01` (1001), `dns01` (1002, 10.10.20.10), `ca01` (1003, 10.10.20.11), `git01` (1004), `nbx01` (1005, 10.10.20.13), `s3-01` (1006), `runner01` (1007), `dns02` (1008, 10.10.20.16). Étiquettes Proxmox `socle` + `role-…` ; `ca01`, `nbx01` et `dns02` sont créées par OpenTofu (état `socle`) et configurées par les rôles Ansible du module.
- Services et leurs références : PKI step-ca (M06-E02, E03, E18-E20, E27, E33), NetBox (E04, E05, E10-E13), PowerDNS (E06-E08, E14, E15, E24, E26), Kea (E16, E17, E25), chrony avec NTS (E21), sauvegardes (E28), supervision (E29), durcissement et flux (E30), ADR-0060 (E31), RB-060 (E23).
- Documentation : `plateforme/medisphere` (clone `~/medisphere`, variable `WB_DEPOT`) ; matrice des flux **en code** dans `inventories/lab/host_vars/gw01/pare_feu.yml` de `plateforme/ansible`, reportée dans `docs/socle/matrice-flux.md`.
- Le contrôle global `lab/bin/check 06 46` vérifie les services du module, **revérifie les acquis des modules 01 à 05** (forge, runner, pipelines des projets `plateforme/*`, `medictl`, inventaire Proxmox, image dorée `current`, sauvegardes), vérifie l'**absence** de ce que le module a remplacé (dnsmasq sur `dns01`, CA provisoire sur tous les hôtes, rôle `dnsmasq` dans `site.yml`), puis la documentation et l'hygiène. Il prend quelques minutes.

**Travail demandé**
1. **Aucun service provisoire.** dnsmasq est désinstallé de `dns01` et son rôle retiré de `site.yml` (le relais DHCP de `gw01`, lui, reste) ; la CA provisoire est retirée de **tous** les magasins de confiance après bascule de tous les certificats (`git01`, `s3-01`, `nbx01`, `ca01`) ; plus aucun certificat en service n'est signé par elle. Les clés de la CA provisoire sont archivées chiffrées ou détruites, et ce choix est consigné.
2. **PKI.** Racine hors ligne (clé absente de `ca01`, archive chiffrée et procédure de cérémonie documentées), intermédiaire en ligne, ACME pour **tous** les services HTTPS du socle avec renouvellement automatique surveillé (30 jours au plus), CA SSH : clés d'hôte signées pour tous les hôtes, certificats d'utilisateur de 16 h au plus, `adm01` comme bastion. Politique de certification (`docs/socle/pki/politique-certification.md`) relue par Sophie.
3. **Source de vérité.** NetBox modélise tout le socle (sites, préfixes et plages de PLAN §4.2, VMs avec `vmid`, interfaces, IP primaires, étiquettes, statut) ; la synchronisation Proxmox → NetBox tourne régulièrement et sans erreur ; l'inventaire Ansible NetBox contient tout le socle ; OpenTofu alloue les adresses dans NetBox. L'ADR-0060 dit qui fait foi pour quoi, et le pipeline vérifie que les deux inventaires (Proxmox et NetBox) sont d'accord.
4. **DNS et DHCP.** PowerDNS primaire sur `dns01` et secondaire sur `dns02` (transferts signés TSIG, série identique), zone interne signée et validée sur les deux récurseurs, enregistrements des VMs pilotés par le code ; Kea en haute disponibilité (`dns01` primaire, `dns02` en attente) avec mise à jour dynamique du DNS ; clients du lab avec deux résolveurs.
5. **Temps et accès.** `gw01` authentifie ses sources Internet par NTS et sert le lab ; tous les hôtes sont synchronisés. Le compte `secours` et la clé de bris de glace existent, sont documentés, et leur usage est tracé.
6. **Exploitation.** Sauvegardes applicatives (base de NetBox, base de PowerDNS, baux et configuration de Kea, `/etc/step-ca` sans la clé racine) vers PBS dans `par1/<hôte>`, avec un test de restauration **réalisé pour cette livraison** et chronométré (ajouté en tête de `docs/socle/tests/restauration.md`) ; sondes `ms-verif-services` planifiées avec alerte, dont l'expiration des certificats à moins de 10 jours.
7. **Démonstration de la chaîne.** Préparer la démonstration de Julien : ajouter une VM d'essai (VMID de la plage 2060-2068) en ne touchant qu'au code et à NetBox, et obtenir sans geste manuel : adresse allouée, VM créée, nom et inverse publiés, configuration appliquée, certificat TLS par ACME, clé d'hôte signée (connexion SSH depuis `adm01` sans question sur l'empreinte). Puis la retirer proprement par le même chemin (NetBox, DNS, certificat révoqué ou laissé expirer — choix justifié).
8. **Documentation.** `docs/socle/services.md` (architecture des services socle, dépendances entre eux, ce qui se passe quand chacun tombe, procédures d'exploitation, liens vers les runbooks), RB-060 (ajouter un hôte au socle) testé par quelqu'un d'autre, runbooks issus du palier 4, ADR-0060, politique de certification, inventaire (exporté de NetBox) et matrice des flux à jour, registre des secrets complété (jetons NetBox, clé d'API PowerDNS, clés TSIG, provisioners et mots de passe de step-ca, clé de bris de glace SSH : emplacement, portée, propriétaire, échéance — jamais la valeur).
9. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, aucune panne `M06` n'est active, les VMs 2060-2069 sont détruites, et l'étiquette `socle-v1` est posée sur `plateforme/medisphere` (commit qui documente la livraison).
10. **La revue.** 10 minutes de présentation (ce qui a changé depuis le socle v0, dépendances et points uniques de défaillance restants, risques, ce que le bloc B consommera), puis la démonstration de Julien avec le seul RB-060.

**Contraintes**
- Aucune interruption de la résolution DNS du lab pendant les bascules finales (retrait de dnsmasq, bascule des certificats) au-delà d'un redémarrage de service annoncé.
- Aucun secret dans un dépôt, un journal de CI ou la documentation : des **emplacements**, jamais des valeurs. La clé de la racine ne réside sur aucune VM du lab.
- Tout ce qui est créé l'est par le code (OpenTofu, Ansible, scripts de synchronisation) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 06 46` est entièrement vert.
- [ ] La démonstration « ajouter un hôte au socle » se déroule de bout en bout avec RB-060, sans geste manuel hors du code et de NetBox, puis l'hôte est retiré proprement.
- [ ] Le test de restauration d'un service socle est chronométré et consigné, avec RTO et RPO.
- [ ] La documentation dit ce qui n'est **pas** encore redondant ou automatisé, et ce que le bloc B devra traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 06 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 06 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 06 XX`) donnent le détail par brique ; ceux des mini-projets précédents (`01 47`, `02 46`, `04 46`, `05 46`) aussi, en sachant que certains points ont légitimement changé avec ce module (dnsmasq, CA provisoire).
</details>

<details><summary>Indice 2</summary>

Fais la démonstration de l'étape 7 **avant** la recette, chronomètre-la, et note chaque endroit où tu as dû intervenir à la main : chacun est un défaut de RB-060 ou du code. Une démonstration qui marche une fois sur deux n'est pas une démonstration.
</details>

<details><summary>Indice 3</summary>

Pour retirer la CA provisoire sans casser quoi que ce soit : liste d'abord, sur chaque hôte et pour chaque client (navigateurs compris), qui lui fait encore confiance et qui présente encore un certificat signé par elle (`openssl s_client` sur chaque service, `grep` dans les magasins). On retire l'ancre en dernier, après une période de recouvrement mesurée.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord texte (préparé pour le module 21) qui affiche, pour chaque hôte du socle, l'écart entre NetBox, Proxmox et le DNS ; une MR de démonstration qui ajoute un hôte en une seule modification de NetBox, et le pipeline qui fait le reste.
