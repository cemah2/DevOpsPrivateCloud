# Orchestration du provisioning (PLAT-1232)

> M11-E15. Outil : `plateforme/provisioning`, `outils/provisionner.py`, job manuel `provisionner` du pipeline (variable `EQUIPEMENT`). Runbook : RB-110.

## États et transitions

```
          (humain : NetBox)            (job « provisionner »)
 planned ─────────────────────► staged / pxe_action=installer
                                   │ rendu : script iPXE d'installation pour la MAC
                                   │ Proxmox : arrêt si allumée, démarrage
                                   │ attente : la VM s'éteint (fin d'installation)   ≤ 60 min
                                   ▼
                                staged / pxe_action=local
                                   │ rendu : script iPXE « exit » (disque local)
                                   │ Proxmox : démarrage ; attente SSH ≤ 10 min, DNS ≤ 2 min
                                   │ clé d'hôte lue par l'agent QEMU (hors réseau)
                                   │ Ansible : ca_lab, ssh_ca_hote, base (clé d'hôte signée)
                                   ▼
                                active / pxe_action=local ──► rendu : « exit » pour toujours
 toute étape en échec ─────────► failed (+ entrée « danger » au journal NetBox : étape, cause)
```

| Transition | Condition observable | Délai | En cas d'échec |
|---|---|---|---|
| planned → staged/installer | lancement du job | — | — |
| fin d'installation | état Proxmox `stopped` (preseed `exit/poweroff`, kickstart `poweroff`) | 60 min | console de la VM, RB-111 « Installateurs » |
| premier démarrage | port 22 ouvert sur l'IP primaire NetBox, nom résolu | 10 min + 2 min | console : réinstallation ? → rendu « local » non déployé |
| accueil | clé lue par l'agent = clé présentée par sshd ; playbook `accueil-bm.yml` | — | journal du job |
| mise en service | SSH avec certificat d'hôte reconnu | — | — |

## Pourquoi pas de « rappel » de la machine

Un installateur qui appelle une API avec un jeton laisse ce jeton dans le fichier de réponse et sur le disque installé. L'orchestrateur n'utilise que ce qu'il contrôle déjà : l'alimentation (API Proxmox), le réseau (port 22), le DNS, et l'agent QEMU pour la clé d'hôte. Sur un serveur physique : état d'alimentation par Redfish, clé d'hôte par la console série de l'iLO ou une attestation TPM.

## Reprise

- `failed` pendant l'installation : analyser (journal NetBox, console), corriger, relancer avec `--reprendre` : réinstallation complète.
- `failed` après l'installation (`pxe_action=local`) : `--reprendre` repart du premier démarrage, sans réinstaller.
- `active` : la relance ne fait rien (code 0) ; `active` injoignable : incident d'exploitation (code 1), jamais une réinstallation.

## Garde-fous

- Un équipement `active` est toujours rendu en « local » ; une MAC inconnue reçoit `exit` (boot.ipxe).
- VMID refusé hors 2112-2115 ; rôle NetBox `serveur-bm` exigé.
- Une installation à la fois (`resource_group`).
- Droits : `wb-provision@pve!provision` (rôle `WBProvision` : `VM.Audit`, `VM.PowerMgmt`, `VM.GuestAgent.FileRead` sur `/vms/2112`-`/vms/2115`) ; `svc-automatisation` : modification des équipements de rôle `serveur-bm` et création d'entrées de journal (contrainte `{"role__slug": "serveur-bm"}`).

## Limites connues

UEFI : après une installation Rocky, l'installateur crée sa propre entrée de démarrage et la place en tête de l'ordre UEFI (variables OVMF persistées dans `efidisk0`) : la machine ne repasse plus par le réseau. C'est sans danger (elle ne se réinstalle pas), mais une réinstallation exigera de remettre le réseau en tête (`efibootmgr` sur la machine, ou démarrage réseau forcé par le contrôleur).
