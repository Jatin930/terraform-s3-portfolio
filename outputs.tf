# ---------------------------------------------------------------
# outputs.tf
# Outputs display useful information after Terraform runs.
# Think of them like return values — Terraform prints these
# to the terminal after apply, so you can easily find key details
# like URLs without digging through the AWS console.
# ---------------------------------------------------------------


# The raw S3 website endpoint — HTTP only, served directly from the bucket.
# Useful for testing, but use the CloudFront URL for the real site.
output "website_endpoint" {
  description = "Direct S3 website URL (HTTP only)"
  value       = "http://${aws_s3_bucket_website_configuration.mybucket.website_endpoint}"
}


# The CloudFront URL — HTTPS, globally cached, and the one to share publicly.
# Note: CloudFront takes 5-10 minutes to fully deploy after apply completes.
# The URL will work once the distribution status changes to "Deployed" in AWS console.
output "cloudfront_url" {
  description = "CloudFront distribution URL (HTTPS, globally cached)"
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}
