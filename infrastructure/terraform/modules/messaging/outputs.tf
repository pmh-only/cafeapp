output "order_submission_queue_url" {
  description = "SQS order submission queue URL"
  value       = aws_sqs_queue.order_submission.url
}

output "order_submission_queue_arn" {
  description = "SQS order submission queue ARN"
  value       = aws_sqs_queue.order_submission.arn
}

output "payment_processing_queue_url" {
  description = "SQS payment processing queue URL"
  value       = aws_sqs_queue.payment_processing.url
}

output "payment_processing_queue_arn" {
  description = "SQS payment processing queue ARN"
  value       = aws_sqs_queue.payment_processing.arn
}

output "notification_queue_url" {
  description = "SQS notification queue URL"
  value       = aws_sqs_queue.notification.url
}

output "notification_queue_arn" {
  description = "SQS notification queue ARN"
  value       = aws_sqs_queue.notification.arn
}

output "order_events_stream_name" {
  description = "Kinesis order events stream name"
  value       = aws_kinesis_stream.order_events.name
}

output "order_events_stream_arn" {
  description = "Kinesis order events stream ARN"
  value       = aws_kinesis_stream.order_events.arn
}

output "analytics_events_stream_name" {
  description = "Kinesis analytics events stream name"
  value       = aws_kinesis_stream.analytics_events.name
}

output "analytics_events_stream_arn" {
  description = "Kinesis analytics events stream ARN"
  value       = aws_kinesis_stream.analytics_events.arn
}

output "sqs_queue_urls" {
  description = "Map of SQS queue URLs for chaos scripts"
  value = {
    order_submission    = aws_sqs_queue.order_submission.url
    payment_processing  = aws_sqs_queue.payment_processing.url
    notification        = aws_sqs_queue.notification.url
  }
}

output "kinesis_stream_names" {
  description = "List of Kinesis stream names for chaos scripts"
  value       = [
    aws_kinesis_stream.order_events.name,
    aws_kinesis_stream.analytics_events.name
  ]
}
