import json
import boto3
import os


def handler(event, context):
    # Initialize the DynamoDB and Step Functions clients
    dynamodb_client = boto3.client("dynamodb")
    sfn_client = boto3.client("stepfunctions")

    # State Machine ARN and the threshold for number_of_articles from environment variables
    state_machine_arn = os.environ["STATE_MACHINE_ARN"]
    articles_threshold = int(os.environ["ARTICLES_THRESHOLD"])
    article_cap = 3  # A multiple of articles_threshold, to stop processing summaries
    # DynamoDB table name
    table_name = os.environ["DYNAMODB_TABLE_NAME"]

    # Process each record in the DynamoDB Stream
    for record in event[
        "Records"
    ]:  # ! ToDo aggregate records and send them in batch instead of one at at Time
        if record["eventName"] == "INSERT":
            new_image = record["dynamodb"].get("NewImage", {})
            print("New Record")
            if "type" in new_image and new_image["type"]["S"] == "article":
                print("Record is an Article")

                # Extract primary key (PK)
                pk_value = new_image["PK"]["S"]
                metadata_key = f"#METADATA#{pk_value}"
                print("PK is", pk_value)

                # Get the item with PK and #METADATA#[PK] sort key
                response = dynamodb_client.get_item(
                    TableName=table_name,
                    Key={"PK": {"S": pk_value}, "SK": {"S": metadata_key}},
                )
                item = response.get("Item", {})
                print("Cluster: ", item)
                
                # If we get an empty item with no articles move to the next record
                if "number_of_articles" not in item:
                    continue

                summary_count = int(item.get("summary_count", {"N": "0"})["N"])
                lower_limit_flag = int(item["number_of_articles"]["N"]) > articles_threshold * (summary_count + 1)
                upper_limit_flag = int(item["number_of_articles"]["N"]) < 3 * articles_threshold
                
                print("Summary Count:", summary_count)
                print("Lower Limit Flag:", lower_limit_flag)
                print("Upper Limit Flag:", upper_limit_flag)
                print("Overall flag:", (lower_limit_flag and upper_limit_flag) or (lower_limit_flag and summary_count == 0))

                # Check if number_of_articles is within a range or if it is outside the upper limit but still hasn't been summarized
                if (lower_limit_flag and upper_limit_flag) or (lower_limit_flag and summary_count == 0):
                    # Prepare data for Step Functions
                    input_data = {
                        "cluster_id": pk_value,
                    }

                    # Start execution of the state machine
                    response = sfn_client.start_execution(
                        stateMachineArn=state_machine_arn, input=json.dumps(input_data)
                    )

                    print(
                        f"Started Step Functions execution for 'article' record: {response['executionArn']}"
                    )
                else:
                    print(
                        "Not enough articles in the cluster yet, less than ",
                        articles_threshold,
                    )

    return {
        "statusCode": 200,
        "body": json.dumps(
            'Processed DynamoDB stream records of type "article" with sufficient count.'
        ),
    }
