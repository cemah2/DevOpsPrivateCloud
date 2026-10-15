# Équipe MédiDoc sur `k8s-par1`

| | |
|---|---|
| Ticket | DEV-1533 (accueil), enveloppe accordée par Claire Morel le <DATE> |
| Référent | `<prenom.nom>` (groupe `medisphere:medidoc-devs`), certificat de 7 jours renouvelé par `outils/kubeconfig-personnel.sh` |
| Espace | `medidoc-dev` — Pod Security `restricted` (enforce, warn, audit) ; politique d'images `medisphere-images` de M14-E18 (sélection par l'étiquette `medisphere.internal/equipe`) |
| Enveloppe | 2 vCPU / 4 Gio demandés, 4 vCPU / 8 Gio en limites, 20 pods, 0 LoadBalancer, 0 NodePort, 0 PVC (jusqu'au M16) ; défauts par conteneur 100m / 128Mi (demandes), 500m / 256Mi (limites) |
| Images | `registry.par1.medisphere.internal/medisphere/medidoc:<version>`, tirées par `robot$k8s-pull` (Secret `harbor-pull`, compte `default`) |
| Rôles | `medisphere-developpeur` et `medisphere-secrets-edition` (M14-E11), liés dans `medidoc-dev` seulement (`rbac/40-medidoc.yaml`) ; aucun droit hors de l'espace |
| Revue | <DATE + 6 mois> |

## Essais (le <DATE>)

| Essai | Attendu | Obtenu |
|---|---|---|
| `kubectl auth can-i create deployments -n medidoc-dev --as <REFERENT> --as-group medisphere:medidoc-devs` | yes | |
| `… get secrets -n medidoc-dev …` | yes | |
| `… update resourcequota/quota-equipe -n medidoc-dev …` | no | |
| `… create rolebindings -n medidoc-dev …` | no | |
| `… patch namespace/medidoc-dev …` | no | |
| `… get pods -n mediagenda-dev …` | no | |
| `… list nodes …` | no | |
| `… get namespace medidoc-dev …` | no (aucun droit hors de l'espace ; un refus Pod Security s'explique par le message d'erreur et la fiche) | |
| pod privilégié dans `medidoc-dev` | refusé (Pod Security) | |
| image `…:latest` | refusée (ValidatingAdmissionPolicy) | |
| pod de test MédiDoc | Running (`/healthz` 200 ; `/readyz` 503 tant que S3 n'est pas configuré) | |
