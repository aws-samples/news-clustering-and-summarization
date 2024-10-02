variable "function_name" {
  type        = string
  description = "Name of the lambda function"
}

variable "handler_name" {
  type        = string
  description = "Name of the function handler"
}

variable "runtime" {
  type        = string
  default     = "python3.9"
  description = "Lambda runtime e.g. dotnet, python3.9 etc"
}

variable "description" {
  type        = string
  description = "Description of the function"
}

variable "resource_policy" {
  type        = string
  description = "Lambda role IAM policy document"
}

variable "environment_variables" {
  type        = map(any)
  description = "Optional map of environment variables"
  default     = { DUMMY = "" }
}

variable "memory_size" {
  default     = 512
  description = "Memory size for the function"
  type        = number
}

variable "subnet_ids" {
  type        = list(string)
  default     = []
  description = "List of subnet id(s) to which lambda should be attached"
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "List of security group id(s) to which lambda should be attached"
}

variable "code_archive" {
  type        = string
  default     = null
  description = "Zip file with lambda's code package"
}