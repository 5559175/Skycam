This repo is very specific to my personal setup - I don't expect it to work elsewhere - no in-depth help can be provided.

Through a LOT of trial and error, Gemini coded most of it for me as I am not a developer.

I run this on my NAS, an HP Gen 8 Microserver running Debian 13 with Openmediavault 8 - I use the OMV compose plugin for docker containers (including this one). 

The server runis 24/7 and to save cost has a very low power (17W TDP) Intel Xeon E3-1220L v2 (2C/4T), 16GB RAM and Nvidia Quadro P600 GPU which is used for acceleration of encode/decode with ffpmeg, and for the portions of MetDetPy which can be accelerated with CUDA.

I use the offical NVidia driver (580 branch) due to the age of this card.

To get CUDA to work properly with this older card/driver and to help accelerate portions of MetDetPy, I had to build a **Python 3.10** venv in which to run MetDetPy using uv and pip.

The requirements.txt is included in MetDetPy_customisations along with a script I call to run it to make use of my Quadro P600.

These clear-execstack commmands were also necessary to be run against the 3 critical ONNX files to ensure Debian 13's glibc does not block execution:

```
patchelf --clear-execstack .venv/lib/python3.10/site-packages/onnxruntime/capi/libonnxruntime_providers_cuda.so
patchelf --clear-execstack .venv/lib/python3.10/site-packages/onnxruntime/capi/libonnxruntime_providers_shared.so
patchelf --clear-execstack .venv/lib/python3.10/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-310-x86_64-linux-gnu.so
```

With this setup I get between 30-60 it/sec
