#!/bin/sh
# 自动时间同步脚本 (基于HTTP Header, 纯TCP协议)
# 兼容: 主流Linux发行版, OpenWrt (Busybox)

PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
SHELL_HOME_PATH="$SCRIPT_DIR"
CONF_INSTALL_DIR="/usr/local/lib/http_time_sync"

# 目标服务器列表
# 选用大型云厂商和CDN，并使用 HTTP 避免 TLS 握手带来的几百毫秒延迟误差，提升时间精度
SERVERS="https://www.google.com
https://www.apple.com
https://www.microsoft.com
https://www.cloudflare.com
https://www.kernel.org"

# 网络超时时间(秒) - 设置极短以剔除高延迟节点，保证精度
TIMEOUT=2
LOG_TAG="http-time-sync"

# 日志输出函数：同时输出到终端和系统日志 (适用 crontab 调试追踪)
log_msg() {
    echo "$1"
    #logger -t "$LOG_TAG" "$1" 2>/dev/null
}

has_cmd() {
    # command -v "$@" > /dev/null 2>&1
    command -v "$1" >/dev/null 2>&1
}


# 安装：复制脚本 + 创建 profile.d 钩子
do_install() {
    local script_path

    # 获取当前脚本的绝对路径
    script_path=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
    if has_cmd readlink; then
        script_path=$(readlink -f "$0" 2>/dev/null || printf '%s' "$script_path")
    fi

    # 创建安装目录
    if ! mkdir -p "$CONF_INSTALL_DIR" 2>/dev/null; then
        printf '[错误] 无法创建目录 %s，请使用 root 权限运行\n' "$CONF_INSTALL_DIR" >&2
        return 1
    fi

    # 复制脚本到安装目录（幂等：覆盖旧版本）
    if ! cp -f "$script_path" "${CONF_INSTALL_DIR}/http_time_sync.sh" 2>/dev/null; then
        printf '[错误] 无法复制脚本到 %s\n' "$CONF_INSTALL_DIR" >&2
        return 1
    fi
    chmod +x "${CONF_INSTALL_DIR}/http_time_sync.sh"


    if has_cmd crontab; then
        CRON_CHANGE="N"
        TMP_CRON="/tmp/cron_tmp_http_time_sync.txt"
        # 如果有任务就导出，没有任务就创建一个空文件
        # crontab -l 2>/dev/null > $TMP_CRON || true
        if crontab -l >/dev/null 2>&1; then
            crontab -l > $TMP_CRON
        else
            touch $TMP_CRON
        fi

        if grep -q "http_time_sync" "$TMP_CRON"; then
            log_msg "定时任务【定期同步时间】已存在，无需添加"
        else
            echo "0 5 * * * ${CONF_INSTALL_DIR}/http_time_sync.sh >/dev/null 2>&1" >> $TMP_CRON
            CRON_CHANGE="Y"
            log_msg "定时任务【定期同步时间】已添加：每天5点执行 ${CONF_INSTALL_DIR}/http_time_sync.sh >/dev/null 2>&1"
        fi

        if [ "$CRON_CHANGE" = "Y" ]; then
            crontab $TMP_CRON
            systemctl restart cron || systemctl restart crond || true
        fi
        rm -f $TMP_CRON
        log_msg "配置定时任务配置完成"
		
		do_sync_time
    else
        log_msg "未识别crontab命令"
        exit 1
    fi
}

# 卸载：删除钩子和安装目录，保留日志
do_uninstall() {
    local removed=0
    if has_cmd crontab; then
        TMP_CRON="/tmp/cron_tmp_http_time_sync.txt"
        # 如果有任务就导出，没有任务就创建一个空文件
        # crontab -l 2>/dev/null > $TMP_CRON || true
        if crontab -l >/dev/null 2>&1; then
            crontab -l > $TMP_CRON
        else
            touch $TMP_CRON
        fi

        if grep -q "http_time_sync" "$TMP_CRON"; then
            grep -v 'http_time_sync' "$TMP_CRON" 2>/dev/null >"${TMP_CRON}222" 
            crontab "${TMP_CRON}222"
            rm -f "${TMP_CRON}222"
            removed=1
            printf '已删除: %s\n' "已删除: 定时任务【定期同步时间】 http_time_sync"
            systemctl restart cron || systemctl restart crond || true
        fi
        rm -f $TMP_CRON
    else
        log_msg "未识别crontab命令"
        exit 1
    fi

    if [ -d "$CONF_INSTALL_DIR" ]; then
        rm -rf "$CONF_INSTALL_DIR" 2>/dev/null
        printf '已删除: %s\n' "$CONF_INSTALL_DIR"
        removed=1
    fi

    if [ "$removed" -eq 0 ]; then
        printf '未找到已安装的组件\n'
    else
        printf '卸载完成（日志文件 %s 已保留）\n' "$CONF_LOG_FILE"
    fi
}

sync_time() {
    local server=$1
    local http_date=""

    # 提取 HTTP 响应头中的 Date 字段
    # 优先使用 curl，后备使用 wget
    if command -v curl >/dev/null 2>&1; then
        http_date=$(curl -s -I --connect-timeout $TIMEOUT -m $TIMEOUT "$server" | grep -i "^date:" | sed 's/^[Dd]ate:[ \t]*//i' | tr -d '\r')
    elif command -v wget >/dev/null 2>&1; then
        # wget 在不同系统中表现不同，--spider 适合仅获取头部
        http_date=$(wget -q -S --spider -T $TIMEOUT -t 1 "$server" 2>&1 | grep -i "^[ \t]*date:" | sed 's/^[ \t]*[Dd]ate:[ \t]*//i' | tr -d '\r')
    else
        log_msg "ERROR: 找不到 curl 或 wget 命令，无法执行同步。"
        exit 1
    fi

    if [ -n "$http_date" ]; then
        # HTTP Date 标准返回的是 GMT 时区时间 (如: Fri, 03 Apr 2026 09:00:15 GMT)
        # 使用 date -u 强制系统按 UTC 零时区逻辑解析该字符串，系统会自动换算为你的本地时区(CST)
        if date -u -s "$http_date" >/dev/null 2>&1; then
            log_msg "SUCCESS: 时间同步成功 -> $(date) (来源: $server)"
            
            # 如果存在硬件时钟 (RTC)，则将系统时间刷入硬件，防止重启后丢失
            # 注意：部分精简版 OpenWrt 路由器可能没有硬件RTC芯片
            if command -v hwclock >/dev/null 2>&1; then
                hwclock -w -u >/dev/null 2>&1
            fi
            return 0
        fi
    fi
    return 1
}

do_sync_time() {
    # 遍历测速：只要有一个服务器同步成功，直接退出并返回 0 (成功状态码)
    for srv in $SERVERS; do
        if sync_time "$srv"; then
            log_msg "时间同步成功"
            exit 0
        fi
    done
    log_msg "时间同步失败"
}

case "${1:-}" in
    install)           do_install ;;
    uninstall)         do_uninstall ;;
    *)                 do_sync_time ;;
esac