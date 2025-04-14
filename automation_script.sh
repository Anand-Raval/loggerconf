#!/bin/bash

################################################################################
#                            Logger Automation Script                          #
################################################################################
# This script automates the setup and configuration of a syslog logger system.
#
# ▶ What this script does (step-by-step):
#
# Step 1: Install required packages like ca-certificates.
# Step 2: Start and restart the rsyslog service.
# Step 3: Validate presence of CA certificate files.
# Step 4: Modify system limits configuration.
# Step 5: Setup required crontab jobs.
# Step 6: Create size_logfile.txt file for log size monitoring.
# Step 7: Interactively create newpurge.sh script.
#
# ▶ Usage:
#   sudo ./automation_script.sh                 # Run all steps
#   sudo ./automation_script.sh --resume 4     # Start directly from step 4
#
# Notes:
# - Each step checks if it's already completed (idempotent).
# - Uses --resume option to jump to a specific step.
# - Logs are written to /var/log/automation_setup.log
################################################################################

LOGFILE="/var/log/automation_setup.log"

log() {
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

highlight() {
    echo -e "\n\e[1;34m==================== $1 ====================\e[0m\n"
    log "$1"
}

install_package() {
    log "Installing package: $1"
    if apt-get install -y "$1"; then
        log "✅ Successfully installed $1."
    else
        log "❌ Failed to install $1. Exiting."
        exit 1
    fi
}

RESUME_STEP=0
if [[ "$1" == "--resume" && -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
    RESUME_STEP=$2
    highlight "Resuming from Step $RESUME_STEP"
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "❌ Please run this script as root or with sudo."
    exit 1
fi

########################################
CURRENT_STEP=1
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 1: System Update & Package Installations"
    apt-get update || { log "❌ apt-get update failed."; exit 1; }
    install_package python3
    install_package rsyslog
    install_package rsyslog-relp
    install_package rsyslog-gnutls
    install_package gnutls-bin
    install_package ca-certificates
fi

########################################
CURRENT_STEP=2
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 2: Start and Restart rsyslog Service"
    systemctl start rsyslog && log "✅ rsyslog started." || { log "❌ Failed to start rsyslog."; exit 1; }
    systemctl restart rsyslog && log "✅ rsyslog restarted." || { log "❌ Failed to restart rsyslog."; exit 1; }
fi

########################################
CURRENT_STEP=3
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 3: Certificate Setup (Optional)"
    CERT_FILES=("CA.pem" "client-cert.pem" "client-key.pem")
    for cert in "${CERT_FILES[@]}"; do
        if [[ ! -f "$cert" ]]; then
            log "⚠️ Certificate file $cert not found. Skipping certificate setup."
        else
            chmod 644 "$cert" && log "Set permissions for $cert."
        fi
    done
    update-ca-certificates && log "✅ CA certificates updated."
fi

########################################
CURRENT_STEP=4
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 4: Modify System Limits"
    LIMITS_FILE="/etc/security/limits.conf"
    cp "$LIMITS_FILE" "$LIMITS_FILE.backup"
    LIMITS=(
        "* soft nofile 100000"
        "* hard nofile 100000"
        "root soft nofile 100000"
        "root hard nofile 100000"
    )
    for line in "${LIMITS[@]}"; do
        grep -Fxq "$line" "$LIMITS_FILE" || echo "$line" >> "$LIMITS_FILE"
    done
    log "✅ System limits updated."
fi

########################################
CURRENT_STEP=5
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 5: Setup Crontab Jobs"
    CRON_JOBS=(
        "* * * * * sudo systemctl restart rsyslog"
        "0 0 * * * /var/log/newpurge.sh"
        "0 0 * * * sudo systemctl restart evenus-agent"
    )
    TMP_CRON=$(mktemp)
    crontab -l > "$TMP_CRON" 2>/dev/null
    for job in "${CRON_JOBS[@]}"; do
        grep -Fq "$job" "$TMP_CRON" || echo "$job" >> "$TMP_CRON"
    done
    crontab "$TMP_CRON"
    rm "$TMP_CRON"
    log "✅ Crontab updated."
fi

########################################
CURRENT_STEP=6
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 6: Create size_logfile.txt"
    if [[ ! -f /var/log/size_logfile.txt ]]; then
        touch /var/log/size_logfile.txt && log "✅ Created /var/log/size_logfile.txt."
    else
        log "ℹ️ /var/log/size_logfile.txt already exists."
    fi
fi

########################################
CURRENT_STEP=7
if [[ $RESUME_STEP -le $CURRENT_STEP ]]; then
highlight "Step 7: Interactive Setup of newpurge.sh"
    echo -e "\e[1;33mPlease now open /var/log/newpurge.sh in an editor (e.g., nano):\e[0m"
    echo -e "\e[1;32m  nano /var/log/newpurge.sh\e[0m"
    echo "Paste your script content, save and exit."
    read -rp "Press ENTER once you have saved the file to continue..."

    if [[ ! -f /var/log/newpurge.sh ]]; then
        log "❌ newpurge.sh was not created. Exiting."
        exit 1
    fi

    chmod +x /var/log/newpurge.sh && log "✅ newpurge.sh is now executable."
fi

highlight "✅ Logger Setup Automation Completed Successfully"
echo -e "\e[1;32mAll steps completed. You may now verify log ingestion and functionality.\e[0m"
exit 0
