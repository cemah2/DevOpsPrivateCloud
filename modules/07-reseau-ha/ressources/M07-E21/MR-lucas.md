# MR !47 — Répartiteurs : publication de MédiAgenda (brouillon)

**Auteur** : Lucas Martin — **Relecteur demandé** : Karim Benali

Bonjour Karim,

Voici la configuration des répartiteurs pour publier `agenda.par1.medisphere.internal` (les deux
serveurs d'application arriveront au bloc C, adresses prévues 10.10.40.21 et .22). J'ai repris la
base de `lb01`/`lb02` et ajouté ce qu'il faut.

Ce que j'ai fait :
- testé sur deux VMs de la sandbox (`sbx81`, `sbx82`), avec deux petits serveurs Python à la place
  de MédiAgenda : la page s'affiche en HTTP et en HTTPS, j'ai fait 500 requêtes avec `ab`, zéro erreur ;
- les serveurs d'application auront un certificat autosigné au début, donc j'ai mis `verify none`
  pour ne pas être bloqué ;
- j'ai ouvert la page de statistiques sur le port 8404 pour qu'on puisse la regarder depuis nos
  postes (mot de passe simple, on le changera) ;
- keepalived : j'ai mis le VRID 70 pour que ce soit cohérent avec le VLAN 70 ; `lb01` est MASTER,
  `lb02` BACKUP ; j'ai copié le fichier de `lb01` pour `lb02` en changeant ce qu'il fallait ;
- j'ai ajouté une vérification d'HAProxy dans keepalived et un mot de passe VRRP pour la sécurité ;
- délais d'une heure, parce que l'export des agendas en PDF peut être long.

Pour tester la bascule, j'ai fait `systemctl stop keepalived` sur `lb01` : la VIP est bien passée
sur `lb02`. 👍
