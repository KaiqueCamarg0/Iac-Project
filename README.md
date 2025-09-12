# Iac-Project

This project is Infrastructure as Code on the Azure Cloud.

This infrastructure account starts with two Virtual Machines, and they are automatically scaled when CPU usage exceeds 80%.

New VMs are added to the load balancer along with the others, all automatically because we use VMSS and Azure Monitor to trigger the duplication script.

We also created an Azure Cosmos DB to store files for possible sites with forms.

The entire infrastructure is created using Terraform code.
