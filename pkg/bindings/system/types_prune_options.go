// Code generated by go generate; DO NOT EDIT.
package system

import (
	"net/url"

	"github.com/containers/podman/v5/pkg/bindings/internal/util"
)

// Changed returns true if named field has been set
func (o *PruneOptions) Changed(fieldName string) bool {
	return util.Changed(o, fieldName)
}

// ToParams formats struct fields to be passed to API service
func (o *PruneOptions) ToParams() (url.Values, error) {
	return util.ToParams(o)
}

// WithAll set field All to given value
func (o *PruneOptions) WithAll(value bool) *PruneOptions {
	o.All = &value
	return o
}

// GetAll returns value of field All
func (o *PruneOptions) GetAll() bool {
	if o.All == nil {
		var z bool
		return z
	}
	return *o.All
}

// WithFilters set field Filters to given value
func (o *PruneOptions) WithFilters(value map[string][]string) *PruneOptions {
	o.Filters = value
	return o
}

// GetFilters returns value of field Filters
func (o *PruneOptions) GetFilters() map[string][]string {
	if o.Filters == nil {
		var z map[string][]string
		return z
	}
	return o.Filters
}

// WithVolumes set field Volumes to given value
func (o *PruneOptions) WithVolumes(value bool) *PruneOptions {
	o.Volumes = &value
	return o
}

// GetVolumes returns value of field Volumes
func (o *PruneOptions) GetVolumes() bool {
	if o.Volumes == nil {
		var z bool
		return z
	}
	return *o.Volumes
}

// WithExternal set field External to given value
func (o *PruneOptions) WithExternal(value bool) *PruneOptions {
	o.External = &value
	return o
}

// GetExternal returns value of field External
func (o *PruneOptions) GetExternal() bool {
	if o.External == nil {
		var z bool
		return z
	}
	return *o.External
}

// WithBuild set field Build to given value
func (o *PruneOptions) WithBuild(value bool) *PruneOptions {
	o.Build = &value
	return o
}

// GetBuild returns value of field Build
func (o *PruneOptions) GetBuild() bool {
	if o.Build == nil {
		var z bool
		return z
	}
	return *o.Build
}
