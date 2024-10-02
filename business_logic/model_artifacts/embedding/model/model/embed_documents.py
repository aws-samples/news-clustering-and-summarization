import torch
from typing import Literal
import importlib
from embedding_model_utils import PretrainedHandler

print("END EMBED_DOCUMENNTS IMPORTS")


class EmbedDocuments:
    def __init__(
        self,
        model_name: Literal["bge", "mistralinstruct"],
        pretrained_path=None,
        bit_loading=None,
        device=None,
        model_handler_module: str = "embedding_model_utils",
    ):

        self.supported_models = dict(
            bge="PretrainedBGELarge",
            mistralinstruct="PretrainedMistral7bInstruct",
        )

        self.model_name = model_name.lower().strip()
        assert (
            model_name in self.supported_models
        ), f"model_name is not supported. Choose from {list(self.supported_models.keys())}"

        self.bit_loading = bit_loading
        self.model_handler: PretrainedHandler = None

        if device is None:
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        else:
            self.device = device

        self.models_module = importlib.import_module(model_handler_module)
        self.load_model(pretrained_path=pretrained_path)

    def load_model(self, pretrained_path=None):
        model_class_name = self.supported_models[self.model_name]

        if hasattr(self.models_module, model_class_name):
            model_class = getattr(self.models_module, model_class_name)
        else:
            raise NotImplementedError(
                "Model loading method does not exist. Check for typos or implement"
            )

        self.model_handler = model_class(
            pretrained_path=pretrained_path, bit_loading=self.bit_loading
        )

        assert self.model_handler is not None

    def delete_model(self):
        self.model_handler.model.to("cpu")
        del self.model_handler.model
        torch.cuda.empty_cache()
