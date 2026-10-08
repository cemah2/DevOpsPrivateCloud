// Package config lit la configuration de MédiDoc dans les variables d'environnement.
//
// Les identifiants S3 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) ne passent pas
// par ici : le SDK AWS les lit lui-même dans l'environnement.
package config

import (
	"fmt"
	"log/slog"
	"strconv"
	"strings"
)

// Config regroupe les réglages de MédiDoc.
type Config struct {
	Port      int        // MEDIDOC_PORT (8080)
	Endpoint  string     // MEDIDOC_S3_ENDPOINT, obligatoire (https://s3-01.par1.medisphere.internal:8333)
	Bucket    string     // MEDIDOC_S3_BUCKET, obligatoire
	Region    string     // MEDIDOC_S3_REGION (us-east-1)
	CAFile    string     // MEDIDOC_CA_FILE, optionnel : CA ajoutée aux autorités du système
	MaxOctets int64      // MEDIDOC_MAX_MB (10) converti en octets
	LogLevel  slog.Level // MEDIDOC_LOG_LEVEL (info)
	Version   string     // MEDIDOC_VERSION, sinon la version compilée
}

// Charger construit la configuration à partir de getenv (os.Getenv en production).
func Charger(getenv func(string) string) (Config, error) {
	c := Config{
		Port:     8080,
		Endpoint: getenv("MEDIDOC_S3_ENDPOINT"),
		Bucket:   getenv("MEDIDOC_S3_BUCKET"),
		Region:   valeurOu(getenv("MEDIDOC_S3_REGION"), "us-east-1"),
		CAFile:   getenv("MEDIDOC_CA_FILE"),
		Version:  getenv("MEDIDOC_VERSION"),
	}
	var manquantes []string
	if c.Endpoint == "" {
		manquantes = append(manquantes, "MEDIDOC_S3_ENDPOINT")
	}
	if c.Bucket == "" {
		manquantes = append(manquantes, "MEDIDOC_S3_BUCKET")
	}
	if len(manquantes) > 0 {
		return c, fmt.Errorf("variable(s) obligatoire(s) absente(s) : %s", strings.Join(manquantes, ", "))
	}
	if !strings.HasPrefix(c.Endpoint, "http://") && !strings.HasPrefix(c.Endpoint, "https://") {
		return c, fmt.Errorf("MEDIDOC_S3_ENDPOINT doit commencer par http:// ou https:// : %q", c.Endpoint)
	}

	if v := getenv("MEDIDOC_PORT"); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil || p < 1 || p > 65535 {
			return c, fmt.Errorf("MEDIDOC_PORT invalide : %q", v)
		}
		c.Port = p
	}

	maxMo := int64(10)
	if v := getenv("MEDIDOC_MAX_MB"); v != "" {
		m, err := strconv.ParseInt(v, 10, 64)
		if err != nil || m < 1 || m > 1024 {
			return c, fmt.Errorf("MEDIDOC_MAX_MB invalide (1 à 1024) : %q", v)
		}
		maxMo = m
	}
	c.MaxOctets = maxMo << 20

	if v := getenv("MEDIDOC_LOG_LEVEL"); v != "" {
		if err := c.LogLevel.UnmarshalText([]byte(v)); err != nil {
			return c, fmt.Errorf("MEDIDOC_LOG_LEVEL invalide (debug, info, warn, error) : %q", v)
		}
	}
	return c, nil
}

func valeurOu(v, defaut string) string {
	if v == "" {
		return defaut
	}
	return v
}
