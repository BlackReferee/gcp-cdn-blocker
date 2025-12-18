#!/bin/bash

# ====================================================
# 项目名称: GCP CDN Egress Blocker (Pro Plus)
# 功能: 自动抓取 IP、分片部署、定时任务安装与【自动校验】
# 适配系统: Google Cloud Platform (GCE)
# ====================================================

# --- 基础配置 ---
ASNS=("13335" "20940" "54113") 
RULE_PREFIX="deny-cdn-egress"
SCRIPT_PATH=$(realpath "$0")
LOG_FILE="$(dirname "$SCRIPT_PATH")/cdn_block.log"
TEST_IPS=("1.1.1.1" "151.101.1.69" "23.235.32.7")

# --- 1. 核心逻辑：部署防火墙 ---
update_firewall() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动防火墙同步程序..."
    ALL_IPS=()
    for ASN in "${ASNS[@]}"; do
        echo "正在提取 AS$ASN (RADB) 的最新 IP 库..."
        IPS=$(whois -h whois.radb.net -- "-i origin AS$ASN" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
        for ip in $IPS; do ALL_IPS+=("$ip"); done
    done

    total=${#ALL_IPS[@]}
    [ "$total" -eq 0 ] && { echo "错误：未抓取到 IP"; exit 1; }

    echo "清理旧规则并部署 $total 个新网段..."
    OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
    for rule in $OLD_RULES; do gcloud compute firewall-rules delete "$rule" --quiet; done

    group_size=200
    count=0
    for (( i=0; i<total; i+=group_size )); do
        batch=("${ALL_IPS[@]:i:group_size}")
        dest_ranges=$(IFS=,; echo "${batch[*]}")
        gcloud compute firewall-rules create "${RULE_PREFIX}-$count" \
            --action=DENY --rules=all --direction=EGRESS --priority=1000 \
            --destination-ranges="$dest_ranges" --quiet
        ((count++))
    done
    echo "[SUCCESS] 防火墙分片规则已应用。"
}

# --- 2. 核心逻辑：检测拦截状态 ---
check_status() {
    echo -e "\n--- 防火墙拦截有效性检测 ---"
    for IP in "${TEST_IPS[@]}"; do
        echo -n "检测目标 $IP ... "
        if curl -I -s --connect-timeout 3 "http://$IP" > /dev/null; then
            echo -e "\e[31m[ 未拦截 ]\e[0m"
        else
            echo -e "\e[32m[ 成功拦截 ]\e[0m"
        fi
    done
}

# --- 3. 核心逻辑：定时任务安装与【校验】 ---
install_cron() {
    echo "======================================="
    echo "   GCP 防火墙自动化管理安装向导"
    echo "======================================="
    echo "请选择脚本自动同步更新的频率:"
    echo "1) 每一天凌晨 1 点"
    echo "2) 每周一凌晨 1 点"
    echo "3) 每月 1 号凌晨 1 点"
    echo "4) 取消退出"
    read -p "请输入数字 [1-4]: " choice

    case $choice in
        1) cron_time="0 1 * * *" ;;
        2) cron_time="0 1 * * 1" ;;
        3) cron_time="0 1 1 * *" ;;
        *) echo "操作取消"; exit 0 ;;
    esac

    # 写入 Crontab
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$cron_time /bin/bash $SCRIPT_PATH update > $LOG_FILE 2>&1") | crontab -
    
    # --- 【新增】定时任务校验逻辑 ---
    echo -n "正在校验定时任务是否写入系统... "
    sleep 1 # 等待系统同步
    if crontab -l | grep -q "$SCRIPT_PATH"; then
        echo -e "\e[32m[ 校验成功 ]\e[0m"
        echo "任务详情: $(crontab -l | grep "$SCRIPT_PATH")"
    else
        echo -e "\e[31m[ 校验失败 ]\e[0m"
        echo "警告：任务未能写入 Crontab，请检查当前用户是否有 cron 使用权限。"
        exit 1
    fi

    # 立即执行首次部署
    echo -e "\n启动首次实时同步部署..."
    update_firewall
    check_status

    echo -e "\n======================================="
    echo "安装与首次部署已全部完成！"
    echo "======================================="
}

# --- 4. 核心逻辑：清理 ---
clear_all() {
    echo "清理中..."
    OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
    for rule in $OLD_RULES; do gcloud compute firewall-rules delete "$rule" --quiet; done
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo "清理完毕。"
}

# --- 命令行入口 ---
case "$1" in
    install) install_cron ;;
    update)  update_firewall; check_status ;;
    check)   check_status ;;
    clear)   clear_all ;;
    *)
        echo "用法: $0 {install|update|check|clear}"
        exit 1
esac
