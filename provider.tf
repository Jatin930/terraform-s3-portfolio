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
      source  = "hashicorp/aws" # download the AWS provider from HashiCorp's registry
      version = "~> 5.0"        # use any version in the 5.x range (e.g. 5.1, 5.100)
      # the ~> means "compatible with" — avoids breaking changes
    }
  }

  # backend = where Terraform stores its state file.
  # Instead of a local terraform.tfstate file, state is now stored remotely in AWS:
  #   - S3 bucket: stores the actual state file (versioned + encrypted)
  #   - DynamoDB:  locks state during apply so two runs can't corrupt it simultaneously
  #
  # This is required for CI/CD (GitHub Actions has no access to your local machine)
  # and is standard practice on any real team or production project.
  backend "s3" {
    bucket         = "myterraformproject-jt-tfstate" # the S3 bucket we created in state.tf
    key            = "terraform.tfstate"             # the filename/path inside the bucket
    region         = "us-east-1"
    dynamodb_table = "myterraformproject-jt-tflock" # the DynamoDB table for locking
    encrypt        = true                           # encrypt state at rest
  }
}


# Configure the AWS provider with our settings.
# Terraform will use your local AWS credentials (set via "aws configure")
# to authenticate and create resources in this region.
provider "aws" {
  region = "us-east-1" # all resources will be created in US East (N. Virginia)
}
