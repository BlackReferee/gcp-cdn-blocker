#!/bin/bash

# ====================================================
# 项目名称: GCP CDN Egress Blocker (One-Click Ultimate)
# 功能: 首次运行自动完成：定时设置 + 防火墙部署 + 拦截检测
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
    echo -e "\n[步骤 1/2] 正在同步 CDN IP 并更新 GCP 防火墙..."
    ALL_IPS=()
    for ASN in "${ASNS[@]}"; do
        echo "正在从 RADB 提取 AS$ASN 的网段..."
        IPS=$(whois -h whois.radb.net -- "-i origin AS$ASN" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
        for ip in $IPS; do ALL_IPS+=("$ip"); done
    done

    total=${#ALL_IPS[@]}
    [ "$total" -eq 0 ] && { echo "错误：抓取 IP 失败，请检查 whois 工具。"; exit 1; }

    # 清理旧规则
    OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
    for rule in $OLD_RULES; do gcloud compute firewall-rules delete "$rule" --quiet; done

    # 分片部署
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
    echo "[SUCCESS] 防火墙规则已同步完成。"
}

# --- 2. 核心逻辑：检测拦截状态 ---
check_status() {
    echo -e "\n[步骤 2/2] 正在验证拦截有效性..."
    echo "---------------------------------------"
    for IP in "${TEST_IPS[@]}"; do
        echo -n "检测目标 $IP ... "
        if curl -I -s --connect-timeout 3 "http://$IP" > /dev/null; then
            echo -e "\e[31m[ 未拦截 ]\e[0m"
        else
            echo -e "\e[32m[ 拦截成功 ]\e[0m"
        fi
    done
    echo "---------------------------------------"
}

# --- 3. 核心逻辑：定时任务安装与校验 ---
install_cron() {
    echo "======================================="
    echo "   首次运行：GCP 防火墙全自动配置向导"
    echo "======================================="
    echo "请选择脚本自动同步更新的频率:"
    echo "1) 每一天凌晨 1 点"
    echo "2) 每周一凌晨 1 点"
    echo "3) 每月 1 号凌晨 1 点"
    read -p "请输入数字 [1-3]: " choice

    case $choice in
        1) cron_time="0 1 * * *" ;;
        2) cron_time="0 1 * * 1" ;;
        3) cron_time="0 1 1 * *" ;;
        *) echo "输入无效，默认选择每天凌晨 1 点"; cron_time="0 1 * * *" ;;
    esac

    # 写入并校验
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$cron_time /bin/bash $SCRIPT_PATH update > $LOG_FILE 2>&1") | crontab -
    
    echo -n "正在校验定时任务状态... "
    sleep 1
    if crontab -l | grep -q "$SCRIPT_PATH"; then
        echo -e "\e[32m[ 任务已成功挂载 ]\e[0m"
    else
        echo -e "\e[31m[ 校验失败 ]\e[0m"
        exit 1
    fi
}

# --- 主逻辑入口 ---
case "$1" in
    update)
        # 定时任务触发此参数
        update_firewall
        check_status
        ;;
    clear)
        # 手动清理
        echo "正在卸载所有规则与定时任务..."
        OLD_RULES=$(gcloud compute firewall-rules list --filter="name ~ ^$RULE_PREFIX" --format="value(name)")
        for rule in $OLD_RULES; do gcloud compute firewall-rules delete "$rule" --quiet; done
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
        echo "清理完毕。"
        ;;
    check)
        check_status
        ;;
    *)
        # ！！！核心修改：不带参数直接运行默认执行全套流程 ！！！
        # 检查是否已经安装过定时任务
        if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
            echo "检测到系统已配置自动更新，现在执行手动同步测试..."
            update_firewall
            check_status
        else
            # 首次运行，执行全流程
            install_cron
            update_firewall
            check_status
            echo -e "\n[恭喜] 首次全功能初始化已完成！"
            echo "以后系统会按计划自动更新，你也可以随时运行 $0 check 进行检测。"
        fi
        ;;
esac
