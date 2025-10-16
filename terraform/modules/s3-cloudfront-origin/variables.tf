variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "resized_images_expiration_days" {
  description = "Number of days to keep resized images before deletion"
  type        = number
  default     = 30
}

variable "enable_cors" {
  description = "Enable CORS configuration"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
