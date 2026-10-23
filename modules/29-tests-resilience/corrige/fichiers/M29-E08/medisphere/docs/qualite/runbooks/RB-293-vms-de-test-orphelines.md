# RB-293 — VMs de test orphelines (Terratest)

| | |
|---|---|
| Déclencheurs | Terratest échoue avec « aucun VMID libre entre 2290 et 2299 » ; une VM `tt-*` existe depuis plus d'une heure ; une adresse « Allouée par OpenTofu pour tt-… » reste dans NetBox |
| Durée | 15 min |
| Références | `plateforme/tofu-modules/vm-debian/test/`, identité `wb-terratest@pve!terratest`, module `vm-debian` v2 (NetBox) |

Une VM de Terratest est **jetable** : nom `tt-<6 caractères>`, VMID 2290-2299, sous-pool Proxmox **`lab/terratest`**, étiquettes `env-m29` et `terratest`, note « Terratest M29-E08 (<lancement>) ». Elle est détruite par le test lui-même (t.Cleanup), sauf si le processus du test est **tué** ou panique (délai de `go test` ou du job dépassé, runner redémarré, Ctrl-C deux fois) : plus rien ne la détruit. Son état local reste parfois dans le dossier temporaire du test (`/tmp/TestVmDebian*/` sur le poste ou sur `runner01`) ; s'il est cohérent, `tofu destroy` dans ce dossier (mêmes variables d'environnement) est le plus propre, sinon suis la procédure ci-dessous.

## 1. Inventaire

```
admin@adm01:~$ set -a; . ~/.config/workbook/pve-terratest.env; set +a
admin@adm01:~$ curl -fsS -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" "${PROXMOX_VE_ENDPOINT%/}/api2/json/cluster/resources?type=vm" \
    | jq -r '.data[] | select(.vmid >= 2290 and .vmid <= 2299) | "\(.vmid) \(.name) \(.status) \(.pool) \(.tags)"'
```

Pour chaque VM : la note (`qm config <VMID> | grep description` en root sur `pve01`) dit quel pipeline l'a créée. **Un test en cours** (pipeline encore actif, job `terratest:vm-debian` en cours) : ne touche à rien.

## 2. Supprimer, avec la même identité que le test

Uniquement des VMs **à la fois** dans 2290-2299, nommées `tt-*`, étiquetées `terratest` et rangées dans `lab/terratest` :

```
admin@adm01:~$ VMID=<VMID> NOEUD=pve01
admin@adm01:~$ curl -fsS -X POST -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" "${PROXMOX_VE_ENDPOINT%/}/api2/json/nodes/$NOEUD/qemu/$VMID/status/stop"
admin@adm01:~$ curl -fsS -X DELETE -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" "${PROXMOX_VE_ENDPOINT%/}/api2/json/nodes/$NOEUD/qemu/$VMID?purge=1&destroy-unreferenced-disks=1"
```

Le jeton `wb-terratest` ne peut rien supprimer d'autre : ses droits d'écriture portent sur le sous-pool `lab/terratest` seulement (une faute de frappe sur le VMID d'une VM du socle est refusée, HTTP 403). Une VM de la plage qui n'est **pas** dans ce sous-pool n'a pas été créée par Terratest : ne la supprime pas, cherche qui l'a créée.

## 3. NetBox

L'adresse et l'objet VM créés par `vm-debian` (statut actif, étiquettes `env-m29`, `terratest`) restent dans NetBox :

```
admin@adm01:~$ curl -fsS -H "Authorization: Bearer $(<~/.config/workbook/netbox-checks.token)" \
    "https://nbx01.par1.medisphere.internal/api/virtualization/virtual-machines/?tag=terratest" | jq -r '.results[] | "\(.id) \(.name)"'
```

Supprime l'objet VM (ses interfaces et adresses partent avec lui) avec le compte d'automatisation (`netbox-auto.token`), ou dans l'interface ; vérifie que l'adresse ne figure plus dans la plage SANDBOX.

## 4. Prévention

- Trois délais emboîtés : les attentes du test (SSH, cloud-init, agent) s'arrêtent à l'échéance de `go test` **moins 8 minutes** (`margeDestruction`), ce qui laisse à `t.Cleanup` le temps de détruire ; `go test -timeout 35m` ; job `timeout: 40m`. Quand `go test -timeout` expire, le binaire **panique sans exécuter `t.Cleanup` ni `defer`** : c'est l'échéance interne du test qui protège, pas celle de Go. Le délai du job, plus long, garde le journal et le message de Go.
- Le palier 4 (M29-E21) revient sur ce cas et sur son automatisation.
