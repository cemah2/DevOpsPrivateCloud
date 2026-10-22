## Un cluster distant est Unknown ou en échec de connexion

> Section ajoutée à RB-200 après INC-4742 (M20-E42). Argo CD parle à un cluster distant avec ce
> que contient son Secret de cluster (adresse, jeton, autorité) et à travers tout le réseau entre
> les deux. Quatre étages, quatre messages.

1. **État vu par Argo CD** : `argocd cluster list` (colonne `STATUS`, message), `argocd cluster get
   <serveur>`, conditions de l'Application qui y déploie (`argocd app get <app>`).
2. **Classer par le message** :
   | Message | Étage | Preuve |
   |---|---|---|
   | `the server has asked for the client to provide credentials`, `Unauthorized` | jeton | jeton du Secret de cluster ≠ jeton du compte argocd-gestion sur le cluster (`kubectl get secret argocd-gestion-jeton -n agence` côté k3s) ; qui a modifié le Secret (`managedFields`, annotations) |
   | `x509: certificate signed by unknown authority` | autorité | `caData` du Secret ≠ CA de k3s (`/var/lib/rancher/k3s/server/tls/server-ca.crt`) |
   | `i/o timeout`, `connection refused`, `no route to host` | réseau | depuis un pod de k8s-par1 et depuis un nœud ; `nft list ruleset` sur lyo-k3s01 ; matrice de la bordure (VLAN 40 → 10.10.99.61:6443) |
   | `forbidden: User "system:serviceaccount:agence:argocd-gestion" cannot list …` | droits | `kubectl auth can-i --as=system:serviceaccount:agence:argocd-gestion …` sur k3s ; Role/RoleBinding attendus (playbook m20-lyo) |
3. **Corriger à la source, sans élargir** : jeton et autorité → `secrets-k8s.sh argocd` depuis le
   Vault ; réseau → la règle fautive retirée par le code qui gère la machine (rôle Ansible), pas à
   la main ; droits → le manifeste du playbook `m20-lyo.yml` réappliqué. Jamais `cluster-admin`
   « pour voir si ça passe », jamais `insecure: true`.
4. **Vérifier** : `argocd cluster list` → `Successful` ; Application de l'agence Synced et Healthy.
