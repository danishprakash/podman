package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"

	"github.com/containers/image/v5/docker/reference"
	"github.com/containers/image/v5/image"
	"github.com/containers/image/v5/types"
	"github.com/pkg/errors"
)

// Image is a Docker-specific implementation of types.ImageCloser with a few extra methods
// which are specific to Docker.
type Image struct {
	types.ImageCloser
	src *dockerImageSource
}

// newImage returns a new Image interface type after setting up
// a client to the registry hosting the given image.
// The caller must call .Close() on the returned Image.
func newImage(ctx context.Context, sys *types.SystemContext, ref dockerReference) (types.ImageCloser, error) {
	s, err := newImageSource(ctx, sys, ref)
	if err != nil {
		return nil, err
	}
	img, err := image.FromSource(ctx, sys, s)
	if err != nil {
		return nil, err
	}
	return &Image{ImageCloser: img, src: s}, nil
}

// SourceRefFullName returns a fully expanded name for the repository this image is in.
func (i *Image) SourceRefFullName() string {
	return i.src.logicalRef.ref.Name()
}

// GetRepositoryTags list all tags available in the repository. The tag
// provided inside the ImageReference will be ignored. (This is a
// backward-compatible shim method which calls the module-level
// GetRepositoryTags)
func (i *Image) GetRepositoryTags(ctx context.Context) ([]string, error) {
	return GetRepositoryTags(ctx, i.src.c.sys, i.src.logicalRef)
}

// GetRepositoryTags list all tags available in the repository. The tag
// provided inside the ImageReference will be ignored.
func GetRepositoryTags(ctx context.Context, sys *types.SystemContext, ref types.ImageReference) ([]string, error) {
	dr, ok := ref.(dockerReference)
	if !ok {
		return nil, errors.Errorf("ref must be a dockerReference")
	}

	path := fmt.Sprintf(tagsPath, reference.Path(dr.ref))
	client, err := newDockerClientFromRef(sys, dr, false, "pull")
	if err != nil {
		return nil, errors.Wrap(err, "failed to create client")
	}

	tags := make([]string, 0)

	for {
		res, err := client.makeRequest(ctx, "GET", path, nil, nil, v2Auth, nil)
		if err != nil {
			return nil, err
		}
		defer res.Body.Close()
		if err := httpResponseToError(res, "Error fetching tags list"); err != nil {
			return nil, err
		}

		var tagsHolder struct {
			Tags []string
		}
		if err = json.NewDecoder(res.Body).Decode(&tagsHolder); err != nil {
			return nil, err
		}
		for _, tag := range tagsHolder.Tags {
			if _, err := reference.WithTag(dr.ref, tag); err != nil { // Ensure the tag does not contain unexpected values
				return nil, fmt.Errorf("registry returned invalid tag %q: %w", tag, err)
			}
			tags = append(tags, tag)
		}

		link := res.Header.Get("Link")
		if link == "" {
			break
		}

		linkURLStr := strings.Trim(strings.Split(link, ";")[0], "<>")
		linkURL, err := url.Parse(linkURLStr)
		if err != nil {
			return tags, err
		}

		// can be relative or absolute, but we only want the path (and I
		// guess we're in trouble if it forwards to a new place...)
		path = linkURL.Path
		if linkURL.RawQuery != "" {
			path += "?"
			path += linkURL.RawQuery
		}
	}
	return tags, nil
}
