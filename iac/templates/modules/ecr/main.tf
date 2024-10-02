# Checks if build folder has changed
data "external" "this_external" {
  program = ["bash", "${var.build_script_path}/dir_md5.sh", "${var.business_logic_path}"]
}

resource "aws_ecr_repository" "this_aws_ecr_repository" {
  name                 = var.ecr_name
  tags                 = var.tags
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.aws_kms_key_arn
  }
}

resource "aws_ecr_lifecycle_policy" "this_aws_ecr_lifecycle_policy" {
  policy     = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last x images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": ${var.ecr_count_number}
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
  repository = aws_ecr_repository.this_aws_ecr_repository.name
}

resource "terraform_data" "this_terraform_data_build_ecr_image" {
  depends_on = [aws_ecr_repository.this_aws_ecr_repository]
  triggers_replace = [
    data.external.this_external.result.md5,
    aws_ecr_repository.this_aws_ecr_repository.id
  ]
  provisioner "local-exec" {
    command = "bash ${var.build_script_path}/build.sh ${var.ecr_base_arn} ${var.business_logic_path} ${aws_ecr_repository.this_aws_ecr_repository.name} ${aws_ecr_repository.this_aws_ecr_repository.repository_url} ${var.region}"
  }
}

data "aws_ecr_image" "this_aws_ecr_image" {
  depends_on      = [terraform_data.this_terraform_data_build_ecr_image, aws_ecr_repository.this_aws_ecr_repository]
  repository_name = aws_ecr_repository.this_aws_ecr_repository.name
  most_recent     = true
}