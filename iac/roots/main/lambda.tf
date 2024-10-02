# Lambda functions

module "pre_process_docs_ecr" {
  source              = "../../templates/modules/ecr"
  region              = local.region
  ecr_name            = "pre-process-docs-${local.standard_resource_name}"
  build_script_path   = "${path.module}/${var.build_script_path}"
  business_logic_path = "${path.module}/${var.lambda_code_path}/pre_process_docs/"
  tags                = local.tags
  aws_kms_key_arn     = aws_kms_key.this_aws_kms_key.arn
  ecr_count_number    = 2
  ecr_base_arn        = local.ecr_base_arn
}

resource "aws_lambda_function" "pre_processing_lambda" {
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)"
  #checkov:skip=CKV_AWS_173: "Check encryption settings for Lambda environmental variable"
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC"
  #checkov:skip=CKV_AWS_272: "Ensure AWS Lambda function is configured to validate code-signing"
  description                    = "Executes the pre-process_docs-${local.standard_resource_name} Function"
  function_name                  = "pre-process-docs-${local.standard_resource_name}"
  role                           = aws_iam_role.preprocessing_lambda_role.arn
  timeout                        = 300 # Timeout in seconds (5 minutes)
  kms_key_arn                    = aws_kms_key.this_aws_kms_key.arn
  image_uri                      = module.pre_process_docs_ecr.latest_image_uri
  package_type                   = "Image"
  tags                           = local.tags
  reserved_concurrent_executions = -1
  # vpc_config {
  #   # If the list of security group ids and subnets are empty,
  #   # this property is effectively ignored
  #   subnet_ids         = [aws_subnet.subnet.id]
  #   security_group_ids = [aws_security_group.sg.id]
  # }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      PREPROCESS_BUCKET = module.preprocess_data_bucket.name
    }
  }
}

module "embedding_lambda_ecr" {
  source              = "../../templates/modules/ecr"
  region              = local.region
  ecr_name            = "embed-docs-${local.standard_resource_name}"
  build_script_path   = "${path.module}/${var.build_script_path}"
  business_logic_path = "${path.module}/${var.lambda_code_path}/embed_docs/"
  tags                = local.tags
  aws_kms_key_arn     = aws_kms_key.this_aws_kms_key.arn
  ecr_count_number    = 2
  ecr_base_arn        = local.ecr_base_arn
}

resource "aws_lambda_function" "embedding_lambda" {
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)"
  #checkov:skip=CKV_AWS_173: "Check encryption settings for Lambda environmental variable"
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC"
  #checkov:skip=CKV_AWS_272: "Ensure AWS Lambda function is configured to validate code-signing"
  description                    = "Executes the embed-docs-${local.standard_resource_name} Function"
  function_name                  = "embed-docs-${local.standard_resource_name}"
  role                           = aws_iam_role.embedding_lambda_role.arn
  timeout                        = 300 # Timeout in seconds (5 minutes)
  kms_key_arn                    = aws_kms_key.this_aws_kms_key.arn
  image_uri                      = module.embedding_lambda_ecr.latest_image_uri
  package_type                   = "Image"
  tags                           = local.tags
  reserved_concurrent_executions = -1
  # vpc_config {
  #   # If the list of security group ids and subnets are empty,
  #   # this property is effectively ignored
  #   subnet_ids         = [aws_subnet.subnet.id]
  #   security_group_ids = [aws_security_group.sg.id]
  # }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      EMBEDDING_ENDPOINT_NAME = var.model_name != "titan" ? aws_sagemaker_endpoint.pytorch_endpoint[0].name : ""
      MAX_LENGTH              = var.max_length_embedding
      SQS_QUEUE_URL           = aws_sqs_queue.tags.url
      PREPROCESS_BUCKET       = module.preprocess_data_bucket.name
      EMBEDDING_BUCKET        = module.embedding_data_bucket.name
      MAX_ARTICLES            = var.max_articles_embedding_endpoint
      EMBEDDING_MODEL         = var.model_name
    }
  }
}

module "trigger_sfn_ecr" {
  source              = "../../templates/modules/ecr"
  region              = local.region
  ecr_name            = "trigger-sfn-${local.standard_resource_name}"
  build_script_path   = "${path.module}/${var.build_script_path}"
  business_logic_path = "${path.module}/${var.lambda_code_path}/trigger_sfn/"
  tags                = local.tags
  aws_kms_key_arn     = aws_kms_key.this_aws_kms_key.arn
  ecr_count_number    = 2
  ecr_base_arn        = local.ecr_base_arn
}

resource "aws_lambda_function" "trigger_sfn_function" {
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)"
  #checkov:skip=CKV_AWS_173: "Check encryption settings for Lambda environmental variable"
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC"
  #checkov:skip=CKV_AWS_272: "Ensure AWS Lambda function is configured to validate code-signing"
  description   = "Executes the trigger-sfn-${local.standard_resource_name} Function"
  function_name = "trigger-sfn-${local.standard_resource_name}"
  role          = aws_iam_role.trigger_sfn_lambda_role.arn
  timeout       = 30
  kms_key_arn   = aws_kms_key.this_aws_kms_key.arn
  image_uri     = module.trigger_sfn_ecr.latest_image_uri
  package_type  = "Image"
  tags          = local.tags

  reserved_concurrent_executions = -1
  # vpc_config {
  #   # If the list of security group ids and subnets are empty,
  #   # this property is effectively ignored
  #   subnet_ids         = [aws_subnet.subnet.id]
  #   security_group_ids = [aws_security_group.sg.id]
  # }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      STATE_MACHINE_ARN   = aws_sfn_state_machine.summary_sfn.arn
      ARTICLES_THRESHOLD  = 5
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.cluster_table.name
    }
  }
}

module "summarization_function_ecr" {
  source              = "../../templates/modules/ecr"
  region              = local.region
  ecr_name            = "summarization-function-docs-${local.standard_resource_name}"
  build_script_path   = "${path.module}/${var.build_script_path}"
  business_logic_path = "${path.module}/${var.lambda_code_path}/summarization/"
  tags                = local.tags
  aws_kms_key_arn     = aws_kms_key.this_aws_kms_key.arn
  ecr_count_number    = 2
  ecr_base_arn        = local.ecr_base_arn
}

resource "aws_lambda_function" "summarization_function" {
  #checkov:skip=CKV_AWS_116: "Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)"
  #checkov:skip=CKV_AWS_173: "Check encryption settings for Lambda environmental variable"
  #checkov:skip=CKV_AWS_272: "Ensure AWS Lambda function is configured to validate code-signing"
  #checkov:skip=CKV_AWS_117: "Ensure that AWS Lambda function is configured inside a VPC"
  description                    = "Executes the summarization-function-${local.standard_resource_name} Function"
  function_name                  = "summarization-function-${local.standard_resource_name}"
  role                           = aws_iam_role.summarization_lambda_role.arn
  timeout                        = 30
  kms_key_arn                    = aws_kms_key.this_aws_kms_key.arn
  image_uri                      = module.summarization_function_ecr.latest_image_uri
  package_type                   = "Image"
  tags                           = local.tags
  reserved_concurrent_executions = -1

  tracing_config {
    mode = "Active"
  }

  # vpc_config {
  #   # If the list of security group ids and subnets are empty,
  #   # this property is effectively ignored
  #   subnet_ids         = [aws_subnet.subnet.id]
  #   security_group_ids = [aws_security_group.sg.id]
  # }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.cluster_table.name
      MODEL_ID            = "anthropic.claude-3-haiku-20240307-v1:0"
    }
  }
}
