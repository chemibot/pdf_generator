output "cloudfront_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "name" {
  value = aws_s3_bucket.pdf_bucket.bucket
}