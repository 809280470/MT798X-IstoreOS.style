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

# =========================================================
# 修复 Rust 编译失败：替换为 ImmortalWrt 的稳定版 Rust
# =========================================================

# 1. 删除 feeds 中那个下载失败的 Rust (1.89.0)
echo "Removing broken Rust package..."
rm -rf feeds/packages/lang/rust

# 2. 克隆 ImmortalWrt 的 packages 仓库 (临时)
# 这里使用 openwrt-23.05 分支，因为它的 Rust 版本极其稳定(通常是 1.77-1.79)，且一定有预编译缓存
echo "Cloning stable Rust from ImmortalWrt..."
git clone --depth 1 -b openwrt-23.05 https://github.com/immortalwrt/packages.git temp_packages

# 3. 将稳定的 Rust 搬运到你的编译环境中
cp -r temp_packages/lang/rust feeds/packages/lang/

# 4. 清理临时文件
rm -rf temp_packages

echo "Rust has been replaced with a stable version!"

# =========================================================
# 修复 QuickStart 首页温度显示问题
# 逻辑：将仓库中的 istore_backend.lua 复制到 files 目录进行强制覆盖
# =========================================================

# 1. 创建目标目录结构 (相当于路由器的 /usr/lib/lua/luci/controller/)
mkdir -p files/usr/lib/lua/luci/controller/

# 2. 复制文件并覆盖
# 注意：.. 代表上级目录，因为 diy-part2.sh 运行在 openwrt/ 目录下
if [ -f "../istore/istore_backend.lua" ]; then
    echo "Found custom istore_backend.lua, overwriting..."
    cp -f ../istore/istore_backend.lua files/usr/lib/lua/luci/controller/istore_backend.lua
    
    # 3. 赋予执行权限 (防止权限问题导致无法读取)
    chmod 644 files/usr/lib/lua/luci/controller/istore_backend.lua
else
    echo "WARNING: Custom istore_backend.lua not found!"
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
