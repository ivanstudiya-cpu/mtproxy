"""
Сервис создания/удаления прокси на VPS через SSH.
Команды выполняются на удалённом Linux-сервере через Paramiko.
"""
import asyncio
import base64
import binascii
import json
import logging
import os
import posixpath
import re
import secrets
import shlex
from dataclasses import dataclass
from datetime import datetime

import paramiko

from config import config

logger = logging.getLogger(__name__)

SAFE_NAME_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")
SAFE_DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!.*\.\.)[a-zA-Z0-9]"
    r"(?:[a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])?)+$"
)
MTG_SECRET_RE = re.compile(r"^ee[0-9a-fA-F]{32,512}$")
CONFIG_DIR = "/etc/mtproxy"
PROXIES_CONF = f"{CONFIG_DIR}/proxies.conf"
XRAY_CONF = f"{CONFIG_DIR}/xray.conf"
XRAY_DIR = f"{CONFIG_DIR}/xray"
XRAY_CONFIG_PATH = f"{XRAY_DIR}/config.json"
XRAY_CONTAINER = "xray-proxy"
XRAY_IMAGE = "ghcr.io/xtls/xray-core:latest"
WG_CLIENTS_DIR = f"{CONFIG_DIR}/wg-clients"
TOKEN_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


@dataclass
class ProxyResult:
    success: bool
    proxy_type: str
    container_name: str | None = None
    client_name: str | None = None
    port: int | None = None
    secret: str | None = None
    tg_link: str | None = None
    config_data: dict | None = None
    error: str | None = None


class SSHClient:
    """Менеджер SSH соединения."""

    def connect(self) -> paramiko.SSHClient:
        client = paramiko.SSHClient()
        client.load_system_host_keys()

        if config.vps_known_hosts:
            known_hosts = os.path.expanduser(config.vps_known_hosts)
            if not os.path.exists(known_hosts):
                raise FileNotFoundError(f"Known hosts file not found: {known_hosts}")
            client.load_host_keys(known_hosts)

        client.set_missing_host_key_policy(paramiko.RejectPolicy())

        connect_kwargs = dict(
            hostname=config.vps_host,
            port=config.vps_port,
            username=config.vps_user,
            timeout=30,
            banner_timeout=30,
            auth_timeout=30,
        )
        if config.vps_key_path:
            connect_kwargs["key_filename"] = config.vps_key_path
            connect_kwargs["allow_agent"] = False
            connect_kwargs["look_for_keys"] = False
        elif config.vps_password:
            connect_kwargs["password"] = config.vps_password
            connect_kwargs["allow_agent"] = False
            connect_kwargs["look_for_keys"] = False
        else:
            connect_kwargs["allow_agent"] = True
            connect_kwargs["look_for_keys"] = True

        client.connect(**connect_kwargs)
        return client

    def exec(self, command: str) -> tuple[str, str, int]:
        """Выполняет команду, возвращает (stdout, stderr, exit_code)."""
        client = self.connect()
        try:
            _, stdout, stderr = client.exec_command(command, timeout=60)
            out = stdout.read().decode("utf-8", errors="replace").strip()
            err = stderr.read().decode("utf-8", errors="replace").strip()
            code = stdout.channel.recv_exit_status()
            return out, err, code
        finally:
            client.close()


ssh = SSHClient()


def _run(command: str) -> tuple[str, str, int]:
    return ssh.exec(command)


async def run_remote(command: str) -> tuple[str, str, int]:
    """Асинхронный вызов SSH команды через executor."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _run, command)


def _q(value: object) -> str:
    return shlex.quote(str(value))


def _now() -> str:
    return datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")


def _safe_name(user_id: int, suffix: str = "") -> str:
    name = f"u{int(user_id)}"
    if suffix:
        name += f"_{suffix}"
    return re.sub(r"[^a-zA-Z0-9_-]", "", name)[:32]


def _require_safe_name(value: str, field: str = "name") -> str:
    if not value or not SAFE_NAME_RE.fullmatch(value):
        raise ValueError(f"Unsafe {field}: {value!r}")
    return value


def _require_port(value: int | str, field: str = "port") -> int:
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Invalid {field}: {value!r}") from exc
    if port < 1 or port > 65535:
        raise ValueError(f"Invalid {field}: {port}")
    return port


def _require_domain(value: str) -> str:
    domain = value.strip().lower().rstrip(".")
    if not SAFE_DOMAIN_RE.fullmatch(domain):
        raise ValueError(f"Invalid domain: {value!r}")
    return domain


def _random_credential(length: int = 28) -> str:
    return "".join(secrets.choice(TOKEN_ALPHABET) for _ in range(length))


def _decode_config_field(value: str) -> str:
    if not value:
        return ""
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")
        if 0 < len(decoded) <= 128 and re.fullmatch(r"[a-zA-Z0-9_.@:-]+", decoded):
            return decoded
    except (UnicodeDecodeError, binascii.Error, ValueError):
        pass
    return value


def _remote_write_file_command(path: str, content: str, mode: str = "600") -> str:
    if not re.fullmatch(r"[0-7]{3,4}", mode):
        raise ValueError(f"Invalid file mode: {mode}")
    directory = posixpath.dirname(path)
    encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
    return (
        f"umask 077; mkdir -p {_q(directory)} && "
        f"printf %s {_q(encoded)} | base64 -d > {_q(path)} && "
        f"chmod {mode} {_q(path)}"
    )


def _remote_append_line_command(path: str, line: str, mode: str = "600") -> str:
    if not re.fullmatch(r"[0-7]{3,4}", mode):
        raise ValueError(f"Invalid file mode: {mode}")
    directory = posixpath.dirname(path)
    return (
        f"umask 077; mkdir -p {_q(directory)} && touch {_q(path)} && "
        f"chmod {mode} {_q(path)} && printf '%s\\n' {_q(line)} >> {_q(path)}"
    )


def _remote_append_text_command(path: str, text: str, mode: str = "600") -> str:
    if not re.fullmatch(r"[0-7]{3,4}", mode):
        raise ValueError(f"Invalid file mode: {mode}")
    directory = posixpath.dirname(path)
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    return (
        f"umask 077; mkdir -p {_q(directory)} && touch {_q(path)} && "
        f"chmod {mode} {_q(path)} && "
        f"printf %s {_q(encoded)} | base64 -d >> {_q(path)}"
    )


async def get_free_port(start: int = 10000, end: int = 59999) -> int:
    """Находит свободный порт на VPS."""
    start = _require_port(start, "start")
    end = _require_port(end, "end")
    if start > end:
        raise RuntimeError("Некорректный диапазон портов")

    out, _, _ = await run_remote(
        "ss -tlnp | awk '{print $4}' | grep -oE '[0-9]+$' | sort -n | uniq"
    )
    used = {int(line) for line in out.splitlines() if line.isdigit()}
    for port in range(start, end + 1):
        if port not in used:
            return port
    raise RuntimeError("Нет свободных портов")


# ─── MTProxy ────────────────────────────────────────────────

async def create_mtproxy(user_id: int, domain: str = "cloudflare.com") -> ProxyResult:
    """Создаёт MTProxy контейнер для пользователя."""
    try:
        domain = _require_domain(domain)
    except ValueError as exc:
        return ProxyResult(success=False, proxy_type="mtproxy", error=str(exc))

    client_name = _safe_name(user_id, "mt")
    container_name = _require_safe_name(f"mtproxy-{client_name}", "container_name")

    try:
        port = await get_free_port()
    except RuntimeError as exc:
        return ProxyResult(success=False, proxy_type="mtproxy", error=str(exc))

    secret_out, secret_err, secret_code = await run_remote(
        f"docker run --rm nineseconds/mtg:2 generate-secret --hex {_q(domain)}"
    )
    fake_tls_secret = secret_out.strip().splitlines()[-1] if secret_out.strip() else ""
    if secret_code != 0 or not MTG_SECRET_RE.fullmatch(fake_tls_secret):
        logger.error("MTProxy secret generation failed: %s", secret_err)
        return ProxyResult(
            success=False,
            proxy_type="mtproxy",
            error="Не удалось безопасно сгенерировать MTProxy secret.",
        )

    cmd = (
        f"docker run -d "
        f"--name {_q(container_name)} "
        f"--restart unless-stopped "
        f"-p {port}:{port} "
        f"--log-opt max-size=10m "
        f"--log-opt max-file=3 "
        f"nineseconds/mtg:2 "
        f"simple-run -n 1.1.1.1 -i prefer-ipv4 {_q(f'0.0.0.0:{port}')} {_q(fake_tls_secret)}"
    )

    _, err, code = await run_remote(cmd)

    if code != 0:
        logger.error("MTProxy create failed: %s", err)
        return ProxyResult(
            success=False,
            proxy_type="mtproxy",
            error=f"Docker error: {err[:200]}",
        )

    await run_remote(f"ufw allow {port}/tcp 2>/dev/null || true")

    tg_link = (
        f"https://t.me/proxy?server={config.vps_host}"
        f"&port={port}&secret={fake_tls_secret}"
    )

    line = f"{container_name}|{client_name}|{port}|{fake_tls_secret}|{domain}|{_now()}"
    await run_remote(_remote_append_line_command(PROXIES_CONF, line))

    logger.info("MTProxy created: %s port=%d", container_name, port)
    return ProxyResult(
        success=True,
        proxy_type="mtproxy",
        container_name=container_name,
        client_name=client_name,
        port=port,
        secret=fake_tls_secret,
        tg_link=tg_link,
        config_data={"domain": domain},
    )


async def delete_mtproxy(container_name: str, port: int | None = None) -> bool:
    """Останавливает и удаляет MTProxy контейнер."""
    container_name = _require_safe_name(container_name, "container_name")
    await run_remote(f"docker rm -f {_q(container_name)} 2>/dev/null || true")
    if port:
        safe_port = _require_port(port)
        await run_remote(f"ufw delete allow {safe_port}/tcp 2>/dev/null || true")
    await run_remote(
        f"sed -i {_q(f'/^{container_name}|/d')} {_q(PROXIES_CONF)} 2>/dev/null || true"
    )
    logger.info("MTProxy deleted: %s", container_name)
    return True


# ─── Xray SOCKS5/HTTP ───────────────────────────────────────

def _xray_result_from_conf(socks_port: int, http_port: int, user: str, password: str) -> ProxyResult:
    data = {
        "socks_port": socks_port,
        "http_port": http_port,
        "host": config.vps_host,
        "auth": "password" if user and password else "missing",
    }
    if user and password:
        data["user"] = user
        data["password"] = password

    return ProxyResult(
        success=True,
        proxy_type="xray",
        container_name=XRAY_CONTAINER,
        port=socks_port,
        config_data=data,
    )


async def _read_existing_xray_config() -> tuple[ProxyResult | None, list[int]]:
    conf_out, _, _ = await run_remote(f"cat {_q(XRAY_CONF)} 2>/dev/null")
    if not conf_out:
        return None, []

    parts = conf_out.strip().split("|")
    if len(parts) < 2:
        return None, []

    try:
        socks_port = _require_port(parts[0], "socks_port")
        http_port = _require_port(parts[1], "http_port")
    except ValueError:
        return None, []

    user = _decode_config_field(parts[2]) if len(parts) > 2 else ""
    password = _decode_config_field(parts[3]) if len(parts) > 3 else ""
    return _xray_result_from_conf(socks_port, http_port, user, password), [socks_port, http_port]


async def _remove_existing_xray(ports: list[int]) -> None:
    await run_remote(f"docker rm -f {_q(XRAY_CONTAINER)} 2>/dev/null || true")
    for port in ports:
        await run_remote(f"ufw delete allow {port}/tcp 2>/dev/null || true")


async def create_xray(user_id: int) -> ProxyResult:
    """Создаёт безопасный Xray SOCKS5/HTTP инстанс или возвращает существующий."""
    out, _, _ = await run_remote("docker ps -a --format '{{.Names}}' | grep -x xray-proxy")
    if out.strip() == XRAY_CONTAINER:
        existing, existing_ports = await _read_existing_xray_config()
        if existing and existing.config_data and existing.config_data.get("user") and existing.config_data.get("password"):
            return existing

        logger.warning("Existing Xray has no credentials; recreating secure instance")
        await _remove_existing_xray(existing_ports)

    try:
        socks_port = await get_free_port(8400, 8500)
        http_port = await get_free_port(socks_port + 1, 8501)
    except RuntimeError as exc:
        return ProxyResult(success=False, proxy_type="xray", error=str(exc))

    xuser = _safe_name(user_id, "xr")
    xpass = _random_credential()
    account = {"user": xuser, "pass": xpass}
    xray_config = {
        "log": {"loglevel": "warning"},
        "dns": {"servers": ["8.8.8.8", "1.1.1.1", "8.8.4.4"]},
        "inbounds": [
            {
                "port": socks_port,
                "listen": "0.0.0.0",
                "protocol": "socks",
                "tag": "socks-in",
                "settings": {
                    "auth": "password",
                    "accounts": [account],
                    "udp": True,
                    "ip": "0.0.0.0",
                },
            },
            {
                "port": http_port,
                "listen": "0.0.0.0",
                "protocol": "http",
                "tag": "http-in",
                "settings": {
                    "accounts": [account],
                    "allowTransparent": True,
                },
            },
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {"domainStrategy": "UseIP"},
            }
        ],
    }
    config_text = json.dumps(xray_config, ensure_ascii=False, indent=2)

    _, err, code = await run_remote(_remote_write_file_command(XRAY_CONFIG_PATH, config_text))
    if code != 0:
        return ProxyResult(success=False, proxy_type="xray", error=err[:200])

    cmd = (
        f"docker run -d "
        f"--name {_q(XRAY_CONTAINER)} "
        f"--restart unless-stopped "
        f"-p {socks_port}:{socks_port} "
        f"-p {http_port}:{http_port} "
        f"-v {_q(f'{XRAY_DIR}:/etc/xray')} "
        f"--log-opt max-size=10m "
        f"--log-opt max-file=3 "
        f"{XRAY_IMAGE} "
        f"run -config /etc/xray/config.json"
    )

    _, err, code = await run_remote(cmd)
    if code != 0:
        return ProxyResult(success=False, proxy_type="xray", error=err[:200])

    await run_remote(f"ufw allow {socks_port}/tcp 2>/dev/null || true")
    await run_remote(f"ufw allow {http_port}/tcp 2>/dev/null || true")

    line = f"{socks_port}|{http_port}|{xuser}|{xpass}|{_now()}"
    await run_remote(_remote_write_file_command(XRAY_CONF, line + "\n"))

    logger.info("Xray created: ports=%d/%d auth=password", socks_port, http_port)
    return _xray_result_from_conf(socks_port, http_port, xuser, xpass)


# ─── WireGuard ──────────────────────────────────────────────

async def create_wireguard_client(user_id: int) -> ProxyResult:
    """Добавляет WireGuard клиента и возвращает конфиг + QR."""
    client_name = _safe_name(user_id, "wg")
    conf_path = f"{WG_CLIENTS_DIR}/{client_name}.conf"

    out, _, code = await run_remote("command -v wg")
    if code != 0:
        return ProxyResult(
            success=False,
            proxy_type="wireguard",
            error="WireGuard не установлен на сервере. Установи через mtproxy меню 20→1.",
        )

    out, _, _ = await run_remote(f"test -f {_q(conf_path)} && cat {_q(conf_path)} 2>/dev/null")
    if out:
        qr, _, _ = await run_remote(f"qrencode -t UTF8 < {_q(conf_path)}")
        return ProxyResult(
            success=True,
            proxy_type="wireguard",
            client_name=client_name,
            config_data={"config": out, "qr": qr},
        )

    meta, _, _ = await run_remote(f"cat {_q(f'{WG_CLIENTS_DIR}/server.meta')} 2>/dev/null")
    if not meta:
        return ProxyResult(
            success=False,
            proxy_type="wireguard",
            error="Метаданные сервера не найдены. Переустанови WireGuard.",
        )

    parts = meta.strip().split("|")
    if len(parts) < 3:
        return ProxyResult(
            success=False,
            proxy_type="wireguard",
            error="Метаданные WireGuard повреждены.",
        )
    server_pubkey, server_ip, wg_port_raw = parts[0], parts[1], parts[2]
    try:
        wg_port = _require_port(wg_port_raw, "wg_port")
    except ValueError as exc:
        return ProxyResult(success=False, proxy_type="wireguard", error=str(exc))

    last_ip_out, _, _ = await run_remote(
        f"grep -h '^Address' {_q(WG_CLIENTS_DIR)}/*.conf 2>/dev/null "
        f"| grep -oE '10\\.8\\.0\\.[0-9]+' | sort -t. -k4 -n | tail -1 | cut -d. -f4"
    )
    last_ip = int(last_ip_out.strip()) if last_ip_out.strip().isdigit() else 1
    client_ip = f"10.8.0.{last_ip + 1}"

    privkey_out, _, _ = await run_remote("wg genkey")
    privkey = privkey_out.strip()
    pubkey_out, _, _ = await run_remote(f"printf %s {_q(privkey)} | wg pubkey")
    pubkey = pubkey_out.strip()

    client_conf = (
        f"[Interface]\n"
        f"PrivateKey = {privkey}\n"
        f"Address = {client_ip}/24\n"
        f"DNS = 8.8.8.8, 1.1.1.1\n\n"
        f"[Peer]\n"
        f"PublicKey = {server_pubkey}\n"
        f"Endpoint = {server_ip}:{wg_port}\n"
        f"AllowedIPs = 0.0.0.0/0\n"
        f"PersistentKeepalive = 25\n"
    )

    _, err, code = await run_remote(_remote_write_file_command(conf_path, client_conf))
    if code != 0:
        return ProxyResult(success=False, proxy_type="wireguard", error=err[:200])

    await run_remote(f"wg set wg0 peer {_q(pubkey)} allowed-ips {_q(f'{client_ip}/32')}")
    peer_block = (
        f"\n# Client: {client_name}\n"
        f"[Peer]\n"
        f"PublicKey = {pubkey}\n"
        f"AllowedIPs = {client_ip}/32\n"
    )
    await run_remote(_remote_append_text_command("/etc/wireguard/wg0.conf", peer_block))

    qr_out, _, _ = await run_remote(f"qrencode -t UTF8 < {_q(conf_path)}")

    logger.info("WG client created: %s ip=%s", client_name, client_ip)
    return ProxyResult(
        success=True,
        proxy_type="wireguard",
        client_name=client_name,
        config_data={
            "config": client_conf,
            "qr": qr_out,
            "client_ip": client_ip,
            "wg_port": wg_port,
        },
    )


async def delete_wireguard_client(client_name: str) -> bool:
    """Удаляет WireGuard клиента."""
    client_name = _require_safe_name(client_name, "client_name")
    conf_path = f"{WG_CLIENTS_DIR}/{client_name}.conf"

    privkey_out, _, _ = await run_remote(
        f"grep '^PrivateKey' {_q(conf_path)} 2>/dev/null | cut -d= -f2- | tr -d ' '"
    )
    if privkey_out.strip():
        pubkey_out, _, _ = await run_remote(f"printf %s {_q(privkey_out.strip())} | wg pubkey")
        pubkey = pubkey_out.strip()
        await run_remote(f"wg set wg0 peer {_q(pubkey)} remove 2>/dev/null || true")
        await run_remote(
            f"sed -i {_q(f'/# Client: {client_name}/,/^$/d')} /etc/wireguard/wg0.conf 2>/dev/null || true"
        )

    await run_remote(f"rm -f {_q(conf_path)}")
    logger.info("WG client deleted: %s", client_name)
    return True


async def check_proxy_alive(container_name: str) -> bool:
    """Проверяет работает ли docker контейнер."""
    container_name = _require_safe_name(container_name, "container_name")
    out, _, _ = await run_remote(
        f"docker inspect -f '{{{{.State.Running}}}}' {_q(container_name)} 2>/dev/null"
    )
    return out.strip().lower() == "true"
