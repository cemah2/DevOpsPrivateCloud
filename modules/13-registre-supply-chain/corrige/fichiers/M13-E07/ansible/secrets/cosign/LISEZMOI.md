# secrets/cosign/ — clé de signature des images MédiSphère (M13-E07)

- `cosign.key` : clé privée Cosign, **fichier entièrement chiffré** par Ansible Vault, identité
  `critique` (en-tête `$ANSIBLE_VAULT;1.2;AES256;critique`). Jamais déchiffrée sur disque : on la
  lit avec `ansible-vault view` vers une variable d'environnement (`--key env://COSIGN_KEY`).
- Phrase de passe : `vault_cosign_mdp` dans `inventories/lab/group_vars/all/vault-critique-cosign.yml`
  (identité `critique`).
- Clé publique : **pas ici** — `plateforme/medisphere`, `docs/registre/cosign.pub`.
- Copies pour la CI : variables `COSIGN_PRIVATE_KEY` (fichier, protégée) et `COSIGN_PASSWORD`
  (protégée, masquée) des groupes `mediagenda`, `medidoc`, `medinotif`, `legacy`
  (outils/variables-ci-cosign.sh).
- Rotation et révocation : `docs/registre/signature.md`. Inscrit au registre des secrets.
