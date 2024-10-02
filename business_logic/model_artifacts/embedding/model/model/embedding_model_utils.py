import torch
import torch.nn.functional as F
from torch import Tensor
from transformers import AutoTokenizer, AutoModel
from typing import List
from abc import ABC, abstractmethod


class PretrainedHandler(ABC):
    def __init__(self, pretrained_path=None, bit_loading=None, device=None):
        self.model = None
        self.tokenizer = None

        if device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        else:
            assert device in set(
                ["cuda", "cpu"]
            ), "Incorrect device chosen. Choose from [cuda, cpu]"
            self.device = device

        self.bit_loading = bit_loading
        self.get_model(pretrained_path=pretrained_path)

    @abstractmethod
    def get_model(self, pretrained_path=None) -> None:
        """
        Instantiates self.model and self.tokenizer
        """
        raise NotImplementedError

    def encode(self, texts: List[str]):
        """encode texts"""
        return self._encode()(texts)

    def _encode(self):
        """return the encoding method for the target model
        Can differ between models (e.g. model.encode, model, model.forward)"""
        return self.model.encode


class PretrainedMistral7bInstruct(PretrainedHandler):

    @classmethod
    def last_token_pool(
        cls, last_hidden_states: Tensor, attention_mask: Tensor
    ) -> Tensor:
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

    @classmethod
    def get_detailed_instruct(cls, task_description: str, query: str) -> str:
        return f"Instruct: {task_description}\nNewsPassage: {query}"

    def get_model(self, pretrained_path=None):

        model_source = (
            "intfloat/e5-mistral-7b-instruct"
            if pretrained_path is None
            else pretrained_path
        )

        # Each query must come with a one-sentence instruction that describes the task
        # Example
        # task = 'Given a web search query, retrieve relevant passages that answer the query'
        # input_texts = [self.get_detailed_instruct(task, 'how much protein should a female eat'),
        #             self.get_detailed_instruct(task, 'summit define'),
        #             "As a general guideline, the CDC's average requirement of protein for women ages 19 to 70 is 46 grams per day. But, as you can see from this chart, you'll need to increase that if you're expecting or training for a marathon. Check out the chart below to see how much protein you should be eating each day.",
        #             "Definition of summit for English Language Learners. : 1  the highest point of a mountain : the top of a mountain. : 2  the highest level. : 3  a meeting or series of meetings between the leaders of two or more governments."]
        self.tokenizer = AutoTokenizer.from_pretrained(
            pretrained_model_name_or_path=model_source
        )

        assert (
            torch.cuda.is_available()
        ), "GPU is needed to load model in 4-bit or 8-bit"

        if self.bit_loading == "4":
            print("loading in 4bit")

            self.model = AutoModel.from_pretrained(
                pretrained_model_name_or_path=model_source,
                load_in_4bit=True,
                bnb_4bit_compute_dtype=torch.float16,
                device_map=self.device,
            )
        else:
            print("loading in 8bit")
            self.model = AutoModel.from_pretrained(
                pretrained_model_name_or_path=model_source, load_in_8bit=True
            )

        self.model.eval()

    def encode(self, texts: List[str]):
        max_length = 4096

        task = "Given this news passage, retrieve relevant news passages that pertain to the same event (who, what, where, when)"
        texts = [self.get_detailed_instruct(task, text) for text in texts]

        # Tokenize the input texts
        batch_dict = self.tokenizer(
            texts,
            max_length=max_length - 1,
            return_attention_mask=False,
            padding=False,
            truncation=True,
        )

        # append eos_token_id to every input_ids
        batch_dict["input_ids"] = [
            input_ids + [self.tokenizer.eos_token_id]
            for input_ids in batch_dict["input_ids"]
        ]
        batch_dict = self.tokenizer.pad(
            batch_dict, padding=True, return_attention_mask=True, return_tensors="pt"
        )

        return self._encode(encoded_input=batch_dict)

    def _encode(self, encoded_input=None):
        with torch.no_grad():
            outputs = self.model(**encoded_input)

        embeddings = self.last_token_pool(
            outputs.last_hidden_state, encoded_input["attention_mask"]
        )

        # normalize embeddings
        embeddings = F.normalize(embeddings, p=2, dim=1)

        embeddings = embeddings.to("cpu").tolist()

        return embeddings


class PretrainedBGELarge(PretrainedHandler):

    def get_model(self, pretrained_path=None):

        model_source = (
            "BAAI/bge-large-zh-v1.5" if pretrained_path is None else pretrained_path
        )

        # Load model from HuggingFace Hub
        tokenizer = AutoTokenizer.from_pretrained(model_source)
        model = AutoModel.from_pretrained(model_source)
        model.eval()

        self.model = model
        self.tokenizer = tokenizer

        model.to(self.device)

    def encode(self, texts: List[str]):

        # # Tokenize sentencesxs
        # encoded_input = self.tokenizer(texts, padding=True, truncation=True, max_length=512, return_tensors='pt')

        # for s2p(short query to long passage) retrieval task, add an instruction to query (not add instruction for passages)
        instruction = "Embed this passage for clustering on the topic of discussion in the news article: "
        encoded_input = self.tokenizer(
            [instruction + t for t in texts],
            padding=True,
            truncation=True,
            max_length=512,
            return_tensors="pt",
        )

        encoded_input.to(self.device)

        return self._encode()(encoded_input)

    def _encode(self):
        def forward(encoded_input):
            # Compute token embeddings
            with torch.no_grad():
                model_output = self.model(**encoded_input)
                # Perform pooling. In this case, cls pooling.
                sentence_embeddings = model_output[0][:, 0]

            # normalize embeddings
            sentence_embeddings = (
                torch.nn.functional.normalize(sentence_embeddings, p=2, dim=1)
                .to("cpu")
                .tolist()
            )

            return sentence_embeddings

        return forward
