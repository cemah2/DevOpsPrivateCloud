<!-- EXTRAIT de docs/socle/iac.md (plateforme/medisphere), section écrite en M05-E31. -->

## Montée de version des providers

**Fréquence** : le premier mardi du mois (et sans attendre pour un correctif de sécurité). Un
provider en 0.x (`bpg/proxmox`) ne saute jamais plus d'une version mineure à la fois.

**Qui décide** : l'ingénieur de la plateforme qui prépare la MR ; un report (« on reste en 0.x »)
est noté dans la MR avec sa raison et une date de réexamen. Karim Benali tranche en cas de doute.

**Procédure**
1. **Lire** le journal des modifications de chaque version sautée
   (<https://github.com/bpg/terraform-provider-proxmox/blob/main/CHANGELOG.md>) ; noter dans la MR
   les entrées qui touchent nos ressources (`proxmox_virtual_environment_vm`, sources de données
   `proxmox_virtual_environment_vms`, `proxmox_datastores`, fichiers) et celles qui peuvent
   changer un plan sans changement de code.
2. **Branche** `conf/provider-<version>` ; changer la contrainte dans **toutes** les configurations
   racine (`socle/`, `envs/*/`) et dans les composants Terragrunt ; ne pas toucher au module
   `vm-debian` si sa contrainte admet la nouvelle version.
3. **Locks** : `tofu init -upgrade` puis `tofu providers lock -platform=linux_amd64` dans chaque
   configuration (et chaque unité Terragrunt) ; relire le diff des locks (une version, de
   nouvelles empreintes `h1:`/`zh:`, rien d'autre).
4. **Plans** sur toutes les configurations (`tofu plan`, `terragrunt run --all plan`) : attendu
   « No changes ». Tout changement est expliqué dans la MR (normalisation du provider, nouvelle
   valeur par défaut, vraie différence) et décidé : accepter, `ignore_changes` argumenté, ou
   reporter la montée.
5. **Noter le retour arrière** dans la MR : pour chaque état, le `VersionId` courant de l'objet
   dans `tofu-state` (`outils/restaurer-etat.sh --lister <clé>`).
6. **Fusion**, puis jobs `apply:` (plans vides ; une nouvelle version de l'état n'apparaît que si son contenu change, par exemple une `schema_version` relevée),
   contrôle de convergence vert.

**Retour arrière**
- *Avant* tout apply : revert de la MR, rien d'autre.
- *Après* un apply : un provider plus ancien peut refuser de lire un état écrit par un plus récent
  (version de schéma des ressources). Revert de la MR **et** restauration, pour chaque état, de la
  version notée à l'étape 5 (`outils/restaurer-etat.sh --version`), puis plans vides. Tout apply
  fait entre-temps est perdu de l'état : à refaire, ou à réimporter.
