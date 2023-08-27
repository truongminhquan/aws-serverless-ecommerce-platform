resource "aws_dynamodb_table" "product_table" {
  name             = "product_table"
  hash_key         = "productId"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "productId"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name               = "category"
    hash_key           = "category"
    range_key          = "productId"
    projection_type    = "ALL"
  }
}

data "aws_iam_policy_document" "product_validate_function_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "readpolicy" {
  statement {
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:ListTables",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]

    resources = ["*"]

    effect = "Allow"
  }
}

resource "aws_iam_role" "product_validate_function_iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.product_validate_function_assume_role.json
}



resource "aws_lambda_function" "product_validate_function" {
  filename      = "../src/validate/"
  function_name = "product_validate_function"
  role          = aws_iam_role.product_validate_function_iam_for_lambda.arn
  handler       = "main.handler"
  architectures = ["arm64"]
  

  runtime = "python3.9"
  environment {
    variables = {
        ENVIRONMENT = "dev"
      POWERTOOLS_SERVICE_NAME = "products"
      POWERTOOLS_TRACE_DISABLED = "false"
      TABLE_NAME = "product_table"
      LOG_LEVEL = "DEBUG"
      EVENT_BUS_NAME = "/ecommerce/dev/platform/event-bus/name"
    }
  }
}