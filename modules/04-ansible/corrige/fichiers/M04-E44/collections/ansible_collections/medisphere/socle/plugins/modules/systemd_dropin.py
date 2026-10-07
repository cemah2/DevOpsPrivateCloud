#!/usr/bin/python
# -*- coding: utf-8 -*-
# Copyright: (c) 2026, MédiSphère — équipe Plateforme
# GNU General Public License v3.0+ (see https://www.gnu.org/licenses/gpl-3.0.txt)
#
# M04-E44 — module maison de la collection medisphere.socle.
# Gère un fichier de surcharge (« drop-in ») d'une unité systemd :
#   <unit_dir>/<unit>.d/<name>.conf
# Idempotent, compatible avec --check et --diff, écriture atomique, droits gérés par les
# arguments de fichier communs (owner, group, mode…), daemon-reload seulement si nécessaire.

from __future__ import annotations

DOCUMENTATION = r"""
---
module: systemd_dropin
short_description: Gère un fichier de surcharge (drop-in) d'une unité systemd
version_added: "1.1.0"
description:
  - Crée, met à jour ou supprime le fichier C(<unit_dir>/<unit>.d/<name>.conf).
  - Le contenu est entièrement généré à partir de O(settings) dans un ordre stable, ce qui rend le module idempotent.
  - Ne relance aucun service. Lance C(systemctl daemon-reload) quand le fichier change, sauf si O(daemon_reload=false).
  - Le redémarrage éventuel du service reste à la charge du playbook (handler), comme pour un fichier de configuration.
options:
  unit:
    description:
      - Nom complet de l'unité surchargée, suffixe compris (par exemple V(chrony.service), V(ms-verif-sauvegardes.timer)).
    type: str
    required: true
  name:
    description:
      - Nom du fichier de surcharge, sans le suffixe C(.conf).
      - systemd lit les fichiers d'un dossier C(.d/) par ordre alphabétique ; pour une même clé, le dernier lu l'emporte
        (sauf pour les clés à valeurs multiples, qui s'accumulent).
    type: str
    default: 50-medisphere
  settings:
    description:
      - "Sections et réglages, sous la forme C({Section: {Cle: valeur}})."
      - >-
        Une valeur liste produit une ligne par élément (utile pour remettre à zéro une clé multiple avec une chaîne
        vide en tête, par exemple C(ExecStart=) puis C(ExecStart=/usr/local/bin/outil)).
      - Les booléens sont écrits C(yes)/C(no).
      - Obligatoire si O(state=present).
    type: dict
  state:
    description:
      - V(present) garantit le contenu du fichier, V(absent) le supprime (et supprime le dossier C(.d/) s'il devient vide).
    type: str
    choices: [present, absent]
    default: present
  daemon_reload:
    description:
      - Lance C(systemctl daemon-reload) après une modification réelle (jamais en mode vérification).
    type: bool
    default: true
  unit_dir:
    description:
      - Dossier des unités de l'administrateur. À changer seulement pour les tests ou des unités utilisateur.
    type: path
    default: /etc/systemd/system
extends_documentation_fragment:
  - ansible.builtin.files
attributes:
  check_mode:
    support: full
  diff_mode:
    support: full
notes:
  - Le mode par défaut du fichier est V(0644) si O(mode) n'est pas précisé.
author:
  - Équipe Plateforme MédiSphère
"""

EXAMPLES = r"""
- name: Redémarrer chrony automatiquement s'il s'arrête
  medisphere.socle.systemd_dropin:
    unit: chrony.service
    name: 50-redemarrage
    settings:
      Unit:
        StartLimitIntervalSec: 300
        StartLimitBurst: 5
      Service:
        Restart: on-failure
        RestartSec: 5s
  notify: Redémarrer chrony

- name: Retirer une ancienne surcharge
  medisphere.socle.systemd_dropin:
    unit: dnsmasq.service
    name: 90-ancien
    state: absent
"""

RETURN = r"""
path:
  description: Chemin du fichier de surcharge géré.
  returned: always
  type: str
  sample: /etc/systemd/system/chrony.service.d/50-redemarrage.conf
content:
  description: Contenu attendu du fichier (vide si O(state=absent)).
  returned: always
  type: str
daemon_reloaded:
  description: Indique si C(systemctl daemon-reload) a été lancé.
  returned: always
  type: bool
  sample: true
"""

import os
import re
import tempfile

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.common.text.converters import to_bytes, to_native

ENTETE = "# Géré par Ansible (medisphere.socle.systemd_dropin) : toute modification manuelle sera écrasée.\n"
RE_UNITE = re.compile(r"^[A-Za-z0-9:_.@\\-]+\.(service|socket|timer|mount|automount|path|slice|scope|target|swap|device)$")
RE_NOM = re.compile(r"^[A-Za-z0-9_.@-]+$")
RE_CLE = re.compile(r"^[A-Za-z][A-Za-z0-9]*$")


def valeur_systemd(valeur):
    """Convertit une valeur YAML en texte systemd."""
    if isinstance(valeur, bool):
        return "yes" if valeur else "no"
    if valeur is None:
        return ""
    texte = to_native(valeur)
    if "\n" in texte:
        raise ValueError("une valeur ne peut pas contenir de saut de ligne : %r" % texte)
    return texte


def generer_contenu(settings):
    """Produit le contenu du fichier : ordre des sections et des clés conservé (dict ordonné)."""
    lignes = [ENTETE]
    for section, cles in settings.items():
        if not RE_CLE.match(to_native(section)):
            raise ValueError("nom de section invalide : %r" % section)
        if not isinstance(cles, dict) or not cles:
            raise ValueError("la section %s doit être un dictionnaire non vide" % section)
        lignes.append("\n[%s]\n" % section)
        for cle, valeur in cles.items():
            if not RE_CLE.match(to_native(cle)):
                raise ValueError("nom de clé invalide : %r" % cle)
            valeurs = valeur if isinstance(valeur, list) else [valeur]
            for v in valeurs:
                lignes.append("%s=%s\n" % (cle, valeur_systemd(v)))
    return "".join(lignes)


def lire(chemin):
    try:
        with open(chemin, "rb") as f:
            return f.read().decode("utf-8")
    except FileNotFoundError:
        return None


def ecrire_atomique(module, chemin, contenu):
    """Écrit dans un fichier temporaire du même dossier, puis atomic_move (rename)."""
    dossier = os.path.dirname(chemin)
    fd, tmp = tempfile.mkstemp(prefix=".systemd_dropin.", dir=dossier)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(to_bytes(contenu))
        module.atomic_move(tmp, chemin)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def run_module():
    module = AnsibleModule(
        argument_spec=dict(
            unit=dict(type="str", required=True),
            name=dict(type="str", default="50-medisphere"),
            settings=dict(type="dict"),
            state=dict(type="str", choices=["present", "absent"], default="present"),
            daemon_reload=dict(type="bool", default=True),
            unit_dir=dict(type="path", default="/etc/systemd/system"),
        ),
        required_if=[("state", "present", ["settings"])],
        add_file_common_args=True,
        supports_check_mode=True,
    )
    p = module.params

    if not RE_UNITE.match(p["unit"]):
        module.fail_json(msg="nom d'unité invalide (suffixe attendu : .service, .timer…) : %s" % p["unit"])
    if not RE_NOM.match(p["name"]):
        module.fail_json(msg="nom de fichier de surcharge invalide : %s" % p["name"])

    dossier = os.path.join(p["unit_dir"], p["unit"] + ".d")
    chemin = os.path.join(dossier, p["name"] + ".conf")
    avant = lire(chemin)

    if p["state"] == "present":
        try:
            apres = generer_contenu(p["settings"])
        except ValueError as e:
            module.fail_json(msg="réglages invalides : %s" % to_native(e))
    else:
        apres = None

    changed = avant != apres
    result = dict(changed=changed, path=chemin, content=apres or "", daemon_reloaded=False)

    # --diff : une liste de différences est acceptée par Ansible (contenu, puis attributs).
    diffs = []
    if module._diff:
        diffs.append(dict(
            before=avant or "",
            after=apres or "",
            before_header="%s (%s)" % (chemin, "présent" if avant is not None else "absent"),
            after_header="%s (%s)" % (chemin, "présent" if apres is not None else "absent"),
        ))

    if changed and not module.check_mode:
        if apres is not None:
            if not os.path.isdir(dossier):
                os.makedirs(dossier, 0o755)
            ecrire_atomique(module, chemin, apres)
        else:
            os.unlink(chemin)
            try:
                os.rmdir(dossier)
            except OSError:
                pass  # dossier non vide : d'autres surcharges existent, on les laisse

    # Droits et propriétaire : gérés par les arguments communs (owner, group, mode, seuser…).
    # Un fichier encore absent en mode vérification est déjà compté comme changement.
    if p["state"] == "present" and os.path.exists(chemin):
        file_args = module.load_file_common_arguments(p, path=chemin)
        if file_args.get("mode") is None:
            file_args["mode"] = "0644"
        diff_attributs = {}
        result["changed"] = module.set_fs_attributes_if_different(
            file_args, result["changed"], diff=diff_attributs
        )
        if module._diff and diff_attributs:
            diffs.append(diff_attributs)
    if diffs:
        result["diff"] = diffs

    # daemon-reload seulement si le CONTENU a changé (un chmod ne change rien pour systemd).
    if changed and p["daemon_reload"] and not module.check_mode:
        systemctl = module.get_bin_path("systemctl", required=True)
        rc, out, err = module.run_command([systemctl, "daemon-reload"])
        if rc != 0:
            module.fail_json(msg="systemctl daemon-reload a échoué", rc=rc, stdout=out, stderr=err, **result)
        result["daemon_reloaded"] = True

    module.exit_json(**result)


def main():
    run_module()


if __name__ == "__main__":
    main()
