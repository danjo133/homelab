# MinIO bucket management

resource "minio_s3_bucket" "buckets" {
  for_each = toset(var.buckets)
  bucket   = each.value
  acl      = "private"
}
