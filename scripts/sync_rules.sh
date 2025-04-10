#!/bin/sh
#set -e

global_temp_path="/root/_temps_"

print_message(){
  # -eq/-ne/-gt/-lt/-ge/-le
  echo "$1"
}

clean_up(){
  code=$1
}

exit_now(){
  code="$1"
  msg="$2"
  clean_up $code
  if [ $code -eq 0 ]; then
    print_message "任务结束：成功。"
  else
    print_message "任务结束：失败（error=$code, message=$msg）"
  fi
  exit $code
}

exit_on_code_failure(){
  code="$1"
  msg="$2"
  if [ $code -ne 0 ]; then
    exit_now "$code" "$msg"
  fi
  return 0
}

command_exists() {
  # command -v $1 > /dev/null 2>&1
  command -v "$@" > /dev/null 2>&1
  # return $?
}

download_and_cover() {
  file_url="$1"
  tmp_file="$2"
  dest_file="$3"
  curl -fL "$file_url" -o "$tmp_file"
  code=$?
  if [ $code -ne 0 ]; then
    return $code
  fi
  if head -n 1 "$tmp_file" | grep -q "^payload:"; then
    print_message "payload校验：通过，$file_url"
    cat $tmp_file > $dest_file
  else
    print_message "payload校验：未通过，跳过"
  fi
  return $?
}

git_init(){
  #sudo apt-get install git
  #ssh-keygen -t ed25519 -C "your_email@example.com"
  #复制密钥【cat ~/.ssh/id_ed25519.pub】，添加到github中
  #git config --global user.name "your_username"
  #git config --global user.email "your_email@example.com"
  print_message "git 初始化"
}

git_changed(){
  recv_file="$1"
  # 综合检测逻辑
  if [ -n "$(git status --porcelain $recv_file 2>/dev/null)" ]; then
      #echo "Git检测到变化"
      return 0
  elif ! git ls-files --error-unmatch $recv_file >/dev/null 2>&1 && [ -f $recv_file ]; then
      #echo "新增未跟踪文件"
      return 0
  else
      #echo "无变化"
      return 1
  fi
}

update_box_rule_geoip_cn_3rd(){
  print_message "开始更新 geoip_cn_3rd"
  content=""
  content_file1="$global_temp_path/content_tmp1.txt"
  cat /dev/null > "$content_file1"
  while IFS= read -r line; do
      domain=$(echo "$line" | awk -F"'" '{print $2}')
      if [ -z "$domain" ]; then
          continue
      fi
      #content="${content}\n        \"${domain}\","
      echo "        \"${domain}\"," >> "$content_file1"
  done < "$share_files_path/clash/rules/geoip-cn-3rd.txt"
  content=$(cat "$content_file1")
  content="${content%,}"
  cat << EOF > "$share_files_path/sbox/rules/geoip-cn-3rd.json"
{
  "version": 1,
  "rules": [
    {
      "ip_cidr": [
${content}
      ]
    }
  ]
}
EOF
  print_message "更新完成 geoip_cn_3rd"
}

update_box_rule_geosite_cn_3rd(){
  print_message "开始更新 geosite_cn_3rd"
  content=""
  content_file1="$global_temp_path/content_tmp1.txt"
  cat /dev/null > "$content_file1"
  content_file2="$global_temp_path/content_tmp2.txt"
  cat /dev/null > "$content_file2"
  while IFS= read -r line; do
      domain=$(echo "$line" | awk -F"'" '{print $2}')
      if [ -z "$domain" ]; then
          continue
      fi
      domain=$(echo "$domain" | sed 's/^[^0-9a-zA-Z_-]*//')
      #content="${content}\n        \"${domain}\","
      #content2="${content2}\n        \".${domain}\","
      echo "        \"${domain}\"," >> "$content_file1"
      echo "        \".${domain}\"," >> "$content_file2"
  done < "$share_files_path/clash/rules/geosite-cn-3rd.txt"
  content=$(cat "$content_file1")
  content2=$(cat "$content_file2")
  content="${content%,}"
  content2="${content2%,}"
  cat << EOF > "$share_files_path/sbox/rules/geosite-cn-3rd.json"
{
  "version": 1,
  "rules": [
    {
      "domain": [
${content}
      ],
      "domain_suffix": [
${content2}
      ]
    }
  ]
}
EOF
  print_message "更新完成 geosite_cn_3rd"
}

update_box_rule_geosite_proxy_3rd(){
  print_message "开始更新 geosite_proxy_3rd"
  content=""
  content_file1="$global_temp_path/content_tmp1.txt"
  cat /dev/null > "$content_file1"
  content_file2="$global_temp_path/content_tmp2.txt"
  cat /dev/null > "$content_file2"
  while IFS= read -r line; do
      domain=$(echo "$line" | awk -F"'" '{print $2}')
      if [ -z "$domain" ]; then
          continue
      fi
      domain=$(echo "$domain" | sed 's/^[^0-9a-zA-Z_-]*//')
      #content="${content}\n        \"${domain}\","
      #content2="${content2}\n        \".${domain}\","
      echo "        \"${domain}\"," >> "$content_file1"
      echo "        \".${domain}\"," >> "$content_file2"
  done < "$share_files_path/clash/rules/geosite-proxy-3rd.txt"
  content=$(cat "$content_file1")
  content2=$(cat "$content_file2")
  content="${content%,}"
  content2="${content2%,}"
  cat << EOF > "$share_files_path/sbox/rules/geosite-proxy-3rd.json"
{
  "version": 1,
  "rules": [
    {
      "domain": [
${content}
      ],
      "domain_suffix": [
${content2}
      ]
    }
  ]
}
EOF
  print_message "更新完成 geosite_proxy_3rd"
}

update_box_rule_geosite_usincn_block(){
  print_message "开始更新 geosite_usincn_block"
  content=""
  contentall="  - '+.xxx.xxx.xxx'\n"
  content_file="$global_temp_path/content_tmp.txt"

  cat /dev/null > "$content_file"
  curl -fL https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/apple.txt -o "$content_file"
  content=$(cat "$content_file")
  contentall="${contentall}\n${content}"

  cat /dev/null > "$content_file"
  curl -fL https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/icloud.txt -o "$content_file"
  content=$(cat "$content_file")
  contentall="${contentall}\n${content}"

  cat /dev/null > "$content_file"
  curl -fL https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/google.txt -o "$content_file"
  content=$(cat "$content_file")
  contentall="${contentall}\n${content}"
  echo "$contentall" > "$content_file"

  content1=""
  content2=""
  content3=""
  content_file1="$global_temp_path/content_tmp1.txt"
  cat /dev/null > "$content_file1"
  content_file2="$global_temp_path/content_tmp2.txt"
  cat /dev/null > "$content_file2"
  content_file3="$global_temp_path/content_tmp3.txt"
  cat /dev/null > "$content_file3"
  while IFS= read -r line; do
      domain=$(echo "$line" | awk -F"'" '{print $2}')
      if [ -z "$domain" ]; then
          continue
      fi
      #content3="${content3}\n  - '${domain}'"
      echo "  - '${domain}'" >> "$content_file3"
      domain=$(echo "$domain" | sed 's/^[^0-9a-zA-Z_-]*//')
      #content="${content}\n        \"${domain}\","
      #content2="${content2}\n        \".${domain}\","
      echo "        \"${domain}\"," >> "$content_file1"
      echo "        \".${domain}\"," >> "$content_file2"
  done < "$global_temp_path/content_tmp.txt"
  content1=$(cat "$content_file1")
  content2=$(cat "$content_file2")
  content3=$(cat "$content_file3")
  content1="${content1%,}"
  content2="${content2%,}"
  cat << EOF > "$share_files_path/clash/rules/geosite-usincn-block.txt"
payload:
${content3}
EOF
  cat << EOF > "$share_files_path/sbox/rules/geosite-usincn-block.json"
{
  "version": 1,
  "rules": [
    {
      "domain": [
${content1}
      ],
      "domain_suffix": [
${content2}
      ]
    }
  ]
}
EOF
  print_message "更新完成 geosite_usincn_block"
}

# 主流程开始 ----------------------
print_message "start script: ------------------------------------------------------------------------"
date "+%Y-%m-%d %H:%M:%S %:z"
curr_script_path=$(readlink -f "$0")
curr_script_path=$(dirname "$curr_script_path")
share_files_home_path="/opt/softs"
global_temp_path="/root/_temps_"
share_files_path="${share_files_home_path}/share-files"
if ! command_exists git; then
  exit_now 1 "请先安装并配置git"
fi

mkdir -p "$share_files_home_path"
mkdir -p "$global_temp_path"
touch "$global_temp_path/content_tmp1.txt"
touch "$global_temp_path/content_tmp2.txt"

if [ -d "$share_files_path" ]; then
  cd "$share_files_path"
  git pull origin main
  exit_on_code_failure $? "git pull 项目失败"
else
  cd "$share_files_home_path"
  git clone -b "main" "git@github.com:landergo123/share-files.git" "$share_files_path"
  exit_on_code_failure $? "git clone 项目失败"
  cd "$share_files_path"
fi
print_message "当前工作目录：$(pwd)"


#file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/cncidr.txt"
#curl -fL "$file_url" -o "$share_files_path/clash/rules/geoip-cn-3rd.txt"

#file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"
#curl -fL "$file_url" -o "$share_files_path/clash/rules/geoip-proxy-3rd.txt"

#file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"
#curl -fL "$file_url" -o "$share_files_path/clash/rules/geosite-cn-3rd.txt"

#file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt"
#curl -fL "$file_url" -o "$share_files_path/clash/rules/geosite-proxy-3rd.txt"

file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/cncidr.txt"
temp_file="$global_temp_path/content_tmp1.txt"
dest_file="$share_files_path/clash/rules/geoip-cn-3rd.txt"
download_and_cover "$file_url" "$temp_file" "$dest_file"

#file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"
#curl -fL "$file_url" -o "$share_files_path/clash/rules/geoip-proxy-3rd.txt"

file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"
temp_file="$global_temp_path/content_tmp1.txt"
dest_file="$share_files_path/clash/rules/geosite-cn-3rd.txt"
download_and_cover "$file_url" "$temp_file" "$dest_file"

file_url="https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt"
temp_file="$global_temp_path/content_tmp1.txt"
dest_file="$share_files_path/clash/rules/geosite-proxy-3rd.txt"
download_and_cover "$file_url" "$temp_file" "$dest_file"

if git_changed "$share_files_path/clash/rules/geoip-cn-3rd.txt"; then
  update_box_rule_geoip_cn_3rd
else
  print_message "geoip-cn-3rd 无更新"
fi

if git_changed "$share_files_path/clash/rules/geosite-cn-3rd.txt"; then
  update_box_rule_geosite_cn_3rd
else
  print_message "geosite_cn_3rd 无更新"
fi

if git_changed "$share_files_path/clash/rules/geosite-proxy-3rd.txt"; then
  update_box_rule_geosite_proxy_3rd
else
  print_message "geosite_proxy_3rd 无更新"
fi

update_box_rule_geosite_usincn_block

print_message "current status: ..."
git status
git add .
curr_time=$(date +"%Y%m%d_%H%M%S")
git commit -m "updated on $curr_time" || true
print_message "start push: ..."
git push origin "main" || true
print_message "current status: ..."
git status

rm -f "$global_temp_path/content_tmp1.txt"
rm -f "$global_temp_path/content_tmp2.txt"


#chmod +x "$curr_script_path"/sync_rules.sh
#crontab -e
# 每天凌晨3点执行，输出日志到指定文件
#33 12 * * * /bin/bash /root/auto-tasks/scripts/sync_rules.sh >> /root/sync_rules_cron.log 2>&1
#systemctl restart cron
# 检查crontab中是否已经存在该脚本的任务
if crontab -l | grep -q "sync_rules.sh"; then
  print_message "定时任务已存在，无需添加"
else
  # 添加每天12点执行的定时任务
  chmod +x "$curr_script_path"/sync_rules.sh
  (crontab -l 2>/dev/null; echo "0 12 * * * ${curr_script_path}/sync_rules.sh >> /root/sync_rules_cron.log 2>&1") | crontab -
  print_message "已添加定时任务：每天12点执行 ${curr_script_path}/sync_rules.sh"
fi
print_message "finish script: ------------------------------------------------------------------------"



