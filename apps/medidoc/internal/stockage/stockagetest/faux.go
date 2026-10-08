// Package stockagetest fournit un faux client S3 en mémoire pour les tests.
package stockagetest

import (
	"bytes"
	"context"
	"io"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type objet struct {
	contenu     []byte
	typeContenu string
	meta        map[string]string
	modifie     time.Time
}

// FauxS3 implémente stockage.ClientS3 en mémoire.
type FauxS3 struct {
	mu      sync.Mutex
	objets  map[string]objet
	EnPanne error // si non nil, toutes les opérations échouent avec cette erreur
}

// Nouveau crée un faux service S3 vide.
func Nouveau() *FauxS3 { return &FauxS3{objets: map[string]objet{}} }

// Nombre renvoie le nombre d'objets stockés.
func (f *FauxS3) Nombre() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.objets)
}

func (f *FauxS3) PutObject(_ context.Context, in *s3.PutObjectInput, _ ...func(*s3.Options)) (*s3.PutObjectOutput, error) {
	if f.EnPanne != nil {
		return nil, f.EnPanne
	}
	contenu, err := io.ReadAll(in.Body)
	if err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.objets[aws.ToString(in.Key)] = objet{
		contenu: contenu, typeContenu: aws.ToString(in.ContentType), meta: in.Metadata, modifie: time.Now().UTC(),
	}
	return &s3.PutObjectOutput{}, nil
}

func (f *FauxS3) GetObject(_ context.Context, in *s3.GetObjectInput, _ ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	if f.EnPanne != nil {
		return nil, f.EnPanne
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	o, ok := f.objets[aws.ToString(in.Key)]
	if !ok {
		return nil, &types.NoSuchKey{Message: aws.String("The specified key does not exist.")}
	}
	return &s3.GetObjectOutput{
		Body:          io.NopCloser(bytes.NewReader(o.contenu)),
		ContentLength: aws.Int64(int64(len(o.contenu))),
		ContentType:   aws.String(o.typeContenu),
		Metadata:      o.meta,
		LastModified:  aws.Time(o.modifie),
	}, nil
}

func (f *FauxS3) HeadBucket(_ context.Context, _ *s3.HeadBucketInput, _ ...func(*s3.Options)) (*s3.HeadBucketOutput, error) {
	if f.EnPanne != nil {
		return nil, f.EnPanne
	}
	return &s3.HeadBucketOutput{}, nil
}

func (f *FauxS3) ListObjectsV2(_ context.Context, in *s3.ListObjectsV2Input, _ ...func(*s3.Options)) (*s3.ListObjectsV2Output, error) {
	if f.EnPanne != nil {
		return nil, f.EnPanne
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	cles := make([]string, 0, len(f.objets))
	for k := range f.objets {
		if strings.HasPrefix(k, aws.ToString(in.Prefix)) {
			cles = append(cles, k)
		}
	}
	sort.Strings(cles) // S3 renvoie les clés dans l'ordre lexicographique
	if max := int(aws.ToInt32(in.MaxKeys)); max > 0 && len(cles) > max {
		cles = cles[:max]
	}
	out := &s3.ListObjectsV2Output{}
	for _, k := range cles {
		o := f.objets[k]
		out.Contents = append(out.Contents, types.Object{
			Key: aws.String(k), Size: aws.Int64(int64(len(o.contenu))), LastModified: aws.Time(o.modifie),
		})
	}
	return out, nil
}
