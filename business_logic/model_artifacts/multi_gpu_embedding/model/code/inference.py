from transformers import AutoModel, AutoTokenizer, BitsAndBytesConfig
import torch
import torch.nn.functional as F
from torch import Tensor
from transformers import AutoTokenizer, AutoModel
import traceback
from accelerate import Accelerator

accelerate = Accelerator()


def model_fn(model_dir, context):

    # load tokenizer and model from model_dir
    try:
        device = f"cuda:{context._system_properties['gpu_id']}"
        print(f"LOADING MODEL onto: {device}")
        model = AutoModel.from_pretrained(
            model_dir,
            quantization_config=BitsAndBytesConfig(load_in_8bit=True),
            device_map=device,
        )
        model.eval()

    except Exception as e:
        print("FAILED: LOADING MODEL")
        print(e)
        print(traceback.format_exc())

    tokenizer = AutoTokenizer.from_pretrained(model_dir)

    return tokenizer, model


def predict_fn(data, tokenizer_and_model):
    torch.cuda.empty_cache()

    # unpack tokenizer and model
    tokenizer, model = tokenizer_and_model

    # Grab the data
    texts = data.pop("input_texts")
    max_length = data.pop("max_length")

    def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:

        left_padding = attention_mask[:, -1].sum() == attention_mask.shape[0]
        if left_padding:
            return last_hidden_states[:, -1]
        else:
            sequence_lengths = attention_mask.sum(dim=1) - 1
            batch_size = last_hidden_states.shape[0]
            return last_hidden_states[
                torch.arange(batch_size, device=last_hidden_states.device),
                sequence_lengths,
            ]

    def get_detailed_instruct(task_description: str, query: str) -> str:
        return f"Instruct: {task_description}\nQuery: {query}"

    print("PROCESSING texts")
    task = "Given this news passage, retrieve relevant news passages that pertain to the same event (who, what, where, when)"
    texts = [get_detailed_instruct(task, text) for text in texts]

    # Tokenize the input texts
    batch_dict = tokenizer(
        texts,
        max_length=max_length - 1,
        return_attention_mask=False,
        padding=False,
        truncation=True,
    )

    print("TOKENIZED texts")
    # append eos_token_id to every input_ids
    batch_dict["input_ids"] = [
        input_ids + [tokenizer.eos_token_id] for input_ids in batch_dict["input_ids"]
    ]
    batch_dict = tokenizer.pad(
        batch_dict, padding=True, return_attention_mask=True, return_tensors="pt"
    )

    try:
        print("FORWARD PASS")
        with torch.no_grad():
            outputs = model(**batch_dict)

        print("GET EMBEDDINGS")
        embeddings = last_token_pool(
            outputs.last_hidden_state, batch_dict["attention_mask"]
        )

        # normalize embeddings
        embeddings = F.normalize(embeddings.to(torch.float32), p=2, dim=1)

        embeddings = embeddings.to("cpu").tolist()
    except Exception as e:
        print("FORWARD ERROR")
        print(traceback.format_exc())
        print(e)
        embeddings = [None for _ in range(len(texts))]

    del batch_dict

    return {"embeddings": embeddings}
