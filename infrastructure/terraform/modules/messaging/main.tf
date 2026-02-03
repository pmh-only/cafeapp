# SQS Queue - Order Submission (Standard)
resource "aws_sqs_queue" "order_submission" {
  name                       = "${var.project_name}-order-submission-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_submission_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-order-submission-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Dead Letter Queue - Order Submission
resource "aws_sqs_queue" "order_submission_dlq" {
  name                      = "${var.project_name}-order-submission-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-order-submission-dlq-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Queue - Payment Processing (FIFO)
resource "aws_sqs_queue" "payment_processing" {
  name                        = "${var.project_name}-payment-processing-${var.environment}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 300
  message_retention_seconds   = 1209600 # 14 days
  receive_wait_time_seconds   = 20      # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payment_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-payment-processing-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Dead Letter Queue - Payment Processing
resource "aws_sqs_queue" "payment_processing_dlq" {
  name                      = "${var.project_name}-payment-processing-dlq-${var.environment}.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-payment-processing-dlq-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Queue - Notification (Standard)
resource "aws_sqs_queue" "notification" {
  name                       = "${var.project_name}-notification-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-notification-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Dead Letter Queue - Notification
resource "aws_sqs_queue" "notification_dlq" {
  name                      = "${var.project_name}-notification-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-notification-dlq-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Kinesis Data Stream - Order Events
resource "aws_kinesis_stream" "order_events" {
  name             = "${var.project_name}-order-events-${var.environment}"
  shard_count      = var.kinesis_order_events_shard_count
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = "${var.project_name}-order-events-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Kinesis Data Stream - Analytics Events
resource "aws_kinesis_stream" "analytics_events" {
  name             = "${var.project_name}-analytics-events-${var.environment}"
  shard_count      = var.kinesis_analytics_events_shard_count
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = "${var.project_name}-analytics-events-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}
