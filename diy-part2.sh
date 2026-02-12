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
echo "Rust 编译修复脚本 (路径增强版)"
echo "=========================================="

# 1. 环境检查与路径识别
# 优先使用脚本后的第一个参数作为路径，否则使用当前路径
TARGET_DIR="${1:-$(pwd)}"

# 检查是否是有效的 OpenWrt 源码目录
check_openwrt_root() {
    if [ -f "$1/scripts/feeds" ] && [ -f "$1/Makefile" ]; then
        return 0
    else
        return 1
    fi
}

if check_openwrt_root "$TARGET_DIR"; then
    OPENWRT_ROOT="$TARGET_DIR"
    echo "✅ 找到 OpenWrt 根目录: $OPENWRT_ROOT"
else
    echo "⚠️  在 $TARGET_DIR 未找到 OpenWrt 源码"
    echo "正在尝试寻找当前目录下的子目录..."
    # 尝试在子目录中寻找一级
    SUB_DIR=$(find . -maxdepth 2 -name "scripts" -type d | head -n 1 | xargs dirname)
    if [ -n "$SUB_DIR" ] && check_openwrt_root "$SUB_DIR"; then
        OPENWRT_ROOT="$(realpath "$SUB_DIR")"
        echo "✅ 在子目录中找到 OpenWrt 根目录: $OPENWRT_ROOT"
    else
        echo "❌ 错误: 无法确定 OpenWrt 源码根目录。"
        echo "用法: $0 /your/openwrt/path"
        exit 1
    fi
fi

# 定义相关路径
RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"

# 2. 确保 Rust 文件夹存在
if [ ! -d "$RUST_DIR" ]; then
    echo ">>> Rust 文件夹缺失，正在尝试同步 Feeds..."
    cd "$OPENWRT_ROOT" || exit
    ./scripts/feeds update packages
    ./scripts/feeds install -a -p packages
    cd - > /dev/null || exit
fi

# 3. 获取权威版本信息 (使用 24.10 作为参考标准)
REF_MK="/tmp/rust_ref.mk"
IMM_URL="https://raw.githubusercontent.com/openwrt/packages/openwrt-24.10/lang/rust/Makefile"

echo ">>> 正在获取远程版本元数据..."
if ! curl -fsSL "$IMM_URL" -o "$REF_MK"; then
    echo "⚠️ 无法获取远程 Makefile，将使用本地版本"
    [ -f "$RUST_MK" ] && cp "$RUST_MK" "$REF_MK" || { echo "❌ 无法找到任何 Makefile"; exit 1; }
fi

RUST_VER=$(grep '^PKG_VERSION:=' "$REF_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$REF_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')

echo ">>> 目标 Rust 版本: $RUST_VER"

# 4. 修改 Makefile 参数
echo ">>> 正在应用优化参数到: $RUST_MK"

# 更新版本号和 Hash
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$RUST_VER/" "$RUST_MK"
[ -n "$RUST_HASH" ] && sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$RUST_HASH/" "$RUST_MK"

# 【关键】开启下载预编译 LLVM 模式，防止磁盘空间爆满
if grep -q "download-ci-llvm" "$RUST_MK"; then
    echo ">>> 开启 download-ci-llvm 以节省磁盘空间"
    sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"
fi

# 修正源码下载地址
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# 5. 预下载源码（使用国内镜像加速）
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"
mkdir -p "$DL_DIR"

if [ ! -s "$DL_PATH" ]; then
    echo ">>> 正在预下载 Rust 源码包..."
    MIRRORS=(
        "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"
        "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"
        "https://static.rust-lang.org/dist/${RUST_FILE}"
    )

    for mirror in "${MIRRORS[@]}"; do
        echo ">>> 尝试镜像: $mirror"
        if wget --timeout=20 --tries=2 -O "$DL_PATH" "$mirror"; then
            if [ -s "$DL_PATH" ]; then
                echo "✅ 源码已成功缓存至 $DL_PATH"
                break
            fi
        fi
    done
else
    echo ">>> 源码已存在，跳过下载。"
fi

echo "=========================================="
echo "✅ 针对 $OPENWRT_ROOT 的 Rust 修复已完成"
echo "=========================================="

# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================
REPO_ROOT=$(readlink -f "$GITHUB_WORKSPACE")
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

echo ">>> Patching DiskMan and libxcrypt..."

#  DiskMan 修复
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
if [ -f "$DM_MAKEFILE" ]; then
    sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"
    echo "✅ DiskMan fix applied."
fi

# =========================================================
# 强制修改默认主题为 Argon (彻底移除 Bootstrap)
# =========================================================

echo ">>> 开始强制替换默认主题为 luci-theme-argon..."

# 1. 修正 collections/luci 中的硬依赖
# 将 Makefile 中依赖的 luci-theme-bootstrap 替换为 luci-theme-argon
find "$OPENWRT_ROOT/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' {} +

# 2. 修改 luci-base 的默认主题配置
# 这一步是为了防止系统启动时去找 bootstrap 的路径
LUCI_BASE_CONFIG="$OPENWRT_ROOT/feeds/luci/modules/luci-base/root/etc/config/luci"
if [ -f "$LUCI_BASE_CONFIG" ]; then
    sed -i 's/bootstrap/argon/g' "$LUCI_BASE_CONFIG"
    echo "✅ luci-base 默认配置已指向 argon"
fi

# 3. 修改系统初始化时的默认主题 (uci-defaults)
# 搜索所有包含 bootstrap 路径的默认设置并替换为 argon
find "$OPENWRT_ROOT/feeds/luci/themes/" -type f -name "*_luci-theme-bootstrap" -exec sed -i 's/bootstrap/argon/g' {} +

# 4. 删除 Bootstrap 源码文件夹 (可选，如果你怕依赖报错可以不删，但上面的步骤会确保它不被选中)
# 建议：如果不删除，可以确保编译不报错，但生成的固件里不会包含它。
# 如果非要删除，必须清理 tmp 目录
rm -rf "$OPENWRT_ROOT/feeds/luci/themes/luci-theme-bootstrap"

# 5. 【关键】强制在 .config 层面禁用 Bootstrap
# 即使你在 menuconfig 选了，这里也会在最后阶段将其强制关闭
[ -f "$OPENWRT_ROOT/.config" ] && sed -i '/CONFIG_PACKAGE_luci-theme-bootstrap=y/d' "$OPENWRT_ROOT/.config"
echo "CONFIG_PACKAGE_luci-theme-bootstrap=n" >> "$OPENWRT_ROOT/.config"
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> "$OPENWRT_ROOT/.config"

echo "✅ 默认主题修改完成：Argon 现在是唯一的默认选项。"

# 修复 libxcrypt 编译报错
# 给 configure 脚本添加 --disable-werror 参数，忽略警告
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# =========================================================
# 智能修改 Tailscale 菜单归类 (自动定位文件)
# =========================================================

echo ">>> 正在搜索并修改 Tailscale 菜单归类..."

# 使用 find 自动寻找这个 JSON 文件，不管它在 package/tailscale 里的哪个角落
TS_JSON_FILE=$(find package/tailscale -name "luci-app-tailscale-community.json" -o -name "tailscale.json" | head -n 1)

if [ -f "$TS_JSON_FILE" ]; then
    echo "✅ 找到菜单文件: $TS_JSON_FILE"
    # 执行修改：将 admin/services/tailscale 修改为 admin/vpn/tailscale
    sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' "$TS_JSON_FILE"
    
    # 兼容性补充：如果文件中存在 "parent": "luci.services" 也一并修改
    sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' "$TS_JSON_FILE"
    
    echo "✅ Tailscale 菜单已成功移动到 VPN 分类"
else
    echo "❌ 错误: 在 package/tailscale 中找不到 Tailscale 的菜单配置文件！"
    # 打印一下当前的目录结构，方便在 Actions 日志里排错
    echo "Debug: 当前 package/tailscale 目录结构如下："
    ls -R package/tailscale | head -n 20
fi

# 自定义默认网关，后方的192.168.30.1即是可自定义的部分
sed -i 's/192.168.[0-9]*.[0-9]*/192.168.30.1/g' package/base-files/files/bin/config_generate

# 自定义主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='360T7'/g" package/base-files/files/bin/config_generate

# 固件版本名称自定义
#sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By gino $(date +"%Y%m%d")'/g" package/base-files/files/etc/openwrt_release
