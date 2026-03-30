#!/bin/sh

# 1. 确保脚本以 root 权限运行 (兼容 sh)
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：请使用 root 用户或 sudo 权限运行此脚本。"
  exit 1
fi

echo "正在检查系统的 BBR 加速状态..."

# 2. 检查当前是否已经开启 BBR (兼容 sh，使用单个 =)
current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
if [ "$current_cc" = "bbr" ]; then
    echo "✅ 系统当前已经开启了 BBR 加速，无需重复配置。"
    exit 0
fi

echo "未检测到 BBR 加速，正在为您配置..."

# 3. 检查内核版本 (BBR 需要 Linux Kernel 4.9 及以上)
kernel_version=$(uname -r | awk -F. '{print $1"."$2}')
if [ 1 -eq "$(echo "${kernel_version} < 4.9" | bc 2>/dev/null || echo 0)" ]; then
    echo "⚠️ 警告: 当前系统内核版本 ($kernel_version) 低于 4.9，可能不支持 BBR。"
    echo "建议先升级系统内核再尝试开启 BBR。"
fi

# 4. 保证幂等性：从 /etc/sysctl.conf 中删除已存在的老配置
sed -i '/^\s*net\.core\.default_qdisc\s*=/d' /etc/sysctl.conf
sed -i '/^\s*net\.ipv4\.tcp_congestion_control\s*=/d' /etc/sysctl.conf

# 5. 写入 BBR 配置
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf

# 6. 重载 sysctl 配置使其生效
echo "正在应用配置..."
sysctl -p > /dev/null 2>&1

# 7. 最终验证 (兼容 sh，使用单个 =)
new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
if [ "$new_cc" = "bbr" ]; then
    echo "🎉 BBR 加速配置并开启成功！"
    
    # 检查内核模块是否正确加载
    if lsmod | grep -q bbr; then
        echo "✅ tcp_bbr 内核模块已成功加载。"
    fi
else
    echo "❌ BBR 加速开启失败，请检查系统内核是否原生支持 BBR 模块。"
fi