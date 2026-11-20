#!/bin/sh
# 极简时钟同步脚本（USB WiFi 版）

(
    # 等待 wlan0 出现
    for i in $(seq 30); do
        ifconfig wlan0 2>/dev/null && break
        sleep 0.5
    done

    # 启动 WiFi
    killall wpa_supplicant 2>/dev/null
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant

    # 获取 IP（udhcpc 会自动后台守护）
    udhcpc -i wlan0 -q

    # 加载 RTC/OLED 模块（根据需要）
    insmod /root/ds3231.ko 2>/dev/null
    insmod /root/ssd1306.ko 2>/dev/null
    sleep 1

    # 同步网络时间
    killall ntpd 2>/dev/null
    ntpdate -t 5 203.107.6.88 || ntpdate -t 5 ntp.aliyun.com

    # 写入硬件时钟
    /root/ds3231_tomato &
) &
