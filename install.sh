#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Completo e Autônomo
#  Versão 2.1.1 — Julho de 2026
#  Ubuntu Server 22.04 LTS / 24.04 LTS
#
#  Uso: sudo bash install.sh
#
#  Etapas executadas automaticamente:
#    0.  Verificações iniciais
#    1.  Coleta interativa de informações
#    2.  Preparação do sistema
#    3.  Segurança (UFW, fail2ban, auditd, NTP, SSH)
#    4.  Docker Engine + Compose Plugin
#    5.  Download do código-fonte
#    6.  Arquivo .env com segredos gerados automaticamente
#    7.  Certificado TLS (Let's Encrypt, PKI ou self-signed)
#    8.  Build das imagens Docker
#    9.  Inicialização, migrations e seed
#    10. Systemd (boot automático)
#    11. Scripts operacionais (backup, health, update, restore)
#    12. Cron jobs automáticos
#    13. Permissões finais
#    14. Verificação final e resumo
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly INSTALLER_VERSION="2.1.1"
readonly INSTALL_DIR="/opt/ad-license-manager"
readonly INSTALL_LOG="/tmp/admanager-install-$(date +%Y%m%d-%H%M%S).log"
readonly INSTALL_START=$(date +%s)
readonly REPO_URL="${REPO_URL:-https://github.com/sua-org/ad-license-manager.git}"
readonly SERVICE_USER="admanager"
readonly REQUIRED_RAM_GB=4
readonly REQUIRED_DISK_GB=15

# ─── Variáveis de configuração ────────────────────────────────────────────────
APP_DOMAIN=""
AD_URL=""
AD_BASE_DN=""
AD_USERNAME=""
AD_PASSWORD=""
AD_DOMAIN=""
AD_HOST=""
AD_PORT=""
AZURE_TENANT_ID=""
AZURE_CLIENT_ID=""
AZURE_CLIENT_SECRET=""
ADMIN_USER="admin"
ADMIN_PASSWORD=""
ADMIN_EMAIL=""
SMTP_HOST=""
SMTP_PORT="587"
SMTP_SECURE="false"
SMTP_USER=""
SMTP_PASS=""
SMTP_FROM=""
TEAMS_WEBHOOK_URL=""
DB_PASSWORD=""
REDIS_PASSWORD=""
JWT_SECRET=""
JWT_REFRESH_SECRET=""
ENCRYPTION_KEY=""
SETUP_SMTP="n"
SETUP_TEAMS="n"
SETUP_GRAPH="n"
CERT_OPCAO="3"
SERVER_IP=""
UBUNTU_VERSION=""
UBUNTU_CODENAME="jammy"

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Log ──────────────────────────────────────────────────────────────────────
touch "$INSTALL_LOG"
chmod 600 "$INSTALL_LOG"

# Executa silenciosamente, grava no log
q() { "$@" >> "$INSTALL_LOG" 2>&1; }

# ─── UI ───────────────────────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════════╗"
  echo "  ║      AD License Manager — Instalador Autônomo v${INSTALLER_VERSION}              ║"
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
  echo ""
  echo -e "  ${DIM}Log completo disponível em: ${INSTALL_LOG}${NC}"
  echo ""
  exit 1
}

ask() {
  local label="$1"
  local default="${2:-}"
  if [ -n "$default" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} ${DIM}[${default}]${NC}: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC}: "
  fi
  local val
  read -r val
  echo "${val:-$default}"
}

ask_secret() {
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}$1${NC}: "
  local val
  read -rs val
  echo ""
  echo "$val"
}

confirm() {
  local label="$1"
  local default="${2:-s}"
  local hint
  if [ "$default" = "s" ]; then
    hint="${GREEN}S${NC}/n"
  else
    hint="s/${GREEN}N${NC}"
  fi
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} [${hint}]: "
  local val
  read -r val
  val="${val:-$default}"
  [[ "$val" =~ ^[SsYy]$ ]]
}

pause() {
  echo ""
  read -rp "$(echo -e "  ${DIM}Pressione ENTER para continuar...${NC}")"
}

wait_for() {
  local label="$1"
  local cmd="$2"
  local tries="${3:-30}"
  local interval="${4:-3}"
  echo -ne "  Aguardando ${label}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if eval "$cmd" >> "$INSTALL_LOG" 2>&1; then
      echo -e " ${GREEN}OK${NC}"
      return 0
    fi
    echo -n "."
    sleep "$interval"
    i=$((i + 1))
  done
  echo -e " ${RED}timeout após $((tries * interval))s${NC}"
  return 1
}

# ─── Validações ───────────────────────────────────────────────────────────────
is_valid_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

is_valid_email() {
  [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

is_valid_ldap_url() {
  [[ "$1" =~ ^ldaps?://[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]
}

is_valid_base_dn() {
  [[ "$1" =~ ^(DC|OU|CN)=[^,]+(,(DC|OU|CN)=[^,]+)*$ ]]
}

password_strength() {
  local p="$1"
  local score=0
  [ "${#p}" -ge 12 ]                    && score=$((score + 1))
  echo "$p" | grep -q '[A-Z]'           && score=$((score + 1))
  echo "$p" | grep -q '[a-z]'           && score=$((score + 1))
  echo "$p" | grep -q '[0-9]'           && score=$((score + 1))
  echo "$p" | grep -q '[^a-zA-Z0-9]'   && score=$((score + 1))
  case $score in
    0|1) echo "Muito fraca" ;;
      2) echo "Fraca"       ;;
      3) echo "Regular"     ;;
      4) echo "Forte"       ;;
      5) echo "Muito forte" ;;
  esac
}

# ─── Geração de segredos ──────────────────────────────────────────────────────
gen_secret()   { openssl rand -base64 64 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-80; }
gen_password() { openssl rand -base64 32 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32; }
gen_hex()      { openssl rand -hex 32; }

detect_ip() {
  SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' \
    || hostname -I 2>/dev/null | awk '{print $1}' \
    || echo "127.0.0.1")
}

# =============================================================================
#  ETAPA 0 — VERIFICAÇÕES INICIAIS
# =============================================================================
step_0_verify() {
  banner
  echo -e "  ${DIM}Log da instalação: ${INSTALL_LOG}${NC}"
  echo ""

  [ "$(id -u)" -eq 0 ] || fail "Execute como root: sudo bash install.sh"

  if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "?")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    if [[ "$UBUNTU_VERSION" == "22.04" || "$UBUNTU_VERSION" == "24.04" ]]; then
      ok "Ubuntu ${UBUNTU_VERSION} LTS (${UBUNTU_CODENAME})"
    else
      warn "Ubuntu ${UBUNTU_VERSION} não é LTS suportada oficialmente (22.04 / 24.04)."
      confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
    fi
  else
    warn "Sistema não identificado como Ubuntu."
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
  fi

  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|aarch64) ok "Arquitetura: ${ARCH}" ;;
    *) fail "Arquitetura ${ARCH} não suportada. Use x86_64 ou aarch64." ;;
  esac

  local RAM_GB
  RAM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
  if   [ "$RAM_GB" -lt "$REQUIRED_RAM_GB" ]; then
    fail "RAM insuficiente: ${RAM_GB}GB. Mínimo: ${REQUIRED_RAM_GB}GB."
  elif [ "$RAM_GB" -lt 8 ]; then
    warn "RAM: ${RAM_GB}GB — recomendado 8GB+ para produção."
  else
    ok "RAM: ${RAM_GB}GB"
  fi

  local DISK_KB DISK_GB
  DISK_KB=$(df --block-size=1K / | awk 'NR==2{print $4}')
  DISK_GB=$((DISK_KB / 1024 / 1024))
  if   [ "$DISK_GB" -lt "$REQUIRED_DISK_GB" ]; then
    fail "Disco insuficiente: ${DISK_GB}GB livres. Mínimo: ${REQUIRED_DISK_GB}GB."
  elif [ "$DISK_GB" -lt 40 ]; then
    warn "Disco: ${DISK_GB}GB livres — recomendado 40GB+ para produção."
  else
    ok "Disco: ${DISK_GB}GB livres"
  fi

  pg "Verificando acesso à internet"
  if curl -sf --max-time 15 https://download.docker.com > /dev/null 2>&1; then
    pg_ok
  else
    pg_fail
    fail "Sem acesso à internet. Necessário para download do Docker e imagens."
  fi

  detect_ip
  ok "IP do servidor: ${SERVER_IP}"

  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""
    warn "Instalação existente detectada em ${INSTALL_DIR}."
    confirm "Deseja REINSTALAR (dados existentes serão preservados)" "n" \
      || { echo "Cancelado."; exit 0; }
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
  echo -e "  Responda as perguntas abaixo. ${DIM}Padrões entre [ ] — ENTER para aceitar.${NC}"
  echo ""

  # ── 1.1 Domínio ──────────────────────────────────────────────────────────
  div
  echo -e "  ${WHITE}${BOLD}1.1  Domínio de acesso${NC}"
  echo ""
  while true; do
    APP_DOMAIN=$(ask "Domínio da interface web" "admanager.empresa.com.br")
    [ -z "$APP_DOMAIN" ]            && warn "Obrigatório." && continue
    ! is_valid_domain "$APP_DOMAIN" && warn "Formato inválido." && continue
    ok "Domínio: ${APP_DOMAIN}"; break
  done

  # ── 1.2 Active Directory ─────────────────────────────────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"
  echo ""
  info "Use ldaps:// (porta 636) para habilitar reset de senha."
  info "Use ldap://  (porta 389) somente se LDAPS não estiver disponível."
  echo ""

  while true; do
    AD_URL=$(ask "URL do Controlador de Domínio" "ldaps://dc01.empresa.com.br")
    ! is_valid_ldap_url "$AD_URL" && warn "Formato inválido (ex: ldaps://dc01.empresa.com.br)." && continue
    AD_HOST=$(echo "$AD_URL" | sed -E 's/ldaps?:\/\///' | cut -d: -f1)
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\K\d+' || { [[ "$AD_URL" == *ldaps* ]] && echo "636" || echo "389"; })
    pg "Testando conexão com o AD (${AD_HOST}:${AD_PORT})"
    if nc -zv "$AD_HOST" "$AD_PORT" > /dev/null 2>&1; then
      pg_ok; break
    else
      pg_fail; warn "Não foi possível conectar ao AD. Verifique o IP/hostname e a porta."
      confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
      break # Permite continuar mesmo com falha de conexão se o usuário aceitar
    fi
  done

  while true; do
    AD_BASE_DN=$(ask "Base DN do AD" "DC=empresa,DC=com,DC=br")
    ! is_valid_base_dn "$AD_BASE_DN" && warn "Formato inválido (ex: DC=empresa,DC=com,DC=br)." && continue
    ok "Base DN: ${AD_BASE_DN}"; break
  done

  info "A conta de serviço deve ter permissões de leitura/escrita no AD."
  info "Consulte o manual para as permissões mínimas necessárias."
  echo ""

  while true; do
    AD_USERNAME=$(ask "Usuário da conta de serviço AD" "svc-admanager@empresa.com.br")
    [ -z "$AD_USERNAME" ] && warn "Obrigatório." && continue
    ok "Usuário AD: ${AD_USERNAME}"; break
  done

  while true; do
    AD_PASSWORD=$(ask_secret "Senha da conta de serviço AD")
    [ -z "$AD_PASSWORD" ] && warn "Obrigatório." && continue
    ok "Senha AD: [oculta]"; break
  done

  AD_DOMAIN=$(ask "Nome do domínio NetBIOS (opcional)" "EMPRESA")

  # ── 1.3 Administrador inicial ────────────────────────────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.3  Administrador inicial do sistema${NC}"
  echo ""
  info "Este será o primeiro usuário com acesso total ao AD License Manager."
  info "A senha será solicitada no primeiro login."
  echo ""

  while true; do
    ADMIN_USER=$(ask "Nome de usuário" "admin")
    [ -z "$ADMIN_USER" ] && warn "Obrigatório." && continue
    ok "Usuário Admin: ${ADMIN_USER}"; break
  done

  while true; do
    ADMIN_EMAIL=$(ask "Email do administrador" "admin@empresa.com.br")
    ! is_valid_email "$ADMIN_EMAIL" && warn "Formato de email inválido." && continue
    ok "Email Admin: ${ADMIN_EMAIL}"; break
  done

  # ── 1.4 Integração Azure AD / Microsoft 365 ──────────────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.4  Integração Azure AD / Microsoft 365${NC}"
  echo ""
  info "Necessário para gerenciar licenças M365, MFA e sessões."
  info "Consulte o manual para criar o App Registration no Azure AD."
  echo ""

  if confirm "Deseja configurar a integração com Azure AD / M365 agora" "s"; then
    SETUP_GRAPH="y"
    while true; do
      AZURE_TENANT_ID=$(ask "Tenant ID (Directory ID)")
      [ -z "$AZURE_TENANT_ID" ] && warn "Obrigatório." && continue
      ok "Tenant ID: [oculto]"; break
    done
    while true; do
      AZURE_CLIENT_ID=$(ask "Client ID (Application ID)")
      [ -z "$AZURE_CLIENT_ID" ] && warn "Obrigatório." && continue
      ok "Client ID: [oculto]"; break
    done
    while true; do
      AZURE_CLIENT_SECRET=$(ask_secret "Client Secret (Valor do segredo)")
      [ -z "$AZURE_CLIENT_SECRET" ] && warn "Obrigatório." && continue
      ok "Client Secret: [oculto]"; break
    done
  else
    info "Integração Azure AD / M365 será ignorada."
  fi

  # ── 1.5 Configuração de SMTP ─────────────────────────────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.5  Configuração de SMTP${NC}"
  echo ""
  info "Necessário para envio de emails (alertas, relatórios, etc.)."
  echo ""

  if confirm "Deseja configurar SMTP agora" "s"; then
    SETUP_SMTP="y"
    while true; do
      SMTP_HOST=$(ask "Servidor SMTP")
      [ -z "$SMTP_HOST" ] && warn "Obrigatório." && continue
      ok "Servidor SMTP: ${SMTP_HOST}"; break
    done
    SMTP_PORT=$(ask "Porta SMTP" "587")
    if confirm "Usar conexão segura (TLS/SSL)" "s"; then
      SMTP_SECURE="true"
    else
      SMTP_SECURE="false"
    fi
    SMTP_USER=$(ask "Usuário SMTP (opcional)")
    if [ -n "$SMTP_USER" ]; then
      SMTP_PASS=$(ask_secret "Senha SMTP")
    fi
    while true; do
      SMTP_FROM=$(ask "Email de remetente" "admanager@empresa.com.br")
      ! is_valid_email "$SMTP_FROM" && warn "Formato de email inválido." && continue
      ok "Remetente: ${SMTP_FROM}"; break
    done
  else
    info "Configuração SMTP será ignorada."
  fi

  # ── 1.6 Configuração de Alertas no Microsoft Teams ──────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.6  Alertas no Microsoft Teams${NC}"
  echo ""
  info "Receba notificações críticas diretamente em um canal do Teams."
  info "Crie um conector 'Webhook de Entrada' no Teams para obter a URL."
  echo ""

  if confirm "Deseja configurar alertas no Microsoft Teams agora" "n"; then
    SETUP_TEAMS="y"
    while true; do
      TEAMS_WEBHOOK_URL=$(ask "URL do Webhook do Teams")
      [ -z "$TEAMS_WEBHOOK_URL" ] && warn "Obrigatório." && continue
      [[ "$TEAMS_WEBHOOK_URL" == https://outlook.office.com/webhook/* ]] \
        || warn "URL inválida. Deve começar com 'https://outlook.office.com/webhook/'." && continue
      ok "Webhook Teams: [oculto]"; break
    done
  else
    info "Alertas no Teams serão ignorados."
  fi

  # ── 1.7 Certificado TLS ──────────────────────────────────────────────────
  echo ""; div
  echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS (HTTPS)${NC}"
  echo ""
  info "O sistema precisa de um certificado TLS para HTTPS."
  echo ""
  echo "  1) Let's Encrypt (gratuito, automático, requer porta 80/443 aberta para internet)"
  echo "  2) PKI Corporativa (você fornecerá os arquivos .pem após a instalação)"
  echo "  3) Auto-assinado (self-signed, para testes ou ambientes internos sem PKI)"
  echo ""

  while true; do
    CERT_OPCAO=$(ask "Escolha uma opção" "1")
    [[ "$CERT_OPCAO" =~ ^[1-3]$ ]] && break
    warn "Opção inválida. Escolha 1, 2 ou 3."
  done

  ok "Coleta de informações concluída."
  pause
}

# =============================================================================
#  ETAPA 2 — PREPARAÇÃO DO SISTEMA
# =============================================================================
step_2_prepare_system() {
  step "2" "PREPARAÇÃO DO SISTEMA"

  sub "Atualizando pacotes do sistema..."
  q apt-get update
  q apt-get upgrade -y
  ok "Pacotes atualizados"

  sub "Instalando dependências essenciais..."
  q apt-get install -y \
    curl git openssl netcat-openbsd python3-apt python3-pip jq unzip \
    ufw fail2ban auditd chrony
  ok "Dependências instaladas"

  sub "Criando usuário de serviço '${SERVICE_USER}'..."
  if ! id -u "$SERVICE_USER" > /dev/null 2>&1; then
    q useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    ok "Usuário '${SERVICE_USER}' criado"
  else
    ok "Usuário '${SERVICE_USER}' já existe"
  fi

  sub "Criando diretórios de instalação e dados..."
  q mkdir -p "${INSTALL_DIR}/logs" "${INSTALL_DIR}/backups" "${INSTALL_DIR}/scripts"
  q chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
  q chmod 750 "${INSTALL_DIR}"
  ok "Diretórios criados e permissões configuradas"

  sub "Configurando limites do kernel (sysctl)..."
  cat << EOF | q tee /etc/sysctl.d/99-admanager.conf
# AD License Manager otimizacoes e seguranca
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

  # ── UFW ──────────────────────────────────────────────────────────────────
  sub "Configurando UFW (firewall)..."
  q ufw default deny incoming
  q ufw default allow outgoing
  q ufw allow ssh comment "Permitir SSH"
  q ufw allow http comment "Permitir HTTP (redirecionamento)"
  q ufw allow https comment "Permitir HTTPS"
  q ufw --force enable
  ok "UFW configurado e habilitado"

  # ── fail2ban ─────────────────────────────────────────────────────────────
  sub "Configurando fail2ban..."
  cat << EOF | q tee /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF
  q systemctl enable fail2ban
  q systemctl restart fail2ban
  ok "fail2ban configurado e habilitado"

  # ── auditd ───────────────────────────────────────────────────────────────
  sub "Configurando auditd..."
  cat << EOF | q tee /etc/audit/rules.d/admanager.rules
# AD License Manager - Monitoramento de seguranca
-w /opt/ad-license-manager/.env -p rwxa -k admanager-config
-w /opt/ad-license-manager/infra/nginx/ssl/key.pem -p rwxa -k admanager-tls-key
-w /etc/systemd/system/ad-license-manager.service -p rwxa -k admanager-systemd
-w /etc/cron.d/admanager -p rwxa -k admanager-cron
-w /usr/local/bin/admanager-renew-cert.sh -p rwxa -k admanager-cert-script
EOF
  q augenrules --load
  q systemctl enable auditd
  q systemctl restart auditd
  ok "auditd configurado e habilitado"

  # ── chrony (NTP) ─────────────────────────────────────────────────────────
  sub "Configurando chrony (NTP)..."
  q systemctl enable chrony
  q systemctl restart chrony
  q timedatectl set-ntp true
  ok "chrony configurado e habilitado"

  # ── SSH Hardening ────────────────────────────────────────────────────────
  sub "Configurando SSH hardening..."
  q sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  q sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/sshd_config
  q sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  q sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config # Garante PAM para outros métodos
  q systemctl restart sshd
  warn "Autenticação por senha SSH desabilitada. Use chaves SSH."
  warn "Login root via SSH desabilitado."
  ok "SSH hardening aplicado"
}

# =============================================================================
#  ETAPA 4 — DOCKER ENGINE E COMPOSE PLUGIN
# =============================================================================
step_4_docker() {
  step "4" "DOCKER ENGINE E COMPOSE PLUGIN"

  sub "Removendo versões antigas do Docker (se existirem)..."
  q apt-get remove -y docker docker-engine docker.io containerd runc || true
  ok "Versões antigas removidas"

  sub "Instalando dependências do Docker..."
  q apt-get install -y ca-certificates curl gnupg
  ok "Dependências instaladas"

  sub "Adicionando chave GPG oficial do Docker..."
  q install -m 0755 -d /etc/apt/keyrings
  q rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | q gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  q chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  sub "Adicionando repositório do Docker..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ${UBUNTU_CODENAME} stable" | q tee /etc/apt/sources.list.d/docker.list > /dev/null
  q apt-get update
  ok "Repositório Docker adicionado"

  sub "Instalando Docker Engine e Compose Plugin..."
  q apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ok "Docker Engine e Compose Plugin instalados"

  sub "Configurando Docker para iniciar com o sistema..."
  q systemctl enable docker.service
  q systemctl enable containerd.service
  ok "Docker configurado para iniciar com o sistema"

  sub "Adicionando '${SERVICE_USER}' ao grupo 'docker'..."
  q usermod -aG docker "$SERVICE_USER"
  ok "Usuário '${SERVICE_USER}' adicionado ao grupo 'docker'"

  sub "Configurando daemon do Docker (otimizações e segurança)..."
  cat << EOF | q tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.20.0.0/16",
      "size": 24
    }
  ]
}
EOF
  q systemctl restart docker
  ok "Daemon do Docker configurado e reiniciado"
}

# =============================================================================
#  ETAPA 5 — DOWNLOAD DO CÓDIGO-FONTE
# =============================================================================
step_5_download_code() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"

  sub "Clonando repositório do AD License Manager..."
  if [ -d "${INSTALL_DIR}/.git" ]; then
    warn "Repositório já existe. Pulando clone."
    cd "${INSTALL_DIR}"
    q git fetch origin
    q git reset --hard origin/main
  else
    q git clone "$REPO_URL" "$INSTALL_DIR"
  fi
  ok "Código-fonte baixado para ${INSTALL_DIR}"

  sub "Verificando arquivos essenciais..."
  [ -f "${INSTALL_DIR}/docker-compose.yml" ] || fail "docker-compose.yml não encontrado."
  [ -d "${INSTALL_DIR}/backend" ]             || fail "Diretório 'backend' não encontrado."
  [ -d "${INSTALL_DIR}/frontend" ]            || fail "Diretório 'frontend' não encontrado."
  ok "Arquivos essenciais verificados"
}

# =============================================================================
#  ETAPA 6 — GERAÇÃO DO ARQUIVO .ENV
# =============================================================================
step_6_generate_env() {
  step "6" "GERAÇÃO DO ARQUIVO .ENV"

  sub "Gerando segredos criptográficos..."
  DB_PASSWORD=$(gen_password)
  REDIS_PASSWORD=$(gen_password)
  JWT_SECRET=$(gen_secret)
  JWT_REFRESH_SECRET=$(gen_secret)
  ENCRYPTION_KEY=$(gen_hex)
  ok "Segredos gerados"

  sub "Criando arquivo .env..."
  cat << EOF > "${INSTALL_DIR}/.env"
# ════════════════════════════════════════════════════════════════════════════
#  AD License Manager — Variáveis de Ambiente
#  Gerado pelo instalador v${INSTALLER_VERSION} em $(date '+%Y-%m-%d %H:%M:%S')
# ════════════════════════════════════════════════════════════════════════════

# ── Configurações Gerais ──────────────────────────────────────────────────────
NODE_ENV=production
APP_URL=https://${APP_DOMAIN}
PORT=3000
TZ=America/Sao_Paulo # Fuso horário do servidor

# ── Active Directory (LDAP/LDAPS) ─────────────────────────────────────────────
AD_URL=${AD_URL}
AD_BASE_DN=${AD_BASE_DN}
AD_USERNAME=${AD_USERNAME}
AD_PASSWORD=${AD_PASSWORD}
AD_DOMAIN=${AD_DOMAIN} # Nome NetBIOS do domínio (opcional)
AD_SYNC_INTERVAL_MINUTES=60 # Intervalo de sincronização do AD

# ── Banco de Dados (PostgreSQL) ───────────────────────────────────────────────
DATABASE_URL=postgresql://admanager:${DB_PASSWORD}@postgres:5432/admanager?schema=public
DB_PASSWORD=${DB_PASSWORD} # Senha do usuario admanager no PostgreSQL

# ── Cache e Filas (Redis) ─────────────────────────────────────────────────────
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=${REDIS_PASSWORD} # Senha do Redis

# ── Autenticação e Segurança ──────────────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY} # Chave para criptografia de dados sensiveis (ex: senhas de servico)
SESSION_SECRET=${JWT_SECRET} # Usado para criptografar cookies de sessao

# ── Integração Azure AD / Microsoft 365 (Microsoft Graph API) ─────────────────
EOF

  if [ "$SETUP_GRAPH" = "y" ]; then
    cat << EOF >> "${INSTALL_DIR}/.env"
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
EOF
  else
    cat << EOF >> "${INSTALL_DIR}/.env"
# AZURE_TENANT_ID=
# AZURE_CLIENT_ID=
# AZURE_CLIENT_SECRET=
EOF
  fi

  cat << EOF >> "${INSTALL_DIR}/.env"

# ── Configuração de SMTP (Envio de E-mails) ───────────────────────────────────
EOF

  if [ "$SETUP_SMTP" = "y" ]; then
    cat << EOF >> "${INSTALL_DIR}/.env"
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURE=${SMTP_SECURE}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_FROM=${SMTP_FROM}
EOF
  else
    cat << EOF >> "${INSTALL_DIR}/.env"
# SMTP_HOST=
# SMTP_PORT=587
# SMTP_SECURE=true
# SMTP_USER=
# SMTP_PASS=
# SMTP_FROM=
EOF
  fi

  cat << EOF >> "${INSTALL_DIR}/.env"

# ── Integração Microsoft Teams (Webhooks) ─────────────────────────────────────
EOF

  if [ "$SETUP_TEAMS" = "y" ]; then
    cat << EOF >> "${INSTALL_DIR}/.env"
TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL}
EOF
  else
    cat << EOF >> "${INSTALL_DIR}/.env"
# TEAMS_WEBHOOK_URL=
EOF
  fi

  cat << EOF >> "${INSTALL_DIR}/.env"

# ── GLPI (Opcional) ───────────────────────────────────────────────────────────
# GLPI_URL=https://glpi.empresa.com.br/apirest.php
# GLPI_APP_TOKEN=
# GLPI_USER_TOKEN=

# ── Configurações do Frontend ─────────────────────────────────────────────────
VITE_APP_NAME="AD License Manager"
VITE_APP_VERSION=${INSTALLER_VERSION}
EOF

  q chmod 600 "${INSTALL_DIR}/.env"
  q chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/.env"
  ok "Arquivo .env criado e protegido"

  sub "Criando docker-compose.yml..."
  cat << EOF > "${INSTALL_DIR}/docker-compose.yml"
# ════════════════════════════════════════════════════════════════════════════
#  AD License Manager — Docker Compose
#  Gerado pelo instalador v${INSTALLER_VERSION} em $(date '+%Y-%m-%d %H:%M:%S')
# ════════════════════════════════════════════════════════════════════════════
version: '3.8'

services:
  nginx:
    container_name: admanager_nginx
    image: nginx:stable-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./infra/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./infra/nginx/ssl:/etc/nginx/ssl:ro
      - ./frontend/dist:/usr/share/nginx/html:ro
    depends_on:
      - frontend
      - backend
    networks:
      - admanager_external
      - admanager_internal

  frontend:
    container_name: admanager_frontend
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        NODE_ENV: production
    restart: unless-stopped
    environment:
      - VITE_APP_NAME=\${VITE_APP_NAME}
      - VITE_APP_VERSION=\${VITE_APP_VERSION}
      - VITE_API_URL=\${APP_URL}/api
      - VITE_WS_URL=\${APP_URL}/ws
    networks:
      - admanager_internal

  backend:
    container_name: admanager_backend
    build:
      context: ./backend
      dockerfile: Dockerfile
      args:
        NODE_ENV: production
    restart: unless-stopped
    env_file:
      - ./.env
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - REDIS_URL=\${REDIS_URL}
      - JWT_SECRET=\${JWT_SECRET}
      - JWT_REFRESH_SECRET=\${JWT_REFRESH_SECRET}
      - ENCRYPTION_KEY=\${ENCRYPTION_KEY}
      - AD_URL=\${AD_URL}
      - AD_BASE_DN=\${AD_BASE_DN}
      - AD_USERNAME=\${AD_USERNAME}
      - AD_PASSWORD=\${AD_PASSWORD}
      - AD_DOMAIN=\${AD_DOMAIN}
      - AZURE_TENANT_ID=\${AZURE_TENANT_ID}
      - AZURE_CLIENT_ID=\${AZURE_CLIENT_ID}
      - AZURE_CLIENT_SECRET=\${AZURE_CLIENT_SECRET}
      - SMTP_HOST=\${SMTP_HOST}
      - SMTP_PORT=\${SMTP_PORT}
      - SMTP_SECURE=\${SMTP_SECURE}
      - SMTP_USER=\${SMTP_USER}
      - SMTP_PASS=\${SMTP_PASS}
      - SMTP_FROM=\${SMTP_FROM}
      - TEAMS_WEBHOOK_URL=\${TEAMS_WEBHOOK_URL}
      - GLPI_URL=\${GLPI_URL}
      - GLPI_APP_TOKEN=\${GLPI_APP_TOKEN}
      - GLPI_USER_TOKEN=\${GLPI_USER_TOKEN}
      - PORT=3001
      - TZ=\${TZ}
    volumes:
      - ./logs:/app/logs
    depends_on:
      - postgres
      - redis
    networks:
      - admanager_internal

  worker:
    container_name: admanager_worker
    build:
      context: ./backend
      dockerfile: Dockerfile
      args:
        NODE_ENV: production
    restart: unless-stopped
    env_file:
      - ./.env
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - REDIS_URL=\${REDIS_URL}
      - JWT_SECRET=\${JWT_SECRET}
      - JWT_REFRESH_SECRET=\${JWT_REFRESH_SECRET}
      - ENCRYPTION_KEY=\${ENCRYPTION_KEY}
      - AD_URL=\${AD_URL}
      - AD_BASE_DN=\${AD_BASE_DN}
      - AD_USERNAME=\${AD_USERNAME}
      - AD_PASSWORD=\${AD_PASSWORD}
      - AD_DOMAIN=\${AD_DOMAIN}
      - AZURE_TENANT_ID=\${AZURE_TENANT_ID}
      - AZURE_CLIENT_ID=\${AZURE_CLIENT_ID}
      - AZURE_CLIENT_SECRET=\${AZURE_CLIENT_SECRET}
      - SMTP_HOST=\${SMTP_HOST}
      - SMTP_PORT=\${SMTP_PORT}
      - SMTP_SECURE=\${SMTP_SECURE}
      - SMTP_USER=\${SMTP_USER}
      - SMTP_PASS=\${SMTP_PASS}
      - SMTP_FROM=\${SMTP_FROM}
      - TEAMS_WEBHOOK_URL=\${TEAMS_WEBHOOK_URL}
      - GLPI_URL=\${GLPI_URL}
      - GLPI_APP_TOKEN=\${GLPI_APP_TOKEN}
      - GLPI_USER_TOKEN=\${GLPI_USER_TOKEN}
      - PORT=3002 # Porta interna para o worker, nao exposta
      - TZ=\${TZ}
    command: node dist/worker.js
    volumes:
      - ./logs:/app/logs
    depends_on:
      - postgres
      - redis
    networks:
      - admanager_internal

  postgres:
    container_name: admanager_postgres
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: admanager
      POSTGRES_USER: admanager
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    volumes:
      - admanager_db_data:/var/lib/postgresql/data
    networks:
      - admanager_internal

  redis:
    container_name: admanager_redis
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS_PASSWORD} --appendonly yes
    volumes:
      - admanager_redis_data:/data
    networks:
      - admanager_internal

volumes:
  admanager_db_data:
  admanager_redis_data:

networks:
  admanager_external:
    driver: bridge
  admanager_internal:
    driver: bridge
    internal: true
EOF
  ok "docker-compose.yml criado"

  sub "Criando arquivos de configuração do Nginx..."
  q mkdir -p "${INSTALL_DIR}/infra/nginx/conf.d" "${INSTALL_DIR}/infra/nginx/ssl"

  cat << EOF > "${INSTALL_DIR}/infra/nginx/nginx.conf"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}
EOF

  cat << EOF > "${INSTALL_DIR}/infra/nginx/conf.d/default.conf"
server {
    listen 80;
    listen [::]:80;
    server_name ${APP_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${APP_DOMAIN};

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # HSTS (15768000 seconds = 6 months)
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/nginx/ssl/cert.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 10M; # Aumentado para upload de fotos
    }

    location /ws/ {
        proxy_pass http://backend:3001/ws/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400; # 24 horas para WebSockets
    }

    # Bloqueia acesso a arquivos de configuracao
    location ~ /\.env { deny all; }
    location ~ /\.git { deny all; }
}
EOF
  ok "Arquivos de configuração do Nginx criados"
}

# =============================================================================
#  ETAPA 7 — CERTIFICADO TLS
# =============================================================================
step_7_tls() {
  step "7" "CONFIGURAÇÃO DE CERTIFICADO TLS"

  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  # ── Let's Encrypt (opção 1) ──────────────────────────────────────────────
  if [ "$CERT_OPCAO" = "1" ]; then
    sub "Configurando Let's Encrypt..."
    q apt-get install -y certbot
    q docker compose stop nginx # Libera porta 80/443
    if q certbot certonly \
      --standalone \
      --non-interactive \
      --agree-tos \
      --email "$ADMIN_EMAIL" \
      -d "$APP_DOMAIN"; then
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem" "${SSL_DIR}/cert.pem"
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem"   "${SSL_DIR}/key.pem"
      ok "Certificado Let's Encrypt gerado"

      sub "Configurando renovação automática do Let's Encrypt..."
      cat > /usr/local/bin/admanager-renew-cert.sh << EOF
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR}"
SSL_DIR="${SSL_DIR}"
DOMAIN="${APP_DOMAIN}"
LOG="${INSTALL_DIR}/logs/certbot.log"
echo "\$(date '+%Y-%m-%d %H:%M:%S') Iniciando renovação de certificado." >> "\$LOG"
certbot renew --quiet >> "\$LOG" 2>&1
cp /etc/letsencrypt/live/\${DOMAIN}/fullchain.pem \${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/\${DOMAIN}/privkey.pem   \${SSL_DIR}/key.pem
chown ${SERVICE_USER}:${SERVICE_USER} \${SSL_DIR}/cert.pem \${SSL_DIR}/key.pem
chmod 644 \${SSL_DIR}/cert.pem
chmod 600 \${SSL_DIR}/key.pem
docker compose -f ${INSTALL_DIR}/docker-compose.yml restart nginx >> "\$LOG" 2>&1
echo "\$(date '+%Y-%m-%d %H:%M:%S') Renovação concluída." >> "\$LOG"
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      cat > /etc/cron.d/admanager-certbot << 'EOF'
# Renovação automática do certificado Let's Encrypt
0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh >> /opt/ad-license-manager/logs/certbot.log 2>&1
EOF
      ok "Renovação automática agendada (dia 1 de cada mês às 02:00)"
    else
      warn "Let's Encrypt falhou. Gerando self-signed como fallback."
      CERT_OPCAO="3"
    fi
  fi

  # ── Self-signed (opção 2, 3 ou fallback) ──────────────────────────────────
  if [ "$CERT_OPCAO" != "1" ] || [ ! -f "${SSL_DIR}/cert.pem" ]; then
    sub "Gerando certificado self-signed RSA 4096 (válido por 10 anos)..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
      -keyout "${SSL_DIR}/key.pem" \
      -out    "${SSL_DIR}/cert.pem" \
      -subj   "/CN=${APP_DOMAIN}/O=AD License Manager/C=BR/OU=TI" \
      -addext "subjectAltName=DNS:${APP_DOMAIN},DNS:localhost,IP:${SERVER_IP},IP:127.0.0.1" \
      >> "$INSTALL_LOG" 2>&1
    ok "Certificado self-signed gerado"

    if [ "$CERT_OPCAO" = "2" ]; then
      warn "Substitua pelos arquivos da sua PKI corporativa após a instalação:"
      warn "  ${SSL_DIR}/cert.pem"
      warn "  ${SSL_DIR}/key.pem"
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
  info "Acompanhe em outro terminal: tail -f ${INSTALL_LOG}"
  echo ""

  sub "Construindo todas as imagens..."
  docker compose build \
    --no-cache \
    --progress=plain \
    >> "$INSTALL_LOG" 2>&1 \
    || fail "Erro no build das imagens. Detalhes em: ${INSTALL_LOG}"

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
  ok "Containers de infraestrutura iniciados"
  echo ""

  wait_for "PostgreSQL" \
    "docker compose exec -T postgres pg_isready -U admanager -d admanager" \
    40 3 || fail "PostgreSQL não ficou pronto. Veja: docker compose logs postgres"
  ok "PostgreSQL aceitando conexões"

  wait_for "Redis" \
    "docker compose exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping | grep -q PONG" \
    20 2 || fail "Redis não ficou pronto. Veja: docker compose logs redis"
  ok "Redis respondendo"
  echo ""

  sub "Aplicando migrations do banco de dados..."
  q docker compose run --rm backend node dist/migrate.js \
    || fail "Erro nas migrations. Detalhes: ${INSTALL_LOG}"
  ok "Migrations aplicadas com sucesso"

  sub "Criando dados iniciais e usuário administrador..."
  q docker compose run --rm backend node dist/seed.js \
    || fail "Erro no seed. Detalhes: ${INSTALL_LOG}"
  ok "Dados iniciais criados"

  sub "Iniciando todos os serviços..."
  q docker compose up -d
  ok "Todos os containers iniciados"
  echo ""

  wait_for "Backend API (até 120s)" \
    "curl -sf http://localhost:3001/health" \
    30 4 || warn "Backend ainda iniciando. Verifique: docker compose logs backend"

  echo ""
  sub "Status dos containers:"
  echo ""
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

  # ── backup.sh ──────────────────────────────────────────────────────────────
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

REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d "\"'")

log "Dump do PostgreSQL..."
docker compose -f "${INSTALL_DIR}/docker-compose.yml" \
  exec -T postgres \
  pg_dump -U admanager admanager --format=custom --compress=9 \
  > "${BACKUP_DIR}/database.dump"
log "Banco: OK ($(du -sh "${BACKUP_DIR}/database.dump" | cut -f1))"

cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"
chmod 600 "${BACKUP_DIR}/.env.bak"
log "Configurações: OK"

if ls "${INSTALL_DIR}/logs/"*.log 1>/dev/null 2>&1; then
  tar -czf "${BACKUP_DIR}/logs.tar.gz" \
    -C "${INSTALL_DIR}" logs/ 2>/dev/null \
    && log "Logs: OK" \
    || log "AVISO: Logs não comprimidos."
fi

find "${INSTALL_DIR}/backups" -maxdepth 1 -type d \
  -mtime "+${RETENCAO}" -exec rm -rf {} + 2>/dev/null || true

log "=== Backup concluído. Tamanho: $(du -sh "$BACKUP_DIR" | cut -f1) → ${BACKUP_DIR} ==="
BACKUP_SCRIPT
  ok "backup.sh criado"

  # ── health-check.sh ────────────────────────────────────────────────────────
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
    echo "  ✗  ${label}"
    FALHAS=$((FALHAS + 1))
  fi
}

echo ""
echo "  ── Health Check AD License Manager — $(date '+%d/%m/%Y %H:%M:%S')"
echo ""

check "PostgreSQL" \
  "docker compose -f '$COMPOSE' exec -T postgres pg_isready -U admanager" \
  "accepting"

check "Redis" \
  "docker compose -f '$COMPOSE' exec -T redis redis-cli -a '$REDIS_PASSWORD' --no-auth-warning ping" \
  "PONG"

check "Backend API" \
  "curl -sf http://localhost:3001/health" \
  "."

check "Nginx HTTPS" \
  "curl -skf https://localhost/health" \
  "."

check "Worker" \
  "docker compose -f '$COMPOSE' ps worker" \
  "running"

echo ""
if [ "$FALHAS" -gt 0 ]; then
  echo "  ✗  ${FALHAS} serviço(s) com problema."
  echo "     Detalhes: docker compose -f '${COMPOSE}' logs"
  echo "$(date '+%Y-%m-%d %H:%M:%S') FALHA: ${FALHAS} servico(s)" >> "$LOG"
  exit 1
else
  echo "  ✓  Todos os serviços saudáveis."
  echo "$(date '+%Y-%m-%d %H:%M:%S') OK: todos saudaveis" >> "$LOG"
fi
echo ""
HEALTH_SCRIPT
  ok "health-check.sh criado"

  # ── update.sh ──────────────────────────────────────────────────────────────
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
echo "Baixando atualizações do repositório..."
cd "${INSTALL_DIR}"
git fetch origin
git reset --hard origin/main
echo ""
echo "Reconstruindo imagens Docker..."
docker compose build --no-cache --progress=plain
echo ""
echo "Aplicando migrations do banco de dados..."
docker compose run --rm backend node dist/migrate.js
echo ""
echo "Reiniciando todos os serviços..."
docker compose up -d --remove-orphans
echo ""
echo "Aguardando inicialização..."
sleep 15
echo ""
echo "Verificando saúde após atualização..."
bash "${INSTALL_DIR}/scripts/health-check.sh"
echo ""
echo "=== Atualização concluída com sucesso ==="
UPDATE_SCRIPT
  ok "update.sh criado"

  # ── restore.sh ─────────────────────────────────────────────────────────────
  sub "Criando scripts/restore.sh..."
  cat > "${INSTALL_DIR}/scripts/restore.sh" << 'RESTORE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"

usage() {
  echo ""
  echo "  Uso: sudo bash restore.sh [DATA]"
  echo "       DATA formato: YYYY-MM-DD"
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
[ -d "$BACKUP_DIR"              ] || { echo "Backup não encontrado: ${BACKUP_DIR}"; usage; }
[ -f "${BACKUP_DIR}/database.dump" ] || { echo "Arquivo de banco não encontrado em: ${BACKUP_DIR}"; exit 1; }

echo ""
echo "=== Restauração — backup de ${DATE} ==="
echo ""
echo "ATENÇÃO: Esta operação substituirá os dados atuais pelo backup de ${DATE}."
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
  --clean    \
  --if-exists \
  < "${BACKUP_DIR}/database.dump"

echo "Reiniciando serviços..."
docker compose start backend worker

echo ""
echo "Aguardando inicialização (10s)..."
sleep 10

echo ""
echo "Verificando integridade após restauração..."
bash "${INSTALL_DIR}/scripts/health-check.sh"

echo ""
echo "=== Restauração concluída. Dados de ${DATE} restaurados. ==="
RESTORE_SCRIPT
  ok "restore.sh criado"

  # ── Permissões finais dos scripts ──────────────────────────────────────────
  chmod +x  "${INSTALL_DIR}/scripts/"*.sh
  chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/scripts/"*.sh
  ok "Permissões dos scripts configuradas"
}

# =============================================================================
#  ETAPA 12 — CRON JOBS
# =============================================================================
step_12_cron() {
  step "12" "CONFIGURAÇÃO DE CRON JOBS AUTOMÁTICOS"

  cat > /etc/cron.d/admanager << EOF
# ══════════════════════════════════════════════════════════════════════
#  AD License Manager — Tarefas automáticas
#  Gerado em: $(date '+%Y-%m-%d %H:%M:%S')
# ══════════════════════════════════════════════════════════════════════

# Backup diário às 03:00
0 3 * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/backup.sh >> ${INSTALL_DIR}/logs/backup.log 2>&1

# Health check a cada 5 minutos
*/5 * * * * ${SERVICE_USER} ${INSTALL_DIR}/scripts/health-check.sh >> ${INSTALL_DIR}/logs/health.log 2>&1

# Limpeza de logs da aplicacao (a cada 6 horas)
0 */6 * * * ${SERVICE_USER} find ${INSTALL_DIR}/logs -type f -name "*.log" -mtime +7 -delete >> ${INSTALL_DIR}/logs/cleanup.log 2>&1

# Limpeza de logs do Docker (a cada 24 horas)
0 0 * * * root docker system prune -f --volumes >> ${INSTALL_DIR}/logs/docker-prune.log 2>&1

EOF
  ok "Cron jobs configurados"
}

# =============================================================================
#  ETAPA 13 — PERMISSÕES FINAIS E AUDITORIA
# =============================================================================
step_13_final_permissions() {
  step "13" "PERMISSÕES FINAIS E AUDITORIA"

  sub "Aplicando permissões restritivas na instalação..."
  q chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
  q chmod -R u=rwX,g=rX,o= "${INSTALL_DIR}"
  q chmod 600 "${INSTALL_DIR}/.env"
  q chmod 600 "${INSTALL_DIR}/infra/nginx/ssl/key.pem"
  q chmod 700 "${INSTALL_DIR}/logs"
  q chmod 700 "${INSTALL_DIR}/backups"
  ok "Permissões aplicadas"

  sub "Verificando regras de auditoria do auditd..."
  if q auditctl -l | grep -q "admanager-config"; then
    ok "Regras de auditoria do auditd ativas"
  else
    warn "Regras de auditoria do auditd não ativas. Reiniciando auditd."
    q systemctl restart auditd
    if q auditctl -l | grep -q "admanager-config"; then
      ok "Regras de auditoria do auditd ativas após reinício"
    else
      warn "Falha ao ativar regras de auditoria do auditd. Verifique /etc/audit/rules.d/admanager.rules"
    fi
  fi
}

# =============================================================================
#  ETAPA 14 — VERIFICAÇÃO FINAL E RESUMO
# =============================================================================
step_14_final_check() {
  step "14" "VERIFICAÇÃO FINAL E RESUMO"

  cd "${INSTALL_DIR}"

  sub "Status dos containers:"
  echo ""
  docker compose ps 2>/dev/null | while IFS= read -r l; do echo "    ${l}"; done
  echo ""

  sub "Executando health check completo..."
  echo ""
  bash "${INSTALL_DIR}/scripts/health-check.sh" || true
  echo ""

  sub "Verificando certificado TLS..."
  local CERT_INFO
  CERT_INFO=$(openssl x509 -in "${INSTALL_DIR}/infra/nginx/ssl/cert.pem" \
    -noout -subject -dates 2>/dev/null || echo "erro")
  if echo "$CERT_INFO" | grep -q "notAfter"; then
    local EXPIRA
    EXPIRA=$(echo "$CERT_INFO" | grep notAfter | cut -d= -f2)
    ok "Certificado TLS válido — expira em: ${EXPIRA}"
  else
    warn "Não foi possível verificar o certificado TLS."
  fi

  sub "Testando acesso HTTPS..."
  if curl -skf "https://${APP_DOMAIN}/health" > /dev/null 2>&1; then
    ok "Acesso HTTPS ao sistema OK."
  else
    warn "Não foi possível acessar https://${APP_DOMAIN}/health."
    warn "Verifique o DNS, firewall e logs do Nginx (docker compose logs nginx)."
  fi

  local INSTALL_END
  INSTALL_END=$(date +%s)
  local DURACAO
  DURACAO=$(( (INSTALL_END - INSTALL_START) / 60 ))

  banner
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════════╗"
  echo "  ║                                                                      ║"
  echo "  ║           ✓  INSTALAÇÃO CONCLUÍDA COM SUCESSO!                      ║"
  echo "  ║                                                                      ║"
  echo "  ╚══════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Tempo total: ${DURACAO} minutos${NC}"
  echo ""

  div
  echo -e "  ${WHITE}${BOLD}ACESSO AO SISTEMA${NC}"
  div
  echo ""
  echo -e "  ${CYAN}URL:${NC}      ${WHITE}${BOLD}https://${APP_DOMAIN}${NC}"
  echo -e "  ${CYAN}Usuário:${NC}  ${WHITE}${BOLD}${ADMIN_USER}${NC}"
  echo -e "  ${CYAN}Senha:${NC}    ${WHITE}${BOLD}Será solicitada no primeiro login.${NC}"
  echo ""

  div
  echo -e "  ${WHITE}${BOLD}PRÓXIMOS PASSOS${NC}"
  div
  echo ""
  echo -e "  1.  Acesse a URL acima e faça login com o usuário '${ADMIN_USER}'."
  echo -e "  2.  Altere a senha do administrador no primeiro acesso."
  echo -e "  3.  Configure o registro DNS para '${APP_DOMAIN}' apontando para o IP '${SERVER_IP}'."
  echo -e "  4.  Consulte o manual para as configurações pós-instalação."
  echo ""

  div
  echo -e "  ${WHITE}${BOLD}COMANDOS ÚTEIS${NC}"
  div
  echo ""
  echo -e "  ${DIM}Acesse o diretório de instalação:${NC} cd ${INSTALL_DIR}"
  echo -e "  ${DIM}Verificar status:${NC} docker compose ps"
  echo -e "  ${DIM}Verificar saúde:${NC} bash scripts/health-check.sh"
  echo -e "  ${DIM}Ver logs em tempo real:${NC} docker compose logs -f"
  echo -e "  ${DIM}Atualizar o sistema:${NC} sudo bash scripts/update.sh"
  echo -e "  ${DIM}Fazer backup manual:${NC} sudo bash scripts/backup.sh"
  echo ""

  echo -e "  ${DIM}Log completo da instalação: ${INSTALL_LOG}${NC}"
  echo ""
}

# =============================================================================
#  FLUXO PRINCIPAL
# =============================================================================
main() {
  step_0_verify
  step_1_collect
  step_2_prepare_system
  step_3_security
  step_4_docker
  step_5_download_code
  step_6_generate_env
  step_7_tls
  step_8_build
  step_9_start
  step_10_systemd
  step_11_scripts
  step_12_cron
  step_13_final_permissions
  step_14_final_check
}

main "$@"
