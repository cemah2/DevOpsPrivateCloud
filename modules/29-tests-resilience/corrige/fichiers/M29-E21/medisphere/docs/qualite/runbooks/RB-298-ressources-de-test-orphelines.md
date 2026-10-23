# RB-298 — Ressources de test orphelines (VMs de Terratest)

| | |
|---|---|
| Ticket d'origine | INC-5621 (M29-E21) |
| Déclencheurs | pipeline Terratest en échec « VM already exists » ou création refusée ; nettoyeur nocturne en échec (code 3) ; VMs `tt-*` visibles sur `pve01` ; budget mémoire du lab dépassé au démarrage |
| Périmètre | VMID **2290-2299**, pool `lab`, noms `tt-*`, étiquettes `env-m29` + `terratest`. **Rien d'autre** |

## 1. Inventaire (lecture)

```
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json \
    | jq -r '.[] | select(.vmid >= 2290 and .vmid <= 2299) | [.vmid, .name, .status, .pool, .tags] | @tsv'
root@pve01:~# qm config 2298 | grep -E '^(name|tags|meta|onboot|protection|lock)'
admin@adm01:~$ find /tmp -maxdepth 6 -name terraform.tfstate -path '*vm-debian*' -printf '%TY-%Tm-%Td %TH:%TM %p\n'
```

Puis : un pipeline Terratest tourne-t-il **en ce moment** (`plateforme/tofu-modules` → Pipelines) ? Si oui, on attend : ses VMs ne sont pas orphelines.

Une VM est orpheline si elle est dans la plage, dans le pool `lab`, nommée `tt-*`, créée il y a plus de 2 h (`ctime` de `meta`), et qu'aucun test ne tourne. **Ne te fie pas aux seules étiquettes** : un test qui ne les pose plus (régression du test) laisse des VMs `tt-*` sans `terratest` ; elles restent dans la plage et le pool.

## 2. Comprendre pourquoi (avant de nettoyer)

| Indice | Cause | Prévention |
|---|---|---|
| journal du job : `panic: test timed out after 10m0s` | délai par défaut de `go test` : panique, aucun `defer` exécuté | `-timeout` explicite (20 min) dans le job |
| job annulé, runner perdu, pod de job tué | SIGKILL : aucun `defer` | nettoyeur planifié |
| `protection: 1` sur la VM, erreur de destruction dans le journal | destruction refusée par Proxmox | `protection = false` forcé par le test |
| `defer terraform.Destroy` **après** `InitAndApply` | un échec d'application arrête le test avant l'enregistrement du `defer` | ordre : `defer` puis `InitAndApply` |
| VMs sans étiquette `terratest` | le test ne pose plus les étiquettes | variables obligatoires du test ; le nettoyeur le signale |
| `onboot: 1` sur une VM de test | elle démarrera au prochain démarrage de `pve01` et prendra 1 Go | le module ne doit jamais l'activer pour un test (`demarrage_auto = false`) |

## 3. Nettoyer

**De préférence par l'état** quand il est cohérent (il décrit les mêmes VMID et noms) :

```
admin@adm01:~$ cd /tmp/TestVmDebian<n>/vm-debian && tofu state list && tofu destroy
```

(les identifiants Proxmox du test doivent être dans l'environnement : mêmes variables que le pipeline ; si la copie du module est incomplète, `tofu destroy` échoue : passe au nettoyage VM par VM). Sinon, **VM par VM**, après avoir montré la VM :

```
root@pve01:~# qm config 2298 | grep -E '^(name|tags|meta)'          # c'est bien tt-…, env-m29, lab
root@pve01:~# qm set 2298 --protection 0
root@pve01:~# qm stop 2298 ; qm destroy 2298 --purge 1 --destroy-unreferenced-disks 1
admin@adm01:~$ rm -rf /tmp/TestVmDebian<n>                            # l'état orphelin, après
```

ou par le nettoyeur : pipeline manuel de `plateforme/tofu-modules` avec `NETTOYAGE=1` et `NETTOYAGE_APPLIQUER=1` (après lecture de la simulation).

> ⚠️ Jamais de `qm destroy` hors 2290-2299 ou hors pool `lab`. Jamais de nettoyage pendant un pipeline Terratest.

## 4. Vérifier

Plus aucune VM dans 2290-2299 ; plus d'état dans `/tmp` ; relance du pipeline Terratest : vert ; nettoyeur en simulation : « 0 orpheline ».

## 5. Prévention en place

- Test : nom et étiquettes obligatoires, `protection = false`, `defer terraform.Destroy` avant `InitAndApply` (M29-E21).
- Job : `go test -timeout 20m`, `timeout: 25m`, `resource_group: terratest`.
- Nettoyeur nocturne en simulation (`outils/nettoyer-terratest.sh`) : échoue s'il trouve une orpheline de plus de 2 h → courriel à la plateforme.
