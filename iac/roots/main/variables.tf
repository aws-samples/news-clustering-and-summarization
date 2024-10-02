# Copyright 2023 Amazon.com and its affiliates; all rights reserved.
# This file is Amazon Web Services Content and may not be duplicated or distributed without permission.

variable "app_name" {
  type        = string
  description = "Name of the app"
}

variable "env_name" {
  type        = string
  description = "Name of the environment"
}

# VPC Variables
variable "cidr_block" {
  description = "The CIDR block for the VPC. Default value is a valid CIDR, but not acceptable by AWS and should be overridden"
  type        = string
  default     = "0.0.0.0/0"
}

variable "public_subnet" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "private_subnet" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "lambda_code_path" {
  description = "Relative path to the Lambda functions' code"
  type        = string
  default     = "../../../business_logic/lambdas"
}

variable "build_script_path" {
  description = "Relative path to the Build functions' code"
  type        = string
  default     = "../../../build-script"
}

variable "model_name" {
  description = "'bge', 'titan', 'mistralinstruct'"
  type        = string
  default     = "titan"
}

variable "max_length_embedding" {
  description = "Max length on the encode call within the Sagemaker endpoint: 512, 1024, 2048, 4096"
  type        = string
  default     = "512"
}

variable "embedding_endpoint_instance_type" {
  description = "Instance type for embedding endpoint"
  type        = string
  # default     = "ml.inf2.xlarge"
  default = "ml.g5.2xlarge"
  # default = "ml.g5.12xlarge"
}

variable "embedding_endpoint_instance_count" {
  description = "Number of instances of embedding endpoint"
  type        = number
  default     = 2
}

/* 
variable "azs" {
  description = "A list of availability zones in the region"
  type        = list(string)
  default     = []
}

variable "embedding_strategy" {
  description = "'concat' or 'pooling'"
  type        = string
  default     = "concat"
}

variable "pooling_strategy" {
  description = "'mean' or 'max'"
  type        = string
  default     = "mean"
}

variable "min_embedding_instance_count" {
  description = "Number of instances of embedding endpoint"
  type        = number
  default     = 1
}

variable "max_embedding_instance_count" {
  description = "Number of instances of embedding endpoint"
  type        = number
  default     = 8
}
*/

variable "max_articles_embedding_endpoint" {
  description = "Maximum number of articles the embedding endpoint can take in one API call"
  type        = number
  default     = 200
}

variable "instance_type" {
  type        = string
  default     = "c7g.4xlarge"
  description = "Instance type for the for the clustering compute"
}

variable "volume_size" {
  type        = number
  description = "Volume Size of the EBS Volume"
  default     = 35
}

variable "number_of_nodes" {
  type        = number
  description = "Number of Nodes Needed for the clustering compute"
  default     = 1
}

variable "auto_verified_attributes" {
  type        = list(any)
  default     = ["email"]
  description = "Attributes to be auto-verified. Valid values: email, phone_number."
}

variable "mfa_configuration" {
  type        = string
  default     = "OFF"
  description = "Multi-Factor Authentication (MFA) configuration for the User Pool. Defaults of OFF. Valid values are OFF, ON and OPTIONAL."
}

variable "advanced_security_mode" {
  type        = string
  default     = "OFF"
  description = "Mode for advanced security, must be one of OFF, AUDIT or ENFORCED."
}

variable "allow_software_mfa_token" {
  description = "(Optional) Boolean whether to enable software token Multi-Factor (MFA) tokens, such as Time-based One-Time Password (TOTP). To disable software token MFA when 'sms_configuration' is not present, the 'mfa_configuration' argument must be set to OFF and the 'software_token_mfa_configuration' configuration block must be fully removed."
  type        = bool
  default     = false
}

variable "case_sensitive" {
  type        = bool
  default     = true
  description = "Whether username case sensitivity will be applied for all users in the user pool through Cognito APIs."
}

variable "sms_authentication_message" {
  type        = string
  default     = "Your username is {username}. Sign up at {####}"
  description = "String representing the SMS authentication message. The Message must contain the {####} placeholder, which will be replaced with the code."
}

variable "minimum_length" {
  type        = number
  description = "(Optional) The minimum length of the password policy that you have set."
  default     = 6
}

variable "require_lowercase" {
  type        = bool
  description = "(Optional) Whether you have required users to use at least one lowercase letter in their password."
  default     = false
}

variable "require_numbers" {
  type        = bool
  default     = false
  description = "Whether you have required users to use at least one number in their password."
}

variable "require_symbols" {
  type        = bool
  default     = false
  description = "Whether you have required users to use at least one symbol in their password."
}

variable "require_uppercase" {
  type        = bool
  default     = false
  description = "Whether you have required users to use at least one uppercase letter in their password."
}

variable "temporary_password_validity_days" {
  type        = number
  description = "(Optional) In the password policy you have set, refers to the number of days a temporary password is valid. If the user does not sign-in during this time, their password will need to be reset by an administrator."
  default     = 100
}

variable "cognito_users" {
  description = "A map of user attributes for each user in the User Pool. Each attribute is a name-value pair."
  type = map(object({
    name     = string
    email    = string
    password = string
  }))
  default = {
    user1 = {
      name     = "aws-user"
      email    = "donotreply@amazon.com"
      password = "awsiscool$"
    }
  }
}

variable "front_end_path" {
  description = "Relative path to the Lambda functions' code"
  type        = string
  default     = "../../../front_end"
}

variable "task_cpu" {
  type        = number
  description = "VCPUs for Task"
  default     = 512
}

variable "task_memory" {
  type        = number
  description = "Memory for Task"
  default     = 2048
}

variable "launch_type" {
  type        = string
  description = "Launch type for the service."
  default     = "FARGATE"
}

variable "desired_count" {
  type        = number
  description = "The number of instances of the task definition to place and keep running"
  default     = 1
}