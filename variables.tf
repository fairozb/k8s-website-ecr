variable "aws_region" {
  description = "AWS region to deploy in."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for AWS resources."
  type        = string
  default     = "k8s-website-ecr"
}

variable "instance_type" {
  description = "EC2 size. k3s needs some memory; t3.medium is a good fit."
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair (for SSH)."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32."
  type        = string
}

variable "image_tag" {
  description = "The ECR image tag to deploy (must be pushed before EC2 boots)."
  type        = string
  default     = "v1"
}
