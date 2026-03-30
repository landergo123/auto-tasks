#!/bin/sh

# ==========================================================
# 脚本功能：高并发优化 + 自动时间点备份
# 兼容性：Linux (Ubuntu/CentOS/Debian) & OpenWrt
# 特性：幂等性、内存自适应、全自动备份
# 示例：还原 sysctl 配置
#     cp -p /etc/sys_opt_backup/optimize_network_2026xxxx_xxxxxx/sysctl.conf.bak /etc/sysctl.conf
#     sysctl -p
# ==========================================================

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 root 权限运行此脚本。"
    exit 1
fi
mkdir -p /etc/sys_opt_backup

# 2. 初始化备份路径 (按时间点创建独立文件夹)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/etc/sys_opt_backup/optimize_network_$TIMESTAMP"
CONF_SYSCTL="/etc/sysctl.conf"
CONF_LIMITS="/etc/security/limits.conf"
LIMIT_VAL=1048576

echo "🚀 开始系统优化任务..."
echo "📂 备份目录: $BACKUP_DIR"

# 备份函数：仅在目标文件存在时执行备份
safe_backup() {
    file=$1
    if [ -f "$file" ]; then
        [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"
        cp -p "$file" "$BACKUP_DIR/$(basename "$file").bak"
    fi
}

# 3. 动态内存计算 (适配不同硬件)
total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$total_mem" -gt 524288 ]; then
    RMEM_MAX=16777216
    WMEM_MAX=16777216
    TCP_MEM="786432 1048576 1572864"
else
    RMEM_MAX=4194304
    WMEM_MAX=4194304
    TCP_MEM="196608 262144 393216"
fi

# 4. 优化文件描述符 (ULIMIT)
echo "[1/3] 正在备份并优化文件描述符..."

# 备份相关文件
safe_backup "$CONF_LIMITS"
safe_backup "/etc/systemd/system.conf"
safe_backup "/etc/systemd/user.conf"
safe_backup "/etc/profile"

# 写入 limits.conf (针对标准 Linux)
if [ -f "$CONF_LIMITS" ]; then
    sed -i '/nofile/d' "$CONF_LIMITS"
    echo "* soft nofile $LIMIT_VAL" >> "$CONF_LIMITS"
    echo "* hard nofile $LIMIT_VAL" >> "$CONF_LIMITS"
    echo "root soft nofile $LIMIT_VAL" >> "$CONF_LIMITS"
    echo "root hard nofile $LIMIT_VAL" >> "$CONF_LIMITS"
fi

# 写入 Systemd 配置
if [ -d /etc/systemd ]; then
    for s_conf in /etc/systemd/system.conf /etc/systemd/user.conf; do
        if [ -f "$s_conf" ]; then
            sed -i '/DefaultLimitNOFILE/d' "$s_conf"
            echo "DefaultLimitNOFILE=$LIMIT_VAL" >> "$s_conf"
        fi
    done
    systemctl daemon-reexec >/dev/null 2>&1 || true
fi

# 写入 Profile (针对 OpenWrt/通用)
if [ -f /etc/profile ]; then
    sed -i '/ulimit -n/d' /etc/profile
    echo "ulimit -n $LIMIT_VAL" >> /etc/profile
fi

# 5. 优化网络参数 (sysctl)
echo "[2/3] 正在备份并优化网络协议栈..."

# 备份 sysctl.conf
safe_backup "$CONF_SYSCTL"

net_params="
net.core.default_qdisc=fq_codel
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_fin_timeout=20
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_max_tw_buckets=10000
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.core.somaxconn=8192
net.core.netdev_max_backlog=10000
net.core.rmem_max=$RMEM_MAX
net.core.wmem_max=$WMEM_MAX
net.ipv4.tcp_mem=$TCP_MEM
fs.file-max=1048576
"

for item in $net_params; do
    key=$(echo "$item" | cut -d'=' -f1)
    val=$(echo "$item" | cut -d'=' -f2-)
    sed -i "/^#* *$key *=/d" "$CONF_SYSCTL"
    echo "$key = $val" >> "$CONF_SYSCTL"
done

# 清理空行并应用配置
sed -i '/^$/N;/^\n$/D' "$CONF_SYSCTL"
sysctl -p >/dev/null 2>&1

# 6. 环境适配与收尾
echo "[3/3] 正在进行环境检测与验证..."

# 针对 OpenWrt 的 Flow Offloading 提醒
if [ -f /etc/openwrt_release ]; then
    echo "提示: 检测到 OpenWrt 环境。"
fi

echo "---------------------------------------------------"
echo "✅ 优化完成！"
echo "📦 原始文件已安全备份至: $BACKUP_DIR"
echo "📊 当前 Shell 文件句柄限制: $(ulimit -n)"
echo "💡 提示: 建议重启系统以确保所有配置（尤其是 Systemd 限制）完全生效。"