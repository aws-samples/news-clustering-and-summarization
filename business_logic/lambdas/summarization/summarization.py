import json
import os
import boto3
from datetime import datetime
from collections import Counter

bedrock_client = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")
model_id = os.environ["MODEL_ID"]
table_name = os.environ["DYNAMODB_TABLE_NAME"]


def generate_average_cluster_data(articles):
    # Initialize counters and variables for tracking
    location_counter = Counter()
    organization_counter = Counter()
    earliest_date = datetime.max
    latest_date = datetime.min

    # Check if articles list is empty
    if not articles:
        return {
            "most_common_location": "",
            "most_common_organization": "",
            "earliest_date": "",
            "latest_date": "",
        }

    # Process each article
    for article in articles:
        publication_date = None
        if article.get("publication_date"):
            publication_date = datetime.fromisoformat(
                article.get("publication_date").rstrip("Z")
            )
        location_counter.update(article.get("locations"))
        organization_counter.update(article.get("organizations"))

        if publication_date and publication_date < earliest_date:
            earliest_date = publication_date
        if publication_date and publication_date > latest_date:
            latest_date = publication_date

    # Handle case where no locations or organizations were found
    if location_counter:
        most_common_location, _ = location_counter.most_common(1)[0]
    else:
        most_common_location = ""

    if organization_counter:
        most_common_organization, _ = organization_counter.most_common(1)[0]
    else:
        most_common_organization = ""

    # Adjusted return to include a check for the date range
    return {
        "most_common_location": most_common_location,
        "most_common_organization": most_common_organization,
        "earliest_date": earliest_date.strftime("%Y-%m-%d %H:%M:%S"),
        "latest_date": latest_date.strftime("%Y-%m-%d %H:%M:%S"),
    }


def get_cluster_data(cluster_id):
    # Initialize a DynamoDB client
    table = dynamodb.Table(table_name)

    # Query the table
    response = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("PK").eq(cluster_id),
    )
    cluster_data = response.get("Items", [])

    # Extract the first item
    metadata = cluster_data[0]
    articles = cluster_data[1:]
    summary_count = metadata.get("summary_count", 0)

    return metadata.get("generated_summary", ""), summary_count, articles


def generate_bedrock_claude(input_tokens):
    claude_body = {
        "modelId": model_id,
        "body": json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "messages": [{"role": "user", "content": input_tokens}],
                "max_tokens": 500,  # the higher this is the longer it takes
                "temperature": 0.1,  # these parameters affect response diversity
                "top_p": 1,
                "top_k": 100,
            }
        ),
    }
    bedrock_response = bedrock_client.invoke_model(
        **claude_body,
        accept="*/*",
        contentType="application/json",
    )
    body = bedrock_response.get("body")
    rd = body.read()
    body_json = json.loads(rd)
    try:
        response = body_json["content"][0].get("text")
        output_token_cnt = int(
            bedrock_response["ResponseMetadata"]["HTTPHeaders"].get(
                "x-amzn-bedrock-output-token-count"
            )
        )
        input_token_cnt = int(
            bedrock_response["ResponseMetadata"]["HTTPHeaders"].get(
                "x-amzn-bedrock-input-token-count"
            )
        )
    except Exception:
        print(rd)
    return input_token_cnt, output_token_cnt, response


def parse_res(res):
    try:
        title = res.split("<title>")[-1].split("</title>")[0]
        summary = res.split("<summary>")[-1].split("</summary>")[0]
        return title, summary
    except Exception:
        return "<Title>", res


def generate_cluster_summary(previous_summary, articles, limit):
    input_context = []
    # If we've done summaries before we'll limit the input tokens for each summary
    limit_number = 2000
    if limit:
        limit_number = 1500
    instructions = "You will be provided with multiple sets of titles and summaries from different articles in <context> tag, and the current title and summary for a story in <story> tag. Compile, summarize and update the current title and summary for the story. The summary should be less than 100 words. Put the generated context inside <title> and <summary> tag. Do not hallucinate or make up content.\n\n"
    texts = "\n".join(
        [
            f"title: {article.get('title')}, summary: {article.get('summary', "")[:limit_number]}"
            for article in articles
        ]
    )
    prompt = f"{instructions} <story> \n{previous_summary} </story> \n\n <context>\n{texts}\n</context>\n"
    print("Prompt Length:", len(prompt))
    input_context.append(prompt)
    output = generate_bedrock_claude(prompt[:12000])
    title, summary = parse_res(output[2])

    return {"title": title, "summary": summary}


"""
Event Expected in following format
{
    cluster_id: "198be4aa-95e8-4d8e-9e0b-a37eef6c29e2"
}
"""


def handler(event, context):
    print("Input Event", event)

    previous_summary, summary_count, articles = get_cluster_data(event["cluster_id"])
    generated_summary = generate_cluster_summary(previous_summary, articles, summary_count > 0)
    averages = generate_average_cluster_data(articles)

    print("Generated Summary", generated_summary)
    print("Averages", averages)

    return {**generated_summary, **averages, "summary_count": summary_count + 1}
