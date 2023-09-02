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
    name            = "category"
    hash_key        = "category"
    range_key       = "productId"
    projection_type = "ALL"
  }
}

resource "aws_dynamodb_table_item" "master_item" {
  table_name = aws_dynamodb_table.product_table.name
  hash_key   = aws_dynamodb_table.product_table.hash_key

  item = <<ITEM
{
  "productId": {
    "S": "f380305b-99fe-45ba-b1ab-ba6349d141a2"
  },
  "name": {
    "S": "Product1"
  },
  "package": {
    "M": {
      "height": {
        "N": "0"
      },
      "length": {
        "N": "0"
      },
      "weight": {
        "N": "0"
      },
      "width": {
        "N": "0"
      }
    }
  },
  "price": {
    "N": "0"
  }
}
ITEM
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
      "dynamodb:BatchGetItem"
    ]

    resources = ["*"]

    effect = "Allow"
  }
}

resource "aws_iam_policy" "readpolicy" {
  name   = "Custom-DynamoDb-Read-Policy"
  policy = data.aws_iam_policy_document.readpolicy.json
}

resource "aws_iam_role" "product_validate_function_iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.product_validate_function_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda-role-readpolicy-attachment" {
  role       = aws_iam_role.product_validate_function_iam_for_lambda.name
  policy_arn = aws_iam_policy.readpolicy.arn
}

data "archive_file" "simple_lambda_zip" {
  source_dir  = "../src/validate"
  output_path = "${path.module}/lambda_function_payload.zip"
  type        = "zip"
}

resource "aws_lambda_function" "product_validate_function" {
  filename         = data.archive_file.simple_lambda_zip.output_path
  function_name    = "product_validate_function"
  source_code_hash = data.archive_file.simple_lambda_zip.output_base64sha256
  role             = aws_iam_role.product_validate_function_iam_for_lambda.arn
  handler          = "main.handler"
  architectures    = ["arm64"]


  runtime = "python3.9"
  environment {
    variables = {
      ENVIRONMENT               = "dev"
      POWERTOOLS_SERVICE_NAME   = "products"
      POWERTOOLS_TRACE_DISABLED = "false"
      TABLE_NAME                = "product_table"
      LOG_LEVEL                 = "DEBUG"
      EVENT_BUS_NAME            = "/ecommerce/dev/platform/event-bus/name"
    }
  }
}

resource "aws_api_gateway_rest_api" "products-svc-api-gateway" {
  # body = "${file("../resources/openapi.json")}"

  name = "products-svc-api-gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "products-svc-api-gateway-resource-backend" {
  rest_api_id = aws_api_gateway_rest_api.products-svc-api-gateway.id
  parent_id   = aws_api_gateway_rest_api.products-svc-api-gateway.root_resource_id
  path_part   = "backend"
}

resource "aws_api_gateway_resource" "products-svc-api-gateway-resource-validate" {
  rest_api_id = aws_api_gateway_rest_api.products-svc-api-gateway.id
  parent_id   = aws_api_gateway_resource.products-svc-api-gateway-resource-backend.id
  path_part   = "validate"
}

resource "aws_api_gateway_method" "products-svc-api-gateway-resource-method" {
  rest_api_id   = aws_api_gateway_rest_api.products-svc-api-gateway.id
  resource_id   = aws_api_gateway_resource.products-svc-api-gateway-resource-validate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.products-svc-api-gateway.id
  resource_id             = aws_api_gateway_method.products-svc-api-gateway-resource-method.resource_id
  http_method             = aws_api_gateway_method.products-svc-api-gateway-resource-method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.product_validate_function.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.product_validate_function.function_name}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.products-svc-api-gateway.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "dev_stage" {
  depends_on = [
    "aws_api_gateway_integration.lambda"
  ]

  rest_api_id = "${aws_api_gateway_rest_api.products-svc-api-gateway.id}"
  stage_name  = "dev"
}