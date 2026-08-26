#!/usr/bin/env python3
# 最小化 pkg-config 包装脚本：仅支持本工程 OHOS 预编译 libssh2
import os
import re
import sys

args = sys.argv[1:]
name = None
for a in args:
    if not a.startswith("-"):
        name = a
        break

if name != "libssh2":
    sys.exit(1)

pc_path = os.environ.get("PKG_CONFIG_PATH", "")
if not pc_path:
    sys.exit(1)

pc_file = os.path.join(pc_path, "libssh2.pc")
if not os.path.isfile(pc_file):
    sys.exit(1)

pc_dir = os.path.dirname(os.path.abspath(pc_file))
shared_dir = os.path.abspath(os.path.join(pc_dir, "../.."))

with open(pc_file, "r") as f:
    content = f.read()

# 根据 .pc 文件所在目录推断 ABI
abi = os.path.basename(pc_dir)  # arm64-v8a 或 x86_64
content = content.replace("${pcfiledir}", pc_dir)
content = content.replace("${shared}", shared_dir)
content = content.replace("${libdir}", shared_dir + "/build/ohos-ssh/" + abi)
content = content.replace("${includedir}", shared_dir + "/third_party/libssh2/include")

libs = " ".join(re.findall(r"^Libs:\s*(.*)$", content, re.MULTILINE))
cflags = " ".join(re.findall(r"^Cflags:\s*(.*)$", content, re.MULTILINE))
version = " ".join(re.findall(r"^Version:\s*(.*)$", content, re.MULTILINE)).strip()

out = []
for a in args:
    if a == "--libs":
        out.append(libs)
    elif a == "--cflags":
        out.append(cflags)
    elif a == "--modversion":
        print(version)
        sys.exit(0)

print(" ".join(out).strip())
