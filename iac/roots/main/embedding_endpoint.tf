# Create an S3 bucket for storing model artifacts
module "model_bucket" {
  source      = "../../templates/modules/s3_bucket"
  name_prefix = "models-${var.app_name}-${var.env_name}"
  log_bucket  = module.log_bucket.name
}

resource "aws_s3_object" "uncompressed_model_artifact" {
  bucket = module.model_bucket.name

  for_each      = fileset("../../../business_logic/model_artifacts/embedding/model", "**/*.*")
  key           = "model/${each.value}"
  source        = "../../../business_logic/model_artifacts/embedding/model/${each.value}"
  source_hash   = filemd5("../../../business_logic/model_artifacts/embedding/model/${each.value}")
  content_type  = each.value
  force_destroy = true
}


# Define IAM Role for SageMaker
resource "aws_iam_role" "sagemaker_execution_role" {

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "sagemaker.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sagemaker_policy" {

  description = "Policy for SageMaker access to S3 and IAM role assumption"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [module.model_bucket.arn, "${module.model_bucket.arn}/*"],
      }
    ]
  })
}

# Attach SageMaker permissions to IAM role
resource "aws_iam_policy_attachment" "sagemaker_permissions" {

  name       = "sagemaker_permissions"
  roles      = [aws_iam_role.sagemaker_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" # Adjust permissions as needed
}

resource "aws_iam_policy_attachment" "sagemaker_policy_attachment" {

  name       = "SageMakerPolicyAttachment"
  roles      = [aws_iam_role.sagemaker_execution_role.name] # Replace with your IAM role name
  policy_arn = aws_iam_policy.sagemaker_policy.arn
}

# Define SageMaker model  
resource "aws_sagemaker_model" "pytorch_model" {
  count = var.model_name != "titan" ? 1 : 0

  name = "model-${var.app_name}-${var.env_name}"

  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn
  primary_container {
    image = "763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:2.1.0-transformers4.37.0-gpu-py310-cu118-ubuntu20.04"
    environment = {
      BIT_LOADING                   = "4"
      MODEL_NAME                    = var.model_name
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
      SAGEMAKER_PROGRAM             = "inference.py"
      SAGEMAKER_REGION              = data.aws_region.current.name
      SAGEMAKER_SUBMIT_DIRECTORY    = "/opt/ml/model/code"
      # Only for Multi-GPU processing (mistral)
      # HF_MODEL_ID                   = "intfloat/e5-mistral-7b-instruct" # ToDO Paramaterize
      # PYTORCH_CUDA_ALLOC_CONF        = "max_split_size_mb:50" 
      # SAGEMAKER_MODEL_SERVER_WORKERS = 4
    }

    model_data_source {
      s3_data_source {
        s3_uri           = "s3://${module.model_bucket.id}/model/"
        s3_data_type     = "S3Prefix"
        compression_type = "None"
      }
    }
  }

  depends_on = [
    aws_s3_object.uncompressed_model_artifact,
    module.model_bucket,
    aws_iam_role.sagemaker_execution_role
  ]
}

# Create SageMaker endpoint configuration
resource "aws_sagemaker_endpoint_configuration" "pytorch_endpoint_config" {
  count = var.model_name != "titan" ? 1 : 0

  #checkov:skip=CKV_AWS_98: "Ensure all data stored in the Sagemaker Endpoint is securely encrypted at rest"
  name = "endpoint-config-${var.app_name}-${var.env_name}"
  production_variants {
    variant_name           = "${var.app_name}-${var.env_name}-traffic"
    instance_type          = var.embedding_endpoint_instance_type
    initial_instance_count = var.embedding_endpoint_instance_count
    model_name             = aws_sagemaker_model.pytorch_model[count.index].name
  }
}

# Create SageMaker endpoint
resource "aws_sagemaker_endpoint" "pytorch_endpoint" {
  count = var.model_name != "titan" ? 1 : 0

  name                 = "endpoint-${var.app_name}-${var.env_name}"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.pytorch_endpoint_config[count.index].name
}

# Auto scaling
# resource "aws_appautoscaling_target" "sagemaker_target" {
#   max_capacity       = var.max_embedding_instance_count
#   min_capacity       = var.min_embedding_instance_count
#   resource_id        = "endpoint/${aws_sagemaker_endpoint.pytorch_endpoint.name}/variant/${var.app_name}-${var.env_name}-traffic"
#   scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
#   service_namespace  = "sagemaker"
# }

# resource "aws_appautoscaling_policy" "sagemaker_policy" {
#   name               = "${var.app_name}-${var.env_name}-target-tracking"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.sagemaker_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.sagemaker_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.sagemaker_target.service_namespace

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
#     }
#     target_value       = 3
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 60
#   }
# }
