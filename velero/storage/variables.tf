variable "project_id" {
  default = "lithe-key-416318"
  description = "project id"
}

variable "region" {
  default = "asia-south1"
  description = "region"
}

variable "credentials_file" {
  default = "../gcpServiceAccount/credentials.json"
  description = "credential file name"
}
