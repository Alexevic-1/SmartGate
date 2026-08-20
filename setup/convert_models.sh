#!/bin/bash
### Convert marsupial .pt model to TensorRT engine ###
# Reference: https://www.youtube.com/watch?v=ErWC3nBuV6k
# This script converts the marsupial_16s.pt model to a TensorRT .engine file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/models"

# Check CUDA is in PATH
if ! command -v nvcc &> /dev/null; then
    echo "[-] nvcc not found. Setting up CUDA paths..."
    export PATH=/usr/local/cuda/bin:${PATH}
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}
fi

# Check if .pt file exists
if [ ! -f "$MODELS_DIR/marsupial_16s.pt" ]; then
    echo "[-] marsupial_16s.pt not found in $MODELS_DIR"
    echo "[-] Download it from https://github.com/carlosclaiton/marsupial and place it in models/"
    exit 1
fi

# Clone YOLOv5 v6.2 if not present
if [ ! -d "$PROJECT_DIR/yolov5" ]; then
    echo "[+] Cloning YOLOv5 v6.2..."
    cd "$PROJECT_DIR"
    git clone --branch v6.2 https://github.com/ultralytics/yolov5.git
    cd yolov5
    # NOTE: onnx==1.9.0 (2021-era) does not install on Python 3.12 / Ubuntu 24.04 containers.
    # Installing an unpinned/current onnx instead - if export.py needs a specific opset,
    # pass --opset explicitly rather than pinning onnx itself.
    pip3 install onnx
else
    cd "$PROJECT_DIR/yolov5"
fi

# Step 1: Export .pt to ONNX
echo "[+] Exporting marsupial_16s.pt to ONNX..."
python3 export.py --weights "$MODELS_DIR/marsupial_16s.pt" --include onnx --img 640

# Check ONNX was created
if [ ! -f "$MODELS_DIR/marsupial_16s.onnx" ]; then
    # YOLOv5 export puts onnx next to the .pt file
    if [ -f "$PROJECT_DIR/yolov5/marsupial_16s.onnx" ]; then
        mv "$PROJECT_DIR/yolov5/marsupial_16s.onnx" "$MODELS_DIR/"
    else
        echo "[-] ONNX export failed"
        exit 1
    fi
fi

# Step 2: Convert ONNX to TensorRT engine
# Locate trtexec - its install path has moved around across TensorRT versions/packagings,
# so check the classic location first and fall back to searching PATH.
if [ -x "/usr/src/tensorrt/bin/trtexec" ]; then
    TRTEXEC="/usr/src/tensorrt/bin/trtexec"
elif command -v trtexec &> /dev/null; then
    TRTEXEC="$(command -v trtexec)"
else
    echo "[-] trtexec not found. Searching filesystem..."
    TRTEXEC="$(find / -maxdepth 6 -iname trtexec -type f 2>/dev/null | head -n 1)"
    if [ -z "$TRTEXEC" ]; then
        echo "[-] Could not locate trtexec anywhere. Is the tensorrt apt package installed?"
        exit 1
    fi
fi
echo "[+] Using trtexec at: $TRTEXEC"

echo "[+] Converting ONNX to TensorRT engine (this will take a while)..."
"$TRTEXEC" \
    --onnx="$MODELS_DIR/marsupial_16s.onnx" \
    --saveEngine="$MODELS_DIR/marsupial_16s.engine" \
    --fp16

if [ -f "$MODELS_DIR/marsupial_16s.engine" ]; then
    echo "[+] Conversion complete! Engine saved to $MODELS_DIR/marsupial_16s.engine"
else
    echo "[-] TensorRT conversion failed"
    exit 1
fi