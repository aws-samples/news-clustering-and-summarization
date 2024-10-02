from typing import List, Optional
import json
import botocore
from clustering import (
    batch_update_numpy_distance_matrix,
    get_sparse_distance_matrix,
)
import numpy as np
import time
import boto3
from sklearn.cluster import DBSCAN
import uuid
from datetime import datetime
import ast  # Use Abstract Syntax Trees module to safely evaluate string representation of dictionaries
import functools
import os
import pickle
import threading
import copy
from botocore.exceptions import ClientError

# Initialize AWS clients
s3 = boto3.client("s3")
ssm = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

# Configuration variables
S3_BUCKET_NAME = os.environ["S3_BUCKET_NAME"]
S3_FILE_KEY = os.environ["S3_FILE_KEY"]
SQS_QUEUE = os.environ["SQS_QUEUE"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]

# Setup for clustering
label_tracker: List[tuple] = []
is_cluster: List[bool] = []
embeds: List = None

distance_matrix = None

unique_article_id = 0
unique_cluster_id = 0
cluster_count = 0

# Stream
batch_times = []  #
processed_pool_sizes = []
incoming_articles = []


def timer(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        end = time.time()
        print(f"{func.__name__}\t{end - start:f}")
        return result

    return wrapper


# Format docs for clustering
@timer
def format_documents(messages):
    print("Format Docs")
    converted_messages = []
    associated_articles = {}
    seen_ids = set()  # Keep track of seen ids

    for msg in messages:
        try:
            message_body = json.loads(msg.get("Body", "{}"))
        except json.JSONDecodeError:
            continue  # Skip this message if there's a problem parsing it

        message_id = message_body.get("id")

        # Check for duplicate ids and skip if found
        if message_id in seen_ids:
            continue
        else:
            seen_ids.add(message_id)

        # Proceed if id is not a duplicate
        embeddings = np.asarray(message_body["concat_embedding"][0])

        converted_messages.append(
            {
                "id": message_id,
                "concat_embedding": embeddings,
            }
        )
        associated_articles[message_id] = message_body

    return converted_messages, associated_articles


@timer
def batch_get_meta_data(keys_to_get):
    items = []  # List to store the successfully retrieved items
    missing_keys = []  # List to store keys of items that were not found
    unprocessed_keys = keys_to_get  # Start with all keys as unprocessed

    while unprocessed_keys:
        # Prepare the current batch request
        request = {
            "RequestItems": {
                DYNAMODB_TABLE: {
                    "Keys": unprocessed_keys[
                        :100
                    ]  # DynamoDB limits to 100 items per batch
                }
            }
        }

        # Perform the batch get operation
        response = dynamodb.batch_get_item(RequestItems=request["RequestItems"])

        # Add the successfully retrieved items to our results list
        items.extend(response["Responses"][DYNAMODB_TABLE])

        # Update unprocessed_keys based on UnprocessedKeys from the response
        unprocessed_keys_info = response.get("UnprocessedKeys", {})
        unprocessed_keys = unprocessed_keys_info.get(DYNAMODB_TABLE, {}).get("Keys", [])

        # If there are more than 100 unprocessed keys, prepare the next batch
        if unprocessed_keys:
            unprocessed_keys = unprocessed_keys[100:]

    # Assuming items is the list of items returned from DynamoDB
    found_keys = [{"PK": item["PK"], "SK": item["SK"]} for item in items]

    # Assuming keys_to_get is the list of keys you originally requested
    requested_keys = keys_to_get  # No change needed if keys_to_get already structured as [{'PK': ..., 'SK': ...}, ...]

    # To find missing keys, we'll convert these dictionaries to a comparable format (e.g., string) because dictionaries cannot be directly compared in sets
    found_keys_str = set([str(k) for k in found_keys])
    requested_keys_str = set([str(k) for k in requested_keys])

    # Identify missing keys by comparing their string representations
    missing_keys_str = requested_keys_str - found_keys_str

    # Convert back to dictionaries using ast.literal_eval for safety
    missing_keys = [ast.literal_eval(k) for k in missing_keys_str]

    return items, missing_keys


def check_for_repeats(strings):
    seen = set()
    for string in strings:
        if string in seen:
            return True  # Found a repeat
        seen.add(string)
    return False  # No repeats found


def find_duplicates(items):
    # Track occurrences of (PK, SK) tuples
    occurrences = {}
    # Track duplicates
    duplicates = {}

    for item in items:
        pk_sk_tuple = (item["PK"], item["SK"])
        if pk_sk_tuple in occurrences:
            occurrences[pk_sk_tuple] += 1
            duplicates[pk_sk_tuple] = occurrences[pk_sk_tuple]
        else:
            occurrences[pk_sk_tuple] = 1

    # Check if there are duplicates and throw an error
    if duplicates:
        duplicate_details = ", ".join(
            [f"{duplicate}: {count}" for duplicate, count in duplicates.items()]
        )
        raise ValueError(f"Duplicates found - {duplicate_details}")


@timer
def add_items_to_dynamodb(articles, clusters, associated_articles):
    # Get the table
    table = dynamodb.Table(DYNAMODB_TABLE)

    keys_to_get = [
        {"PK": cluster[0], "SK": f"#METADATA#{cluster[0]}"} for cluster in clusters
    ]

    # Convert to the desired dictionary format
    cluster_associations = {}

    # Initialize a dictionary to keep track of items to batch write
    items_to_batch_write = {}
    for item in clusters:
        key, article_ids = item
        cluster_associations[key] = article_ids

    existing_metadata, missing_keys = batch_get_meta_data(keys_to_get)
    print("Missing Keys: ", len(missing_keys))
    print("Existing Metadata: ", len(existing_metadata))

    for item in existing_metadata:
        pk_sk = (item["PK"], item["SK"])

        # Assume 'NumAttribute' exists, increment it
        if "number_of_articles" in item:
            item["number_of_articles"] += (
                len(cluster_associations[item["PK"]]) - 1
            )  # Subtract one for metadata
        # Check for duplicates
        if pk_sk in items_to_batch_write:
            print(f"Duplicate found for existing metadata: {pk_sk}")
        items_to_batch_write[pk_sk] = item

    # For unprocessed keys write a new METADATA entry
    for key in missing_keys:
        pk_sk = (key["PK"], f"#METADATA#{key['PK']}")
        item = {
            "PK": key["PK"],
            "SK": f"#METADATA#{key['PK']}",
            "type": "metadata",
            "created_at": datetime.now().isoformat(),
            "number_of_articles": len(cluster_associations[key["PK"]]) + 1,
            "generated_summary": "",
            "summary_count": 0,
            "description": "",
            "is_cluster": True,
        }  # Partition Key  # Sort Key
        if pk_sk in items_to_batch_write:
            print(f"Duplicate found for new metadata: {pk_sk}")
        items_to_batch_write[pk_sk] = item

    for cluster_id, ids in clusters + articles:
        for article_id in ids:
            pk_sk = (cluster_id, f"ARTICLE#{article_id}")
            article = associated_articles.get(article_id)

            # ! This is accounting for a bug, should not have to be done!!
            if article is not None:
                # Define the item to be inserted
                item = {
                    "PK": cluster_id,
                    "SK": f"ARTICLE#{article_id}",
                    "type": "article",
                    "article_id": article_id,
                    "title": article.get("title"),
                    "summary": article.get("summary"),
                    "text": article.get("text"),
                    "organizations": article.get("organizations_fd"),
                    "locations": article.get("locations_fd"),
                    # "article_sentiment": article.get("article_sentiment"),
                    "publication_date": article.get("publication_date"),
                    "entry_creation_date": datetime.now().isoformat(),
                }  # Partition Key  # Sort Key
            else:
                item = {
                    "PK": cluster_id,
                    "SK": f"ARTICLE#{article_id}",
                    "type": "article",
                    "article_id": article_id,
                    "entry_creation_date": datetime.now().isoformat(),
                }  # Partition Key  # Sort Key

            # Check for duplicates
            if pk_sk in items_to_batch_write:
                print(f"Duplicate found for article: {pk_sk}")
            items_to_batch_write[pk_sk] = item

    # Write aggregated items to DynamoDB using batch writer
    with table.batch_writer() as batch:
        for pk_sk, item in items_to_batch_write.items():
            batch.put_item(Item=item)


def find_string_duplicates(strings):
    seen = set()
    duplicates = set(string for string in strings if string in seen or seen.add(string))
    if duplicates:
        raise ValueError(f"Duplicates: {', '.join(duplicates)}")


@timer
def cluster(records):
    # Set Global Variables # ToDO Find "pythonic" way of doing this
    global label_tracker
    global is_cluster
    global distance_matrix
    global embeds

    global unique_article_id
    global unique_cluster_id
    global cluster_count
    global batch_times
    global processed_pool_sizes

    batch_update_distance_matrix = (
        batch_update_numpy_distance_matrix  # For now we will always use this function
    )

    eps = 0.10  # ToDo Parameterize

    print("***\t***")
    print(f"Starting eps:\t{eps}")

    # Configure logging
    metric = "precomputed"
    clustering_args = dict(eps=eps, min_samples=2, metric=metric, n_jobs=-1)

    batch_time = time.time()

    # report cluster pool metrics
    processed_pool_size = len(label_tracker)
    number_of_singletons = processed_pool_size - cluster_count
    print(f"Number of clusters in pool:\t{cluster_count}")
    print(f"Number of singletons in pool:\t{number_of_singletons}")

    # add this batch to bookkeeping
    processed_pool_sizes.append(processed_pool_size)

    label_tracker.extend(
        [(str(uuid.uuid4()), [doc["id"]]) for i, doc in enumerate(records)]
    )

    is_cluster.extend([False for _ in range(len(records))])

    # Size of existing cluster_pool.
    old_size = len(embeds) if embeds is not None else 0

    # update embedding list
    new_embeds = [doc["concat_embedding"] for doc in records]

    if embeds is not None:
        embeds.extend(new_embeds)
    else:
        embeds = new_embeds

    unique_article_id += len(records)  # increment by number of samples added

    # get distances from new samples to old samples
    # M X [[N], [M]] = M x N+M matrix
    # TODO: This implementation vs. Database
    # TODO: Thresholding to make it more sparse
    add_to_distance_matrix = batch_update_distance_matrix(
        np.ascontiguousarray(new_embeds),
        cluster_pool=np.ascontiguousarray(embeds),
    )

    # Convert (M, N+M) -> (N+M, N+M), make sparse if possible
    if distance_matrix is None:
        distance_matrix = add_to_distance_matrix
    else:
        distance_matrix = get_sparse_distance_matrix(
            add_to_distance_matrix, old_size if old_size > 0 else None
        )

    # Cluster
    clusterer = DBSCAN(**clustering_args).fit(distance_matrix)

    # Update clusters and singletons
    update_time = time.time()
    unique_labels = np.unique(clusterer.labels_)
    to_remove = set()
    updated_clusters = []  # Indicies to update database

    # Cluster formation
    for label in unique_labels:
        if label != -1:
            indices = np.nonzero(clusterer.labels_ == label)[0]

            update_idx = indices[0]

            # * Don't need for DB
            to_remove.update(
                [i for i in indices[1:] if not is_cluster[i]]
            )  # keep track of items to remove from all items

            added_articles = [
                label_tracker[id_idx][1][0]
                for id_idx in indices[1:]
                if not is_cluster[id_idx]
            ]

            updated_clusters.append((label_tracker[update_idx][0], added_articles))

            # extend first instance with all like labels
            label_tracker[update_idx][1].extend(added_articles)

            # rename if not labeled cluster yet
            if is_cluster[update_idx] is False:
                cluster_count += 1

                unique_cluster_id += 1
                is_cluster[update_idx] = True

            # Update embeddings with the mean of all the embeddings in cluster
            embeddings_for_this_cluster_label = [embeds[id_idx] for id_idx in indices]

            centroid = np.mean(embeddings_for_this_cluster_label, axis=0)
            embeds[update_idx] = centroid.tolist()

    print(f"update_time:\t{time.time() - update_time}")

    # delete indices that were merged
    cleanup_time = time.time()
    update_label_time = time.time()

    label_tracker = [
        label_tracker[i] for i in range(len(label_tracker)) if i not in to_remove
    ]

    is_cluster = [is_cluster[i] for i in range(len(is_cluster)) if i not in to_remove]
    print(f"Labeling cleanup\t{time.time() - update_label_time:.2f}")

    embed_cleanup = time.time()
    embeds = [e for i, e in enumerate(embeds) if i not in to_remove]

    print(f"embed cleanup\t{time.time() - embed_cleanup:.2f}")
    print(f"cleanup_time:\t{time.time() - cleanup_time}")

    # Track times
    batch_time = time.time() - batch_time
    batch_times.append(batch_time)
    print(f"Batch time:\t{batch_time}")
    print(f"mean batch time:\t{sum(batch_times)/len(batch_times)}")

    # dont use aggregated variables here, recalculate to double check accuracy
    number_of_clusters = len(np.nonzero(is_cluster)[0])
    number_of_singletons = len(np.nonzero(~np.asarray(is_cluster, dtype=bool))[0])
    print(f"Number of clusters\t{number_of_clusters}")
    print(f"Number of singletons\t{number_of_singletons}")

    number_of_stories_in_saved = sum([len(samples[1]) for samples in label_tracker])
    print(f"total_stories_clustered\t{number_of_stories_in_saved}")

    new_entries_articles = [
        label_tracker[i]
        for i in range(old_size, len(label_tracker))
        if is_cluster[i] is False
    ]

    total_new_articles = sum([len(a[1]) for a in new_entries_articles])
    print("Total New Articles Actual", total_new_articles)
    print("Total New Articles Expected", len(new_entries_articles))
    return new_entries_articles, updated_clusters


@timer
def process_messages(records):
    formatted_records, associated_articles = format_documents(records)
    new_entries_articles, updated_clusters = cluster(formatted_records)
    add_items_to_dynamodb(new_entries_articles, updated_clusters, associated_articles)


@timer
def delete_messages_in_batches(messages):
    # Split messages into batches of 10 for deletion
    batch_size = 10
    for i in range(0, len(messages), batch_size):
        batch = messages[i : i + batch_size]
        entries = [
            {"Id": str(index), "ReceiptHandle": msg["ReceiptHandle"]}
            for index, msg in enumerate(batch)
        ]
        sqs.delete_message_batch(QueueUrl=SQS_QUEUE, Entries=entries)
    print("Deleted messages from queue")


def consume_records(batch_size=20):
    global incoming_articles

    # -----------------------------------------------------------------
    # Get the records.
    # Get max_records from the shard, or run continuously if you wish.
    # -----------------------------------------------------------------
    all_messages = []
    while len(all_messages) < batch_size:

        response = sqs.receive_message(
            QueueUrl=SQS_QUEUE,
            MaxNumberOfMessages=min(10, int(batch_size - len(all_messages))),
            WaitTimeSeconds=0,  # Short polling to avoid long waits
        )

        messages = response.get("Messages", [])
        if not messages:
            # print("The queue is empty.")
            break

        all_messages.extend(messages)
        if len(all_messages) >= batch_size:
            break

    incoming_articles.extend(all_messages)


@timer
def checkpoint():
    global label_tracker
    global is_cluster
    global distance_matrix
    global embeds
    global incoming_articles

    data_to_serialize = {
        "label_tracker": label_tracker,
        "is_cluster": is_cluster,
        "embeds": embeds,
    }

    serialized_data = pickle.dumps(data_to_serialize)

    # Upload the updated data back to S3 as a checkpoint
    s3.put_object(Body=serialized_data, Bucket=S3_BUCKET_NAME, Key=S3_FILE_KEY)
    print(f"Updated file uploaded successfully to {S3_BUCKET_NAME}/{S3_FILE_KEY}")


@timer
def load_from_checkpoint():
    global label_tracker
    global is_cluster
    global embeds
    global distance_matrix
    global cluster_count

    try:
        # Retrieve the object from S3
        s3_response_object = s3.get_object(Bucket=S3_BUCKET_NAME, Key=S3_FILE_KEY)

        # Read the file's content
        serialized_data = s3_response_object["Body"].read()
        loaded_data = pickle.loads(serialized_data)

        label_tracker = loaded_data["label_tracker"]
        is_cluster = loaded_data["is_cluster"]
        embeds = loaded_data["embeds"]
        # distance_matrix = ""  # ToDo ask hector best way to deal with this
        distance_matrix = "" if embeds is not None and len(embeds) > 0 else None

        print(
            "Successfully loaded from checkpoint, cluster pool size: ",
            len(label_tracker),
        )
        number_of_clusters = len(np.nonzero(is_cluster)[0])
        number_of_singletons = len(np.nonzero(~np.asarray(is_cluster, dtype=bool))[0])
        print(f"Number of clusters\t{number_of_clusters}")
        print(f"Number of singletons\t{number_of_singletons}")

        cluster_count = number_of_clusters
    except s3.exceptions.NoSuchKey:
        print(
            f"No existing checkpoint found at {S3_BUCKET_NAME}/{S3_FILE_KEY}. Starting with new data."
        )


if __name__ == "__main__":

    batch_size = 500
    checkpoint_rate = 5  # How many batches before checkpointing
    batches_processed = 0
    number_of_threads = 50
    number_of_articles = batch_size / number_of_threads
    print("Batch Size", batch_size)
    print("Checkpoint Rate", checkpoint_rate)

    load_from_checkpoint()

    print(f"Article queue: {len(incoming_articles)}")

    ### Define number of threads
    # articles_received = number_of_threads * batch_size
    threads = [
        threading.Thread(target=lambda: consume_records(number_of_articles))
        for _ in range(number_of_threads)
    ]
    # start all threads
    start = time.time()
    [t.start() for t in threads]
    # collect threads to finish
    [t.join() for t in threads]

    print(f"Processed batches: {len(incoming_articles)}")
    print(f"total time: {time.time() - start:.2f} seconds")

    # Consumer Server
    while True:
        threads = [
            threading.Thread(target=lambda: consume_records(number_of_articles))
            for _ in range(number_of_threads)
        ]
        if batches_processed % checkpoint_rate == 0:
            checkpoint_thread = threading.Thread(target=lambda: checkpoint())
            threads.append(checkpoint_thread)

        # start all threads
        start = time.time()
        [t.start() for t in threads]

        if len(incoming_articles) >= batch_size:  # Check we have enough articles
            process_messages(incoming_articles)
            delete_messages_in_batches(incoming_articles)

            batches_processed += 1
            incoming_articles = []

        [t.join() for t in threads]
        print(f"Processed batches: {len(incoming_articles)}")
        print(f"TOTAL TIME FOR CLUSTERING BATCH: {time.time() - start:.2f} seconds")
