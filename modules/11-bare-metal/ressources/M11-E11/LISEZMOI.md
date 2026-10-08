# Fichiers d'installation d'InfoGér (archive du partage `\\infoger-nas\deploiement\`)

Récupérés par Lucas Martin le JJ/MM/AAAA. Note jointe par InfoGér (reproduite telle quelle) :

> Fichiers de déploiement standard MédiSphère, utilisés pour tous les serveurs depuis 2019.
> - `preseed-infoger.cfg` : Debian (serveurs applicatifs). Servi par notre serveur PXE `pxe.infoger.local`.
> - `ks-infoger.cfg` : Rocky Linux (serveurs de base de données), même serveur.
> Les deux fichiers sont testés et validés en production. Le compte `support` permet à notre
> équipe d'intervenir en urgence. Ne pas modifier sans nous prévenir.

Serveurs installés avec ces fichiers et encore en service chez l'hébergeur actuel : `app-prod-01` à
`app-prod-06` (Debian), `db-prod-01` et `db-prod-02` (Rocky). Le contrat d'InfoGér est résilié.
