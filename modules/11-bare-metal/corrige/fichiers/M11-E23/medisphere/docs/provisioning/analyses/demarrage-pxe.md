# Un démarrage PXE paquet par paquet (PLAT-1240)

> Modèle de compte rendu (M11-E23). Les valeurs entre `<…>` sont celles de **ta** capture. Captures prises sur `pve01` (`tap2112i0`, `tap2114i0`) et `dns01` (`ens18`), puis supprimées des hôtes.

## Démarrage BIOS (`bm01`, SeaBIOS, ROM iPXE de QEMU)

| t (s) | De → vers | Protocole | Contenu significatif |
|---|---|---|---|
| 0,00 | 0.0.0.0:68 → 255.255.255.255:67 | DHCP DISCOVER | option 53=1, **option 93 = 0x0000** (BIOS x86), option 60 `PXEClient:Arch:00000:UNDI:002001`, option 97 (UUID) |
| <…> | 10.10.60.1 (relais) → 10.10.20.10:67 | DHCP relayé | même message, **`giaddr` = 10.10.60.<2 ou 1>**, source UDP 67 (vu sur `ens18` de `dns01`) |
| <…> | 10.10.20.10 → relais → client | DHCP OFFER | `yiaddr` 10.10.60.1xx (réservation), **`siaddr` = 10.10.60.10**, **`file` = `undionly.kpxe`**, option 54 (identifiant du serveur) |
| <…> | client ↔ Kea | REQUEST / ACK | — |
| <…> | client → 10.10.60.10:69 | TFTP RRQ `undionly.kpxe` | options `tsize 0`, `blksize 1432` (ou 1468) |
| <…> | 10.10.60.10:<éphémère> → client | TFTP OACK | `tsize <octets>`, `blksize <n>` ; puis DATA/ACK numérotés |
| <…> | client | DHCP DISCOVER (2e) | **option 77 (user-class) = `iPXE`**, option 175 (options iPXE) |
| <…> | Kea → client | OFFER | `file` = `https://pxe01.par1.medisphere.internal/boot.ipxe` (classe iPXE) |
| <…> | client → 10.10.20.10:53 | DNS A `pxe01.par1.medisphere.internal` | réponse 10.10.60.10 |
| <…> | client → 10.10.60.10:443 | TLS ClientHello | **SNI `pxe01.par1.medisphere.internal`**, version proposée TLS 1.2 |
| <…> | pxe01 → client | ServerHello, Certificate… | suite `<ex. TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384>` |
| <…> | client ↔ pxe01 | TLS Application Data | `GET /boot.ipxe`, `/ipxe/mac-…ipxe`, noyau, initrd, preseed (journal nginx : `pxe-access.log`) |

## Démarrage UEFI (`bm03`, OVMF)

Mêmes étapes ; différences : option 93 = **0x0007** (EFI x86-64), fichier `ipxe.efi`, chargeur plus gros (<…> Kio contre <…> Kio), <autres différences observées>.

## Temps par étage

| Étage | BIOS | UEFI |
|---|---|---|
| Micrologiciel jusqu'au premier DISCOVER | <…> s | <…> s |
| DHCP (ROM) | <…> | <…> |
| TFTP du chargeur | <…> | <…> |
| DHCP (iPXE) + DNS + TLS | <…> | <…> |
| HTTPS noyau + initrd | <…> | <…> |

## Réponses aux questions

a. Deux échanges DHCP : la ROM PXE obtient adresse et chargeur ; iPXE, une fois chargé, **refait** un DHCP (il ne réutilise pas l'état de la ROM) et s'annonce par l'option 77 *user-class* « iPXE » (RFC 3004) ; Kea classe ce client (`option[77]`) et lui donne l'URL HTTPS au lieu du chargeur, sans quoi iPXE rechargerait iPXE en boucle.
b. Le relais reçoit le broadcast sur `ens19.60`, renseigne `giaddr` avec son adresse sur le VLAN 60, et envoie le message en **unicast** depuis le port 67 vers chaque serveur Kea ; Kea choisit le sous-réseau `id: 60` d'après `giaddr`, et répond au relais (port 67), qui rediffuse vers le client.
c. `tsize` (RFC 2349) et `blksize` (RFC 2348), acceptés par un OACK (RFC 2347). À 512 octets par bloc, un fichier de <…> Kio demande <…> allers-retours ; à 1432, <…> : <mesure>.
d. TLS 1.2, suite `<…>` ; le nom apparaît en clair dans l'extension SNI du ClientHello (et dans la requête DNS juste avant).
e. <étage le plus long> ; pistes : initrd plus petit, HTTP/1.1 *keep-alive*, miroir local (`apt-cacher-ng`) pour l'installateur, `blksize` plus grand.
f. Option 93, nom et taille du chargeur, <…>.
