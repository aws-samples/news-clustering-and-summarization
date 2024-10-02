# Code Deployment
module "cluster_code_bucket" {
  source      = "../../templates/modules/s3_bucket"
  name_prefix = "code-bucket-${var.app_name}-${var.env_name}"
  log_bucket  = module.log_bucket.name
}

resource "aws_s3_object" "clustering_code" {
  bucket = module.cluster_code_bucket.name

  for_each      = fileset("../../../business_logic/stream_consumer", "**/*.*")
  key           = "stream_consumer/${each.value}"
  source        = "../../../business_logic/stream_consumer/${each.value}"
  source_hash   = filemd5("../../../business_logic/stream_consumer/${each.value}")
  content_type  = each.value
  force_destroy = true
}

# SQS Queue
resource "aws_sqs_queue" "tags" {
  name                    = "${var.app_name}-${var.env_name}-queue"
  sqs_managed_sse_enabled = true
}

# EC2 Instance
data "aws_ami" "amazon_linux" {
  most_recent = true
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"] # Arm
  }
  filter {
    name   = "architecture"
    values = ["arm64"] # Arm
  }

}

resource "aws_iam_instance_profile" "this_aws_iam_instance_profile_stream_consumer" {
  name = "stream-consumer-instance-profile-${var.app_name}-${var.env_name}"
  role = aws_iam_role.stream_consumer_role.name
}

# User Data
data "cloudinit_config" "this_cloudinit_config" {
  gzip          = false
  base64_encode = false
  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/init.cfg",
      {
        CONFIGURE_NODE_SCRIPT = base64gzip(templatefile("${path.module}/templates/ConfigureNode.sh",
          {
            config = {
              "S3_BUCKET_PATH"     = "${module.cluster_code_bucket.id}/stream_consumer/"
              "S3_BUCKET_NAME"     = module.cluster_code_bucket.id
              "S3_FILE_KEY"        = "checkpoint.pkl"
              "SQS_QUEUE"          = aws_sqs_queue.tags.url
              "DYNAMODB_TABLE"     = aws_dynamodb_table.cluster_table.name
              "AWS_DEFAULT_REGION" = local.region
            }
          }
          )
        )
      }
    )
  }
}

resource "aws_security_group" "this_aws_security_group_ec2" {
  name        = "${local.standard_resource_name}-ec2"
  description = "Security group for EC2"
  vpc_id      = module.vpc.vpc_id
  egress {
    description = "Internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${local.standard_resource_name}-ec2" })

}

resource "aws_launch_template" "this_aws_launch_template" {
  name_prefix                          = "stream-consumer-instance-${local.standard_resource_name}-"
  description                          = "Launch template for stream-consumer-instance-${local.standard_resource_name}"
  tags                                 = merge(local.tags, { Name = "stream-consumer-instance-${local.standard_resource_name}" })
  image_id                             = data.aws_ami.amazon_linux.id
  instance_type                        = var.instance_type
  vpc_security_group_ids               = [aws_security_group.this_aws_security_group_ec2.id]
  user_data                            = base64encode(data.cloudinit_config.this_cloudinit_config.rendered)
  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "stop"
  update_default_version               = true
  disable_api_termination              = false

  iam_instance_profile {
    arn = aws_iam_instance_profile.this_aws_iam_instance_profile_stream_consumer.arn
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "stream-consumer-instance-${local.standard_resource_name}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "stream-consumer-instance-${local.standard_resource_name}" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(local.tags, { Name = "stream-consumer-instance-${local.standard_resource_name}" })
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = aws_kms_key.this_aws_kms_key.arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforces IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }
}

resource "aws_autoscaling_group" "this_aws_autoscaling_group_stream_consumer" {
  depends_on  = [aws_s3_object.clustering_code] # Code needs to be uploaded to s3 first
  name_prefix = "stream-consumer-instance-${local.standard_resource_name}"
  launch_template {
    id      = aws_launch_template.this_aws_launch_template.id
    version = "$Latest"
  }
  vpc_zone_identifier     = [module.vpc.private_subnets[0]]
  max_size                = var.number_of_nodes
  min_size                = 0
  desired_capacity        = var.number_of_nodes
  service_linked_role_arn = aws_iam_service_linked_role.this_asg_aws_iam_service_linked_role.arn
  dynamic "tag" {
    for_each = local.tags
    iterator = tags
    content {
      key                 = tags.key
      value               = tags.value
      propagate_at_launch = true
    }
  }
}
