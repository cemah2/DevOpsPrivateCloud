"""Tests de la synchronisation Proxmox → NetBox (M06-E11) : calcul pur, sans réseau."""

from __future__ import annotations

from medictl import synchro_netbox as s

GIO = 1024**3


def ressource(
    vmid, nom, *, tags="socle;role-dns", status="running", cpus=2, mem_gio=2, disque_gio=20
):
    return {
        "vmid": vmid,
        "name": nom,
        "type": "qemu",
        "status": status,
        "maxcpu": cpus,
        "maxmem": mem_gio * GIO,
        "maxdisk": disque_gio * GIO,
        "tags": tags,
        "template": 0,
        "node": "pve01",
    }


def vm_netbox(
    ident,
    nom,
    *,
    vmid,
    status="active",
    vcpus=2.0,
    memoire=2048,
    disque=20480,
    tags=("socle", "role-dns"),
    ip="10.10.20.10/24",
    onboot="on",
    disques_virtuels=0,
):
    return {
        "id": ident,
        "name": nom,
        "status": {"value": status, "label": status.capitalize()},
        "vcpus": vcpus,
        "memory": memoire,
        "disk": disque,
        "start_on_boot": {"value": onboot, "label": onboot},
        "custom_fields": {"vmid": vmid},
        "cluster": {"id": 1, "name": "pve01"},
        "tags": [{"slug": t, "name": t} for t in tags],
        "primary_ip4": {"address": ip} if ip else None,
        "virtual_disk_count": disques_virtuels,
    }


ETIQUETTES = {"socle", "role-dns", "role-pki", "env-m06"}


def planifier(proxmox, netbox):
    return s.planifier(proxmox, netbox, cluster_id=1, etiquettes_netbox=ETIQUETTES)


def test_rien_a_faire_quand_tout_concorde():
    proxmox = [(ressource(1002, "dns01"), {"onboot": 1}, ["10.10.20.10"])]
    netbox = [vm_netbox(10, "dns01", vmid=1002)]
    assert planifier(proxmox, netbox) == []


def test_creation_avec_etiquettes_connues_seulement():
    proxmox = [(ressource(2061, "m06-essai", tags="env-m06;inconnue"), {}, [])]
    changements = planifier(proxmox, [])
    assert [c.action for c in changements] == ["creer"]
    champs = changements[0].champs
    assert champs["name"] == "m06-essai"
    assert champs["cluster"] == 1
    assert champs["tags"] == [{"slug": "env-m06"}]
    assert champs["custom_fields"] == {"vmid": 2061}
    assert champs["memory"] == 2048 and champs["disk"] == 20480
    assert champs["start_on_boot"] == "off"


def test_etiquette_absente_de_netbox_signalee():
    proxmox = [(ressource(1003, "ca01", tags="socle;role-nouveau"), {"onboot": 1}, [])]
    changements = planifier(proxmox, [])
    assert [c.action for c in changements] == ["creer", "signaler"]
    assert "role-nouveau" in changements[1].detail


def test_modification_seulement_des_champs_qui_different():
    proxmox = [(ressource(1002, "dns01", cpus=4, status="stopped"), {"onboot": 1}, [])]
    netbox = [vm_netbox(10, "dns01", vmid=1002)]
    (changement,) = planifier(proxmox, netbox)
    assert changement.action == "modifier"
    assert changement.ident_netbox == 10
    assert changement.champs == {"vcpus": 4.0, "status": "offline"}


def test_vmid_absent_dans_netbox_est_complete_sans_toucher_aux_autres_champs_personnalises():
    proxmox = [(ressource(1002, "dns01"), {"onboot": 1}, ["10.10.20.10"])]
    vm = vm_netbox(10, "dns01", vmid=None)
    vm["custom_fields"] = {"vmid": None, "contact": "Nadia"}
    (changement,) = planifier(proxmox, [vm])
    assert changement.champs == {"custom_fields": {"vmid": 1002}}


def test_disque_ignore_quand_la_vm_a_des_disques_virtuels():
    proxmox = [(ressource(1005, "nbx01", disque_gio=30), {"onboot": 1}, ["10.10.20.13"])]
    netbox = [vm_netbox(11, "nbx01", vmid=1005, disque=99, disques_virtuels=1, ip="10.10.20.13/24")]
    assert planifier(proxmox, netbox) == []


def test_ip_differente_signalee_jamais_corrigee():
    proxmox = [(ressource(1002, "dns01"), {"onboot": 1}, ["10.10.20.99"])]
    netbox = [vm_netbox(10, "dns01", vmid=1002)]
    (changement,) = planifier(proxmox, netbox)
    assert changement.action == "signaler"
    assert "10.10.20.10" in changement.detail and "10.10.20.99" in changement.detail


def test_vm_du_socle_absente_de_proxmox_signalee():
    netbox = [vm_netbox(12, "vault01", vmid=1021, tags=("socle",))]
    (changement,) = planifier([], netbox)
    assert changement.action == "signaler"
    assert "absente de Proxmox" in changement.detail


def test_renommage_dans_proxmox_signale_sans_creation():
    proxmox = [(ressource(1002, "dns01-nouveau"), {"onboot": 1}, [])]
    netbox = [vm_netbox(10, "dns01", vmid=1002)]
    changements = planifier(proxmox, netbox)
    assert [c.action for c in changements] == ["signaler"]
    assert "dns01" in changements[0].detail


def test_templates_et_molecule_exclus():
    modele = ressource(9020, "deb13-gold", tags="gold;current;debian13") | {"template": 1}
    instance = ressource(2045, "m04-mol-base", tags="molecule;env-m04")
    personnelle = ressource(100, "perso", tags="")
    assert planifier([(modele, {}, []), (instance, {}, []), (personnelle, {}, [])], []) == []


def test_mauvais_cluster_corrige():
    proxmox = [(ressource(1002, "dns01"), {"onboot": 1}, ["10.10.20.10"])]
    vm = vm_netbox(10, "dns01", vmid=1002)
    vm["cluster"] = {"id": 7, "name": "ancien"}
    (changement,) = planifier(proxmox, [vm])
    assert changement.champs == {"cluster": 1}


class FauxNetbox:
    def __init__(self):
        self.appels = []

    def creer(self, chemin, donnees):
        self.appels.append(("POST", chemin, donnees))
        return {"id": 99}

    def modifier(self, chemin, ident, donnees):
        self.appels.append(("PATCH", chemin, ident, donnees))
        return {"id": ident}


def test_appliquer_n_ecrit_pas_les_ecarts():
    changements = [
        s.Changement("creer", "a", 1, {"name": "a"}),
        s.Changement("modifier", "b", 2, {"vcpus": 2.0}, ident_netbox=5),
        s.Changement("signaler", "c", 3, detail="x"),
    ]
    faux = FauxNetbox()
    bilan = s.appliquer(faux, changements)
    assert (bilan.crees, bilan.modifies, bilan.ecarts) == (1, 1, 1)
    assert [a[0] for a in faux.appels] == ["POST", "PATCH"]
