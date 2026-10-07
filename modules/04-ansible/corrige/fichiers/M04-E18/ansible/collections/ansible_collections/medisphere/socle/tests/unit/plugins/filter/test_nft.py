"""Tests du filtre medisphere.socle.regle_nft (M04-E18).

Lancement depuis la racine du projet :
  PYTHONPATH=collections uv run --with pytest pytest collections/ansible_collections/medisphere/socle/tests/unit
"""

import pytest
from ansible.errors import AnsibleFilterError
from ansible_collections.medisphere.socle.plugins.filter.nft import regle_nft


def test_flux_complet():
    flux = {
        "entree": "$V_MGMT", "sortie": "$WAN", "destination": "$PVE01",
        "proto": "tcp", "ports": [22, 8006], "motif": "adm01 vers pve01", "ref": "M00-E15",
    }
    assert regle_nft(flux) == (
        'iifname $V_MGMT oifname $WAN ip daddr $PVE01 tcp dport { 22, 8006 } '
        'accept comment "adm01 vers pve01 (M00-E15)"'
    )


def test_tcp_et_udp():
    flux = {"source": ["$NETS_LAB", "$NET_VPN"], "destination": "$DNS01",
            "proto": "tcp_udp", "ports": 53, "motif": "DNS"}
    assert regle_nft(flux) == (
        'ip saddr { $NETS_LAB, $NET_VPN } ip daddr $DNS01 meta l4proto { tcp, udp } '
        'th dport 53 accept comment "DNS"'
    )


def test_ports_source_et_destination():
    flux = {"entree": "$V_SANDBOX", "proto": "udp", "ports_source": 68, "ports": 67, "motif": "DHCP"}
    assert regle_nft(flux) == 'iifname $V_SANDBOX udp sport 68 udp dport 67 accept comment "DHCP"'


def test_icmp_et_negation():
    assert regle_nft({"source": "10.10.10.0/24", "proto": "icmp", "motif": "ping"}) == (
        'ip saddr 10.10.10.0/24 icmp type echo-request accept comment "ping"'
    )
    assert regle_nft({"entree": "$LAB_IFS", "sortie": "$WAN", "destination": "!= $LAN_MAISON",
                      "motif": "Internet"}) == (
        'iifname $LAB_IFS oifname $WAN ip daddr != $LAN_MAISON accept comment "Internet"'
    )


def test_protocole_sans_port():
    assert regle_nft({"proto": "udp", "motif": "tout UDP"}) == 'meta l4proto udp accept comment "tout UDP"'


@pytest.mark.parametrize(
    "flux, message",
    [
        ({"destinaton": "$DNS01", "motif": "faute"}, r"champ\(s\) inconnu"),
        ({"proto": "tcp", "ports": 22}, "motif"),
        ({"proto": "tcp", "ports": 22, "motif": 'avec "guillemets"'}, "guillemet"),
        ({"ports": 22, "motif": "sans proto"}, "sans proto"),
        ({"proto": "sctp", "ports": 22, "motif": "inconnu"}, "inconnu"),
        ({"proto": "icmp", "ports": 22, "motif": "icmp"}, "ICMP"),
        ({"proto": "tcp", "ports": 22, "action": "allow", "motif": "action"}, "action"),
        ({"proto": "tcp", "ports": [], "motif": "vide"}, "liste vide"),
        ({"motif": "é" * 70}, "octets"),
        ("pas un dictionnaire", "dictionnaire"),
    ],
)
def test_refus(flux, message):
    with pytest.raises(AnsibleFilterError, match=message):
        regle_nft(flux)
