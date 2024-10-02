# Create KMS Key and allow the use of it
resource "aws_kms_key" "this_aws_kms_key" {
  description             = "clustering-summarization-${local.standard_resource_name}"
  deletion_window_in_days = 30
  multi_region            = true
  enable_key_rotation     = true
  tags                    = merge(local.tags)
}

resource "aws_kms_key_policy" "this_aws_kms_key_policy" {
  key_id = aws_kms_key.this_aws_kms_key.key_id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "key-default-1",
    "Statement" : [
      {
        "Sid" : "Enable IAM User Permissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::${local.account_id}:root"
        },
        "Action" : "kms:*",
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "logs.${local.region}.amazonaws.com"
        },
        "Action" : [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        "Resource" : "*",
        "Condition" : {
          "ArnEquals" : {
            "kms:EncryptionContext:aws:logs:arn" : "arn:aws:logs:${local.region}:${local.account_id}:log-group:*${local.standard_resource_name}*"
          }
        }
      },
      {
        "Sid" : "Allow service-linked role use of the customer managed key",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : aws_iam_service_linked_role.this_asg_aws_iam_service_linked_role.arn
        },
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Allow attachment of persistent resources",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : aws_iam_service_linked_role.this_asg_aws_iam_service_linked_role.arn
        },
        "Action" : "kms:CreateGrant",
        "Resource" : "*",
        "Condition" : {
          "Bool" : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "this_aws_kms_alias" {
  name          = "alias/clustering-summarization-${local.standard_resource_name}"
  target_key_id = aws_kms_key.this_aws_kms_key.key_id
}