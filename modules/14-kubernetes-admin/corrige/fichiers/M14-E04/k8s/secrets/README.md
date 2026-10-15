# secrets/ — bris de glace du cluster k8s-par1 (M14-E04, SEC-1504)

Fichiers **chiffrés** par Ansible Vault, identité `critique` (le mot de passe est dans
`~/.config/workbook/ansible-vault-critique.pass` sur `adm01`, jamais ailleurs). Aucun fichier en
clair ici : `.gitignore` refuse `*.conf`, `*.key`, `*.kubeconfig`.

| Fichier | Contenu | Identité | Quand s'en servir |
|---|---|---|---|
| `admin.conf.vault` | `/etc/kubernetes/admin.conf` de `k8s-cp01` | `kubernetes-admin`, groupe `kubeadm:cluster-admins` (lié à `cluster-admin` par kubeadm) | Créer les premiers droits (E06), réparer quand plus aucune identité personnelle ne fonctionne |
| `super-admin.conf.vault` | `/etc/kubernetes/super-admin.conf` de `k8s-cp01`, **retiré du nœud** | `kubernetes-super-admin`, groupe `system:masters` (contourne toute autorisation, irrévocable sans changer la CA) | Seulement si le RBAC lui-même est cassé (liaison `kubeadm:cluster-admins` supprimée…) |

Utilisation, toujours depuis `~/src/ansible` (son `ansible.cfg` fournit l'identité `critique`), sans
fichier en clair sur le disque : le kubeconfig déchiffré va dans le dossier de session, en mémoire
(`$XDG_RUNTIME_DIR`, tmpfs propre à l'utilisateur), et il est effacé aussitôt après.

```
admin@adm01:~/src/ansible$ install -m 600 /dev/null "$XDG_RUNTIME_DIR/k8s-admin.conf"
admin@adm01:~/src/ansible$ uv run ansible-vault view ~/src/k8s/secrets/admin.conf.vault > "$XDG_RUNTIME_DIR/k8s-admin.conf"
admin@adm01:~/src/ansible$ export KUBECONFIG="$XDG_RUNTIME_DIR/k8s-admin.conf"
admin@adm01:~/src/ansible$ kubectl config rename-context kubernetes-admin@k8s-par1 k8s-par1   # nom attendu par le Taskfile
admin@adm01:~/src/ansible$ kubectl --context k8s-par1 get nodes
admin@adm01:~/src/ansible$ unset KUBECONFIG
admin@adm01:~/src/ansible$ rm -f "$XDG_RUNTIME_DIR/k8s-admin.conf"
```

Chaque usage est noté dans le journal de diagnostic (`docs/socle/journal/`) : qui, quand, pourquoi.
Les certificats de ces fichiers expirent au bout d'un an (`kubeadm certs check-expiration`) : après
un renouvellement (M14-E26) ou une montée de version (M14-E25), on rechiffre la nouvelle version.
