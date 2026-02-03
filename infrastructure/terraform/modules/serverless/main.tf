# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-execution-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Wait for IAM to propagate
resource "time_sleep" "wait_for_iam" {
  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
  create_duration = "30s"
}

# Lambda policy for SQS, DynamoDB, Kinesis, CloudWatch
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-lambda-permissions-${var.environment}"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = var.payment_processing_queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = var.analytics_events_stream_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
}

# Payment Processor Lambda Function
resource "aws_lambda_function" "payment_processor" {
  function_name = "${var.project_name}-payment-processor-${var.environment}"
  role          = aws_iam_role.lambda_execution.arn

  # Placeholder for deployment package
  filename      = "${path.module}/lambda_placeholder.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = var.lambda_payment_memory_size

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      PROJECT_NAME      = var.project_name
      DYNAMODB_TABLE    = "${var.project_name}-payment-transactions-${var.environment}"
      SQS_QUEUE_URL     = var.payment_processing_queue_url
    }
  }

  reserved_concurrent_executions = 100

  dead_letter_config {
    target_arn = aws_sqs_queue.payment_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda_permissions,
    aws_iam_role_policy_attachment.lambda_basic,
    time_sleep.wait_for_iam
  ]

  tags = {
    Name        = "${var.project_name}-payment-processor-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Create placeholder ZIP for Lambda
resource "null_resource" "lambda_placeholder" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "echo 'def lambda_handler(event, context): return {\"statusCode\": 200}' > ${path.module}/handler.py && cd ${path.module} && zip lambda_placeholder.zip handler.py || true"
  }
}

# SQS DLQ for Payment Processor
resource "aws_sqs_queue" "payment_dlq" {
  name                      = "${var.project_name}-payment-lambda-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-payment-lambda-dlq-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Lambda Event Source Mapping - SQS Trigger
resource "aws_lambda_event_source_mapping" "payment_sqs" {
  event_source_arn = var.payment_processing_queue_arn
  function_name    = aws_lambda_function.payment_processor.arn
  batch_size       = 10
  maximum_batching_window_in_seconds = 5

  scaling_config {
    maximum_concurrency = 100
  }
}

# Analytics Writer Lambda Function
resource "aws_lambda_function" "analytics_writer" {
  function_name = "${var.project_name}-analytics-writer-${var.environment}"
  role          = aws_iam_role.lambda_execution.arn

  filename      = "${path.module}/lambda_placeholder.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = var.lambda_analytics_memory_size

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  reserved_concurrent_executions = 50

  tags = {
    Name        = "${var.project_name}-analytics-writer-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_permissions
  ]
}

# Lambda Event Source Mapping - Kinesis Trigger
resource "aws_lambda_event_source_mapping" "analytics_kinesis" {
  event_source_arn  = var.analytics_events_stream_arn
  function_name     = aws_lambda_function.analytics_writer.arn
  starting_position = "LATEST"
  batch_size        = 100
  maximum_batching_window_in_seconds = 10

  maximum_record_age_in_seconds = 3600
  maximum_retry_attempts        = 2
}

# CloudWatch Log Group for Payment Processor
resource "aws_cloudwatch_log_group" "payment_processor" {
  name              = "/aws/lambda/${aws_lambda_function.payment_processor.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-payment-logs-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Log Group for Analytics Writer
resource "aws_cloudwatch_log_group" "analytics_writer" {
  name              = "/aws/lambda/${aws_lambda_function.analytics_writer.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-analytics-logs-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "CloudCafe API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Link for NLB integration (VPC Link only supports NLB, not ALB)
resource "aws_api_gateway_vpc_link" "main" {
  name        = "${var.project_name}-vpc-link-${var.environment}"
  target_arns = [var.nlb_arn]

  tags = {
    Name        = "${var.project_name}-vpc-link-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# API Gateway Resource - /api
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "api"
}

# API Gateway Resource - /api/{proxy+}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

# API Gateway Method - ANY /api/{proxy+}
resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# API Gateway Integration - VPC Link to ALB
resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${var.alb_dns_name}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.proxy
  ]
}

# API Gateway Stage - dev
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "dev"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.project_name}-api-dev-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-api-gateway-logs-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# API Gateway Method Settings for CloudWatch metrics
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.dev.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
    data_trace_enabled = true
  }
}
