#!/usr/bin/python
# -*- coding: utf-8 -*-
# M04-E44 — squelette FACULTATIF du module medisphere.socle.systemd_dropin.
# À copier dans ~/src/ansible/collections/ansible_collections/medisphere/socle/plugins/modules/
# puis à compléter selon le contrat de l'énoncé. Les « TODO » indiquent ce qui reste à écrire ;
# rien ici n'est une solution complète.

from __future__ import annotations

DOCUMENTATION = r"""
---
module: systemd_dropin
short_description: Gère un fichier de surcharge (drop-in) d'une unité systemd
description:
  - TODO décrire ce que fait le module, ce qu'il ne fait pas (redémarrer le service).
options:
  unit:
    description: TODO
    type: str
    required: true
  # TODO name, settings, state, daemon_reload, unit_dir (voir le contrat)
extends_documentation_fragment:
  - ansible.builtin.files
attributes:
  check_mode:
    support: full
  diff_mode:
    support: full
author:
  - TODO
"""

EXAMPLES = r"""
# TODO un exemple pour chrony.service, un exemple state=absent
"""

RETURN = r"""
# TODO path, content, daemon_reloaded
"""

from ansible.module_utils.basic import AnsibleModule


def generer_contenu(settings):
    """TODO : texte du fichier, ordre stable, une ligne par valeur, refus des sauts de ligne."""
    raise NotImplementedError


def run_module():
    module = AnsibleModule(
        argument_spec=dict(
            unit=dict(type="str", required=True),
            # TODO les autres options du contrat
        ),
        add_file_common_args=True,
        supports_check_mode=True,
    )
    result = dict(changed=False)

    # TODO 1. calculer le chemin et lire le contenu actuel (ou son absence)
    # TODO 2. calculer le contenu attendu (state=present) ou None (state=absent)
    # TODO 3. diff si module._diff
    # TODO 4. si changement et pas module.check_mode : écrire (atomic_move) ou supprimer
    # TODO 5. droits : load_file_common_arguments + set_fs_attributes_if_different
    # TODO 6. daemon-reload si le CONTENU a changé et pas en mode vérification

    module.exit_json(**result)


def main():
    run_module()


if __name__ == "__main__":
    main()
