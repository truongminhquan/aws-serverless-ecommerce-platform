terraform {
  required_version = ">= 0.12"
  backend "s3" {
    bucket         = "quantm15-terraform-serverless"
    key            = "tfstates/products-svc.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "dev-serverless"
  }
}

provider "aws" {
  region = "us-east-1"
}