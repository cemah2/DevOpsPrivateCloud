# Image Debian 13 « gold » — proposition de Lucas

Salut ! J'ai fait une image dorée Debian 13 plus simple que celle de l'équipe : **un seul
fichier**, pas de wrapper, pas de fichier d'environnement, et ça marche chez moi du premier
coup (template en 20 minutes environ).

    cd debian13-lucas
    packer build .

- J'ai mis les identifiants directement dans le fichier : comme ça, pas besoin de `source`
  quoi que ce soit avant de lancer Packer.
- Pas de VMID à choisir : Proxmox prend le premier libre.
- La VM de build est sur `vmbr0` : elle a Internet tout de suite par la box, pas besoin
  d'ouvrir des ports sur `gw01`.
- L'IP est fixe (192.168.1.150), donc pas besoin de l'agent QEMU pour la trouver.
- Pour les outils de l'équipe MédiAgenda j'ai repris la commande d'installation de leur doc.

Tu peux relire avant que j'ouvre la MR ? — Lucas
