# RB-153 — Mettre à jour Cilium sur `k8s-par1`

| | |
|---|---|
| Déclencheurs | correctif 1.20.y publié (sécurité : sous 7 jours ; autre : mensuel) ; nouvelle mineure compatible avec la mineure de Kubernetes (trimestriel, ADR-0141) |
| Durée | 45 min (correctif) ; fenêtre annoncée d'une heure |
| Exercice | M15-E27 (CHG-1627) |
| Liens | RB-142 (montée de Kubernetes), RB-152 (BGP), ADR-0141 (cycle de vie des versions) |

## Règles

1. **Une seule version** pour l'agent, l'opérateur et Envoy : la CLI met tout à jour d'un coup ; jamais un composant seul.
2. Les *values* viennent du fichier du projet, seul : `cilium upgrade --reset-values` (la tâche le fait ; sans option, la CLI reprend les values de la release précédente) ; jamais `--reuse-values` entre deux versions du chart.
3. **Kubernetes ou Cilium d'abord ?** La version de Cilium doit être compatible avec la mineure de Kubernetes **avant et après** : on monte d'abord Cilium vers une version qui supporte les deux mineures, puis Kubernetes (RB-142). Jamais Kubernetes vers une mineure que la version installée de Cilium ne liste pas.
4. Mineure (1.20 → 1.21) : d'abord le dernier correctif de la 1.20, lire les *Upgrade Notes* de la 1.21 (CRD retirées, options renommées), `upgradeCompatibility` à la version initiale, vérification préalable obligatoire.

## Avant (J-1)

- Notes du correctif : correctifs, changements de comportement, matrice Kubernetes.
- `lab/bin/check 15 23` et `ms-verif-k8s-reseau` verts ; `cilium status --wait` vert.
- Redémarrage en douceur BGP actif (`kubectl get ciliumbgppeerconfig bordure -o yaml`), PDB de l'opérateur présent, `maxUnavailable: 1` sur `cilium` et `cilium-envoy`.
- MR : `CILIUM_VERSION` dans le Taskfile ; aperçu `task cilium:apercu` joint à la MR (aucune différence de *values* attendue pour un correctif).
- Fiche de changement : fenêtre, impact attendu (connexions HTTP en cours coupées sur un nœud à la fois au redémarrage d'Envoy), critères d'arrêt.

## Pendant

```
admin@adm01:~$ ~/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources/E25-sonde-http.sh https://mediagenda-recette.apps.par1.medisphere.internal
admin@adm01:~$ hubble observe --verdict DROPPED -f                                   # second terminal
admin@adm01:~/src/k8s$ task cilium:preflight                                          # images tirées partout, politiques valides
admin@adm01:~/src/k8s$ task cilium:appliquer
admin@adm01:~$ kubectl -n kube-system rollout status ds/cilium ; kubectl -n kube-system rollout status ds/cilium-envoy
admin@adm01:~$ cilium version ; cilium status --wait ; cilium bgp peers
admin@adm01:~$ cilium connectivity test --test-namespace wb-cilium-test                 # crée wb-cilium-test-1 (suffixe toujours ajouté)
admin@adm01:~$ cilium connectivity test --cleanup --test-namespace wb-cilium-test       # ménage, puis : kubectl get ns | grep cilium-test (vide)
```

**Critères d'arrêt** (retour arrière immédiat) : un agent en `CrashLoopBackOff` ; plus d'une interruption de la sonde de plus de 5 s ; des refus `Policy denied` nouveaux dans Hubble sur les espaces d'application ; une session BGP qui ne revient pas en 2 minutes.

## Retour arrière

```
admin@adm01:~$ helm -n kube-system history cilium
admin@adm01:~$ helm -n kube-system rollback cilium <RÉVISION-PRÉCÉDENTE> --wait
admin@adm01:~$ cilium status --wait
```

Puis **remettre le code en accord** : MR qui rétablit `CILIUM_VERSION` (sinon la prochaine `task appliquer` refait la mise à jour). Ce qui fait foi après un retour arrière : le dépôt, mis à jour dans l'heure.

## Après

- `lab/bin/check 15 27`, `ms-verif-k8s-reseau` verts ; ticket fermé avec les interruptions mesurées.

## Mesures (M15-E27, à remplacer par les tiennes)

| Étape | Durée | Interruptions vues par la sonde (200 ms) |
|---|---|---|
| Vérification préalable | ≈ 3 min (téléchargement des images par le cache Harbor) | aucune |
| Mise à jour (6 agents, 1 à la fois, puis 6 Envoy) | ≈ 8 min | 1 à 3 échecs isolés par redémarrage d'Envoy d'un travailleur (connexion en cours coupée) |
| Retour arrière (`helm rollback`) | ≈ 7 min | identique |

Sans redémarrage en douceur BGP, chaque redémarrage d'agent retirait le nœud de la bordure ≈ 1-3 s (une part des nouvelles connexions perdue) : mesuré en M15-E25.
