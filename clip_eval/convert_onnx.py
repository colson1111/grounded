#!/tmp/clip_coreml_env/bin/python3.11
"""
Export MobileCLIP-S1 image encoder to ONNX, then convert to CoreML.
"""

import json
from pathlib import Path

import coremltools as ct
import numpy as np
import open_clip
import torch
import onnx

REPO_ROOT = Path(__file__).parent
MODELS_DIR = REPO_ROOT / "models"
MODELS_DIR.mkdir(exist_ok=True)

ONNX_PATH = MODELS_DIR / "MobileCLIPImageEncoder.onnx"
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
    print(f"Loading {MODEL_NAME}...")
    model, _, _ = open_clip.create_model_and_transforms(MODEL_NAME, pretrained=PRETRAINED)
    model.eval()

    wrapper = ImageEncoderWrapper(model)
    wrapper.eval()

    dummy = torch.zeros(1, 3, 256, 256)

    if not ONNX_PATH.exists():
        print("Exporting to ONNX...")
        with torch.no_grad():
            torch.onnx.export(
                wrapper,
                dummy,
                str(ONNX_PATH),
                input_names=["image"],
                output_names=["embedding"],
                dynamic_axes={"image": {0: "batch"}, "embedding": {0: "batch"}},
                opset_version=17,
            )
        print(f"Saved ONNX → {ONNX_PATH}")
    else:
        print(f"ONNX already exists at {ONNX_PATH}")

    print("Checking ONNX model...")
    onnx_model = onnx.load(str(ONNX_PATH))
    onnx.checker.check_model(onnx_model)
    print("ONNX check passed.")

    if MLPACKAGE_PATH.exists():
        print(f"CoreML model already exists at {MLPACKAGE_PATH}, skipping.")
        return

    print("Converting ONNX → CoreML...")
    mlmodel = ct.convert(
        str(ONNX_PATH),
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
    print(f"Saved CoreML model → {MLPACKAGE_PATH}")


if __name__ == "__main__":
    main()
