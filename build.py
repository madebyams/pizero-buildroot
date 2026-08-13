import os
import subprocess
import shutil
from pathlib import Path

if Path("build").exists():
    shutil.rmtree(Path("build"))

Path("build").mkdir()

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

shutil.move("./build/main/app", "./app-overlay/usr/bin/app")

subprocess.run([
    "podman",
    "build",
    "--target",
    "image",
    "-t",
    "buildroot-image",
    "."
], check=True)

subprocess.run([
    "podman",
    "create",
    "--replace",
    "--name",
    "temp_extract",
    "buildroot-image"
], check=True)

subprocess.run([
    "podman",
    "cp",
    "temp_extract:/buildroot/output/images/sdcard.img",
    "./sdcard.img"
], check=True)

subprocess.run([
    "podman",
    "rm",
    "temp_extract"
], check=True)
