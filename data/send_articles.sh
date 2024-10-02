#!/bin/bash

STREAM_NAME="input-stream-newsedge-ally"
PARTITION_KEY="a"
FILE_PATH="./article_example.json"


python put_records.py


# aws kinesis put-record --stream-name "$STREAM_NAME" --data file://"$FILE_PATH" --partition-key "$PARTITION_KEY"

# aws kinesis put-record --stream-name "$STREAM_NAME" --data file://"$FILE_PATH" --partition-key "id"

# aws kinesis put-records \
#     --stream-name "$STREAM_NAME" \
#     --records file://"$FILE_PATH"
