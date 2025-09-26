variable "region" {
  type    = string
  default = "us-east-1"
}

# If your environment ever uses different names, change these defaults.
variable "existing_iam_role_name" {
  type        = string
  description = "Pre-existing IAM role to attach to EC2"
  default     = "LabRole"
}

variable "existing_instance_profile_name" {
  type        = string
  description = "Pre-existing instance profile that wraps the IAM role"
  default     = "LabInstanceProfile"
}