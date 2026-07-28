#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Completo v2.1.2 — Julho de 2026
#  Ubuntu 22.04 / 24.04 LTS — Uso: sudo bash install.sh
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly INSTALLER_VERSION="2.1.2"
readonly INSTALL_DIR="/opt/ad-license-manager"
readonly INSTALL_LOG="/tmp/admanager-install-$(date +%Y%m%d-%H%M%S).log"
readonly INSTALL_START=$(date +%s)
readonly REPO_URL="${REPO_URL:-https://github.com/sua-org/ad-license-manager.git}"
readonly SERVICE_USER="admanager"
readonly REQUIRED_RAM_GB=4
readonly REQUIRED_DISK_GB=15

APP_DOMAIN="" AD_URL="" AD_BASE_DN="" AD_USERNAME="" AD_PASSWORD="" AD_DOMAIN=""
AD_HOST="" AD_PORT="" AZURE_TENANT_ID="" AZURE_CLIENT_ID="" AZURE_CLIENT_SECRET=""
ADMIN_USER="admin" ADMIN_PASSWORD="" ADMIN_EMAIL=""
SMTP_HOST="" SMTP_PORT="587" SMTP_SECURE="false" SMTP_USER="" SMTP_PASS="" SMTP_FROM=""
TEAMS_WEBHOOK_URL="" DB_PASSWORD="" REDIS_PASSWORD=""
JWT_SECRET="" JWT_REFRESH_SECRET="" ENCRYPTION_KEY=""
SETUP_SMTP="n" SETUP_TEAMS="n" SETUP_GRAPH="n"
CERT_OPCAO="3" SERVER_IP="" UBUNTU_VERSION="" UBUNTU_CODENAME="jammy"

RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';   MAGENTA='\033[0;35m'
WHITE='\033[1;37m';BOLD='\033[1m';      DIM='\033[2m'; NC='\033[0m'

touch "$INSTALL_LOG"; chmod 600 "$INSTALL_LOG"
q() { "$@" >> "$INSTALL_LOG" 2>&1; }

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════════╗"
  echo "  ║      AD License Manager — Instalador Autônomo v${INSTALLER_VERSION}            ║"
  echo "  ║      Ubuntu Server 22.04 LTS / 24.04 LTS — Julho de 2026          ║"
  echo "  ╚══════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

step()    { echo ""; echo -e "${CYAN}${BOLD}━━ ETAPA $1 — $2${NC}"; echo ""; }
ok()      { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()    { echo -e "  ${DIM}ℹ  $1${NC}"; }
sub()     { echo -e "  ${BLUE}▸${NC} $1"; }
div()     { echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"; }
pg()      { echo -ne "  ${BLUE}▸${NC} $1..."; }
pg_ok()   { echo -e " ${GREEN}OK${NC}"; }
pg_fail() { echo -e " ${RED}FALHOU${NC}"; }

fail() {
  echo ""
  echo -e "  ${RED}${BOLD}✗  ERRO CRÍTICO: $1${NC}"
  echo -e "  ${DIM}Log: ${INSTALL_LOG}${NC}"
  echo ""; exit 1
}

# ─── _trim — remove \r, espaços e códigos ANSI ───────────────────────────────
_trim() {
  local v="$1"
  v="${v//$'\r'/}"
  # Remove códigos ANSI de cor (ex: \033[0m \033[1;37m \033[2m)
  # que o SSH Windows ecoa de volta junto com o prompt
  v=$(printf '%s' "$v" | sed 's/\x1b|$$[0-9;]*[mK]//g' 2>/dev/null || printf '%s' "$v")
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

# ─── ask — lê entrada do usuário ─────────────────────────────────────────────
ask() {
  local label="$1" default="${2:-}"
  if [ -n "$default" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} ${DIM}[${default}]${NC}: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC}: "
  fi
  local val
  read -r val

  # _trim já removeu os ANSI codes, então agora o padrão ]: casa corretamente
  # Ex antes do trim:  "  ?  Domínio \033[2m[default]\033[0m: valor"
  # Ex depois do trim: "  ?  Domínio [default]: valor"
  val=$(_trim "$val")

  # Extrai apenas a resposta do usuário descartando o eco do prompt
  if [[ "$val" == *"]: "* ]]; then
    # Prompt com default → "Pergunta [default]: resposta" → extrai "resposta"
    val="${val##*]: }"
  elif [[ "$val" == *": "* ]]; then
    # Prompt sem default → "Pergunta: resposta" → extrai "resposta"
    # Guarda URLs: só aplica se não houver "://" (ldaps://, https://, etc.)
    local after_colon="${val##*: }"
    if [[ "$after_colon" != "//"* ]]; then
      val="$after_colon"
    fi
  fi

  val=$(_trim "$val")
  echo "${val:-$default}"
}

ask_secret() {
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}$1${NC}: "
  local val; read -rs val; echo ""
  val="${val//$'\r'/}"; echo "$val"
}

confirm() {
  local label="$1" default="${2:-s}" hint
  [ "$default" = "s" ] && hint="${GREEN}S${NC}/n" || hint="s/${GREEN}N${NC}"
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} [${hint}]: "
  local val; read -r val
  val=$(_trim "$val"); val="${val:-$default}"
  [[ "$val" =~ ^[SsYy]$ ]]
}

pause() {
  echo ""
  read -rp "$(echo -e "  ${DIM}Pressione ENTER para continuar...${NC}")"
}

wait_for() {
  local label="$1" cmd="$2" tries="${3:-30}" interval="${4:-3}"
  echo -ne "  Aguardando ${label}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if eval "$cmd" >> "$INSTALL_LOG" 2>&1; then
      echo -e " ${GREEN}OK${NC}"; return 0
    fi
    echo -n "."; sleep "$interval"; i=$((i+1))
  done
  echo -e " ${RED}timeout após $((tries*interval))s${NC}"; return 1
}

is_valid_domain() {
  local domain="${1//$'\r'/}"
  [ "${#domain}" -lt 3   ] && return 1
  [ "${#domain}" -gt 253 ] && return 1
  [[ "$domain" =~ ^\. ]]   && return 1
  [[ "$domain" =~ \.$  ]]  && return 1
  local IFS_BKP="$IFS"; IFS='.'
  local labels; read -ra labels <<< "$domain"
  IFS="$IFS_BKP"
  [ "${#labels[@]}" -lt 2 ] && return 1
  local label
  for label in "${labels[@]}"; do
    [ -z "$label" ]        && return 1
    [ "${#label}" -gt 63 ] && return 1
    [[ "$label" =~ ^-    ]] && return 1
    [[ "$label" =~ -$    ]] && return 1
    if [ "${#label}" -eq 1 ]; then
      [[ "$label" =~ ^[a-zA-Z0-9]$ ]] || return 1
    else
      [[ "$label" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] || return 1
    fi
  done
  return 0
}

is_valid_email()    { local e="${1//$'\r'/}"; [[ "$e" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
is_valid_ldap_url() { local u="${1//$'\r'/}"; [[ "$u" =~ ^ldaps?://[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; }
is_valid_base_dn()  { local d="${1//$'\r'/}"; [[ "$d" =~ ^(DC|OU|CN)=[^,]+(,(DC|OU|CN)=[^,]+)*$ ]]; }

password_strength() {
  local p="$1" score=0
  [ "${#p}" -ge 12 ]                  && score=$((score+1))
  echo "$p" | grep -q '[A-Z]'         && score=$((score+1))
  echo "$p" | grep -q '[a-z]'         && score=$((score+1))
  echo "$p" | grep -q '[0-9]'         && score=$((score+1))
  echo "$p" | grep -q '[^a-zA-Z0-9]' && score=$((score+1))
  case $score in
    0|1) echo "Muito fraca";; 2) echo "Fraca";;
      3) echo "Regular";;     4) echo "Forte";; 5) echo "Muito forte";;
  esac
}

gen_secret()   { openssl rand -base64 64 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-80; }
gen_password() { openssl rand -base64 32 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32; }
gen_hex()      { openssl rand -hex 32; }

detect_ip() {
  SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7;exit}' \
    || hostname -I 2>/dev/null | awk '{print $1}' \
    || echo "127.0.0.1")
}

# =============================================================================
#  ETAPA 0 — VERIFICAÇÕES INICIAIS
# =============================================================================
step_0_verify() {
  banner
  echo -e "  ${DIM}Log: ${INSTALL_LOG}${NC}"; echo ""
  [ "$(id -u)" -eq 0 ] || fail "Execute como root: sudo bash install.sh"

  if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "?")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    if [[ "$UBUNTU_VERSION" == "22.04" || "$UBUNTU_VERSION" == "24.04" ]]; then
      ok "Ubuntu ${UBUNTU_VERSION} LTS (${UBUNTU_CODENAME})"
    else
      warn "Ubuntu ${UBUNTU_VERSION} não é LTS suportada."
      confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
    fi
  else
    warn "Sistema não identificado como Ubuntu."
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
  fi

  local ARCH; ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|aarch64) ok "Arquitetura: ${ARCH}" ;;
    *) fail "Arquitetura ${ARCH} não suportada." ;;
  esac

  local RAM_GB
  RAM_GB=$(awk '/MemTotal/{printf "%d",$2/1024/1024}' /proc/meminfo)
  if   [ "$RAM_GB" -lt "$REQUIRED_RAM_GB" ]; then fail "RAM insuficiente: ${RAM_GB}GB."
  elif [ "$RAM_GB" -lt 8 ]; then warn "RAM: ${RAM_GB}GB — recomendado 8GB+."
  else ok "RAM: ${RAM_GB}GB"; fi

  local DISK_KB DISK_GB
  DISK_KB=$(df --block-size=1K / | awk 'NR==2{print $4}')
  DISK_GB=$((DISK_KB/1024/1024))
  if   [ "$DISK_GB" -lt "$REQUIRED_DISK_GB" ]; then fail "Disco insuficiente: ${DISK_GB}GB."
  elif [ "$DISK_GB" -lt 40 ]; then warn "Disco: ${DISK_GB}GB — recomendado 40GB+."
  else ok "Disco: ${DISK_GB}GB livres"; fi

  pg "Verificando internet"
  curl -sf --max-time 15 https://download.docker.com > /dev/null 2>&1 \
    && pg_ok || { pg_fail; fail "Sem acesso à internet."; }

  detect_ip; ok "IP: ${SERVER_IP}"

  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""; warn "Instalação existente detectada."
    confirm "Deseja REINSTALAR" "n" || { echo "Cancelado."; exit 0; }
  fi

  ok "Verificações iniciais passaram"; pause
}

# =============================================================================
#  ETAPA 1 — COLETA DE INFORMAÇÕES
# =============================================================================
step_1_collect() {
  banner
  step "1" "COLETA DE INFORMAÇÕES"
  echo -e "  ${DIM}Padrões entre [ ] — ENTER para aceitar.${NC}"; echo ""

  div; echo -e "  ${WHITE}${BOLD}1.1  Domínio${NC}"; echo ""
  info "Exemplos: admanager.empresa.com.br · portal.ti.empresa.org.br"; echo ""
  while true; do
    APP_DOMAIN=$(ask "Domínio da interface web" "admanager.empresa.com.br")
    [ -z "$APP_DOMAIN" ] && warn "Campo obrigatório." && continue
    if ! is_valid_domain "$APP_DOMAIN"; then
      warn "Domínio inválido: '${APP_DOMAIN}'"
      info "Letras, números e hífen. Mínimo dois níveis. Sem hífen no início/fim."
      continue
    fi
    ok "Domínio: ${APP_DOMAIN}"; break
  done

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"; echo ""
  info "ldaps:// (636) para reset de senha — ldap:// (389) se LDAPS indisponível."; echo ""
  while true; do
    AD_URL=$(ask "URL do Controlador de Domínio" "ldaps://dc01.empresa.com.br")
    AD_URL="${AD_URL//$'\r'/}"
    if ! is_valid_ldap_url "$AD_URL"; then warn "Formato inválido."; continue; fi
    AD_HOST=$(echo "$AD_URL" | sed -E 's|ldaps?://||' | cut -d: -f1)
    local _port; _port=$(echo "$AD_URL" | grep -oP ':\K[0-9]+' || true)
    [ -z "$_port" ] && { [[ "$AD_URL" == ldaps://* ]] && AD_PORT="636" || AD_PORT="389"; } || AD_PORT="$_port"
    pg "Testando ${AD_HOST}:${AD_PORT}"
    if nc -zw 5 "$AD_HOST" "$AD_PORT" > /dev/null 2>&1; then
      pg_ok; ok "AD acessível"; break
    else
      pg_fail; warn "Não conectou a ${AD_HOST}:${AD_PORT}."
      confirm "Usar mesmo assim" "n" && break || continue
    fi
  done

  while true; do
    AD_BASE_DN=$(ask "Base DN" "DC=empresa,DC=com,DC=br")
    AD_BASE_DN="${AD_BASE_DN//$'\r'/}"
    is_valid_base_dn "$AD_BASE_DN" && { ok "Base DN: ${AD_BASE_DN}"; break; }
    warn "Formato inválido. Ex: DC=empresa,DC=com,DC=br"
  done

  echo ""; info "Conta de serviço precisa de permissões de leitura/escrita no AD."; echo ""
  while true; do
    AD_USERNAME=$(ask "UPN da conta de serviço" "svc-admanager@empresa.com.br")
    AD_USERNAME="${AD_USERNAME//$'\r'/}"; [ -n "$AD_USERNAME" ] && break; warn "Obrigatório."
  done
  while true; do
    AD_PASSWORD=$(ask_secret "Senha da conta de serviço")
    [ -n "$AD_PASSWORD" ] && break; warn "Obrigatório."
  done
  while true; do
    AD_DOMAIN=$(ask "Domínio NetBIOS / UPN suffix" "empresa.com.br")
    AD_DOMAIN="${AD_DOMAIN//$'\r'/}"; [ -n "$AD_DOMAIN" ] && break; warn "Obrigatório."
  done
  ok "Active Directory configurado"

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.3  Administrador inicial${NC}"; echo ""
  while true; do
    ADMIN_USER=$(ask "Usuário administrador" "admin")
    ADMIN_USER="${ADMIN_USER//$'\r'/}"; [ -n "$ADMIN_USER" ] && break; warn "Obrigatório."
  done
  while true; do
    ADMIN_EMAIL=$(ask "Email do administrador" "admin@empresa.com.br")
    ADMIN_EMAIL="${ADMIN_EMAIL//$'\r'/}"
    is_valid_email "$ADMIN_EMAIL" && break; warn "Email inválido."
  done
  echo ""; info "Senha: mín. 12 chars, maiúsculas, minúsculas, números e símbolos."; echo ""
  while true; do
    ADMIN_PASSWORD=$(ask_secret "Senha do administrador")
    [ "${#ADMIN_PASSWORD}" -lt 12 ] && warn "Mínimo 12 caracteres." && continue
    echo -e "  ${DIM}Força: $(password_strength "$ADMIN_PASSWORD")${NC}"
    local CONF; CONF=$(ask_secret "Confirme a senha")
    [ "$ADMIN_PASSWORD" = "$CONF" ] && break; warn "Senhas não coincidem."
  done
  ok "Administrador: ${ADMIN_USER} (${ADMIN_EMAIL})"

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.4  Azure AD / M365 ${DIM}(opcional)${NC}"; echo ""
  info "Necessário para licenças M365, MFA e sessões."; echo ""
  if confirm "Configurar Azure AD / M365 agora" "s"; then
    SETUP_GRAPH="y"
    while true; do AZURE_TENANT_ID=$(ask "Tenant ID"); AZURE_TENANT_ID="${AZURE_TENANT_ID//$'\r'/}"; [ -n "$AZURE_TENANT_ID" ] && break; warn "Obrigatório."; done
    while true; do AZURE_CLIENT_ID=$(ask "Client ID"); AZURE_CLIENT_ID="${AZURE_CLIENT_ID//$'\r'/}"; [ -n "$AZURE_CLIENT_ID" ] && break; warn "Obrigatório."; done
    while true; do AZURE_CLIENT_SECRET=$(ask_secret "Client Secret"); [ -n "$AZURE_CLIENT_SECRET" ] && break; warn "Obrigatório."; done
    ok "Azure AD / M365 configurado"
  else
    warn "Azure AD ignorado. Configure depois em Configurações."
  fi

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.5  SMTP ${DIM}(opcional)${NC}"; echo ""
  if confirm "Configurar SMTP agora" "s"; then
    SETUP_SMTP="y"
    while true; do SMTP_HOST=$(ask "Servidor SMTP" "smtp.empresa.com.br"); SMTP_HOST="${SMTP_HOST//$'\r'/}"; [ -n "$SMTP_HOST" ] && break; warn "Obrigatório."; done
    SMTP_PORT=$(ask "Porta SMTP" "587"); SMTP_PORT="${SMTP_PORT//$'\r'/}"
    confirm "Usar TLS/SSL" "s" && SMTP_SECURE="true" || SMTP_SECURE="false"
    SMTP_USER=$(ask "Usuário SMTP (em branco para relay)"); SMTP_USER="${SMTP_USER//$'\r'/}"
    [ -n "$SMTP_USER" ] && SMTP_PASS=$(ask_secret "Senha SMTP")
    while true; do
      SMTP_FROM=$(ask "Email remetente" "admanager@${APP_DOMAIN}"); SMTP_FROM="${SMTP_FROM//$'\r'/}"
      is_valid_email "$SMTP_FROM" && break; warn "Email inválido."
    done
    ok "SMTP: ${SMTP_HOST}:${SMTP_PORT}"
  else
    SMTP_FROM="admanager@${APP_DOMAIN}"; warn "SMTP ignorado."
  fi

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.6  Microsoft Teams ${DIM}(opcional)${NC}"; echo ""
  if confirm "Configurar alertas no Teams agora" "n"; then
    SETUP_TEAMS="y"
    while true; do
      TEAMS_WEBHOOK_URL=$(ask "URL do Incoming Webhook"); TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL//$'\r'/}"
      [[ "$TEAMS_WEBHOOK_URL" =~ ^https:// ]] && break; warn "URL deve começar com https://"
    done
    ok "Teams configurado"
  else
    warn "Teams ignorado."
  fi

  echo ""; div; echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"; echo ""
  echo -e "   ${GREEN}1)${NC} Let's Encrypt — gratuito, renovação automática"
  echo -e "   ${GREEN}2)${NC} PKI corporativa — self-signed temporário"
  echo -e "   ${GREEN}3)${NC} Self-signed — para ambientes internos"
  echo ""
  while true; do
    CERT_OPCAO=$(ask "Tipo de certificado" "3"); CERT_OPCAO="${CERT_OPCAO//$'\r'/}"
    case "$CERT_OPCAO" in 1|2|3) break;; *) warn "Digite 1, 2 ou 3.";; esac
  done

  banner
  echo -e "  ${WHITE}${BOLD}RESUMO — CONFIRME ANTES DE PROSSEGUIR${NC}"; echo ""; div; echo ""
  echo -e "  URL: ${WHITE}https://${APP_DOMAIN}${NC}  |  IP: ${SERVER_IP}"
  echo -e "  AD:  ${AD_URL}  |  ${AD_BASE_DN}"
  echo -e "  Admin: ${ADMIN_USER} / ${ADMIN_EMAIL}"
  [ "$SETUP_GRAPH" = "y" ] \
    && echo -e "  M365: ${GREEN}Habilitado — ${AZURE_TENANT_ID}${NC}" \
    || echo -e "  M365: ${DIM}Não configurado${NC}"
  [ "$SETUP_SMTP" = "y" ] \
    && echo -e "  SMTP: ${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}" \
    || echo -e "  SMTP: ${DIM}Não configurado${NC}"
  [ "$SETUP_TEAMS" = "y" ] \
    && echo -e "  Teams: ${GREEN}Habilitado${NC}" \
    || echo -e "  Teams: ${DIM}Não configurado${NC}"
  case "$CERT_OPCAO" in
    1) echo -e "  TLS: ${GREEN}Let's Encrypt${NC}" ;;
    2) echo -e "  TLS: ${YELLOW}PKI corporativa (temporário)${NC}" ;;
    3) echo -e "  TLS: ${DIM}Self-signed 10 anos${NC}" ;;
  esac
  echo ""; div; echo ""
  confirm "Iniciar a instalação" "s" || { echo "Cancelado."; exit 0; }
}

# =============================================================================
#  ETAPA 2 — PREPARAÇÃO DO SISTEMA
# =============================================================================
step_2_prepare() {
  step "2" "PREPARAÇÃO DO SISTEMA"
  sub "Atualizando pacotes..."
  q apt-get update -qq; q apt-get upgrade -y -qq; ok "Pacotes atualizados"
  sub "Instalando dependências..."
  q apt-get install -y -qq curl wget git openssl netcat-openbsd python3 jq unzip \
    ca-certificates gnupg ufw fail2ban auditd chrony lsb-release
  ok "Dependências instaladas"
  sub "Criando usuário '${SERVICE_USER}'..."
  id -u "$SERVICE_USER" > /dev/null 2>&1 \
    || q useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
  ok "Usuário '${SERVICE_USER}' pronto"
  sub "Criando diretórios..."
  q mkdir -p "${INSTALL_DIR}/logs" "${INSTALL_DIR}/backups" "${INSTALL_DIR}/scripts" \
             "${INSTALL_DIR}/infra/nginx/ssl" "${INSTALL_DIR}/infra/nginx/conf.d"
  ok "Diretórios criados"
  sub "Configurando kernel..."
  cat > /etc/sysctl.d/99-admanager.conf << 'EOF'
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
net.core.somaxconn=65535
fs.inotify.max_user_watches=524288
EOF
  q sysctl --system; ok "Kernel configurado"
}

# =============================================================================
#  ETAPA 3 — SEGURANÇA E NTP
# =============================================================================
step_3_security() {
  step "3" "SEGURANÇA E NTP"
  sub "UFW..."
  q ufw --force reset; q ufw default deny incoming; q ufw default allow outgoing
  q ufw allow ssh; q ufw allow http; q ufw allow https; q ufw --force enable
  ok "UFW ativo: 22, 80, 443"

  sub "fail2ban..."
  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime=7200
findtime=600
maxretry=3
[sshd]
enabled=true
port=ssh
filter=sshd
logpath=/var/log/auth.log
maxretry=3
EOF
  q systemctl enable fail2ban; q systemctl restart fail2ban
  ok "fail2ban ativo (3 tentativas → 2h bloqueio)"

  sub "auditd..."
  cat > /etc/audit/rules.d/99-admanager.rules << EOF
-w ${INSTALL_DIR}/.env                            -p rwxa -k admanager-config
-w ${INSTALL_DIR}/infra/nginx/ssl/key.pem         -p rwxa -k admanager-tls-key
-w /etc/systemd/system/ad-license-manager.service -p rwxa -k admanager-systemd
-w /etc/cron.d/admanager                          -p rwxa -k admanager-cron
EOF
  q augenrules --load || true
  q systemctl enable auditd; q systemctl restart auditd; ok "auditd configurado"

  sub "chrony NTP..."
  q systemctl enable chrony; q systemctl start chrony
  q timedatectl set-ntp true; ok "chrony ativo"

  sub "SSH hardening..."
  local S="/etc/ssh/sshd_config"
  cp "$S" "${S}.bak-$(date +%Y%m%d)" 2>/dev/null || true
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'          "$S"
  sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/'                 "$S"
  sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' "$S"
  sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/'   "$S"
  sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/'              "$S"
  q systemctl restart sshd; ok "SSH hardening aplicado"
}

# =============================================================================
#  ETAPA 4 — DOCKER
# =============================================================================
step_4_docker() {
  step "4" "DOCKER ENGINE E COMPOSE PLUGIN"
  sub "Removendo versões antigas..."
  q apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  ok "Versões antigas removidas"

  sub "Chave GPG oficial..."
  q install -m 0755 -d /etc/apt/keyrings; q rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$INSTALL_LOG" 2>&1
  q chmod a+r /etc/apt/keyrings/docker.gpg; ok "Chave GPG adicionada"

  sub "Repositório Docker..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  q apt-get update -qq; ok "Repositório adicionado"

  sub "Instalando Docker..."
  q apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "Docker instalado"

  sub "Configurando daemon..."
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver":"json-file",
  "log-opts":{"max-size":"10m","max-file":"5"},
  "live-restore":true,
  "userland-proxy":false,
  "default-address-pools":[{"base":"172.20.0.0/16","size":24}]
}
EOF
  q systemctl enable docker; q systemctl restart docker
  q usermod -aG docker "$SERVICE_USER"; ok "Daemon configurado"

  sub "Verificando Docker..."
  q docker run --rm hello-world \
    && ok "Docker funcionando" \
    || fail "Docker com problema."

  local DV CV
  DV=$(docker --version       | grep -oP '\d+\.\d+\.\d+' | head -1)
  CV=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${DV} · Compose ${CV}"
}

# =============================================================================
#  ETAPA 5 — CÓDIGO-FONTE
# =============================================================================
step_5_clone() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"
  if [ -d "${INSTALL_DIR}/.git" ]; then
    sub "Atualizando repositório..."
    cd "${INSTALL_DIR}"; q git fetch origin; q git reset --hard origin/main
    ok "Código atualizado"
  else
    sub "Clonando repositório..."
    local TMP; TMP=$(mktemp -d)
    if q git clone "$REPO_URL" "$TMP"; then
      cp -a "${TMP}/." "${INSTALL_DIR}/"; rm -rf "$TMP"; ok "Clonado"
    else
      rm -rf "$TMP"; fail "Falha ao clonar ${REPO_URL}."
    fi
  fi
  find "${INSTALL_DIR}" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  ok "Scripts executáveis"
}

# =============================================================================
#  ETAPA 6 — ARQUIVO .ENV
# =============================================================================
step_6_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"
  sub "Gerando segredos..."
  DB_PASSWORD=$(gen_password); REDIS_PASSWORD=$(gen_password)
  JWT_SECRET=$(gen_secret);    JWT_REFRESH_SECRET=$(gen_secret)
  ENCRYPTION_KEY=$(gen_hex);   ok "Segredos gerados"

  sub "Escrevendo .env..."
  cat > "${INSTALL_DIR}/.env" << EOF
# AD License Manager — $(date '+%Y-%m-%d %H:%M:%S')
NODE_ENV=production
APP_URL=https://${APP_DOMAIN}
PORT=3001
TZ=America/Sao_Paulo
AD_URL=${AD_URL}
AD_BASE_DN=${AD_BASE_DN}
AD_USERNAME=${AD_USERNAME}
AD_PASSWORD=${AD_PASSWORD}
AD_DOMAIN=${AD_DOMAIN}
DATABASE_URL=postgresql://admanager:${DB_PASSWORD}@postgres:5432/admanager?schema=public
DB_PASSWORD=${DB_PASSWORD}
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=${REDIS_PASSWORD}
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d
ENCRYPTION_KEY=${ENCRYPTION_KEY}
SESSION_SECRET=${JWT_SECRET}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURE=${SMTP_SECURE}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_FROM=${SMTP_FROM}
TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL}
GLPI_URL=
GLPI_APP_TOKEN=
GLPI_USER_TOKEN=
LOG_LEVEL=info
SESSION_TIMEOUT_MINUTES=60
MAX_LOGIN_ATTEMPTS=5
PASSWORD_MIN_LENGTH=12
INACTIVE_USER_THRESHOLD_DAYS=90
PASSWORD_EXPIRY_ALERT_DAYS=14
LICENSE_ALERT_THRESHOLD=85
AUDIT_RETENTION_DAYS=365
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}
EOF
  chmod 600 "${INSTALL_DIR}/.env"
  chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/.env"
  local BAK="${INSTALL_DIR}/.env.backup-$(date +%Y%m%d-%H%M%S)"
  cp "${INSTALL_DIR}/.env" "$BAK"; chmod 600 "$BAK"
  ok ".env gerado (600) — backup: $(basename "$BAK")"
}

# =============================================================================
#  ETAPA 7 — TLS
# =============================================================================
step_7_tls() {
  step "7" "CERTIFICADO TLS"
  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  if [ "$CERT_OPCAO" = "1" ]; then
    sub "Instalando Certbot..."
    q apt-get install -y -qq certbot; ok "Certbot instalado"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nginx" \
      && q docker compose -f "${INSTALL_DIR}/docker-compose.yml" stop nginx || true
    sub "Gerando Let's Encrypt para ${APP_DOMAIN}..."
    if certbot certonly --standalone --non-interactive --agree-tos \
        --email "$ADMIN_EMAIL" -d "$APP_DOMAIN" >> "$INSTALL_LOG" 2>&1; then
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem" "${SSL_DIR}/cert.pem"
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem"   "${SSL_DIR}/key.pem"
      ok "Certificado Let's Encrypt gerado"
      cat > /usr/local/bin/admanager-renew-cert.sh << EOF
#!/bin/bash
set -e
certbot renew --quiet
cp /etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem ${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem   ${SSL_DIR}/key.pem
chown ${SERVICE_USER}:${SERVICE_USER} ${SSL_DIR}/cert.pem ${SSL_DIR}/key.pem
chmod 644 ${SSL_DIR}/cert.pem; chmod 600 ${SSL_DIR}/key.pem
docker compose -f ${INSTALL_DIR}/docker-compose.yml restart nginx
echo "\$(date '+%Y-%m-%d %H:%M:%S') Renovado." >> ${INSTALL_DIR}/logs/certbot.log
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      echo "0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh" \
        > /etc/cron.d/admanager-certbot
      ok "Renovação automática agendada"
    else
      warn "Let's Encrypt falhou. Usando self-signed."; CERT_OPCAO="3"
    fi
  fi

  if [ "$CERT_OPCAO" != "1" ] || [ ! -f "${SSL_DIR}/cert.pem" ]; then
    sub "Gerando self-signed RSA 4096 (10 anos)..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
      -keyout "${SSL_DIR}/key.pem" -out "${SSL_DIR}/cert.pem" \
      -subj "/CN=${APP_DOMAIN}/O=AD License Manager/C=BR/OU=TI" \
      -addext "subjectAltName=DNS:${APP_DOMAIN},DNS:localhost,IP:${SERVER_IP},IP:127.0.0.1" \
      >> "$INSTALL_LOG" 2>&1 || fail "Falha ao gerar certificado."
    ok "Certificado self-signed gerado"
    if [ "$CERT_OPCAO" = "2" ]; then
      warn "Substitua pela PKI: ${SSL_DIR}/{cert,key}.pem"
      warn "Depois: docker compose restart nginx"
    fi
  fi

  chown "${SERVICE_USER}:${SERVICE_USER}" "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"; chmod 600 "${SSL_DIR}/key.pem"
  openssl x509 -in "${SSL_DIR}/cert.pem" -noout >> "$INSTALL_LOG" 2>&1 \
    || fail "Certificado inválido."
  ok "Certificado válido — expira: $(openssl x509 -in "${SSL_DIR}/cert.pem" -noout -enddate | cut -d= -f2)"
}

# =============================================================================
#  ETAPA 8 — BUILD
# =============================================================================
step_8_build() {
  step "8" "BUILD DAS IMAGENS DOCKER"
  cd "${INSTALL_DIR}"
  info "Pode levar 10-25 min. Acompanhe: tail -f ${INSTALL_LOG}"; echo ""
  sub "Construindo imagens..."
  docker compose build --no-cache --progress=plain >> "$INSTALL_LOG" 2>&1 \
    || fail "Erro no build. Veja: ${INSTALL_LOG}"
  ok "Imagens construídas"
  docker compose images 2>/dev/null | tail -n +2 | \
    while IFS= read -r l; do echo "    ${l}"; done || true
}

# =============================================================================
#  ETAPA 9 — INICIALIZAÇÃO
# =============================================================================
step_9_start() {
  step "9" "INICIALIZAÇÃO DOS SERVIÇOS"
  cd "${INSTALL_DIR}"
  sub "Iniciando PostgreSQL e Redis..."
  q docker compose up -d postgres redis; ok "Infraestrutura iniciada"; echo ""

  wait_for "PostgreSQL" \
    "docker compose exec -T postgres pg_isready -U admanager -d admanager" 40 3 \
    || fail "PostgreSQL não ficou pronto."
  ok "PostgreSQL aceitando conexões"

  wait_for "Redis" \
    "docker compose exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping | grep -q PONG" 20 2 \
    || fail "Redis não ficou pronto."
  ok "Redis respondendo"; echo ""

  sub "Migrations..."
  q docker compose run --rm backend node dist/migrate.js || fail "Erro nas migrations."
  ok "Migrations aplicadas"

  sub "Seed..."
  q docker compose run --rm backend node dist/seed.js || fail "Erro no seed."
  ok "Dados iniciais criados"

  sub "Iniciando todos os serviços..."
  q docker compose up -d; ok "Todos os containers iniciados"; echo ""

  wait_for "Backend API" "curl -sf http://localhost:3001/health" 30 4 \
    || warn "Backend ainda iniciando. Veja: docker compose logs backend"

  echo ""; sub "Status:"; echo ""
  docker compose ps 2>/dev/null | while IFS= read -r l; do echo "    ${l}"; done
}

# =============================================================================
#  ETAPA 10 — SYSTEMD
# =============================================================================
step_10_systemd() {
  step "10" "SYSTEMD — BOOT AUTOMÁTICO"
  cat > /etc/systemd/system/ad-license-manager.service << EOF
[Unit]
Description=AD License Manager
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
User=${SERVICE_USER}
Group=${SERVICE_USER}
Environment="HOME=/tmp"
Environment="COMPOSE_PROJECT_NAME=admanager"
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down --timeout 30
ExecReload=/usr/bin/docker compose up -d --remove-orphans
Restart=on-failure
RestartSec=30
TimeoutStartSec=300
TimeoutStopSec=60
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ad-license-manager

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  q systemctl enable ad-license-manager
  ok "Serviço systemd habilitado para boot automático"
}

# =============================================================================
#  ETAPA 11 — SCRIPTS OPERACIONAIS
# =============================================================================
step_11_scripts() {
  step "11" "SCRIPTS OPERACIONAIS"

  sub "backup.sh..."
  cat > "${INSTALL_DIR}/scripts/backup.sh" << 'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"
BACKUP_DIR="${INSTALL_DIR}/backups/$(date +%Y-%m-%d)"
LOG="${INSTALL_DIR}/logs/backup.log"
RETENCAO=30
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }
log "=== Backup iniciado ==="
mkdir -p "$BACKUP_DIR"
REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d "\"'")
log "Dump PostgreSQL..."
if docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T postgres \
    pg_dump -U admanager admanager --format=custom --compress=9 \
    > "${BACKUP_DIR}/database.dump"; then
  log "Banco OK: $(du -sh "${BACKUP_DIR}/database.dump" | cut -f1)"
else
  log "ERRO: falha no dump."; exit 1
fi
cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"; chmod 600 "${BACKUP_DIR}/.env.bak"
log "Config OK"
ls "${INSTALL_DIR}/logs/"*.log 1>/dev/null 2>&1 && \
  tar -czf "${BACKUP_DIR}/logs.tar.gz" -C "${INSTALL_DIR}" logs/ 2>/dev/null && \
  log "Logs OK" || log "AVISO: logs não comprimidos."
find "${INSTALL_DIR}/backups" -maxdepth 1 -type d -mtime "+${RETENCAO}" \
  -exec rm -rf {} + 2>/dev/null || true
log "=== Concluído: $(du -sh "$BACKUP_DIR" | cut -f1) em ${BACKUP_DIR} ==="
BACKUP_SCRIPT
  ok "backup.sh"

  sub "health-check.sh..."
  cat > "${INSTALL_DIR}/scripts/health-check.sh" << 'HEALTH_SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
INSTALL_DIR="/opt/ad-license-manager"
COMPOSE="${INSTALL_DIR}/docker-compose.yml"
LOG="${INSTALL_DIR}/logs/health.log"
FALHAS=0
REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" 2>/dev/null \
  | cut -d= -f2- | tr -d "\"'")
check() {
  local label="$1" cmd="$2" match="${3:-.}"
  eval "$cmd" 2>/dev/null | grep -q "$match" \
    && echo "  ✓  ${label}" \
    || { echo "  ✗  ${label}"; FALHAS=$((FALHAS+1)); }
}
echo ""; echo "  ── Health Check — $(date '+%d/%m/%Y %H:%M:%S')"; echo ""
check "PostgreSQL"  "docker compose -f '$COMPOSE' exec -T postgres pg_isready -U admanager" "accepting"
check "Redis"       "docker compose -f '$COMPOSE' exec -T redis redis-cli -a '$REDIS_PASSWORD' --no-auth-warning ping" "PONG"
check "Backend API" "curl -sf http://localhost:3001/health" "."
check "Nginx HTTPS" "curl -skf https://localhost/health" "."
check "Worker"      "docker compose -f '$COMPOSE' ps worker" "running"
echo ""
if [ "$FALHAS" -gt 0 ]; then
  echo "  ✗  ${FALHAS} serviço(s) com problema. Veja: docker compose logs"
  echo "$(date '+%Y-%m-%d %H:%M:%S') FALHA:${FALHAS}" >> "$LOG"; exit 1
else
  echo "  ✓  Todos saudáveis."
  echo "$(date '+%Y-%m-%d %H:%M:%S') OK" >> "$LOG"
fi
echo ""
HEALTH_SCRIPT
  ok "health-check.sh"

  sub "update.sh..."
  cat > "${INSTALL_DIR}/scripts/update.sh" << 'UPDATE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"
echo "=== Atualização — $(date '+%d/%m/%Y %H:%M:%S') ==="
bash "${INSTALL_DIR}/scripts/backup.sh"
cd "${INSTALL_DIR}"
git fetch origin; git reset --hard origin/main
docker compose build --no-cache --progress=plain
docker compose run --rm backend node dist/migrate.js
docker compose up -d --remove-orphans
sleep 15
bash "${INSTALL_DIR}/scripts/health-check.sh"
echo "=== Atualização concluída ==="
UPDATE_SCRIPT
  ok "update.sh"

  sub "restore.sh..."
  cat > "${INSTALL_DIR}/scripts/restore.sh" << 'RESTORE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"
usage() {
  echo "Uso: sudo bash restore.sh YYYY-MM-DD"
  ls -d "${INSTALL_DIR}/backups/"*/ 2>/dev/null | xargs -I{} basename {} \
    || echo "Nenhum backup encontrado."
  exit 1
}
DATE="${1:-}"; [ -z "$DATE" ] && { echo "Informe a data."; usage; }
BACKUP_DIR="${INSTALL_DIR}/backups/${DATE}"
[ -d "$BACKUP_DIR" ]                 || { echo "Backup não encontrado."; usage; }
[ -f "${BACKUP_DIR}/database.dump" ] || { echo "Dump não encontrado.";   exit 1; }
echo ""
echo "ATENÇÃO: dados atuais serão substituídos pelo backup de ${DATE}."
read -rp "  Confirme digitando 'RESTAURAR': " CONFIRM
[ "$CONFIRM" = "RESTAURAR" ] || { echo "Cancelado."; exit 0; }
cd "${INSTALL_DIR}"
docker compose stop backend worker
docker compose exec -T postgres pg_restore \
  --username admanager --dbname admanager \
  --clean --if-exists < "${BACKUP_DIR}/database.dump"
docker compose start backend worker
sleep 10
bash "${INSTALL_DIR}/scripts/health-check.sh"
echo "=== Restauração de ${DATE} concluída ==="
RESTORE_SCRIPT

  chmod +x "${INSTALL_DIR}/scripts/"*.sh
  chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/scripts/"*.sh
  ok "Todos os scripts criados"
}
# =============================================================================
#  ETAPA 12 — CRON JOBS
# =============================================================================
step_12_cron() {
  step "12" "CRON JOBS AUTOMÁTICOS"
  cat > /etc/cron.d/admanager << EOF
# AD License Manager — $(date '+%Y-%m-%d')
0   3   * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/backup.sh >> ${INSTALL_DIR}/logs/backup.log 2>&1
*/5 *   * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/health-check.sh >> ${INSTALL_DIR}/logs/health.log 2>&1
0   */6 * * * ${SERVICE_USER} find ${INSTALL_DIR}/logs -name "*.log" -mtime +7 -delete 2>/dev/null || true
0   4   * * * root docker system prune -f >> ${INSTALL_DIR}/logs/docker-prune.log 2>&1
EOF
  chmod 644 /etc/cron.d/admanager
  ok "Cron jobs: backup 03h · health /5min · limpeza 6h · prune 04h"
}

# =============================================================================
#  ETAPA 13 — PERMISSÕES FINAIS
# =============================================================================
step_13_permissions() {
  step "13" "PERMISSÕES FINAIS"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
  chmod 750 "${INSTALL_DIR}"
  chmod 600 "${INSTALL_DIR}/.env"
  chmod 700 "${INSTALL_DIR}/logs"
  chmod 700 "${INSTALL_DIR}/backups"
  chmod 700 "${INSTALL_DIR}/scripts"
  chmod 644 "${INSTALL_DIR}/infra/nginx/ssl/cert.pem"
  chmod 600 "${INSTALL_DIR}/infra/nginx/ssl/key.pem"
  ok "Permissões aplicadas"
  systemctl is-active --quiet ufw      && ok "UFW ativo"      || warn "UFW inativo"
  systemctl is-active --quiet fail2ban && ok "fail2ban ativo" || warn "fail2ban inativo"
  systemctl is-active --quiet auditd   && ok "auditd ativo"   || warn "auditd inativo"
  systemctl is-active --quiet chrony   && ok "chrony ativo"   || warn "chrony inativo"
}

# =============================================================================
#  ETAPA 14 — RESUMO FINAL
# =============================================================================
step_14_summary() {
  step "14" "VERIFICAÇÃO FINAL E RESUMO"
  cd "${INSTALL_DIR}"

  sub "Health check..."
  echo ""
  bash "${INSTALL_DIR}/scripts/health-check.sh" || true
  echo ""

  sub "Certificado TLS..."
  local EXPIRY
  EXPIRY=$(openssl x509 \
    -in "${INSTALL_DIR}/infra/nginx/ssl/cert.pem" \
    -noout -enddate 2>/dev/null | cut -d= -f2 || echo "não verificado")
  ok "Certificado expira: ${EXPIRY}"

  sub "Testando HTTPS..."
  if curl -skf "https://localhost/health" > /dev/null 2>&1; then
    ok "Nginx respondendo via HTTPS"
  else
    warn "Aguardando Nginx (15s)..."
    sleep 15
    curl -skf "https://localhost/health" > /dev/null 2>&1 \
      && ok "Nginx OK" \
      || warn "Nginx sem resposta. Veja: docker compose logs nginx"
  fi

  local INSTALL_END DURACAO
  INSTALL_END=$(date +%s)
  DURACAO=$(( (INSTALL_END - INSTALL_START) / 60 ))

  banner
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════════╗"
  echo "  ║                                                                      ║"
  echo "  ║           ✓  INSTALAÇÃO CONCLUÍDA COM SUCESSO!                      ║"
  echo "  ║                                                                      ║"
  echo "  ╚══════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Tempo total: ${DURACAO} minuto(s)${NC}"
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}ACESSO AO SISTEMA${NC}"
  div
  echo ""
  echo -e "  ${CYAN}URL:${NC}      ${WHITE}${BOLD}https://${APP_DOMAIN}${NC}"
  echo -e "  ${CYAN}Usuário:${NC}  ${WHITE}${BOLD}${ADMIN_USER}${NC}"
  echo -e "  ${CYAN}Email:${NC}    ${WHITE}${BOLD}${ADMIN_EMAIL}${NC}"
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}PRÓXIMOS PASSOS${NC}"
  div
  echo ""
  echo -e "  1. Acesse https://${APP_DOMAIN} e faça login com '${ADMIN_USER}'"
  echo -e "  2. Altere a senha do administrador no primeiro acesso"
  echo -e "  3. Crie o registro DNS: ${APP_DOMAIN} → ${SERVER_IP}"
  if [ "$CERT_OPCAO" = "2" ]; then
    echo -e "  4. ${YELLOW}Substitua o certificado pela PKI corporativa:${NC}"
    echo -e "     ${INSTALL_DIR}/infra/nginx/ssl/cert.pem"
    echo -e "     ${INSTALL_DIR}/infra/nginx/ssl/key.pem"
    echo -e "     Depois: docker compose restart nginx"
  fi
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}COMANDOS ÚTEIS${NC}"
  div
  echo ""
  echo -e "  cd ${INSTALL_DIR}"
  echo -e "  docker compose ps                  ${DIM}# status${NC}"
  echo -e "  docker compose logs -f             ${DIM}# logs em tempo real${NC}"
  echo -e "  bash scripts/health-check.sh       ${DIM}# health check${NC}"
  echo -e "  sudo bash scripts/backup.sh        ${DIM}# backup manual${NC}"
  echo -e "  sudo bash scripts/update.sh        ${DIM}# atualização${NC}"
  echo -e "  sudo bash scripts/restore.sh DATA  ${DIM}# restauração${NC}"
  echo -e "  sudo systemctl status ad-license-manager"
  echo ""
  echo -e "  ${DIM}Log da instalação: ${INSTALL_LOG}${NC}"
  echo ""
}

# =============================================================================
#  FLUXO PRINCIPAL
# =============================================================================
main() {
  step_0_verify
  step_1_collect
  step_2_prepare
  step_3_security
  step_4_docker
  step_5_clone
  step_6_env
  step_7_tls
  step_8_build
  step_9_start
  step_10_systemd
  step_11_scripts
  step_12_cron
  step_13_permissions
  step_14_summary
}

main "$@"
