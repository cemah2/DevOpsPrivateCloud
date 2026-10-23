// Package test contient le test d'intégration Terratest du module vm-debian (M29-E08).
//
// Les fichiers de test portent l'étiquette de construction « integration » : un simple
// « go test ./... » ne crée aucune VM. Lancement réel :
//
//	go test -tags integration -run TestVmDebian -timeout 30m -v ./...
package test
