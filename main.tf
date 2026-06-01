# ---------------------------------------------------------------
# main.tf
# This is the main configuration file where we define all the
# AWS resources we want Terraform to create and manage.
# Each "resource" block tells Terraform: "create this thing in AWS".
# ---------------------------------------------------------------


# Create the S3 bucket itself.
# "aws_s3_bucket" is the resource type (from AWS).
# "mybucket" is what WE call it inside Terraform (used to reference it later).
# The actual name of the bucket in AWS comes from our variable file.
resource "aws_s3_bucket" "mybucket" {
  bucket = var.bucket_name  # pulls the name from variables.tf
}


# Set ownership controls on the bucket.
# "BucketOwnerPreferred" means: the bucket owner will own all objects
# uploaded to this bucket, BUT ACLs (Access Control Lists) are still allowed.
# We need this set before we can apply a public-read ACL below.
resource "aws_s3_bucket_ownership_controls" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id  # reference the bucket we created above

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


# By default, AWS blocks all public access to S3 buckets for safety.
# We're turning ALL four of those blocks OFF so our website can be public.
# Setting each one to false means: "do NOT block this type of public access".
resource "aws_s3_bucket_public_access_block" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id

  block_public_acls       = false  # allow public ACLs to be set
  block_public_policy     = false  # allow public bucket policies
  ignore_public_acls      = false  # do not ignore public ACLs
  restrict_public_buckets = false  # do not restrict public bucket access
}


# Apply a public-read ACL to the bucket.
# "public-read" means anyone on the internet can read (view) the contents.
# This is what makes our website files accessible in a browser.
#
# depends_on tells Terraform: wait until ownership controls AND
# public access block are created before trying to set the ACL.
# Without this order, AWS would reject the request.
resource "aws_s3_bucket_acl" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id
  acl    = "public-read"

  depends_on = [
    aws_s3_bucket_ownership_controls.mybucket,
    aws_s3_bucket_public_access_block.mybucket
  ]
}


# Enable static website hosting on the bucket.
# This turns our plain S3 bucket into a web server that can serve HTML files.
# - index_document: the file AWS serves when someone visits the root URL (/)
# - error_document: the file AWS serves when a page is not found (404)
resource "aws_s3_bucket_website_configuration" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id

  index_document {
    suffix = "index.html"  # serve this file at the root of the site
  }

  error_document {
    key = "error.html"  # serve this file when a page doesn't exist
  }
}


# Upload index.html to the S3 bucket.
# - key: the filename/path it will have inside the bucket
# - source: the local file on your machine to upload
# - acl: public-read so anyone can view it in their browser
# - content_type: tells the browser this is an HTML file (not a download)
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.mybucket.id
  key          = "index.html"
  source       = "index.html"
  acl          = "public-read"
  content_type = "text/html"
  etag         = filemd5("index.html")  # detects file content changes so Terraform re-uploads when the file is edited

  depends_on = [
    aws_s3_bucket_ownership_controls.mybucket,
    aws_s3_bucket_public_access_block.mybucket
  ]
}


# Upload error.html to the S3 bucket.
# Same setup as index.html — this is the custom 404 page.
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.mybucket.id
  key          = "error.html"
  source       = "error.html"
  acl          = "public-read"
  content_type = "text/html"
  etag         = filemd5("error.html")  # detects file content changes so Terraform re-uploads when the file is edited

  depends_on = [
    aws_s3_bucket_ownership_controls.mybucket,
    aws_s3_bucket_public_access_block.mybucket
  ]
}


# ---------------------------------------------------------------
# CloudFront Distribution
#
# CloudFront is AWS's CDN (Content Delivery Network).
# Instead of visitors hitting our S3 bucket directly in us-east-1,
# CloudFront caches our files at 400+ edge locations worldwide.
#
# Key benefits over plain S3 hosting:
#   1. HTTPS — S3 website hosting only supports HTTP. CloudFront
#      provides a free SSL certificate automatically.
#   2. Speed — content is served from the nearest edge location
#      to the visitor, not always from Virginia.
#   3. HTTP → HTTPS redirect — any http:// request is automatically
#      upgraded to https://.
#   4. Custom error pages — we can map 404 errors to our error.html.
# ---------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {

  # origin = where CloudFront fetches your content FROM.
  # We point it at the S3 website endpoint (not the bucket directly)
  # so it respects our index/error document configuration.
  origin {
    domain_name = aws_s3_bucket_website_configuration.mybucket.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.mybucket.id}"  # a unique label for this origin, used below

    # custom_origin_config is needed when using an S3 website endpoint
    # (as opposed to a raw S3 bucket). The website endpoint only speaks HTTP,
    # so we set origin_protocol_policy to "http-only" here.
    # CloudFront still serves HTTPS to visitors — it just fetches from S3 over HTTP internally.
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true           # the distribution is active and serving traffic
  default_root_object = "index.html"   # serve index.html when someone visits the root URL /

  # default_cache_behavior defines how CloudFront handles requests and caching.
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]          # only allow read requests (this is a static site)
    cached_methods   = ["GET", "HEAD"]          # cache responses to GET and HEAD requests
    target_origin_id = "S3-${aws_s3_bucket.mybucket.id}"  # which origin to use (matches origin_id above)

    # forwarded_values controls what request info CloudFront passes to the origin.
    # For a static site we don't need query strings or cookies.
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # redirect-to-https means: if a visitor uses http://, CloudFront
    # automatically sends them to https:// instead.
    viewer_protocol_policy = "redirect-to-https"

    # TTL = Time To Live — how long CloudFront caches files before checking S3 for updates.
    # min: 0 seconds, default: 1 hour (3600s), max: 24 hours (86400s)
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # When a visitor hits a URL that doesn't exist, S3 returns a 404.
  # This maps that 404 to our custom error.html page.
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/error.html"
  }

  # geo_restriction lets you block or allowlist specific countries.
  # "none" means the site is accessible from everywhere in the world.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # viewer_certificate controls the SSL certificate shown to visitors.
  # cloudfront_default_certificate = true means we use the free
  # AWS-provided certificate with the *.cloudfront.net domain.
  # (To use your own domain + cert, you'd use acm_certificate_arn instead.)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
