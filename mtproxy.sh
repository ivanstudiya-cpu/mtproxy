#!/bin/bash
# ============================================================
#  mtproxy — Telegram MTProxy Manager с Fake TLS
#  Версия: 3.0
#  GitHub: https://github.com/ivanstudiya-cpu/mtproxy
# ============================================================

BINARY_PATH="/usr/local/bin/mtproxy"
BACKUP_DIR="/etc/mtproxy/backups"
LOG_FILE="/var/log/mtproxy.log"
CONFIG_DIR="/etc/mtproxy"
CONFIG_FILE="$CONFIG_DIR/proxies.conf"
EXPORT_FILE="$CONFIG_DIR/export_links.txt"
CRON_TAG="# mtproxy-auto"
GITHUB_RAW="https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh"
VERSION="3.0"

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
  ║        MTProxy Manager v3.0  (Fake TLS)             ║
  ╚══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

pause() { read -rp $'\nНажмите Enter...' _; }

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
    case $PKG_MANAGER in
        apt) apt-get install -y "$@" -qq >/dev/null 2>&1 ;;
        yum) yum install -y "$@" >/dev/null 2>&1 ;;
        dnf) dnf install -y "$@" >/dev/null 2>&1 ;;
    esac
}

install_deps() {
    info "Проверка зависимостей..."

    if ! command -v docker &>/dev/null; then
        info "Установка Docker..."
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
        systemctl enable --now docker >/dev/null 2>&1
        success "Docker установлен."
    fi

    if ! command -v qrencode &>/dev/null; then
        info "Установка qrencode..."
        [[ $PKG_MANAGER == "apt" ]] && apt-get update -qq >/dev/null 2>&1
        pkg_install qrencode
    fi

    if ! command -v jq &>/dev/null; then
        pkg_install jq
    fi

    if ! command -v curl &>/dev/null; then
        pkg_install curl
    fi

    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$CONFIG_FILE" "$LOG_FILE"

    if [[ ! -f "$BINARY_PATH" || "$(realpath "$0")" != "$BINARY_PATH" ]]; then
        cp "$0" "$BINARY_PATH"
        chmod +x "$BINARY_PATH"
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

port_in_use() {
    ss -tlnp | grep -q ":$1 "
}

# ─── ДОМЕНЫ ─────────────────────────────────────────────────

# Категории: параллельные массивы меток и доменов
CAT_LABELS=(
    "[Int] Tech"
    "[Int] SMI"
    "[Int] Entertainment"
    "[Int] Education"
    "[RU]  SMI"
    "[RU]  Tech/IT"
    "[RU]  Education"
    "[RU]  Services"
)

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
            [[ "$CHOSEN_PORT" =~ ^[0-9]+$ ]] || { warn "Некорректный порт, используется 443."; CHOSEN_PORT=443; }
            ;;
        *)
            warn "Неверный выбор, используется 443."
            CHOSEN_PORT=443
            ;;
    esac

    info "Выбран порт: $CHOSEN_PORT"

    # Проверка — занят другим процессом (не нашим контейнером)?
    if ss -tlnp 2>/dev/null | grep -q ":${CHOSEN_PORT} "; then
        local our=0
        mapfile -t _running < <(docker ps --format "{{.Names}}" 2>/dev/null | grep "^mtproto-")
        for c in "${_running[@]}"; do
            local cp
            cp=$(docker inspect "$c" \
                --format='{{range $p,$cc := .HostConfig.PortBindings}}{{(index $cc 0).HostPort}}{{end}}' 2>/dev/null)
            [[ "$cp" == "$CHOSEN_PORT" ]] && our=1 && break
        done
        if [[ $our -eq 0 ]]; then
            warn "Порт $CHOSEN_PORT занят сторонним процессом!"
            read -rp "  Принудительно использовать? [y/N] " force
            [[ "${force,,}" != "y" ]] && return 1
        else
            warn "Порт $CHOSEN_PORT уже используется другим mtproxy!"
            read -rp "  Всё равно использовать? [y/N] " force
            [[ "${force,,}" != "y" ]] && return 1
        fi
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

    if [[ $? -ne 0 ]]; then
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
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow "$port"/tcp >/dev/null 2>&1
        success "UFW: порт $port открыт."
        log "UFW: открыт порт $port"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        success "firewalld: порт $port открыт."
        log "firewalld: открыт порт $port"
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        success "iptables: порт $port открыт."
        log "iptables: открыт порт $port"
    fi
}

_firewall_close() {
    local port="$1"
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
            local CONTAINER="${containers[$((IDX-1))]}"
            local PORT
            PORT=$(docker inspect "$CONTAINER" \
                --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' 2>/dev/null)
            [[ $fc -eq 1 ]] && _firewall_open "$PORT" || _firewall_close "$PORT"
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
    local CONTAINER="mtproto-$CLIENT_ID"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER$"; then
        warn "Контейнер '$CONTAINER' не найден."; pause; return
    fi

    local PORT DOMAIN
    PORT=$(docker inspect "$CONTAINER" \
        --format='{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}')
    DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f5 || echo "google.com")

    local BFILE="$BACKUP_DIR/${CONTAINER}_$(date +%Y%m%d_%H%M%S).bak"
    grep "^$CONTAINER|" "$CONFIG_FILE" > "$BFILE" 2>/dev/null
    success "Резервная копия: $BFILE"

    info "Генерация нового секрета..."
    local NEW_SECRET
    NEW_SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN" 2>/dev/null)

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
            ACTIVE=$(ss -tn | grep ":$PORT " | grep ESTAB | wc -l)
            echo -e "  ${W}$CONTAINER${NC}: ${G}$ACTIVE${NC} активных соединений (ESTAB)"
        fi
    done
}

# ─── УПРАВЛЕНИЕ ─────────────────────────────────────────────

manage_proxy() {
    banner
    echo -e "${C}Управление (start/stop/restart):${NC}"
    mapfile -t containers < <(docker ps -a --format "{{.Names}}" | grep "^mtproto-")

    for i in "${!containers[@]}"; do
        local s
        s=$(docker inspect --format='{{.State.Status}}' "${containers[$i]}")
        local col="${R}"
        [[ "$s" == "running" ]] && col="${G}"
        echo -e "  ${Y}$((i+1)))${NC} ${containers[$i]} [${col}${s}${NC}]"
    done

    echo ""
    read -rp "Номер контейнера: " IDX
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
    [[ "$IDX" -eq 0 ]] && return

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

    local MIGRATION_FILE="$CONFIG_DIR/migration_$(date +%Y%m%d_%H%M%S).sh"
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

    chmod +x "$MIGRATION_FILE"
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
            chmod +x /etc/mtproxy/healthcheck.sh

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
            chmod +x /etc/mtproxy/auto_rotate.sh

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
            chmod +x /etc/mtproxy/healthcheck.sh

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

    local TMP="/tmp/mtproxy_new.sh"
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
    chmod +x "$BINARY_PATH"
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
    [[ -n "$ids" ]] && docker stop $ids >/dev/null 2>&1 && docker rm $ids >/dev/null 2>&1

    crontab -l 2>/dev/null | grep -v "$CRON_TAG" | grep -v "auto_rotate" | crontab -
    rm -f "$BINARY_PATH"

    success "Скрипт удалён. Конфиги и бэкапы сохранены в $CONFIG_DIR"
    log "Полное удаление выполнено."
    exit 0
}

# ─── ГЛАВНОЕ МЕНЮ ───────────────────────────────────────────

main_menu() {
    while true; do
        banner
        echo -e "  ${G}1)${NC}  Добавить новый прокси"
        echo -e "  ${C}2)${NC}  Список всех прокси"
        echo -e "  ${C}3)${NC}  Детали / QR по клиенту"
        echo -e "  ${C}4)${NC}  Статус, трафик и подключения"
        echo -e "  ${Y}5)${NC}  Start / Stop / Restart"
        echo -e "  ${Y}6)${NC}  Обновить секрет (rotate)"
        echo -e "  ${G}7)${NC}  Экспорт всех ссылок в файл"
        echo -e "  ${G}8)${NC}  Миграция на новый сервер"
        echo -e "  ${C}9)${NC}  Firewall — управление портами"
        echo -e "  ${M}10)${NC} Healthcheck / Автоперезапуск"
        echo -e "  ${M}11)${NC} Авто-обновление секрета (cron)"
        echo -e "  ${M}12)${NC} Уведомления в Telegram"
        echo -e "  ${B}13)${NC} Обновить скрипт"
        echo -e "  ${DIM}14)${NC} Просмотр лога"
        echo -e "  ${R}15)${NC} Удалить прокси"
        echo -e "  ${R}16)${NC} Полное удаление"
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
            9)  firewall_menu ;;
            10) setup_healthcheck ;;
            11) setup_auto_rotate ;;
            12) setup_tg_notify ;;
            13) self_update ;;
            14) show_log ;;
            15) delete_proxy ;;
            16) full_uninstall ;;
            0)  echo -e "${DIM}Выход.${NC}"; exit 0 ;;
            *)  warn "Неверный ввод." ;;
        esac
    done
}

# ─── ТОЧКА ВХОДА ────────────────────────────────────────────

check_root
check_os
install_deps
main_menu
