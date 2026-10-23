// plateforme/tofu-modules — vm-debian/test/vm_debian_test.go (EXTRAIT M29-E21, INC-5621)
// Les trois lignes qui comptent, dans cet ordre, au début du test de M29-E08 :
//   1. nom et étiquettes OBLIGATOIRES (tt-<suffixe>, env-m29 ET terratest) : le nettoyeur s'y fie ;
//   2. defer terraform.Destroy enregistré AVANT InitAndApply : si l'application échoue à mi-chemin
//      (VM créée, cloud-init en erreur), la destruction a quand même lieu ;
//   3. pas de protection (le module a « protection » en variable : on la force à false).
// Rappel : un defer ne protège PAS d'une panique de go test (-timeout dépassé) ni d'un SIGKILL du job :
// c'est le rôle du délai explicite (.gitlab-ci.yml) et du nettoyeur planifié.
// Fonctions de Terratest 1.0 (module github.com/gruntwork-io/terratest/modules/terraform) : à relire
// avec « go doc » sur la version installée (changements d'API depuis les 0.x non vérifiés à la rédaction).
// Les variables passées (nom, vm_id, etiquettes, protection) sont celles du module vm-debian (M05-E13) :
// l'exemple exemples/minimal doit les déclarer et les transmettre au module.
package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestVmDebian(t *testing.T) {
	t.Parallel()

	dossier := test_structure.CopyTerraformFolderToTemp(t, "..", "exemples/minimal")
	suffixe := strings.ToLower(random.UniqueId())
	vmid := 2290 + random.Random(0, 9) // plage Terratest ; collision possible : resource_group en CI

	options := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir:    dossier,
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"nom":        fmt.Sprintf("tt-%s", suffixe),
			"vm_id":      vmid,
			"etiquettes": []string{"env-m29", "terratest"},
			"protection": false,
		},
	})

	defer terraform.Destroy(t, options) // AVANT InitAndApply
	terraform.InitAndApply(t, options)

	// … vérifications de M29-E08 (sorties, SSH, cloud-init) …
}
