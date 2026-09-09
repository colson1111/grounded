#!/tmp/clip_coreml_env/bin/python3.11
"""
Convert MobileCLIP-S1 image encoder to CoreML via torch.export (dynamo path).
"""

import json
from pathlib import Path

import coremltools as ct
import open_clip
import torch

REPO_ROOT = Path(__file__).parent
MODELS_DIR = REPO_ROOT / "models"
MODELS_DIR.mkdir(exist_ok=True)

MLPACKAGE_PATH = MODELS_DIR / "MobileCLIPImageEncoder.mlpackage"
MODEL_NAME = "MobileCLIP-S1"
PRETRAINED = "datacompdr"


class ImageEncoderWrapper(torch.nn.Module):
    def __init__(self, clip_model):
        super().__init__()
        self.visual = clip_model.visual

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        feats = self.visual(x)
        return feats / feats.norm(dim=-1, keepdim=True)


def main():
    if MLPACKAGE_PATH.exists():
        print(f"CoreML model already exists at {MLPACKAGE_PATH}")
        return

    print(f"Loading {MODEL_NAME}...")
    model, _, _ = open_clip.create_model_and_transforms(MODEL_NAME, pretrained=PRETRAINED)
    model.eval()

    wrapper = ImageEncoderWrapper(model)
    wrapper.eval()

    dummy = torch.zeros(1, 3, 256, 256)

    print("Exporting with torch.export...")
    with torch.no_grad():
        exported = torch.export.export(wrapper, (dummy,), strict=False)

    print("Decomposing...")
    exported = exported.run_decompositions({})

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        exported,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, 256, 256),
            scale=1.0 / 255.0,
            bias=[0.0, 0.0, 0.0],
            color_layout=ct.colorlayout.RGB,
        )],
        outputs=[ct.TensorType(name="embedding")],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = "MobileCLIP-S1 image encoder. Output: L2-normalized 512-dim embedding."
    mlmodel.save(str(MLPACKAGE_PATH))
    print(f"Saved → {MLPACKAGE_PATH}")


if __name__ == "__main__":
    main()
