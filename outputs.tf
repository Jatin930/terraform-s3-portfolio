# ---------------------------------------------------------------
# outputs.tf
# Outputs display useful information after Terraform runs.
# Think of them like return values — Terraform prints these
# to the terminal after apply so you can find key details
# without digging through the AWS console.
# ---------------------------------------------------------------


# The CloudFront URL — HTTPS, globally cached, the URL to share publicly.
# Note: CloudFront takes ~2 minutes to fully deploy after apply completes.
output "cloudfront_url" {
  description = "CloudFront distribution URL (HTTPS, globally cached)"
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

# The state S3 bucket name — useful to confirm remote state is configured.
output "state_bucket" {
  description = "S3 bucket storing Terraform remote state"
  value       = aws_s3_bucket.terraform_state.bucket
}

# The DynamoDB table name — useful to confirm state locking is in place.
output "state_lock_table" {
  description = "DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.terraform_state_lock.name
}
