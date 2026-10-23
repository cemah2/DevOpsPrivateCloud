---
chg: CHG-3403
titre: "Go ou no-go : Kubernetes 1.36 → 1.37 sur k8s-par1"
categorie: normal
statut: termine
decision: no-go
demandeur: Claire Morel
executant: équipe Plateforme
approbateurs: Claire Morel, Karim Benali
fenetre-debut: ""
fenetre-fin: ""
mesure-source: cluster
mesure-groupes: ""
mesure-debut: ""
mesure-fin: ""
mesure-objectif-s: 30
mesure-interruption-s: ""
---

# CHG-3403 — Go ou no-go : Kubernetes 1.36 → 1.37

## 1. Résumé

Faut-il monter `k8s-par1` de 1.36.5 à 1.37.x ce trimestre ? Décision prise le 29/10/2026 sur la [matrice de compatibilité](../matrices/compatibilite-kubernetes-1.37.md) : **no-go**. La montée de CHG-3404 est remplacée par ce qui est prêt : Cilium à sa dernière corrective et remplacement immuable d'un travailleur par une VM de la dernière image dorée.

## 2. Risque

| Risque | Probabilité | Gravité | Réduction | Signal |
|---|---|---|---|---|
| Monter en 1.37 avec Cilium 1.20 (non testé sur 1.37) | — | forte (réseau de tous les pods) | **ne pas le faire** | — |
| Rester en 1.36 | faible | faible | 1.36 maintenue jusqu'au 28/06/2027 | calendrier de fin de maintenance |
| Composant monté entre-temps qui n'accepte plus 1.36 | faible | moyenne | matrice relue à chaque CHG | notes de version |

## 3. Analyse

- Au relevé : Kubernetes 1.37.1 publiée le 15/09/2026 ; 1.36 maintenue jusqu'au 28/06/2027 : **aucune urgence** de sécurité ni de fin de maintenance.
- **Cilium 1.20** ne teste que 1.33 à 1.36 ; **1.21** (qui testera 1.34 à 1.37) n'est qu'en développement. Bloquant.
- **Argo CD 3.5** (testé 1.33-1.36) et **KEDA 2.21** (1.34-1.36) ne déclarent pas 1.37 ; Argo CD 3.6 est annoncée pour le 03/11/2026. Non bloquants seuls, mais à monter avant (CHG-3405).
- Plusieurs composants « à relever » (CNPG, ceph-csi, Kyverno, Capsule, kubelet-csr-approver) : à confirmer quand la décision sera revue.
- API : `apiserver_requested_deprecated_apis{removed_release="1.37"}` vide sur 7 jours ; rendus des dépôts valides contre les schémas actuels. Aucune API **dépréciée** retirée en 1.37 n'est utilisée (à refaire au moment de la montée).
- Changements de comportement de 1.37 qui toucheraient ce cluster : à lire dans le CHANGELOG 1.37 (*Urgent Upgrade Notes*, *Deprecation*, kubeadm) le jour de la révision ; non retenus ici puisque la décision est déjà no-go.

## 4. Décision

**No-go** pour 1.37, le 29/10/2026, par Claire Morel sur proposition de l'équipe Plateforme, relu par Karim Benali.

Ce qui se fait à la place (CHG-3404) :
1. Cilium à la **dernière corrective 1.20** (ordre « Cilium d'abord » préparé pour la suite : la 1.21 acceptera encore 1.36) ;
2. **remplacement immuable** de `k8s-w01` par une VM neuve de la dernière image dorée (système à jour sans mise à jour en place) ;
3. correctif de Kubernetes **1.36** s'il en sort un dans la fenêtre (changement standard, RB-142).

## 5. Conditions de révision

La décision est revue quand **toutes** ces conditions sont vraies :
- Cilium 1.21.x publiée en version stable, et passée en 1.21 sur `k8s-par1` en 1.36 (changement à part) ;
- Argo CD et KEDA en versions qui déclarent 1.37 (CHG-3405 ou suivant) ;
- les composants « à relever » relevés et tous **D** ou **—** ;
- métrique des API dépréciées vide sur 7 jours.

Revue planifiée : à la publication de Cilium 1.21.0 (suivi : liste `cilium-announce`, Renovate).

## 6. Retour arrière

Sans objet (aucune action sur le cluster). Le retour arrière d'une future montée de plan de contrôle reste la restauration d'etcd (RB-141) : à écrire dans la fiche de la montée.

## 7. Communication

Courriel à Julien Petit, Nadia Roussel, Inès Garnier, Sophie Laurent : « pas de 1.37 ce trimestre, la chaîne n'est pas prête ; aucune conséquence pour vous ; remplacement d'un travailleur le 10/11 (CHG-3404) ».

## 8. Clôture

Décision écrite et communiquée. Revue après mise en œuvre : `revue-trimestre.md`.
