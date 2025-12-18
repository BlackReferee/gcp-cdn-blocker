#!/bin/bash

# ====================================================
# 项目名称: GCP CDN Egress Blocker (Pro Version)
# 功能: 自动更新防火墙、状态检测、交互式定时任务配置
# 托管: 适合托管至 GitHub
# ====================================================

# --- 基础配置 ---
ASNS=("13335" "20940" "54113") 
RULE_PREFIX="deny-cdn-egress"
SCRIPT_PATH=$(realpath "$0")
LOG_FILE="$(dirname "$SCRIPT_PATH")/cdn_block.log"
TEST_IPS=("1.1.1.1" "151.101.1.69" "23.235.32.7")

# --- 核心逻辑：部署防火墙 ---
update_firewall() {
    echo "[$(date)] 正在获取最新 IP 段 (RADB)..."
    ALL_IPS=()
    for ASN in "${ASNS[@]}"; do
        echo "正在提取 AS$ASN 数据..."
        IPS=$(whois -h whois.radb.net -- "-i origin AS$ASN" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
        for ip in $IPS; do ALL_IPS+=($ip); done
    done

    total=${#ALL_IPS[@]}
    [ $total -eq 0 ] && { echo "错误：未获取到数据"; exit 1; }

    echo "清理旧规则并部署 $total 个新网段..."
    OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
    for rule in $OLD_RULES; do gcloud compute firewall-rules delete $rule --quiet; done

    group_size=200
    count=0
    for (( i=0; i<$total; i+=group_size )); do
        batch=("${ALL_IPS[@]:i:group_size}")
        dest_ranges=$(IFS=,; echo "${batch[*]}")
        gcloud compute firewall-rules create "${RULE_PREFIX}-$count" \
            --action=DENY --rules=all --direction=EGRESS --priority=1000 \
            --destination-ranges="$dest_ranges" --quiet
        ((count++))
    done
    echo "[SUCCESS] 防火墙已部署。"
}

# --- 核心逻辑：检测状态 ---
check_status() {
    echo -e "\n--- 防火墙拦截有效性检测 ---"
    for IP in "${TEST_IPS[@]}"; do
        echo -n "检测目标 $IP ... "
        if curl -I -s --connect-timeout 3 http://$IP > /dev/null; then
            echo -e "\e[31m[ 未拦截 ]\e[0m"
        else
            echo -e "\e[32m[ 成功拦截 ]\e[0m"
        fi
    done
}

# --- 核心逻辑：定时任务安装器 ---
install_cron() {
    echo "======================================="
    echo "   GCP 防火墙定时更新配置向导"
    echo "======================================="
    echo "请选择自动更新频率:"
    echo "1) 每天凌晨 1 点 (推荐)"
    echo "2) 每周一凌晨 1 点"
    echo "3) 每月 1 号凌晨 1 点"
    echo "4) 取消并退出"
    read -p "请输入选项 [1-4]: " choice

    case $choice in
        1) cron_time="0 1 * * *" ;;
        2) cron_time="0 1 * * 1" ;;
        3) cron_time="0 1 1 * *" ;;
        *) echo "操作取消"; exit 0 ;;
    esac

    # 清除旧的同名任务并添加新任务
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$cron_time /bin/bash $SCRIPT_PATH update > $LOG_FILE 2>&1") | crontab -
    echo "[SUCCESS] 定时任务已设置！"
    echo "当前 Cron 规则: $(crontab -l | grep "$SCRIPT_PATH")"
}

# --- 命令行参数处理 ---
case "$1" in
    update)  update_firewall; check_status ;;
    check)   check_status ;;
    install) install_cron ;;
    clear)
        echo "清理所有规则..."; 
        OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
        for rule in $OLD_RULES; do gcloud compute firewall-rules delete $rule --quiet; done
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
        echo "已卸载规则与定时任务。" ;;
    *)
        echo "使用方法: $0 {install|update|check|clear}"
        exit 1
esac
