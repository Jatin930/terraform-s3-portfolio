# ---------------------------------------------------------------
# provider.tf
# A "provider" tells Terraform WHICH cloud platform to talk to.
# Think of it like installing a plugin — without it, Terraform
# wouldn't know how to create AWS resources.
# ---------------------------------------------------------------


terraform {
  # required_providers lists every provider (cloud plugin) this project needs.
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # download the AWS provider from HashiCorp's registry
      version = "~> 5.0"         # use any version in the 5.x range (e.g. 5.1, 5.100)
                                  # the ~> means "compatible with" — avoids breaking changes
    }
  }
}


# Configure the AWS provider with our settings.
# Terraform will use your local AWS credentials (set via "aws configure")
# to authenticate and create resources in this region.
provider "aws" {
  region = "us-east-1"  # all resources will be created in US East (N. Virginia)
}
