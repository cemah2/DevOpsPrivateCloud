# MR !12 — feat: rôles fail2ban et comptes_equipe

**Auteur** : Lucas Martin — **Cible** : `main` de `plateforme/ansible`

Salut ! Deux rôles pour l'audit HDS :

- `fail2ban` : bannit les IP qui ratent leur authentification SSH (3 essais, 1 h). Comme ça on est
  protégés contre la force brute.
- `comptes_equipe` : un compte nominatif par personne de l'équipe, avec ses clés SSH récupérées
  directement depuis son profil GitLab (plus besoin de les recopier !) et sudo.

Le playbook `playbooks/durcir-socle.yml` applique les deux partout.

**Tests** : lancé trois fois sur ma VM d'essai (Debian 12, l'Ansible du paquet Debian), tout est vert,
aucune erreur. J'ai mis `ignore_errors` sur la création des comptes parce que ça plantait quand le
compte existait déjà.

Je n'ai pas lancé ansible-lint, il trouvait des centaines de trucs dans d'autres fichiers.
