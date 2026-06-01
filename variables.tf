# ---------------------------------------------------------------
# variables.tf
# Variables let you avoid hardcoding values directly in main.tf.
# Think of them like constants in programming — define a value
# once here, and reference it anywhere with var.<name>.
# This makes your code easier to reuse and update.
# ---------------------------------------------------------------


# Define a variable called "bucket_name".
# In main.tf we reference this as: var.bucket_name
variable "bucket_name" {
  description = "Name of the S3 bucket" # explains what this variable is for
  type        = string                  # the value must be text (not a number or list)
  default     = "myterraformproject-jt" # used automatically if no other value is provided
  # note: S3 bucket names must be globally unique,
  # lowercase, and use hyphens (no underscores)
}
