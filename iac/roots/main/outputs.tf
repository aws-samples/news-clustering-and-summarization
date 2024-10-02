output "sample_user_creds" {
  description = "Sample User Credentials"
  value       = var.cognito_users
}

output "dns_record_for_application" {
  description = "DNS Address to Access the Application"
  value       = "https://${aws_alb.this_aws_alb_front_end.dns_name}"
}