#!/bin/sh
# rule-sync.sh - 规则同步脚本
# 兼容 OpenWrt (ash/busybox) 和通用 Linux (bash)

set -e

# 1. 获取脚本所在的绝对目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# 2. 获取脚本的完整绝对路径（包含文件名）
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
JAR_PATH="$SCRIPT_DIR/rule-sync-1.0-SNAPSHOT.jar"
DEFAULT_SRC_PATH="/opt/softs/meta-rules-dat"
DEFAULT_DEST_PATH="/opt/softs/share-files"

# ============ 工具函数 ============
write_log() {
    # 检查是否传入了足够的参数
    if [ "$#" -lt 2 ]; then
        return 1
    fi

    local level="$1"
    shift # 移除第一个参数，剩下的全都是消息内容
    
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # 使用 printf 保证在 bash 和 busybox ash 中的绝对兼容性
    printf "%s [%s] %s\n" "$timestamp" "$level" "$*"
}

# 快捷调用函数
log_info()  { write_log "INFO"  "$@"; }
log_warn()  { write_log "WARN"  "$@"; }
log_error() { write_log "ERROR" "$@"; }
log_debug() { write_log "DEBUG" "$@"; }

check_command() {
  command -v "$1" >/dev/null 2>&1 || {
	  log_error "未找到命令: $1"
	  exit 1
  }
}

# 查找 Java 运行时
find_java() {
  if command -v java >/dev/null 2>&1; then
	  echo "java"
  elif [ -x "/usr/bin/java" ]; then
	  echo "/usr/bin/java"
  elif [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
	  echo "$JAVA_HOME/bin/java"
  else
	  log_error "未找到 Java 运行时"
	  exit 1
  fi
}

# ============ 主流程 ============

SRC_PATH="${1:-$DEFAULT_SRC_PATH}"
DEST_PATH="${2:-$DEFAULT_DEST_PATH}"

SOURCE_REPO="$SRC_PATH"
TARGET_REPO="$DEST_PATH"

log_info "========================================================================"
log_info "主目录: $SCRIPT_DIR"
log_info "源路径: $SRC_PATH"
log_info "目标路径: $DEST_PATH"

# 检查必要命令
check_command git
check_command python

# pip install netaddr
python "$SCRIPT_DIR/gma-ip-official.py" "$DEST_PATH/rules"

# 检查目录和文件
[ -d "$SOURCE_REPO" ] || { log_error "源仓库不存在: $SOURCE_REPO"; exit 1; }
[ -d "$TARGET_REPO" ] || { log_error "目标仓库不存在: $TARGET_REPO"; exit 1; }
[ -f "$JAR_PATH" ] || { log_error "JAR文件不存在: $JAR_PATH"; exit 1; }

JAVA_CMD=$(find_java)
log_info "使用 Java: $JAVA_CMD"

# 步骤1: 更新源仓库
log_info "正在更新源仓库: $SOURCE_REPO"
cd "$SOURCE_REPO"
git fetch --all
git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
log_info "源仓库更新完成"

# 步骤2: 运行 JAR 程序
log_info "正在运行同步程序..."
"$JAVA_CMD" -jar "$JAR_PATH" "$SRC_PATH/" "$DEST_PATH/rules/" >> ~/rules_sync_new.log
log_info "同步程序执行完成"

# 步骤3: 提交推送目标仓库
log_info "正在处理目标仓库: $TARGET_REPO"
cd "$TARGET_REPO"

# 检查是否有变更
if git diff --quiet && git diff --cached --quiet; then
  log_info "目标仓库无变更，跳过提交"
else
  COMMIT_MSG="sync: update rules $(date '+%Y-%m-%d %H:%M:%S')"
  git add -A
  git commit -m "$COMMIT_MSG"
  git push
  log_info "目标仓库推送完成"
fi

log_info "全部任务完成"