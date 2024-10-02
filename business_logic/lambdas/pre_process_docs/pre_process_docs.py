import os
import json
import pickle
import boto3
from typing import List, Dict
from bs4 import BeautifulSoup
import re
import base64

kinesis_client = boto3.client("kinesis")
s3_client = boto3.client("s3")

PREPROCESS_BUCKET = os.environ["PREPROCESS_BUCKET"]


def clean_text(text):
    # apply to title
    text = text.replace("&quot;", '"')
    text = re.sub(r'[^:a-zA-Z0-9\s"\'-]', "", text)
    return text


def extract_top_subjects(subject_entry: List[dict], threshold: float):
    subjects = []
    for e in subject_entry:
        if e["relevance"] >= threshold:
            subjects.append(e["long_name"])

    return "StorySubjects: " + ", ".join(subjects)


def extract_top_industries(industries_entry: List[dict], threshold: float):
    industries = []
    for e in industries_entry:
        if e["relevance"] >= threshold:
            industries.append(e["long_name"])

    result = "RelevantIndustries: " + ", ".join(industries) if industries else ""

    return result


def extract_top_organizations(orgs_entry: List[dict], threshold: float):
    orgs = []
    for e in orgs_entry:
        if e["relevance"] >= threshold:
            orgs.append(e["name"])

    result = "RelevantOrganizations: " + ", ".join(orgs) if orgs else ""

    return result


def remove_tags(text: str):
    soup = BeautifulSoup(text, "html.parser")
    return soup.get_text()


def get_names(people: List[Dict], threshold=0.5):

    names = [person["name"] for person in people if person["relevance"] > threshold]

    result = "PeopleOfInterest: " + ", ".join(names) if names else ""

    return result


def get_locations(locations: List[dict], threshold=0.8):
    result = []
    if locations:
        names = [
            location["long_name"]
            for location in locations
            if location["relevance"] > threshold
        ]

        result = "Location: " + ", ".join(names) if names else ""

    return result


def process_data(data: dict):

    # irrelevant columns for embedding
    drop = [
        "vendor_data",
        "headline_only",
        "deckline",
        "version",
        "story_link",
        "copyright_line",
        "display_date",
        "received_date",
        "publication_reason",
        "media",
        "spam",
        "control_flags",
        "issuer",
        "market",
        "business_relevance",
        "cluster_signature",
        "headline_cluster_signature",
        "signals",
        "cik",
        "feed",
    ]

    processed_data = {}
    for k, v in data.items():
        if k not in drop:
            processed_data[k] = v

    processed_data["title"] = clean_text(data["title"])
    processed_data["summary"] = clean_text(
        data["text"]
    )  # No summary in public dataset using text
    processed_data["text"] = remove_tags(data["text"])
    processed_data["publication_date"] = remove_tags(data["date"])

    ## * Additional data that's useful for embeddings but isn't in public data
    # processed_data["subjects"] = extract_top_subjects(data["subjects"], threshold=0.8)
    # processed_data["summary"] = clean_text(data["summary"])
    # processed_data["industries"] = extract_top_industries(
    #     data["industries"], threshold=0.8
    # )
    # processed_data["organizations"] = extract_top_organizations(
    #     data["organizations"], threshold=0.6
    # )
    # processed_data["people"] = get_names(data["people"], threshold=0.5)
    # processed_data["locations"] = get_locations(data.get("locations"), threshold=0.8)

    return processed_data


def handler(events, context):
    event = events[0]
    print("EVENT: ", event)

    encrypted_list = event["data"]
    document_json = base64.b64decode(encrypted_list).decode("utf-8")

    document_list = json.loads(document_json)
    print("Document List: ", document_list)
    s3_key_list = []

    for doc in document_list:
        processed_data = process_data(doc)

        print("Processed Data:")
        print(processed_data)

        s3_key = processed_data["id"] + ".json"
        json_data = json.dumps(processed_data)
        print("Pushing data to ", PREPROCESS_BUCKET + "/" + s3_key)
        s3_client.put_object(Bucket=PREPROCESS_BUCKET, Key=s3_key, Body=json_data)

        s3_key_list.append(s3_key)

    print("End of function: ", s3_key_list)
    return s3_key_list
