resource "aws_sfn_state_machine" "summary_sfn" {
  #checkov:skip=CKV_AWS_285: "Ensure State Machine has execution history logging enabled"

  name     = "summary-sfn-${var.app_name}-${var.env_name}"
  role_arn = aws_iam_role.summary_sfn_exec_role.arn

  tracing_configuration {
    enabled = true
  }
  definition = jsonencode({
    Comment = "An example state machine that invokes a Lambda function and updates DynamoDB.",
    StartAt = "SummarizeCluster",
    States = {
      SummarizeCluster = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = aws_lambda_function.summarization_function.arn,
          "Payload.$"  = "$"
        },
        ResultPath = "$.LambdaOutput",
        Next       = "UpdateDynamoDB"
      },
      UpdateDynamoDB = {
        Type     = "Task",
        Resource = "arn:aws:states:::dynamodb:updateItem",
        Parameters = {
          TableName = aws_dynamodb_table.cluster_table.id
          Key = {
            "PK" : {
              "S.$" : "$.cluster_id"
            },
            "SK" : {
              "S.$" : "States.Format('#METADATA#{}', $.cluster_id)"
            }
          },
          "UpdateExpression" : "SET #description = :description_val, #generated_summary = :generated_summary_val, #summary_count = :summary_count_val, #most_common_location = :most_common_location_val, #most_common_organization = :most_common_organization_val, #earliest_date = :earliest_date_val, #latest_date = :latest_date_val",
          "ExpressionAttributeNames" : {
            "#description" : "description",
            "#generated_summary" : "generated_summary",
            "#summary_count" : "summary_count",
            "#most_common_location" : "most_common_location",
            "#most_common_organization" : "most_common_organization",
            "#earliest_date" : "earliest_date",
            "#latest_date" : "latest_date"
          },
          "ExpressionAttributeValues" : {
            ":description_val" : { "S.$" : "$.LambdaOutput.Payload.title" },
            ":generated_summary_val" : { "S.$" : "$.LambdaOutput.Payload.summary" },
            ":summary_count_val" : { "N.$" : "States.Format('{}', $.LambdaOutput.Payload.summary_count)" }, // Convert to a string
            ":most_common_location_val" : { "S.$" : "$.LambdaOutput.Payload.most_common_location" },
            ":most_common_organization_val" : { "S.$" : "$.LambdaOutput.Payload.most_common_organization" },
            ":earliest_date_val" : { "S.$" : "$.LambdaOutput.Payload.earliest_date" },
            ":latest_date_val" : { "S.$" : "$.LambdaOutput.Payload.latest_date" }
          }
        },
        End = true
      }
    }
  })
}
