//go:build integration

// Test d'intégration du module vm-debian (plateforme/tofu-modules, M29-E08, PLAT-3008).
//
// Il CRÉE une vraie VM dans Proxmox (tt-<suffixe>, VMID 2290-2299, sous-pool lab/terratest, vsandbox,
// étiquettes env-m29 et terratest), vérifie ce que le module promet, puis la DÉTRUIT, même si une vérification échoue
// (t.Cleanup). Ce n'est pas un test unitaire : « tofu test » avec un fournisseur simulé (M05-E13)
// vérifie la logique du module en une seconde ; ce test vérifie que la VM obtenue MARCHE.
//
// Lancement (depuis vm-debian/test, environnement chargé) :
//
//	set -a; . ~/.config/workbook/pve-terratest.env; . ~/.config/workbook/netbox-tofu.env; set +a
//	go test -tags integration -run TestVmDebian -timeout 35m -v ./...
//
// Variables : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (wb-terratest@pve!terratest),
// TF_VAR_netbox_api_token, NETBOX_URL (facultatif), TT_NOEUD (défaut pve01), TT_LANCEMENT
// (identifiant écrit dans la note de la VM ; la CI y met $CI_PIPELINE_URL).
package test

import (
	"context"
	"fmt"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	vmidMin = 2290
	vmidMax = 2299
)

// Plage d'adresses où NetBox alloue (plage « statique » de SANDBOX, M06-E13).
var plageAdresses = netip.MustParsePrefix("10.10.99.0/24")

func envOuDefaut(nom, defaut string) string {
	if v := os.Getenv(nom); v != "" {
		return v
	}
	return defaut
}

// Temps gardé pour détruire la VM à la fin. ATTENTION : quand « go test -timeout » expire, le
// binaire de test PANIQUE et s'arrête sans exécuter ni t.Cleanup ni defer (la VM resterait,
// RB-293). Les attentes du test sont donc bornées par une échéance PLUS COURTE que celle de
// go test, qui laisse ce temps à la destruction.
const margeDestruction = 8 * time.Minute

func TestVmDebian(t *testing.T) {
	ctx := context.Background()
	if fin, ok := t.Deadline(); ok {
		var annuler context.CancelFunc
		ctx, annuler = context.WithDeadline(ctx, fin.Add(-margeDestruction))
		defer annuler()
	}
	pve := nouveauProxmox(t)
	noeud := envOuDefaut("TT_NOEUD", "pve01")

	// 1. Identité de la VM : un nom unique (deux lancements ne se marchent pas dessus) et un VMID
	//    LIBRE de la plage. UniqueID est en base 62 : on le passe en minuscules (règle de nommage).
	nom := "tt-" + strings.ToLower(random.UniqueID())
	vmid := pve.premierVmidLibre(t, vmidMin, vmidMax)
	cles := ssh.GenerateRSAKeyPair(t, 3072)
	t.Logf("VM de test : %s, VMID %d", nom, vmid)

	// 2. Copie de vm-debian/ dans un dossier temporaire : l'état local et .terraform/ du test ne
	//    salissent pas le dépôt, et le chemin relatif du module (../../..) reste juste.
	dossier := test_structure.CopyTerraformFolderToTemp(t, "..", "test/fixtures/vm")

	options := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Explicite : sans cela, Terratest prend « terraform » s'il le trouve dans le PATH.
		TerraformBinary: "tofu",
		TerraformDir:    dossier,
		Vars: map[string]any{
			"nom":           nom,
			"vmid":          vmid,
			"noeud":         noeud,
			"cle_ssh_admin": cles.PublicKey,
			"lancement":     envOuDefaut("TT_LANCEMENT", "poste"),
		},
		NoColor: true,
	})

	// 3. Nettoyage GARANTI, dans cet ordre (t.Cleanup : dernier enregistré, premier exécuté) :
	//    destruction, puis vérification que rien ne reste (Proxmox ET NetBox).
	var ipv4 string
	t.Cleanup(func() {
		assert.False(t, pve.vmExiste(t, vmid), "la VM %d existe encore après destroy : RB-293", vmid)
		if ipv4 != "" {
			assert.Equal(t, 0, nombreAdressesNetbox(t, ipv4), "l'adresse %s est encore dans NetBox après destroy", ipv4)
		}
	})
	t.Cleanup(func() { terraform.Destroy(t, options) })

	terraform.InitAndApply(t, options)

	// 4. Ce que le module promet.
	t.Run("sorties", func(t *testing.T) {
		assert.Equal(t, strconv.Itoa(vmid), terraform.Output(t, options, "vmid"))
		assert.Equal(t, nom, terraform.Output(t, options, "nom"))
		assert.Equal(t, nom+".par1.medisphere.internal", terraform.Output(t, options, "fqdn"))
	})
	ipv4 = terraform.Output(t, options, "ipv4")
	adresse, err := netip.ParseAddr(ipv4)
	require.NoError(t, err, "sortie ipv4 invalide : %q", ipv4)
	require.True(t, plageAdresses.Contains(adresse), "adresse %s hors de SANDBOX", ipv4)

	t.Run("etiquettes-et-pool", func(t *testing.T) {
		vm := pve.ressourceVM(t, vmid)
		assert.Equal(t, "lab/terratest", vm.Pool)
		assert.ElementsMatch(t, []string{"env-m29", "terratest"}, strings.Split(vm.Tags, ";"))
		assert.Equal(t, 0, vm.Template)
	})

	hote := ssh.Host{Hostname: ipv4, SshUserName: "admin", SshKeyPair: cles}

	t.Run("ssh-et-cloud-init", func(t *testing.T) {
		// Le premier démarrage prend une à deux minutes (clone complet, cloud-init). Tentatives
		// bornées par ctx ; « cloud-init status --wait » borné par timeout (il peut attendre sans fin).
		retry.DoWithRetryContext(t, ctx, "connexion SSH", 30, 10*time.Second, func() (string, error) {
			return "", ssh.CheckSshConnectionE(t, hote)
		})
		etat := ssh.CheckSshCommand(t, hote, "timeout 600 cloud-init status --wait")
		assert.Contains(t, etat, "status: done")
		assert.Equal(t, nom, strings.TrimSpace(ssh.CheckSshCommand(t, hote, "hostname")))
		assert.Contains(t, ssh.CheckSshCommand(t, hote, "cat /etc/os-release"), `VERSION_ID="13"`)
		// sudo sans mot de passe pour admin (image dorée, M03) : Ansible en dépend.
		assert.Equal(t, "root", strings.TrimSpace(ssh.CheckSshCommand(t, hote, "sudo -n whoami")))
	})

	t.Run("agent-qemu", func(t *testing.T) {
		// L'agent répond et annonce l'adresse que NetBox a allouée.
		retry.DoWithRetryContext(t, ctx, "agent QEMU", 18, 10*time.Second, func() (string, error) {
			adresses, err := pve.adressesAgent(vmid, noeud)
			if err != nil {
				return "", err
			}
			for _, a := range adresses {
				if a == ipv4 {
					return a, nil
				}
			}
			return "", fmt.Errorf("adresse %s pas encore annoncée par l'agent (vu : %v)", ipv4, adresses)
		})
	})
}
