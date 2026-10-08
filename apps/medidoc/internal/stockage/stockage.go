// Package stockage range les documents dans un compartiment S3 compatible
// (SeaweedFS du socle ou Ceph RGW).
//
// Le code ne dépend que de l'interface ClientS3 : *s3.Client la satisfait en
// production, un faux client en mémoire la satisfait dans les tests.
package stockage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// Prefixe des clés d'objet : documents/<id>.
const Prefixe = "documents/"

// ErrIntrouvable : le document demandé n'existe pas.
var ErrIntrouvable = errors.New("document introuvable")

// ClientS3 est le sous-ensemble de *s3.Client utilisé par MédiDoc.
type ClientS3 interface {
	PutObject(ctx context.Context, in *s3.PutObjectInput, opts ...func(*s3.Options)) (*s3.PutObjectOutput, error)
	GetObject(ctx context.Context, in *s3.GetObjectInput, opts ...func(*s3.Options)) (*s3.GetObjectOutput, error)
	HeadBucket(ctx context.Context, in *s3.HeadBucketInput, opts ...func(*s3.Options)) (*s3.HeadBucketOutput, error)
	ListObjectsV2(ctx context.Context, in *s3.ListObjectsV2Input, opts ...func(*s3.Options)) (*s3.ListObjectsV2Output, error)
}

// Document décrit un document stocké.
type Document struct {
	ID          string    `json:"id"`
	Patient     string    `json:"patient,omitempty"`
	NomFichier  string    `json:"nom_fichier,omitempty"`
	TypeContenu string    `json:"type_contenu,omitempty"`
	Taille      int64     `json:"taille"`
	ModifieLe   time.Time `json:"modifie_le,omitzero"`
}

// Objet est un document lu, avec son contenu à fermer après usage.
type Objet struct {
	Document
	Corps io.ReadCloser
}

// Depot range les documents dans un compartiment.
type Depot struct {
	client ClientS3
	bucket string
}

// NouveauDepot crée un dépôt sur le compartiment bucket.
func NouveauDepot(client ClientS3, bucket string) *Depot {
	return &Depot{client: client, bucket: bucket}
}

// Verifier contrôle que le compartiment existe et est accessible (HeadBucket).
func (d *Depot) Verifier(ctx context.Context) error {
	_, err := d.client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(d.bucket)})
	return err
}

// Enregistrer écrit le contenu sous documents/<doc.ID>.
//
// Les métadonnées S3 « utilisateur » n'acceptent que de l'ASCII : le nom de
// fichier (souvent accentué) est donc encodé façon URL.
func (d *Depot) Enregistrer(ctx context.Context, doc Document, contenu []byte) error {
	_, err := d.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(d.bucket),
		Key:    aws.String(Prefixe + doc.ID),
		// Un bytes.Reader est « rejouable » : le SDK peut calculer la signature
		// du contenu et réessayer l'envoi en cas d'erreur réseau.
		Body:          bytes.NewReader(contenu),
		ContentLength: aws.Int64(int64(len(contenu))),
		ContentType:   aws.String(doc.TypeContenu),
		Metadata: map[string]string{
			"patient":     url.QueryEscape(doc.Patient),
			"nom-fichier": url.QueryEscape(doc.NomFichier),
		},
	})
	if err != nil {
		return fmt.Errorf("écriture de %s : %w", doc.ID, err)
	}
	return nil
}

// Lire ouvre le document id. L'appelant ferme Objet.Corps.
func (d *Depot) Lire(ctx context.Context, id string) (*Objet, error) {
	out, err := d.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(d.bucket),
		Key:    aws.String(Prefixe + id),
	})
	if err != nil {
		if estIntrouvable(err) {
			return nil, ErrIntrouvable
		}
		return nil, fmt.Errorf("lecture de %s : %w", id, err)
	}
	doc := Document{
		ID:          id,
		Patient:     decoder(out.Metadata["patient"]),
		NomFichier:  decoder(out.Metadata["nom-fichier"]),
		TypeContenu: aws.ToString(out.ContentType),
		Taille:      aws.ToInt64(out.ContentLength),
		ModifieLe:   aws.ToTime(out.LastModified),
	}
	return &Objet{Document: doc, Corps: out.Body}, nil
}

// Lister renvoie au plus limite documents (une seule page S3, sans métadonnées :
// les obtenir demanderait une requête HeadObject par document).
func (d *Depot) Lister(ctx context.Context, limite int32) ([]Document, error) {
	out, err := d.client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket:  aws.String(d.bucket),
		Prefix:  aws.String(Prefixe),
		MaxKeys: aws.Int32(limite),
	})
	if err != nil {
		return nil, fmt.Errorf("liste du compartiment : %w", err)
	}
	docs := make([]Document, 0, len(out.Contents))
	for _, o := range out.Contents {
		docs = append(docs, Document{
			ID:        strings.TrimPrefix(aws.ToString(o.Key), Prefixe),
			Taille:    aws.ToInt64(o.Size),
			ModifieLe: aws.ToTime(o.LastModified),
		})
	}
	return docs, nil
}

func estIntrouvable(err error) bool {
	var nsk *types.NoSuchKey
	if errors.As(err, &nsk) {
		return true
	}
	// Certains serveurs compatibles renvoient un 404 sans le code NoSuchKey.
	var re *awshttp.ResponseError
	return errors.As(err, &re) && re.HTTPStatusCode() == 404
}

func decoder(v string) string {
	if s, err := url.QueryUnescape(v); err == nil {
		return s
	}
	return v
}
