import os
import sys
import json
import time
import torch.multiprocessing as mp

mp.set_start_method("spawn", force=True)

MODEL_NAME = os.environ.get("MODEL_NAME")
BIT_LOADING = os.environ.get("BIT_LOADING")
print(f"MODEL_NAME: {MODEL_NAME}")
print(f"BIT_LOADING: {BIT_LOADING}")
MODEL_MAP = {
    "mistralinstruct": None,
    "bge": None,
}


print("Current working directory: ", os.getcwd())
print("List current working directory: ", os.listdir(os.getcwd()))


def model_fn(model_dir):
    try:
        print(f"In model_fn, model_dir={model_dir}")
        print(f"CWD: {os.getcwd()}")
        print(f"List CWD: {os.listdir(os.getcwd())}")
        print(f"List model_dir: {os.listdir(model_dir)}")
        sys.path.append(model_dir + "/model")
        print(f"Sys path: {sys.path}")
        print(f"List model_dir/model: {os.listdir(model_dir+'/model')}")
        print(f"List model_dir/code: {os.listdir(model_dir+'/code')}")

        from embed_documents import EmbedDocuments

        print("Successfully imported EmbedDocuments")
        model_cls = EmbedDocuments(MODEL_NAME, MODEL_MAP[MODEL_NAME], BIT_LOADING)

    except Exception as e:
        print(f"WEIRD, error: {e}")
    return model_cls


def input_fn(input_data, content_type="application/json"):
    """A default input_fn that can handle JSON, CSV and NPZ formats.

    Args:
        input_data: the request payload serialized in the content_type format
        content_type: the request content_type

    Returns: input_data deserialized into torch.FloatTensor or torch.cuda.FloatTensor depending if cuda is available.
    """
    print(f"input_fn, input_data={input_data}, content_type={content_type}")
    # Process the input data (e.g., convert from JSON)
    print("input_fn")
    print("request body: ", input_data)
    if content_type == "application/json":
        print("request_content_type is application/json")
        data = json.loads(input_data)
        texts = data["input_texts"]
        return texts
    else:
        raise ValueError(f"Unsupported content type: {content_type}")


def predict_fn(data, model):
    """A default predict_fn for PyTorch. Calls a model on data deserialized in input_fn.
    Runs prediction on GPU if cuda is available.

    Args:
        data: input data (torch.Tensor) for prediction deserialized by input_fn
        model: PyTorch model loaded in memory by model_fn

    Returns: a prediction
    """
    print(f"predict_fn, data={data}, model={model}")
    start_time = time.time()
    new_doc = model.model_handler.encode(data)
    end_time = time.time()
    new_data = {"embeddings": new_doc, "time": end_time - start_time}
    return new_data


def output_fn(prediction, content_type="application/json"):
    """A default output_fn for PyTorch. Serializes predictions from predict_fn to JSON, CSV or NPY format.

    Args:
        prediction: a prediction result from predict_fn
        accept: type which the output data needs to be serialized

    Returns: output data serialized
    """
    print(f"output_fn, prediction={prediction}, content_type={content_type}")
    if content_type == "application/json":
        print("content_type is application/json")
        return json.dumps(prediction)
    else:
        raise ValueError(f"Unsupported content type: {content_type}")
