# Milk-V Duo 256M SDK — Linux (big core) + RT-Thread (little core)

[中文](#中文) | [English](#english)

---

## 中文

### 简介

本仓库基于 Milk-V 官方 `duo-buildroot-sdk-v2` 的定制版本，目标板卡为 **Milk-V Duo 256M（SG2002，RISC-V C906B + C906L）**。

- 上游：<https://github.com/milkv-duo/duo-buildroot-sdk-v2>
- 基线提交：`6f8962c39`（2025-11-04，`Merge branch 'develop'`）
- 本地全部修改集中在**最新一个提交**中；需要对比时，直接与上游基线 `6f8962c39` 做 diff 即可。

主要特性：

- 大核（C906B）运行 **Linux**，小核（C906L）运行 **RT-Thread**，两者由 FSBL 分别启动、互不依赖
- RTL8188FU WiFi 驱动 + hostapd AP 模式
- DS3231 RTC（I2C1）+ 时钟同步脚本
- 内置 Web 服务（`webapp.py` + 静态页面）
- YOLOv5 手势识别示例（随板 overlay 一起打包）
- 修复非 root 用户构建时根文件系统的属主问题（fakeroot + buildroot 自带工具）

### 与上游的差异

#### 1. 异构双系统：Linux + RT-Thread

| 文件 | 修改内容 |
| --- | --- |
| `build/scripts/fip_v2.mk` | 新增 `C906L_IMAGE` 变量，可替换 `fip.bin` 中的小核镜像（`BLCP_2ND`）。留空时行为与上游一致（FreeRTOS `cvirtos.bin`） |
| `pack_fip_rtthread.sh`（新增） | 用指定的小核镜像重打 `fip.bin`，并解析校验 `BLCP_2ND` 内容 |
| `build/boards/cv181x/sg2002_milkv_duo256m_musl_riscv64_sd/dts_riscv/*.dts` | `&uart1` 置为 `disabled`：UART1（GP0/GP1）归小核 RT-Thread 控制台所有 |
| `device/generic/br_overlay/common/etc/inittab` | 去掉 `ttyS1` 上的 getty（uart1 已不归 Linux） |

内存划分：Linux 使用 `0x80000000`–`0x8fe00000`（254 MB），小核固定运行在 `0x8fe00000`–`0x90000000`（2 MB），互不重叠。

```bash
# 小核固件（RT-Thread）
cd ~/rt-thread/rt-thread/bsp/cvitek/c906_little && source env-little.sh && scons
# 重打 fip.bin（含小核）
cd ~/sdk/duo-buildroot-sdk-v2 && ./pack_fip_rtthread.sh
```

#### 2. WiFi（RTL8188FU）与 AP 模式

- `build/boards/cv181x/sg2002_.../linux/*_defconfig`：`CONFIG_RTL8188FU=y`
- `buildroot/configs/milkv-duo256m-musl-riscv64-sd_defconfig`：`libgpiod`、`libgpiod-tools`
- `buildroot/configs/milkv-duos-musl-riscv64-sd_defconfig`：`hostapd`（WPA3/WPS/EAP/wired）
- 新增 `etc/hostapd.conf`、`etc/init.d/S99xhostapd`（AP：`wlan0`，`192.168.50.1`）
- `etc/wpa_supplicant.conf`、`etc/dnsmasq.conf`（新增 `wlan0`、`192.168.50.0/24`）
- `device/milkv-duo256m-musl-riscv64-sd/u-boot/cvi_board_init.c`：USB host、以太网、屏幕背光等引脚初始化调整

#### 3. DS3231 RTC

- DTS：`&i2c1` 使能，新增 `ds3231@68`（中断 PA15）
- overlay 预置：`root/ds3231.ko`、`root/ds3231_tomato`、`root/ssd1306.ko`、`root/vk36n16i.ko`
- 新增 `mnt/system/ds3231_sync_1.sh`；`S99user` 中原来的时钟同步调用已注释（改由这个脚本/其他方式触发）

#### 4. Web 服务

- `usr/local/bin/webapp.py`、`www/`、`etc/init.d/S99yweb`（监听 80 端口）

#### 5. AI 示例

- `device/milkv-duo256m-musl-riscv64-sd/overlay/root/yolov5/`：`gesture_fixed_int8_sym_v2.cvimodel` + `yolo_gesture`

#### 6. 构建系统修复

| 文件 | 内容 |
| --- | --- |
| `device/gen_burn_image_sd.sh` | `fakeroot -- genimage ...`；`PATH` 前置 buildroot 的 `host/bin`、`host/sbin`，确保使用 buildroot 自带的 `genimage`/`fakeroot`/`mke2fs` |
| `build/Makefile` | overlay 拷贝 `cp -arf` → `cp -rf`，不再把宿主机的 uid/gid、ACL、xattr 带进 rootfs |
| `build/envsetup_milkv.sh` | 导出 `FLASH_PARTITION_XML` |
| `linux_5.10/drivers/mtd/nand/raw/cvitek/Makefile` | 修正 include 路径 |
| `device/generic/rootfs_overlay/duos/mnt/system/ko/loadsystemko.sh` | 注释 `cv181x_mipi_tx.ko` |

> 效果：普通用户即可构建，且 `rootfs.ext4` 内所有文件属主均为 `root:root`（`mke2fs -E root_owner=0:0` + buildroot 的 `chown -R 0:0`）。

### 构建

```bash
cd ~/sdk/duo-buildroot-sdk-v2
source build/envsetup_milkv.sh milkv-duo256m-musl-riscv64-sd   # 生成 build/.config、导出环境

build_uboot        # OpenSBI + U-Boot + fip.bin
build_kernel       # Image + dtb + boot.sd
pack_rootfs        # buildroot 根文件系统
make -C build sd_image                                        # 组装 .img

# 或者全量：
./build.sh milkv-duo256m-musl-riscv64-sd
```

产物目录：`install/soc_sg2002_milkv_duo256m_musl_riscv64_sd/`

| 文件 | 说明 |
| --- | --- |
| `fip.bin` | FSBL + OpenSBI + U-Boot + 小核镜像（`BLCP_2ND`） |
| `rawimages/boot.sd` | 大核内核 FIT（Image + dtb + cpio） |
| `milkv-duo256m-musl-riscv64-sd.img` | 整卡镜像（FAT32 boot + ext4 rootfs） |

### 串口 / 外设分配

| 资源 | 归属 |
| --- | --- |
| UART0（UART0_TX/RX） | 大核 Linux 控制台 |
| UART1（GP0/GP1，IIC0_SCL/SDA） | 小核 RT-Thread 控制台 |
| I2C1 | Linux（DS3231） |

> 同一外设只能归一个核使用；跨核共用会造成中断/寄存器竞争。

### 许可与合规

- **本仓库是私有/内部使用的衍生仓库**，与 Milk-V、Sophgo 官方无隶属关系。
- 上游仓库本身**没有顶层 LICENSE**；各组件分别遵循自己的许可：
  - `buildroot`、`linux_5.10`、`u-boot-2021.10`：GPL-2.0（或更高）
  - `opensbi`：BSD-2-Clause
  - `freertos`：MIT
  - `tdl_sdk`：BSD-2-Clause
  - `cvi_mpi`、`ive`、`isp_tuning`、`osdrv`、`cviruntime` 等厂商组件：未附带独立许可文件，请遵循 Sophgo/CVITEK SDK 的使用条款
  - RT-Thread（独立仓库）：Apache-2.0
- **删除上游 git 历史是允许的**：许可证约束的是"源码/二进制的分发"，与 git 提交历史无关。但请注意：
  1. 不要删除各子项目内的 `COPYING` / `LICENSE` / 版权头；
  2. 一旦**对外分发二进制**，GPL 组件需要同时提供对应源码；
  3. 厂商专有组件（含预编译库）能否再分发，需以 Sophgo/CVITEK 的条款为准，公开仓库前请逐一确认。

---

## English

### Overview

Customized fork of the official Milk-V `duo-buildroot-sdk-v2`, targeting **Milk-V Duo 256M (SG2002: RISC-V C906B + C906L)**.

- Upstream: <https://github.com/milkv-duo/duo-buildroot-sdk-v2>
- Base commit: `6f8962c39` (2025-11-04, `Merge branch 'develop'`)
- All local changes are contained in the **latest commit**; diff against the upstream baseline `6f8962c39` to review them.

Key features:

- **Linux on the big core (C906B), RT-Thread on the little core (C906L)** — both started independently by the FSBL
- RTL8188FU WiFi driver + hostapd AP mode
- DS3231 RTC on I2C1 with a clock-sync script
- Built-in web service (`webapp.py` + static pages)
- YOLOv5 gesture demo shipped in the board overlay
- Root-owned rootfs even when building as a normal user (fakeroot + buildroot-hosted tools)

### Changes vs upstream

#### 1. Heterogeneous dual-OS: Linux + RT-Thread

| File | Change |
| --- | --- |
| `build/scripts/fip_v2.mk` | New `C906L_IMAGE` variable to replace the little-core image (`BLCP_2ND`) inside `fip.bin`. When unset, behaviour is identical to upstream (FreeRTOS `cvirtos.bin`) |
| `pack_fip_rtthread.sh` (new) | Repacks `fip.bin` with a given little-core image and verifies the embedded `BLCP_2ND` |
| `build/boards/cv181x/sg2002_milkv_duo256m_musl_riscv64_sd/dts_riscv/*.dts` | `&uart1` set to `disabled`: UART1 (GP0/GP1) belongs to the RT-Thread console |
| `device/generic/br_overlay/common/etc/inittab` | Removed the `ttyS1` getty (uart1 is no longer owned by Linux) |

Memory split: Linux gets `0x80000000`–`0x8fe00000` (254 MB); the little core runs at `0x8fe00000`–`0x90000000` (2 MB). No overlap.

```bash
# Little-core firmware (RT-Thread)
cd ~/rt-thread/rt-thread/bsp/cvitek/c906_little && source env-little.sh && scons
# Rebuild fip.bin with the RT-Thread image
cd ~/sdk/duo-buildroot-sdk-v2 && ./pack_fip_rtthread.sh
```

#### 2. WiFi (RTL8188FU) and AP mode

- `.../linux/*_defconfig`: `CONFIG_RTL8188FU=y`
- `buildroot/configs/milkv-duo256m-musl-riscv64-sd_defconfig`: `libgpiod`, `libgpiod-tools`
- `buildroot/configs/milkv-duos-musl-riscv64-sd_defconfig`: `hostapd` (WPA3/WPS/EAP/wired)
- New `etc/hostapd.conf` and `etc/init.d/S99xhostapd` (AP on `wlan0`, `192.168.50.1`)
- `etc/wpa_supplicant.conf`; `etc/dnsmasq.conf` adds `wlan0` and `192.168.50.0/24`
- `device/milkv-duo256m-musl-riscv64-sd/u-boot/cvi_board_init.c`: USB host / Ethernet / panel backlight pin init

#### 3. DS3231 RTC

- DTS: `&i2c1` enabled, new `ds3231@68` node (IRQ on PA15)
- Prebuilt blobs in the overlay: `root/ds3231.ko`, `root/ds3231_tomato`, `root/ssd1306.ko`, `root/vk36n16i.ko`
- Added `mnt/system/ds3231_sync_1.sh`; the previous clock-sync call in `S99user` is commented out

#### 4. Web service

- `usr/local/bin/webapp.py`, `www/`, `etc/init.d/S99yweb` (port 80)

#### 5. AI demo

- `device/milkv-duo256m-musl-riscv64-sd/overlay/root/yolov5/`: `gesture_fixed_int8_sym_v2.cvimodel` + `yolo_gesture`

#### 6. Build-system fixes

| File | Change |
| --- | --- |
| `device/gen_burn_image_sd.sh` | `fakeroot -- genimage ...`; `PATH` prepends buildroot `host/bin` and `host/sbin` so buildroot's own `genimage`/`fakeroot`/`mke2fs` are used |
| `build/Makefile` | Overlay copies `cp -arf` → `cp -rf`, so host uid/gid, ACLs and xattrs are not carried into the rootfs |
| `build/envsetup_milkv.sh` | Export `FLASH_PARTITION_XML` |
| `linux_5.10/drivers/mtd/nand/raw/cvitek/Makefile` | Fix include path |
| `device/generic/rootfs_overlay/duos/mnt/system/ko/loadsystemko.sh` | Commented out `cv181x_mipi_tx.ko` |

> Result: builds run as a normal user, and every file inside `rootfs.ext4` is owned by `root:root` (buildroot's `chown -R 0:0` plus `mke2fs -E root_owner=0:0`).

### Building

```bash
cd ~/sdk/duo-buildroot-sdk-v2
source build/envsetup_milkv.sh milkv-duo256m-musl-riscv64-sd   # generates build/.config, exports env

build_uboot        # OpenSBI + U-Boot + fip.bin
build_kernel       # Image + dtb + boot.sd
pack_rootfs        # buildroot root filesystem
make -C build sd_image                                        # assemble the .img

# or everything at once:
./build.sh milkv-duo256m-musl-riscv64-sd
```

Outputs live in `install/soc_sg2002_milkv_duo256m_musl_riscv64_sd/`:

| File | Description |
| --- | --- |
| `fip.bin` | FSBL + OpenSBI + U-Boot + little-core image (`BLCP_2ND`) |
| `rawimages/boot.sd` | Big-core kernel FIT (Image + dtb + cpio) |
| `milkv-duo256m-musl-riscv64-sd.img` | Full SD image (FAT32 boot + ext4 rootfs) |

### Serial ports / peripherals

| Resource | Owner |
| --- | --- |
| UART0 (UART0_TX/RX) | Linux console (big core) |
| UART1 (GP0/GP1, IIC0_SCL/SDA) | RT-Thread console (little core) |
| I2C1 | Linux (DS3231) |

> A peripheral must be owned by exactly one core; sharing it causes interrupt and register races.

### License and compliance

- **This is a private/internal fork**, not affiliated with Milk-V or Sophgo.
- The upstream repository has **no top-level LICENSE file**; each component keeps its own:
  - `buildroot`, `linux_5.10`, `u-boot-2021.10`: GPL-2.0 (or later)
  - `opensbi`: BSD-2-Clause
  - `freertos`: MIT
  - `tdl_sdk`: BSD-2-Clause
  - `cvi_mpi`, `ive`, `isp_tuning`, `osdrv`, `cviruntime`: vendor components without a standalone license file — follow the Sophgo/CVITEK SDK terms
  - RT-Thread (separate repository): Apache-2.0
- **Removing upstream git history is allowed**: licenses govern distribution of source/binaries, not git metadata. Please note that:
  1. `COPYING` / `LICENSE` files and copyright headers inside sub-projects must be kept;
  2. When **distributing binaries**, GPL components require corresponding source to be made available;
  3. Whether vendor proprietary blobs may be redistributed is governed by Sophgo/CVITEK terms — verify before making this repository public.
