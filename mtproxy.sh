#!/bin/bash
# ============================================================
#  Messenger Proxy Manager v5.0
#  Telegram MTProxy (Fake TLS) + Xray SOCKS5 (WhatsApp/universal)
#  GitHub: https://github.com/ivanstudiya-cpu/mtproxy
# ============================================================

set -o pipefail
umask 077

BINARY_PATH="/usr/local/bin/mtproxy"
XRAY_DIR="/etc/mtproxy/xray"
BACKUP_DIR="/etc/mtproxy/backups"
LOG_FILE="/var/log/mtproxy.log"
CONFIG_DIR="/etc/mtproxy"
CONFIG_FILE="$CONFIG_DIR/proxies.conf"
EXPORT_FILE="$CONFIG_DIR/export_links.txt"
CRON_TAG="# mtproxy-auto"
GITHUB_RAW="https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh"
VERSION="5.0"
WARP_DIR="$CONFIG_DIR/warp"
WARP_XRAY_DIR="$CONFIG_DIR/xray-warp"
WARP_CONF="$CONFIG_DIR/warp.conf"
WGCF_BIN="/usr/local/bin/wgcf"
APT_UPDATED=0

# --- ЦВЕТА ---
R='\033[0;31m'
G='\033[0;32m'
C='\033[0;36m'
Y='\033[1;33m'
M='\033[0;35m'
B='\033[0;34m'
W='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# ─── УТИЛИТЫ ────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

die() {
    echo -e "${R}[ERROR]${NC} $*" >&2
    log "ERROR: $*"
    exit 1
}

info()    { echo -e "${C}[INFO]${NC} $*";  log "INFO: $*"; }
success() { echo -e "${G}[OK]${NC} $*";   log "OK: $*"; }
warn()    { echo -e "${Y}[WARN]${NC} $*"; log "WARN: $*"; }

banner() {
    clear
    echo -e "${M}"
    cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║     Messenger Proxy Manager v5.0                    ║
  ║     Telegram MTProxy + Xray SOCKS5                  ║
  ╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

pause() { read -rp $'\nНажмите Enter...' _; }

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

is_valid_index() {
    local idx="$1" max="$2"
    [[ "$idx" =~ ^[0-9]+$ ]] && (( 10#$idx >= 1 && 10#$idx <= max ))
}

is_valid_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.[a-zA-Z]{2,}$ ]]
}

is_systemd_available() {
    command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]
}

random_password() {
    if command -v openssl &>/dev/null; then
        openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
        echo
    else
        date +%s%N | sha256sum | cut -c1-24
    fi
}

secure_file() {
    [[ -f "$1" ]] && chmod 600 "$1" 2>/dev/null || true
}

secure_dir() {
    [[ -d "$1" ]] && chmod 700 "$1" 2>/dev/null || true
}

# ─── СИСТЕМНЫЕ ПРОВЕРКИ ──────────────────────────────────────

check_root() {
    [[ "$EUID" -ne 0 ]] && die "Запустите через sudo!"
}

check_os() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        die "Неподдерживаемый дистрибутив."
    fi
}

pkg_install() {
    if [[ $PKG_MANAGER == "apt" && $APT_UPDATED -eq 0 ]]; then
        apt-get update -qq >/dev/null 2>&1 || die "apt-get update завершился ошибкой."
        APT_UPDATED=1
    fi

    case $PKG_MANAGER in
        apt) apt-get install -y "$@" -qq >/dev/null 2>&1 ;;
        yum) yum install -y "$@" >/dev/null 2>&1 ;;
        dnf) dnf install -y "$@" >/dev/null 2>&1 ;;
    esac
    local rc=$?
    [[ $rc -eq 0 ]] || die "Не удалось установить пакеты: $*"
}

install_deps() {
    info "Проверка зависимостей..."

    if ! command -v curl &>/dev/null; then
        info "Установка curl..."
        pkg_install curl ca-certificates
    fi

    if ! command -v docker &>/dev/null; then
        info "Установка Docker..."
        local docker_installer
        docker_installer=$(mktemp /tmp/get-docker.XXXXXX)
        curl -fsSL https://get.docker.com -o "$docker_installer" || die "Не удалось скачать установщик Docker."
        sh "$docker_installer" >/dev/null 2>&1 || die "Установка Docker завершилась ошибкой."
        rm -f "$docker_installer"
        if command -v systemctl &>/dev/null; then
            systemctl enable --now docker >/dev/null 2>&1 || warn "Docker установлен, но systemctl не смог включить сервис автоматически."
        fi
        command -v docker &>/dev/null || die "Docker не найден после установки."
        success "Docker установлен."
    fi

    if ! command -v qrencode &>/dev/null; then
        info "Установка qrencode..."
        pkg_install qrencode
    fi

    if ! command -v jq &>/dev/null; then
        pkg_install jq
    fi

    if ! command -v python3 &>/dev/null; then
        pkg_install python3
    fi

    if ! command -v openssl &>/dev/null; then
        pkg_install openssl
    fi

    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR" "$XRAY_DIR" "$WARP_DIR" "$WARP_XRAY_DIR"
    secure_dir "$CONFIG_DIR"
    secure_dir "$BACKUP_DIR"
    secure_dir "$XRAY_DIR"
    secure_dir "$WARP_DIR"
    secure_dir "$WARP_XRAY_DIR"
    touch "$CONFIG_FILE" "$LOG_FILE"
    secure_file "$CONFIG_FILE"

    # Настраиваем logrotate если не настроен
    if [[ ! -f /etc/logrotate.d/mtproxy ]]; then
        cat > /etc/logrotate.d/mtproxy << 'LREOF'
/var/log/mtproxy.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 root root
}
LREOF
    fi

    if [[ ! -f "$BINARY_PATH" || "$(realpath "$0")" != "$BINARY_PATH" ]]; then
        cp "$0" "$BINARY_PATH"
        chmod 755 "$BINARY_PATH"
        success "Команда 'mtproxy' доступна глобально."
    fi
}

# ─── СЕТЬ ───────────────────────────────────────────────────

get_public_ip() {
    local ip
    for svc in "https://api.ipify.org" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
        ip=$(curl -s4 --max-time 4 "$svc" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "$ip"
            return
        fi
    done
    echo "0.0.0.0"
}


# ─── ДОМЕНЫ ─────────────────────────────────────────────────

# Категории: параллельные массивы меток и доменов
CAT_DISPLAY=(
    "Международные (Tech)"
    "Международные (СМИ)"
    "Международные (Развлечения)"
    "Международные (Образование)"
    "Российские (СМИ)"
    "Российские (Tech/IT)"
    "Российские (Образование)"
    "Российские (Сервисы)"
)

CAT_DOMAINS=(
    "google.com cloudflare.com microsoft.com apple.com amazon.com github.com stackoverflow.com gitlab.com"
    "wikipedia.org bbc.com cnn.com reuters.com nytimes.com theguardian.com bloomberg.com forbes.com"
    "netflix.com twitch.tv discord.com zoom.us spotify.com reddit.com medium.com tumblr.com"
    "coursera.org udemy.com khanacademy.org edx.org duolingo.com ted.com skillshare.com"
    "lenta.ru rbc.ru ria.ru kommersant.ru vedomosti.ru iz.ru novayagazeta.ru meduza.io"
    "habr.com mail.ru yandex.ru vk.com 2ch.hk pikabu.ru 4pda.to 3dnews.ru"
    "stepik.org geekbrains.ru skillbox.ru hexlet.io netology.ru skillfactory.ru"
    "gosuslugi.ru sberbank.ru tinkoff.ru avito.ru ozon.ru wildberries.ru kinopoisk.ru ivi.ru"
)

# Строим плоский массив всех доменов в порядке категорий
DOMAINS=()
_build_domain_list() {
    DOMAINS=()
    for cat_domains in "${CAT_DOMAINS[@]}"; do
        for d in $cat_domains; do
            DOMAINS+=("$d")
        done
    done
}

choose_domain() {
    _build_domain_list

    echo -e "\n${C}Выберите домен для Fake TLS маскировки:${NC}\n"

    local idx=0
    for i in "${!CAT_DISPLAY[@]}"; do
        echo -e "${W}  ── ${CAT_DISPLAY[$i]} ──${NC}"
        local col=0
        for d in ${CAT_DOMAINS[$i]}; do
            idx=$((idx + 1))
            col=$((col + 1))
            printf "  ${Y}%3d)${NC} %-25s" "$idx" "$d"
            [[ $((col % 3)) -eq 0 ]] && echo ""
        done
        # перенос строки если последняя строка не полная
        [[ $((col % 3)) -ne 0 ]] && echo ""
        echo ""
    done

    echo -e "${DIM}    0) Ввести свой домен${NC}\n"

    local choice
    read -rp "  Выбор [0-${#DOMAINS[@]}]: " choice

    if [[ "$choice" == "0" ]]; then
        read -rp "  Введите домен: " CHOSEN_DOMAIN
        CHOSEN_DOMAIN="${CHOSEN_DOMAIN//[^a-zA-Z0-9._-]/}"
        if ! is_valid_domain "$CHOSEN_DOMAIN"; then
            warn "Некорректный домен, используется google.com"
            CHOSEN_DOMAIN="google.com"
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#DOMAINS[@]}" ]]; then
        CHOSEN_DOMAIN="${DOMAINS[$((choice-1))]}"
    else
        warn "Некорректный выбор, используется google.com"
        CHOSEN_DOMAIN="google.com"
    fi

    CHOSEN_DOMAIN="${CHOSEN_DOMAIN:-google.com}"
    echo -e "  ${G}Выбран домен: $CHOSEN_DOMAIN${NC}"
}

# Проверяет открыт ли порт в firewall
_port_fw_status() {
    local port="$1"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw status 2>/dev/null | grep -qE "^${port}[/ ].*ALLOW" && echo "open" || echo "closed"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp" && echo "open" || echo "closed"
    elif command -v iptables &>/dev/null; then
        iptables -L INPUT -n 2>/dev/null | grep -q "dpt:${port}" && echo "open" || echo "closed"
    else
        echo "unknown"
    fi
}

# Показывает статус всех портов
_show_ports_status() {
    local PRESET_PORTS=(443 8443 3128 1080)

    echo -e "\n${W}  Статус портов:${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"
    printf "  ${W}%-6s  %-12s  %-16s  %s${NC}\n" "Порт" "Процесс" "Firewall" "Прокси"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"

    # Порты используемых прокси
    local USED_PORTS=()
    local USED_NAMES=()
    mapfile -t _containers < <(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^mtproto-")
    for c in "${_containers[@]}"; do
        local p
        p=$(docker inspect "$c" \
            --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
        if [[ -n "$p" ]]; then
            USED_PORTS+=("$p")
            USED_NAMES+=("${c#mtproto-}")
        fi
    done

    # Объединяем: preset + нестандартные порты прокси
    local ALL_PORTS=("${PRESET_PORTS[@]}")
    for up in "${USED_PORTS[@]}"; do
        local found=0
        for pp in "${PRESET_PORTS[@]}"; do [[ "$up" == "$pp" ]] && found=1 && break; done
        [[ $found -eq 0 ]] && ALL_PORTS+=("$up")
    done

    for port in "${ALL_PORTS[@]}"; do
        local proc_label proc_color fw_label fw_color proxy_label=""

        # Занят процессом?
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            proc_label="занят"; proc_color="${R}"
        else
            proc_label="свободен"; proc_color="${G}"
        fi

        # Firewall статус
        local fw_s; fw_s=$(_port_fw_status "$port")
        case $fw_s in
            open)    fw_label="открыт";      fw_color="${G}" ;;
            closed)  fw_label="закрыт";      fw_color="${R}" ;;
            *)       fw_label="неизвестно";  fw_color="${Y}" ;;
        esac

        # Используется прокси?
        for i in "${!USED_PORTS[@]}"; do
            [[ "${USED_PORTS[$i]}" == "$port" ]] && proxy_label="${USED_NAMES[$i]}" && break
        done

        printf "  ${W}%-6s${NC}  ${proc_color}%-12s${NC}  ${fw_color}%-16s${NC}  ${C}%s${NC}\n" \
            "$port" "$proc_label" "$fw_label" "$proxy_label"
    done
    echo -e "  ${DIM}──────────────────────────────────────${NC}\n"
}

choose_port() {
    _show_ports_status

    echo -e "${C}  Выберите порт:${NC}"
    echo "  1) 443   (рекомендуется — HTTPS)"
    echo "  2) 8443"
    echo "  3) 3128"
    echo "  4) 1080  (SOCKS)"
    echo "  5) Свой порт"
    read -rp "  Выбор [1-5]: " pc

    case $pc in
        1) CHOSEN_PORT=443  ;;
        2) CHOSEN_PORT=8443 ;;
        3) CHOSEN_PORT=3128 ;;
        4) CHOSEN_PORT=1080 ;;
        5)
            read -rp "  Порт: " CHOSEN_PORT
            is_valid_port "$CHOSEN_PORT" || { warn "Некорректный порт, используется 443."; CHOSEN_PORT=443; }
            ;;
        *)
            warn "Неверный выбор, используется 443."
            CHOSEN_PORT=443
            ;;
    esac

    info "Выбран порт: $CHOSEN_PORT"

    # Проверка — занят нашим контейнером?
    local our=0
    local our_name=""
    mapfile -t _running < <(docker ps --format "{{.Names}}" 2>/dev/null | grep "^mtproto-")
    for c in "${_running[@]}"; do
        local cp
        cp=$(docker inspect "$c" \
            --format='{{range $p,$cc := .HostConfig.PortBindings}}{{(index $cc 0).HostPort}}{{end}}' 2>/dev/null)
        if [[ "$cp" == "$CHOSEN_PORT" ]]; then
            our=1
            our_name="${c#mtproto-}"
            break
        fi
    done

    if [[ $our -eq 1 ]]; then
        echo ""
        echo -e "  ${R}╔══════════════════════════════════════════════╗${NC}"
        echo -e "  ${R}║  Порт $CHOSEN_PORT уже занят прокси: $our_name ${NC}"
        echo -e "  ${R}║  Выберите другой порт!                      ${NC}"
        echo -e "  ${R}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        return 1
    fi

    # Занят сторонним процессом?
    if ss -tlnp 2>/dev/null | grep -q ":${CHOSEN_PORT} "; then
        warn "Порт $CHOSEN_PORT занят сторонним процессом!"
        read -rp "  Принудительно использовать? [y/N] " force
        [[ "${force,,}" != "y" ]] && return 1
    fi

    # Firewall — открыть если закрыт
    local fw_s; fw_s=$(_port_fw_status "$CHOSEN_PORT")
    if [[ "$fw_s" == "closed" ]]; then
        warn "Порт $CHOSEN_PORT закрыт в firewall!"
        read -rp "  Открыть автоматически? [Y/n] " fw_open
        if [[ "${fw_open,,}" != "n" ]]; then
            _firewall_open "$CHOSEN_PORT"
        else
            warn "Порт не открыт — клиенты могут не подключиться."
        fi
    elif [[ "$fw_s" == "open" ]]; then
        success "Порт $CHOSEN_PORT уже открыт в firewall."
    fi
}

# ─── СОЗДАНИЕ ПРОКСИ ────────────────────────────────────────

menu_add() {
    banner
    echo -e "${G}═══ СОЗДАНИЕ НОВОГО ПРОКСИ ═══${NC}\n"

    read -rp "Имя клиента (ID/ник, без пробелов): " CLIENT_ID
    CLIENT_ID="${CLIENT_ID//[^a-zA-Z0-9_-]/}"
    [[ -z "$CLIENT_ID" ]] && CLIENT_ID="client-$(date +%s)"

    local CONTAINER_NAME="mtproto-$CLIENT_ID"

    if docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        warn "Контейнер '$CONTAINER_NAME' уже существует!"
        pause; return
    fi

    choose_domain
    choose_port || { pause; return; }

    info "Генерация секрета для домена '$CHOSEN_DOMAIN'..."
    local SECRET
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$CHOSEN_DOMAIN" 2>/dev/null)

    if [[ -z "$SECRET" ]]; then
        die "Не удалось сгенерировать секрет. Проверьте Docker."
    fi

    info "Запуск контейнера на порту $CHOSEN_PORT..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$CHOSEN_PORT:$CHOSEN_PORT" \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        nineseconds/mtg:2 \
        simple-run \
            -n 1.1.1.1 \
            -i prefer-ipv4 \
            0.0.0.0:"$CHOSEN_PORT" "$SECRET" >/dev/null 2>&1

    if ! docker ps --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        die "Контейнер не запустился."
    fi

    # Firewall — автооткрытие порта
    _firewall_open "$CHOSEN_PORT"

    echo "$CONTAINER_NAME|$CLIENT_ID|$CHOSEN_PORT|$SECRET|$CHOSEN_DOMAIN|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_FILE"
    log "Создан прокси: $CONTAINER_NAME, порт=$CHOSEN_PORT, домен=$CHOSEN_DOMAIN"

    local IP
    IP=$(get_public_ip)
    local LINK="tg://proxy?server=$IP&port=$CHOSEN_PORT&secret=$SECRET"
    local HTTPS_LINK="https://t.me/proxy?server=$IP&port=$CHOSEN_PORT&secret=$SECRET"

    clear
    echo -e "${G}╔══════════════════════════════════════════╗${NC}"
    echo -e "${G}║      Прокси успешно создан!             ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════╝${NC}\n"
    echo -e "  ${C}Клиент:${NC}  $CLIENT_ID"
    echo -e "  ${C}Домен:${NC}   $CHOSEN_DOMAIN (Fake TLS)"
    echo -e "  ${C}IP:${NC}      $IP"
    echo -e "  ${C}Порт:${NC}    $CHOSEN_PORT"
    echo -e "  ${C}Secret:${NC}  $SECRET"
    echo -e "\n  ${B}tg:// ссылка:${NC}\n  $LINK"
    echo -e "\n  ${B}HTTPS ссылка:${NC}\n  $HTTPS_LINK"
    echo -e "\n  ${Y}QR-код (tg://):${NC}"
    qrencode -t ANSIUTF8 "$LINK"

    pause
}

# ─── FIREWALL ПОМОЩНИК ──────────────────────────────────────

_firewall_open() {
    local port="$1"
    is_valid_port "$port" || { warn "Некорректный порт firewall: $port"; return 1; }
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw status 2>/dev/null | grep -qE "^${port}[/ ].*ALLOW" || ufw allow "$port"/tcp >/dev/null 2>&1
        success "UFW: порт $port открыт."
        log "UFW: открыт порт $port"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp" || {
            firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        }
        success "firewalld: порт $port открыт."
        log "firewalld: открыт порт $port"
    elif command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        success "iptables: порт $port открыт."
        log "iptables: открыт порт $port"
    fi
}

_firewall_close() {
    local port="$1"
    is_valid_port "$port" || { warn "Некорректный порт firewall: $port"; return 1; }
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw delete allow "$port"/tcp >/dev/null 2>&1
        log "UFW: закрыт порт $port"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-port="$port"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        log "firewalld: закрыт порт $port"
    elif command -v iptables &>/dev/null; then
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        log "iptables: закрыт порт $port"
    fi
}

firewall_menu() {
    banner
    echo -e "${C}═══ FIREWALL УПРАВЛЕНИЕ ═══${NC}\n"

    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")
    if [[ ${#containers[@]} -eq 0 ]]; then
        warn "Прокси не найдены."; pause; return
    fi

    echo -e "  1) Открыть порт прокси в firewall"
    echo -e "  2) Закрыть порт прокси в firewall"
    echo -e "  3) Показать статус firewall\n"
    read -rp "Выбор: " fc

    case $fc in
        1|2)
            for i in "${!containers[@]}"; do
                echo -e "  ${Y}$((i+1)))${NC} ${containers[$i]}"
            done
            read -rp "Номер: " IDX
            is_valid_index "$IDX" "${#containers[@]}" || { warn "Неверный выбор."; pause; return; }
            local CONTAINER="${containers[$((IDX-1))]}"
            local PORT
            PORT=$(docker inspect "$CONTAINER" \
                --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
            if [[ $fc -eq 1 ]]; then
                _firewall_open "$PORT"
            else
                _firewall_close "$PORT"
            fi
            ;;
        3)
            if command -v ufw &>/dev/null; then ufw status numbered
            elif command -v firewall-cmd &>/dev/null; then firewall-cmd --list-all
            else iptables -L INPUT -n --line-numbers
            fi
            ;;
    esac
    pause
}

# ─── СПИСОК ПРОКСИ ──────────────────────────────────────────

show_list() {
    banner
    echo -e "${G}═══ СПИСОК ПРОКСИ ═══${NC}\n"

    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")

    if [[ ${#containers[@]} -eq 0 ]]; then
        warn "Прокси не найдены."
        pause; return
    fi

    local IP
    IP=$(get_public_ip)

    for CONTAINER in "${containers[@]}"; do
        local STATUS
        STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
        local COLOR="${R}"
        [[ "$STATUS" == "running" ]] && COLOR="${G}"

        local PORT
        PORT=$(docker inspect "$CONTAINER" \
            --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)

        local CMD
        CMD=$(docker inspect "$CONTAINER" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
        local SECRET
        SECRET=$(echo "$CMD" | awk '{print $NF}')

        local DOMAIN="—"
        grep -q "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null && \
            DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" | cut -d'|' -f5)

        local CREATED
        CREATED=$(docker inspect --format='{{.Created}}' "$CONTAINER" 2>/dev/null | cut -dT -f1)

        local LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

        echo -e "${W}┌─ $CONTAINER${NC}  [${COLOR}${STATUS}${NC}]  создан: $CREATED"
        echo -e "${W}│${NC}  Домен: ${C}$DOMAIN${NC}  |  IP: $IP  |  Порт: ${Y}$PORT${NC}"
        echo -e "${W}│${NC}  Secret: ${DIM}$SECRET${NC}"
        echo -e "${W}│${NC}  Link:   ${B}$LINK${NC}"
        echo -e "${W}└──────────────────────────────────────────${NC}\n"
    done

    pause
}

# ─── ДЕТАЛЬНЫЙ ПРОСМОТР ─────────────────────────────────────

show_detail() {
    banner
    read -rp "ID клиента: " CLIENT_ID
    CLIENT_ID="${CLIENT_ID//[^a-zA-Z0-9_-]/}"
    local CONTAINER="mtproto-$CLIENT_ID"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER$"; then
        warn "Контейнер '$CONTAINER' не найден."
        pause; return
    fi

    local IP STATUS PORT CMD SECRET DOMAIN CREATED
    IP=$(get_public_ip)
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER")
    PORT=$(docker inspect "$CONTAINER" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}')
    CMD=$(docker inspect "$CONTAINER" --format='{{join .Config.Cmd " "}}')
    SECRET=$(echo "$CMD" | awk '{print $NF}')
    DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "—")
    CREATED=$(docker inspect --format='{{.Created}}' "$CONTAINER" | cut -dT -f1)

    local LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
    local HTTPS_LINK="https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"

    clear
    echo -e "\n${W}Контейнер:${NC}  $CONTAINER"
    echo -e "${W}Статус:${NC}     $STATUS"
    echo -e "${W}Создан:${NC}     $CREATED"
    echo -e "${W}Домен:${NC}      $DOMAIN"
    echo -e "${W}IP:${NC}         $IP"
    echo -e "${W}Порт:${NC}       $PORT"
    echo -e "${W}Secret:${NC}     $SECRET"
    echo -e "\n${B}tg://  ${NC} $LINK"
    echo -e "${B}HTTPS  ${NC} $HTTPS_LINK"
    echo -e "\n${Y}QR (tg://):${NC}"
    qrencode -t ANSIUTF8 "$LINK"
    echo -e "\n${Y}QR (HTTPS):${NC}"
    qrencode -t ANSIUTF8 "$HTTPS_LINK"
    echo -e "\n${C}--- Логи (последние 30 строк) ---${NC}"
    docker logs --tail=30 "$CONTAINER" 2>&1

    pause
}

# ─── ОБНОВЛЕНИЕ СЕКРЕТА ─────────────────────────────────────

rotate_secret() {
    banner
    echo -e "${Y}═══ ОБНОВЛЕНИЕ СЕКРЕТА ═══${NC}"
    warn "Все текущие соединения будут разорваны."
    echo ""
    read -rp "ID клиента: " CLIENT_ID
    CLIENT_ID="${CLIENT_ID//[^a-zA-Z0-9_-]/}"
    local CONTAINER="mtproto-$CLIENT_ID"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER$"; then
        warn "Контейнер '$CONTAINER' не найден."; pause; return
    fi

    local PORT DOMAIN
    PORT=$(docker inspect "$CONTAINER" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}')
    DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "google.com")

    local BFILE
    BFILE="$BACKUP_DIR/${CONTAINER}_$(date +%Y%m%d_%H%M%S).bak"
    grep "^$CONTAINER|" "$CONFIG_FILE" > "$BFILE" 2>/dev/null
    success "Резервная копия: $BFILE"

    info "Генерация нового секрета..."
    local NEW_SECRET
    NEW_SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN" 2>/dev/null)
    if [[ -z "$NEW_SECRET" ]]; then
        warn "Не удалось сгенерировать новый секрет. Старый контейнер не тронут."
        pause; return
    fi

    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm "$CONTAINER" >/dev/null 2>&1

    docker run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        -p "$PORT:$PORT" \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        nineseconds/mtg:2 \
        simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$NEW_SECRET" >/dev/null 2>&1

    if ! docker ps --format "{{.Names}}" | grep -q "^$CONTAINER$"; then
        warn "Новый контейнер не запустился. Бэкап записи: $BFILE"
        local OLD_SECRET
        OLD_SECRET=$(cut -d'|' -f4 "$BFILE" 2>/dev/null)
        if [[ -n "$OLD_SECRET" ]]; then
            warn "Пробую восстановить старый контейнер..."
            docker rm "$CONTAINER" >/dev/null 2>&1 || true
            docker run -d \
                --name "$CONTAINER" \
                --restart unless-stopped \
                -p "$PORT:$PORT" \
                --log-opt max-size=10m \
                --log-opt max-file=3 \
                nineseconds/mtg:2 \
                simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$OLD_SECRET" >/dev/null 2>&1
        fi
        pause; return
    fi

    sed -i "/^$CONTAINER|/d" "$CONFIG_FILE"
    echo "$CONTAINER|$CLIENT_ID|$PORT|$NEW_SECRET|$DOMAIN|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_FILE"
    log "Секрет обновлён: $CONTAINER"

    local IP
    IP=$(get_public_ip)
    local LINK="tg://proxy?server=$IP&port=$PORT&secret=$NEW_SECRET"

    success "Секрет обновлён!"
    echo -e "\n${B}Новая ссылка:${NC} $LINK"
    echo -e "\n${Y}QR-код:${NC}"
    qrencode -t ANSIUTF8 "$LINK"

    pause
}

# ─── СТАТУС / ТРАФИК ────────────────────────────────────────

show_status() {
    banner
    echo -e "${C}═══ СТАТУС КОНТЕЙНЕРОВ ═══${NC}\n"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Image}}" \
        | grep -E "NAMES|mtproto-"
    echo ""
    echo -e "${C}═══ СТАТИСТИКА ПОДКЛЮЧЕНИЙ ═══${NC}\n"
    _show_connections
    echo ""
    echo -e "${C}═══ СЕТЕВОЙ ТРАФИК ═══${NC}\n"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
        | grep -E "NAME|mtproto-"
    pause
}

# ─── СТАТИСТИКА ПОДКЛЮЧЕНИЙ (mtg metrics) ───────────────────

_show_connections() {
    mapfile -t containers < <(docker ps --format "{{.Names}}" | grep "^mtproto-")
    if [[ ${#containers[@]} -eq 0 ]]; then
        echo -e "  ${DIM}Нет активных прокси.${NC}"
        return
    fi

    for CONTAINER in "${containers[@]}"; do
        local PORT
        PORT=$(docker inspect "$CONTAINER" \
            --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)

        # mtg отдаёт метрики на порту 3129 (если включён)
        local METRICS_PORT=$((PORT + 100))
        local CONNS
        CONNS=$(curl -s --max-time 2 "http://127.0.0.1:$METRICS_PORT/metrics" 2>/dev/null \
            | grep "mtg_connections_total" | awk '{print $2}' | head -1)

        if [[ -n "$CONNS" ]]; then
            echo -e "  ${W}$CONTAINER${NC}: ${G}$CONNS${NC} соединений всего"
        else
            # Fallback — считаем через ss
            local ACTIVE
            ACTIVE=$(ss -tn | grep -c ":$PORT .*ESTAB" || echo 0)
            echo -e "  ${W}$CONTAINER${NC}: ${G}$ACTIVE${NC} активных соединений (ESTAB)"
        fi
    done
}

# ─── УПРАВЛЕНИЕ ─────────────────────────────────────────────

manage_proxy() {
    banner
    echo -e "${C}Управление (start/stop/restart):${NC}"
    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")
    [[ ${#containers[@]} -eq 0 ]] && { warn "Прокси не найдены."; pause; return; }

    for i in "${!containers[@]}"; do
        local s
        s=$(docker inspect --format='{{.State.Status}}' "${containers[$i]}")
        local col="${R}"
        [[ "$s" == "running" ]] && col="${G}"
        echo -e "  ${Y}$((i+1)))${NC} ${containers[$i]} [${col}${s}${NC}]"
    done

    echo ""
    read -rp "Номер контейнера: " IDX
    is_valid_index "$IDX" "${#containers[@]}" || { warn "Неверный выбор."; pause; return; }
    local CONTAINER="${containers[$((IDX-1))]}"
    [[ -z "$CONTAINER" ]] && { warn "Неверный выбор."; pause; return; }

    echo -e "\n  1) Start   2) Stop   3) Restart"
    read -rp "Действие: " ACT
    case $ACT in
        1) docker start "$CONTAINER" >/dev/null && success "Запущен: $CONTAINER" ;;
        2) docker stop "$CONTAINER" >/dev/null && success "Остановлен: $CONTAINER" ;;
        3) docker restart "$CONTAINER" >/dev/null && success "Перезапущен: $CONTAINER" ;;
        *) warn "Неверный выбор." ;;
    esac
    log "Управление: $ACT -> $CONTAINER"
    pause
}

# ─── УДАЛЕНИЕ ───────────────────────────────────────────────

delete_proxy() {
    banner
    echo -e "${R}═══ УДАЛЕНИЕ ПРОКСИ ═══${NC}\n"

    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")
    [[ ${#containers[@]} -eq 0 ]] && { warn "Прокси не найдены."; pause; return; }

    for i in "${!containers[@]}"; do
        echo -e "  ${Y}$((i+1)))${NC} ${containers[$i]}"
    done

    echo ""
    read -rp "Номер для удаления (0 — отмена): " IDX
    [[ "$IDX" == "0" ]] && return
    is_valid_index "$IDX" "${#containers[@]}" || { warn "Неверный выбор."; pause; return; }

    local CONTAINER="${containers[$((IDX-1))]}"
    [[ -z "$CONTAINER" ]] && { warn "Неверный выбор."; pause; return; }

    read -rp "Удалить '$CONTAINER'? [y/N] " confirm
    [[ "${confirm,,}" != "y" ]] && return

    local PORT
    PORT=$(docker inspect "$CONTAINER" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)

    mkdir -p "$BACKUP_DIR"
    grep "^$CONTAINER|" "$CONFIG_FILE" > "$BACKUP_DIR/${CONTAINER}_deleted_$(date +%Y%m%d_%H%M%S).bak" 2>/dev/null

    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm "$CONTAINER" >/dev/null 2>&1
    sed -i "/^$CONTAINER|/d" "$CONFIG_FILE"

    # Закрыть порт в firewall
    read -rp "Закрыть порт $PORT в firewall? [y/N] " fw
    [[ "${fw,,}" == "y" ]] && _firewall_close "$PORT"

    success "Удалён: $CONTAINER"
    log "Удалён: $CONTAINER"
    pause
}

# ─── ЭКСПОРТ ВСЕХ ССЫЛОК ────────────────────────────────────

export_links() {
    banner
    echo -e "${C}═══ ЭКСПОРТ ССЫЛОК ═══${NC}\n"

    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")
    if [[ ${#containers[@]} -eq 0 ]]; then
        warn "Прокси не найдены."; pause; return
    fi

    local IP
    IP=$(get_public_ip)

    {
        echo "# MTProxy Links Export — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# IP: $IP"
        echo ""
    } > "$EXPORT_FILE"
    secure_file "$EXPORT_FILE"

    for CONTAINER in "${containers[@]}"; do
        local PORT CMD SECRET DOMAIN STATUS
        STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
        PORT=$(docker inspect "$CONTAINER" \
            --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
        CMD=$(docker inspect "$CONTAINER" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
        SECRET=$(echo "$CMD" | awk '{print $NF}')
        DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "—")

        local LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
        local HTTPS_LINK="https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"

        {
            echo "## $CONTAINER  [$STATUS]"
            echo "Домен: $DOMAIN | Порт: $PORT"
            echo "tg://   $LINK"
            echo "HTTPS:  $HTTPS_LINK"
            echo ""
        } >> "$EXPORT_FILE"

        echo -e "${W}$CONTAINER${NC} [${STATUS}]"
        echo -e "  ${B}$LINK${NC}"
    done

    echo ""
    success "Сохранено в: $EXPORT_FILE"
    echo -e "\n${DIM}Содержимое файла:${NC}"
    cat "$EXPORT_FILE"
    pause
}

# ─── ИМПОРТ / МИГРАЦИЯ ──────────────────────────────────────

migrate_export() {
    banner
    echo -e "${Y}═══ ЭКСПОРТ ДЛЯ МИГРАЦИИ ═══${NC}\n"
    warn "Этот файл содержит все настройки. Скопируй его на новый сервер."

    local MIGRATION_FILE
    MIGRATION_FILE="$CONFIG_DIR/migration_$(date +%Y%m%d_%H%M%S).sh"
    local IP
    IP=$(get_public_ip)

    {
        echo "#!/bin/bash"
        echo "# MTProxy Migration Script — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Экспортировано с сервера: $IP"
        echo ""
        echo "# Запусти этот скрипт на новом сервере от root"
        echo ""
    } > "$MIGRATION_FILE"

    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")

    for CONTAINER in "${containers[@]}"; do
        local PORT CMD SECRET DOMAIN
        PORT=$(docker inspect "$CONTAINER" \
            --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
        CMD=$(docker inspect "$CONTAINER" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
        SECRET=$(echo "$CMD" | awk '{print $NF}')
        DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "google.com")
        local CLIENT_ID="${CONTAINER#mtproto-}"

        {
            echo "# $CONTAINER"
            echo "docker run -d \\"
            echo "    --name \"$CONTAINER\" \\"
            echo "    --restart unless-stopped \\"
            echo "    -p $PORT:$PORT \\"
            echo "    --log-opt max-size=10m \\"
            echo "    --log-opt max-file=3 \\"
            echo "    nineseconds/mtg:2 \\"
            echo "    simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:$PORT \"$SECRET\""
            echo "echo \"$CONTAINER|$CLIENT_ID|$PORT|$SECRET|$DOMAIN|migrated-$(date '+%Y-%m-%d')\" >> /etc/mtproxy/proxies.conf"
            echo ""
        } >> "$MIGRATION_FILE"
    done

    chmod 700 "$MIGRATION_FILE"
    success "Скрипт миграции: $MIGRATION_FILE"
    echo -e "\n${C}Скопируй файл на новый сервер:${NC}"
    echo -e "  scp $MIGRATION_FILE root@НОВЫЙ_IP:/root/"
    echo -e "  ssh root@НОВЫЙ_IP 'bash /root/$(basename "$MIGRATION_FILE")'"
    pause
}

# ─── HEALTHCHECK (CRON) ─────────────────────────────────────

setup_healthcheck() {
    banner
    echo -e "${C}═══ HEALTHCHECK / АВТОПЕРЕЗАПУСК ═══${NC}\n"
    echo "Cron-задача будет проверять все прокси каждые 5 минут"
    echo "и перезапускать упавшие контейнеры автоматически."
    echo ""
    echo "  1) Включить healthcheck"
    echo "  2) Отключить healthcheck"
    echo "  3) Показать статус"
    read -rp "Выбор: " hc

    case $hc in
        1)
            # Создаём скрипт healthcheck
            cat > /etc/mtproxy/healthcheck.sh << 'HCEOF'
#!/bin/bash
LOG="/var/log/mtproxy.log"
for CONTAINER in $(docker ps -a --format "{{.Names}}" | grep "^mtproto-"); do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    if [[ "$STATUS" != "running" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $CONTAINER упал ($STATUS), перезапуск..." >> "$LOG"
        docker start "$CONTAINER" >/dev/null 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $CONTAINER перезапущен." >> "$LOG"
    fi
done
HCEOF
            chmod 700 /etc/mtproxy/healthcheck.sh

            # Добавляем в cron (убираем дубликаты)
            crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab -
            (crontab -l 2>/dev/null; echo "*/5 * * * * /etc/mtproxy/healthcheck.sh $CRON_TAG") | crontab -

            success "Healthcheck включён (каждые 5 минут)."
            log "Healthcheck включён"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab -
            success "Healthcheck отключён."
            log "Healthcheck отключён"
            ;;
        3)
            echo -e "\n${C}Текущие cron-задачи:${NC}"
            crontab -l 2>/dev/null | grep "$CRON_TAG" || echo "  Healthcheck не настроен."
            ;;
    esac
    pause
}

# ─── АВТО-ROTATE СЕКРЕТА ────────────────────────────────────

setup_auto_rotate() {
    banner
    echo -e "${C}═══ АВТО-ОБНОВЛЕНИЕ СЕКРЕТА ═══${NC}\n"
    echo "Автоматически обновлять секреты всех прокси по расписанию."
    echo ""
    echo "  1) Каждую неделю (воскресенье 03:00)"
    echo "  2) Каждый месяц (1-е число 03:00)"
    echo "  3) Отключить авто-rotate"
    echo "  4) Показать статус"
    read -rp "Выбор: " ar

    case $ar in
        1|2)
            # Создаём скрипт авто-rotate
            cat > /etc/mtproxy/auto_rotate.sh << 'AREOF'
#!/bin/bash
LOG="/var/log/mtproxy.log"
CONFIG="/etc/mtproxy/proxies.conf"
BACKUP="/etc/mtproxy/backups"
mkdir -p "$BACKUP"

for CONTAINER in $(docker ps -a --format "{{.Names}}" | grep "^mtproto-"); do
    PORT=$(docker inspect "$CONTAINER" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
    DOMAIN=$(grep "^$CONTAINER|" "$CONFIG" 2>/dev/null | cut -d'|' -f5 || echo "google.com")
    CLIENT_ID=$(grep "^$CONTAINER|" "$CONFIG" 2>/dev/null | cut -d'|' -f2 || echo "unknown")

    grep "^$CONTAINER|" "$CONFIG" > "$BACKUP/${CONTAINER}_autorotate_$(date +%Y%m%d).bak" 2>/dev/null

    NEW_SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN" 2>/dev/null)
    if [[ -z "$NEW_SECRET" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO-ROTATE ERROR: $CONTAINER — не удалось получить секрет" >> "$LOG"
        continue
    fi

    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm "$CONTAINER" >/dev/null 2>&1

    docker run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        -p "$PORT:$PORT" \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        nineseconds/mtg:2 \
        simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$NEW_SECRET" >/dev/null 2>&1

    sed -i "/^$CONTAINER|/d" "$CONFIG"
    echo "$CONTAINER|$CLIENT_ID|$PORT|$NEW_SECRET|$DOMAIN|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO-ROTATE OK: $CONTAINER, новый секрет: $NEW_SECRET" >> "$LOG"
done
AREOF
            chmod 700 /etc/mtproxy/auto_rotate.sh

            # Убираем старый cron авто-rotate
            crontab -l 2>/dev/null | grep -v "auto_rotate" | crontab -

            if [[ $ar -eq 1 ]]; then
                (crontab -l 2>/dev/null; echo "0 3 * * 0 /etc/mtproxy/auto_rotate.sh # mtproxy-rotate") | crontab -
                success "Авто-rotate: каждое воскресенье в 03:00"
            else
                (crontab -l 2>/dev/null; echo "0 3 1 * * /etc/mtproxy/auto_rotate.sh # mtproxy-rotate") | crontab -
                success "Авто-rotate: каждое 1-е число месяца в 03:00"
            fi
            log "Авто-rotate настроен (вариант $ar)"
            ;;
        3)
            crontab -l 2>/dev/null | grep -v "auto_rotate" | crontab -
            success "Авто-rotate отключён."
            ;;
        4)
            echo -e "\n${C}Текущие задачи rotate:${NC}"
            crontab -l 2>/dev/null | grep "auto_rotate" || echo "  Авто-rotate не настроен."
            ;;
    esac
    pause
}

# ─── УВЕДОМЛЕНИЯ В TELEGRAM ─────────────────────────────────

setup_tg_notify() {
    banner
    echo -e "${C}═══ УВЕДОМЛЕНИЯ В TELEGRAM ═══${NC}\n"
    echo "Бот будет писать тебе когда прокси упал или перезапустился."
    echo ""
    echo "  1) Настроить уведомления"
    echo "  2) Тест уведомления"
    echo "  3) Отключить уведомления"
    read -rp "Выбор: " tn

    local NOTIFY_CONF="$CONFIG_DIR/notify.conf"

    case $tn in
        1)
            echo ""
            echo -e "${C}Создай бота через @BotFather и получи токен.${NC}"
            echo -e "${C}Свой chat_id узнай через @userinfobot.${NC}\n"
            read -rp "Bot Token: " BOT_TOKEN
            read -rp "Chat ID:   " CHAT_ID
            BOT_TOKEN="${BOT_TOKEN//[^a-zA-Z0-9:_-]/}"
            CHAT_ID="${CHAT_ID//[^0-9-]/}"

            echo "BOT_TOKEN=$BOT_TOKEN" > "$NOTIFY_CONF"
            echo "CHAT_ID=$CHAT_ID" >> "$NOTIFY_CONF"
            chmod 600 "$NOTIFY_CONF"

            # Патчим healthcheck чтобы слал уведомления
            cat > /etc/mtproxy/healthcheck.sh << 'HCEOF'
#!/bin/bash
LOG="/var/log/mtproxy.log"
NOTIFY_CONF="/etc/mtproxy/notify.conf"

_tg_send() {
    [[ ! -f "$NOTIFY_CONF" ]] && return
    source "$NOTIFY_CONF"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$1" \
        -d parse_mode="HTML" >/dev/null 2>&1
}

HOSTNAME=$(hostname)
for CONTAINER in $(docker ps -a --format "{{.Names}}" | grep "^mtproto-"); do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    if [[ "$STATUS" != "running" ]]; then
        MSG="🔴 <b>MTProxy упал!</b>%0AСервер: $HOSTNAME%0AКонтейнер: $CONTAINER%0AСтатус: $STATUS%0AВремя: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $CONTAINER упал, перезапуск..." >> "$LOG"
        docker start "$CONTAINER" >/dev/null 2>&1
        sleep 3
        NEW_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
        if [[ "$NEW_STATUS" == "running" ]]; then
            MSG2="🟢 <b>MTProxy восстановлен!</b>%0AСервер: $HOSTNAME%0AКонтейнер: $CONTAINER%0AВремя: $(date '+%Y-%m-%d %H:%M:%S')"
            _tg_send "$MSG"
            _tg_send "$MSG2"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $CONTAINER перезапущен." >> "$LOG"
        else
            MSG3="❌ <b>MTProxy НЕ запустился!</b>%0AСервер: $HOSTNAME%0AКонтейнер: $CONTAINER%0AПроверь сервер вручную!"
            _tg_send "$MSG"
            _tg_send "$MSG3"
        fi
    fi
done
HCEOF
            chmod 700 /etc/mtproxy/healthcheck.sh

            # Добавляем healthcheck в cron если ещё нет
            if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
                (crontab -l 2>/dev/null; echo "*/5 * * * * /etc/mtproxy/healthcheck.sh $CRON_TAG") | crontab -
            fi

            success "Уведомления настроены! Healthcheck активен."
            log "TG уведомления настроены для chat_id=$CHAT_ID"
            ;;
        2)
            if [[ ! -f "$NOTIFY_CONF" ]]; then
                warn "Сначала настрой уведомления (пункт 1)."; pause; return
            fi
            # shellcheck source=/dev/null
            source "$NOTIFY_CONF"
            RESULT=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
                -d chat_id="$CHAT_ID" \
                -d text="✅ <b>MTProxy тест!</b>%0AУведомления работают. Сервер: $(hostname)" \
                -d parse_mode="HTML")
            if echo "$RESULT" | grep -q '"ok":true'; then
                success "Тестовое сообщение отправлено!"
            else
                warn "Ошибка! Проверь токен и chat_id."
                echo "$RESULT"
            fi
            ;;
        3)
            rm -f "$NOTIFY_CONF"
            success "Уведомления отключены."
            ;;
    esac
    pause
}

# ─── АВТО-ОБНОВЛЕНИЕ СКРИПТА ────────────────────────────────

self_update() {
    banner
    echo -e "${C}═══ ОБНОВЛЕНИЕ СКРИПТА ═══${NC}\n"
    info "Проверяю обновления на GitHub..."

    local TMP
    TMP=$(mktemp /tmp/mtproxy_update.XXXXXX)
    curl -fsSL "$GITHUB_RAW" -o "$TMP" 2>/dev/null

    if [[ ! -f "$TMP" || ! -s "$TMP" ]]; then
        warn "Не удалось загрузить обновление. Проверь интернет-соединение."
        pause; return
    fi

    local NEW_VER
    NEW_VER=$(grep '^VERSION=' "$TMP" | cut -d'"' -f2)

    if [[ -z "$NEW_VER" ]]; then
        warn "Не удалось определить версию. Файл повреждён?"
        rm -f "$TMP"; pause; return
    fi

    if ! bash -n "$TMP" 2>/dev/null; then
        warn "Загруженный файл не проходит bash -n. Обновление отменено."
        rm -f "$TMP"; pause; return
    fi

    echo -e "  Текущая версия: ${Y}$VERSION${NC}"
    echo -e "  Новая версия:   ${G}$NEW_VER${NC}\n"

    if [[ "$NEW_VER" == "$VERSION" ]]; then
        success "У тебя уже последняя версия!"
        rm -f "$TMP"; pause; return
    fi

    read -rp "Обновить до v$NEW_VER? [y/N] " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        warn "Отменено."; rm -f "$TMP"; pause; return
    fi

    # Бэкап текущей версии
    cp "$BINARY_PATH" "$BACKUP_DIR/mtproxy_v${VERSION}_$(date +%Y%m%d).bak" 2>/dev/null

    cp "$TMP" "$BINARY_PATH"
    chmod 755 "$BINARY_PATH"
    rm -f "$TMP"

    success "Обновлено до v$NEW_VER! Перезапусти скрипт: mtproxy"
    log "Обновление: v$VERSION -> v$NEW_VER"
    exit 0
}

# ─── ЛОГ СКРИПТА ────────────────────────────────────────────

show_log() {
    banner
    echo -e "${C}Лог скрипта (последние 50 строк):${NC}\n"
    tail -50 "$LOG_FILE" 2>/dev/null || warn "Лог пуст."
    pause
}

# ─── ПОЛНОЕ УДАЛЕНИЕ ────────────────────────────────────────

full_uninstall() {
    banner
    echo -e "${R}╔══════════════════════════════════════╗${NC}"
    echo -e "${R}║       ПОЛНОЕ УДАЛЕНИЕ MTPROXY        ║${NC}"
    echo -e "${R}╚══════════════════════════════════════╝${NC}\n"
    warn "Будут удалены ВСЕ прокси-контейнеры и сам скрипт."
    read -rp "Подтвердите: напишите DELETE: " confirm
    [[ "$confirm" != "DELETE" ]] && { warn "Отменено."; pause; return; }

    local ids
    ids=$(docker ps -aq --filter "name=mtproto-")
    if [[ -n "$ids" ]]; then
        # shellcheck disable=SC2086
        docker stop $ids >/dev/null 2>&1
        # shellcheck disable=SC2086
        docker rm $ids >/dev/null 2>&1
    fi

    crontab -l 2>/dev/null | grep -v "$CRON_TAG" | grep -v "auto_rotate" | crontab -
    rm -f "$BINARY_PATH"

    success "Скрипт удалён. Конфиги и бэкапы сохранены в $CONFIG_DIR"
    log "Полное удаление выполнено."
    exit 0
}


# ═══════════════════════════════════════════════════════════
# ─── XRAY SOCKS5 (WhatsApp / универсальный прокси) ─────────
# ═══════════════════════════════════════════════════════════

xray_install() {
    banner
    echo -e "${G}═══ УСТАНОВКА XRAY SOCKS5 ═══${NC}
"
    echo "Xray SOCKS5 — универсальный прокси для WhatsApp, Instagram,"
    echo "браузера и любых других приложений."
    echo ""

    local XRAY_PORT XRAY_HTTP_PORT xp xa

    if docker ps -a --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        warn "Xray уже установлен!"
        echo -e "  Используй меню Xray для управления существующим экземпляром."
        pause; return
    fi

    # Выбор порта
    echo -e "${C}Выберите порт для Xray SOCKS5:${NC}"
    echo "  1) 1080 (стандартный SOCKS5)"
    echo "  2) 3129"
    echo "  3) 8080"
    echo "  4) Свой порт"
    read -rp "  Выбор [1-4]: " xp
    case $xp in
        1) XRAY_PORT=1080 ;;
        2) XRAY_PORT=3129 ;;
        3) XRAY_PORT=8080 ;;
        4) read -rp "  Порт: " XRAY_PORT
           is_valid_port "$XRAY_PORT" || XRAY_PORT=1080 ;;
        *) XRAY_PORT=1080 ;;
    esac
    info "Выбран порт: $XRAY_PORT"
    # HTTP прокси будет на следующем порту (для WhatsApp)
    XRAY_HTTP_PORT=$((XRAY_PORT + 1))

    # Проверяем что порты не заняты
    for check_port in "$XRAY_PORT" "$XRAY_HTTP_PORT"; do
        if ss -tlnp 2>/dev/null | grep -q ":${check_port} "; then
            warn "Порт $check_port уже занят другим процессом!"
            read -rp "  Принудительно использовать? [y/N] " force
            [[ "${force,,}" != "y" ]] && { pause; return; }
        fi
    done

    # Проверяем что HTTP порт не совпадает с существующим MTProxy
    mapfile -t _existing < <(docker ps --format "{{.Names}}" | grep "^mtproto-")
    for _c in "${_existing[@]}"; do
        local _cp
        _cp=$(docker inspect "$_c"             --format='{{range $p,$cc := .HostConfig.PortBindings}}{{(index $cc 0).HostPort}}{{end}}' 2>/dev/null)
        if [[ "$_cp" == "$XRAY_HTTP_PORT" ]]; then
            warn "HTTP порт $XRAY_HTTP_PORT занят MTProxy контейнером $_c!"
            warn "Выбери другой SOCKS5 порт (HTTP будет на SOCKS5+1)"
            pause; return
        fi
    done
    info "HTTP прокси (WhatsApp): порт $XRAY_HTTP_PORT"

    # Авторизация
    echo -e "\n${C}Защита паролем:${NC}"
    echo "  1) С логином и паролем (рекомендуется)"
    echo "  2) Без пароля (опасно: публичный open proxy)"
    read -rp "  Выбор [1-2]: " xa

    local XRAY_USER="" XRAY_PASS="" XRAY_AUTH_TYPE="password"
    if [[ "$xa" == "2" ]]; then
        warn "Открытый SOCKS5/HTTP прокси будет доступен всем, кто найдёт порт."
        read -rp "  Напиши OPEN чтобы подтвердить: " open_confirm
        if [[ "$open_confirm" == "OPEN" ]]; then
            XRAY_AUTH_TYPE="noauth"
            info "Открытый доступ (без пароля)"
        else
            warn "Подтверждение не введено, включаю пароль."
            xa="1"
        fi
    fi

    if [[ "$XRAY_AUTH_TYPE" == "password" ]]; then
        read -rp "  Логин [proxy]: " XRAY_USER
        XRAY_USER="${XRAY_USER:-proxy}"
        XRAY_USER="${XRAY_USER//[^a-zA-Z0-9_.-]/}"
        XRAY_USER="${XRAY_USER:-proxy}"
        read -rsp "  Пароль (Enter = сгенерировать): " XRAY_PASS
        echo ""
        XRAY_PASS="${XRAY_PASS//[^a-zA-Z0-9_.-]/}"
        [[ -z "$XRAY_PASS" ]] && XRAY_PASS="$(random_password)"
        XRAY_AUTH_TYPE="password"
        info "Авторизация включена: $XRAY_USER"
    fi

    # Генерируем конфиг раздельно чтобы не было проблем с кавычками в JSON
    mkdir -p "$XRAY_DIR"
    if [[ "$XRAY_AUTH_TYPE" == "password" ]]; then
        cat > "$XRAY_DIR/config.json" << XCONF
{
  "log": {"loglevel": "warning"},
  "dns": {"servers": ["8.8.8.8", "1.1.1.1", "8.8.4.4"]},
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "tag": "socks-in",
      "settings": {
        "auth": "password",
        "accounts": [{"user": "$XRAY_USER", "pass": "$XRAY_PASS"}],
        "udp": true,
        "ip": "0.0.0.0"
      }
    },
    {
      "port": $XRAY_HTTP_PORT,
      "listen": "0.0.0.0",
      "protocol": "http",
      "tag": "http-in",
      "settings": {
        "accounts": [{"user": "$XRAY_USER", "pass": "$XRAY_PASS"}],
        "allowTransparent": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIP"}
    }
  ]
}
XCONF
    else
        cat > "$XRAY_DIR/config.json" << XCONF
{
  "log": {"loglevel": "warning"},
  "dns": {"servers": ["8.8.8.8", "1.1.1.1", "8.8.4.4"]},
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "tag": "socks-in",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "0.0.0.0"
      }
    },
    {
      "port": $XRAY_HTTP_PORT,
      "listen": "0.0.0.0",
      "protocol": "http",
      "tag": "http-in",
      "settings": {
        "allowTransparent": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIP"}
    }
  ]
}
XCONF
    fi
    secure_file "$XRAY_DIR/config.json"

    # Проверяем JSON
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import json; json.load(open('$XRAY_DIR/config.json'))" 2>/dev/null; then
            warn "Ошибка в конфиге! Содержимое:"
            cat "$XRAY_DIR/config.json"
            die "Конфиг невалидный."
        fi
        success "Конфиг Xray валидный."
    fi

    info "Загрузка образа Xray..."

    # Пробуем основной образ, при неудаче — fallback
    local XRAY_IMAGE=""
    if docker pull ghcr.io/xtls/xray-core:latest >/dev/null 2>&1; then
        XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"
        success "Образ загружен: $XRAY_IMAGE"
    elif docker pull teddysun/xray >/dev/null 2>&1; then
        XRAY_IMAGE="teddysun/xray"
        success "Образ загружен: $XRAY_IMAGE"
    else
        die "Не удалось загрузить образ Xray. Проверь интернет-соединение."
    fi

    info "Запуск Xray контейнера на порту $XRAY_PORT..."

    # Для ghcr образа команда запуска немного отличается
    if [[ "$XRAY_IMAGE" == *"xtls"* ]]; then
        docker run -d \
            --name xray-proxy \
            --restart unless-stopped \
            -p "$XRAY_PORT:$XRAY_PORT" \
            -p "$XRAY_HTTP_PORT:$XRAY_HTTP_PORT" \
            -v "$XRAY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$XRAY_IMAGE" \
            run -config /etc/xray/config.json >/dev/null 2>&1
    else
        docker run -d \
            --name xray-proxy \
            --restart unless-stopped \
            -p "$XRAY_PORT:$XRAY_PORT" \
            -p "$XRAY_HTTP_PORT:$XRAY_HTTP_PORT" \
            -v "$XRAY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$XRAY_IMAGE" \
            xray -config /etc/xray/config.json >/dev/null 2>&1
    fi

    if ! docker ps --format "{{.Names}}" | grep -q "^xray-proxy$" 2>/dev/null; then
        echo ""
        echo -e "${R}Диагностика:${NC}"
        docker logs xray-proxy 2>&1 | tail -20
        docker rm xray-proxy >/dev/null 2>&1
        die "Xray контейнер не запустился. Смотри логи выше."
    fi

    # Даём секунду на старт и проверяем
    sleep 2
    if ! docker ps --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        echo -e "${R}Контейнер упал сразу после старта:${NC}"
        docker logs xray-proxy 2>&1 | tail -20
        docker rm xray-proxy >/dev/null 2>&1
        die "Xray упал. Проверь конфиг."
    fi

    _firewall_open "$XRAY_PORT"
    _firewall_open "$XRAY_HTTP_PORT"

    local IP
    IP=$(get_public_ip)

    echo "$XRAY_PORT|$XRAY_HTTP_PORT|$XRAY_USER|$XRAY_PASS|$(date '+%Y-%m-%d %H:%M:%S')" > "$CONFIG_DIR/xray.conf"
    secure_file "$CONFIG_DIR/xray.conf"
    log "Xray установлен: порт=$XRAY_PORT"

    clear
    echo -e "${G}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${G}║        Xray SOCKS5 установлен!              ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════╝${NC}
"
    echo -e "  ${C}IP:${NC}       $IP"
    echo -e "  ${C}Порт:${NC}     $XRAY_PORT"
    echo -e "  ${C}Протокол:${NC} SOCKS5"
    if [[ "$XRAY_AUTH_TYPE" == "password" ]]; then
        echo -e "  ${C}Логин:${NC}    $XRAY_USER"
        echo -e "  ${C}Пароль:${NC}   $XRAY_PASS"
    else
        echo -e "  ${C}Авторизация:${NC} без пароля"
    fi
    echo -e "
  ${W}Как настроить:${NC}"
    echo -e "  • Android/iPhone: Настройки → WiFi → Прокси → Вручную"
    echo -e "    Хост: $IP  |  Порт: $XRAY_PORT  |  Тип: SOCKS5"
    echo -e "  • Браузер: расширение Proxy SwitchyOmega"
    echo -e "  • WhatsApp/Telegram: Настройки → Прокси → SOCKS5"
    echo -e "
  ${Y}QR для мобильных приложений:${NC}"
    if [[ "$XRAY_AUTH_TYPE" == "password" ]]; then
        qrencode -t ANSIUTF8 "socks5://$XRAY_USER:$XRAY_PASS@$IP:$XRAY_PORT"
    else
        qrencode -t ANSIUTF8 "socks5://$IP:$XRAY_PORT"
    fi

    pause
}

xray_status() {
    banner
    echo -e "${C}═══ СТАТУС XRAY SOCKS5 ═══${NC}
"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        warn "Xray не установлен."
        pause; return
    fi

    local STATUS IP PORT
    STATUS=$(docker inspect --format='{{.State.Status}}' xray-proxy 2>/dev/null)
    PORT=$(docker inspect xray-proxy \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
    IP=$(get_public_ip)

    local COLOR="${R}"
    [[ "$STATUS" == "running" ]] && COLOR="${G}"

    echo -e "  ${W}Статус:${NC}   [${COLOR}${STATUS}${NC}]"
    echo -e "  ${W}IP:${NC}       $IP"
    echo -e "  ${W}Порт:${NC}     $PORT"
    echo -e "  ${W}Протокол:${NC} SOCKS5"

    if [[ -f "$CONFIG_DIR/xray.conf" ]]; then
        local XHTTP_PORT XUSER XPASS
        XHTTP_PORT=$(cut -d'|' -f2 "$CONFIG_DIR/xray.conf")
        XUSER=$(cut -d'|' -f3 "$CONFIG_DIR/xray.conf")
        XPASS=$(cut -d'|' -f4 "$CONFIG_DIR/xray.conf")
        [[ -n "$XHTTP_PORT" ]] && echo -e "  ${W}HTTP порт:${NC} $XHTTP_PORT  ${DIM}(для WhatsApp)${NC}"
        [[ -n "$XUSER" ]] && echo -e "  ${W}Логин:${NC}    $XUSER"
        [[ -n "$XPASS" ]] && echo -e "  ${W}Пароль:${NC}   $XPASS"
    fi

    echo -e "
  ${W}SOCKS5:${NC} ${B}$IP:$PORT${NC}  ${DIM}(браузер, система)${NC}"
    if [[ -f "$CONFIG_DIR/xray.conf" ]]; then
        local http_p
        http_p=$(cut -d'|' -f2 "$CONFIG_DIR/xray.conf")
        [[ -n "$http_p" ]] && echo -e "  ${W}HTTP:${NC}   ${B}$IP:$http_p${NC}  ${DIM}(WhatsApp, Instagram)${NC}"
    fi
    echo ""
    echo -e "${C}  Трафик:${NC}"
    docker stats --no-stream --format "  CPU: {{.CPUPerc}}  RAM: {{.MemUsage}}  NET: {{.NetIO}}" xray-proxy 2>/dev/null
    echo ""
    echo -e "${C}  Логи (последние 20 строк):${NC}"
    docker logs --tail=20 xray-proxy 2>&1

    pause
}

xray_manage() {
    banner
    echo -e "${C}═══ УПРАВЛЕНИЕ XRAY ═══${NC}
"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        warn "Xray не установлен."; pause; return
    fi

    local STATUS
    STATUS=$(docker inspect --format='{{.State.Status}}' xray-proxy)
    local COLOR="${R}"; [[ "$STATUS" == "running" ]] && COLOR="${G}"
    echo -e "  Xray [${COLOR}${STATUS}${NC}]
"
    echo -e "  1) Start   2) Stop   3) Restart"
    read -rp "  Действие: " act
    case $act in
        1) docker start xray-proxy >/dev/null && success "Запущен" ;;
        2) docker stop xray-proxy >/dev/null && success "Остановлен" ;;
        3) docker restart xray-proxy >/dev/null && success "Перезапущен" ;;
        *) warn "Неверный выбор" ;;
    esac
    log "Xray управление: $act"
    pause
}

xray_delete() {
    banner
    echo -e "${R}═══ УДАЛЕНИЕ XRAY ═══${NC}
"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        warn "Xray не установлен."; pause; return
    fi

    read -rp "  Удалить Xray SOCKS5? [y/N] " confirm
    [[ "${confirm,,}" != "y" ]] && return

    # Читаем порты ДО удаления контейнера и конфига
    local SOCKS_PORT HTTP_PORT
    SOCKS_PORT=$(cut -d'|' -f1 "$CONFIG_DIR/xray.conf" 2>/dev/null)
    HTTP_PORT=$(cut -d'|' -f2 "$CONFIG_DIR/xray.conf" 2>/dev/null)

    # Если конфига нет — берём порт из docker inspect (только первый)
    if [[ -z "$SOCKS_PORT" ]]; then
        SOCKS_PORT=$(docker inspect xray-proxy             --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}} {{end}}'             2>/dev/null | awk '{print $1}')
    fi

    docker stop xray-proxy >/dev/null 2>&1
    docker rm xray-proxy >/dev/null 2>&1
    rm -f "$CONFIG_DIR/xray.conf"

    # Закрываем порты в firewall — защита от пустых значений
    if [[ -n "$SOCKS_PORT" && "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then
        if [[ -n "$HTTP_PORT" && "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
            read -rp "  Закрыть порты $SOCKS_PORT и $HTTP_PORT в firewall? [y/N] " fw
            if [[ "${fw,,}" == "y" ]]; then
                _firewall_close "$SOCKS_PORT"
                _firewall_close "$HTTP_PORT"
            fi
        else
            read -rp "  Закрыть порт $SOCKS_PORT в firewall? [y/N] " fw
            [[ "${fw,,}" == "y" ]] && _firewall_close "$SOCKS_PORT"
        fi
    fi

    success "Xray удалён."
    log "Xray удалён"
    pause
}

install_all() {
    banner
    echo -e "${G}═══ УСТАНОВКА ВСЕГО (Telegram + Xray) ═══${NC}
"
    echo "Будет установлено:"
    echo "  • Telegram MTProxy с Fake TLS"
    echo "  • Xray SOCKS5 (WhatsApp / универсальный)"
    echo ""
    read -rp "Продолжить? [Y/n] " confirm
    [[ "${confirm,,}" == "n" ]] && return

    menu_add
    xray_install
}

# ─── МЕНЮ XRAY ──────────────────────────────────────────────

xray_menu() {
    while true; do
        banner
        echo -e "${W}  ── Xray SOCKS5 (WhatsApp / универсальный) ──${NC}
"
        echo -e "  ${G}1)${NC} Установить Xray SOCKS5"
        echo -e "  ${C}2)${NC} Статус и логи"
        echo -e "  ${Y}3)${NC} Start / Stop / Restart"
        echo -e "  ${R}4)${NC} Удалить Xray"
        echo -e "  ${DIM}0)${NC} Назад
"

        read -rp "  Пункт: " choice
        case $choice in
            1) xray_install ;;
            2) xray_status ;;
            3) xray_manage ;;
            4) xray_delete ;;
            0) return ;;
            *) warn "Неверный ввод." ;;
        esac
    done
}


# ═══════════════════════════════════════════════════════════
# ─── CLOUDFLARE WARP ЧЕРЕЗ XRAY WIREGUARD OUTBOUND ────────
# ═══════════════════════════════════════════════════════════

_install_wgcf() {
    if command -v wgcf &>/dev/null; then
        command -v wgcf
        return
    fi

    local arch suffix release_json url tmp
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) suffix="linux_amd64" ;;
        aarch64|arm64) suffix="linux_arm64" ;;
        armv7l) suffix="linux_armv7" ;;
        armv6l) suffix="linux_armv6" ;;
        armv5l) suffix="linux_armv5" ;;
        i386|i686) suffix="linux_386" ;;
        *) die "Архитектура не поддерживается для wgcf: $arch" ;;
    esac

    info "Скачиваю wgcf для $suffix..." >&2
    release_json=$(curl -fsSL "https://api.github.com/repos/ViRb3/wgcf/releases/latest") || die "Не удалось получить release wgcf."
    url=$(echo "$release_json" | jq -r --arg suffix "$suffix" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' | head -n1)
    [[ -n "$url" && "$url" != "null" ]] || die "Не найден бинарник wgcf для $suffix."

    tmp=$(mktemp /tmp/wgcf.XXXXXX)
    curl -fsSL "$url" -o "$tmp" || die "Не удалось скачать wgcf."
    install -m 755 "$tmp" "$WGCF_BIN" || die "Не удалось установить wgcf в $WGCF_BIN."
    rm -f "$tmp"
    echo "$WGCF_BIN"
}

_warp_generate_profile() {
    local license_key="$1"
    local wgcf
    wgcf=$(_install_wgcf)

    mkdir -p "$WARP_DIR"
    secure_dir "$WARP_DIR"

    (
        cd "$WARP_DIR" || exit 1
        if [[ ! -f wgcf-account.toml ]]; then
            info "Регистрирую новый WARP аккаунт..."
            "$wgcf" register --accept-tos >/dev/null 2>&1 || die "wgcf register завершился ошибкой."
        fi
        if [[ -n "$license_key" ]]; then
            info "Привязываю WARP+ license key..."
            "$wgcf" update --license-key "$license_key" >/dev/null 2>&1 || die "wgcf update завершился ошибкой."
        fi
        "$wgcf" generate >/dev/null 2>&1 || die "wgcf generate завершился ошибкой."
    )

    [[ -s "$WARP_DIR/wgcf-profile.conf" ]] || die "wgcf-profile.conf не создан."
    secure_file "$WARP_DIR/wgcf-account.toml"
    secure_file "$WARP_DIR/wgcf-profile.conf"
}

_warp_profile_value() {
    local key="$1" file="$2"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            line=$0;
            sub(/^[^=]*=/, "", line);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
            print line;
            exit
        }
    ' "$file"
}

_warp_profile_values_json() {
    local key="$1" file="$2"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            line=$0;
            sub(/^[^=]*=/, "", line);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
            gsub(/,/, "\n", line);
            print line;
        }
    ' "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | jq -R . | jq -s .
}

_warp_reserved_json() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo '[0,0,0]'
        return
    fi
    echo "$raw" | tr -d '[][:space:]' | jq -R 'split(",") | map(select(length > 0) | tonumber)'
}

_warp_write_xray_config() {
    local socks_port="$1" http_port="$2" listen="$3" user="$4" pass="$5"
    local profile="$WARP_DIR/wgcf-profile.conf"
    local private_key public_key endpoint mtu reserved_raw
    local address_json reserved_json

    private_key=$(_warp_profile_value "PrivateKey" "$profile")
    public_key=$(_warp_profile_value "PublicKey" "$profile")
    endpoint=$(_warp_profile_value "Endpoint" "$profile")
    mtu=$(_warp_profile_value "MTU" "$profile")
    reserved_raw=$(_warp_profile_value "Reserved" "$profile")
    address_json=$(_warp_profile_values_json "Address" "$profile")
    reserved_json=$(_warp_reserved_json "$reserved_raw")
    mtu="${mtu:-1280}"

    [[ -n "$private_key" && -n "$public_key" && -n "$endpoint" ]] || die "WARP профиль неполный: нет PrivateKey/PublicKey/Endpoint."
    [[ -n "$address_json" && "$address_json" != "[]" ]] || die "WARP профиль неполный: нет Address."
    [[ "$mtu" =~ ^[0-9]+$ ]] || mtu=1280

    mkdir -p "$WARP_XRAY_DIR"
    secure_dir "$WARP_XRAY_DIR"

    jq -n \
        --argjson socks_port "$socks_port" \
        --argjson http_port "$http_port" \
        --arg listen "$listen" \
        --arg user "$user" \
        --arg pass "$pass" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg endpoint "$endpoint" \
        --argjson addresses "$address_json" \
        --argjson reserved "$reserved_json" \
        --argjson mtu "$mtu" \
        '{
          log: {loglevel: "warning"},
          dns: {servers: ["1.1.1.1", "1.0.0.1", "8.8.8.8"]},
          inbounds: [
            {
              port: $socks_port,
              listen: $listen,
              protocol: "socks",
              tag: "socks-in",
              settings: {
                auth: "password",
                accounts: [{user: $user, pass: $pass}],
                udp: true,
                ip: $listen
              }
            },
            {
              port: $http_port,
              listen: $listen,
              protocol: "http",
              tag: "http-in",
              settings: {
                accounts: [{user: $user, pass: $pass}],
                allowTransparent: true
              }
            }
          ],
          outbounds: [
            {
              tag: "wireguard",
              protocol: "wireguard",
              settings: {
                secretKey: $private_key,
                address: $addresses,
                peers: [
                  {
                    publicKey: $public_key,
                    endpoint: $endpoint,
                    allowedIPs: ["0.0.0.0/0", "::/0"],
                    keepAlive: 25
                  }
                ],
                reserved: $reserved,
                mtu: $mtu,
                noKernelTun: true,
                domainStrategy: "ForceIPv4"
              }
            }
          ],
          routing: {
            domainStrategy: "IPIfNonMatch",
            rules: [
              {type: "field", inboundTag: ["socks-in", "http-in"], outboundTag: "wireguard"}
            ]
          }
        }' > "$WARP_XRAY_DIR/config.json" || die "Не удалось создать WARP Xray config."

    secure_file "$WARP_XRAY_DIR/config.json"
}

_warp_pull_xray_image() {
    local image=""
    if docker pull ghcr.io/xtls/xray-core:latest >/dev/null 2>&1; then
        image="ghcr.io/xtls/xray-core:latest"
    elif docker pull teddysun/xray >/dev/null 2>&1; then
        image="teddysun/xray"
    else
        die "Не удалось загрузить образ Xray для WARP."
    fi
    echo "$image"
}

_warp_proxy_url() {
    local scheme="$1" host="$2" port="$3" user="$4" pass="$5"
    echo "${scheme}://${user}:${pass}@${host}:${port}"
}

_warp_test_trace() {
    [[ -f "$WARP_CONF" ]] || return 1
    local port user pass
    port=$(cut -d'|' -f1 "$WARP_CONF")
    user=$(cut -d'|' -f3 "$WARP_CONF")
    pass=$(cut -d'|' -f4 "$WARP_CONF")
    curl -s --max-time 12 -x "$(_warp_proxy_url "socks5h" "127.0.0.1" "$port" "$user" "$pass")" \
        "https://www.cloudflare.com/cdn-cgi/trace/" 2>/dev/null
}

warp_install() {
    banner
    echo -e "${G}═══ УСТАНОВКА WARP PROXY ═══${NC}\n"
    echo "Создаёт отдельный Xray SOCKS5/HTTP прокси, у которого outbound идёт через Cloudflare WARP."
    echo "Маршруты сервера и SSH не меняются."
    echo ""

    if docker ps -a --format "{{.Names}}" | grep -q "^xray-warp$"; then
        warn "WARP proxy уже установлен."
        pause; return
    fi

    local WARP_PORT WARP_HTTP_PORT mode listen bind_prefix user pass license_key
    read -rp "  SOCKS5 порт [40000]: " WARP_PORT
    WARP_PORT="${WARP_PORT:-40000}"
    is_valid_port "$WARP_PORT" || { warn "Некорректный порт."; pause; return; }
    WARP_HTTP_PORT=$((WARP_PORT + 1))
    is_valid_port "$WARP_HTTP_PORT" || { warn "HTTP порт выходит за диапазон."; pause; return; }

    for check_port in "$WARP_PORT" "$WARP_HTTP_PORT"; do
        if ss -tlnp 2>/dev/null | grep -q ":${check_port} "; then
            warn "Порт $check_port уже занят."
            pause; return
        fi
    done

    echo -e "\n${C}Доступ:${NC}"
    echo "  1) Публичный 0.0.0.0 с логином/паролем"
    echo "  2) Только localhost 127.0.0.1"
    read -rp "  Выбор [1-2]: " mode
    if [[ "$mode" == "2" ]]; then
        listen="127.0.0.1"
        bind_prefix="127.0.0.1:"
    else
        listen="0.0.0.0"
        bind_prefix=""
    fi

    read -rp "  Логин [warp]: " user
    user="${user:-warp}"
    user="${user//[^a-zA-Z0-9_.-]/}"
    user="${user:-warp}"
    read -rsp "  Пароль (Enter = сгенерировать): " pass
    echo ""
    pass="${pass//[^a-zA-Z0-9_.-]/}"
    [[ -z "$pass" ]] && pass="$(random_password)"

    echo ""
    read -rp "  WARP+ license key (Enter = бесплатный WARP): " license_key
    license_key="${license_key//[^a-zA-Z0-9_-]/}"

    _warp_generate_profile "$license_key"
    _warp_write_xray_config "$WARP_PORT" "$WARP_HTTP_PORT" "$listen" "$user" "$pass"

    local image
    image=$(_warp_pull_xray_image)

    info "Запуск xray-warp..."
    if [[ "$image" == *"xtls"* ]]; then
        docker run -d \
            --name xray-warp \
            --restart unless-stopped \
            -p "${bind_prefix}${WARP_PORT}:${WARP_PORT}" \
            -p "${bind_prefix}${WARP_HTTP_PORT}:${WARP_HTTP_PORT}" \
            -v "$WARP_XRAY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$image" \
            run -config /etc/xray/config.json >/dev/null 2>&1
    else
        docker run -d \
            --name xray-warp \
            --restart unless-stopped \
            -p "${bind_prefix}${WARP_PORT}:${WARP_PORT}" \
            -p "${bind_prefix}${WARP_HTTP_PORT}:${WARP_HTTP_PORT}" \
            -v "$WARP_XRAY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$image" \
            xray -config /etc/xray/config.json >/dev/null 2>&1
    fi

    sleep 3
    if ! docker ps --format "{{.Names}}" | grep -q "^xray-warp$"; then
        echo -e "${R}Логи:${NC}"
        docker logs xray-warp 2>&1 | tail -30
        docker rm xray-warp >/dev/null 2>&1
        die "WARP proxy не запустился."
    fi

    if [[ "$listen" == "0.0.0.0" ]]; then
        _firewall_open "$WARP_PORT"
        _firewall_open "$WARP_HTTP_PORT"
    fi

    echo "$WARP_PORT|$WARP_HTTP_PORT|$user|$pass|$listen|$(date '+%Y-%m-%d %H:%M:%S')" > "$WARP_CONF"
    secure_file "$WARP_CONF"
    log "WARP proxy установлен: socks=$WARP_PORT http=$WARP_HTTP_PORT listen=$listen"

    local IP display_host trace warp_line
    IP=$(get_public_ip)
    display_host="$IP"
    [[ "$listen" == "127.0.0.1" ]] && display_host="127.0.0.1"
    trace=$(_warp_test_trace)
    warp_line=$(echo "$trace" | grep '^warp=' || true)

    clear
    echo -e "${G}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${G}║          WARP proxy установлен!             ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════╝${NC}\n"
    echo -e "  ${C}Listen:${NC}   $listen"
    echo -e "  ${C}SOCKS5:${NC}   ${display_host}:${WARP_PORT}"
    echo -e "  ${C}HTTP:${NC}     ${display_host}:${WARP_HTTP_PORT}"
    echo -e "  ${C}Логин:${NC}    $user"
    echo -e "  ${C}Пароль:${NC}   $pass"
    [[ -n "$warp_line" ]] && echo -e "  ${C}Trace:${NC}    $warp_line" || warn "Не удалось проверить WARP trace через прокси."
    echo -e "\n  ${Y}QR SOCKS5:${NC}"
    qrencode -t ANSIUTF8 "$(_warp_proxy_url "socks5" "$display_host" "$WARP_PORT" "$user" "$pass")"
    pause
}

warp_status() {
    banner
    echo -e "${C}═══ СТАТУС WARP PROXY ═══${NC}\n"
    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-warp$"; then
        warn "WARP proxy не установлен."
        pause; return
    fi

    local status color ip display_host port http_port user listen trace
    status=$(docker inspect --format='{{.State.Status}}' xray-warp 2>/dev/null)
    color="${R}"; [[ "$status" == "running" ]] && color="${G}"
    ip=$(get_public_ip)

    if [[ -f "$WARP_CONF" ]]; then
        port=$(cut -d'|' -f1 "$WARP_CONF")
        http_port=$(cut -d'|' -f2 "$WARP_CONF")
        user=$(cut -d'|' -f3 "$WARP_CONF")
        listen=$(cut -d'|' -f5 "$WARP_CONF")
    fi
    display_host="$ip"
    [[ "$listen" == "127.0.0.1" ]] && display_host="127.0.0.1"

    echo -e "  ${W}Статус:${NC}  [${color}${status}${NC}]"
    echo -e "  ${W}Listen:${NC}  ${listen:-unknown}"
    echo -e "  ${W}SOCKS5:${NC}  ${display_host}:${port:-unknown}"
    echo -e "  ${W}HTTP:${NC}    ${display_host}:${http_port:-unknown}"
    echo -e "  ${W}Логин:${NC}   ${user:-unknown}"
    echo ""

    trace=$(_warp_test_trace)
    if [[ -n "$trace" ]]; then
        echo -e "${C}Cloudflare trace:${NC}"
        echo "$trace" | grep -E '^(ip|colo|warp|gateway)=' || echo "$trace" | head -10
    else
        warn "Trace не получен."
    fi

    echo -e "\n${C}Трафик:${NC}"
    docker stats --no-stream --format "  CPU: {{.CPUPerc}}  RAM: {{.MemUsage}}  NET: {{.NetIO}}" xray-warp 2>/dev/null
    echo -e "\n${C}Логи (20 строк):${NC}"
    docker logs --tail=20 xray-warp 2>&1
    pause
}

warp_manage() {
    banner
    echo -e "${C}═══ УПРАВЛЕНИЕ WARP PROXY ═══${NC}\n"
    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-warp$"; then
        warn "WARP proxy не установлен."; pause; return
    fi
    local status
    status=$(docker inspect --format='{{.State.Status}}' xray-warp)
    echo -e "  xray-warp: ${Y}$status${NC}\n"
    echo "  1) Start   2) Stop   3) Restart"
    read -rp "  Действие: " act
    case $act in
        1) docker start xray-warp >/dev/null && success "Запущен" ;;
        2) docker stop xray-warp >/dev/null && success "Остановлен" ;;
        3) docker restart xray-warp >/dev/null && success "Перезапущен" ;;
        *) warn "Неверный выбор" ;;
    esac
    pause
}

warp_delete() {
    banner
    echo -e "${R}═══ УДАЛЕНИЕ WARP PROXY ═══${NC}\n"
    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-warp$"; then
        warn "WARP proxy не установлен."; pause; return
    fi
    read -rp "  Удалить WARP proxy? [y/N] " confirm
    [[ "${confirm,,}" != "y" ]] && return

    local port http_port listen
    if [[ -f "$WARP_CONF" ]]; then
        port=$(cut -d'|' -f1 "$WARP_CONF")
        http_port=$(cut -d'|' -f2 "$WARP_CONF")
        listen=$(cut -d'|' -f5 "$WARP_CONF")
    fi

    docker stop xray-warp >/dev/null 2>&1
    docker rm xray-warp >/dev/null 2>&1
    rm -f "$WARP_CONF"

    if [[ "$listen" == "0.0.0.0" && -n "$port" && -n "$http_port" ]]; then
        read -rp "  Закрыть порты $port и $http_port в firewall? [y/N] " fw
        if [[ "${fw,,}" == "y" ]]; then
            _firewall_close "$port"
            _firewall_close "$http_port"
        fi
    fi

    success "WARP proxy удалён. WARP аккаунт сохранён в $WARP_DIR"
    log "WARP proxy удалён"
    pause
}

warp_menu() {
    while true; do
        banner
        echo -e "${W}  ── Cloudflare WARP через Xray ──${NC}\n"
        echo -e "  ${G}1)${NC} Установить WARP proxy"
        echo -e "  ${C}2)${NC} Статус и trace"
        echo -e "  ${Y}3)${NC} Start / Stop / Restart"
        echo -e "  ${R}4)${NC} Удалить WARP proxy"
        echo -e "  ${DIM}0)${NC} Назад\n"
        read -rp "  Пункт: " choice
        case $choice in
            1) warp_install ;;
            2) warp_status ;;
            3) warp_manage ;;
            4) warp_delete ;;
            0) return ;;
            *) warn "Неверный ввод." ;;
        esac
    done
}


# ═══════════════════════════════════════════════════════════
# ─── TELEGRAM БОТ — УПРАВЛЕНИЕ ПРОКСИ ──────────────────────
# ═══════════════════════════════════════════════════════════

BOT_CONF="$CONFIG_DIR/bot.conf"
BOT_PID_FILE="$CONFIG_DIR/bot.pid"
BOT_LOG="$CONFIG_DIR/bot.log"

_bot_send() {
    local token="$1" chat_id="$2" text="$3"
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -d chat_id="$chat_id" \
        -d text="$text" \
        -d parse_mode="HTML" \
        -d disable_web_page_preview="true" >/dev/null 2>&1
}

_bot_send_photo() {
    local token="$1" chat_id="$2" photo="$3" caption="$4"
    curl -s -X POST "https://api.telegram.org/bot${token}/sendPhoto" \
        -F chat_id="$chat_id" \
        -F photo="@$photo" \
        -F caption="$caption" \
        -F parse_mode="HTML" >/dev/null 2>&1
}

_bot_get_ip() {
    curl -s4 --max-time 4 https://api.ipify.org 2>/dev/null || echo "0.0.0.0"
}

_bot_cmd_help() {
    local token="$1" chat_id="$2"
    _bot_send "$token" "$chat_id" "🤖 <b>Proxy Manager Bot</b>

<b>Команды:</b>
/add имя порт домен — создать прокси
  Пример: /add ivan 443 cloudflare.com

/delete имя — удалить прокси
  Пример: /delete ivan

/list — все прокси со ссылками

/status — статус контейнеров

/qr имя — получить QR-код

/restart имя — перезапустить прокси

/help — эта справка"
}

_bot_cmd_add() {
    local token="$1" chat_id="$2" args="$3"
    local client_id port domain
    client_id=$(echo "$args" | awk '{print $1}')
    port=$(echo "$args" | awk '{print $2}')
    domain=$(echo "$args" | awk '{print $3}')
    port="${port:-443}"
    domain="${domain:-google.com}"

    # Санитизация — только безопасные символы
    client_id="${client_id//[^a-zA-Z0-9_-]/}"
    port="${port//[^0-9]/}"
    domain="${domain//[^a-zA-Z0-9._-]/}"

    if [[ -z "$client_id" ]]; then
        _bot_send "$token" "$chat_id" "❌ Пример: /add ivan 443 cloudflare.com"
        return
    fi

    # Валидация порта
    if [[ -z "$port" || "$port" -lt 1 || "$port" -gt 65535 ]] 2>/dev/null; then
        _bot_send "$token" "$chat_id" "❌ Неверный порт: <code>$port</code>\nДопустимо: 1-65535"
        return
    fi

    # Валидация домена
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$ ]]; then
        _bot_send "$token" "$chat_id" "❌ Неверный домен: <code>$domain</code>"
        return
    fi

    # Ограничение длины имени
    if [[ ${#client_id} -gt 32 ]]; then
        _bot_send "$token" "$chat_id" "❌ Имя слишком длинное (макс. 32 символа)"
        return
    fi

    local container="mtproto-$client_id"
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        _bot_send "$token" "$chat_id" "⚠️ Клиент <b>$client_id</b> уже существует!"
        return
    fi

    _bot_send "$token" "$chat_id" "⏳ Создаю прокси <b>$client_id</b> на порту <b>$port</b>..."

    local secret
    secret=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$domain" 2>/dev/null)
    if [[ -z "$secret" ]]; then
        _bot_send "$token" "$chat_id" "❌ Ошибка генерации секрета."
        return
    fi

    docker run -d \
        --name "$container" \
        --restart unless-stopped \
        -p "${port}:${port}" \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        nineseconds/mtg:2 \
        simple-run -n 1.1.1.1 -i prefer-ipv4 "0.0.0.0:${port}" "$secret" >/dev/null 2>&1

    sleep 2
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        _bot_send "$token" "$chat_id" "❌ Контейнер не запустился! Порт $port возможно занят."
        return
    fi

    _firewall_open "$port" >/dev/null 2>&1
    echo "$container|$client_id|$port|$secret|$domain|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_FILE"
    log "БОТ: создан прокси $container порт=$port"

    local ip
    ip=$(_bot_get_ip)
    local link="tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    local https_link="https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"

    _bot_send "$token" "$chat_id" "✅ <b>Прокси создан!</b>

👤 Клиент: <b>$client_id</b>
🌐 Домен: <code>$domain</code>
🖥 IP: <code>$ip</code>
🔌 Порт: <code>$port</code>

🔗 tg://
<code>$link</code>

🔗 https://
<code>$https_link</code>"

    local qr_file
    qr_file=$(mktemp "/tmp/qr_${client_id}.XXXXXX.png")
    if command -v qrencode &>/dev/null; then
        qrencode -o "$qr_file" -s 8 "$link" 2>/dev/null
        [[ -f "$qr_file" ]] && _bot_send_photo "$token" "$chat_id" "$qr_file" "QR для $client_id" && rm -f "$qr_file"
    fi
}

_bot_cmd_delete() {
    local token="$1" chat_id="$2" args="$3"
    local client_id="${args//[^a-zA-Z0-9_-]/}"
    local container="mtproto-$client_id"

    if [[ -z "$client_id" ]]; then
        _bot_send "$token" "$chat_id" "❌ Пример: /delete ivan"
        return
    fi

    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        _bot_send "$token" "$chat_id" "⚠️ Клиент <b>$client_id</b> не найден."
        return
    fi

    local port
    port=$(docker inspect "$container" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)

    mkdir -p "$BACKUP_DIR"
    grep "^${container}|" "$CONFIG_FILE" > "$BACKUP_DIR/${container}_bot_del_$(date +%Y%m%d).bak" 2>/dev/null
    docker stop "$container" >/dev/null 2>&1
    docker rm "$container" >/dev/null 2>&1
    sed -i "/^${container}|/d" "$CONFIG_FILE"
    log "БОТ: удалён $container"

    _bot_send "$token" "$chat_id" "🗑 Прокси <b>$client_id</b> (порт $port) удалён."
}

_bot_cmd_list() {
    local token="$1" chat_id="$2"
    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")

    if [[ ${#containers[@]} -eq 0 ]]; then
        _bot_send "$token" "$chat_id" "📋 Прокси не найдены."
        return
    fi

    local ip
    ip=$(_bot_get_ip)
    local msg="📋 <b>Список прокси:</b>"

    for c in "${containers[@]}"; do
        local status port cmd secret domain
        status=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null)
        port=$(docker inspect "$c" \
            --format='{{range $p,$cc := .HostConfig.PortBindings}}{{(index $cc 0).HostPort}}{{end}}' 2>/dev/null)
        cmd=$(docker inspect "$c" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
        secret=$(echo "$cmd" | awk '{print $NF}')
        domain=$(grep "^${c}|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "—")
        local icon="🔴"
        [[ "$status" == "running" ]] && icon="🟢"
        local link="tg://proxy?server=${ip}&port=${port}&secret=${secret}"
        msg="${msg}

${icon} <b>${c#mtproto-}</b> | порт <code>${port}</code> | ${domain}
<code>${link}</code>"
    done

    _bot_send "$token" "$chat_id" "$msg"
}

_bot_cmd_status() {
    local token="$1" chat_id="$2"
    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")
    local msg="📊 <b>Статус:</b>"

    if [[ ${#containers[@]} -eq 0 ]]; then
        msg="${msg}
Прокси не найдены."
    else
        for c in "${containers[@]}"; do
            local status port
            status=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null)
            port=$(docker inspect "$c" \
                --format='{{range $p,$cc := .HostConfig.PortBindings}}{{(index $cc 0).HostPort}}{{end}}' 2>/dev/null)
            local icon="🔴"
            [[ "$status" == "running" ]] && icon="🟢"
            msg="${msg}
${icon} <b>${c#mtproto-}</b> | порт <code>${port}</code> | ${status}"
        done
    fi

    if docker ps -a --format "{{.Names}}" | grep -q "^xray-proxy$"; then
        local xs
        xs=$(docker inspect --format='{{.State.Status}}' xray-proxy 2>/dev/null)
        local xi="🔴"; [[ "$xs" == "running" ]] && xi="🟢"
        msg="${msg}

${xi} <b>Xray SOCKS5</b> | ${xs}"
    fi

    msg="${msg}

🖥 <code>$(_bot_get_ip)</code>"
    _bot_send "$token" "$chat_id" "$msg"
}

_bot_cmd_qr() {
    local token="$1" chat_id="$2" args="$3"
    local client_id="${args//[^a-zA-Z0-9_-]/}"
    local container="mtproto-$client_id"

    if [[ -z "$client_id" ]] || ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        _bot_send "$token" "$chat_id" "⚠️ Клиент не найден. Пример: /qr ivan"
        return
    fi

    local ip port cmd secret
    ip=$(_bot_get_ip)
    port=$(docker inspect "$container" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
    cmd=$(docker inspect "$container" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
    secret=$(echo "$cmd" | awk '{print $NF}')
    local link="tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    local qr_file
    qr_file=$(mktemp "/tmp/qr_${client_id}.XXXXXX.png")

    if command -v qrencode &>/dev/null; then
        qrencode -o "$qr_file" -s 8 "$link" 2>/dev/null
        _bot_send_photo "$token" "$chat_id" "$qr_file" "🔗 $client_id | порт $port
$link"
        rm -f "$qr_file"
    else
        _bot_send "$token" "$chat_id" "🔗 <b>$client_id</b>
<code>$link</code>"
    fi
}

_bot_cmd_restart() {
    local token="$1" chat_id="$2" args="$3"
    local client_id="${args//[^a-zA-Z0-9_-]/}"
    local container="mtproto-$client_id"

    if [[ -z "$client_id" ]] || ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        _bot_send "$token" "$chat_id" "⚠️ Клиент не найден. Пример: /restart ivan"
        return
    fi

    docker restart "$container" >/dev/null 2>&1
    _bot_send "$token" "$chat_id" "🔄 Прокси <b>$client_id</b> перезапущен."
    log "БОТ: перезапущен $container"
}

_bot_parse_updates() {
    local response="$1"
    python3 - "$response" << 'PYEOF'
import sys, json
try:
    data = json.loads(sys.argv[1])
    if not data.get('ok'):
        sys.exit(0)
    for u in data.get('result', []):
        uid = u.get('update_id', 0)
        msg = u.get('message', {})
        chat = msg.get('chat', {}).get('id', '')
        text = msg.get('text', '')
        if text and chat:
            print(f"{uid}|||{chat}|||{text}")
except Exception as e:
    import sys
    print(f"PARSE_ERROR: {e}", file=sys.stderr)
PYEOF
}

_bot_loop() {
    local token="$1" admin_id="$2"
    local offset=0

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] БОТ запущен" >> "$BOT_LOG"
    _bot_send "$token" "$admin_id" "🟢 <b>Proxy Bot запущен!</b>
Напиши /help для команд."

    while true; do
        local response
        response=$(curl -s "https://api.telegram.org/bot${token}/getUpdates?offset=${offset}&timeout=25&limit=5" 2>/dev/null)

        local updates
        updates=$(_bot_parse_updates "$response")

        if [[ -n "$updates" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local upd_id chat_id text
                upd_id=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
                chat_id=$(echo "$line" | awk -F'[|][|][|]' '{print $2}')
                text=$(echo "$line" | awk -F'[|][|][|]' '{print $3}')
                offset=$((upd_id + 1))

                # Защита — пустой chat_id пропускаем
                [[ -z "$chat_id" ]] && continue

                if [[ "$chat_id" != "$admin_id" ]]; then
                    _bot_send "$token" "$chat_id" "⛔ Доступ запрещён."
                    log "БОТ: отклонён запрос от chat_id=$chat_id"
                    continue
                fi

                local cmd args
                cmd=$(echo "$text" | awk '{print $1}')
                args=$(echo "$text" | cut -d' ' -f2-)
                [[ "$args" == "$cmd" ]] && args=""

                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $chat_id: $cmd $args" >> "$BOT_LOG"

                case "$cmd" in
                    /add)          _bot_cmd_add     "$token" "$chat_id" "$args" ;;
                    /delete)       _bot_cmd_delete  "$token" "$chat_id" "$args" ;;
                    /list)         _bot_cmd_list    "$token" "$chat_id" ;;
                    /status)       _bot_cmd_status  "$token" "$chat_id" ;;
                    /qr)           _bot_cmd_qr      "$token" "$chat_id" "$args" ;;
                    /restart)      _bot_cmd_restart "$token" "$chat_id" "$args" ;;
                    /help|/start)  _bot_cmd_help    "$token" "$chat_id" ;;
                    *)             _bot_send "$token" "$chat_id" "❓ Неизвестная команда. /help" ;;
                esac
            done <<< "$updates"
        fi

        sleep 1
    done
}

setup_tg_bot() {
    banner
    echo -e "${M}═══ TELEGRAM БОТ УПРАВЛЕНИЯ ═══${NC}\n"
    echo "Управляй прокси прямо из Telegram:"
    echo "  /add, /delete, /list, /status, /qr, /restart"
    echo ""
    echo -e "  ${G}1)${NC} Настроить и запустить бота"
    echo -e "  ${C}2)${NC} Статус бота"
    echo -e "  ${Y}3)${NC} Остановить бота"
    echo -e "  ${DIM}4)${NC} Лог бота"
    echo -e "  ${DIM}0)${NC} Назад\n"
    read -rp "  Пункт: " bc

    case $bc in
        1)
            echo ""
            echo -e "${C}1. Создай бота через @BotFather — получи токен.${NC}"
            echo -e "${C}2. Свой chat_id узнай через @userinfobot.${NC}\n"
            read -rp "  Bot Token: " BOT_TOKEN
            read -rp "  Твой Chat ID: " BOT_ADMIN_ID
            BOT_TOKEN="${BOT_TOKEN//[^a-zA-Z0-9:_-]/}"
            BOT_ADMIN_ID="${BOT_ADMIN_ID//[^0-9-]/}"

            if [[ -z "$BOT_TOKEN" || -z "$BOT_ADMIN_ID" ]]; then
                warn "Токен и Chat ID обязательны!"; pause; return
            fi

            local check
            check=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
            if ! echo "$check" | grep -q '"ok":true'; then
                warn "Неверный токен!"; pause; return
            fi

            local bot_name
            bot_name=$(echo "$check" | jq -r '.result.username // "unknown"' 2>/dev/null)
            success "Бот найден: @$bot_name"

            cat > "$BOT_CONF" << BOTEOF
BOT_TOKEN=$BOT_TOKEN
BOT_ADMIN_ID=$BOT_ADMIN_ID
BOT_NAME=$bot_name
BOTEOF
            secure_file "$BOT_CONF"

            # Останавливаем старый
            if [[ -f "$BOT_PID_FILE" ]]; then
                kill "$(cat "$BOT_PID_FILE")" 2>/dev/null
                rm -f "$BOT_PID_FILE"
            fi

            # Создаём systemd unit для автозапуска при ребуте
            cat > /etc/systemd/system/mtproxy-bot.service << SVCEOF
[Unit]
Description=MTProxy Telegram Bot
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/mtproxy --bot-daemon
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

            if [[ -f "$BOT_PID_FILE" ]]; then
                kill "$(cat "$BOT_PID_FILE")" 2>/dev/null || true
                rm -f "$BOT_PID_FILE"
            fi

            if is_systemd_available; then
                systemctl daemon-reload 2>/dev/null || true
                systemctl enable mtproxy-bot.service 2>/dev/null || true
                systemctl restart mtproxy-bot.service 2>/dev/null || true
                if systemctl is-active --quiet mtproxy-bot.service; then
                    success "Бот @$bot_name запущен через systemd."
                else
                    warn "Systemd unit создан, но сервис не стартовал. Смотри: journalctl -u mtproxy-bot -n 50"
                fi
            else
                _bot_loop "$BOT_TOKEN" "$BOT_ADMIN_ID" &
                echo $! > "$BOT_PID_FILE"
                success "Бот @$bot_name запущен (PID: $(cat "$BOT_PID_FILE"))!"
            fi

            echo -e "\n${C}Напиши /help боту в Telegram.${NC}"
            log "TG бот запущен: @$bot_name"
            ;;
        2)
            echo ""
            if is_systemd_available && systemctl is-active --quiet mtproxy-bot.service; then
                # shellcheck disable=SC1090
                source "$BOT_CONF" 2>/dev/null || true
                success "Бот работает через systemd | @${BOT_NAME:-unknown}"
            elif [[ -f "$BOT_PID_FILE" ]] && kill -0 "$(cat "$BOT_PID_FILE")" 2>/dev/null; then
                # shellcheck disable=SC1090
                source "$BOT_CONF" 2>/dev/null
                success "Бот работает | PID: $(cat "$BOT_PID_FILE") | @${BOT_NAME:-unknown}"
            else
                warn "Бот не запущен."
            fi
            ;;
        3)
            if is_systemd_available; then
                systemctl disable --now mtproxy-bot.service 2>/dev/null || true
            fi
            if [[ -f "$BOT_PID_FILE" ]]; then
                kill "$(cat "$BOT_PID_FILE")" 2>/dev/null
                rm -f "$BOT_PID_FILE"
            fi
            success "Бот остановлен."
            log "TG бот остановлен"
            ;;
        4)
            echo ""
            tail -30 "$BOT_LOG" 2>/dev/null || warn "Лог пуст."
            ;;
    esac
    pause
}


# ─── ГЛАВНОЕ МЕНЮ ───────────────────────────────────────────

main_menu() {
    while true; do
        banner
        echo -e "  ${W}── Telegram MTProxy (Fake TLS) ──${NC}"
        echo -e "  ${G}1)${NC}  Добавить новый MTProxy"
        echo -e "  ${C}2)${NC}  Список всех прокси"
        echo -e "  ${C}3)${NC}  Детали / QR по клиенту"
        echo -e "  ${C}4)${NC}  Статус, трафик и подключения"
        echo -e "  ${Y}5)${NC}  Start / Stop / Restart"
        echo -e "  ${Y}6)${NC}  Обновить секрет (rotate)"
        echo -e "  ${G}7)${NC}  Экспорт всех ссылок в файл"
        echo -e "  ${G}8)${NC}  Миграция на новый сервер"
        echo ""
        echo -e "  ${W}── VLESS + XTLS-Reality (Anti-DPI) ──${NC}"
        echo -e "  ${G}9)${NC}  Меню VLESS+Reality"
        echo ""
        echo -e "  ${W}── Xray SOCKS5 (WhatsApp / универсальный) ──${NC}"
        echo -e "  ${M}10)${NC} Меню Xray SOCKS5"
        echo -e "  ${M}21)${NC} Меню Cloudflare WARP"
        echo ""
        echo -e "  ${W}── Установить всё сразу ──${NC}"
        echo -e "  ${G}11)${NC} Установить Telegram + Xray"
        echo ""
        echo -e "  ${W}── Telegram Бот ──${NC}"
        echo -e "  ${M}20)${NC} Бот управления (add/delete/list/qr)"
        echo ""
        echo -e "  ${W}── Система ──${NC}"
        echo -e "  ${C}12)${NC} Firewall — управление портами"
        echo -e "  ${M}13)${NC} Healthcheck / Автоперезапуск"
        echo -e "  ${M}14)${NC} Авто-обновление секрета (cron)"
        echo -e "  ${M}15)${NC} Уведомления в Telegram"
        echo -e "  ${B}16)${NC} Обновить скрипт"
        echo -e "  ${DIM}17)${NC} Просмотр лога"
        echo -e "  ${R}18)${NC} Удалить MTProxy"
        echo -e "  ${R}19)${NC} Полное удаление"
        echo -e "  ${DIM}0)${NC}  Выход\n"

        read -rp "  Пункт: " choice
        case $choice in
            1)  menu_add ;;
            2)  show_list ;;
            3)  show_detail ;;
            4)  show_status ;;
            5)  manage_proxy ;;
            6)  rotate_secret ;;
            7)  export_links ;;
            8)  migrate_export ;;
            9)  xray_reality_menu ;;
            10) xray_menu ;;
            11) install_all ;;
            12) firewall_menu ;;
            13) setup_healthcheck ;;
            14) setup_auto_rotate ;;
            15) setup_tg_notify ;;
            16) self_update ;;
            17) show_log ;;
            18) delete_proxy ;;
            19) full_uninstall ;;
            20) setup_tg_bot ;;
            21) warp_menu ;;
            0)  echo -e "${DIM}Выход.${NC}"; exit 0 ;;
            *)  warn "Неверный ввод." ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════
# ─── VLESS + XTLS-REALITY ──────────────────────────────────
# ═══════════════════════════════════════════════════════════

REALITY_DIR="/etc/mtproxy/xray-reality"
REALITY_META="$REALITY_DIR/reality.meta"

xray_reality_install() {
    banner
    echo -e "${G}═══ УСТАНОВКА VLESS + XTLS-REALITY ═══${NC}\n"
    echo "Reality маскирует трафик под обычный HTTPS к реальному сайту."
    echo "Обходит DPI. Не нужен домен. Работает там где SOCKS5 блокируется."
    echo ""

    if docker ps -a --format "{{.Names}}" | grep -q "^xray-reality$"; then
        warn "Xray Reality уже установлен!"
        pause; return
    fi

    local REALITY_PORT
    echo -e "${C}Выберите порт:${NC}"
    echo "  1) 443  (рекомендуется — максимальная маскировка)"
    echo "  2) 8443"
    echo "  3) Свой порт"
    read -rp "  Выбор [1-3]: " rp
    case $rp in
        2) REALITY_PORT=8443 ;;
        3) read -rp "  Порт: " REALITY_PORT
           is_valid_port "$REALITY_PORT" || REALITY_PORT=443 ;;
        *) REALITY_PORT=443 ;;
    esac

    if ss -tlnp 2>/dev/null | grep -q ":${REALITY_PORT} "; then
        warn "Порт $REALITY_PORT уже занят!"
        read -rp "  Продолжить? [y/N] " force
        [[ "${force,,}" != "y" ]] && { pause; return; }
    fi

    # Выбор сайта-донора
    echo -e "\n${C}Выберите сайт-донор для маскировки:${NC}"
    echo "  1) www.microsoft.com  (рекомендуется)"
    echo "  2) www.apple.com"
    echo "  3) www.google.com"
    echo "  4) www.cloudflare.com"
    echo "  5) Свой домен"
    read -rp "  Выбор [1-5]: " sd
    local SERVER_NAME DEST
    case $sd in
        2) SERVER_NAME="www.apple.com";      DEST="www.apple.com:443" ;;
        3) SERVER_NAME="www.google.com";     DEST="www.google.com:443" ;;
        4) SERVER_NAME="www.cloudflare.com"; DEST="www.cloudflare.com:443" ;;
        5) read -rp "  Домен: " SERVER_NAME
           SERVER_NAME="${SERVER_NAME//[^a-zA-Z0-9._-]/}"
           is_valid_domain "$SERVER_NAME" || SERVER_NAME="www.microsoft.com"
           DEST="${SERVER_NAME}:443" ;;
        *) SERVER_NAME="www.microsoft.com";  DEST="www.microsoft.com:443" ;;
    esac

    mkdir -p "$REALITY_DIR"

    info "Загрузка образа Xray..."
    local XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"
    if ! docker pull "$XRAY_IMAGE" >/dev/null 2>&1; then
        XRAY_IMAGE="teddysun/xray"
        docker pull "$XRAY_IMAGE" >/dev/null 2>&1 || die "Не удалось загрузить образ Xray."
    fi
    success "Образ загружен: $XRAY_IMAGE"

    info "Генерация ключей x25519, UUID, shortId..."
    local X25519 PRIVATE_KEY PUBLIC_KEY UUID SHORT_ID
    X25519=$(docker run --rm "$XRAY_IMAGE" xray x25519 2>/dev/null)
    PRIVATE_KEY=$(echo "$X25519" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$X25519" | grep "Public key:" | awk '{print $3}')

    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        # Fallback для ghcr образа
        X25519=$(docker run --rm "$XRAY_IMAGE" x25519 2>/dev/null)
        PRIVATE_KEY=$(echo "$X25519" | grep -i "private" | awk '{print $NF}')
        PUBLIC_KEY=$(echo "$X25519" | grep -i "public" | awk '{print $NF}')
    fi

    [[ -z "$PRIVATE_KEY" ]] && die "Не удалось сгенерировать ключи. Проверь образ Xray."

    UUID=$(cat /proc/sys/kernel/random/uuid)
    SHORT_ID=$(openssl rand -hex 8)

    info "Создание конфига VLESS-Reality..."
    cat > "$REALITY_DIR/config.json" << XCONF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $REALITY_PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST",
          "xver": 0,
          "serverNames": ["$SERVER_NAME"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIP"}
    }
  ]
}
XCONF
    secure_file "$REALITY_DIR/config.json"

    # Проверяем JSON
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import json; json.load(open('$REALITY_DIR/config.json'))" 2>/dev/null; then
            die "Конфиг невалидный JSON."
        fi
    fi

    info "Запуск контейнера Xray Reality..."
    if [[ "$XRAY_IMAGE" == *"xtls"* ]]; then
        docker run -d \
            --name xray-reality \
            --restart unless-stopped \
            -p "$REALITY_PORT:$REALITY_PORT" \
            -v "$REALITY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$XRAY_IMAGE" \
            run -config /etc/xray/config.json >/dev/null 2>&1
    else
        docker run -d \
            --name xray-reality \
            --restart unless-stopped \
            -p "$REALITY_PORT:$REALITY_PORT" \
            -v "$REALITY_DIR:/etc/xray" \
            --log-opt max-size=10m \
            --log-opt max-file=3 \
            "$XRAY_IMAGE" \
            xray -config /etc/xray/config.json >/dev/null 2>&1
    fi

    sleep 2
    if ! docker ps --format "{{.Names}}" | grep -q "^xray-reality$"; then
        echo -e "${R}Логи:${NC}"
        docker logs xray-reality 2>&1 | tail -20
        docker rm xray-reality >/dev/null 2>&1
        die "Xray Reality не запустился."
    fi

    _firewall_open "$REALITY_PORT"
    echo "$REALITY_PORT|$UUID|$PUBLIC_KEY|$PRIVATE_KEY|$SHORT_ID|$SERVER_NAME" > "$REALITY_META"
    chmod 600 "$REALITY_META"
    log "VLESS-Reality установлен: порт=$REALITY_PORT donner=$SERVER_NAME"

    local IP
    IP=$(get_public_ip)
    local VLESS_LINK="vless://${UUID}@${IP}:${REALITY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SERVER_NAME}&sid=${SHORT_ID}&spx=%2F&flow=xtls-rprx-vision#Reality-${IP}"

    clear
    echo -e "${G}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${G}║     VLESS + Reality успешно установлен!     ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════╝${NC}\n"
    echo -e "  ${C}IP:${NC}           $IP"
    echo -e "  ${C}Порт:${NC}         $REALITY_PORT"
    echo -e "  ${C}UUID:${NC}         $UUID"
    echo -e "  ${C}Public Key:${NC}   $PUBLIC_KEY"
    echo -e "  ${C}Short ID:${NC}     $SHORT_ID"
    echo -e "  ${C}Сайт-донор:${NC}   $SERVER_NAME"
    echo -e "\n  ${W}VLESS ссылка (v2rayNG / Nekobox / Hiddify):${NC}"
    echo -e "  ${B}$VLESS_LINK${NC}"
    echo -e "\n  ${Y}QR-код:${NC}"
    qrencode -t ANSIUTF8 "$VLESS_LINK"
    echo -e "\n  ${W}Приложения для подключения:${NC}"
    echo -e "  Android: ${G}v2rayNG${NC} или ${G}Nekobox${NC}"
    echo -e "  iPhone:  ${G}Streisand${NC} или ${G}Shadowrocket${NC}"
    echo -e "  Windows: ${G}Hiddify${NC} или ${G}v2rayN${NC}"
    pause
}

xray_reality_status() {
    banner
    echo -e "${C}═══ СТАТУС VLESS-REALITY ═══${NC}\n"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-reality$"; then
        warn "Xray Reality не установлен."; pause; return
    fi

    local STATUS IP
    STATUS=$(docker inspect --format='{{.State.Status}}' xray-reality 2>/dev/null)
    IP=$(get_public_ip)
    local COLOR="${R}"; [[ "$STATUS" == "running" ]] && COLOR="${G}"

    echo -e "  ${W}Статус:${NC}  [${COLOR}${STATUS}${NC}]"

    if [[ -f "$REALITY_META" ]]; then
        local PORT UUID PK SID SN
        PORT=$(cut -d'|' -f1 "$REALITY_META")
        UUID=$(cut -d'|' -f2 "$REALITY_META")
        PK=$(cut -d'|' -f3 "$REALITY_META")
        SID=$(cut -d'|' -f5 "$REALITY_META")
        SN=$(cut -d'|' -f6 "$REALITY_META")
        local VLESS_LINK="vless://${UUID}@${IP}:${PORT}?type=tcp&security=reality&pbk=${PK}&fp=chrome&sni=${SN}&sid=${SID}&spx=%2F&flow=xtls-rprx-vision#Reality-${IP}"

        echo -e "  ${W}IP:${NC}      $IP"
        echo -e "  ${W}Порт:${NC}    $PORT"
        echo -e "  ${W}Донор:${NC}   $SN"
        echo -e "  ${W}UUID:${NC}    $UUID"
        echo -e "\n  ${B}$VLESS_LINK${NC}"
        echo -e "\n  ${Y}QR-код:${NC}"
        qrencode -t ANSIUTF8 "$VLESS_LINK"
    fi

    echo -e "\n${C}Трафик:${NC}"
    docker stats --no-stream --format \
        "  CPU: {{.CPUPerc}}  RAM: {{.MemUsage}}  NET: {{.NetIO}}" xray-reality 2>/dev/null
    echo -e "\n${C}Логи (20 строк):${NC}"
    docker logs --tail=20 xray-reality 2>&1
    pause
}

xray_reality_manage() {
    banner
    echo -e "${C}═══ УПРАВЛЕНИЕ VLESS-REALITY ═══${NC}\n"
    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-reality$"; then
        warn "Xray Reality не установлен."; pause; return
    fi
    local STATUS
    STATUS=$(docker inspect --format='{{.State.Status}}' xray-reality)
    local COL="${R}"; [[ "$STATUS" == "running" ]] && COL="${G}"
    echo -e "  Xray Reality [${COL}${STATUS}${NC}]\n"
    echo -e "  1) Start   2) Stop   3) Restart"
    read -rp "  Действие: " act
    case $act in
        1) docker start xray-reality >/dev/null && success "Запущен" ;;
        2) docker stop xray-reality >/dev/null && success "Остановлен" ;;
        3) docker restart xray-reality >/dev/null && success "Перезапущен" ;;
        *) warn "Неверный выбор" ;;
    esac
    log "Reality управление: $act"
    pause
}

xray_reality_delete() {
    banner
    echo -e "${R}═══ УДАЛЕНИЕ VLESS-REALITY ═══${NC}\n"
    if ! docker ps -a --format "{{.Names}}" | grep -q "^xray-reality$"; then
        warn "Xray Reality не установлен."; pause; return
    fi
    read -rp "  Удалить Xray Reality? [y/N] " confirm
    [[ "${confirm,,}" != "y" ]] && return

    local PORT=""
    [[ -f "$REALITY_META" ]] && PORT=$(cut -d'|' -f1 "$REALITY_META")

    docker stop xray-reality >/dev/null 2>&1
    docker rm xray-reality >/dev/null 2>&1
    rm -f "$REALITY_META"

    if [[ -n "$PORT" && "$PORT" =~ ^[0-9]+$ ]]; then
        read -rp "  Закрыть порт $PORT в firewall? [y/N] " fw
        [[ "${fw,,}" == "y" ]] && _firewall_close "$PORT"
    fi

    success "Xray Reality удалён."
    log "Xray Reality удалён"
    pause
}

xray_reality_menu() {
    while true; do
        banner
        echo -e "${W}  ── VLESS + XTLS-Reality (Anti-DPI) ──${NC}\n"
        echo -e "  ${G}1)${NC} Установить VLESS+Reality"
        echo -e "  ${C}2)${NC} Статус и ссылка/QR"
        echo -e "  ${Y}3)${NC} Start / Stop / Restart"
        echo -e "  ${R}4)${NC} Удалить"
        echo -e "  ${DIM}0)${NC} Назад\n"
        read -rp "  Пункт: " choice
        case $choice in
            1) xray_reality_install ;;
            2) xray_reality_status ;;
            3) xray_reality_manage ;;
            4) xray_reality_delete ;;
            0) return ;;
            *) warn "Неверный ввод." ;;
        esac
    done
}

run_bot_daemon() {
    [[ -f "$BOT_CONF" ]] || die "Конфиг бота не найден: $BOT_CONF"
    # shellcheck disable=SC1090
    source "$BOT_CONF"
    [[ -n "${BOT_TOKEN:-}" && -n "${BOT_ADMIN_ID:-}" ]] || die "BOT_TOKEN/BOT_ADMIN_ID не заданы в $BOT_CONF"
    echo $$ > "$BOT_PID_FILE"
    secure_file "$BOT_PID_FILE"
    trap 'rm -f "$BOT_PID_FILE"' EXIT
    _bot_loop "$BOT_TOKEN" "$BOT_ADMIN_ID"
}

main() {
    check_root
    check_os
    install_deps

    case "${1:-}" in
        --bot-daemon)
            run_bot_daemon
            ;;
        -h|--help)
            echo "Usage: mtproxy [--bot-daemon]"
            ;;
        "")
            main_menu
            ;;
        *)
            warn "Неизвестный аргумент: $1"
            echo "Usage: mtproxy [--bot-daemon]"
            exit 2
            ;;
    esac
}

main "$@"
