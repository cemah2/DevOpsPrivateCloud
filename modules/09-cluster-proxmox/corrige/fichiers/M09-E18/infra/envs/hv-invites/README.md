# envs/hv-invites — VMs de recette sur le cluster hv-par1 (M09-E18)

| | |
|---|---|
| API | `https://hv.par1.medisphere.internal:8006/` : VIP keepalived 10.10.10.200 portée par un nœud sain (rôle Ansible `pve_cluster`) |
| TLS | certificat de chaque nœud signé par l'autorité du cluster, valable aussi pour le nom de la VIP ; autorité de confiance sur `adm01` et `runner01` (`pki/hv-par1-root-ca.crt` de `plateforme/ansible`, rôle `ca_lab`) |
| Jeton | `wb-tofu-hv@pve!tofu`, rôle `WBTofuHV` sur `/pool/recette` seulement (M09-E17) |
| État | `s3://tofu-state/envs/hv-invites/terraform.tfstate`, chiffré (`TF_ENCRYPTION`), verrou natif |
| VMs | clés de `var.vms`, VMID 130-139, pool `recette`, étiquettes `tofu` + `recette`, `ceph-vm`, `vinv99` |

Sur `adm01` :

```
admin@adm01:~/src/infra/envs/hv-invites$ . ../../outils/charger-acces.sh          # S3, TF_ENCRYPTION… et pve01
admin@adm01:~/src/infra/envs/hv-invites$ set -a; . ~/.config/workbook/pve-tofu-hv.env; set +a   # APRÈS : remplace pve01
admin@adm01:~/src/infra/envs/hv-invites$ echo "$PROXMOX_VE_ENDPOINT"            # https://hv.par1.medisphere.internal:8006/
admin@adm01:~/src/infra/envs/hv-invites$ tofu init && tofu plan
```

`charger-acces.sh` (M05-E27) charge `pve-tofu.env` (l'API de `pve01`) ; `pve-tofu-hv.env` redéfinit
ensuite `PROXMOX_VE_ENDPOINT` et `PROXMOX_VE_API_TOKEN`. L'ordre compte : vérifie toujours le point
d'accès affiché avant un `plan` (un jeton de `pve01` envoyé au cluster échoue en 401 ; l'inverse aussi).
L'application passe par le pipeline (`apply:hv-invites`, manuel, sur `main`).
