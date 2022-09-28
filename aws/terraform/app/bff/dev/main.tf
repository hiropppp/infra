terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.1.0"
    }
  }
}
locals {
  app_name = "webapi"
  host_domain = "unchi.ga"
  app_domain_name = "app.unchi.ga"
  api_domain_name = "api.unchi.ga"
}
provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      application = local.app_name
    }
  }
}
