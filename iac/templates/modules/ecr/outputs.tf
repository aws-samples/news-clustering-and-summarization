output "latest_image_uri" {
  value       = "${aws_ecr_repository.this_aws_ecr_repository.repository_url}@${data.aws_ecr_image.this_aws_ecr_image.image_digest}"
  description = "URI of the ECR Images"
}

output "latest_image_url" {
  value       = aws_ecr_repository.this_aws_ecr_repository.repository_url
  description = "URL of the ECR Images"
}

output "latest_image_tag" {
  value       = data.aws_ecr_image.this_aws_ecr_image.image_tags
  description = "URI of the ECR Images"
}