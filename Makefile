# List all Make targets in alphabetical order
.PHONY: list send-article

# Terraform Init
init: 
	terraform -chdir=iac/roots/main init

# Deploy all targets in the correct order
deploy-all: 
	terraform -chdir=iac/roots/main apply -auto-approve

# Destroy all targets in the correct order
destroy-all:
	terraform -chdir=iac/roots/main apply -destroy 

send-articles:
	@echo "Sending articles..."
	cd data && ./send_articles.sh && cd ..

download-public-dataset:
	@echo "Downloading public dataset..."
	cd data && ./download_public_data.sh && cd ..

clear-data:
	@echo "Clearing DynamoDB table, SQS queue, S3 bucket DBSCAN memory and removing EC2 instance from ASG..."
	cd data && python clear_data.py && cd ..