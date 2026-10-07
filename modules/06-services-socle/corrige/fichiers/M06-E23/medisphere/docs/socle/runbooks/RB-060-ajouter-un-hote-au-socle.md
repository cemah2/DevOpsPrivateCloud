# RB-060 — Ajouter (ou reconstruire) un hôte au socle

| | |
|---|---|
| **Propriétaire** | Équipe Plateforme |
| **Dernière revue** | `<DATE>` (MR `<N°>`, relue par Nadia Roussel et Karim Benali) |
| **Durée** | 45 min à 1 h 30 (hors écriture d'un rôle Ansible nouveau) |
| **Risque** | Faible pour l'existant ; **moyen** à l'étape 10 (pare-feu de `gw01`) |
| **Remplace** | La procédure « ajout d'un hôte permanent » des modules 00 à 05 : `host-record` dans dnsmasq, ligne dans `docs/socle/inventaire.md`, alias SSH ajouté à la main, empreinte SSH acceptée « à l'aveugle ». **Ne plus les faire.** |

## 1. Quand utiliser ce runbook

- **Oui** : nouvel hôte **permanent** du socle (VMID 1000-1099, PLAN.md §4.5), ou reconstruction à l'identique d'un hôte perdu (même nom, même adresse).
- **Non** : VM d'environnement d'un module (2000-2999 : `envs/<env>/` de `plateforme/infra`, sans étapes 7 à 12) ; VM jetable de la sandbox (5000-5999 : DHCP de Kea, rien à déclarer) ; hôte physique (`hp01`/`pbs01`) ; changement de rôle d'un hôte existant (MR sur NetBox et Ansible, pas une création).
- **Reconstruction** : sauter l'étape 1 (adresse déjà dans NetBox), ne **pas** supprimer l'ancien certificat SSH d'hôte à la main (il sera remplacé à l'étape 7), restaurer les données applicatives **après** l'étape 8 (runbook propre au service).

## 2. Prérequis

| Quoi | Où | Contrôle |
|---|---|---|
| Ligne de l'hôte dans PLAN.md §4.5 (VMID, VLAN, IP, rôle) | MR sur le dépôt du workbook / `plateforme/medisphere` | revue faite |
| Rôle Ansible du service, testé par Molecule | `plateforme/ansible`, `roles/<rôle>/`, `molecule/<rôle>/` | pipeline vert sur `main` |
| Étiquette de rôle `role-<rôle>` | NetBox (*Tags*) **et** liste des groupes attendus (`site.yml`, garde-fou d'inventaire) | `curl …/api/extras/tags/?slug=role-<rôle>` |
| Accès | `adm01` : `~/.config/workbook/` (`netbox-auto.token`, `netbox-tofu.env`, `powerdns-api.env`, `pve-tofu.env`, `s3-tofu.env`, `step-admin.pass`), agent SSH avec le certificat du jour | `ms-ssh-cert --statut` ; `medictl netbox whoami` → `svc-automatisation` |
| Fenêtre | Aucune pour les étapes 1-9 ; l'étape 10 (pare-feu) suit RB-040 | — |

## 3. Dépendances entre les étapes

```
NetBox (adresse) ──► OpenTofu : VM NetBox + IP ──► VM Proxmox ──► DNS (A, PTR)
                                                       │
            synchro Proxmox→NetBox (vmid) ◄────────────┤
                                                       ▼
                 inventaire Ansible (étiquettes NetBox) ──► certificat SSH d'hôte
                                                       ──► configuration (site.yml)
                                                       ──► certificat TLS (ACME : DNS + port 80)
            pare-feu gw01 (flux propres au service) ──► service joignable
                                                       ──► sauvegardes, supervision, documentation
```

Règles qui en découlent : l'adresse existe avant la VM ; le nom existe avant tout certificat ; l'inventaire voit l'hôte avant la configuration ; un flux est ouvert avant d'être testé.

## 4. Procédure

Variables d'exemple : `<HOTE>` = `dns02`, `<VMID>` = `1008`, `<IP>` = `10.10.20.16`, `<ROLE>` = `dns`.

### Étape 1 — L'adresse dans NetBox

Hôte du socle : l'adresse est **imposée** par le PLAN. Vérifie qu'elle est libre ou réservée pour cet hôte :
```
admin@adm01:~$ NB=https://nbx01.par1.medisphere.internal; T="Authorization: Bearer $(cat ~/.config/workbook/netbox-auto.token)"
admin@adm01:~$ curl -s -H "$T" "$NB/api/ipam/ip-addresses/?address=<IP>" | jq '.results[] | {address, status: .status.value, dns_name, assigned_object}'
```
**Attendu** : rien, ou une adresse `reserved` dont la description nomme `<HOTE>`. **Sinon** (adresse `active`, attribuée à autre chose) : **arrêt**, conflit d'adressage à trancher avec Claire Morel.

### Étape 2 — Déclarer l'hôte dans `plateforme/infra`

Dans `socle/`, un bloc `module "<HOTE>"` (source `vm-debian`, étiquette de version en cours) avec `vmid`, `vnet`, ressources, `etiquettes = ["socle", "role-<ROLE>"]`, `reseau_prefixe`, **`ipv4_imposee = "<IP>"`**, `ordre_demarrage`, et un bloc `module "dns_<HOTE>"` (source `enregistrement-dns`). Si une adresse `reserved` existe déjà (étape 1), supprime-la d'abord dans NetBox (le module crée la sienne) ou importe-la (`import {}`) : sinon `apply` échoue sur un doublon.
MR → pipeline : relis le **plan** dans la MR. **Attendu** : uniquement des créations (`+`) : `netbox_virtual_machine`, `netbox_interface`, `netbox_ip_address`, `netbox_primary_ip`, `proxmox_virtual_environment_vm`, deux `powerdns_record`. **Sinon** (une destruction `-` ou un remplacement `-/+` d'une autre ressource du socle) : **arrêt**, ne pas fusionner.

### Étape 3 — Appliquer

Fusion, puis job `apply` (manuel, protégé). **Attendu** : `Apply complete!`, sorties `vmid = <VMID>`, `ipv4 = "<IP>"`. **Sinon** : lire l'erreur ; une création partielle se reprend par un nouvel `apply` (OpenTofu sait ce qui existe) — jamais par une création manuelle dans Proxmox.

### Étape 4 — Contrôles immédiats

```
admin@adm01:~$ dig +short @10.10.20.10 <HOTE>.par1.medisphere.internal ; dig +short @10.10.20.10 -x <IP>
admin@adm01:~$ ping -c 2 <IP>
admin@adm01:~$ medictl vm show <VMID> | grep -E 'status|tags'
```
**Attendu** : `<IP>`, `<HOTE>.par1.medisphere.internal.`, réponses au ping, `running`, étiquettes `role-<ROLE>;socle`. **Sinon** : DNS absent → état du pipeline (module `enregistrement-dns`) et API PowerDNS ; pas de ping → `qm terminal <VMID>` (cloud-init : adresse, passerelle).

### Étape 5 — NetBox à jour

```
admin@adm01:~$ medictl netbox sync --dry-run
```
**Attendu** : la synchronisation complète le `vmid` de `<HOTE>` (ou l'a déjà fait, minuterie de 15 min) ; aucun écart signalé pour `<HOTE>`. **Sinon** : écart d'IP → l'adresse de cloud-init ne correspond pas à NetBox : corriger le code, pas NetBox.

### Étape 6 — Inventaire Ansible

```
admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/netbox-ansible.env; set +a
admin@adm01:~/src/ansible$ uv run ansible-inventory --host <HOTE> | jq '{ansible_host, vmid}'
admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_<ROLE>
admin@adm01:~/src/ansible$ outils/comparer-inventaires.sh
```
**Attendu** : `ansible_host = <IP>`, `<HOTE>` dans `socle` et `role_<ROLE>`, inventaires NetBox et Proxmox concordants. **Sinon** : étiquette manquante dans NetBox (ou statut ≠ `active`).

### Étape 7 — Identité SSH de l'hôte

Premier contact : la VM présente une clé d'hôte **non certifiée**. Ne l'accepte pas « à l'aveugle » : compare son empreinte à celle que la console affiche.
```
root@pve01:~# qm guest exec <VMID> -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub     # champ "out-data" de la réponse
admin@adm01:~$ ssh-keyscan -t ed25519 <IP> 2>/dev/null | ssh-keygen -lf -
```
Mêmes empreintes → applique `ssh_ca_hote` **depuis adm01** avec cette clé acceptée pour cette seule exécution :
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ssh-ca.yml --limit <HOTE> \
    -e ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/kh-<HOTE>'
admin@adm01:~$ ssh-keyscan -c -t ed25519 <IP> | ssh-keygen -L -f - | grep -A4 Principals ; rm /tmp/kh-<HOTE>
```
**Attendu** : certificat d'hôte avec `<HOTE>`, `<HOTE>.par1.medisphere.internal`, `<IP>`. Désormais la CI vérifie l'hôte par la CA. **Sinon** : empreintes différentes → **arrêt, incident sécurité** (Sophie Laurent).

### Étape 8 — Configuration

MR éventuelle sur `group_vars/role_<ROLE>/` et `host_vars/<HOTE>/` ; puis pipeline de `plateforme/ansible` : job `check-socle` (simulation) **limité** à `<HOTE>`, lecture du diff, puis job `appliquer`. **Attendu** : passage complet sans échec, second passage `changed=0`. **Sinon** : RB-040 (appliquer un changement), section « symptômes ».

### Étape 9 — Certificat TLS (si le service parle HTTPS ou NTS)

Dans `host_vars/<HOTE>/certificats.yml`, une entrée `certificats_acme` (id, noms, chemins, arrêt/reprise du port 80 si nécessaire, rechargement) ; pipeline. **Attendu** :
```
admin@adm01:~$ curl -sv https://<HOTE>.par1.medisphere.internal/ -o /dev/null 2>&1 | grep -E 'issuer|expire'
```
émetteur « MédiSphère Intermediate CA », expiration dans 30 jours au plus ; `ssh <HOTE> systemctl is-active 'cert-renewer@*.timer'`. **Sinon** : défi HTTP-01 refusé → port 80 de l'hôte et DNS (étape 4) ; journal de `ca01`.

### Étape 10 — Flux réseau

Si le service doit être joint depuis un autre VLAN (ou joindre l'extérieur autrement que par la règle générale) : MR sur `host_vars/gw01/pare_feu.yml` (une règle par flux, `motif`, `ref`), application selon RB-040 (accès de secours ouvert, filet anti-coupure). INFRA ↔ INFRA : rien à ouvrir. **Attendu** : le flux passe, et seulement lui (test depuis un autre VLAN refusé).

### Étape 11 — Sauvegardes et supervision

- VM : membre du pool `lab` → sauvegardée par la tâche `lab-nuit` de `pbs01` (vérifier le lendemain : `ms-verif-sauvegardes`).
- Données applicatives : sauvegarde propre au service (M06-E28) si l'hôte a un état (base, zone, baux, CA).
- Supervision : l'hôte apparaît dans `ms-verif-services` (M06-E29) par son rôle ; premier passage vert.

### Étape 12 — Documentation

PLAN.md §4.5 (si ce n'est pas déjà fait), `docs/socle/services.md` (rôle, dépendances), registre des secrets (nouveau secret éventuel), runbook propre au service. L'inventaire, lui, **est** NetBox : plus de tableau à tenir à la main.

## 5. Contrôle final

```
admin@adm01:~$ ssh -o ControlPath=none <HOTE> 'hostname -f; sudo sshd -T | grep -E "hostcertificate|trustedusercakeys"'
admin@adm01:~$ medictl netbox sync --dry-run && medictl dns sync --dry-run
```
Tout est vert, aucun écart pour `<HOTE>` : clôturer le changement avec l'heure de fin.

## 6. Retour arrière

Dans l'ordre **inverse** des étapes, en ne défaisant que ce qui a été fait :

| Étape atteinte | Retour arrière | Ce qui ne doit pas rester |
|---|---|---|
| 10 | Revert de la MR `pare_feu.yml`, pipeline (RB-040) | règle ouverte vers une adresse vide |
| 9 | Retirer l'entrée `certificats_acme` ; révoquer le certificat (`step ca revoke`, M06-E27) | certificat valide pour un nom qui n'existe plus |
| 7-8 | Rien sur l'hôte (il va disparaître) ; le certificat SSH d'hôte expire seul (30 j) — le révoquer si l'hôte est compromis | — |
| 2-3 | Revert de la MR `plateforme/infra`, pipeline : `tofu` détruit la VM, **puis** rend l'adresse et retire les enregistrements DNS | adresse `active` sans VM, A/PTR orphelins |
| 1 | Remettre l'adresse au statut `reserved` (hôte prévu) ou la supprimer | — |

Vérification du retour arrière : `dig` (NXDOMAIN), NetBox (aucune adresse `active` pour `<HOTE>`), `medictl netbox sync --dry-run` (aucun écart), `qm status <VMID>` (inexistant).

**Supprimer définitivement un hôte** : même tableau, après avoir sauvegardé ses données et retiré le module de `socle/` (le `prevent_destroy` des hôtes importés doit être levé par MR, explicitement).

## 7. Pièges connus

- **Adresse réservée à la main** puis imposée par le module : doublon dans NetBox, `apply` en échec. Étape 2.
- **Étiquette de rôle absente de NetBox** : `netbox_virtual_machine` échoue (étiquette inconnue) ou l'hôte n'entre pas dans `role_<ROLE>` : il est configuré à moitié (rôles communs seulement).
- **Hôte joint par adresse** sans adresse dans les principaux du certificat SSH : « Certificate invalid: name is not a listed principal ». Les principaux viennent de l'inventaire (étape 6 avant 7).
- **Défi ACME avant le DNS** : `ca01` ne résout pas le nom, le certificat n'est pas émis. Étape 4 avant 9.
- **Port 80 occupé** (nginx) pendant l'émission ACME : prévoir l'arrêt/reprise dans l'entrée `certificats_acme`.
- **Reconstruction** : la nouvelle VM a de nouvelles clés d'hôte ; un `known_hosts` qui garde l'ancienne clé brute de l'hôte refuse la connexion (« REMOTE HOST IDENTIFICATION HAS CHANGED ») : retirer la clé brute (`ssh-keygen -R <IP>`), la CA suffit.
- **Kea** : une adresse statique d'INFRA n'est jamais dans une plage DHCP ; une VM de SANDBOX en adresse fixe doit être hors de .100-.199.

## 8. Après l'opération

Consigner dans le ticket : heure de début et de fin, MR (infra, ansible, pare-feu), écarts rencontrés, corrections apportées à ce runbook (MR sur ce fichier).
