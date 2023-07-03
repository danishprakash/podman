package generate

// KubeOptions are optional options for generating kube YAML files
//
//go:generate go run ../generator/generator.go KubeOptions
type KubeOptions struct {
	// Service - generate YAML for a Kubernetes _service_ object.
	Service *bool
	// Type - the k8s kind to be generated i.e Pod or Deployment
	Type *string
	// Replicas - the value to set in the replicas field for a Deployment
	Replicas *int32
	// NoTrunc - don't truncate annotations to the Kubernetes maximum length of 63 characters
	NoTrunc *bool
}

// SystemdOptions are optional options for generating systemd files
//
//go:generate go run ../generator/generator.go SystemdOptions
type SystemdOptions struct {
	// Name - use container/pod name instead of its ID.
	UseName *bool
	// New - create a new container instead of starting a new one.
	New *bool
	// NoHeader - Removes autogenerated by Podman and timestamp if set to true
	NoHeader *bool
	// TemplateUnitFile - Create a template unit file that uses the identity specifiers
	TemplateUnitFile *bool
	// RestartPolicy - systemd restart policy.
	RestartPolicy *string
	// RestartSec - systemd service restartsec. Configures the time to sleep before restarting a service.
	RestartSec *uint
	// StartTimeout - time when starting the container.
	StartTimeout *uint
	// StopTimeout - time when stopping the container.
	StopTimeout *uint
	// ContainerPrefix - systemd unit name prefix for containers
	ContainerPrefix *string
	// PodPrefix - systemd unit name prefix for pods
	PodPrefix *string
	// Separator - systemd unit name separator between name/id and prefix
	Separator *string
	// Wants - systemd wants list for the container or pods
	Wants *[]string
	// After - systemd after list for the container or pods
	After *[]string
	// Requires - systemd requires list for the container or pods
	Requires *[]string
	// AdditionalEnvVariables - Sets environment variables to a systemd unit file
	AdditionalEnvVariables *[]string
}
