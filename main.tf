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
}
