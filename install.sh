#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Completo e Autônomo
#  Versão 2.1.0 — Julho de 2026
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
readonly INSTALLER_VERSION="2.1.0"
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
    [ -z "$APP_DOMAIN" ]            && warn "Obrigatório."      && continue
    ! is_valid_domain "$APP_DOMAIN" && warn "Formato inválido." && continue
    ok "Domínio: ${APP_DOMAIN}"
    break
  done

  # ── 1.2 Active Directory ─────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"
  echo ""
  info "Use ldaps:// (porta 636) para habilitar redefinição de senha."
  info "Use ldap://  (porta 389) somente se LDAPS não estiver disponível."
  echo ""

  while true; do
    AD_URL=$(ask "URL do Controlador de Domínio" "ldaps://dc01.empresa.com.br")
    ! is_valid_ldap_url "$AD_URL" \
      && warn "Formato inválido. Ex: ldaps://dc01.empresa.com.br" \
      && continue
    break
  done

  while true; do
    AD_BASE_DN=$(ask "Base DN" "DC=empresa,DC=com,DC=br")
    ! is_valid_base_dn "$AD_BASE_DN" \
      && warn "Formato inválido. Ex: DC=empresa,DC=com,DC=br" \
      && continue
    break
  done

  while true; do
    AD_USERNAME=$(ask "UPN da conta de serviço" "svc-admanager@empresa.com.br")
    [ -n "$AD_USERNAME" ] && break
    warn "Obrigatório."
  done

  while true; do
    AD_PASSWORD=$(ask_secret "Senha da conta de serviço")
    [ -n "$AD_PASSWORD" ] && break
    warn "Obrigatório."
  done

  while true; do
    AD_DOMAIN=$(ask "Domínio NetBIOS / UPN suffix" "empresa.com.br")
    [ -n "$AD_DOMAIN" ] && break
    warn "Obrigatório."
  done

  # Testa conectividade com o AD
  echo ""
  AD_HOST=$(echo "$AD_URL" | sed -E 's|ldaps?://||' | cut -d: -f1)
  if echo "$AD_URL" | grep -qi "ldaps"; then
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':')
    AD_PORT="${AD_PORT:-636}"
  else
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':')
    AD_PORT="${AD_PORT:-389}"
  fi

  pg "Testando conectividade com ${AD_HOST}:${AD_PORT}"
  if nc -zw 5 "$AD_HOST" "$AD_PORT" 2>/dev/null; then
    pg_ok
    ok "Active Directory acessível"
  else
    pg_fail
    warn "Não foi possível conectar a ${AD_HOST}:${AD_PORT}."
    warn "Verifique endereço, porta e regras de firewall."
    confirm "Continuar mesmo sem confirmar conectividade" "n" \
      || fail "Conectividade com AD não confirmada. Corrija e execute novamente."
  fi

  # ── 1.3 Azure AD ─────────────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.3  Azure AD / Microsoft 365 ${DIM}(opcional — para licenças M365)${NC}"
  echo ""

  if confirm "Configurar integração com Microsoft 365" "n"; then
    SETUP_GRAPH="s"
    while true; do
      AZURE_TENANT_ID=$(ask "Azure Tenant ID")
      [ -n "$AZURE_TENANT_ID" ] && break
      warn "Obrigatório."
    done
    while true; do
      AZURE_CLIENT_ID=$(ask "Azure Client ID")
      [ -n "$AZURE_CLIENT_ID" ] && break
      warn "Obrigatório."
    done
    while true; do
      AZURE_CLIENT_SECRET=$(ask_secret "Azure Client Secret")
      [ -n "$AZURE_CLIENT_SECRET" ] && break
      warn "Obrigatório."
    done
    ok "Azure AD configurado"
  else
    warn "Azure ignorado. Configure depois em Configurações → Azure / M365."
  fi

  # ── 1.4 Administrador ────────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.4  Conta de administrador do sistema${NC}"
  echo ""

  ADMIN_USER=$(ask "Usuário administrador" "admin")
  ADMIN_USER="${ADMIN_USER:-admin}"

  while true; do
    ADMIN_EMAIL=$(ask "Email do administrador")
    is_valid_email "$ADMIN_EMAIL" && break
    warn "Formato inválido. Ex: ti@empresa.com.br"
  done

  echo ""
  info "Senha: mín. 12 caracteres, maiúsculas, minúsculas, números e símbolos."
  echo ""

  while true; do
    ADMIN_PASSWORD=$(ask_secret "Senha do administrador")
    if [ "${#ADMIN_PASSWORD}" -lt 12 ]; then
      warn "Mínimo 12 caracteres."
      continue
    fi
    local STR
    STR=$(password_strength "$ADMIN_PASSWORD")
    echo -e "  ${DIM}Força: ${STR}${NC}"
    local CONFIRM
    CONFIRM=$(ask_secret "Confirme a senha")
    if [ "$ADMIN_PASSWORD" = "$CONFIRM" ]; then
      ok "Administrador: ${ADMIN_USER} (${ADMIN_EMAIL})"
      break
    fi
    warn "Senhas não coincidem. Tente novamente."
  done

  # ── 1.5 SMTP ─────────────────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.5  Email — SMTP ${DIM}(opcional)${NC}"
  echo ""

  if confirm "Configurar envio de emails" "n"; then
    SETUP_SMTP="s"
    SMTP_HOST=$(ask "Host SMTP" "smtp.empresa.com.br")
    SMTP_PORT=$(ask "Porta SMTP" "587")
    SMTP_SECURE=$(ask "TLS obrigatório — true para porta 465" "false")
    SMTP_USER=$(ask "Usuário SMTP (em branco para relay anônimo)")
    [ -n "$SMTP_USER" ] && SMTP_PASS=$(ask_secret "Senha SMTP")
    SMTP_FROM=$(ask "Remetente" "AD Manager <noreply@${APP_DOMAIN}>")
    ok "SMTP: ${SMTP_HOST}:${SMTP_PORT}"
  else
    SMTP_FROM="AD Manager <noreply@${APP_DOMAIN}>"
    warn "SMTP ignorado. Configure depois em Configurações → Notificações."
  fi

  # ── 1.6 Microsoft Teams ───────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.6  Microsoft Teams ${DIM}(opcional)${NC}"
  echo ""
  info "Para criar o Webhook: canal → ··· → Conectores → Incoming Webhook → Criar"
  echo ""

  if confirm "Configurar alertas no Microsoft Teams" "n"; then
    SETUP_TEAMS="s"
    while true; do
      TEAMS_WEBHOOK_URL=$(ask "URL do Webhook")
      [[ "$TEAMS_WEBHOOK_URL" =~ ^https:// ]] && break
      warn "URL deve começar com https://"
    done
    ok "Microsoft Teams configurado"
  else
    warn "Teams ignorado. Configure depois em Configurações."
  fi

  # ── 1.7 Certificado TLS ───────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"
  echo ""
  echo -e "   ${GREEN}1)${NC} Let's Encrypt   — gratuito, renovação automática (requer porta 80 pública)"
  echo -e "   ${GREEN}2)${NC} PKI corporativa — self-signed temporário; substitua os arquivos depois"
  echo -e "   ${GREEN}3)${NC} Self-signed     — para ambientes internos e testes"
  echo ""

  while true; do
    CERT_OPCAO=$(ask "Tipo de certificado" "3")
    case "$CERT_OPCAO" in
      1|2|3) break ;;
      *) warn "Digite 1, 2 ou 3." ;;
    esac
  done

  # ── Resumo de confirmação ─────────────────────────────────────────────────
  banner
  echo -e "  ${WHITE}${BOLD}RESUMO — CONFIRME ANTES DE PROSSEGUIR${NC}"
  echo ""
  div
  echo ""
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
  if [ "$SETUP_GRAPH" = "s" ]; then
    echo -e "    Integração:       ${GREEN}Habilitada${NC} — Tenant: ${AZURE_TENANT_ID}"
  else
    echo -e "    Integração:       ${DIM}Não configurada${NC}"
  fi
  echo ""
  echo -e "  ${CYAN}Administrador${NC}"
  echo -e "    Usuário:          ${ADMIN_USER}"
  echo -e "    Email:            ${ADMIN_EMAIL}"
  echo ""
  echo -e "  ${CYAN}Notificações${NC}"
  if [ "$SETUP_SMTP" = "s" ]; then
    echo -e "    SMTP:             ${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}"
  else
    echo -e "    SMTP:             ${DIM}Não configurado${NC}"
  fi
  if [ "$SETUP_TEAMS" = "s" ]; then
    echo -e "    Teams:            ${GREEN}Habilitado${NC}"
  else
    echo -e "    Teams:            ${DIM}Não configurado${NC}"
  fi
  echo ""
  echo -e "  ${CYAN}Certificado TLS${NC}"
  case "$CERT_OPCAO" in
    1) echo -e "    Tipo:             ${GREEN}Let's Encrypt${NC}" ;;
    2) echo -e "    Tipo:             ${YELLOW}PKI corporativa (self-signed temporário)${NC}" ;;
    3) echo -e "    Tipo:             ${DIM}Self-signed (10 anos)${NC}" ;;
  esac
  echo ""
  div
  echo ""
  confirm "Iniciar a instalação com estas configurações" "s" \
    || { echo "Cancelado. Execute novamente para reiniciar."; exit 0; }
}

# =============================================================================
#  ETAPA 2 — PREPARAÇÃO DO SISTEMA
# =============================================================================
step_2_prepare() {
  step "2" "PREPARAÇÃO DO SISTEMA"

  sub "Atualizando lista de pacotes..."
  q apt-get update -qq
  ok "Lista de pacotes atualizada"

  sub "Instalando dependências essenciais..."
  q apt-get install -y -qq \
    curl wget git openssl netcat-openbsd \
    python3 python3-pip jq \
    ca-certificates gnupg lsb-release \
    apt-transport-https software-properties-common \
    cron logrotate unzip
  ok "Dependências instaladas"

  sub "Criando usuário de serviço '${SERVICE_USER}'..."
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd --system \
      --shell /usr/sbin/nologin \
      --home-dir "${INSTALL_DIR}" \
      --create-home \
      --comment "AD License Manager service account" \
      "$SERVICE_USER"
    ok "Usuário '${SERVICE_USER}' criado"
  else
    ok "Usuário '${SERVICE_USER}' já existe"
  fi

  sub "Criando estrutura de diretórios..."
  local dirs=(
    "${INSTALL_DIR}"
    "${INSTALL_DIR}/logs"
    "${INSTALL_DIR}/backups"
    "${INSTALL_DIR}/scripts"
    "${INSTALL_DIR}/infra/nginx/ssl"
    "${INSTALL_DIR}/infra/nginx/conf.d"
    "${INSTALL_DIR}/data/postgres"
    "${INSTALL_DIR}/data/redis"
  )
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
    chown "${SERVICE_USER}:${SERVICE_USER}" "$d"
  done
  ok "Estrutura de diretórios criada"

  sub "Otimizando parâmetros do kernel..."
  cat > /etc/sysctl.d/99-admanager.conf << 'EOF'
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.netdev_max_backlog = 65535
vm.overcommit_memory = 1
vm.swappiness = 10
fs.file-max = 2097152
EOF
  q sysctl --system
  ok "Parâmetros do kernel aplicados"

  sub "Configurando limites de recursos do sistema..."
  cat >> /etc/security/limits.conf << EOF
# AD License Manager
${SERVICE_USER} soft nofile 65536
${SERVICE_USER} hard nofile 65536
${SERVICE_USER} soft nproc  65536
${SERVICE_USER} hard nproc  65536
EOF
  ok "Limites de recursos configurados"

  sub "Configurando rotação de logs..."
  cat > /etc/logrotate.d/admanager << EOF
${INSTALL_DIR}/logs/*.log {
  daily
  rotate 30
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
  dateext
  dateformat -%Y%m%d
}
EOF
  ok "Rotação de logs configurada (30 dias, compressão diária)"
}

# =============================================================================
#  ETAPA 3 — SEGURANÇA (UFW, FAIL2BAN, AUDITD, NTP, SSH)
# =============================================================================
step_3_security() {
  step "3" "CONFIGURAÇÃO DE SEGURANÇA"

  # ── UFW ───────────────────────────────────────────────────────────────────
  sub "Instalando e configurando UFW..."
  q apt-get install -y -qq ufw
  q ufw --force reset
  q ufw default deny incoming
  q ufw default allow outgoing
  q ufw allow 22/tcp    comment "SSH - administracao"
  q ufw allow 80/tcp    comment "AD Manager - HTTP redirect"
  q ufw allow 443/tcp   comment "AD Manager - HTTPS"
  q ufw deny  3001/tcp  comment "Backend - somente Docker interno"
  q ufw deny  5432/tcp  comment "PostgreSQL - somente Docker interno"
  q ufw deny  6379/tcp  comment "Redis - somente Docker interno"
  q ufw deny  3000/tcp  comment "Frontend dev - somente Docker interno"
  echo "y" | q ufw enable
  ok "UFW configurado — portas 22, 80 e 443 abertas; internas bloqueadas"

  # ── fail2ban ──────────────────────────────────────────────────────────────
  sub "Instalando e configurando fail2ban..."
  q apt-get install -y -qq fail2ban

  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 7200
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
EOF

  q systemctl enable fail2ban
  q systemctl restart fail2ban
  ok "fail2ban configurado (SSH: 3 tentativas → 24h ban)"

  # ── auditd ────────────────────────────────────────────────────────────────
  sub "Instalando e configurando auditd..."
  q apt-get install -y -qq auditd audispd-plugins

  cat > /etc/audit/rules.d/admanager.rules << EOF
# AD License Manager — regras de auditoria
-w ${INSTALL_DIR}/.env -p rwxa -k admanager-config
-w ${INSTALL_DIR}/scripts/ -p rwxa -k admanager-scripts
-w /etc/systemd/system/ad-license-manager.service -p rwxa -k admanager-service
-w /etc/docker/daemon.json -p rwxa -k docker-config
-a always,exit -F arch=b64 -S execve -F uid=0 -k root-commands
EOF

  q systemctl enable auditd
  q systemctl restart auditd
  ok "auditd configurado com regras para arquivos críticos"

  # ── NTP / chrony ──────────────────────────────────────────────────────────
  sub "Instalando e configurando sincronização NTP (chrony)..."
  q apt-get install -y -qq chrony

  cat > /etc/chrony/chrony.conf << 'EOF'
pool time.google.com     iburst maxsources 4
pool ntp.ubuntu.com      iburst maxsources 3
pool time.cloudflare.com iburst maxsources 2
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

  q systemctl enable chrony
  q systemctl restart chrony
  ok "chrony configurado (Google, Cloudflare, Ubuntu NTP pools)"

  # ── Hardening SSH ─────────────────────────────────────────────────────────
  sub "Aplicando hardening no SSH..."
  local SSHD_CONF="/etc/ssh/sshd_config"

  declare -A SSH_SETTINGS=(
    ["PermitRootLogin"]="no"
    ["PasswordAuthentication"]="yes"
    ["MaxAuthTries"]="3"
    ["LoginGraceTime"]="30"
    ["ClientAliveInterval"]="300"
    ["ClientAliveCountMax"]="2"
    ["X11Forwarding"]="no"
    ["AllowTcpForwarding"]="no"
    ["Protocol"]="2"
  )

  for key in "${!SSH_SETTINGS[@]}"; do
    if grep -q "^${key}" "$SSHD_CONF"; then
      sed -i "s/^${key}.*/${key} ${SSH_SETTINGS[$key]}/" "$SSHD_CONF"
    else
      echo "${key} ${SSH_SETTINGS[$key]}" >> "$SSHD_CONF"
    fi
  done

  q sshd -t && q systemctl reload sshd \
    && ok "SSH hardened (root desabilitado, máx. 3 tentativas)" \
    || warn "SSH não recarregado — verifique sshd_config manualmente"
}

# =============================================================================
#  ETAPA 4 — INSTALAÇÃO DO DOCKER ENGINE
# =============================================================================
step_4_docker() {
  step "4" "INSTALAÇÃO DO DOCKER ENGINE"

  if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    local DV CV
    DV=$(docker --version        | grep -oP '\d+\.\d+\.\d+' | head -1)
    CV=$(docker compose version  | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker ${DV} já instalado"
    ok "Compose Plugin ${CV} já instalado"
    q systemctl enable docker
    q systemctl start  docker
    usermod -aG docker "$SERVICE_USER"
    return 0
  fi

  sub "Removendo versões antigas do Docker..."
  q apt-get remove -y -qq \
    docker docker-engine docker.io containerd runc \
    docker-compose docker-compose-plugin 2>/dev/null || true
  ok "Versões antigas removidas"

  sub "Adicionando chave GPG oficial do Docker..."
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>>"$INSTALL_LOG" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  sub "Adicionando repositório oficial do Docker..."
  local ARCH
  ARCH=$(dpkg --print-architecture)
  cat > /etc/apt/sources.list.d/docker.list << EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF
  q apt-get update -qq
  ok "Repositório Docker adicionado (${UBUNTU_CODENAME} / ${ARCH})"

  sub "Instalando Docker Engine, CLI e Compose Plugin..."
  q apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  ok "Docker instalado"

  sub "Configurando Docker daemon..."
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver":        "json-file",
  "log-opts":          { "max-size": "50m", "max-file": "5" },
  "storage-driver":    "overlay2",
  "live-restore":      true,
  "userland-proxy":    false,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 }
  }
}
EOF

  q systemctl enable docker
  q systemctl start  docker
  ok "Docker daemon iniciado e configurado"

  usermod -aG docker "$SERVICE_USER"
  ok "Usuário '${SERVICE_USER}' adicionado ao grupo docker"

  sub "Verificando funcionamento do Docker..."
  q docker run --rm hello-world \
    && ok "Docker funcionando corretamente" \
    || fail "Docker instalado mas não está funcionando. Verifique: ${INSTALL_LOG}"

  local DV CV
  DV=$(docker --version        | grep -oP '\d+\.\d+\.\d+' | head -1)
  CV=$(docker compose version  | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${DV} · Compose Plugin ${CV}"
}

# =============================================================================
#  ETAPA 5 — DOWNLOAD DO CÓDIGO-FONTE
# =============================================================================
step_5_clone() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    sub "Repositório existente encontrado. Atualizando..."
    cd "${INSTALL_DIR}"
    q git fetch origin
    q git reset --hard origin/main
    ok "Código atualizado para a versão mais recente"
  else
    sub "Clonando repositório em ${INSTALL_DIR}..."
    local TMP
    TMP=$(mktemp -d)
    if q git clone "$REPO_URL" "$TMP"; then
      cp -a "${TMP}/." "${INSTALL_DIR}/"
      rm -rf "$TMP"
      ok "Repositório clonado com sucesso"
    else
      rm -rf "$TMP"
      fail "Falha ao clonar ${REPO_URL}. Verifique a URL e o acesso."
    fi
  fi

  find "${INSTALL_DIR}" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
  ok "Permissões dos scripts configuradas"
}

# =============================================================================
#  ETAPA 6 — ARQUIVO DE CONFIGURAÇÃO (.env)
# =============================================================================
step_6_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

  sub "Gerando segredos criptográficos aleatórios..."
  DB_PASSWORD=$(gen_password)
  REDIS_PASSWORD=$(gen_password)
  JWT_SECRET=$(gen_secret)
  JWT_REFRESH_SECRET=$(gen_secret)
  ENCRYPTION_KEY=$(gen_hex)
  ok "Segredos gerados (${#JWT_SECRET} chars JWT · 64 bytes ENCRYPTION_KEY)"

  sub "Escrevendo ${INSTALL_DIR}/.env..."
  cat > "${INSTALL_DIR}/.env" << EOF
# ══════════════════════════════════════════════════════════════════════════════
#  AD License Manager — Configuração do Ambiente
#  Gerado em: $(date '+%d/%m/%Y às %H:%M:%S') pelo instalador v${INSTALLER_VERSION}
#  ATENÇÃO: Arquivo sensível. Permissão 600. Não commite no repositório.
# ══════════════════════════════════════════════════════════════════════════════

# ── Aplicação ─────────────────────────────────────────────────────────────────
APP_DOMAIN=${APP_DOMAIN}
APP_URL=https://${APP_DOMAIN}
NODE_ENV=production
PORT=3001
ALLOWED_ORIGINS=https://${APP_DOMAIN}
SERVER_IP=${SERVER_IP}

# ── Banco de dados ────────────────────────────────────────────────────────────
DB_USER=admanager
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=admanager
DATABASE_URL=postgresql://admanager:${DB_PASSWORD}@postgres:5432/admanager

# ── Redis ─────────────────────────────────────────────────────────────────────
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

# ── JWT ───────────────────────────────────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# ── Criptografia ──────────────────────────────────────────────────────────────
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# ── Active Directory ──────────────────────────────────────────────────────────
AD_URL=${AD_URL}
AD_BASE_DN=${AD_BASE_DN}
AD_USERNAME=${AD_USERNAME}
AD_PASSWORD=${AD_PASSWORD}
AD_DOMAIN=${AD_DOMAIN}

# ── Azure AD / Microsoft Graph ────────────────────────────────────────────────
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}

# ── Administrador inicial ─────────────────────────────────────────────────────
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}

# ── SMTP ──────────────────────────────────────────────────────────────────────
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURE=${SMTP_SECURE}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_FROM=${SMTP_FROM}

# ── Microsoft Teams ───────────────────────────────────────────────────────────
TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL}

# ── Integrações externas (configurar após instalação) ─────────────────────────
GLPI_URL=
GLPI_APP_TOKEN=
GLPI_USER_TOKEN=

# ── Comportamento da aplicação ────────────────────────────────────────────────
LOG_LEVEL=info
SESSION_TIMEOUT_MINUTES=60
MAX_LOGIN_ATTEMPTS=5
PASSWORD_MIN_LENGTH=12
INACTIVE_USER_THRESHOLD_DAYS=90
PASSWORD_EXPIRY_ALERT_DAYS=14
LICENSE_ALERT_THRESHOLD=85
AUDIT_RETENTION_DAYS=365
EOF

  chmod 600 "${INSTALL_DIR}/.env"
  chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/.env"
  ok ".env gerado com permissão 600"

  local BAK="${INSTALL_DIR}/.env.backup-$(date +%Y%m%d-%H%M%S)"
  cp "${INSTALL_DIR}/.env" "$BAK"
  chmod 600 "$BAK"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$BAK"
  ok "Backup salvo em: $(basename "$BAK")"
}

# =============================================================================
#  ETAPA 7 — CERTIFICADO TLS
# =============================================================================
step_7_tls() {
  step "7" "CONFIGURAÇÃO DO CERTIFICADO TLS"

  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  # ── Let's Encrypt ──────────────────────────────────────────────────────────
  if [ "$CERT_OPCAO" = "1" ]; then
    sub "Instalando Certbot..."
    q apt-get install -y -qq certbot
    ok "Certbot instalado"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nginx"; then
      q docker compose -f "${INSTALL_DIR}/docker-compose.yml" stop nginx
    fi

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
DOMAIN="${APP_DOMAIN}"
SSL_DIR="${SSL_DIR}"
LOG="${INSTALL_DIR}/logs/certbot.log"

certbot renew --quiet
cp /etc/letsencrypt/live/\${DOMAIN}/fullchain.pem \${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/\${DOMAIN}/privkey.pem   \${SSL_DIR}/key.pem
chown ${SERVICE_USER}:${SERVICE_USER} \${SSL_DIR}/cert.pem \${SSL_DIR}/key.pem
chmod 644 \${SSL_DIR}/cert.pem
chmod 600 \${SSL_DIR}/key.pem
docker compose -f "${INSTALL_DIR}/docker-compose.yml" restart nginx
echo "\$(date '+%Y-%m-%d %H:%M:%S') Certificado renovado com sucesso." >> "\$LOG"
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

REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d '"'"'" ')

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
  | cut -d= -f2- | tr -d '"'"'" ' || echo "")

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

  # ── restore.sh ─────────────────────────
