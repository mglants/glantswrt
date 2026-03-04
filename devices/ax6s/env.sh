#! /usr/bin/env bash
# Copyright (c) 2022 The Parca Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail
OPENWRT_CHANNEL="release"
# renovate: datasource=git-tags depName=https://github.com/openwrt/openwrt.git
OPENWRT_VERSION="v24.10.5"

TARGET="mediatek"
SUBTARGET="mt7622"

# Must match an ImageBuilder PROFILE exactly
PROFILE="xiaomi_redmi-router-ax6s"
# -----------------------------------------------------------------------------
# opkg feed architecture
# -----------------------------------------------------------------------------
# This must match the directory name in your binary feed
OPKG_ARCH="aarch64_cortex-a53"

# -----------------------------------------------------------------------------
# Optional metadata (not required by the workflow, but useful later)
# -----------------------------------------------------------------------------
DEVICE_NAME="ax6s"
DEVICE_VENDOR="xiaomi"
DEVICE_MODEL="redmi-router-ax6s"
