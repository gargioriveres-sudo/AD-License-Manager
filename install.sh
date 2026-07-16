#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Completo e Autônomo
#  Ubuntu Server 22.04 LTS / 24.04 LTS
#  Versão 2.0.0 — Julho de 2026
#
#  Uso: sudo bash install.sh
#
#  O instalador realiza AUTOMATICAMENTE:
#    - Atualização do sistema
#    - Instalação e configuração do Docker
#    - Criação de usuários e diretórios
#    - Configuração de firewall, fail2ban, auditd, NTP
#    - Geração de certificado TLS
#    - Build e inicialização de todos os containers
#    - Configuração do systemd para boot automático
#    - Criação de scripts de operação (backup, health, update)
#    - Configuração de cron jobs
#    - Registro DNS local (/etc/hosts)
#
#  O usuário precisa fornecer APENAS:
#    - Domínio de acesso
#    - Dados de conexão do Active Directory
#    - Credenciais do admin inicial
#    - (Opcionais) Azure, SMTP, Teams
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Versão do instalador ────────────────────────────────────────────────────
INSTALLER_VERSION="2.0.0"
REQUIRED_RAM_GB=4
REQUIRED_DISK_GB=15
REPO_URL="${REPO_URL:-https://github.com/sua-org/ad-license-manager.git}"
INSTALL_DIR="/opt/ad-license-manager"
INSTALL_LOG="/tmp/admanager-install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_START=$(date +%s)
UBUNTU_CODENAME=""
UBUNTU_VERSION=""

# ─── Variáveis de configuração ───────────────────────────────────────────────
APP_DOMAIN=""
AD_URL=""
AD_BASE_DN=""
AD_USERNAME=""
AD_PASSWORD=""
AD_DOMAIN=""
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

# ─── Cores ───────────────────────────────────────────────────────────────────
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

# ─── Log ─────────────────────────────────────────────────────────────────────
touch "$INSTALL_LOG"
chmod 600 "$INSTALL_LOG"

# Executa comando silenciosamente, grava saída no log
q() { "$@" >> "$INSTALL_LOG" 2>&1; }

# Executa e mostra saída na tela E no log
v() { "$@" 2>&1 | tee -a "$INSTALL_LOG"; }

# ─── UI ──────────────────────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════════════╗"
  echo "  ║        AD License Manager — Instalador Autônomo v${INSTALLER_VERSION}          ║"
  echo "  ║        Ubuntu Server 22.04 LTS / 24.04 LTS                       ║"
  echo "  ╚═══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

step()    { echo ""; echo -e "${CYAN}${BOLD}━━ ETAPA $1 — $2${NC}"; echo ""; }
ok()      { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()    { echo -e "  ${DIM}ℹ  $1${NC}"; }
sub()     { echo -e "  ${BLUE}▸${NC} $1"; }
div()     { echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"; }
fail()    { echo ""; echo -e "  ${RED}${BOLD}✗  ERRO CRÍTICO: $1${NC}"; echo ""; echo -e "  ${DIM}Log: ${INSTALL_LOG}${NC}"; echo ""; exit 1; }

pg()      { echo -ne "  ${BLUE}▸${NC} $1..."; }
pg_ok()   { echo -e " ${GREEN}OK${NC}"; }
pg_fail() { echo -e " ${RED}FALHOU${NC}"; }

# Pergunta simples com padrão
ask() {
  local label=$1 default=${2:-""}
  if [ -n "$default" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} ${DIM}[${default}]${NC}: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC}: "
  fi
  local val
  read -r val
  echo "${val:-$default}"
}

# Pergunta de senha sem eco
ask_secret() {
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}$1${NC}: "
  local val
  read -rs val; echo ""
  echo "$val"
}

# Confirmação S/N
confirm() {
  local label=$1 default=${2:-s}
  local hint
  [ "$default" = "s" ] && hint="${GREEN}S${NC}/n" || hint="s/${GREEN}N${NC}"
  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${label}${NC} [${hint}]: "
  local val
  read -r val
  val="${val:-$default}"
  [[ "$val" =~ ^[SsYy]$ ]]
}

# Aguarda serviço com timeout
wait_for() {
  local label=$1 cmd=$2 tries=${3:-30} interval=${4:-3}
  echo -ne "  Aguardando ${label}"
  local i=0
  while [ $i -lt $tries ]; do
    if eval "$cmd" >> "$INSTALL_LOG" 2>&1; then
      echo -e " ${GREEN}pronto!${NC}"
      return 0
    fi
    echo -n "."
    sleep "$interval"
    i=$((i + 1))
  done
  echo -e " ${RED}timeout após $((tries * interval))s${NC}"
  return 1
}

# ─── Validações ──────────────────────────────────────────────────────────────
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

is_strong_password() {
  local p=$1
  [ ${#p} -ge 12 ] && \
  echo "$p" | grep -q '[A-Z]' && \
  echo "$p" | grep -q '[a-z]' && \
  echo "$p" | grep -q '[0-9]'
}

password_strength_label() {
  local p=$1
  local score=0
  [ ${#p} -ge 12 ] && score=$((score+1))
  echo "$p" | grep -q '[A-Z]'      && score=$((score+1))
  echo "$p" | grep -q '[a-z]'      && score=$((score+1))
  echo "$p" | grep -q '[0-9]'      && score=$((score+1))
  echo "$p" | grep -q '[^a-zA-Z0-9]' && score=$((score+1))
  case $score in
    0|1) echo "Muito fraca" ;;
    2)   echo "Fraca" ;;
    3)   echo "Regular" ;;
    4)   echo "Forte" ;;
    5)   echo "Muito forte" ;;
  esac
}

# ─── Geração de segredos ──────────────────────────────────────────────────────
gen_secret() {
  openssl rand -base64 64 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-80
}

gen_password() {
  openssl rand -base64 32 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32
}

gen_hex() {
  openssl rand -hex 32
}

# ─── Detecta IP do servidor ───────────────────────────────────────────────────
detect_server_ip() {
  SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || \
              hostname -I 2>/dev/null | awk '{print $1}' || \
              echo "127.0.0.1")
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 0 — VERIFICAÇÕES INICIAIS
# ═══════════════════════════════════════════════════════════════════════════════
step_0_verificacoes() {
  banner

  echo -e "  ${DIM}Log detalhado: ${INSTALL_LOG}${NC}"
  echo ""

  # Root
  [ "$(id -u)" -eq 0 ] || fail "Execute como root: sudo bash install.sh"

  # Ubuntu
  if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "?")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
    if [[ "$UBUNTU_VERSION" == "22.04" || "$UBUNTU_VERSION" == "24.04" ]]; then
      ok "Ubuntu ${UBUNTU_VERSION} LTS (${UBUNTU_CODENAME})"
    else
      warn "Ubuntu ${UBUNTU_VERSION} não é LTS suportada (22.04 / 24.04)."
      confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
    fi
  else
    warn "Sistema não é Ubuntu."
    confirm "Continuar mesmo assim" "n" || { echo "Cancelado."; exit 0; }
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
  fi

  # Arquitetura
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|aarch64) ok "Arquitetura: ${ARCH}" ;;
    *) fail "Arquitetura ${ARCH} não suportada. Use x86_64 ou aarch64." ;;
  esac

  # RAM
  RAM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
  if [ "$RAM_GB" -lt "$REQUIRED_RAM_GB" ]; then
    fail "RAM insuficiente: ${RAM_GB}GB. Mínimo: ${REQUIRED_RAM_GB}GB."
  elif [ "$RAM_GB" -lt 8 ]; then
    warn "RAM: ${RAM_GB}GB — recomendado 8GB+ para produção."
  else
    ok "RAM: ${RAM_GB}GB"
  fi

  # Disco
  DISK_KB=$(df --block-size=1K / | awk 'NR==2{print $4}')
  DISK_GB=$((DISK_KB / 1024 / 1024))
  if [ "$DISK_GB" -lt "$REQUIRED_DISK_GB" ]; then
    fail "Disco insuficiente: ${DISK_GB}GB livres. Mínimo: ${REQUIRED_DISK_GB}GB."
  elif [ "$DISK_GB" -lt 40 ]; then
    warn "Disco: ${DISK_GB}GB livres — recomendado 40GB+ para produção."
  else
    ok "Disco: ${DISK_GB}GB livres"
  fi

  # Internet
  pg "Verificando acesso à internet"
  if curl -sf --max-time 15 https://download.docker.com > /dev/null 2>&1; then
    pg_ok
  else
    pg_fail
    fail "Sem acesso à internet. Necessário para download do Docker e imagens."
  fi

  # Detecta IP do servidor
  detect_server_ip
  ok "IP do servidor: ${SERVER_IP}"

  # Reinstalação
  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""
    warn "Instalação existente detectada em ${INSTALL_DIR}."
    confirm "Deseja REINSTALAR (dados serão perdidos)" "n" || { echo "Cancelado."; exit 0; }
  fi

  ok "Todas as verificações passaram"
  echo ""
  read -rp "$(echo -e "  ${DIM}Pressione ENTER para começar...${NC}")"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 1 — COLETA DE INFORMAÇÕES
# ═══════════════════════════════════════════════════════════════════════════════
step_1_coletar() {
  banner
  step "1" "COLETA DE INFORMAÇÕES"

  echo -e "  Preencha os dados abaixo. ${DIM}Valores entre [ ] são padrões.${NC}"
  echo ""

  # ── 1.1 Domínio ─────────────────────────────────────────────────────────
  div
  echo -e "  ${WHITE}${BOLD}1.1  Acesso à interface web${NC}"
  echo ""
  info "O domínio deve apontar para o IP ${SERVER_IP} deste servidor."
  info "Se não tiver DNS, o instalador criará uma entrada no /etc/hosts."
  echo ""

  while true; do
    APP_DOMAIN=$(ask "Domínio de acesso" "admanager.empresa.com.br")
    if [ -z "$APP_DOMAIN" ]; then
      warn "Obrigatório."
    elif ! is_valid_domain "$APP_DOMAIN"; then
      warn "Formato inválido. Ex: admanager.empresa.com.br"
    else
      ok "Domínio: ${APP_DOMAIN}"
      break
    fi
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
    if ! is_valid_ldap_url "$AD_URL"; then
      warn "Formato inválido. Ex: ldaps://dc01.empresa.com.br"
    else
      break
    fi
  done

  while true; do
    AD_BASE_DN=$(ask "Base DN" "DC=empresa,DC=com,DC=br")
    if ! is_valid_base_dn "$AD_BASE_DN"; then
      warn "Formato inválido. Ex: DC=empresa,DC=com,DC=br"
    else
      break
    fi
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
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':' || echo "636")
    AD_PORT="${AD_PORT:-636}"
  else
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':' || echo "389")
    AD_PORT="${AD_PORT:-389}"
  fi

  pg "Testando conectividade com ${AD_HOST}:${AD_PORT}"
  if nc -zw 5 "$AD_HOST" "$AD_PORT" 2>/dev/null; then
    pg_ok
  else
    pg_fail
    warn "Não foi possível conectar ao AD em ${AD_HOST}:${AD_PORT}."
    warn "Verifique endereço, porta e regras de firewall."
    confirm "Continuar mesmo sem confirmar conectividade" "n" || \
      fail "Conectividade com AD não confirmada. Corrija e tente novamente."
  fi

  # ── 1.3 Azure AD (opcional) ──────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.3  Microsoft 365 / Azure AD ${DIM}(opcional — para gestão de licenças)${NC}"
  echo ""

  if confirm "Configurar integração com Microsoft 365" "n"; then
    SETUP_GRAPH="s"
    while true; do
      AZURE_TENANT_ID=$(ask "Azure Tenant ID")
      [ -n "$AZURE_TENANT_ID" ] && break; warn "Obrigatório."
    done
    while true; do
      AZURE_CLIENT_ID=$(ask "Azure Client ID")
      [ -n "$AZURE_CLIENT_ID" ] && break; warn "Obrigatório."
    done
    while true; do
      AZURE_CLIENT_SECRET=$(ask_secret "Azure Client Secret")
      [ -n "$AZURE_CLIENT_SECRET" ] && break; warn "Obrigatório."
    done
    ok "Azure AD configurado"
  else
    warn "Integração M365 ignorada. Configure depois em Configurações → Azure."
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
    if ! is_valid_email "$ADMIN_EMAIL"; then
      warn "Formato inválido. Ex: ti@empresa.com.br"
    else
      break
    fi
  done

  echo ""
  info "Requisitos de senha: mínimo 12 caracteres, maiúsculas, minúsculas e números."
  echo ""

  while true; do
    ADMIN_PASSWORD=$(ask_secret "Senha do administrador")
    if [ ${#ADMIN_PASSWORD} -lt 12 ]; then
      warn "Senha muito curta. Mínimo 12 caracteres."
      continue
    fi
    local STRENGTH
    STRENGTH=$(password_strength_label "$ADMIN_PASSWORD")
    local CONFIRM
    CONFIRM=$(ask_secret "Confirme a senha")
    if [ "$ADMIN_PASSWORD" != "$CONFIRM" ]; then
      warn "As senhas não coincidem."
    else
      ok "Administrador: ${ADMIN_USER} — ${ADMIN_EMAIL} (Senha: ${STRENGTH})"
      break
    fi
  done

  # ── 1.5 SMTP (opcional) ──────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.5  Email — SMTP ${DIM}(opcional — para alertas e relatórios)${NC}"
  echo ""

  if confirm "Configurar envio de emails" "n"; then
    SETUP_SMTP="s"
    SMTP_HOST=$(ask "Host SMTP" "smtp.empresa.com.br")
    SMTP_PORT=$(ask "Porta SMTP" "587")
    SMTP_SECURE=$(ask "TLS/SSL obrigatório — 'true' para porta 465" "false")
    SMTP_USER=$(ask "Usuário SMTP (em branco para relay sem autenticação)")
    if [ -n "$SMTP_USER" ]; then
      SMTP_PASS=$(ask_secret "Senha SMTP")
    fi
    ok "SMTP: ${SMTP_HOST}:${SMTP_PORT}"
  else
    warn "SMTP ignorado. Configure depois em Configurações → Notificações."
  fi

  # ── 1.6 Microsoft Teams (opcional) ───────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.6  Microsoft Teams ${DIM}(opcional — alertas em tempo real)${NC}"
  echo ""
  info "Para criar o Webhook: canal → ··· → Conectores → Incoming Webhook → Criar"
  echo ""

  if confirm "Configurar alertas no Microsoft Teams" "n"; then
    SETUP_TEAMS="s"
    while true; do
      TEAMS_WEBHOOK_URL=$(ask "URL do Webhook")
      if [[ "$TEAMS_WEBHOOK_URL" =~ ^https:// ]]; then
        break
      fi
      warn "A URL deve começar com https://"
    done
    ok "Teams configurado"
  else
    warn "Teams ignorado. Configure depois em Configurações → Notificações."
  fi

  # ── 1.7 Certificado TLS ──────────────────────────────────────────────────
  echo ""
  div
  echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"
  echo ""
  echo -e "   ${GREEN}1)${NC} Let's Encrypt   — gratuito e renovação automática (precisa porta 80 pública)"
  echo -e "   ${GREEN}2)${NC} PKI corporativa — você fornece os arquivos após a instalação"
  echo -e "   ${GREEN}3)${NC} Self-signed      — somente para ambiente interno / testes"
  echo ""

  while true; do
    CERT_OPCAO=$(ask "Tipo de certificado" "3")
    case "$CERT_OPCAO" in 1|2|3) break ;; *) warn "Digite 1, 2 ou 3." ;; esac
  done

  # ── Resumo ───────────────────────────────────────────────────────────────
  banner
  echo -e "  ${WHITE}${BOLD}RESUMO DA CONFIGURAÇÃO${NC}"
  echo ""
  div

  local g s t c
  [ "$SETUP_GRAPH" = "s" ]  && g="${GREEN}Configurado${NC}"            || g="${YELLOW}Não configurado${NC}"
  [ "$SETUP_SMTP"  = "s" ]  && s="${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}" || s="${YELLOW}Não configurado${NC}"
  [ "$SETUP_TEAMS" = "s" ]  && t="${GREEN}Configurado${NC}"            || t="${YELLOW}Não configurado${NC}"
  case "$CERT_OPCAO" in
    1) c="${GREEN}Let's Encrypt${NC}" ;;
    2) c="${YELLOW}PKI corporativa (self-signed temporário)${NC}" ;;
    3) c="${YELLOW}Self-signed${NC}" ;;
  esac

  echo -e "  ${CYAN}Aplicação${NC}"
  echo -e "    Domínio         https://${APP_DOMAIN}"
  echo -e "    IP do servidor  ${SERVER_IP}"
  echo ""
  echo -e "  ${CYAN}Active Directory${NC}"
  echo -e "    URL             ${AD_URL}"
  echo -e "    Base DN         ${AD_BASE_DN}"
  echo -e "    Conta           ${AD_USERNAME}"
  echo -e "    Domínio         ${AD_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}Administrador${NC}"
  echo -e "    Usuário         ${ADMIN_USER}"
  echo -e "    Email           ${ADMIN_EMAIL}"
  echo ""
  echo -e "  ${CYAN}Integrações${NC}"
  echo -e "    Microsoft 365   $(echo -e $g)"
  echo -e "    SMTP            $(echo -e $s)"
  echo -e "    Teams           $(echo -e $t)"
  echo ""
  echo -e "  ${CYAN}Certificado TLS  $(echo -e $c)${NC}"
  div
  echo ""

  confirm "Confirmar e iniciar a instalação" "s" || { echo "Cancelado."; exit 0; }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 2 — SEGREDOS CRIPTOGRÁFICOS
# ═══════════════════════════════════════════════════════════════════════════════
step_2_segredos() {
  step "2" "GERAÇÃO DE SEGREDOS CRIPTOGRÁFICOS"

  pg "JWT Secret";            JWT_SECRET=$(gen_secret);            pg_ok
  pg "JWT Refresh Secret";    JWT_REFRESH_SECRET=$(gen_secret);    pg_ok
  pg "Senha do PostgreSQL";   DB_PASSWORD=$(gen_password);         pg_ok
  pg "Senha do Redis";        REDIS_PASSWORD=$(gen_password);      pg_ok
  pg "Chave AES-256";         ENCRYPTION_KEY=$(gen_hex);           pg_ok

  # Valida geração
  for v in JWT_SECRET JWT_REFRESH_SECRET DB_PASSWORD REDIS_PASSWORD ENCRYPTION_KEY; do
    [ -n "${!v}" ] || fail "Falha ao gerar o segredo ${v}."
  done

  ok "Todos os segredos gerados com sucesso"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 3 — PREPARAÇÃO DO SISTEMA UBUNTU
# ═══════════════════════════════════════════════════════════════════════════════
step_3_sistema() {
  step "3" "PREPARAÇÃO DO SISTEMA UBUNTU"

  export DEBIAN_FRONTEND=noninteractive

  # Atualização do sistema
  sub "Atualizando lista de pacotes..."
  q apt-get update -qq
  ok "Lista de pacotes atualizada"

  sub "Aplicando atualizações de segurança..."
  q apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  ok "Atualizações aplicadas"

  # Dependências base
  sub "Instalando dependências base..."
  q apt-get install -y -qq \
    curl wget git openssl netcat-openbsd python3 \
    ca-certificates gnupg lsb-release \
    apt-transport-https software-properties-common \
    cron anacron nano vim htop net-tools \
    dnsutils jq unzip logrotate \
    fail2ban auditd audispd-plugins \
    chrony ufw
  ok "Dependências instaladas"

  # Usuário de serviço
  sub "Criando usuário de serviço 'admanager'..."
  if ! id admanager &>/dev/null; then
    q useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      --comment "AD License Manager Service"
  fi
  ok "Usuário 'admanager' pronto"

  # Estrutura de diretórios
  sub "Criando estrutura de diretórios..."
  local dirs=(
    "${INSTALL_DIR}"
    "${INSTALL_DIR}/logs"
    "${INSTALL_DIR}/backups"
    "${INSTALL_DIR}/scripts"
    "${INSTALL_DIR}/infra"
    "${INSTALL_DIR}/infra/nginx"
    "${INSTALL_DIR}/infra/nginx/ssl"
  )
  for d in "${dirs[@]}"; do
    install -d -m 755 -o admanager -g admanager "$d"
  done
  chmod 700 "${INSTALL_DIR}/logs"
  chmod 700 "${INSTALL_DIR}/backups"
  ok "Estrutura de diretórios criada"

  # Timezone — detecta do sistema ou define São Paulo
  sub "Configurando timezone..."
  local TZ_CURRENT
  TZ_CURRENT=$(cat /etc/timezone 2>/dev/null || echo "")
  if [ -z "$TZ_CURRENT" ]; then
    q timedatectl set-timezone America/Sao_Paulo
    TZ_CURRENT="America/Sao_Paulo (definido pelo instalador)"
  fi
  ok "Timezone: ${TZ_CURRENT}"

  # NTP
  sub "Configurando sincronização de horário (chrony)..."
  cat > /etc/chrony/chrony.conf << 'EOF'
pool pool.ntp.br iburst
pool ntp.ubuntu.com iburst
makestep 1 3
rtcsync
logdir /var/log/chrony
EOF
  q systemctl enable chrony
  q systemctl restart chrony
  ok "NTP com chrony habilitado"

  # fail2ban
  sub "Configurando fail2ban..."
  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 7200
EOF
  q systemctl enable fail2ban
  q systemctl restart fail2ban
  ok "fail2ban configurado (SSH: 3 tentativas → bloqueio de 2h)"

  # auditd
  sub "Configurando auditoria do sistema (auditd)..."
  q systemctl enable auditd
  q systemctl start  auditd
  ok "auditd habilitado"

  # Firewall UFW
  sub "Configurando firewall UFW..."
  # Garante SSH antes de habilitar para não travar a sessão
  q ufw allow 22/tcp   comment "SSH - administracao"
  q ufw allow 80/tcp   comment "AD Manager - HTTP redirect"
  q ufw allow 443/tcp  comment "AD Manager - HTTPS"
  q ufw deny  3001/tcp comment "Backend - apenas Docker interno"
  q ufw deny  5432/tcp comment "PostgreSQL - apenas Docker interno"
  q ufw deny  6379/tcp comment "Redis - apenas Docker interno"
  q ufw deny  3000/tcp comment "Frontend - apenas Docker interno"
  # Habilita com --force para não pedir confirmação
  q ufw --force enable
  q ufw --force reload
  ok "Firewall UFW configurado (portas abertas: 22, 80, 443)"

  # Otimizações do kernel
  sub "Otimizando parâmetros do kernel..."
  cat >> /etc/sysctl.d/99-admanager.conf << 'EOF'
# AD License Manager — Otimizações
net.core.somaxconn             = 65535
net.ipv4.tcp_max_syn_backlog   = 65535
net.ipv4.tcp_tw_reuse          = 1
net.ipv4.ip_local_port_range   = 1024 65535
vm.overcommit_memory           = 1
fs.file-max                    = 100000
EOF
  q sysctl -p /etc/sysctl.d/99-admanager.conf
  ok "Parâmetros do kernel otimizados"

  # Limites do sistema
  sub "Configurando limites de arquivo abertos..."
  cat > /etc/security/limits.d/99-admanager.conf << 'EOF'
admanager soft nofile 65536
admanager hard nofile 65536
root      soft nofile 65536
root      hard nofile 65536
EOF
  ok "Limites de arquivo configurados (65536)"

  # Logrotate
  sub "Configurando rotação automática de logs..."
  cat > /etc/logrotate.d/ad-license-manager << EOF
${INSTALL_DIR}/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 admanager admanager
    sharedscripts
    postrotate
        docker compose -f ${INSTALL_DIR}/docker-compose.yml \
            exec -T backend kill -USR1 1 2>/dev/null || true
    endscript
}
EOF
  ok "Logrotate configurado (30 dias de retenção)"

  # SSH Hardening (mantém acesso mas aumenta a segurança)
  sub "Aplicando hardening do SSH..."
  local SSHD_CFG="/etc/ssh/sshd_config"
  # Faz backup da config original
  cp "$SSHD_CFG" "${SSHD_CFG}.bak.$(date +%Y%m%d)"
  # Aplica apenas configurações seguras que não bloqueiam o acesso
  grep -q "^ClientAliveInterval" "$SSHD_CFG" || echo "ClientAliveInterval 300" >> "$SSHD_CFG"
  grep -q "^ClientAliveCountMax" "$SSHD_CFG" || echo "ClientAliveCountMax 3"   >> "$SSHD_CFG"
  grep -q "^MaxAuthTries"        "$SSHD_CFG" || echo "MaxAuthTries 4"           >> "$SSHD_CFG"
  grep -q "^LoginGraceTime"      "$SSHD_CFG" || echo "LoginGraceTime 30"        >> "$SSHD_CFG"
  q systemctl reload sshd
  ok "SSH hardening aplicado (timeout, tentativas máximas)"

  # /etc/hosts — adiciona o domínio para acesso local
  sub "Registrando domínio no /etc/hosts..."
  local HOSTS_LINE="${SERVER_IP}    ${APP_DOMAIN}"
  if grep -q "$APP_DOMAIN" /etc/hosts; then
    sed -i "/${APP_DOMAIN}/d" /etc/hosts
  fi
  echo "$HOSTS_LINE" >> /etc/hosts
  ok "Entrada adicionada: ${HOSTS_LINE}"

  ok "Sistema Ubuntu preparado com sucesso"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 4 — INSTALAÇÃO DO DOCKER ENGINE
# ═══════════════════════════════════════════════════════════════════════════════
step_4_docker() {
  step "4" "INSTALAÇÃO DO DOCKER ENGINE"

  # Remove versões antigas
  sub "Removendo versões antigas do Docker..."
  q apt-get remove -y \
    docker docker-engine docker.io containerd runc \
    docker-compose docker-compose-plugin \
    docker-ce docker-ce-cli 2>/dev/null || true
  q apt-get autoremove -y
  ok "Versões antigas removidas"

  # Chave GPG
  sub "Adicionando chave GPG oficial do Docker..."
  install -m 0755 -d /etc/apt/keyrings
  # Remove chave antiga se existir
  rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    2>>"$INSTALL_LOG" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  # Repositório
  sub "Adicionando repositório oficial do Docker..."
  local codename="${UBUNTU_CODENAME:-$(lsb_release -cs 2>/dev/null || echo jammy)}"
  local arch
  arch=$(dpkg --print-architecture)
  cat > /etc/apt/sources.list.d/docker.list << EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable
EOF
  q apt-get update -qq
  ok "Repositório Docker adicionado (${codename}/${arch})"

  # Instalação
  sub "Instalando Docker Engine, CLI e Compose Plugin..."
  q apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  ok "Docker instalado"

  # Habilita e inicia
  sub "Habilitando e iniciando o Docker..."
  q systemctl enable docker
  q systemctl start  docker
  ok "Serviço Docker iniciado"

  # Adiciona admanager ao grupo
  sub "Adicionando 'admanager' ao grupo docker..."
  usermod -aG docker admanager
  ok "Usuário admanager pode usar Docker sem sudo"

  # Daemon config
  sub "Configurando daemon Docker..."
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": {
      "Name":  "nofile",
      "Hard":  65536,
      "Soft":  65536
    }
  }
}
EOF
  q systemctl restart docker
  ok "Daemon Docker configurado"

  # Teste
  sub "Verificando funcionamento do Docker..."
  if q docker run --rm hello-world; then
    ok "Docker funcionando corretamente"
  else
    fail "Docker instalado mas não está funcionando. Verifique: ${INSTALL_LOG}"
  fi

  local dv cv
  dv=$(docker --version        | grep -oP '\d+\.\d+\.\d+' | head -1)
  cv=$(docker compose version  | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${dv} · Compose Plugin ${cv}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 5 — DOWNLOAD DO CÓDIGO-FONTE
# ═══════════════════════════════════════════════════════════════════════════════
step_5_clone() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    sub "Atualizando repositório existente..."
    cd "${INSTALL_DIR}"
    q git fetch origin
    q git reset --hard origin/main
    ok "Código atualizado para a versão mais recente"
  else
    sub "Clonando repositório..."
    local TMP
    TMP=$(mktemp -d)
    if q git clone "$REPO_URL" "$TMP"; then
      # Copia para o INSTALL_DIR preservando a estrutura criada na etapa 3
      cp -a "$TMP/." "${INSTALL_DIR}/"
      rm -rf "$TMP"
      ok "Código-fonte baixado em ${INSTALL_DIR}"
    else
      rm -rf "$TMP"
      fail "Falha ao clonar o repositório. Verifique: ${REPO_URL}"
    fi
  fi

  # Permissões dos scripts
  find "${INSTALL_DIR}" -name "*.sh" -exec chmod +x {} \;
  chown -R admanager:admanager "${INSTALL_DIR}"
  ok "Permissões aplicadas"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 6 — ARQUIVO DE CONFIGURAÇÃO (.env)
# ═══════════════════════════════════════════════════════════════════════════════
step_6_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

  sub "Criando .env..."

  cat > "${INSTALL_DIR}/.env" << EOF
# ══════════════════════════════════════════════════════════════════════
#  AD License Manager — Configuração do Ambiente
#  Gerado em: $(date '+%d/%m/%Y às %H:%M:%S')
#  Versão do instalador: ${INSTALLER_VERSION}
#  ─────────────────────────────────────────────────────────────────────
#  ATENÇÃO: Este arquivo contém credenciais sensíveis.
#           Permissão 600 — somente o proprietário pode ler.
#           Não compartilhe. Não commite no repositório.
# ══════════════════════════════════════════════════════════════════════

# ── Aplicação ────────────────────────────────────────────────────────
APP_DOMAIN=${APP_DOMAIN}
APP_URL=https://${APP_DOMAIN}
NODE_ENV=production
PORT=3001
ALLOWED_ORIGINS=https://${APP_DOMAIN}
SERVER_IP=${SERVER_IP}

# ── Banco de dados ───────────────────────────────────────────────────
DB_USER=admanager
DB_PASSWORD=${DB_PASSWORD}
DATABASE_URL=postgresql://admanager:${DB_PASSWORD}@postgres:5432/admanager

# ── Redis ────────────────────────────────────────────────────────────
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── JWT ──────────────────────────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# ── Criptografia ─────────────────────────────────────────────────────
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# ── Active Directory ─────────────────────────────────────────────────
AD_URL=${AD_URL}
AD_BASE_DN=${AD_BASE_DN}
AD_USERNAME=${AD_USERNAME}
AD_PASSWORD=${AD_PASSWORD}
AD_DOMAIN=${AD_DOMAIN}

# ── Azure AD / Microsoft Graph ───────────────────────────────────────
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}

# ── Administrador inicial ────────────────────────────────────────────
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}

# ── SMTP ─────────────────────────────────────────────────────────────
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURE=${SMTP_SECURE}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_FROM=AD Manager <noreply@${APP_DOMAIN}>

# ── Microsoft Teams ──────────────────────────────────────────────────
TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL}

# ── Logs ─────────────────────────────────────────────────────────────
LOG_LEVEL=info
EOF

  chmod 600 "${INSTALL_DIR}/.env"
  chown admanager:admanager "${INSTALL_DIR}/.env"
  ok ".env gerado com permissão 600"

  # Backup
  cp "${INSTALL_DIR}/.env" "${INSTALL_DIR}/.env.backup-$(date +%Y%m%d)"
  chmod 600 "${INSTALL_DIR}/.env.backup-$(date +%Y%m%d)"
  ok "Backup salvo em .env.backup-$(date +%Y%m%d)"

  # Auditoria do .env
  q auditctl -w "${INSTALL_DIR}/.env" -p rwxa -k admanager-config || true
  ok "Auditoria de acesso ao .env habilitada"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 7 — CERTIFICADO TLS
# ═══════════════════════════════════════════════════════════════════════════════
step_7_tls() {
  step "7" "CONFIGURAÇÃO DO CERTIFICADO TLS"

  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  if [ "$CERT_OPCAO" = "1" ]; then
    sub "Instalando Certbot..."
    q apt-get install -y -qq certbot
    ok "Certbot instalado"

    sub "Gerando certificado Let's Encrypt para ${APP_DOMAIN}..."
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        -d "$APP_DOMAIN" \
        >> "$INSTALL_LOG" 2>&1; then

      cp "/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem" "${SSL_DIR}/cert.pem"
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem"   "${SSL_DIR}/key.pem"
      ok "Certificado Let's Encrypt gerado"

      # Script de renovação automática
      cat > /usr/local/bin/admanager-renew-cert.sh << EOF
#!/bin/bash
set -e
DOMAIN="${APP_DOMAIN}"
SSL_DIR="${SSL_DIR}"
LOG="${INSTALL_DIR}/logs/certbot.log"

certbot renew --quiet

cp /etc/letsencrypt/live/\${DOMAIN}/fullchain.pem \${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/\${DOMAIN}/privkey.pem   \${SSL_DIR}/key.pem
chown admanager:admanager \${SSL_DIR}/cert.pem \${SSL_DIR}/key.pem
chmod 644 \${SSL_DIR}/cert.pem
chmod 600 \${SSL_DIR}/key.pem

docker compose -f "${INSTALL_DIR}/docker-compose.yml" restart nginx
echo "\$(date '+%Y-%m-%d %H:%M:%S') Certificado renovado." >> "\$LOG"
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      cat > /etc/cron.d/admanager-certbot << 'EOF'
# Renova certificado Let's Encrypt no dia 1 de cada mes as 02:00
0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh
EOF
      ok "Renovação automática agendada (1º de cada mês às 02:00)"
    else
      warn "Let's Encrypt falhou. Gerando self-signed como fallback."
      CERT_OPCAO="3"
    fi
  fi

  # Self-signed para opção 2, 3 ou fallback
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
      warn "Após a instalação, substitua pelos arquivos da sua PKI em:"
      warn "  ${SSL_DIR}/cert.pem (certificado)"
      warn "  ${SSL_DIR}/key.pem  (chave privada)"
      warn "Em seguida execute: docker compose restart nginx"
    fi
  fi

  # Permissões
  chown admanager:admanager "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  chmod 600 "${SSL_DIR}/key.pem"

  # Valida
  openssl x509 -in "${SSL_DIR}/cert.pem" -noout >> "$INSTALL_LOG" 2>&1 || \
    fail "Certificado TLS inválido."

  local expiry
  expiry=$(openssl x509 -in "${SSL_DIR}/cert.pem" -noout -enddate | cut -d= -f2)
  ok "Certificado válido — expira em: ${expiry}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 8 — BUILD DAS IMAGENS DOCKER
# ═══════════════════════════════════════════════════════════════════════════════
step_8_build() {
  step "8" "BUILD DAS IMAGENS DOCKER"

  cd "${INSTALL_DIR}"

  info "Este processo pode levar de 10 a 25 minutos."
  info "Acompanhe em outro terminal: tail -f ${INSTALL_LOG}"
  echo ""

  sub "Construindo todas as imagens..."
  if docker compose build \
      --no-cache \
      --progress=plain \
      >> "$INSTALL_LOG" 2>&1; then
    ok "Todas as imagens construídas com sucesso"
  else
    fail "Erro no build. Detalhes em: ${INSTALL_LOG}"
  fi

  sub "Imagens geradas:"
  docker compose images 2>/dev/null | tail -n +2 | \
    while IFS= read -r linha; do echo "    ${linha}"; done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 9 — INICIALIZAÇÃO DOS SERVIÇOS
# ═══════════════════════════════════════════════════════════════════════════════
step_9_iniciar() {
  step "9" "INICIALIZAÇÃO DOS SERVIÇOS"

  cd "${INSTALL_DIR}"

  # PostgreSQL e Redis primeiro
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

  # Migrations
  sub "Aplicando migrations do banco de dados..."
  q docker compose run --rm backend node dist/migrate.js || \
    fail "Erro nas migrations. Veja: ${INSTALL_LOG}"
  ok "Migrations aplicadas"

  # Seed
  sub "Criando dados iniciais e usuário administrador..."
  q docker compose run --rm backend node dist/seed.js || \
    fail "Erro no seed. Veja: ${INSTALL_LOG}"
  ok "Dados iniciais criados"

  # Todos os serviços
  sub "Iniciando todos os serviços..."
  q docker compose up -d
  ok "Todos os containers iniciados"

  echo ""
  wait_for "Backend API (timeout: 120s)" \
    "curl -sf http://localhost:3001/health" \
    30 4 || warn "Backend ainda não respondeu. Verifique: docker compose logs backend"

  echo ""
  sub "Status final dos containers:"
  echo ""
  docker compose ps 2>/dev/null | while IFS= read -r l; do echo "    $l"; done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 10 — SYSTEMD (boot automático)
# ═══════════════════════════════════════════════════════════════════════════════
step_10_systemd() {
  step "10" "CONFIGURAÇÃO DE INICIALIZAÇÃO AUTOMÁTICA"

  sub "Criando serviço systemd..."

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
User=admanager
Group=admanager
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

# ═══════════════════════════════════════════════════════════════════════════════
#  ETAPA 11 — SCRIPTS OPERACIONAIS
# ═══════════════════════════════════════════════════════════════════════════════
step_11_scripts() {
  step "11" "CRIAÇÃO DE SCRIPTS OPERACIONAIS"

  # ── backup.sh ─────────────────────────────────────────────────────────────
  sub "Criando scripts/backup.sh..."
  cat > "${INSTALL_DIR}/scripts/backup.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/ad-license-manager"
BACKUP_DIR="${INSTALL_DIR}/backups/$(date +%Y-%m-%d)"
LOG="${INSTALL_DIR}/logs/backup.log"
RETENCAO=30

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

log "=== Backup iniciado ==="
mkdir -p "$BACKUP_DIR"

# Dump do banco
REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" | cut -d= -f2-)

log "Fazendo dump do PostgreSQL..."
docker compose -f "${INSTALL_DIR}/docker-compose.yml" \
  exec -T postgres \
  pg_dump -U admanager admanager \
  --format=custom --compress=9 \
  > "${BACKUP_DIR}/database.dump"
log "Banco: OK ($(du -sh "${BACKUP_DIR}/database.dump" | cut -f1))"

log "Copiando configurações..."
cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"
chmod 600 "${BACKUP_DIR}/.env.bak"
log "Configurações: OK"

log "Comprimindo logs..."
tar -czf "${BACKUP_DIR}/logs.tar.gz" \
  -C "${INSTALL_DIR}" logs/ 2>/dev/null && \
  log "Logs: OK" || log "AVISO: Logs não comprimidos."

log "Removendo backups com mais de ${RETENCAO} dias..."
find "${INSTALL_DIR}/backups" -maxdepth 1 -type d \
  -mtime "+${RETENCAO}" -exec rm -rf {} + 2>/dev/null || true

TOTAL=$(du -sh "$BACKUP_DIR" | cut -f1)
log "=== Backup concluído. Tamanho: ${TOTAL} → ${BACKUP_DIR} ==="
EOF

  # ── health-check.sh ───────────────────────────────────────────────────────
  sub "Criando scripts/health-check.sh..."
  cat > "${INSTALL_DIR}/scripts/health-check.sh" << 'EOF'
#!/usr/bin/env bash
set -uo pipefail
INSTALL_DIR="/opt/ad-license-manager"
COMPOSE="${INSTALL_DIR}/docker-compose.yml"
FALHAS=0

REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" \
  2>/dev/null | cut -d= -f2- | tr -d '"'"'" || echo "")

check() {
  local label="$1" cmd="$2" match="${3:-.}"
  if eval "$cmd" 2>/dev/null | grep -q "$match"; then
    echo "  ✓  ${label}"
  else
    echo "  ✗  ${label}"
    FALHAS=$((FALHAS+1))
  fi
}

echo ""
echo "  ── Health Check — $(date '+%d/%m/%Y %H:%M:%S')"
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
  echo "     Veja: docker compose -f '${COMPOSE}' logs"
  exit 1
else
  echo "  ✓  Todos os serviços saudáveis."
fi
echo ""
EOF

  # ── update.sh ─────────────

