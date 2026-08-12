import os
import subprocess


subprocess.run([
    "podman",
    "run",
    "--rm",
    "-v",
    f"{os.getcwd()}:/work",
    "-w",
    "/work/build", 
    "buildroot-sdk",
    "/buildroot/output/host/bin/cmake",
    "-DCMAKE_C_COMPILER=/buildroot/output/host/bin/aarch64-linux-gcc",
    "-DCMAKE_CXX_COMPILER=/buildroot/output/host/bin/aarch64-linux-g++",
    ".."
], check=True)

subprocess.run([
    "podman",
    "run",
    "--rm",
    "-v",
    f"{os.getcwd()}:/work",
    "-w",
    "/work/build", 
    "buildroot-sdk",
    "/buildroot/output/host/bin/cmake",
    "--build",
    "."
], check=True)
