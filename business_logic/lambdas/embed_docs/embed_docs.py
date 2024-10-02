import os
import json
import boto3

SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
MAX_ARTICLES = int(os.environ["MAX_ARTICLES"])
EMBEDDING_ENDPOINT_NAME = os.environ["EMBEDDING_ENDPOINT_NAME"]
EMBEDDING_MODEL = os.environ["EMBEDDING_MODEL"]
MAX_LENGTH = int(os.environ["MAX_LENGTH"])
EMBEDDING_FIELDS = [
    "title",
    "summary",
    "text",
    # * Useful for embneddings not in public dataset
    # "subjects",
    # "industries",
    # "organizations",
    # "people",
    # "locations",
]
PREPROCESS_BUCKET = os.environ["PREPROCESS_BUCKET"]
EMBEDDING_BUCKET = os.environ["EMBEDDING_BUCKET"]

s3_client = boto3.client("s3")
sagemaker_client = boto3.client("sagemaker-runtime")
sqs_client = boto3.client("sqs")
bedrock_client = boto3.client("bedrock-runtime")


def create_concat_text(doc_list):
    concat_list = []
    for doc in doc_list:
        concat_text = []
        for field in EMBEDDING_FIELDS:
            if isinstance(doc[field], str):
                concat_text.append(doc[field])

        # concat_text = [doc[f] for f in EMBEDDING_FIELDS]
        print("Concat Text", concat_text)
        concatenated = "\n".join(concat_text)
        concat_list.append(concatenated)
    return concat_list


# Event is list of S3 keys
def handler(event, context):

    document_list = []
    for s3_key in event:
        print("Getting article from ", s3_key)
        response = s3_client.get_object(Bucket=PREPROCESS_BUCKET, Key=s3_key)
        data = response["Body"].read().decode("utf-8")
        doc = json.loads(data)
        document_list.append(doc)

    text_list = create_concat_text(document_list)
    print("Text list: ", text_list)

    data = {"input_texts": text_list, "max_length": MAX_LENGTH}

    # Print the content
    print("Data:")
    print(data)
    json_data = json.dumps(data)
    print("Embedding endpoint name: ", EMBEDDING_ENDPOINT_NAME)

    if len(document_list) > MAX_ARTICLES:
        document_list[:MAX_ARTICLES]

    # If titan use bedrock, otherwise use sagemaker
    prediction = {"embeddings": []}
    if EMBEDDING_MODEL == "titan":
        for text in text_list:
            response = bedrock_client.invoke_model(
                body=json.dumps(
                    {"inputText": text, "dimensions": MAX_LENGTH, "normalize": True}
                ),
                modelId="amazon.titan-embed-text-v2:0",
                accept="application/json",
                contentType="application/json",
            )
            response_body = json.loads(response.get("body").read().decode("utf-8"))
            prediction["embeddings"].append(response_body["embedding"])
    else:
        # Push content to the SageMaker endpoint
        response = sagemaker_client.invoke_endpoint(
            EndpointName=EMBEDDING_ENDPOINT_NAME,
            ContentType="application/json",
            Body=json_data,
        )
        prediction = json.loads(response["Body"].read().decode("utf-8"))

    print("Prediction:")
    print(prediction)
    embedding_list = prediction["embeddings"]

    for i, doc in enumerate(document_list):
        doc["concat_embedding"] = [embedding_list[i]]
        message_body = json.dumps(doc)
        if len(message_body.encode("utf-8")) > 262144:
            print(f"Skipping item at index {i} due to size limit")
            continue
        s3_key = doc["id"] + ".json"
        json_data = json.dumps(doc)
        sqs_client.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=json_data)
        s3_client.put_object(Bucket=EMBEDDING_BUCKET, Key=s3_key, Body=json_data)

    print("End of function")
    return "Success"
