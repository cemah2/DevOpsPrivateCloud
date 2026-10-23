"""Rôle durcissement (M26-E10 à E14) : ce que le rôle laisse sur l'hôte, exceptions comprises.

Le registre machine des exceptions (/etc/medisphere/conformite/exceptions.json, écrit par le
rôle) dit quelles règles XCCDF ne s'appliquent PAS sur cet hôte : un test dont la règle est en
exception est sauté (avec la règle dans le message), jamais réécrit pour passer. Sans registre,
le rôle n'est pas encore passé sur l'hôte (vagues de M26) : tout le fichier est sauté.
"""

import re

import pytest

pytestmark = pytest.mark.durcissement


@pytest.fixture(autouse=True)
def _role_applique(exceptions_durcissement):
    if exceptions_durcissement is None:
        pytest.skip("rôle durcissement pas encore appliqué ici (pas de registre des exceptions)")


def _sauf_exception(exceptions, regle):
    if regle in exceptions:
        pytest.skip(f"règle {regle} en exception sur cet hôte (registre M26)")


# (paramètre, valeur attendue, règle XCCDF) — extrait des valeurs du rôle, les plus parlantes.
SYSCTL = [
    ("kernel.kptr_restrict", 2, "sysctl_kernel_kptr_restrict"),
    ("kernel.dmesg_restrict", 1, "sysctl_kernel_dmesg_restrict"),
    ("kernel.randomize_va_space", 2, "sysctl_kernel_randomize_va_space"),
    ("kernel.unprivileged_bpf_disabled", 1, "sysctl_kernel_unprivileged_bpf_disabled"),
    ("fs.suid_dumpable", 0, "sysctl_fs_suid_dumpable"),
    ("net.ipv4.ip_forward", 0, "sysctl_net_ipv4_ip_forward"),
    ("net.ipv4.conf.all.accept_redirects", 0, "sysctl_net_ipv4_conf_all_accept_redirects"),
    ("net.ipv4.conf.all.send_redirects", 0, "sysctl_net_ipv4_conf_all_send_redirects"),
    ("net.ipv4.tcp_syncookies", 1, "sysctl_net_ipv4_tcp_syncookies"),
]


@pytest.mark.parametrize(("parametre", "attendu", "regle"), SYSCTL, ids=[s[0] for s in SYSCTL])
def test_parametre_noyau(host, exceptions_durcissement, parametre, attendu, regle):
    _sauf_exception(exceptions_durcissement, regle)
    assert host.sysctl(parametre) == attendu


@pytest.mark.parametrize("module", ["cramfs", "freevxfs", "hfs", "usb-storage", "dccp", "sctp"])
def test_module_noyau_non_chargeable(host, exceptions_durcissement, module):
    _sauf_exception(exceptions_durcissement, f"kernel_module_{module}_disabled")
    # « modprobe -n -v » dit ce qu'il ferait : « install /bin/false » = le chargement échouerait.
    sortie = host.run(f"modprobe -n -v {module}")
    assert "install /bin/false" in sortie.stdout + sortie.stderr
    assert not host.run(f"grep -qw '^{module.replace('-', '_')}' /proc/modules").succeeded


@pytest.mark.parametrize("paquet", ["telnet", "rsh-client", "avahi-daemon", "xinetd"])
def test_paquet_interdit_absent(host, famille, paquet):
    if famille != "debian":
        pytest.skip("liste Debian")
    assert not host.package(paquet).is_installed


def test_tmp_monte_sans_execution(host, exceptions_durcissement):
    options = set(host.mount_point("/tmp").options)
    assert {"nodev", "nosuid"} <= options
    if "mount_option_tmp_noexec" not in exceptions_durcissement:
        assert "noexec" in options


def test_ssh_tel_que_sshd_le_comprend(host, exceptions_durcissement):
    # « sshd -T » donne la configuration EFFECTIVE (tous les fichiers inclus, premier gagnant).
    with host.sudo():
        effectif = host.check_output("sshd -T")
    reglages = dict(ligne.split(" ", 1) for ligne in effectif.splitlines() if " " in ligne)
    assert reglages["permitrootlogin"] == "no"
    assert reglages["maxsessions"] == "10"
    assert not re.search(r"cbc", reglages["ciphers"])
    if "sshd_limit_user_access" not in exceptions_durcissement:
        assert "admin" in reglages.get("allowgroups", "").split()


def test_auditd_actif(host):
    assert host.service("auditd").is_running


def test_journal_persistant(host):
    conf = host.file("/etc/systemd/journald.conf.d/60-durcissement.conf")
    assert conf.exists
    assert re.search(r"^Storage=persistent$", conf.content_string, re.M)


def test_verification_aide_planifiee(host, exceptions_durcissement):
    _sauf_exception(exceptions_durcissement, "aide_periodic_checking_systemd_timer")
    assert host.service("aide-verification.timer").is_enabled


def test_verrouillage_apres_cinq_echecs(host):
    conf = host.file("/etc/security/faillock.conf")
    assert re.search(r"^deny\s*=\s*5$", conf.content_string, re.M)
