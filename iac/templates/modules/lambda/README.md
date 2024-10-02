# What is this module for?
This module creates following resources:
* Lambda function
* **prod** and **test** lambda aliases
* Lambda execution IAM role

# How do I use it?
Simple useage:

```hcl
module "lambda" {
  source = "../modules/lambda"
  function_name = "test"
  handler_name  = "app.handler"
  description   = "Test function"
  resource_policy = data.aws_iam_policy_document.lambda_policy.json
} 
```
# Inputs
|Variable name|Required|Description|
|-------------|--------|-----------|
|function_name|Yes|Name of the lambda function|
|handler_name|Yes|Name of the function that will act as lambda handler e.g. **app.handler** for python|
|description|Yes|Description of the function|
|resource_policy|Yes|IAM policy to be attached to lambda execution role in JSON|
|runtime|No|Lambda runtime e.g. dotnetcore. Defaults to **python3.9**|
|code_archive|No|Zip file containing lambda code appropriate for the runtime|
|environment_variables|No|Map of environment variables. **NOTE:** Environment variables are not encrypted so do not use them to pass credentials or other secrets to lambda.|
|meomory_size|No|Memory size for the lambda in MB. Defaults to 512|
|subnet_ids|No|List of subnet ids if lambda is to be attached to a VPC|
|security_group_ids|No|List of security group ids if lambda is to be attached to a VPC|


# Outputs
|Output|Description|
|---|---|
|arn|ARN of the lambda function|
|invocation_arn|Invocation ARN of the function|

# Ignored checkov warnings

|Warning|Description|Reason|
|---|---|---|
|CKV_AWS_116|Ensure that AWS Lambda function is configured for a Dead Letter Queue(DLQ)|Ony valid/required for asynchronous lambda functions|
|CKV_AWS_173|Check encryption settings for Lambda environmental variable|No secrets should be stored in env variables|
|CKV_AWS_272|Ensure AWS Lambda function is configured to validate code-signing|Surplus to requirements and overhead not required for majority of PoCs|
