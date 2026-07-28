#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Completo e Autônomo
#  Versão 2.1.2 — Julho de 2026
#  Ubuntu Server 22.04 LTS / 24.04 LTS
#  Uso: sudo bash install.sh
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
  echo ""
  exit 1
}

_trim() {
  local v="$1"
  v="${v//$'\r'/}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

ask() {
  local label="$1" default="${2:-}"
  if [ -n "$default" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} ${DIM}[${default}]${NC}: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC}: "
  fi
  local val; read -r val
  val=$(_trim "$val")
  echo "${val:-$default}"
}

ask_secret() {
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}$1${NC}: "
  local val; read -rs val; echo ""
  val="${val//$'\r'/}"
  echo "$val"
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
  echo -e " ${RED}timeout após $((tries*interval))s${NC}"
  return 1
}

is_valid_domain() {
  local domain="${1//$'\r'/}"
  [ "${#domain}" -lt 3  ] && return 1
  [ "${#domain}" -gt 253 ] && return 1
  [[ "$domain" =~ ^\. ]] && return 1
  [[ "$domain" =~ \.$  ]] && return 1
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
      warn "Ubuntu ${UBUNTU_VERSION} não é LTS suportada (22.04/24.04)."
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

  pg "Verificando acesso à internet"
  curl -sf --max-time 15 https://download.docker.com > /dev/null 2>&1 \
    && pg_ok || { pg_fail; fail "Sem acesso à internet."; }

  detect_ip; ok "IP do servidor: ${SERVER_IP}"

  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""; warn "Instalação existente detectada."
    confirm "Deseja REINSTALAR" "n" || { echo "Cancelado."; exit 0; }
  fi

  ok "Todas as verificações iniciais passaram"
  pause
}

# =============================================================================
#  ETAPA 1 — COLETA DE INFORMAÇÕES
# =============================================================================
step_1_collect() {
  banner
  step "1" "COLETA DE INFORMAÇÕES"
  echo -e "  ${DIM}Padrões entre [ ] — ENTER para aceitar.${NC}"; echo ""

  # 1.1 Domínio
  div; echo -e "  ${WHITE}${BOLD}1.1  Domínio de acesso${NC}"; echo ""
  info "Exemplos: admanager.empresa.com.br · portal.ti.empresa.org.br"; echo ""
  while true; do
    APP_DOMAIN=$(ask "Domínio da interface web" "admanager.empresa.com.br")
    [ -z "$APP_DOMAIN" ] && warn "Campo obrigatório." && continue
    if ! is_valid_domain "$APP_DOMAIN"; then
      warn "Domínio inválido: '${APP_DOMAIN}'"
      info "Letras, números e hífen. Mínimo dois níveis (host.dominio)."
      info "Não pode começar ou terminar com hífen ou ponto."
      continue
    fi
    ok "Domínio aceito: ${APP_DOMAIN}"; break
  done

  # 1.2 Active Directory
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"; echo ""
  info "Use ldaps:// (porta 636) para habilitar reset de senha."
  info "Use ldap://  (porta 389) somente se LDAPS não estiver disponível."; echo ""

  while true; do
    AD_URL=$(ask "URL do Controlador de Domínio" "ldaps://dc01.empresa.com.br")
    AD_URL="${AD_URL//$'\r'/}"
    if ! is_valid_ldap_url "$AD_URL"; then
      warn "Formato inválido. Ex: ldaps://dc01.empresa.com.br"; continue
    fi
    AD_HOST=$(echo "$AD_URL" | sed -E 's|ldaps?://||' | cut -d: -f1)
    local _port; _port=$(echo "$AD_URL" | grep -oP ':\K[0-9]+' || true)
    [ -z "$_port" ] && { [[ "$AD_URL" == ldaps://* ]] && AD_PORT="636" || AD_PORT="389"; } \
      || AD_PORT="$_port"
    pg "Testando ${AD_HOST}:${AD_PORT}"
    if nc -zw 5 "$AD_HOST" "$AD_PORT" > /dev/null 2>&1; then
      pg_ok; ok "Active Directory acessível"; break
    else
      pg_fail; warn "Não foi possível conectar a ${AD_HOST}:${AD_PORT}."
      confirm "Usar esta URL mesmo assim" "n" && break || continue
    fi
  done

  while true; do
    AD_BASE_DN=$(ask "Base DN do domínio" "DC=empresa,DC=com,DC=br")
    AD_BASE_DN="${AD_BASE_DN//$'\r'/}"
    is_valid_base_dn "$AD_BASE_DN" && { ok "Base DN: ${AD_BASE_DN}"; break; }
    warn "Formato inválido. Ex: DC=empresa,DC=com,DC=br"
  done

  echo ""; info "A conta de serviço precisa de permissões de leitura/escrita no AD."; echo ""

  while true; do
    AD_USERNAME=$(ask "UPN da conta de serviço" "svc-admanager@empresa.com.br")
    AD_USERNAME="${AD_USERNAME//$'\r'/}"
    [ -n "$AD_USERNAME" ] && break; warn "Campo obrigatório."
  done
  while true; do
    AD_PASSWORD=$(ask_secret "Senha da conta de serviço")
    [ -n "$AD_PASSWORD" ] && break; warn "Campo obrigatório."
  done
  while true; do
    AD_DOMAIN=$(ask "Domínio NetBIOS / UPN suffix" "empresa.com.br")
    AD_DOMAIN="${AD_DOMAIN//$'\r'/}"
    [ -n "$AD_DOMAIN" ] && break; warn "Campo obrigatório."
  done
  ok "Active Directory configurado"

  # 1.3 Administrador
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.3  Administrador inicial${NC}"; echo ""
  while true; do
    ADMIN_USER=$(ask "Nome de usuário" "admin")
    ADMIN_USER="${ADMIN_USER//$'\r'/}"
    [ -n "$ADMIN_USER" ] && break; warn "Campo obrigatório."
  done
  while true; do
    ADMIN_EMAIL=$(ask "Email do administrador" "admin@empresa.com.br")
    ADMIN_EMAIL="${ADMIN_EMAIL//$'\r'/}"
    is_valid_email "$ADMIN_EMAIL" && break
    warn "Formato inválido. Ex: admin@empresa.com.br"
  done
  echo ""; info "Senha: mín. 12 caracteres, maiúsculas, minúsculas, números e símbolos."; echo ""
  while true; do
    ADMIN_PASSWORD=$(ask_secret "Senha do administrador")
    [ "${#ADMIN_PASSWORD}" -lt 12 ] && warn "Mínimo 12 caracteres." && continue
    local STR; STR=$(password_strength "$ADMIN_PASSWORD")
    echo -e "  ${DIM}Força: ${STR}${NC}"
    local CONF; CONF=$(ask_secret "Confirme a senha")
    [ "$ADMIN_PASSWORD" = "$CONF" ] && break
    warn "Senhas não coincidem."
  done
  ok "Administrador: ${ADMIN_USER} (${ADMIN_EMAIL})"

  # 1.4 Azure AD
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.4  Azure AD / Microsoft 365 ${DIM}(opcional)${NC}"; echo ""
  info "Necessário para gerenciar licenças M365, MFA e sessões."; echo ""
  if confirm "Configurar Azure AD / M365 agora" "s"; then
    SETUP_GRAPH="y"
    while true; do AZURE_TENANT_ID=$(ask "Tenant ID");     AZURE_TENANT_ID="${AZURE_TENANT_ID//$'\r'/}"; [ -n "$AZURE_TENANT_ID" ] && break; warn "Obrigatório."; done
    while true; do AZURE_CLIENT_ID=$(ask "Client ID");     AZURE_CLIENT_ID="${AZURE_CLIENT_ID//$'\r'/}"; [ -n "$AZURE_CLIENT_ID" ] && break; warn "Obrigatório."; done
    while true; do AZURE_CLIENT_SECRET=$(ask_secret "Client Secret"); [ -n "$AZURE_CLIENT_SECRET" ] && break; warn "Obrigatório."; done
    ok "Azure AD / M365 configurado"
  else
    warn "Azure AD ignorado. Configure depois em Configurações → Azure / M365."
  fi

  # 1.5 SMTP
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.5  Email — SMTP ${DIM}(opcional)${NC}"; echo ""
  if confirm "Configurar SMTP agora" "s"; then
    SETUP_SMTP="y"
    while true; do SMTP_HOST=$(ask "Servidor SMTP" "smtp.empresa.com.br"); SMTP_HOST="${SMTP_HOST//$'\r'/}"; [ -n "$SMTP_HOST" ] && break; warn "Obrigatório."; done
    SMTP_PORT=$(ask "Porta SMTP" "587"); SMTP_PORT="${SMTP_PORT//$'\r'/}"
    confirm "Usar TLS/SSL (true para 465)" "s" && SMTP_SECURE="true" || SMTP_SECURE="false"
    SMTP_USER=$(ask "Usuário SMTP (em branco para relay)"); SMTP_USER="${SMTP_USER//$'\r'/}"
    [ -n "$SMTP_USER" ] && SMTP_PASS=$(ask_secret "Senha SMTP")
    while true; do
      SMTP_FROM=$(ask "Email remetente" "admanager@${APP_DOMAIN}"); SMTP_FROM="${SMTP_FROM//$'\r'/}"
      is_valid_email "$SMTP_FROM" && break; warn "Formato inválido."
    done
    ok "SMTP: ${SMTP_HOST}:${SMTP_PORT}"
  else
    SMTP_FROM="admanager@${APP_DOMAIN}"
    warn "SMTP ignorado. Configure depois em Configurações → Notificações."
  fi

  # 1.6 Teams
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.6  Microsoft Teams ${DIM}(opcional)${NC}"; echo ""
  info "Crie um Incoming Webhook no Teams para obter a URL."; echo ""
  if confirm "Configurar alertas no Teams agora" "n"; then
    SETUP_TEAMS="y"
    while true; do
      TEAMS_WEBHOOK_URL=$(ask "URL do Incoming Webhook"); TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL//$'\r'/}"
      [[ "$TEAMS_WEBHOOK_URL" =~ ^https:// ]] && break
      warn "URL inválida. Deve começar com https://"
    done
    ok "Teams configurado"
  else
    warn "Teams ignorado. Configure depois em Configurações."
  fi

  # 1.7 Certificado
  echo ""; div; echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"; echo ""
  echo -e "   ${GREEN}1)${NC} Let's Encrypt   — gratuito, renovação automática"
  echo -e "   ${GREEN}2)${NC} PKI corporativa — self-signed temporário"
  echo -e "   ${GREEN}3)${NC} Self-signed     — para ambientes internos e testes"
  echo ""
  while true; do
    CERT_OPCAO=$(ask "Tipo de certificado" "3"); CERT_OPCAO="${CERT_OPCAO//$'\r'/}"
    case "$CERT_OPCAO" in 1|2|3) break;; *) warn "Digite 1, 2 ou 3.";; esac
  done

  # Resumo
  banner
  echo -e "  ${WHITE}${BOLD}RESUMO — CONFIRME ANTES DE PROSSEGUIR${NC}"; echo ""; div; echo ""
  echo -e "  ${CYAN}Aplicação${NC}"
  echo -e "    URL:              https://${APP_DOMAIN}"
  echo -e "    IP do servidor:   ${SERVER_IP}"
  echo ""
  echo -e "  ${CYAN}Active Directory${NC}"
  echo -e "    URL:              ${AD_URL}"
  echo -e "    Base DN:          ${AD_BASE_DN}"
  echo -e "    Conta de serviço: ${AD_USERNAME}"
  echo -e "    Domínio:          ${AD_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}Microsoft 365${NC}"
  [ "$SETUP_GRAPH" = "y" ] \
    && echo -e "    Integração:       ${GREEN}Habilitada — Tenant: ${AZURE_TENANT_ID}${NC}" \
    || echo -e "    Integração:       ${DIM}Não configurada${NC}"
  echo ""
  echo -e "  ${CYAN}Administrador${NC}"
  echo -e "    Usuário:          ${ADMIN_USER}"
  echo -e "    Email:            ${ADMIN_EMAIL}"
  echo ""
  echo -e "  ${CYAN}Notificações${NC}"
  [ "$SETUP_SMTP"  = "y" ] \
    && echo -e "    SMTP:             ${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}" \
    || echo -e "    SMTP:             ${DIM}Não configurado${NC}"
  [ "$SETUP_TEAMS" = "y" ] \
    && echo -e "    Teams:            ${GREEN}Habilitado${NC}" \
    || echo -e "    Teams:            ${DIM}Não configurado${NC}"
  echo ""
  echo -e "  ${CYAN}Certificado TLS${NC}"
  case "$CERT_OPCAO" in
    1) echo -e "    Tipo:             ${GREEN}Let's Encrypt${NC}" ;;
    2) echo -e "    Tipo:             ${YELLOW}PKI corporativa (self-signed temporário)${NC}" ;;
    3) echo -e "    Tipo:             ${DIM}Self-signed (10 anos)${NC}" ;;
  esac
  echo ""; div; echo ""
  confirm "Iniciar a instalação com estas configurações" "s" \
    || { echo "Cancelado."; exit 0; }
}

# =============================================================================
#  ETAPA 2 — PREPARAÇÃO DO SISTEMA
# =============================================================================
step_2_prepare() {
  step "2" "PREPARAÇÃO DO SISTEMA"

  sub "Atualizando pacotes do sistema..."
  q apt-get update -qq
  q apt-get upgrade -y -qq
  ok "Pacotes atualizados"

  sub "Instalando dependências essenciais..."
  q apt-get install -y -qq \
    curl wget git openssl netcat-openbsd \
    python3 jq unzip ca-certificates gnupg \
    ufw fail2ban auditd chrony lsb-release
  ok "Dependências instaladas"

  sub "Criando usuário de serviço '${SERVICE_USER}'..."
  if ! id -u "$SERVICE_USER" > /dev/null 2>&1; then
    q useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    ok "Usuário '${SERVICE_USER}' criado"
  else
    ok "Usuário '${SERVICE_USER}' já existe"
  fi

  sub "Criando estrutura de diretórios..."
  q mkdir -p \
    "${INSTALL_DIR}/logs" \
    "${INSTALL_DIR}/backups" \
    "${INSTALL_DIR}/scripts" \
    "${INSTALL_DIR}/infra/nginx/ssl" \
    "${INSTALL_DIR}/infra/nginx/conf.d"
  ok "Diretórios criados"

  sub "Configurando limites do kernel..."
  cat > /etc/sysctl.d/99-admanager.conf << 'EOF'
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
fs.inotify.max_user_watches = 524288
EOF
  q sysctl --system
  ok "Limites do kernel configurados"
}

# =============================================================================
#  ETAPA 3 — SEGURANÇA E NTP
# =============================================================================
step_3_security() {
  step "3" "SEGURANÇA E NTP"

  sub "Configurando firewall UFW..."
  q ufw --force reset
  q ufw default deny incoming
  q ufw default allow outgoing
  q ufw allow ssh   comment "SSH"
  q ufw allow http  comment "HTTP redirect"
  q ufw allow https comment "HTTPS"
  q ufw --force enable
  ok "UFW configurado: portas 22, 80 e 443 abertas"

  sub "Configurando fail2ban..."
  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 7200
findtime = 600
maxretry = 3

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
EOF
  q systemctl enable fail2ban
  q systemctl restart fail2ban
  ok "fail2ban configurado (3 tentativas → bloqueio 2h)"

  sub "Configurando auditd..."
  cat > /etc/audit/rules.d/99-admanager.rules << EOF
-w ${INSTALL_DIR}/.env                            -p rwxa -k admanager-config
-w ${INSTALL_DIR}/infra/nginx/ssl/key.pem         -p rwxa -k admanager-tls-key
-w /etc/systemd/system/ad-license-manager.service -p rwxa -k admanager-systemd
-w /etc/cron.d/admanager                          -p rwxa -k admanager-cron
EOF
  q augenrules --load || true
  q systemctl enable auditd
  q systemctl restart auditd
  ok "auditd configurado"

  sub "Configurando chrony (NTP)..."
  q systemctl enable chrony
  q systemctl start  chrony
  q timedatectl set-ntp true
  ok "chrony configurado"

  sub "Aplicando SSH hardening..."
  local SSHD="/etc/ssh/sshd_config"
  cp "${SSHD}" "${SSHD}.bak-$(date +%Y%m%d)" 2>/dev/null || true
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'          "$SSHD"
  sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/'                 "$SSHD"
  sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' "$SSHD"
  sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/'   "$SSHD"
  sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/'              "$SSHD"
  q systemctl restart sshd
  ok "SSH hardening aplicado"
}

# =============================================================================
#  ETAPA 4 — DOCKER ENGINE E COMPOSE PLUGIN
# =============================================================================
step_4_docker() {
  step "4" "DOCKER ENGINE E COMPOSE PLUGIN"

  sub "Removendo versões antigas do Docker..."
  q apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  ok "Versões antigas removidas"

  sub "Adicionando chave GPG oficial do Docker..."
  q install -m 0755 -d /etc/apt/keyrings
  q rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$INSTALL_LOG" 2>&1
  q chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  sub "Adicionando repositório do Docker..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  q apt-get update -qq
  ok "Repositório Docker adicionado"

  sub "Instalando Docker Engine e Compose Plugin..."
  q apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "Docker Engine e Compose Plugin instalados"

  sub "Configurando daemon do Docker..."
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true,
  "userland-proxy": false,
  "default-address-pools": [{ "base": "172.20.0.0/16", "size": 24 }]
}
EOF
  q systemctl enable docker
  q systemctl restart docker
  ok "Daemon do Docker configurado"

  q usermod -aG docker "$SERVICE_USER"
  ok "Usuário '${SERVICE_USER}' adicionado ao grupo docker"

  sub "Verificando instalação..."
  q docker run --rm hello-world \
    && ok "Docker funcionando corretamente" \
    || fail "Docker não está funcionando. Veja: ${INSTALL_LOG}"

  local DV CV
  DV=$(docker --version       | grep -oP '\d+\.\d+\.\d+' | head -1)
  CV=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${DV} · Compose ${CV}"
}

# =============================================================================
#  ETAPA 5 — DOWNLOAD DO CÓDIGO-FONTE
# =============================================================================
step_5_clone() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    sub "Repositório existente. Atualizando..."
    cd "${INSTALL_DIR}"
    q git fetch origin
    q git reset --hard origin/main
    ok "Código atualizado"
  else
    sub "Clonando repositório em ${INSTALL_DIR}..."
    local TMP; TMP=$(mktemp -d)
    if q git clone "$REPO_URL" "$TMP"; then
      cp -a "${TMP}/." "${INSTALL_DIR}/"
      rm -rf "$TMP"
      ok "Repositório clonado"
    else
      rm -rf "$TMP"
      fail "Falha ao clonar ${REPO_URL}. Verifique a URL e acesso."
    fi
  fi

  find "${INSTALL_DIR}" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  ok "Scripts com permissão de execução"
}

# =============================================================================
#  ETAPA 6 — ARQUIVO .ENV
# =============================================================================
step_6_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

  sub "Gerando segredos criptográficos aleatórios..."
  DB_PASSWORD=$(gen_password)
  REDIS_PASSWORD=$(gen_password)
  JWT_SECRET=$(gen_secret)
  JWT_REFRESH_SECRET=$(gen_secret)
  ENCRYPTION_KEY=$(gen_hex)
  ok "Segredos gerados"

  sub "Escrevendo ${INSTALL_DIR}/.env..."
  cat > "${INSTALL_DIR}/.env" << EOF
# ════════════════════════════════════════════════════════════════════════════
#  AD License Manager — Variáveis de Ambiente
#  Gerado pelo instalador v${INSTALLER_VERSION} em $(date '+%Y-%m-%d %H:%M:%S')
#  ATENÇÃO: Permissão 600. Não commite no repositório.
# ════════════════════════════════════════════════════════════════════════════

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
  ok ".env gerado com permissão 600"

  local BAK="${INSTALL_DIR}/.env.backup-$(date +%Y%m%d-%H%M%S)"
  cp "${INSTALL_DIR}/.env" "$BAK"; chmod 600 "$BAK"
  ok "Backup salvo em: $(basename "$BAK")"
}

# =============================================================================
#  ETAPA 7 — CERTIFICADO TLS
# =============================================================================
step_7_tls() {
  step "7" "CONFIGURAÇÃO DO CERTIFICADO TLS"

  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  if [ "$CERT_OPCAO" = "1" ]; then
    sub "Instalando Certbot..."
    q apt-get install -y -qq certbot
    ok "Certbot instalado"

    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nginx" \
      && q docker compose -f "${INSTALL_DIR}/docker-compose.yml" stop nginx || true

    sub "Gerando certificado Let's Encrypt para ${APP_DOMAIN}..."
    if certbot certonly \
        --standalone --non-interactive --agree-tos \
        --email "$ADMIN_EMAIL" -d "$APP_DOMAIN" \
        >> "$INSTALL_LOG" 2>&1; then
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
chmod 644 ${SSL_DIR}/cert.pem
chmod 600 ${SSL_DIR}/key.pem
docker compose -f ${INSTALL_DIR}/docker-compose.yml restart nginx
echo "\$(date '+%Y-%m-%d %H:%M:%S') Renovação concluída." >> ${INSTALL_DIR}/logs/certbot.log
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      echo "0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh" \
        > /etc/cron.d/admanager-certbot
      ok "Renovação automática agendada (dia 1 de cada mês às 02:00)"
    else
      warn "Let's Encrypt falhou. Gerando self-signed como fallback."
      CERT_OPCAO="3"
    fi
  fi

  if [ "$CERT_OPCAO" != "1" ] || [ ! -f "${SSL_DIR}/cert.pem" ]; then
    sub "Gerando certificado self-signed RSA 4096 (10 anos)..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
      -keyout "${SSL_DIR}/key.pem" \
      -out    "${SSL_DIR}/cert.pem" \
      -subj   "/CN=${APP_DOMAIN}/O=AD License Manager/C=BR/OU=TI" \
      -addext "subjectAltName=DNS:${APP_DOMAIN},DNS:localhost,IP:${SERVER_IP},IP:127.0.0.1" \
      >> "$INSTALL_LOG" 2>&1 || fail "Falha ao gerar certificado self-signed."
    ok "Certificado self-signed gerado"
    if [ "$CERT_OPCAO" = "2" ]; then
      warn "Substitua pela PKI corporativa após a instalação:"
      warn "  ${SSL_DIR}/cert.pem  e  ${SSL_DIR}/key.pem"
      warn "Depois execute: docker compose restart nginx"
    fi
  fi

  chown "${SERVICE_USER}:${SERVICE_USER}" "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  chmod 600 "${SSL_DIR}/key.pem"

  openssl x509 -in "${SSL_DIR}/cert.pem" -noout >> "$INSTALL_LOG" 2>&1 \
    || fail "Certificado TLS inválido após geração."

  local EXPIRY
  EXPIRY=$(openssl x509 -in "${SSL_DIR}/cert.pem" -noout -enddate | cut -d= -f2)
  ok "Certificado válido — expira em: ${EXPIRY}"
}

# =============================================================================
#  ETAPA 8 — BUILD DAS IMAGENS DOCKER
# =============================================================================
step_8_build() {
  step "8" "BUILD DAS IMAGENS DOCKER"

  cd "${INSTALL_DIR}"
  info "Este processo pode levar de 10 a 25 minutos."
  info "Acompanhe: tail -f ${INSTALL_LOG}"; echo ""

  sub "Construindo todas as imagens..."
  docker compose build \
    --no-cache \
    --progress=plain \
    >> "$INSTALL_LOG" 2>&1 \
    || fail "Erro no build. Detalhes em: ${INSTALL_LOG}"
  ok "Todas as imagens construídas com sucesso"

  sub "Imagens geradas:"
  docker compose images 2>/dev/null | tail -n +2 | \
    while IFS= read -r l; do echo "    ${l}"; done || true
}

# =============================================================================
#  ETAPA 9 — INICIALIZAÇÃO DOS SERVIÇOS
# =============================================================================
step_9_start() {
  step "9" "INICIALIZAÇÃO DOS SERVIÇOS"

  cd "${INSTALL_DIR}"

  sub "Iniciando PostgreSQL e Redis..."
  q docker compose up -d postgres redis
  ok "Containers de infraestrutura iniciados"; echo ""

  wait_for "PostgreSQL" \
    "docker compose exec -T postgres pg_isready -U admanager -d admanager" \
    40 3 || fail "PostgreSQL não ficou pronto. Veja: docker compose logs postgres"
  ok "PostgreSQL aceitando conexões"

  wait_for "Redis" \
    "docker compose exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping | grep -q PONG" \
    20 2 || fail "Redis não ficou pronto. Veja: docker compose logs redis"
  ok "Redis respondendo"; echo ""

  sub "Aplicando migrations do banco de dados..."
  q docker compose run --rm backend node dist/migrate.js \
    || fail "Erro nas migrations. Detalhes: ${INSTALL_LOG}"
  ok "Migrations aplicadas"

  sub "Criando dados iniciais e usuário administrador..."
  q docker compose run --rm backend node dist/seed.js \
    || fail "Erro no seed. Detalhes: ${INSTALL_LOG}"
  ok "Dados iniciais criados"

  sub "Iniciando todos os serviços..."
  q docker compose up -d
  ok "Todos os containers iniciados"; echo ""

  wait_for "Backend API (até 120s)" \
    "curl -sf http://localhost:3001/health" \
    30 4 || warn "Backend ainda iniciando. Verifique: docker compose logs backend"

  echo ""; sub "Status dos containers:"; echo ""
  docker compose ps 2>/dev/null | while IFS= read -r l; do echo "    ${l}"; done
}

# =============================================================================
#  ETAPA 10 — SYSTEMD
# =============================================================================
step_10_systemd() {
  step "10" "INICIALIZAÇÃO AUTOMÁTICA COM SYSTEMD"

  sub "Criando serviço systemd..."
  cat > /etc/systemd/system/ad-license-manager.service << EOF
[Unit]
Description=AD License Manager
Documentation=file://${INSTALL_DIR}/README.md
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
  ok "Serviço systemd criado e habilitado para boot automático"
}

# =============================================================================
#  ETAPA 11 — SCRIPTS OPERACIONAIS
# =============================================================================
step_11_scripts() {
  step "11" "CRIAÇÃO DE SCRIPTS OPERACIONAIS"

  # ── backup.sh ────────────────────────────────────────────────────────────
  sub "Criando scripts/backup.sh..."
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

REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" \
  | cut -d= -f2- | tr -d "\"'")

log "Dump do PostgreSQL..."
if docker compose -f "${INSTALL_DIR}/docker-compose.yml" \
    exec -T postgres \
    pg_dump -U admanager admanager \
    --format=custom --compress=9 \
    > "${BACKUP_DIR}/database.dump"; then
  log "Banco: OK ($(du -sh "${BACKUP_DIR}/database.dump" | cut -f1))"
else
  log "ERRO: Falha no dump."; exit 1
fi

cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"
chmod 600 "${BACKUP_DIR}/.env.bak"
log "Configurações: OK"

if ls "${INSTALL_DIR}/logs/"*.log 1>/dev/null 2>&1; then
  tar -czf "${BACKUP_DIR}/logs.tar.gz" \
    -C "${INSTALL_DIR}" logs/ 2>/dev/null \
    && log "Logs: OK" || log "AVISO: Logs não comprimidos."
fi

find "${INSTALL_DIR}/backups" -maxdepth 1 -type d \
  -mtime "+${RETENCAO}" -exec rm -rf {} + 2>/dev/null || true

log "=== Backup concluído. Tamanho: $(du -sh "$BACKUP_DIR" | cut -f1) em ${BACKUP_DIR} ==="
BACKUP_SCRIPT
  ok "backup.sh criado"

  # ── health-check.sh ──────────────────────────────────────────────────────
  sub "Criando scripts/health-check.sh..."
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
  if eval "$cmd" 2>/dev/null | grep -q "$match"; then
    echo "  ✓  ${label}"
  else
    echo "  ✗  ${label}"; FALHAS=$((FALHAS+1))
  fi
}

echo ""
echo "  ── Health Check AD License Manager — $(date '+%d/%m/%Y %H:%M:%S')"
echo ""
check "PostgreSQL" \
  "docker compose -f '$COMPOSE' exec -T postgres pg_isready -U admanager" "accepting"
check "Redis" \
  "docker compose -f '$COMPOSE' exec -T redis redis-cli -a '$REDIS_PASSWORD' --no-auth-warning ping" "PONG"
check "Backend API" \
  "curl -sf http://localhost:3001/health" "."
check "Nginx HTTPS" \
  "curl -skf https://localhost/health" "."
check "Worker" \
  "docker compose -f '$COMPOSE' ps worker" "running"
echo ""
if [ "$FALHAS" -gt 0 ]; then
  echo "  ✗  ${FALHAS} serviço(s) com problema."
  echo "     Veja: docker compose -f '${COMPOSE}' logs"
  echo "$(date '+%Y-%m-%d %H:%M:%S') FALHA: ${FALHAS} servico(s)" >> "$LOG"
  exit 1
else
  echo "  ✓  Todos os serviços saudáveis."
  echo "$(date '+%Y-%m-%d %H:%M:%S') OK" >> "$LOG"
fi
echo ""
HEALTH_SCRIPT
  ok "health-check.sh criado"

  # ── update.sh ────────────────────────────────────────────────────────────
  sub "Criando scripts/update.sh..."
  cat > "${INSTALL_DIR}/scripts/update.sh" << 'UPDATE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"

echo "=== Atualização iniciada em $(date '+%d/%m/%Y %H:%M:%S') ==="
echo ""
echo "Criando backup antes de atualizar..."
bash "${INSTALL_DIR}/scripts/backup.sh"
echo ""
echo "Baixando atualizações..."
cd "${INSTALL_DIR}"
git fetch origin
git reset --hard origin/main
echo ""
echo "Reconstruindo imagens Docker..."
docker compose build --no-cache --progress=plain
echo ""
echo "Aplicando migrations..."
docker compose run --rm backend node dist/migrate.js
echo ""
echo "Reiniciando serviços..."
docker compose up -d --remove-orphans
echo ""
echo "Aguardando inicialização (15s)..."
sleep 15
echo ""
bash "${INSTALL_DIR}/scripts/health-check.sh"
echo ""
echo "=== Atualização concluída com sucesso ==="
UPDATE_SCRIPT
  ok "update.sh criado"

  # ── restore.sh ───────────────────────────────────────────────────────────
  sub "Criando scripts/restore.sh..."
  cat > "${INSTALL_DIR}/scripts/restore.sh" << 'RESTORE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"

usage() {
  echo ""
  echo "  Uso: sudo bash restore.sh YYYY-MM-DD"
  echo ""
  echo "  Backups disponíveis:"
  ls -d "${INSTALL_DIR}/backups/"*/ 2>/dev/null \
    | xargs -I{} basename {} \
    || echo "  Nenhum backup encontrado."
  echo ""
  exit 1
}

DATE="${1:-}"
[ -z "$DATE" ] && { echo "Informe a data do backup."; usage; }

BACKUP_DIR="${INSTALL_DIR}/backups/${DATE}"
[ -d "$BACKUP_DIR"                 ] || { echo "Backup não encontrado: ${BACKUP_DIR}"; usage; }
[ -f "${BACKUP_DIR}/database.dump" ] || { echo "Dump não encontrado em: ${BACKUP_DIR}"; exit 1; }

echo ""
echo "=== Restauração — backup de ${DATE} ==="
echo ""
echo "ATENÇÃO: Os dados atuais serão substituídos pelo backup de ${DATE}."
echo ""
read -rp "  Confirme digitando 'RESTAURAR': " CONFIRM
[ "$CONFIRM" = "RESTAURAR" ] || { echo "Cancelado."; exit 0; }

echo ""
echo "Parando serviços dependentes..."
cd "${INSTALL_DIR}"
docker compose stop backend worker

echo "Restaurando banco de dados..."
docker compose exec -T postgres pg_restore \
  --username admanager \
  --dbname   admanager \
  --clean --if-exists \
  < "${BACKUP_DIR}/database.dump"

echo "Reiniciando serviços..."
docker compose start backend worker

echo ""
echo "Aguardando inicialização (10s)..."
sleep 10

echo ""
bash "${INSTALL_DIR}/scripts/health-check.sh"

echo ""
echo "=== Restauração concluída. Dados de ${DATE} restaurados. ==="
RESTORE_SCRIPT
  ok "restore.sh criado"

  # ── Permissões finais ────────────────────────────────────────────────────
  chmod +x "${INSTALL_DIR}/scripts/"*.sh
  chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/scripts/"*.sh
  ok "Permissões dos scripts configuradas"
}

# =============================================================================
#  ETAPA 12 — CRON JOBS
# =============================================================================
step_12_cron() {
  step "12" "CONFIGURAÇÃO DE CRON JOBS AUTOMÁTICOS"

  sub "Criando /etc/cron.d/admanager..."
  cat > /etc/cron.d/admanager << EOF
# AD License Manager — Tarefas automáticas
# Gerado em $(date '+%Y-%m-%d %H:%M:%S')

# Backup diário às 03:00
0 3 * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/backup.sh >> ${INSTALL_DIR}/logs/backup.log 2>&1

# Health check a cada 5 minutos
*/5 * * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/health-check.sh >> ${INSTALL_DIR}/logs/health.log 2>&1

# Limpeza de logs com mais de 7 dias (a cada 6 horas)
0 */6 * * * ${SERVICE_USER} find ${INSTALL_DIR}/logs -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Limpeza de imagens Docker não utilizadas (diariamente às 04:00)
0 4 * * * root docker system prune -f >> ${INSTALL_DIR}/logs/docker-prune.log 2>&1
EOF

  chmod 644 /etc/cron.d/admanager
  ok "Cron jobs configurados"
  ok "  Backup diário às 03:00"
  ok "  Health check a cada 5 minutos"
  ok "  Limpeza de logs a cada 6 horas"
  ok "  Limpeza Docker diária às 04:00"
}

# =============================================================================
#  ETAPA 13 — PERMISSÕES FINAIS
# =============================================================================
step_13_permissions() {
  step "13" "PERMISSÕES FINAIS E AUDITORIA"

  sub "Aplicando permissões na instalação..."
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
  chmod 750 "${INSTALL_DIR}"
  chmod 600 "${INSTALL_DIR}/.env"
  chmod 700 "${INSTALL_DIR}/logs"
  chmod 700 "${INSTALL_DIR}/backups"
  chmod 700 "${INSTALL_DIR}/scripts"
  chmod 644 "${INSTALL_DIR}/infra/nginx/ssl/cert.pem"
  chmod 600 "${INSTALL_DIR}/infra/nginx/ssl/key.pem"
  ok "Permissões aplicadas"

  sub "Verificando serviços de segurança..."
  systemctl is-active --quiet ufw      && ok "UFW ativo"      || warn "UFW não está ativo"
  systemctl is-active --quiet fail2ban && ok "fail2ban ativo" || warn "fail2ban não está ativo"
  systemctl is-active --quiet auditd   && ok "auditd ativo"   || warn "auditd não está ativo"
  systemctl is-active --quiet chrony   && ok "chrony ativo"   || warn "chrony não está ativo"
}

# =============================================================================
#  ETAPA 14 — VERIFICAÇÃO FINAL E RESUMO
# =============================================================================
step_14_summary() {
  step "14" "VERIFICAÇÃO FINAL E RESUMO"

  cd "${INSTALL_DIR}"

  sub "Executando health check completo..."
  echo ""
  bash "${INSTALL_DIR}/scripts/health-check.sh" || true
  echo ""

  sub "Verificando certificado TLS..."
  local EXPIRY
  EXPIRY=$(openssl x509 -in "${INSTALL_DIR}/infra/nginx/ssl/cert.pem" \
    -noout -enddate 2>/dev/null | cut -d= -f2 || echo "não verificado")
  ok "Certificado TLS — expira em: ${EXPIRY}"

  sub "Testando acesso HTTPS..."
  if curl -skf "https://localhost/health" > /dev/null 2>&1; then
    ok "Nginx respondendo via HTTPS"
  else
    warn "Nginx ainda não respondeu. Aguardando 15s..."
    sleep 15
    curl -skf "https://localhost/health" > /dev/null 2>&1 \
      && ok "Nginx respondendo via HTTPS" \
      || warn "Nginx não respondeu. Verifique: docker compose logs nginx"
  fi

  local INSTALL_END DURACAO
  INSTALL_END=$(date +%s)
  DURACAO=$(( (INSTALL_

