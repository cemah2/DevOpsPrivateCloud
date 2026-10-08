package stockage

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// ParamsClient : réglages de connexion au service S3.
type ParamsClient struct {
	Endpoint string // https://s3-01.par1.medisphere.internal:8333
	Region   string
	CAFile   string // optionnel
}

// NouveauClient crée un client S3 pour un service compatible (SeaweedFS, Ceph RGW).
func NouveauClient(ctx context.Context, p ParamsClient) (*s3.Client, error) {
	opts := []func(*awsconfig.LoadOptions) error{awsconfig.WithRegion(p.Region)}
	if p.CAFile != "" {
		racines, err := ChargerCA(p.CAFile)
		if err != nil {
			return nil, err
		}
		client := awshttp.NewBuildableClient().WithTransportOptions(func(tr *http.Transport) {
			tr.TLSClientConfig = &tls.Config{RootCAs: racines, MinVersion: tls.VersionTLS12}
		})
		opts = append(opts, awsconfig.WithHTTPClient(client))
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("configuration du SDK AWS : %w", err)
	}
	// Depuis début 2025, le SDK ajoute par défaut des sommes de contrôle CRC
	// (en-têtes « trailer ») que tous les services compatibles S3 ne gèrent pas.
	// On ne les envoie que lorsque l'opération l'exige.
	cfg.RequestChecksumCalculation = aws.RequestChecksumCalculationWhenRequired
	cfg.ResponseChecksumValidation = aws.ResponseChecksumValidationWhenRequired

	return s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(p.Endpoint)
		// Style « chemin » : https://s3.exemple/<bucket>/<clé>, et non
		// https://<bucket>.s3.exemple/<clé> qui demanderait un DNS joker.
		o.UsePathStyle = true
	}), nil
}

// ChargerCA renvoie les autorités du système complétées par celles du fichier PEM.
func ChargerCA(chemin string) (*x509.CertPool, error) {
	pem, err := os.ReadFile(chemin) // #nosec G304 -- chemin fourni par l'exploitant
	if err != nil {
		return nil, fmt.Errorf("lecture de MEDIDOC_CA_FILE : %w", err)
	}
	racines, err := x509.SystemCertPool()
	if err != nil || racines == nil {
		racines = x509.NewCertPool()
	}
	if !racines.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("aucun certificat PEM valide dans %s", chemin)
	}
	return racines, nil
}
