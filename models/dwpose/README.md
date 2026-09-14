# DWPose model slot

KROLIK does **not** commit the 134 MB ONNX binary to Git.

The runtime candidate path used by `rig_tools.py` is:

`models/dwpose/dw-ll_ucoco_384.onnx`

Fetch it reproducibly with:

```bash
python tools/fetch_dwpose_model.py
```

Verify an existing file without network access:

```bash
python tools/fetch_dwpose_model.py --check
```

Pinned model metadata:

- file: `dw-ll_ucoco_384.onnx`
- expected SHA-256: `724f4ff2439ed61afb86fb8a1951ec39c6220682803b4a8bd4f598cd913b1843`
- expected bytes: `140839825`
- model family: DWPose/RTMPose WholeBody ONNX
- upstream project: `IDEA-Research/DWPose`
- upstream repository license: Apache-2.0

The official DWPose repository documents this exact ONNX filename for its ONNX/ControlNet path. The bootstrap uses a mirror URL but refuses any payload whose SHA-256/size does not match the pinned artifact. Override `--url` if the mirror moves; checksum verification remains mandatory.

Do not mark A2 complete merely because the binary exists. A2 also requires a real inference smoke and measured pose accuracy on a representative art corpus.
