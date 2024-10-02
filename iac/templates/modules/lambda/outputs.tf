output "arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the lambda function"
}

output "invocation_arn" {
  value       = aws_lambda_function.function.invoke_arn
  description = "Invocation ARN of the lambda function"
}

