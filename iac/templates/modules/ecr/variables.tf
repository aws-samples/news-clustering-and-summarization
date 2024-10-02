variable "build_script_path" {
  type        = string
  description = "Path to the Build Script"
}

variable "business_logic_path" {
  type        = string
  description = "Path to the Business Logic"
}

variable "ecr_name" {
  type        = string
  description = "Name of the ECR Repository"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
}

variable "aws_kms_key_arn" {
  type        = string
  description = "KMS Key ARN"
}
variable "ecr_count_number" {
  type        = number
  description = "Number of ECR Images to Keep"
}

variable "ecr_base_arn" {
  type        = string
  description = "Base ARN for ECR Images"
}
variable "region" {
  type        = string
  description = "AWS Region"
}