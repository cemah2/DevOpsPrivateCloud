# Module 28 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M28-E25 — Mini-projet : la plateforme développeurs de MédiSphère v1

**Solution** (une démarche possible ; un `LIBRE` admet d'autres chemins si l'état livré est atteint)

1. **Point de départ** : `lab/bin/check 28 25` ; chaque rouge devient une ligne de ta liste.
2. **Rien de provisoire** :
   ```
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ | grep M28 || echo "aucune panne ouverte"
   admin@adm01:~$ kubectl get ns | grep -E 'vc-essai|essai-isolation|chemin-balise' || echo "propre"
   admin@adm01:~$ kubectl get ciliumnetworkpolicies -A -l medisphere.internal/auteur=lucas.martin
   ```
   Compte `essai-medidoc` en `etat: disabled` (MR `plateforme/identite`), compte `campagne-recette` conservé seulement si les essais de charge en ont encore besoin (décision écrite ; sinon retiré de la topologie et d'OpenBao).
3. **Autoscaling** : `kubectl get hpa,scaledobjects,vpa -A` contre le tableau de [`autoscaling.md`](fichiers/M28-E13/medisphere/docs/plateforme-dev/autoscaling.md) ; aucune ligne hors `Off` pour les VPA.
4. **Locataires** : `argocd app diff locataires capsule politiques` vide ; essais d'isolation rejoués (trois au moins) avec `essai-medidoc` réactivé le temps de l'essai.
5. **Portail** : montée de version du mois faite (E16), sauvegarde récente, catalogue : `GET /api/catalog/entities?filter=kind=component` → chaque entité a un `spec.owner` qui résout vers un `Group` et l'annotation `backstage.io/techdocs-ref`.
6. **Chemin balisé** : [`chemin-balise-essai.md`](fichiers/M28-E25/medisphere/docs/plateforme-dev/chemin-balise-essai.md) — création, mesure, retrait dans l'ordre inverse (Application, espace, entités, projets, dépôt Harbor).
7. **Note de livraison** : [`etat-plateforme-dev-v1.md`](fichiers/M28-E25/medisphere/docs/plateforme-dev/etat-plateforme-dev-v1.md).
8. **Étiquette** :
   ```
   admin@adm01:~/medisphere$ git tag -a plateforme-dev-v1 -m "Plateforme développeurs v1 (M28-E25, PLAT-2925)" && git push origin plateforme-dev-v1
   ```

**Explications** : la revue éprouve les quatre promesses du module — le libre-service fonctionne (Julien), l'autoscaling réagit (Nadia), l'isolation tient (Sophie), l'équité est explicable (Karim). Le contrôle global ne peut pas tout voir (la démonstration de Sophie, par exemple) : c'est la répétition chronométrée qui garantit le reste.

**Démonstration de Karim (attendu)** : une création de pod qui dépasse le budget est refusée **à l'admission**, par le contrôleur qui crée le pod (ReplicaSet) ; le message (`exceeded quota`) est dans les événements du ReplicaSet, pas dans le pod (qui n'existe pas) ; l'objet qui porte le budget est le `GlobalResourceQuota` généré par le Tenant (`kubectl get globalresourcequotas`), ou le `ResourceQuota` de l'espace si c'est lui qui est plein.

**Alternatives** : livrer le portail plus tard et le reste maintenant (étiquette `plateforme-dev-v1` sans portail) : défendable si le portail n'est pas prêt, à écrire dans la note de livraison ; mais la promesse « libre-service » tombe.

**Pièges classiques**
- Retirer le service fictif en supprimant d'abord les projets GitLab : l'Application Argo CD échoue (dépôt introuvable) et l'espace reste orphelin.
- Oublier l'entité du catalogue : elle réapparaît tant que son emplacement est enregistré.
- Réactiver `essai-medidoc` pour la revue et l'oublier ensuite.
- Poser l'étiquette avant que le contrôle global soit vert.

**En production chez MédiSphère** : la note de livraison est relue par Claire Morel ; les actions restantes deviennent des tickets `PLAT-` datés ; la revue d'accès trimestrielle couvre les propriétaires des locataires et les droits de `svc-portail`.
