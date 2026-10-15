# ADR-0141 — Politique de cycle de vie des versions de Kubernetes

| | |
|---|---|
| **Statut** | Acceptée (<DATE>) |
| **Décideurs** | Claire Morel (responsable infrastructure), Karim Benali, Sophie Laurent (avis sécurité) |
| **Remplace** | — (les montées de version étaient décidées au cas par cas) |
| **Sources** (lues le 2026-10-08) | [Releases](https://kubernetes.io/releases/), [Release cycle](https://kubernetes.io/releases/release/), [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/), endoflife.date (Kubernetes), Cilium `requirements` (v1.20.2), cert-manager *supported releases*, ceph-csi README (v3.18.1), CloudNativePG *supported releases* (v1.30.1), Velero *compatibility*, CAPMOX README (v0.9.1) |

## Contexte

- Kubernetes publie une mineure environ tous les **quatre mois** et maintient les **trois** dernières, chacune environ **14 mois** (12 mois de support plus 2 mois de transition). Au 8 octobre 2026 : **1.37** (sortie le 26/08/2026, fin le 28/10/2027), **1.36** (fin le 28/06/2027), **1.35** (fin le 28/02/2027). La 1.34 sort de maintenance le 27/10/2026. La 1.38 est attendue vers décembre 2026.
- Politique de décalage : les kubelets peuvent avoir jusqu'à **trois** mineures de retard sur le serveur d'API ; kubectl une mineure d'avance ou de retard ; kubeadm ne monte que d'**une** mineure à la fois. Une mineure sautée ne se rattrape pas : deux montées à la suite.
- `k8s-par1` dépend de composants qui suivent Kubernetes avec retard :

| Composant | Version | Kubernetes annoncés |
|---|---|---|
| Cilium | 1.20 | 1.33 à 1.36 |
| cert-manager (M15) | 1.21 | 1.33 à 1.36 |
| ceph-csi (M16) | 3.18 | 1.34 à 1.36 (testés) |
| CloudNativePG (M16) | 1.30 | 1.34 à 1.36 (1.37 « testée, non supportée ») |
| Velero (M16) | 1.18 | testé jusqu'à 1.35 |
| Cluster API + CAPMOX (M18) | 1.12 / 0.9 | clusters ≤ 1.36 |
| metrics-server | 0.8 | toutes les mineures récentes |
| containerd.io | 2.3 LTS | 1.36 et 1.37 |

- Expérience de M14-E25 : la montée 1.35 → 1.36 a pris <2 h 30> sans interruption de MédiAgenda, avec un playbook rejouable ; les correctifs (1.36.x → 1.36.y) utilisent le même playbook.

## Options

1. **Suivre la dernière mineure dès sa sortie (N).** Fonctionnalités et correctifs au plus tôt, fenêtre de support maximale. Mais l'écosystème ne suit pas : aujourd'hui, la 1.37 casserait la promesse de support de Cilium, cert-manager, ceph-csi et CloudNativePG. Rejetée.
2. **Rester à N-1, monter quand l'écosystème suit.** Au plus une mineure de retard sur la dernière sortie ; on monte dès que la liste de contrôle d'écosystème est verte, au plus tard dans un délai fixé. Marge de support : environ 10 mois sur la mineure en service, ce qui laisse rater une fenêtre sans sortir du support.
3. **Monter seulement à l'approche de la fin de support.** Peu de montées en apparence, mais chaque montée devient un projet (plusieurs mineures de retard à rattraper une par une), et la sécurité dépend de la date. C'est la pratique d'InfoGér. Rejetée.
4. **Distribution qui gère les versions** (RKE2, Talos : ADR-0140). Ne supprime pas la contrainte d'écosystème. Hors du périmètre de cette ADR.

## Décision

Option 2 :

1. **Position cible : N-1.** `k8s-par1` tourne sur la mineure qui précède la dernière publiée, ou sur la dernière si la liste de contrôle d'écosystème est verte.
2. **Délai maximal** : une nouvelle mineure N+1 de notre position devient la cible **dans les 90 jours** suivant le jour où la liste de contrôle est verte, et **au plus tard 4 mois avant** la fin de maintenance de la mineure en service. Jamais de saut de mineure : si on est en retard de deux, deux montées dans la même fenêtre, à au moins une semaine d'écart.
3. **Correctifs** : le dernier correctif de la mineure en service est appliqué **dans le mois** de sa sortie ; **sous 72 h** pour une faille notée « High » ou « Critical » dans un composant que nous exposons (serveur d'API, kubelet, etcd, runtime).
4. **Liste de contrôle d'écosystème** (tenue par la Plateforme, relue à chaque sortie de mineure et chaque trimestre) : pour chaque composant du tableau ci-dessus, une version publiée qui **annonce** la mineure cible ; containerd compatible (`RELEASES.md`) ; notes de version lues (APIs retirées utilisées par nos manifestes : métrique `apiserver_requested_deprecated_apis` et journal d'audit) ; `kubeadm config validate` de `cluster/kubeadm-config.yaml`.
5. **Ordre** : chaque montée est jouée d'abord sur un cluster jetable (kind ou kubeadm sur `m15-essai`, M15/M18), puis sur `k8s-par1` selon RB-142.
6. **Renovate** (M13) ouvre les MR de version (paquets `pkgs.k8s.io`, images) ; rien n'est fusionné hors fenêtre.

## Conséquences

- Calendrier prévisionnel (sous condition de la liste de contrôle) :

| Date prévue | Montée | Condition | Bloquant aujourd'hui |
|---|---|---|---|
| janvier-février 2027 | 1.36 → **1.37** | Cilium 1.21 (ou 1.20.x qui annonce 1.37), cert-manager, ceph-csi, CloudNativePG, Velero annoncent 1.37 | tous les composants listés |
| juin 2027 au plus tard | 1.37 → **1.38** | idem pour 1.38 | — |
| au fil de l'eau | correctifs 1.36.x | — | — |

  Date butoir pour quitter la 1.36 : **28/02/2027** (4 mois avant sa fin de maintenance du 28/06/2027).
- Charge : 3 montées de mineure et une dizaine de correctifs par an, environ une demi-journée chacune avec le playbook.
- Les certificats feuilles étant renouvelés à chaque montée, la politique tient aussi lieu de renouvellement des certificats (RB-143).
- Cluster API/CAPMOX limite les clusters de charge de travail à 1.36 : à revoir au M18, ou CAPMOX suivra.

## Responsabilités et révision

Veille et liste de contrôle : la Plateforme (Karim) ; décision de fenêtre : Claire ; avis sécurité sur les délais de correctifs : Sophie. Révision : à chaque sortie de mineure et au moins une fois par an.
