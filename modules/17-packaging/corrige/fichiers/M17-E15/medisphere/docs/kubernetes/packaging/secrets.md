# Registre des secrets consommés sur `k8s-par1`

*M17-E15 — ticket SEC-1833. Des emplacements, jamais des valeurs. Mis à jour à chaque nouveau Secret (MR).*

Règle : **aucun secret dans un chart, un overlay, un fichier de valeurs ni une release Helm**. Un paquet référence un Secret existant (`existingSecret`, `secretKeyRef`). Le pipeline de `mediagenda/chart` refuse tout rendu qui contient un objet `Secret` (job `sans-secret`). `plateforme/k8s/outils/audit-valeurs-helm.sh` vérifie les valeurs de toutes les releases.

| Espace | Secret | Créé par | Source de vérité | Consommé par | Rotation |
|---|---|---|---|---|---|
| `mediagenda-recette` | `mediagenda-db-app` (clé `uri`) | CloudNativePG (cluster `mediagenda-db`, M16-E18) | opérateur (rôle PostgreSQL `mediagenda`) | API et migrations (`MEDIAGENDA_DB_URL`) | nouveau mot de passe du rôle par l'opérateur (`kubectl cnpg` ou modification du Secret géré), redémarrage progressif de l'API |
| `mediagenda-dev`, `mediagenda-prod` | `mediagenda-db-app` | CloudNativePG (component `dependances`) | opérateur | idem | idem |
| `mediagenda-*` | `harbor-pull` | script `plateforme/k8s/outils/secret-tirage.sh` (M14-E19) | Vault Ansible `lab` (`robot$k8s-pull`) | kubelet (`imagePullSecrets`) | nouveau jeton du robot dans Harbor, Vault, puis script ; anciens pods inchangés |
| `external-dns` | `externaldns-tsig` | script du M15 depuis Vault Ansible `lab` | Vault Ansible `lab` (clé TSIG `externaldns-k8s`) | ExternalDNS (`--rfc2136-tsig-secret` par l'environnement) | nouvelle clé sur `dns01` (rôle `powerdns_auth`), Vault, script, redémarrage d'ExternalDNS |
| `cert-manager` | `certmanager-tsig` | script du M15 | Vault Ansible `lab` (clé `certmanager-k8s`) | ClusterIssuer `step-ca-acme` (DNS-01) | comme ci-dessus |
| `cert-manager` | compte ACME de `step-ca-acme` (`privateKeySecretRef`) | cert-manager | cert-manager | cert-manager | sans objet (nouveau compte si supprimé) |
| `ceph-csi` | identités `client.k8s` (RBD, CephFS) | script du M16 | Vault Ansible `critique` (trousseaux Ceph) | pilotes ceph-csi | `ceph auth` (rotation de clé), Vault, script, redémarrage des pilotes |
| `velero` | `velero-s3` | script du M16 (`~/.config/workbook/s3-velero.env`) | Vault Ansible `lab` (compte SeaweedFS `velero`) | Velero, node-agent (`credentials.existingSecret`) | nouvelle clé SeaweedFS, Vault, script, redémarrage |
| `cnpg-system`, `mediagenda-*` | identifiants S3 de l'`ObjectStore` `cnpg-s3` | script du M16 | Vault Ansible `lab` (compte `cnpg`) | plugin Barman Cloud | idem |
| `wb-system` | jeton de `wb-checks` | M14-E06 (Secret `kubernetes.io/service-account-token`) | Kubernetes | checks du workbook (`~/.config/workbook/k8s-checks.kubeconfig`) | suppression puis recréation du Secret, nouveau kubeconfig |
| tous | Secrets de release `sh.helm.release.v1.*` | Helm | Helm | Helm | **ne doivent contenir aucun secret** ; `historyMax: 10` |

Accès en lecture aux Secrets : groupe `medisphere:plateforme-admins` et comptes de service des opérateurs. Les équipes applicatives (`medisphere:mediagenda-devs`) n'ont **pas** `get secrets` en recette ni en prod.

## Ce qui change au M25

- **Vault** (OpenBao, `vault01-03`) devient la source de vérité. Vault Ansible ne garde que l'amorçage.
- **External Secrets Operator** crée les Secrets Kubernetes depuis Vault, à la place des scripts : un `ExternalSecret` par ligne de ce tableau, versionné dans `plateforme/k8s`, sans valeur.
- **SOPS + age** pour les rares fichiers qui doivent vivre chiffrés dans un dépôt (amorçage).
- Les identifiants PostgreSQL de MédiAgenda peuvent passer au moteur *database* de Vault (comptes dynamiques).
