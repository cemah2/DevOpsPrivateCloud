<!-- docs/kubernetes/runbooks/RB-143-renouveler-les-certificats.md — EXTRAIT : §5 réécrit en M26-E25 (PLAT-2725). -->

## 5. Certificats de service des kubelets (demandes `kubernetes.io/kubelet-serving`)

**Depuis M26-E25, les demandes sont approuvées automatiquement** par `kubelet-csr-approver` (espace
`kubelet-csr-approver`, Application Argo CD du même nom, deux réplicas avec élection de chef). Il
n'approuve une demande que si : le demandeur est `system:node:<nom>` ; le nom DNS demandé (un seul) est
conforme à `^k8s-(cp|w)0[1-9]$` et commence par le nom du nœud ; toutes les adresses IP sont dans
10.10.40.0/24 ; le nom DNS se résout (PowerDNS) vers les adresses demandées ; la durée demandée est
d'un an au plus. Sinon il **refuse** (condition `Denied`, raison et message lisibles dans la CSR).

### Ce qu'on surveille
- Aucune demande `kubelet-serving` sans décision depuis plus de 15 minutes (`kubectl get csr`, check du
  workbook `lab/bin/check 26 25`) ; pods `kubelet-csr-approver` prêts (ServiceMonitor, cible `up`).
- Échéance du certificat servi par chaque kubelet (`outils/certificats-echeances.sh`, minuterie du lundi).
- Toute demande **refusée** : c'est soit un nœud mal nommé ou mal adressé (nouveau nœud hors du VLAN 40),
  soit une tentative d'usurpation. Lire la demande (`openssl req -noout -text`) et le journal d'audit
  (`impersonatedUser`, `user.username`) avant toute autre action.

### Si l'approbateur est arrêté ou refuse tout
1. `kubectl -n kubelet-csr-approver get pods,events` et journaux des deux pods (le chef seul agit) :
   image introuvable, élection de chef bloquée, DNS (« no such host » pour `k8s-w0N`), expression
   régulière modifiée.
2. En attendant la correction (par MR, jamais à la main : Argo CD la défait) : **approbation manuelle**
   après lecture, comme avant M26 :
   ```
   admin@adm01:~$ kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving
   admin@adm01:~$ kubectl get csr <CSR> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text | grep -A1 -E 'Subject:|Alternative'
   admin@adm01:~$ kubectl certificate approve <CSR>
   ```
   Une demande déjà **refusée** ne se réapprouve pas : le kubelet en crée une nouvelle (redémarrer le
   kubelet du nœud si besoin).
3. Désactiver l'approbateur (0 réplica) seulement s'il approuvait à tort ; dans ce cas, révoquer n'est
   pas possible (pas de liste de révocation pour ces certificats) : remplacer le certificat du nœud
   concerné (supprimer `kubelet-server-current.pem` et son lien, redémarrer le kubelet) et ouvrir un
   incident de sécurité (RB-262).
