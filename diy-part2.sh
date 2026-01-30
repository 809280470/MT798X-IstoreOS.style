#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

echo "=========================================="
echo "DIY Part 2: 修复 Rust LLVM 配置"
echo "=========================================="

cd openwrt || exit 1
echo "当前目录: $(pwd)"

# ==========================================
# 1. 修复 Rust ci-llvm 配置（解决 LLVM 不匹配）
# ==========================================
echo ">>> 修复 Rust ci-llvm 配置..."

RUST_MAKEFILE="feeds/packages/lang/rust/Makefile"

if [ -f "$RUST_MAKEFILE" ]; then
    echo "找到 Rust Makefile: $RUST_MAKEFILE"
    
    # 备份原文件（便于调试）
    cp "$RUST_MAKEFILE" "$RUST_MAKEFILE.bak"
    
    # 禁用 ci-llvm（使用系统 LLVM 或自编译，避免版本冲突）
    if grep -q "ci-llvm=true" "$RUST_MAKEFILE"; then
        sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_MAKEFILE"
        echo "✅ ci-llvm 已禁用（将使用系统 LLVM）"
    else
        echo "ℹ️ ci-llvm 已禁用或配置项不存在"
    fi
    
    # 显示当前配置（调试用）
    grep -n "ci-llvm" "$RUST_MAKEFILE" || true
else
    echo "❌ 错误：找不到 $RUST_MAKEFILE"
    echo "检查 feeds 目录结构："
    find feeds -name "rust" -type d 2>/dev/null | head -5
    exit 1
fi

# ==========================================
# 2. 启用 LLVM BPF 支持（Rust 编译需要）
# ==========================================
echo ">>> 启用 LLVM BPF 支持..."

if [ -f ".config" ]; then
    # 如果配置文件中还没有 llvm-bpf，添加它
    if ! grep -q "^CONFIG_PACKAGE_llvm-bpf=y" ".config"; then
        echo "CONFIG_PACKAGE_llvm-bpf=y" >> .config
        echo "✅ 已添加 llvm-bpf 支持到 .config"
    else
        echo "ℹ️ llvm-bpf 已启用"
    fi
    
    # 同时确保 host 工具链支持（可选但推荐）
    if ! grep -q "^CONFIG_USE_LLVM_HOST=" ".config"; then
        # 设置为 y 使用系统 LLVM（如果可用），或 n 让 OpenWrt 自行编译
        echo "CONFIG_USE_LLVM_HOST=y" >> .config
        echo "✅ 已启用 HOST LLVM 支持"
    fi
else
    echo "⚠️ 警告：.config 不存在，跳过 llvm-bpf 配置"
    echo "请确保 CONFIG_FILE 已正确加载"
fi

echo "=========================================="
echo "Rust 修复完成"
echo "=========================================="
# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================

REPO_ROOT=$(dirname "$(readlink -f "$0")")
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"

echo "Debug: Repo root is $REPO_ROOT"

# 1. 优先查找 package 目录
TARGET_LUA=$(find package -name "istore_backend.lua" -type f 2>/dev/null)

# 2. 如果 package 中没找到，再查找 feeds
if [ -z "$TARGET_LUA" ]; then
    echo "Not found in package/, searching in feeds/..."
    TARGET_LUA=$(find feeds -name "istore_backend.lua" -type f 2>/dev/null)
fi

# 3. 执行覆盖（逻辑与原脚本相同）
if [ -n "$TARGET_LUA" ]; then
    echo "Found target file: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "Overwriting with custom file..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ Overwrite Success! Files match."
        else
             echo "❌ Error: Copy failed or files do not match."
        fi
    else
        echo "❌ Error: Custom file ($CUSTOM_LUA) not found!"
        ls -l "$REPO_ROOT/istore" 2>/dev/null || echo "Directory not found"
    fi
else
    echo "❌ Error: istore_backend.lua not found in package/ or feeds/!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i '/ntfs-3g-utils /d' $DM_FILE

	cd $PKG_PATH && echo "diskman has been fixed!"
fi

# 修复 libxcrypt 编译报错
# 给 configure 脚本添加 --disable-werror 参数，忽略警告
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# 自定义默认网关，后方的192.168.30.1即是可自定义的部分
sed -i 's/192.168.[0-9]*.[0-9]*/192.168.30.1/g' package/base-files/files/bin/config_generate

# 自定义主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='360T7'/g" package/base-files/files/bin/config_generate

# 固件版本名称自定义
#sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By gino $(date +"%Y%m%d")'/g" package/base-files/files/etc/openwrt_release

# 取消原主题luci-theme-bootstrap 为默认主题
# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap

# 删除原默认主题
# rm -rf package/lean/luci-theme-bootstrap

# 修改 argon 为默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
