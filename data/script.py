import json

with open("public_data/dataset.test.json", "r") as f:
    data = json.load(f)
    print(len(data))
