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
  bucket = var.bucket_name
}


# Reset the bucket ACL to private before changing ownership controls.
# The bucket previously had a public-read ACL. AWS won't allow changing
# ownership to BucketOwnerEnforced while any ACL grant still exists.
# Setting this to "private" first clears those grants cleanly.
resource "aws_s3_bucket_acl" "reset" {
  bucket = aws_s3_bucket.mybucket.id
  acl    = "private"
}

# Set ownership controls on the bucket.
# "BucketOwnerEnforced" disables ACLs entirely — the bucket owner owns
# all objects automatically. We no longer need ACLs since the bucket is
# private and only accessible through CloudFront via OAC (below).
resource "aws_s3_bucket_ownership_controls" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_acl.reset]
}


# Block ALL public access to the bucket — it is now fully private.
# Previously this was all false (public). Now it's all true (private).
# Visitors reach our site through CloudFront only, not S3 directly.
# This is more secure because:
#   - Nobody can bypass CloudFront to hit S3 directly
#   - Our security headers and HTTPS enforcement can't be skipped
resource "aws_s3_bucket_public_access_block" "mybucket" {
  bucket = aws_s3_bucket.mybucket.id

  block_public_acls       = true # block any attempt to make objects public via ACL
  block_public_policy     = true # block any public bucket policies
  ignore_public_acls      = true # ignore any existing public ACLs
  restrict_public_buckets = true # restrict all public access to the bucket

  depends_on = [aws_s3_bucket_ownership_controls.mybucket]
}


# Upload index.html to the S3 bucket.
# - key: the filename/path it will have inside the bucket
# - source: the local file on your machine to upload
# - content_type: tells the browser this is an HTML file (not a download)
# - etag: a hash of the file — if the file changes, etag changes,
#   and Terraform knows to re-upload it automatically
# No ACL needed here — the bucket is private, CloudFront handles access.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.mybucket.id
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")

  depends_on = [aws_s3_bucket_public_access_block.mybucket]
}


# Upload error.html to the S3 bucket.
# Same setup as index.html — this is the custom 404 page.
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.mybucket.id
  key          = "error.html"
  source       = "error.html"
  content_type = "text/html"
  etag         = filemd5("error.html")

  depends_on = [aws_s3_bucket_public_access_block.mybucket]
}


# ---------------------------------------------------------------
# Origin Access Control (OAC)
#
# OAC is how CloudFront proves its identity to S3 when fetching files.
# Without OAC, S3 wouldn't know whether a request is coming from
# our CloudFront distribution or from some random person trying to
# access the bucket directly.
#
# How it works:
#   1. CloudFront signs every request to S3 using AWS Signature v4
#   2. S3 checks the signature against our bucket policy (below)
#   3. If the signature matches OUR CloudFront distribution → allow
#   4. Everything else → deny
#
# signing_behavior = "always" means every request is signed, no exceptions.
# ---------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4" # AWS Signature Version 4 — the current standard
}


# ---------------------------------------------------------------
# S3 Bucket Policy — allow only our CloudFront distribution to read files
#
# A bucket policy is a JSON document that defines who can access the bucket.
# This policy says:
#   ALLOW: the CloudFront service to call s3:GetObject (read files)
#   BUT ONLY IF: the request comes from OUR specific CloudFront distribution
#                (matched by its ARN via the Condition block)
#
# This means even if someone creates their own CloudFront distribution
# and points it at our bucket, it still gets denied — only our
# distribution's ARN matches.
# ---------------------------------------------------------------
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.mybucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com" # the CloudFront service identity
        }
        Action   = "s3:GetObject"                    # read-only access
        Resource = "${aws_s3_bucket.mybucket.arn}/*" # all objects in our bucket
        Condition = {
          StringEquals = {
            # only allow requests from OUR specific CloudFront distribution
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.mybucket]
}


# ---------------------------------------------------------------
# CloudFront Response Headers Policy — Security Headers
#
# Security headers are HTTP response headers that tell the browser
# how to behave securely when displaying your site. CloudFront injects
# these into every response automatically.
#
# Each header explained:
#   HSTS (Strict-Transport-Security): tells browsers to ALWAYS use HTTPS
#     for this site for the next year — even if the user types http://
#   X-Content-Type-Options: prevents browsers from guessing the file type
#     (e.g. treating a text file as executable code)
#   X-Frame-Options: prevents your site from being embedded in an iframe
#     on another site (protects against clickjacking attacks)
#   X-XSS-Protection: enables the browser's built-in XSS filter
#   Referrer-Policy: controls how much URL info is sent when clicking links
#     "strict-origin-when-cross-origin" = safe default
# ---------------------------------------------------------------
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.bucket_name}-security-headers"

  security_headers_config {

    # Force HTTPS for 1 year (31536000 seconds), including subdomains
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true # override means apply even if origin already sets this header
    }

    # Block MIME-type sniffing
    content_type_options {
      override = true
    }

    # Block iframe embedding (anti-clickjacking)
    frame_options {
      frame_option = "DENY"
      override     = true
    }

    # Enable browser XSS filter
    xss_protection {
      mode_block = true # block the page entirely if XSS is detected
      protection = true
      override   = true
    }

    # Control referrer info sent on navigation
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}


# ---------------------------------------------------------------
# CloudFront Distribution
#
# CloudFront is AWS's CDN (Content Delivery Network).
# It sits in front of S3 and serves our site from 400+ edge locations
# worldwide, adding HTTPS, caching, security headers, and OAC.
# ---------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {

  # origin = where CloudFront fetches content FROM.
  # We now use the S3 bucket's regional domain name (REST API endpoint)
  # instead of the website endpoint, because OAC requires the REST endpoint.
  origin {
    domain_name              = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.mybucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id # attach OAC
  }

  enabled             = true
  default_root_object = "index.html" # serve index.html when someone visits /

  # default_cache_behavior defines how CloudFront handles and caches requests.
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-${aws_s3_bucket.mybucket.id}"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id # attach security headers

    forwarded_values {
      query_string = false # don't pass query strings to S3 (not needed for static sites)
      cookies {
        forward = "none" # don't forward cookies (not needed for static sites)
      }
    }

    # Redirect any http:// requests to https:// automatically
    viewer_protocol_policy = "redirect-to-https"

    # TTL = how long CloudFront caches files before checking S3 for updates
    min_ttl     = 0     # minimum cache time
    default_ttl = 3600  # default: 1 hour
    max_ttl     = 86400 # maximum: 24 hours
  }

  # When S3 denies a request (403) because the file doesn't exist,
  # serve our custom error.html with a 404 status code.
  # S3 returns 403 instead of 404 for missing files when the bucket is private
  # (it won't reveal whether a file exists or not for security reasons).
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/error.html"
  }

  # Also handle real 404s from S3
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/error.html"
  }

  # No geographic restrictions — site is accessible worldwide
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use the free AWS default CloudFront SSL certificate (*.cloudfront.net)
  # To use a custom domain, you'd replace this with an ACM certificate ARN
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
