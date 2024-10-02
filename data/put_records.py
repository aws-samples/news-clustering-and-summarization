import boto3
import json
import time
import random
import string
from tqdm import tqdm

STREAM_NAME = "input-stream-clustering-demo2"
PARTITION_KEY = "a"
JSON_FILE_PATH = "./public_data/dataset.dev.json"  # Path to the single JSON file
COUNT = 1200000
BATCH_SIZE = 5

# Create a Kinesis client
kinesis = boto3.client("kinesis")


# Helper function to generate a random partition key
def generate_partition_key():
    return "".join(random.choices(string.ascii_letters + string.digits, k=16))


# Helper function to check record size does not exceed 1MB
def is_record_size_valid(record):
    return len(record) < 1024 * 1024  # less than 1MB


# Helper function to check batch size does not exceed 5MB
def is_batch_size_valid(batch):
    return (
        sum(len(record["Data"]) for record in batch) < 5 * 1024 * 1024
    )  # less than 5MB


# Read the JSON data from the file
with open(JSON_FILE_PATH, "r") as f:
    data_list = json.load(f)

# Iterate through the JSON data in batches
for batch_index in tqdm(range(0, min(COUNT, len(data_list)), BATCH_SIZE)):
    batch_list = data_list[batch_index : batch_index + BATCH_SIZE]
    data_json = json.dumps(batch_list)

    # Check if the individual record size is valid
    if not is_record_size_valid(data_json):
        print(
            f"Batch starting at index {batch_index} exceeds the maximum allowed size of 1MB."
        )
        continue  # Skip this batch

    # Create a record to put to Kinesis
    record = {
        "Data": data_json,
        "PartitionKey": generate_partition_key(),
    }

    records_to_put = [record]

    # Add the record to the batch if it doesn't exceed the batch size
    if is_batch_size_valid(records_to_put):
        # Delay for 0.2 seconds
        time.sleep(0.2)

        # Create the PutRecords request
        put_records_request = {
            "Records": records_to_put,
            "StreamName": STREAM_NAME,
        }

        # Put the records to Kinesis
        response = kinesis.put_records(**put_records_request)

        # Check for any failed records
        failed_records = response.get("Records", [])
        for record in failed_records:
            if "ErrorCode" in record:
                print(
                    f"Error: {record['ErrorCode']}, Message: {record['ErrorMessage']}"
                )
    else:
        print(
            f"Batch starting at index {batch_index} would exceed the batch size limit of 5MB."
        )
