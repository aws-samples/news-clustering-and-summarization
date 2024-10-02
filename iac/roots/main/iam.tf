# IAM Roles
resource "aws_iam_role" "preprocessing_lambda_role" {
  name = "preprocessing-lambda_role-${var.app_name}-${var.env_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      }
    ],
  })
}

resource "aws_iam_role" "embedding_lambda_role" {
  name = "embedding-lambda_role-${var.app_name}-${var.env_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      }
    ],
  })
}

resource "aws_iam_role" "step_functions_role" {
  name = "step_functions_role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "states.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_policy" "step_functions_lambda_policy" {
  description = "Policy for Lamba Access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction"
        ],
        "Resource" : [
          aws_lambda_function.pre_processing_lambda.arn, aws_lambda_function.embedding_lambda.arn
        ]
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "step_functions_lambda_policy_attachment" {
  name       = "step_functions_lambda_policy_attachment"
  roles      = [aws_iam_role.step_functions_role.name]
  policy_arn = aws_iam_policy.step_functions_lambda_policy.arn
}


resource "aws_iam_role" "cloudwatch_event_role" {
  name = "cloudwatch_event_role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : "sts:AssumeRole",
        Effect : "Allow",
        Principal : {
          Service : "pipes.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn_policy" {
  name = "eventbridge_sfn_policy-${var.app_name}-${var.env_name}"
  role = aws_iam_role.cloudwatch_event_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["states:StartExecution"]
        Resource = [aws_sfn_state_machine.pre_processing_sfn.arn]
        Effect   = "Allow"
      },
      {
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.dead_letter_queue.arn]
        Effect   = "Allow"
      }
    ]
    }
  )
}

data "aws_iam_policy_document" "eventbridge_kinesis_policy_document" {
  statement {
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListStreams",
      "kinesis:ListShards"
    ]
    resources = [aws_kinesis_stream.input_stream.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_kinesis_policy" {
  name   = "eventbridge_kinesis_policy-${var.app_name}-${var.env_name}"
  role   = aws_iam_role.cloudwatch_event_role.id
  policy = data.aws_iam_policy_document.eventbridge_kinesis_policy_document.json
}

# Consumer Role
resource "aws_iam_role" "stream_consumer_role" {
  name = "stream-consumer-role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "stream_consumer_policy" {
  name = "stream_consumer_policy-${var.app_name}-${var.env_name}"
  role = aws_iam_role.stream_consumer_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = ["${module.cluster_code_bucket.arn}/*", module.cluster_code_bucket.arn]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        "Resource" : [
          "*"
        ]
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:Scan",
        ],
        Effect = "Allow",
        Resource = [
          aws_dynamodb_table.cluster_table.arn,
          "${aws_dynamodb_table.cluster_table.arn}/*"
        ],
      },
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteMessageBatch",
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.tags.arn
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_execution_policy" {
  #checkov:skip=CKV_AWS_355: "Ensure no IAM policies documents allow &quot;*&quot; as a statement's resource for restrictable actions"
  #checkov:skip=CKV_AWS_290: "Ensure IAM policies does not allow write access without constraints"
  description = "Policy for Lambda Execution"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        "Sid" : "AllowModelnvocation",
        "Effect" : "Allow",
        "Action" : [
          "bedrock:InvokeModel"
        ],
        "Resource" : "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ],
        Resource = "*"
      },
      {
        "Sid" : "ECRGrantsToConnectAndDownload",
        "Effect" : "Allow",
        "Action" : [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        "Resource" : "arn:aws:ecr:*:*:repository/*"
      },
      {
        "Sid" : "AccessToEncryptAndDeccryptKMSKeys",
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListGrants",
          "kms:ListKeys",
          "kms:ListAliases",
          "kms:ListKeyPolicies",
          "kms:ListResourceTags",
          "kms:ListRetirableGrants",
          "kms:ReEncryptTo"
        ],
        "Resource" : [
          aws_kms_key.this_aws_kms_key.arn
        ]
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_kinesis_policy" {
  description = "Policy for Kinesis Stream Access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
        ],
        "Resource" : [
          aws_kinesis_stream.input_stream.arn
        ]
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_sagemaker_policy" {
  description = "Policy for Sagemaker Endpoint Access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "Sagemaker:InvokeEndpoint"
        ],
        "Resource" : [
          var.model_name != "titan" ? aws_sagemaker_endpoint.pytorch_endpoint[0].arn : "arn:aws:sagemaker:us-west-2:123456789012:endpoint/dummy-endpoint" # Generate a dummy arn if we aren't using ours
        ]
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_sqs_policy" {
  description = "Policy for Sagemaker Endpoint Access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:SendMessage"
        ],
        "Resource" : [
          aws_sqs_queue.tags.arn
        ]
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_s3_policy" {
  description = "Policy for S3 Access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ],
        "Resource" : [
          module.preprocess_data_bucket.arn,
          "${module.preprocess_data_bucket.arn}/*",
          module.embedding_data_bucket.arn,
          "${module.embedding_data_bucket.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_execution_policy_attachment" {
  name       = "lambda_execution_policy_attachment"
  roles      = [aws_iam_role.summarization_lambda_role.name, aws_iam_role.trigger_sfn_lambda_role.name, aws_iam_role.preprocessing_lambda_role.name, aws_iam_role.embedding_lambda_role.name, aws_iam_role.step_functions_role.name]
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_kinesis_policy_attachment" {
  name       = "lambda_kinesis_policy_attachment"
  roles      = [aws_iam_role.preprocessing_lambda_role.name]
  policy_arn = aws_iam_policy.lambda_kinesis_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_sagemaker_policy_attachment" {
  name       = "lambda_sagemaker_policy_attachment"
  roles      = [aws_iam_role.embedding_lambda_role.name]
  policy_arn = aws_iam_policy.lambda_sagemaker_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_s3_policy_attachment" {
  name       = "lambda_s3_policy_attachment"
  roles      = [aws_iam_role.embedding_lambda_role.name, aws_iam_role.preprocessing_lambda_role.name]
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_sqs_policy_attachment" {
  name       = "lambda_sqs_policy_attachment"
  roles      = [aws_iam_role.embedding_lambda_role.name, aws_iam_role.step_functions_role.name]
  policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}

resource "aws_iam_role" "summarization_lambda_role" {
  name = "summarization-role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy" "summarization_policy" {
  #checkov:skip=CKV_AWS_355: "Ensure no IAM policies documents allow &quot;*&quot; as a statement's resource for restrictable actions"
  #checkov:skip=CKV_AWS_290: "Ensure IAM policies does not allow write access without constraints"
  #checkov:skip=CKV_AWS_355: "Ensure no IAM policies documents allow &quot;*&quot; as a statement's resource for restrictable actions"
  name = "summarization-policy-${var.app_name}-${var.env_name}"
  role = aws_iam_role.summarization_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:Query",
        ],
        Resource = [
          aws_dynamodb_table.cluster_table.arn,
          "${aws_dynamodb_table.cluster_table.arn}/*"
        ],
        Effect = "Allow",
      },
      {
        Action   = "bedrock:InvokeModel",
        Resource = "*",
        Effect   = "Allow",
      },
      {
        Action   = "logs:*",
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*",
        Effect   = "Allow",
      },
    ],
  })
}

resource "aws_iam_role" "summary_sfn_exec_role" {
  name = "summary_sfn_exec_role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "states.amazonaws.com"
        },
      },
    ],
  })
}

# IAM Policy for Step Functions to write to DynamoDB
resource "aws_iam_role_policy" "summary_sfn_exec_policy" {
  name = "summary_sfn_exec_policy-${var.app_name}-${var.env_name}"
  role = aws_iam_role.summary_sfn_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Effect = "Allow",
        Resource = [
          aws_dynamodb_table.cluster_table.arn,
          "${aws_dynamodb_table.cluster_table.arn}/*"
        ],
      },
      {
        Action = [
          "lambda:InvokeFunction"
        ],
        Effect   = "Allow",
        Resource = [aws_lambda_function.summarization_function.arn]
      },
      {
        Action : [
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:PutTelemetryRecords",
          "xray:PutTraceSegments"
        ],
        Resource : "*",
        Effect : "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "trigger_sfn_lambda_role" {
  name = "triggers-sfn-role-${var.app_name}-${var.env_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy" "trigger_sfn_policy" {
  name = "trigger-sfn-policy-${var.app_name}-${var.env_name}"
  role = aws_iam_role.trigger_sfn_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "states:StartExecution",
        ],
        Resource = aws_sfn_state_machine.summary_sfn.arn,
        Effect   = "Allow",
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ],
        Resource = [
          aws_dynamodb_table.cluster_table.arn,
          "${aws_dynamodb_table.cluster_table.arn}/*"
        ],
        Effect = "Allow",
      },
      {
        Action   = "logs:*",
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*",
        Effect   = "Allow",
      },
    ],
  })
}

resource "aws_iam_service_linked_role" "this_asg_aws_iam_service_linked_role" {
  aws_service_name = "autoscaling.amazonaws.com"
  custom_suffix    = local.standard_resource_name
  description      = "A service linked role for autoscaling to use to call other AWS services"
  tags             = local.tags
}
