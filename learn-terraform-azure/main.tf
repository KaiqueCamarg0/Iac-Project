# Configure o Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}

    subscription_id = "35789804-a13e-4872-99d8-e9e308059479"
    client_id = "0e246783-1d11-40a6-a98b-02beb69d690a"
    client_secret = "nxk8Q~lQU4eScvggu6VNBMbZvmjcsnfDFmqC4bh9"
    tenant_id = "b1051c4b-3b94-41ab-9441-e73a72342fdd"


}

resource "azurerm_resource_group" "rg" {
  name     = "myTFResourceGroup"
  location = "westus2"
}
