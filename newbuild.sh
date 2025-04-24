#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

echo "Starting kernel build..."

KERNEL_ROOT_DIR=$(pwd)
TARGET_ARCH="arm64"
KERNEL_CONFIG="nabu_defconfig"

ZIP_KERNEL_STR="coreLinux"
ZIP_DEVICE_NAME="apollo"
ZIP_PREFIX_STR="TwistedKernel-v2.0"

export KBUILD_BUILD_USER="TwistedKernel"
export KBUILD_BUILD_HOST="TwistedHaxor"

ENABLE_CCACHE="0"

#############################
TOOLCHAIN="3"               #
# 1) gcc-4.9                #
# 2) eva-gcc-12             #
# 3) proton-clang-13        #
# 4) sdclang-12.1           #
# 5) aosp-clang-r416183c    #
# 6) aospa-gcc-10.2         #
# 7) arter-gcc [9.3 & 11.1] #
#############################

USE_UNCOMPRESSED_KERNEL="1"
DISABLE_LLD="1"
DISABLE_IAS="0"
DISABLE_LLD_IAS="0"
USE_LLVM_TOOLS="0"
BUILD_MODULES="0"
DO_SYSTEMLESS="1"
BUILD_DTBO_IMG="0"
PATCH_PERMISSIVE="0"
PATCH_CLASSPATH="0"
RAMOOPS_MEMRESERVE="0"
DTC_EXT_FOR_DTC="0"

OUT_BOOT_DIR="$KERNEL_ROOT_DIR/out/arch/$TARGET_ARCH/boot"

TOOLCHAIN_DIR="$KERNEL_ROOT_DIR/toolchains"
mkdir -p "$TOOLCHAIN_DIR"

ANYKERNEL_DIR="$KERNEL_ROOT_DIR/AnyKernel3"
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3"

## Utility Functions

run() {
  echo -e "\n$1\n"
  eval "$1"
}

git_clone() {
  local repo_url=$1
  local branch=$2
  local dest_dir=$3

  if [ ! -d "$dest_dir" ] || [ -z "$(ls -A "$dest_dir")" ]; then
    echo "Cloning ${repo_url} branch ${branch} into $dest_dir"
    git clone --depth=1 --single-branch -b "$branch" "$repo_url" "$dest_dir"
  else
    echo "$dest_dir exists. Skipping clone."
  fi
}

### Toolchain setup

get_proton_clang() {
  local TC="$TOOLCHAIN_DIR/proton-clang-13.0"
  local REPO="https://github.com/kdrag0n/proton-clang"
  local BRANCH="master"

  git_clone "$REPO" "$BRANCH" "$TC"

  CROSS="$TC/bin/aarch64-linux-gnu-"
  CROSS_ARM32="$TC/bin/arm-linux-gnueabi-"
  PFX_OVERRIDE=""

  MAKEOPTS="CC=clang \
    LD=${PFX_OVERRIDE}ld.lld \
    AR=${PFX_OVERRIDE}llvm-ar \
    AS=${PFX_OVERRIDE}llvm-as \
    NM=${PFX_OVERRIDE}llvm-nm \
    STRIP=${PFX_OVERRIDE}llvm-strip \
    OBJCOPY=${PFX_OVERRIDE}llvm-objcopy \
    OBJDUMP=${PFX_OVERRIDE}llvm-objdump \
    READELF=${PFX_OVERRIDE}llvm-readelf \
    HOSTAR=${PFX_OVERRIDE}llvm-ar \
    HOSTAS=${PFX_OVERRIDE}llvm-as \
    HOSTLD=${PFX_OVERRIDE}ld.lld"
}

get_gcc_4_9() {
  local TC_64="$TOOLCHAIN_DIR/gcc-4.9-64"
  local REPO_64="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9"
  local BRANCH_64="lineage-18.1"

  local TC_32="$TOOLCHAIN_DIR/gcc-4.9-32"
  local REPO_32="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9"
  local BRANCH_32="lineage-18.1"

  git_clone "$REPO_64" "$BRANCH_64" "$TC_64"
  git_clone "$REPO_32" "$BRANCH_32" "$TC_32"

  CROSS="$TC_64/bin/aarch64-linux-android-"
  CROSS_ARM32="$TC_32/bin/arm-linux-androideabi-"
  MAKEOPTS=""
}

select_toolchain() {
  echo "Selecting toolchain $TOOLCHAIN"
  case $TOOLCHAIN in
    1) get_gcc_4_9 ;;
    3) get_proton_clang ;;
    # Bạn có thể thêm các toolchain khác ở đây nếu cần
    *)
      echo "Toolchain $TOOLCHAIN không được hỗ trợ trong script này."
      exit 1
      ;;
  esac
}

### Build kernel

build_kernel() {
  echo "Starting kernel build..."

  export PATH="$(dirname "$CROSS"):$PATH"

  echo "Running make $KERNEL_CONFIG"
  make O=out ARCH=$TARGET_ARCH $KERNEL_CONFIG

  echo "Building kernel with  $(nproc) cores"
  make -j$(nproc) O=out ARCH=$TARGET_ARCH \
    CROSS_COMPILE=$CROSS $MAKEOPTS
  echo "Kernel build completed."
}

### Prepare AnyKernel3 package

prepare_anykernel() {
  echo "Preparing AnyKernel3 package..."

  # Clone anykernel nếu chưa có
  if [ ! -d "$ANYKERNEL_DIR" ]; then
    git clone "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
  else
    echo "AnyKernel3 directory exists. Pull latest changes."
    (cd "$ANYKERNEL_DIR" && git pull --ff-only)
  fi

  # Copy image kernel vào thư mục AnyKernel3
  cp "$OUT_BOOT_DIR/Image.gz-dtb" "$ANYKERNEL_DIR/"

  # Nếu bạn có các file dtbo.img hay dtb.img, copy tương tự:
  # cp "$OUT_BOOT_DIR/dtbo.img" "$ANYKERNEL_DIR/"
  # cp "$OUT_BOOT_DIR/dtb.img" "$ANYKERNEL_DIR/"

  echo "AnyKernel3 preparation done."
}

### Package AnyKernel3 thành zip flashable

package_anykernel_zip() {
  echo "Packaging kernel with AnyKernel3..."

  ZIP_NAME="${ZIP_PREFIX_STR}-${ZIP_DEVICE_NAME}-$(date +%Y%m%d-%H%M).zip"
  ZIP_PATH="$KERNEL_ROOT_DIR/out/$ZIP_NAME"

  mkdir -p "$KERNEL_ROOT_DIR/out"

  (
    cd "$ANYKERNEL_DIR"
    zip -r9 "$ZIP_PATH" ./* -x "*.git*" "*.github*" "*README.md" "*CHANGELOG"
  )

  echo "Kernel zip packaged: $ZIP_PATH"
}

### Main chạy các bước

main() {
  select_toolchain
  build_kernel
  prepare_anykernel
  package_anykernel_zip
}

main

