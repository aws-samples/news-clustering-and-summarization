terraform {
  required_version = ">= 1.4.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.4"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.1"
    }
  }
}