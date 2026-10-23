//go:build integration

// Petits clients des API Proxmox et NetBox pour les vérifications du test (M29-E08).
// Lecture seule. TLS vérifié par le magasin du système (racine MédiSphère, ancre de pve01).
package test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

var clientHTTP = &http.Client{Timeout: 20 * time.Second}

type proxmox struct {
	base  string // https://<pve01>:8006/api2/json
	jeton string // wb-terratest@pve!terratest=<secret>
}

func nouveauProxmox(t *testing.T) *proxmox {
	t.Helper()
	point := os.Getenv("PROXMOX_VE_ENDPOINT")
	jeton := os.Getenv("PROXMOX_VE_API_TOKEN")
	require.NotEmpty(t, point, "PROXMOX_VE_ENDPOINT absent (pve-terratest.env)")
	require.NotEmpty(t, jeton, "PROXMOX_VE_API_TOKEN absent (pve-terratest.env)")
	require.True(t, strings.HasPrefix(jeton, "wb-terratest@pve!"),
		"le test s'exécute avec l'identité dédiée wb-terratest, jamais avec celle d'OpenTofu ou de root")
	return &proxmox{base: strings.TrimRight(point, "/") + "/api2/json", jeton: jeton}
}

func (p *proxmox) get(chemin string, cible any) error {
	req, err := http.NewRequest(http.MethodGet, p.base+chemin, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "PVEAPIToken="+p.jeton)
	rep, err := clientHTTP.Do(req)
	if err != nil {
		return err
	}
	defer rep.Body.Close()
	if rep.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s : HTTP %d", chemin, rep.StatusCode)
	}
	return json.NewDecoder(rep.Body).Decode(&struct {
		Data any `json:"data"`
	}{Data: cible})
}

type ressource struct {
	VMID     int    `json:"vmid"`
	Name     string `json:"name"`
	Pool     string `json:"pool"`
	Tags     string `json:"tags"`
	Template int    `json:"template"`
	Status   string `json:"status"`
}

// ressources : VMs visibles par le jeton (VM.Audit) — pour wb-terratest, le sous-pool lab/terratest
// et les modèles. Une VM 229x hors du sous-pool est INVISIBLE ici : le clonage échouera alors
// (« VM 229x already exists ») sans rien écraser.
func (p *proxmox) ressources(t *testing.T) []ressource {
	t.Helper()
	var liste []ressource
	require.NoError(t, p.get("/cluster/resources?type=vm", &liste))
	return liste
}

func (p *proxmox) vmExiste(t *testing.T, vmid int) bool {
	for _, r := range p.ressources(t) {
		if r.VMID == vmid {
			return true
		}
	}
	return false
}

func (p *proxmox) ressourceVM(t *testing.T, vmid int) ressource {
	t.Helper()
	for _, r := range p.ressources(t) {
		if r.VMID == vmid {
			return r
		}
	}
	t.Fatalf("VM %d introuvable dans /cluster/resources", vmid)
	return ressource{}
}

// premierVmidLibre : un VMID de [min, max] qu'aucune VM n'occupe. Plage pleine = des VMs de tests
// précédents n'ont pas été détruites : on s'arrête AVANT de créer quoi que ce soit (RB-293).
func (p *proxmox) premierVmidLibre(t *testing.T, min, max int) int {
	t.Helper()
	pris := map[int]string{}
	for _, r := range p.ressources(t) {
		pris[r.VMID] = r.Name
	}
	for v := min; v <= max; v++ {
		if _, ok := pris[v]; !ok {
			return v
		}
	}
	t.Fatalf("aucun VMID libre entre %d et %d (VMs de tests orphelines ? RB-293) : %v", min, max, pris)
	return 0
}

// adressesAgent : adresses IPv4 annoncées par l'agent QEMU (VM.GuestAgent.Audit).
func (p *proxmox) adressesAgent(vmid int, noeud string) ([]string, error) {
	var reponse struct {
		Result []struct {
			Name      string `json:"name"`
			Addresses []struct {
				Type    string `json:"ip-address-type"`
				Address string `json:"ip-address"`
			} `json:"ip-addresses"`
		} `json:"result"`
	}
	if err := p.get(fmt.Sprintf("/nodes/%s/qemu/%d/agent/network-get-interfaces", noeud, vmid), &reponse); err != nil {
		return nil, err
	}
	var adresses []string
	for _, i := range reponse.Result {
		if i.Name == "lo" {
			continue
		}
		for _, a := range i.Addresses {
			if a.Type == "ipv4" {
				adresses = append(adresses, a.Address)
			}
		}
	}
	return adresses, nil
}

// nombreAdressesNetbox : nombre d'objets IP de NetBox pour cette adresse (0 attendu après destroy).
func nombreAdressesNetbox(t *testing.T, ip string) int {
	t.Helper()
	base := os.Getenv("NETBOX_URL")
	if base == "" {
		base = "https://nbx01.par1.medisphere.internal"
	}
	jeton := os.Getenv("TF_VAR_netbox_api_token")
	require.NotEmpty(t, jeton, "TF_VAR_netbox_api_token absent (netbox-tofu.env)")
	req, err := http.NewRequest(http.MethodGet, base+"/api/ipam/ip-addresses/?address="+url.QueryEscape(ip), nil)
	require.NoError(t, err)
	req.Header.Set("Authorization", "Bearer "+jeton)
	req.Header.Set("Accept", "application/json")
	rep, err := clientHTTP.Do(req)
	require.NoError(t, err)
	defer rep.Body.Close()
	require.Equal(t, http.StatusOK, rep.StatusCode, "API NetBox")
	var page struct {
		Count int `json:"count"`
	}
	require.NoError(t, json.NewDecoder(rep.Body).Decode(&page))
	return page.Count
}
