# ---------------------------------------------------------------
# state.tf
# These resources store Terraform's state file remotely in AWS
# instead of on your local machine.
#
# WHY REMOTE STATE MATTERS:
# By default, Terraform saves a terraform.tfstate file locally.
# That works for solo projects, but has serious problems in the real world:
#   - Two people running apply at the same time can corrupt state
#   - State gets lost if your laptop dies
#   - CI/CD pipelines (GitHub Actions) have no access to your local file
#
# The solution is two AWS resources:
#   1. S3 bucket  — stores the actual state file (versioned + encrypted)
#   2. DynamoDB   — acts as a "lock" so only one apply runs at a time
#
# IMPORTANT: These must be created FIRST (with local state), then we
# configure provider.tf to use them as the backend and migrate state.
# ---------------------------------------------------------------


# S3 bucket to store the Terraform state file.
# This is a separate bucket from our website — it only holds state.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "myterraformproject-jt-tfstate"

  # prevent_destroy stops Terraform from deleting this bucket via
  # terraform destroy. State is critical — losing it means Terraform
  # loses track of all your infrastructure. Protect it at all costs.
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning on the state bucket.
# Every time state changes, S3 keeps a copy of the previous version.
# If state gets corrupted by a bad apply, you can restore a previous version.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt the state file at rest using AES-256.
# State files can contain sensitive values like ARNs, IDs, and resource names,
# so encrypting at rest is a security best practice.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to the state bucket.
# Nobody outside your AWS account should ever be able to read the state file.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking.
# When terraform apply starts, it writes a lock record to this table.
# If another apply tries to run at the same time, it sees the lock and waits.
# Once the first apply finishes, the lock is released.
# This prevents two simultaneous applies from corrupting the state file.
#
# LockID is the key name Terraform expects — don't change it.
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "myterraformproject-jt-tflock"
  billing_mode = "PAY_PER_REQUEST" # no upfront cost — only pay when Terraform reads/writes
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S" # S = String type
  }
}
