import boto3


def clear_dynamodb_table(table_name):
    # Initialize a DynamoDB resource
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)

    # Scan the table for all items (note: this is resource-intensive and not recommended for large tables)
    scan = table.scan()
    items = scan["Items"]

    # Continue scanning if all items were not returned in the first scan
    while "LastEvaluatedKey" in scan:
        scan = table.scan(ExclusiveStartKey=scan["LastEvaluatedKey"])
        items.extend(scan["Items"])

    # Delete items in batches
    with table.batch_writer() as batch:
        for item in items:
            batch.delete_item(
                Key={
                    "PK": item["PK"],  # Primary Key
                    "SK": item["SK"],  # Sort Key, if applicable
                }
            )

    print(f"Cleared {len(items)} items from the table {table_name}.")


def clear_sqs_queue(queue_name):
    sqs = boto3.client("sqs")
    response = sqs.get_queue_url(QueueName=queue_name)
    queue_url = response['QueueUrl']
    response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
    messages = response.get("Messages", [])
    for message in messages:
        sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
    print(f"Cleared {len(messages)} messages from the queue {queue_name}.")


def remove_s3_objects(bucket_name):
    s3 = boto3.client("s3")
    s3.delete_object(Bucket=bucket_name, Key="checkpoint.pkl")
    print(f"Deleted the 'checkpoint.pkl' object from the bucket {bucket_name}.")

def terminate_ec2_instance(instance_name):
    ec2 = boto3.client("ec2")
    response = ec2.describe_instances(Filters=[
        {'Name': 'tag:Name', 'Values': [instance_name]},
        {'Name': 'instance-state-name', 'Values': ['running']}
    ])
    if response['Reservations']:
        instance_id = response['Reservations'][0]['Instances'][0]['InstanceId']
        ec2.terminate_instances(InstanceIds=[instance_id])
        print(f"Terminated the running EC2 instance {instance_name}.")
    else:
        print(f"No running EC2 instance found with the name {instance_name}.")


# Clean DynamoDB table
table_name = "cluster-table-clustering-demo2"
clear_dynamodb_table(table_name)

# Clean SQS queue
queue_name = "clustering-demo2-queue"
clear_sqs_queue(queue_name)

# Clean S3 bucket, need to find the bucket name dynamically starting with "code-bucket-clustering-demo"
def get_s3_bucket_name(prefix):
    s3 = boto3.client('s3')
    response = s3.list_buckets()
    for bucket in response['Buckets']:
        if bucket['Name'].startswith(prefix):
            print(f"Found S3 bucket: {bucket['Name']}") 
            return bucket['Name']
    return None

bucket_prefix = "code-bucket-clustering-demo"
bucket_name = get_s3_bucket_name(bucket_prefix)
if bucket_name:
    remove_s3_objects(bucket_name)
else:
    print(f"No S3 bucket found with prefix: {bucket_prefix}")

# Terminate EC2 instance
instance_name = "stream-consumer-instance-clustering-demo2"
terminate_ec2_instance(instance_name)
