# Copyright 2023 Amazon.com and its affiliates; all rights reserved.
# This file is Amazon Web Services Content and may not be duplicated or distributed without permission.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  tags = {
    app_name = var.app_name
    env_name = var.env_name
  }
  region                 = data.aws_region.current.name
  account_id             = data.aws_caller_identity.current.account_id
  standard_resource_name = "${var.app_name}-${var.env_name}"
  ecr_base_arn           = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
  aws_path               = "/"
  front_end_path         = "../../../front_end/src/"
}

# VPC Module
module "vpc" {
  source          = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=2e417ad0ce830893127476436179ef483485ae84"
  name            = local.standard_resource_name
  cidr            = var.cidr_block
  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnet
  public_subnets  = var.public_subnet

  enable_nat_gateway            = true
  single_nat_gateway            = true # Creating only one NAT to save cost
  enable_vpn_gateway            = false
  manage_default_network_acl    = true
  manage_default_route_table    = true
  manage_default_security_group = true

  tags                     = local.tags
  default_network_acl_tags = { Name = "${local.standard_resource_name}-default" }
  private_subnet_tags      = { Name = "${local.standard_resource_name}-Private", Network = "private" }
  public_subnet_tags       = { Name = "${local.standard_resource_name}-Public", Network = "public" }
  default_route_table_tags = { Name = "${local.standard_resource_name}-default", DefaultRouteTable = true }
  private_route_table_tags = { Name = "${local.standard_resource_name}-private" }
  public_route_table_tags  = { Name = "${local.standard_resource_name}-public" }

}

# Dynamodb
resource "aws_dynamodb_table" "cluster_table" {
  #checkov:skip=CKV_AWS_119: "Ensure DynamoDB Tables are encrypted using a KMS Customer Managed CMK"
  #checkov:skip=CKV_AWS_28: "Ensure DynamoDB point in time recovery (backup) is enabled"
  name         = "cluster-table-${local.standard_resource_name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK" # Partition key
  range_key    = "SK" # Sort key
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "article_id"
    type = "S"
  }

  global_secondary_index {
    name            = "article_id"
    hash_key        = "article_id"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

resource "aws_lambda_event_source_mapping" "stream_mapping" {
  event_source_arn  = aws_dynamodb_table.cluster_table.stream_arn
  function_name     = aws_lambda_function.trigger_sfn_function.arn
  starting_position = "LATEST"
}

# Pre-processing state machine
resource "aws_sfn_state_machine" "pre_processing_sfn" {
  #checkov:skip=CKV_AWS_285: "Ensure State Machine has execution history logging enabled"
  name     = "pre-processing-sfn-${var.app_name}-${var.env_name}"
  role_arn = aws_iam_role.step_functions_role.arn

  tracing_configuration {
    enabled = true
  }
  definition = <<EOF
{
  "Comment": "An example of AWS Step Function",
  "StartAt": "PreProcessing",
  "States": {
    "PreProcessing": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.pre_processing_lambda.arn}",
      "Next": "CallSageMaker"
    },
    "CallSageMaker": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.embedding_lambda.arn}",
       "Next": "SuccessState"
    },
    "SuccessState": {
      "Type": "Succeed"
    }
  }
}
EOF
}

# The Input stream where raw articles will come in to be preprocessed
resource "aws_kinesis_stream" "input_stream" {
  #checkov:skip=CKV_AWS_185: "Ensure Kinesis Stream is encrypted by KMS using a customer managed Key (CMK)"
  #checkov:skip=CKV_AWS_43: "Ensure Kinesis Stream is securely encrypted"
  name             = "input-stream-${var.app_name}-${var.env_name}"
  retention_period = 48
  # encryption_type  = "KMS"
  # kms_key_id       = aws_kms_key.kms_key.id
  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Environment = "test"
  }
}
module "log_bucket" {
  source      = "../../templates/modules/s3_bucket"
  name_prefix = "log-${var.app_name}-${var.env_name}"
}

module "preprocess_data_bucket" {
  source      = "../../templates/modules/s3_bucket"
  name_prefix = "preprocess-${var.app_name}-${var.env_name}"
  log_bucket  = module.log_bucket.name
}

module "embedding_data_bucket" {
  source      = "../../templates/modules/s3_bucket"
  name_prefix = "embedding-${var.app_name}-${var.env_name}"
  log_bucket  = module.log_bucket.name
}

# Code for Front End
resource "aws_security_group" "this_aws_security_group_front_end" {
  #checkov:skip=CKV_AWS_23: Ensure every security groups rule has a description
  #checkov:skip=CKV_AWS_24: Ensure no security groups allow ingress from 0.0.0.0:0 to port 22
  #checkov:skip=CKV_AWS_25: Ensure no security groups allow ingress from 0.0.0.0:0 to port 3389
  #checkov:skip=CKV_AWS_260: Ensure no security groups allow ingress from 0.0.0.0:0 to port 80
  #checkov:skip=CKV_AWS_277: Ensure no security groups allow ingress from 0.0.0.0:0 to port -1
  name        = "front-end-${local.standard_resource_name}"
  description = "Allow traffic for Front End Application"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cognito_user_pool" "this_aws_cognito_user_pool_front_end" {
  name = "front-end-${local.standard_resource_name}"
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  auto_verified_attributes = var.auto_verified_attributes
  alias_attributes         = ["email", "preferred_username"]
  tags                     = local.tags
  mfa_configuration        = var.mfa_configuration
  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }
  dynamic "software_token_mfa_configuration" {
    for_each = var.allow_software_mfa_token ? [true] : []
    content {
      enabled = true
    }
  }
  username_configuration {
    case_sensitive = var.case_sensitive
  }
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  sms_authentication_message = var.sms_authentication_message
  password_policy {
    minimum_length                   = var.minimum_length
    require_lowercase                = var.require_lowercase
    require_numbers                  = var.require_numbers
    require_symbols                  = var.require_symbols
    require_uppercase                = var.require_uppercase
    temporary_password_validity_days = var.temporary_password_validity_days
  }
  schema {
    name                     = "terraform"
    attribute_data_type      = "Boolean"
    mutable                  = false
    required                 = false
    developer_only_attribute = false
  }
}

resource "aws_cognito_user" "this_aws_cognito_user_front_end" {
  for_each     = var.cognito_users
  user_pool_id = aws_cognito_user_pool.this_aws_cognito_user_pool_front_end.id
  username     = each.value.name
  enabled      = true
  password     = each.value.password
  attributes = {
    terraform      = true
    email          = each.value.email
    email_verified = true
  }
}

resource "aws_cognito_user_pool_client" "this_aws_cognito_user_pool_client_front_end" {
  name                = "front-end-client-${local.standard_resource_name}"
  user_pool_id        = aws_cognito_user_pool.this_aws_cognito_user_pool_front_end.id
  generate_secret     = false
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH"]
}

resource "aws_cognito_identity_pool" "this_aws_cognito_identity_pool_front_end" {
  identity_pool_name               = "front-end-identity-pool-${local.standard_resource_name}"
  allow_unauthenticated_identities = false
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.this_aws_cognito_user_pool_client_front_end.id
    provider_name           = aws_cognito_user_pool.this_aws_cognito_user_pool_front_end.endpoint
    server_side_token_check = true
  }
  tags = local.tags
}

resource "aws_iam_role" "this_aws_iam_role_front_end_auth" {
  name               = "front-end-auth-role-${local.standard_resource_name}"
  description        = "front-end-auth-role-${local.standard_resource_name}"
  tags               = local.tags
  path               = local.aws_path
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        },
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end.id}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role" "this_aws_iam_role_front_end_unauth" {
  name               = "front-end-unauth-role-${local.standard_resource_name}"
  description        = "front-end-unauth-role-${local.standard_resource_name}"
  tags               = local.tags
  path               = local.aws_path
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        },
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud":  "${aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end.id}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_policy" "this_aws_iam_policy_front_end_cognito" {
  path = local.aws_path
  name = "front-end-cognito-${local.standard_resource_name}"
  policy = templatefile("templates/cognito-policy.json",
    {
      dd_table_arn = aws_dynamodb_table.cluster_table.arn
  })
}

resource "aws_iam_policy_attachment" "this_aws_iam_policy_attachment_front_end" {
  name       = "front-end-cognito-${local.standard_resource_name}"
  roles      = [aws_iam_role.this_aws_iam_role_front_end_auth.name, aws_iam_role.this_aws_iam_role_front_end_unauth.name]
  policy_arn = aws_iam_policy.this_aws_iam_policy_front_end_cognito.arn
}

resource "local_file" "this_local_file_front_end_config" {
  filename = "${local.front_end_path}/aws-exports.js"
  content = templatefile("templates/aws-exports-js.template",
    {
      AWS_REGION                          = data.aws_region.current.name
      AWS_COGNITO_IDENTITY_POOL           = aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end.id
      AWS_COGNITO_USER_POOL_ID            = aws_cognito_user_pool.this_aws_cognito_user_pool_front_end.id
      AWS_CONGITO_USER_POOL_APP_CLIENT_ID = aws_cognito_user_pool_client.this_aws_cognito_user_pool_client_front_end.id
    }
  )
  lifecycle {
    replace_triggered_by = [
      aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end,
      aws_cognito_user_pool.this_aws_cognito_user_pool_front_end,
      aws_cognito_user_pool_client.this_aws_cognito_user_pool_client_front_end
    ]
  }
}

resource "local_file" "this_local_file_cluseter_list_java_script" {
  filename = "${local.front_end_path}/components/ClusterList.js"
  content = templatefile("templates/ClusterList-js.template",
    {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.cluster_table.id
    }
  )
  lifecycle {
    replace_triggered_by = [
      aws_dynamodb_table.cluster_table,
      aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end,
      aws_cognito_user_pool.this_aws_cognito_user_pool_front_end,
      aws_cognito_user_pool_client.this_aws_cognito_user_pool_client_front_end
    ]
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "this_aws_cognito_identity_pool_roles_attachment_front_end" {
  identity_pool_id = aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end.id
  roles = {
    "authenticated" : aws_iam_role.this_aws_iam_role_front_end_auth.arn
  }
}

# Create Docker image for the front-end
module "front_end_ecr" {
  source              = "../../templates/modules/ecr"
  region              = local.region
  ecr_name            = "front-end-${local.standard_resource_name}"
  build_script_path   = "${path.module}/${var.build_script_path}"
  business_logic_path = "${path.module}/${var.front_end_path}"
  tags                = local.tags
  aws_kms_key_arn     = aws_kms_key.this_aws_kms_key.arn
  ecr_count_number    = 2
  ecr_base_arn        = local.ecr_base_arn
  depends_on = [
    aws_cognito_identity_pool.this_aws_cognito_identity_pool_front_end,
    aws_cognito_user_pool.this_aws_cognito_user_pool_front_end,
    aws_cognito_user_pool_client.this_aws_cognito_user_pool_client_front_end,
    local_file.this_local_file_front_end_config,
    local_file.this_local_file_cluseter_list_java_script
  ]
}

resource "aws_iam_role" "this_aws_iam_role_front_end" {
  name               = "front-end-ecs-role-${local.standard_resource_name}"
  path               = local.aws_path
  description        = "Role to be Assumed by ECS Task"
  tags               = local.tags
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "this_aws_iam_policy_front_end" {
  name = "front-end-ecs-policy-${local.standard_resource_name}"
  policy = templatefile("templates/ecs-role.json", {
    account_number         = local.account_id
    standard_resource_name = local.standard_resource_name
    kms_key_arn            = aws_kms_key.this_aws_kms_key.arn
  })
}

resource "aws_iam_policy_attachment" "this_aws_iam_policy_attachment_front_end_ecs" {
  name       = "front-end-${local.standard_resource_name}"
  roles      = [aws_iam_role.this_aws_iam_role_front_end.name]
  policy_arn = aws_iam_policy.this_aws_iam_policy_front_end.arn
}

# Cloudwatch log Group
#-----------------------
resource "aws_cloudwatch_log_group" "this_aws_cloudwatch_log_group_front_end" {
  name              = "/aws/${local.standard_resource_name}-front-end"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.this_aws_kms_key.arn
  tags              = local.tags
}

# Create ECS Cluster for Hosting the App
#------------------------------------------
resource "aws_ecs_cluster" "this_aws_ecs_cluster_front_end" {
  #checkov:skip=CKV_AWS_65: Ensure container insights are enabled on ECS cluster
  name = "front-end-${local.standard_resource_name}"
  tags = local.tags
}

resource "aws_ecs_task_definition" "this_aws_ecs_task_definition_front_end" {
  #checkov:skip=CKV_AWS_249: Ensure that the Execution Role ARN and the Task Role ARN are different in ECS Task definitions
  family                   = "front-end-${local.standard_resource_name}"
  execution_role_arn       = aws_iam_role.this_aws_iam_role_front_end.arn
  task_role_arn            = aws_iam_role.this_aws_iam_role_front_end.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags                     = local.tags
  container_definitions    = <<DEFINITION
[
  {
    "name": "front-end-${local.standard_resource_name}",
    "image": "${module.front_end_ecr.latest_image_url}:${tolist(module.front_end_ecr.latest_image_tag)[0]}",
    "cpu": ${var.task_cpu},
    "memory": ${var.task_memory},
    "memoryReservation": 300,
    "networkMode": "awsvpc",
    "portMappings": [
     {
        "containerPort": 443
     }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.this_aws_cloudwatch_log_group_front_end.name}",
          "awslogs-region": "${local.region}",
          "awslogs-stream-prefix": "${local.standard_resource_name}"
        }
    },
    "environment": [
      {
        "name": "ENV",
        "value": "${var.env_name}"
      }
    ]
  }
]
DEFINITION
  depends_on               = [module.front_end_ecr]
}

resource "aws_ecs_service" "this_aws_ecs_service_front_end" {
  #checkov:skip=CKV_AWS_333: Ensure ECS services do not have public IP addresses assigned to them automatically
  name                 = "front-end-${local.standard_resource_name}"
  launch_type          = var.launch_type
  cluster              = aws_ecs_cluster.this_aws_ecs_cluster_front_end.id
  task_definition      = aws_ecs_task_definition.this_aws_ecs_task_definition_front_end.arn
  desired_count        = var.desired_count
  tags                 = local.tags
  force_new_deployment = true
  lifecycle {
    replace_triggered_by = [
      aws_ecs_task_definition.this_aws_ecs_task_definition_front_end.id
    ]
  }
  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.this_aws_security_group_front_end.id]
    subnets          = module.vpc.public_subnets
  }
  load_balancer {
    container_name   = "front-end-${local.standard_resource_name}"
    target_group_arn = aws_lb_target_group.this_aws_lb_target_group_front_end.arn
    container_port   = "443"
  }
  depends_on = [module.front_end_ecr]
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a Self-Signed Certificate
#-------------------------------------
resource "tls_self_signed_cert" "self_signed_cert" {
  private_key_pem = tls_private_key.private_key.private_key_pem
  subject {
    common_name  = "aws-samples.com"
    organization = "AWS Samples"
  }
  validity_period_hours = 8760 # 1 year
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Upload the certificate to AWS ACM
#------------------------------------
resource "aws_acm_certificate" "self_signed_cert" {
  private_key       = tls_private_key.private_key.private_key_pem
  certificate_body  = tls_self_signed_cert.self_signed_cert.cert_pem
  certificate_chain = tls_self_signed_cert.self_signed_cert.cert_pem # Self-signed, so no separate chain
  tags              = local.tags
}

resource "aws_alb" "this_aws_alb_front_end" {
  #checkov:skip=CKV_AWS_2: Ensure ALB protocol is HTTPS
  #checkov:skip=CKV_AWS_91: Ensure the ELBv2 (Application/Network) has access logging enabled
  #checkov:skip=CKV_AWS_131: Ensure that ALB drops HTTP headers
  #checkov:skip=CKV_AWS_150: Ensure that Load Balancer has deletion protection enabled
  #checkov:skip=CKV_AWS_333: Ensure ECS services do not have public IP addresses assigned to them automatically
  #checkov:skip=CKV2_AWS_20: Ensure that ALB redirects HTTP requests into HTTPS ones
  #checkov:skip=CKV2_AWS_28: Ensure public facing ALB are protected by WAF
  #checkov:skip=CCKV2_AWS_20: Ensure that ALB redirects HTTP requests into HTTPS ones
  name               = "front-end-${local.standard_resource_name}"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.this_aws_security_group_front_end.id]
}

resource "aws_lb_target_group" "this_aws_lb_target_group_front_end" {
  #checkov:skip=CKV_AWS_261: Ensure HTTP HTTPS Target group defines Healthcheck
  name        = "front-end-${local.standard_resource_name}"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_alb_listener" "this_aws_alb_listener_front_end" {
  #checkov:skip=CKV_AWS_2: Ensure ALB protocol is HTTPS
  #checkov:skip=CKV_AWS_103: Ensure that load balancer is using at least TLS 1.2
  #checkov:skip=CKV_AWS_261: Ensure HTTP HTTPS Target group defines Healthcheck
  load_balancer_arn = aws_alb.this_aws_alb_front_end.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.self_signed_cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this_aws_lb_target_group_front_end.arn
  }
}