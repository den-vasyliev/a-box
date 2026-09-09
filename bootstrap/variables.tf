variable "cluster_name" {
  description = "Cluster Name"
  type        = string
  default     = "abox"
}

variable "oci_registry" {
  description = "OCI registry base URL"
  type        = string
  default     = "oci://ghcr.io/den-vasyliev/abox"
}

variable "releases_version" {
  description = "Default tag for releases OCI artifact bootstrap"
  type        = string
  default     = "0.1.0"
}

variable "bootstrap_revision" {
  description = "Bump to force the flux-operator bootstrap Job to re-run without an input change"
  type        = number
  default     = 1
}
