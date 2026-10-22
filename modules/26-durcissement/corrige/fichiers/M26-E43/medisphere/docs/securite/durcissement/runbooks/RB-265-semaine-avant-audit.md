# RB-265 — La semaine avant l'audit HDS

> Objectif : arriver à l'audit avec un parc mesuré et conforme, une admission qui refuse, une détection
> qui fonctionne, et des preuves. En période de gel, chaque changement passe par Git et est validé.

## Checklist (J-7 à J-1)

1. **Conformité** : `medisphere_conformite_score` ≥ cible (85 % CIS niveau 1 hors exceptions) sur tout le
   parc ; rapports récents dans `s3-01/conformite` ; alertes `ConformiteDegradee`/`ConformiteAnalyseAbsente`
   au vert. Chaque écart restant est au registre `exceptions.md` (daté, signé).
2. **Admission** : chaque politique de refus en `Deny` sur recette/prod, testée (`kyverno test`) ; PSA
   `restricted` partout sauf exceptions écrites ; aucune exemption de groupe ; une charge non conforme
   refusée (démonstration `--dry-run=server`).
3. **Détection** : Falco couvre tous les nœuds ; essai de la chaîne (shell + lecture de jeton) reçu en
   minutes ; Tetragon observe.
4. **Réseau / kubelets** : WireGuard cohérent, pare-feu d'hôte documenté (RB-264), aucune CSR de kubelet
   en attente.
5. **Réponse à incident** : RB-262 à jour, quarantaine posée, compartiment `preuves` prêt.
6. **Exceptions** : aucune périmée ; chacune a un valideur et une date de revue.

## Priorité en cas d'incident pendant le gel

1. Détection muette (Falco) et trou d'admission : **d'abord** (une attaque passerait inaperçue).
2. Blocages (déploiements, sudo, nœuds) : ensuite.
3. Dérive de conformité : réparer par le rôle `durcissement`.

## Ce qu'on ne touche pas

- Aucun contrôle désactivé (`setenforce 0`, webhook `Ignore`, politique rétrogradée en `Audit`).
- Aucune correction à la main sur un objet géré par Argo CD : MR, relecture, `revert` possible.
- Jamais `kube-system`, `kyverno`, `argocd`, `cilium` dans une politique de refus.

## Qui valide

Tout changement en gel est validé par Karim (plateforme) ou Sophie (sécurité), tracé par la MR.
