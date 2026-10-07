# M04-E44 — tests unitaires du module medisphere.socle.systemd_dropin.
# Lancement (depuis ~/src/ansible/collections) :
#   python -m pytest ansible_collections/medisphere/socle/tests/unit -q
# ou, depuis la racine de la collection : ansible-test units --python 3.13 (si ansible-test est utilisé).
# patch_module_args (ansible.module_utils.testing) existe depuis ansible-core 2.19.
from __future__ import annotations

import json
import os
import stat

import pytest

from ansible.module_utils import basic
from ansible.module_utils.testing import patch_module_args
from ansible_collections.medisphere.socle.plugins.modules import systemd_dropin

REGLAGES = {"Service": {"Restart": "on-failure", "RestartSec": "5s"}, "Unit": {"StartLimitBurst": 5}}


class Sortie(Exception):
    """Levée à la place de sys.exit : porte le résultat du module."""

    def __init__(self, resultat, echec=False):
        super().__init__(resultat)
        self.resultat = resultat
        self.echec = echec


@pytest.fixture(autouse=True)
def sans_sortie(monkeypatch):
    def exit_json(self, **kwargs):
        raise Sortie(kwargs)

    def fail_json(self, msg, **kwargs):
        kwargs["msg"] = msg
        raise Sortie(kwargs, echec=True)

    monkeypatch.setattr(basic.AnsibleModule, "exit_json", exit_json)
    monkeypatch.setattr(basic.AnsibleModule, "fail_json", fail_json)


@pytest.fixture
def appels_systemctl(monkeypatch):
    """Remplace systemctl : on note les appels au lieu de toucher au système."""
    appels = []

    def run_command(self, args, **kwargs):
        appels.append(list(args))
        return 0, "", ""

    monkeypatch.setattr(basic.AnsibleModule, "get_bin_path", lambda self, *a, **k: "/usr/bin/systemctl")
    monkeypatch.setattr(basic.AnsibleModule, "run_command", run_command)
    return appels


def lancer(args, check=False, diff=False):
    args = dict(args)
    if check:
        args["_ansible_check_mode"] = True
    if diff:
        args["_ansible_diff"] = True
    with patch_module_args(args):
        with pytest.raises(Sortie) as exc:
            systemd_dropin.main()
    return exc.value


def args_de_base(tmp_path, **autres):
    a = {"unit": "chrony.service", "name": "50-redemarrage", "unit_dir": str(tmp_path), "settings": REGLAGES}
    a.update(autres)
    return a


def chemin(tmp_path):
    return tmp_path / "chrony.service.d" / "50-redemarrage.conf"


def test_generer_contenu_ordre_et_types():
    texte = systemd_dropin.generer_contenu({"Service": {"Restart": "always", "NoNewPrivileges": True,
                                                        "ExecStart": ["", "/bin/true"]}})
    assert texte.splitlines()[2:] == ["[Service]", "Restart=always", "NoNewPrivileges=yes", "ExecStart=", "ExecStart=/bin/true"]


def test_generer_contenu_refuse_les_sauts_de_ligne():
    with pytest.raises(ValueError):
        systemd_dropin.generer_contenu({"Service": {"Environment": "A=1\nExecStart=/bin/sh"}})


def test_creation_puis_idempotence(tmp_path, appels_systemctl):
    r = lancer(args_de_base(tmp_path))
    assert not r.echec and r.resultat["changed"] is True and r.resultat["daemon_reloaded"] is True
    assert chemin(tmp_path).read_text(encoding="utf-8") == systemd_dropin.generer_contenu(REGLAGES)
    assert stat.S_IMODE(os.stat(chemin(tmp_path)).st_mode) == 0o644
    assert appels_systemctl == [["/usr/bin/systemctl", "daemon-reload"]]

    r = lancer(args_de_base(tmp_path))
    assert r.resultat["changed"] is False and r.resultat["daemon_reloaded"] is False
    assert len(appels_systemctl) == 1  # pas de daemon-reload au second passage


def test_mode_verification_ne_touche_a_rien(tmp_path, appels_systemctl):
    r = lancer(args_de_base(tmp_path), check=True, diff=True)
    assert r.resultat["changed"] is True
    assert not chemin(tmp_path).exists()
    assert appels_systemctl == []
    assert "Restart=on-failure" in r.resultat["diff"][0]["after"]
    assert r.resultat["diff"][0]["before"] == ""


def test_modification_manuelle_corrigee(tmp_path, appels_systemctl):
    lancer(args_de_base(tmp_path))
    chemin(tmp_path).write_text("[Service]\nRestart=no\n", encoding="utf-8")
    r = lancer(args_de_base(tmp_path), diff=True)
    assert r.resultat["changed"] is True
    assert "Restart=no" in r.resultat["diff"][0]["before"]
    assert "Restart=on-failure" in chemin(tmp_path).read_text(encoding="utf-8")


def test_mode_seul_sans_daemon_reload(tmp_path, appels_systemctl):
    lancer(args_de_base(tmp_path))
    r = lancer(args_de_base(tmp_path, mode="0600"))
    assert r.resultat["changed"] is True and r.resultat["daemon_reloaded"] is False
    assert stat.S_IMODE(os.stat(chemin(tmp_path)).st_mode) == 0o600
    assert len(appels_systemctl) == 1


def test_suppression_et_dossier_vide_retire(tmp_path, appels_systemctl):
    lancer(args_de_base(tmp_path))
    r = lancer({"unit": "chrony.service", "name": "50-redemarrage", "unit_dir": str(tmp_path), "state": "absent"})
    assert r.resultat["changed"] is True
    assert not (tmp_path / "chrony.service.d").exists()
    r = lancer({"unit": "chrony.service", "name": "50-redemarrage", "unit_dir": str(tmp_path), "state": "absent"})
    assert r.resultat["changed"] is False


def test_unite_invalide(tmp_path):
    r = lancer(args_de_base(tmp_path, unit="chrony"))
    assert r.echec and "unité" in r.resultat["msg"]


def test_settings_obligatoire_si_present(tmp_path):
    r = lancer({"unit": "chrony.service", "unit_dir": str(tmp_path)})
    assert r.echec and "settings" in r.resultat["msg"]


def test_le_resultat_est_serialisable(tmp_path, appels_systemctl):
    r = lancer(args_de_base(tmp_path), diff=True)
    json.dumps(r.resultat)
