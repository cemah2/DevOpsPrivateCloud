# RB-293 — VMs de test orphelines (Terratest)

> Écrit en M29-E08 (PLAT-3008), complété en M29-E21 (INC-5621) : causes, nettoyeur planifié, cas des VMs sans étiquette ou protégées.

| | |
|---|---|
| Déclencheurs | Terratest échoue avec « aucun VMID libre entre 2290 et 2299 » ou « VM already exists » ; nettoyeur nocturne de `plateforme/tofu-modules` en échec (code 3) ; une VM `tt-*` existe depuis plus de 2 h ; une adresse « Allouée par OpenTofu pour tt-… » ou une VM étiquetée `terratest` reste dans NetBox ; budget mémoire du lab dépassé au démarrage de `pve01` |
| Périmètre | VMID **2290-2299**, sous-pool Proxmox **`lab/terratest`**, noms `tt-<6 caractères>`, étiquettes `env-m29` + `terratest`, note « Terratest M29-E08 (…) ». **Rien d'autre** |
| Durée | 15 min |
| Références | `plateforme/tofu-modules/vm-debian/test/` (M29-E08), `outils/nettoyer-terratest.sh` (M29-E21), identité `wb-terratest@pve!terratest`, module `vm-debian` v2 (adresse allouée par NetBox) |

Une VM de Terratest est **jetable** : le test la détruit lui-même (`t.Cleanup` enregistré avant `InitAndApply`), sauf si le processus du test est **tué** ou panique : délai de `go test` ou du job dépassé, job annulé, runner redémarré, Ctrl-C deux fois. Plus rien ne la détruit alors, et son adresse reste allouée dans NetBox. Son état local reste dans le dossier temporaire du test (`/tmp/TestVmDebian*/vm-debian/test/fixtures/vm/terraform.tfstate`, sur le poste ou sur `runner01`).

## 1. Inventaire (lecture)

```
admin@adm01:~$ set -a; . ~/.config/workbook/pve-terratest.env; set +a
admin@adm01:~$ curl -fsS -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" "${PROXMOX_VE_ENDPOINT%/}/api2/json/cluster/resources?type=vm" \
    | jq -r '.data[] | select(.vmid >= 2290 and .vmid <= 2299) | [.vmid, .name, .status, .pool, .tags] | @tsv'
root@pve01:~# qm config 2298 | grep -E '^(name|tags|meta|onboot|protection|lock|description)'
admin@adm01:~$ find /tmp -maxdepth 6 -name terraform.tfstate -path '*vm-debian*' -printf '%TY-%Tm-%Td %TH:%TM %p\n'
admin@adm01:~$ curl -fsS -H "Authorization: Bearer $(<~/.config/workbook/netbox-checks.token)" \
    "https://nbx01.par1.medisphere.internal/api/virtualization/virtual-machines/?tag=terratest" | jq -r '.results[] | "\(.id) \(.name)"'
```

Puis : un job `terratest:vm-debian` tourne-t-il **en ce moment** (`plateforme/tofu-modules` → Pipelines) ? Si oui, on attend : ses VMs ne sont pas orphelines. La note de la VM (`description`) dit quel pipeline l'a créée.

Une VM est orpheline si elle est **à la fois** dans la plage, dans le sous-pool `lab/terratest`, nommée `tt-*`, créée il y a plus de 2 h (`ctime` de `meta`), et qu'aucun test ne tourne. **Ne te fie pas aux seules étiquettes** : un test qui ne les pose plus (régression du test) laisse des VMs `tt-*` sans `terratest` ; elles restent dans la plage et le sous-pool. Une VM de la plage qui n'est **pas** dans `lab/terratest` n'a pas été créée par Terratest : ne la supprime pas, cherche qui l'a créée.

## 2. Comprendre pourquoi (avant de nettoyer)

| Indice | Cause | Prévention |
|---|---|---|
| journal du job : `panic: test timed out after …` | délai de `go test` dépassé : panique, ni `t.Cleanup` ni `defer` exécutés | échéance interne du test plus courte que `go test -timeout` (marge de destruction de 8 min, M29-E08) ; `-timeout` explicite |
| job annulé, `timeout` du job atteint, runner redémarré | processus tué (SIGKILL) : rien ne s'exécute | délais emboîtés (attentes < `go test -timeout 35m` < job `timeout: 40m`), `interruptible: false` ; nettoyeur planifié |
| `protection: 1` sur la VM, erreur de destruction dans le journal | destruction refusée par Proxmox | la fixture force `protection = false` |
| destruction enregistrée **après** `InitAndApply` | un échec d'application arrête le test avant l'enregistrement | `t.Cleanup(func() { terraform.Destroy(…) })` **avant** `InitAndApply` |
| VMs sans étiquette `terratest` | le test ne pose plus les étiquettes | étiquettes en dur dans la fixture ; le nettoyeur le signale |
| `onboot: 1` sur une VM de test | elle démarrera au prochain démarrage de `pve01` et prendra 1 Go | `demarrage_auto = false` dans la fixture |

## 3. Nettoyer

**De préférence par l'état** quand il est cohérent (il décrit les mêmes VMID et noms) et que la copie du module est complète :

```
admin@adm01:~$ set -a; . ~/.config/workbook/pve-terratest.env; . ~/.config/workbook/netbox-tofu.env; set +a
admin@adm01:~$ cd /tmp/TestVmDebian<n>/vm-debian/test/fixtures/vm && tofu state list && tofu destroy
```

`tofu destroy` rend aussi l'adresse dans NetBox. Si la copie est incomplète, `tofu destroy` échoue : passe au nettoyage VM par VM, **avec le jeton du test** (ses droits d'écriture portent sur `lab/terratest` seulement : une faute de frappe sur le VMID d'une VM du socle est refusée en HTTP 403) :

```
admin@adm01:~$ VMID=<VMID> NOEUD=pve01
admin@adm01:~$ API="${PROXMOX_VE_ENDPOINT%/}/api2/json/nodes/$NOEUD/qemu/$VMID"; H="Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN"
admin@adm01:~$ curl -fsS -H "$H" "$API/config" | jq -r '.data | .name, .tags, .description'   # c'est bien tt-…, terratest
admin@adm01:~$ curl -fsS -X PUT -H "$H" --data-urlencode protection=0 "$API/config"
admin@adm01:~$ curl -fsS -X POST -H "$H" "$API/status/stop"
admin@adm01:~$ curl -fsS -X DELETE -H "$H" "$API?purge=1&destroy-unreferenced-disks=1"
admin@adm01:~$ rm -rf /tmp/TestVmDebian<n>                                    # l'état orphelin, APRÈS
```

ou par le nettoyeur : pipeline manuel de `plateforme/tofu-modules` avec `NETTOYAGE=1` et `NETTOYAGE_APPLIQUER=1`, **après** lecture de sa simulation.

**NetBox** : si la VM a été détruite sans `tofu destroy`, l'objet VM et son adresse (statut actif, étiquettes `env-m29`, `terratest`) restent. Supprime l'objet VM (ses interfaces et adresses partent avec lui) avec le compte d'automatisation, ou dans l'interface ; vérifie que l'adresse ne figure plus dans la plage SANDBOX.

> ⚠️ Jamais de destruction hors 2290-2299 ou hors du sous-pool `lab/terratest`. Jamais de nettoyage pendant un job Terratest.

## 4. Vérifier

Plus aucune VM dans 2290-2299 ; plus d'état dans `/tmp` (poste et `runner01`) ; plus de VM `terratest` dans NetBox ; relance du job `terratest:vm-debian` : vert ; nettoyeur en simulation : « 0 orpheline(s) restante(s) » ; `lab/bin/check 29 08` et `29 21` verts.

## 5. Prévention en place

- Test (M29-E08, revu en E21) : nom `tt-<6>` et étiquettes en dur, sous-pool `lab/terratest`, `protection = false`, `demarrage_auto = false`, destruction enregistrée avant `InitAndApply`, échéance interne avec marge de destruction.
- Job : `go test -timeout 35m`, `timeout: 40m`, `resource_group: terratest`, `interruptible: false`.
- Nettoyeur nocturne en simulation (`outils/nettoyer-terratest.sh`, jeton `wb-terratest`) : échoue s'il trouve une orpheline de plus de 2 h → courriel du pipeline planifié à la plateforme.
