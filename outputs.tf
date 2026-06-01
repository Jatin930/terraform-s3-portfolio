# ---------------------------------------------------------------
# outputs.tf
# Outputs display useful information after Terraform runs.
# Think of them like return values — Terraform prints these
# to the terminal after apply, so you can easily find key details
# like URLs without digging through the AWS console.
# ---------------------------------------------------------------


# Output the website endpoint URL after the bucket is created.
# This is the public URL where your static site is accessible.
output "website_endpoint" {
  description = "Public URL of the S3 static website"
  value       = "http://${aws_s3_bucket_website_configuration.mybucket.website_endpoint}"
}
