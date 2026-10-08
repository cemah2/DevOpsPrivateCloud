package stockage

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestChargerCA(t *testing.T) {
	cle, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	modele := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "MédiSphère Racine de test"},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign,
	}
	der, err := x509.CreateCertificate(rand.Reader, modele, modele, &cle.PublicKey, cle)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	valide := filepath.Join(dir, "ca.pem")
	if err := os.WriteFile(valide, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ChargerCA(valide); err != nil {
		t.Fatalf("CA valide refusée : %v", err)
	}

	invalide := filepath.Join(dir, "pas-un-pem.txt")
	_ = os.WriteFile(invalide, []byte("bonjour"), 0o600)
	if _, err := ChargerCA(invalide); err == nil {
		t.Fatal("fichier sans certificat accepté")
	}
	if _, err := ChargerCA(filepath.Join(dir, "absent.pem")); err == nil {
		t.Fatal("fichier absent accepté")
	}
	if _, err := NouveauClient(context.Background(), ParamsClient{
		Endpoint: "https://s3.par1.medisphere.internal", Region: "us-east-1", CAFile: valide,
	}); err != nil {
		t.Fatalf("création du client avec CA : %v", err)
	}
}
