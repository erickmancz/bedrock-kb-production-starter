terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.18"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "~> 2.3"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
