# Tests unitaires du protocole « vrrp » du filtre regle_nft (M07-E25), à côté de test_nft.py
# (M04-E18). Lancés par le job « tests-collection » du pipeline de plateforme/ansible.
import pytest

from ansible.errors import AnsibleFilterError
from ansible_collections.medisphere.socle.plugins.filter.nft import regle_nft


def test_vrrp_entre_passerelles():
    regle = regle_nft({
        "entree": "$V_SANDBOX",
        "source": ["10.10.99.2", "10.10.99.3"],
        "proto": "vrrp",
        "motif": "VRRP entre passerelles",
        "ref": "M07-E25",
    })
    assert regle == ('iifname $V_SANDBOX ip saddr { 10.10.99.2, 10.10.99.3 } meta l4proto 112 '
                     'accept comment "VRRP entre passerelles (M07-E25)"')


def test_vrrp_refuse_les_ports():
    with pytest.raises(AnsibleFilterError, match="pas de ports"):
        regle_nft({"proto": "vrrp", "ports": 112, "motif": "x"})
