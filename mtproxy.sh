#!/bin/bash
# ============================================================
#  mtproxy — Telegram MTProxy Manager с Fake TLS
#  Версия: 2.0
# ============================================================

BINARY_PATH="/usr/local/bin/mtproxy"
BACKUP_DIR="/etc/mtproxy/backups"
LOG_FILE="/var/log/mtproxy.log"
CONFIG_DIR="/etc/mtproxy"
CONFIG_FILE="$CONFIG_DIR/proxies.conf"

# --- ЦВЕТА ---
R='\033[0;31m'   # red
G='\033[0;32m'   # green
C='\033[0;36m'   # cyan
Y='\033[1;33m'   # yellow
M='\033[0;35m'   # magenta
B='\033[0;34m'   # blue
W='\033[1;37m'   # white
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
  ║          MTProxy Manager v2.0  (Fake TLS)           ║
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

    # Docker
    if ! command -v docker &>/dev/null; then
        info "Установка Docker..."
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
        systemctl enable --now docker >/dev/null 2>&1
        success "Docker установлен."
    fi

    # qrencode
    if ! command -v qrencode &>/dev/null; then
        info "Установка qrencode..."
        if [[ $PKG_MANAGER == "apt" ]]; then
            apt-get update -qq >/dev/null 2>&1
        fi
        pkg_install qrencode
    fi

    # jq (для удобного парсинга docker inspect)
    if ! command -v jq &>/dev/null; then
        pkg_install jq
    fi

    # Создаём директории и файлы
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$CONFIG_FILE" "$LOG_FILE"

    # Устанавливаем себя как команду
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

# Домены разбиты по категориям для удобного выбора
declare -A DOMAIN_CATEGORIES
DOMAIN_CATEGORIES["🌍 Международные (Tech)"]="google.com cloudflare.com microsoft.com apple.com amazon.com github.com stackoverflow.com gitlab.com"
DOMAIN_CATEGORIES["🌍 Международные (СМИ)"]="wikipedia.org bbc.com cnn.com reuters.com nytimes.com theguardian.com bloomberg.com forbes.com"
DOMAIN_CATEGORIES["🌍 Международные (Развлечения)"]="netflix.com twitch.tv discord.com zoom.us spotify.com reddit.com medium.com tumblr.com"
DOMAIN_CATEGORIES["🌍 Международные (Образование)"]="coursera.org udemy.com khanacademy.org edx.org duolingo.com ted.com skillshare.com"
DOMAIN_CATEGORIES["🇷🇺 Российские (СМИ)"]="lenta.ru rbc.ru ria.ru kommersant.ru vedomosti.ru iz.ru novayagazeta.ru meduza.io"
DOMAIN_CATEGORIES["🇷🇺 Российские (Tech/IT)"]="habr.com mail.ru yandex.ru vk.com 2ch.hk pikabu.ru 4pda.to 3dnews.ru"
DOMAIN_CATEGORIES["🇷🇺 Российские (Образование)"]="stepik.org geekbrains.ru skillbox.ru hexlet.io netology.ru skillFactory.ru"
DOMAIN_CATEGORIES["🇷🇺 Российские (Сервисы)"]="gosuslugi.ru sberbank.ru tinkoff.ru avito.ru ozon.ru wildberries.ru kinopoisk.ru ivi.ru"

# Плоский массив для нумерации
DOMAINS=()
DOMAIN_LABELS=()

_build_domain_list() {
    local order=(
        "🌍 Международные (Tech)"
        "🌍 Международные (СМИ)"
        "🌍 Международные (Развлечения)"
        "🌍 Международные (Образование)"
        "🇷🇺 Российские (СМИ)"
        "🇷🇺 Российские (Tech/IT)"
        "🇷🇺 Российские (Образование)"
        "🇷🇺 Российские (Сервисы)"
    )
    DOMAINS=()
    DOMAIN_LABELS=()
    for cat in "${order[@]}"; do
        for d in ${DOMAIN_CATEGORIES["$cat"]}; do
            DOMAINS+=("$d")
            DOMAIN_LABELS+=("$cat")
        done
    done
}

choose_domain() {
    _build_domain_list

    local order=(
        "🌍 Международные (Tech)"
        "🌍 Международные (СМИ)"
        "🌍 Международные (Развлечения)"
        "🌍 Международные (Образование)"
        "🇷🇺 Российские (СМИ)"
        "🇷🇺 Российские (Tech/IT)"
        "🇷🇺 Российские (Образование)"
        "🇷🇺 Российские (Сервисы)"
    )

    echo -e "\n${C}Выберите домен для Fake TLS маскировки:${NC}\n"

    local idx=0
    for cat in "${order[@]}"; do
        echo -e "${W}── ${cat} ──${NC}"
        for d in ${DOMAIN_CATEGORIES["$cat"]}; do
            idx=$((idx+1))
            printf "  ${Y}%3d)${NC} %-25s" "$idx" "$d"
            [[ $((idx % 3)) -eq 0 ]] && echo ""
        done
        echo -e "\n"
    done

    echo -e "${DIM}  0) Ввести свой домен${NC}\n"

    local choice
    read -rp "Выбор [0-${#DOMAINS[@]}]: " choice

    if [[ "$choice" -eq 0 ]]; then
        read -rp "Введите домен: " CHOSEN_DOMAIN
    elif [[ "$choice" -ge 1 && "$choice" -le "${#DOMAINS[@]}" ]]; then
        CHOSEN_DOMAIN="${DOMAINS[$((choice-1))]}"
    else
        warn "Некорректный выбор, используется google.com"
        CHOSEN_DOMAIN="google.com"
    fi

    CHOSEN_DOMAIN="${CHOSEN_DOMAIN:-google.com}"
    echo -e "${G}Домен: $CHOSEN_DOMAIN${NC}"
}

choose_port() {
    echo -e "\n${C}Выберите порт:${NC}"
    echo "  1) 443   (рекомендуется — HTTPS)"
    echo "  2) 8443"
    echo "  3) 3128"
    echo "  4) Свой порт"
    read -rp "Выбор [1-4]: " pc

    case $pc in
        2) CHOSEN_PORT=8443 ;;
        3) CHOSEN_PORT=3128 ;;
        4)
            read -rp "Порт: " CHOSEN_PORT
            [[ "$CHOSEN_PORT" =~ ^[0-9]+$ ]] || { warn "Некорректный порт, используется 443."; CHOSEN_PORT=443; }
            ;;
        *) CHOSEN_PORT=443 ;;
    esac

    if port_in_use "$CHOSEN_PORT"; then
        warn "Порт $CHOSEN_PORT уже занят!"
        read -rp "Принудительно использовать? [y/N] " force
        [[ "${force,,}" != "y" ]] && return 1
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

    local EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        die "Контейнер не запустился (exit $EXIT_CODE)."
    fi

    # Сохраняем конфиг
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
    echo -e "\n  ${B}tg:// ссылка:${NC}"
    echo -e "  $LINK"
    echo -e "\n  ${B}HTTPS ссылка:${NC}"
    echo -e "  $HTTPS_LINK"
    echo -e "\n  ${Y}QR-код (tg://):${NC}"
    qrencode -t ANSIUTF8 "$LINK"

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
        # Читаем домен из нашего конфига
        if grep -q "^$CONTAINER|" "$CONFIG_FILE" 2>/dev/null; then
            DOMAIN=$(grep "^$CONTAINER|" "$CONFIG_FILE" | cut -d'|' -f5)
        fi

        local CREATED
        CREATED=$(docker inspect --format='{{.Created}}' "$CONTAINER" 2>/dev/null | cut -dT -f1)

        local LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

        echo -e "${W}┌─ $CONTAINER${NC}  [${COLOR}${STATUS}${NC}]  создан: $CREATED"
        echo -e "${W}│${NC}  Домен: ${C}$DOMAIN${NC}  |  IP: $IP  |  Порт: ${Y}$PORT${NC}"
        echo -e "${W}│${NC}  Secret: ${DIM}$SECRET${NC}"
        echo -e "${W}│${NC}  Link:   ${B}$LINK${NC}"
        echo -e "${W}└──────────────────────────────────────────${NC}"
        echo ""
    done

    pause
}

# ─── ДЕТАЛЬНЫЙ ПРОСМОТР ─────────────────────────────────────

show_detail() {
    banner
    echo -e "${C}Введите ID клиента (или часть имени контейнера):${NC}"
    read -rp "> " CLIENT_ID

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
    warn "Все текущие соединения будут разорваны. Клиентам нужно будет переподключиться."
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

    # Бэкап старой строки
    mkdir -p "$BACKUP_DIR"
    local BFILE="$BACKUP_DIR/${CONTAINER}_$(date +%Y%m%d_%H%M%S).bak"
    grep "^$CONTAINER|" "$CONFIG_FILE" > "$BFILE" 2>/dev/null
    success "Резервная копия: $BFILE"

    info "Генерация нового секрета..."
    local NEW_SECRET
    NEW_SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN" 2>/dev/null)

    info "Пересоздание контейнера..."
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

    # Обновляем конфиг
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
    echo -e "${C}═══ СЕТЕВОЙ ТРАФИК ═══${NC}\n"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
        | grep -E "NAME|mtproto-"
    pause
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

    # Бэкап перед удалением
    mkdir -p "$BACKUP_DIR"
    grep "^$CONTAINER|" "$CONFIG_FILE" > "$BACKUP_DIR/${CONTAINER}_deleted_$(date +%Y%m%d_%H%M%S).bak" 2>/dev/null

    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm "$CONTAINER" >/dev/null 2>&1
    sed -i "/^$CONTAINER|/d" "$CONFIG_FILE"

    success "Удалён: $CONTAINER"
    log "Удалён: $CONTAINER"
    pause
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

    rm -f "$BINARY_PATH"
    success "Скрипт удалён. Конфиги и бэкапы сохранены в $CONFIG_DIR"
    log "Полное удаление выполнено."
    exit 0
}

# ─── ГЛАВНОЕ МЕНЮ ───────────────────────────────────────────

main_menu() {
    while true; do
        banner
        echo -e "  ${G}1)${NC} Добавить новый прокси"
        echo -e "  ${C}2)${NC} Список всех прокси"
        echo -e "  ${C}3)${NC} Детали / QR по клиенту"
        echo -e "  ${C}4)${NC} Статус и трафик"
        echo -e "  ${Y}5)${NC} Start / Stop / Restart"
        echo -e "  ${Y}6)${NC} Обновить секрет (rotate)"
        echo -e "  ${R}7)${NC} Удалить прокси"
        echo -e "  ${DIM}8)${NC} Просмотр лога"
        echo -e "  ${R}9)${NC} Полное удаление"
        echo -e "  ${DIM}0)${NC} Выход\n"

        read -rp "  Пункт: " choice
        case $choice in
            1) menu_add ;;
            2) show_list ;;
            3) show_detail ;;
            4) show_status ;;
            5) manage_proxy ;;
            6) rotate_secret ;;
            7) delete_proxy ;;
            8) show_log ;;
            9) full_uninstall ;;
            0) echo -e "${DIM}Выход.${NC}"; exit 0 ;;
            *) warn "Неверный ввод." ;;
        esac
    done
}

# ─── ТОЧКА ВХОДА ────────────────────────────────────────────

check_root
check_os
install_deps
main_menu
