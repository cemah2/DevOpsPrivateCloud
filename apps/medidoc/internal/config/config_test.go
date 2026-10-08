package config

import (
	"log/slog"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

var base = map[string]string{
	"MEDIDOC_S3_ENDPOINT": "https://s3.par1.medisphere.internal",
	"MEDIDOC_S3_BUCKET":   "medidoc-documents",
}

func avec(cles ...string) map[string]string {
	m := map[string]string{}
	for k, v := range base {
		m[k] = v
	}
	for i := 0; i+1 < len(cles); i += 2 {
		m[cles[i]] = cles[i+1]
	}
	return m
}

func TestValeursParDefaut(t *testing.T) {
	c, err := Charger(env(base))
	if err != nil {
		t.Fatal(err)
	}
	if c.Port != 8080 || c.Region != "us-east-1" || c.MaxOctets != 10<<20 || c.LogLevel != slog.LevelInfo {
		t.Fatalf("défauts inattendus : %+v", c)
	}
}

func TestSurcharges(t *testing.T) {
	c, err := Charger(env(avec("MEDIDOC_PORT", "9090", "MEDIDOC_MAX_MB", "25", "MEDIDOC_LOG_LEVEL", "debug")))
	if err != nil {
		t.Fatal(err)
	}
	if c.Port != 9090 || c.MaxOctets != 25<<20 || c.LogLevel != slog.LevelDebug {
		t.Fatalf("surcharges ignorées : %+v", c)
	}
}

func TestErreurs(t *testing.T) {
	cas := map[string]map[string]string{
		"MEDIDOC_S3_BUCKET":   {"MEDIDOC_S3_ENDPOINT": "https://s3"},
		"http://":             avec("MEDIDOC_S3_ENDPOINT", "s3.par1.medisphere.internal"),
		"MEDIDOC_PORT":        avec("MEDIDOC_PORT", "huit"),
		"MEDIDOC_MAX_MB":      avec("MEDIDOC_MAX_MB", "0"),
		"MEDIDOC_LOG_LEVEL":   avec("MEDIDOC_LOG_LEVEL", "bavard"),
		"MEDIDOC_S3_ENDPOINT": {},
	}
	for attendu, m := range cas {
		_, err := Charger(env(m))
		if err == nil || !strings.Contains(err.Error(), attendu) {
			t.Errorf("attendu une erreur mentionnant %q, obtenu %v", attendu, err)
		}
	}
}
