output "payment_processor_function_name" {
  description = "Payment processor Lambda function name"
  value       = aws_lambda_function.payment_processor.function_name
}

output "payment_processor_function_arn" {
  description = "Payment processor Lambda function ARN"
  value       = aws_lambda_function.payment_processor.arn
}

output "analytics_writer_function_name" {
  description = "Analytics writer Lambda function name"
  value       = aws_lambda_function.analytics_writer.function_name
}

output "analytics_writer_function_arn" {
  description = "Analytics writer Lambda function ARN"
  value       = aws_lambda_function.analytics_writer.arn
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_arn" {
  description = "API Gateway REST API ARN"
  value       = aws_api_gateway_rest_api.main.arn
}

output "api_gateway_url" {
  description = "API Gateway invocation URL"
  value       = aws_api_gateway_stage.dev.invoke_url
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.dev.stage_name
}

output "vpc_link_id" {
  description = "VPC Link ID"
  value       = aws_api_gateway_vpc_link.main.id
}
