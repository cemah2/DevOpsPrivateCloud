# ADR-0140 — Distribution et topologie de `k8s-par1`

| | |
|---|---|
| **Statut** | Acceptée (<DATE>) — à revoir après le module 18 (distributions) |
| **Décideurs** | Claire Morel, Karim Benali ; consultés : Sophie Laurent, Nadia Roussel |
| **Sources** | [Options for Highly Available topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/), [Creating HA clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/), documentations RKE2 et Talos, comptes rendus `docs/kubernetes/tests/` (M14-E24, E25, E29) |

## Contexte

- Exigences : HDS et ISO 27001 (traçabilité, chiffrement, maîtrise des accès), souveraineté (rien d'hébergé par un tiers, aucune dépendance à un service en ligne d'éditeur), compétence de l'équipe (trois personnes, apprentissage en cours), parc : un cluster de production aujourd'hui, deux ou trois demain (recette, PAR2).
- Contraintes du lab : 64 Go sur `pve01`, socle v3 ≈ 37 Go, `k8s-par1` ≈ 36 Go (3 × 4 + 3 × 8).
- Mesures du module : restauration complète d'etcd <38 min>, dont <9 min> d'API indisponible (E24) ; montée 1.35 → 1.36 <2 h 30>, zéro interruption de MédiAgenda (E25) ; perte brutale de `k8s-cp02` : <2> s d'échecs sur la VIP, aucun effet applicatif, remplacement complet du membre en <35 min> (E29) ; trois incidents évités ou résolus grâce à la connaissance du détail (exemples : l'image *pause* à aligner en E25, les fichiers d'audit et de chiffrement absents avant la jonction en E29, l'adresse annoncée par nœud en E27).

## Options

| Axe | Option | Avantages | Inconvénients | Risque principal |
|---|---|---|---|---|
| Distribution | **kubeadm** (actuel) | amont pur, aucune dépendance d'éditeur, chaque composant visible et compris ; outillage maison maîtrisé (playbook, runbooks) | tout est à notre charge : durcissement, audit, chiffrement, sauvegarde etcd, montée de version | erreur humaine dans une procédure manuelle |
| | RKE2 | profil CIS par défaut, etcd et instantanés intégrés, montée par changement de version | dépendance au cycle de SUSE, binaire unique moins transparent | rythme de l'éditeur, composants embarqués (Canal) à remplacer |
| | Talos | système immuable, API à la place de SSH, surface d'attaque minimale, montées atomiques | rupture d'outillage (Ansible inutile sur les nœuds), compétence nouvelle | diagnostic sans shell, dépendance à Sidero |
| | k3s | léger, simple | conçu pour l'embarqué et les agences, pas pour un cluster HDS central | — |
| | Distribution commerciale (OpenShift…) | support, intégration | coût, verrouillage, poids (mémoire du lab) | dépendance éditeur |
| etcd | **empilé** (actuel) | 3 VMs de moins, une seule PKI à gérer, procédures déjà écrites | la perte d'un nœud de contrôle retire un serveur d'API **et** un membre | deux nœuds perdus = restauration |
| | externe (3 VMs dédiées) | couplage réduit, etcd dimensionné à part | +3 VMs (≈ 6 Go), certificats, sauvegardes et montées en plus | complexité opérationnelle pour un gain faible à notre taille |
| Point d'accès | **keepalived + HAProxy sur les nœuds de contrôle** (actuel) | rôles du M07 réutilisés, bascule mesurée en secondes, aucune dépendance externe | VIP et HAProxy à maintenir sur trois nœuds | VRRP mal configuré (*split brain*) |
| | kube-vip (pod statique) | tout dans Kubernetes | amorçage par `super-admin.conf`, composant de plus dans le chemin critique | bogue de kube-vip = API injoignable |
| | `lb01`/`lb02` (DMZ) | répartiteurs déjà exploités | flux DMZ → VLAN 40 à ouvrir, dépendance croisée (les répartiteurs publieront aussi les applications du cluster) | panne d'un étage qui en coupe deux |
| Taille | **3 + 3** (actuel) | tolérance d'un nœud de contrôle et d'un travailleur | capacité limitée à ≈ 2 travailleurs pendant une maintenance | — |
| | 5 nœuds de contrôle | tolère deux pertes | +8 Go, écritures plus lentes, montées plus longues | infaisable dans le lab |
| | nœuds de contrôle qui portent des charges | moins de VMs | isolation affaiblie, éviction des charges en cas de pression | une charge qui affame etcd |

## Décision

**On garde kubeadm, etcd empilé, keepalived + HAProxy sur les nœuds de contrôle, 3 + 3** pour `k8s-par1`, parce que : (1) les mesures du module montrent que nous savons sauvegarder, restaurer, monter et réparer ce cluster dans des délais acceptables ; (2) aucune option ne supprime la contrainte d'écosystème ni l'exigence de comprendre les composants ; (3) le coût en mémoire d'un etcd externe ou de cinq nœuds de contrôle n'est pas justifié à notre taille. Les nœuds de contrôle ne portent **aucune** charge applicative (taint conservé).

## Conséquences

- `plateforme/k8s` et les rôles restent la référence ; l'effort porte sur l'automatisation de ce qui est encore manuel (restauration d'etcd par un playbook, rotation des clés de chiffrement).
- Au M18, mesurer RKE2 (profil CIS) et Talos sur les mêmes critères : installation, montée de version, sauvegarde et restauration d'etcd, durcissement par défaut, effort d'exploitation. **Remplacer cette ADR** si l'une des deux divise par deux le temps des opérations du M14 sans dépendance inacceptable.
- Un deuxième cluster (PAR2, recette) réutilise la même topologie et le même code.
