# Module 15 — Palier 5 : Mini-projet

Le module a construit, exploité, cassé et réparé le réseau de `k8s-par1`. Il reste à le **livrer** comme une brique de la plateforme : un réseau de cluster décrit par le code, qui donne à chaque environnement une adresse, un nom et un certificat sans ticket, qui ferme chaque espace par défaut, chiffre le trafic entre nœuds, s'annonce à la bordure et se publie hors du lab par les répartiteurs. La VM d'essai `m15-essai` disparaît, ingress-nginx n'existe nulle part sur `k8s-par1`, les pannes du palier 4 ont laissé des runbooks. Ce mini-projet est ce que Claire Morel présentera à la DSI et à l'auditeur HDS comme « réseau Kubernetes MédiSphère v1 », et ce que les modules suivants consomment : le stockage (M16) et le packaging (M17) publient leurs interfaces par la Gateway, GitOps (M20) reprendra les objets de `plateforme/k8s` tels quels, et la supervision (M21) branchera ses tableaux de bord sur les métriques que tu exposes déjà.

---

### M15-E46 — Mini-projet : réseau Kubernetes MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1646** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du réseau Kubernetes v1 dans deux semaines. Je veux un contrôle global sans un seul rouge, **sans rien de provisoire** (plus de `m15-essai`, plus d'objet d'essai oublié dans le cluster, plus de modification à chaud absente des dépôts), et une équipe de développement qui publie une application en HTTPS, avec un nom et un certificat, sans nous ouvrir de ticket.
> Pendant la revue : Karim fera la revue de `plateforme/k8s` et de la bordure dans `plateforme/ansible`, puis reconstruira la configuration réseau du cluster depuis le dépôt sur un cluster vide ; Sophie relira l'ADR-0150, la matrice des flux du cluster, les politiques de `mediagenda-*` et le registre des secrets ; Nadia arrêtera un travailleur **et** la passerelle de secours pendant ta présentation et regardera ce que dit la supervision ; Julien publiera une nouvelle route en direct et chronométrera le temps jusqu'au premier `200` en HTTPS. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le réseau du cluster en une brique cohérente, pilotée par le code, sans dette provisoire.
- Offrir aux équipes un chemin de publication en libre-service (route, nom, certificat, politique) borné par la sécurité.
- Livrer l'état `k8s-reseau-v1` : documentation, flux, supervision, étiquette de version.

**Prérequis** : M15-E01 à M15-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; mini-projet M14-E46 (`k8s-v1`).
**Durée indicative** : 12 à 18 h, plus 30 min de revue.

**Contexte technique**
- Cluster `k8s-par1` (PLAN.md §4.10) : `k8s-cp01-03` (10.10.40.51-53), `k8s-w01-03` (10.10.40.61-63), Kubernetes 1.36, Cilium 1.20 en remplacement de kube-proxy, tunnel VXLAN chiffré par WireGuard, Hubble (relay et UI).
- Entrée : pool `lb-par1` (10.10.41.10-10.10.41.199), BGP AS 65040 vers `gw01`/`gw02` (AS 65000), Gateway `gw-par1` (10.10.41.10, `*.apps.par1.medisphere.internal`, joker `apps-joker`), zone `apps.par1.medisphere.internal` sur `dns01` (signée, secondaire `dns02`), cert-manager (`step-ca-acme`), ExternalDNS (`k8s-par1`). Publication hors du lab : `lb01`/`lb02` (VIP 10.10.70.200) relaient les noms publiés vers 10.10.41.10:443 en passage TLS direct.
- Environnements : `mediagenda-dev`, `mediagenda-recette` (MédiAgenda publié en `mediagenda-recette.apps.par1.medisphere.internal`), `medidoc-dev` (M15-E34).
- Le contrôle global `lab/bin/check 15 46` rejoue les contrôles d'état de M15-E35 à M15-E42 (Service, DNS, politiques, BGP et LB IPAM, Gateway et TLS, certificats, noms, chemin entre nœuds), puis vérifie le remplacement de kube-proxy, le chiffrement, Hubble, les politiques des deux environnements de MédiAgenda, la publication par les répartiteurs, la documentation, les flux de la bordure, l'**absence** de `m15-essai` et d'ingress-nginx, et l'étiquette. Il prend quelques minutes.

**Travail demandé**
1. **Rien de provisoire.** `m15-essai` (2151) détruite par OpenTofu (état `m15-essai` vide, objets NetBox et DNS retirés) ; aucun objet d'essai des paliers précédents dans `k8s-par1` (Gateway `gw-essai`, routes et politiques de démonstration, Services jetables, certificats d'essai) sauf ceux justifiés dans la documentation ; aucune panne `M15` active ; les témoins `wb-pannes` gardés ou supprimés (choix écrit).
2. **Le cluster.** Cilium en remplacement de kube-proxy (kube-proxy absent, et `kubeadm` configuré pour ne pas le réinstaller), tunnel VXLAN chiffré par WireGuard, Hubble relay et UI ; CoreDNS par le dépôt (transfert vers `dns01`/`dns02`, bloc `medisphere.internal`). Tout est décrit dans `plateforme/k8s` et appliqué par `task` ; `kubectl diff` sur tous les composants ne montre **aucun** écart.
3. **L'entrée.** LB IPAM, BGP vers les deux passerelles (sessions établies depuis chaque nœud sélectionné, routes installées sur `gw01` **et** `gw02`, redémarrage gracieux réglé et justifié), Gateway `gw-par1` durcie (M15-E33 : TLS 1.2 au minimum, HSTS), joker délivré et renouvelable, ExternalDNS qui publie et nettoie ; publication externe par `lb01`/`lb02` pour les noms publiés.
4. **Les politiques.** Refus par défaut (M15-E17) dans `mediagenda-dev` et `mediagenda-recette`, autorisations au plus juste (DNS, Gateway → API, API → base et cache, règles L7, sortie `toFQDNs`), politique de base à l'échelle du cluster (M15-E28) ; Hubble UI publiée et restreinte (M15-E26/E33).
5. **Le libre-service.** Une page `docs/kubernetes/reseau/publier-une-application.md` pour les équipes : ce qu'elles écrivent (route, étiquette d'espace, politique d'entrée depuis la Gateway), ce qu'elles obtiennent sans ticket (nom, certificat, adresse), ce qui exige un ticket (nouveau domaine, passage TLS direct, exposition hors du lab), et un exemple complet vérifié sur `medidoc-dev`.
6. **Exploitation.** `ms-verif-k8s-reseau` (M15-E26) planifié et vert, avec au minimum : sessions BGP par passerelle, routes 10.10.41.0/24 sur les deux passerelles, conditions des Gateway et des routes, expirations des certificats, cohérence routes ⇔ noms publiés, `cilium-health` ; runbooks RB-150 à RB-153 publiés dans `docs/kubernetes/reseau/runbooks/` et à jour des pannes du palier 4.
7. **Bordure et flux.** Voisins et politiques BGP de la bordure par Ansible (configuration courante de FRR identique au fichier généré sur les deux passerelles) ; tous les flux du module dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md` (BGP 179 des nœuds vers les passerelles, M07 ; VLAN 40 → autoritaire de `dns01` TCP/UDP 5300 pour RFC 2136, à la bordure et dans le pare-feu local de `dns01`, E14 ; `ca01` → 10.10.41.10 TCP 80 pour HTTP-01, E13 ; `lb01`/`lb02` → 10.10.41.10 TCP 443, E20) ; matrice des flux du cluster (`docs/kubernetes/reseau/matrice-flux-cluster.md`, M15-E32) à jour.
8. **Documentation.** `docs/kubernetes/reseau/` : `architecture.md` (schéma du chemin d'une requête, composants et versions, ce qui se passe quand un nœud, une passerelle, l'agent Cilium d'un nœud, CoreDNS, cert-manager, ExternalDNS, `ca01` ou `dns01` tombent), ADR-0150 (M15-E30), matrice des flux du cluster, runbooks, analyses (M15-E29, M15-E44), page de libre-service ; registre des secrets complété (clés TSIG `externaldns-k8s` et `certmanager-k8s`, compte ACME : emplacements, jamais les valeurs).
9. **Livraison.** Tout est fusionné, les pipelines de `main` (`plateforme/k8s`, `plateforme/ansible`, `plateforme/infra`, `plateforme/medisphere`) sont verts, et l'étiquette **`k8s-reseau-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (le chemin d'une requête de bout en bout, les choix et leurs compromis, ce qui n'est **pas** redondant : un seul hyperviseur, un seul site, une seule autorité de certification, un seul autoritaire primaire pour les mises à jour), puis les démonstrations de Nadia (un travailleur arrêté, la passerelle de secours arrêtée) et de Julien (nouvelle route en direct).

**Contraintes**
- Aucun secret dans un dépôt, un journal de CI ou la documentation : des **emplacements**, jamais des valeurs (Ansible Vault `lab`, Secrets Kubernetes créés depuis le Vault ; Vault/OpenBao arrive au M25).
- Tout ce qui est créé l'est par le code (`plateforme/k8s`, rôles Ansible, OpenTofu) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucune politique n'est élargie pour « faire passer » une démonstration ; aucune bascule de la VIP de la bordure hors de la démonstration prévue de Nadia (et seulement par l'arrêt de la passerelle de **secours**).
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 15 46` est entièrement vert.
- [ ] Démonstration de Nadia : un travailleur arrêté puis la passerelle de secours arrêtée (l'un après l'autre) ; MédiAgenda recette reste joignable (pertes mesurées et commentées), la supervision signale chaque perte, le retour ramène l'état nominal sans intervention.
- [ ] Démonstration de Julien : une nouvelle route dans `medidoc-dev`, publiée en HTTPS valide en moins de 5 minutes, sans action de l'équipe Plateforme.
- [ ] La documentation dit ce qui n'est **pas** redondant et ce que M16, M17, M20, M21 et M25 devront traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 15 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 15 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 15 XX`) donnent le détail par brique, et `lab/bin/check 14 46` revérifie le cluster lui-même.
</details>

<details><summary>Indice 2</summary>

Pour « aucun écart avec le dépôt », compare systématiquement chaque dossier de `composants/` à l'état du cluster, et les valeurs appliquées de chaque release Helm à leur fichier de *values* : c'est là que se cachent les corrections à chaud oubliées pendant le palier 4. Côté bordure, compare la configuration courante de FRR au fichier généré, sur chaque passerelle (ta tâche de dérive de M15-E23, si tu l'étends à la bordure, le fera pour toi).
</details>

<details><summary>Indice 3</summary>

Répète les démonstrations **avant** la revue et mesure : combien de requêtes perdues quand un travailleur s'arrête (sessions BGP, temps de maintien, redémarrage gracieux), et quand la passerelle de secours s'arrête (rien ne doit se passer : pourquoi ?). Un chiffre mesuré vaut mieux qu'une promesse.
</details>

**Pour aller plus loin** (facultatif) : un essai de reconstruction de la configuration réseau du cluster sur un cluster jetable (kind ou `m15-essai` recréée le temps de l'essai, puis détruite), chronométré, depuis le seul dépôt ; un tableau de bord texte (préparé pour M21) des métriques Hubble par espace (`hubble_flows_processed_total`, `hubble_drop_total`).
