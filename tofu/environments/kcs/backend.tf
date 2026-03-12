terraform {
  backend "s3" {
    bucket = "tofu-state"
    key    = "kcs/terraform.tfstate"
    region = "us-east-1"

    # MinIO S3-compatible backend
    endpoints = {
      s3 = "https://minio.support.example.com"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
