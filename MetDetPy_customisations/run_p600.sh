#!/bin/bash
export ORT_TENSORRT_FP16_ENABLE=0
export ORT_CUDA_FLAGS="device_id=0"
export GLIBC_TUNABLES=glibc.rtld.execstack=2
export LD_LIBRARY_PATH="/root/MetDetPy/lib_compat:$LD_LIBRARY_PATH"

#Run MetDetPy
/root/MetDetPy/.venv/bin/python /root/MetDetPy/MetDetPy.py $1 --provider cuda --save-path /root/MetDetPy/detections/detections.json
