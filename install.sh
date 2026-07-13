#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Interativo Completo
#  Ubuntu Server 22.04 LTS / 24.04 LTS
#  Versão 1.0.0 — Julho de 2026
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Cores e formatação ───────────────────────────────────────────────────────
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

# ─── Funções de exibição ─────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║          AD License Manager — Instalador Interativo             ║"
  echo "  ║          Ubuntu Server 22.04 LTS / 24.04 LTS                   ║"
  echo "  ║          Versão 1.0.0 — Julho de 2026                          ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

step() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  ETAPA $1 — $2${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

substep() { echo -e "  ${BLUE}▸${NC} $1"; }
ok()      { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
erro()    { echo -e "  ${RED}✗${NC}  ${RED}$1${NC}"; }
info()    { echo -e "  ${DIM}ℹ  $1${NC}"; }
ask()     { echo -e "\n  ${MAGENTA}?${NC}  ${WHITE}$1${NC}"; }
divisor() { echo -e "  ${DIM}────────────────────────────────────────────────${NC}"; }

# Barra de progresso
progress() {
  local label=$1
  echo -ne "  ${BLUE}▸${NC} ${label}..."
}
progress_ok() { echo -e " ${GREEN}OK${NC}"; }
progress_fail() { echo -e " ${RED}FALHOU${NC}"; }

# Aguarda com spinner
spinner() {
  local pid=$1 label=$2
  local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  echo -ne "  ${BLUE}${chars:0:1}${NC}  ${label}..."
  while kill -0 "$pid" 2>/dev/null; do
    for i in $(seq 0 $((${#chars} - 1))); do
      echo -ne "\r  ${CYAN}${chars:$i:1}${NC}  ${label}..."
      sleep 0.1
    done
  done
  echo -e "\r  ${GREEN}✓${NC}  ${label}... concluído"
}

# Confirmação S/N
confirmar() {
  local pergunta=$1 padrao=${2:-s}
  local opcoes
  if [ "$padrao" = "s" ]; then opcoes="${GREEN}S${NC}/n"; else opcoes="s/${GREEN}N${NC}"; fi
  read -rp "$(echo -e "  ${MAGENTA}?${NC}  ${pergunta} [${opcoes}]: ")" resposta
  resposta="${resposta:-$padrao}"
  [[ "$resposta" =~ ^[SsYy]$ ]]
}

# Pausa com mensagem
pausar() {
  echo ""
  read -rp "$(echo -e "  ${DIM}Pressione ENTER para continuar...${NC}")"
}

# Falha crítica — para a instalação
falha_critica() {
  echo ""
  erro "ERRO CRÍTICO: $1"
  echo ""
  erro "A instalação foi interrompida. Corrija o problema e execute o instalador novamente."
  echo ""
  echo -e "  ${DIM}Log de erros: ${INSTALL_LOG}${NC}"
  echo ""
  exit 1
}

# ─── Variáveis globais ────────────────────────────────────────────────────────
INSTALL_DIR="/opt/ad-license-manager"
INSTALL_LOG="/tmp/admanager-install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_START=$(date +%s)

# Variáveis de configuração (preenchidas interativamente)
APP_DOMAIN=""
APP_URL=""
AD_URL=""
AD_BASE_DN=""
AD_USERNAME=""
AD_PASSWORD=""
AD_DOMAIN=""
AZURE_TENANT_ID=""
AZURE_CLIENT_ID=""
AZURE_CLIENT_SECRET=""
ADMIN_USER=""
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
USAR_LETSENCRYPT="n"

# ─── Redireciona stderr para log sem suprimir stdout ─────────────────────────
exec 2>>"$INSTALL_LOG"

# ─── ETAPA 0: Verificações iniciais ──────────────────────────────────────────
verificacoes_iniciais() {
  banner

  echo -e "  ${DIM}Este instalador irá configurar o AD License Manager no seu servidor Ubuntu."
  echo -e "  Tempo estimado: 25 a 55 minutos dependendo da velocidade de internet.${NC}"
  echo ""
  echo -e "  ${DIM}Log detalhado sendo gravado em: ${INSTALL_LOG}${NC}"
  echo ""
  divisor

  # Verifica root
  if [ "$EUID" -ne 0 ]; then
    falha_critica "Este instalador precisa ser executado como root. Use: sudo bash install.sh"
  fi

  # Verifica Ubuntu
  if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    warn "Sistema operacional não detectado como Ubuntu."
    warn "Este instalador foi testado apenas no Ubuntu 22.04 e 24.04 LTS."
    if ! confirmar "Deseja continuar mesmo assim" "n"; then
      echo "Instalação cancelada."
      exit 0
    fi
  else
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "desconhecida")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
    ok "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME}) detectado"

    if [[ "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ]]; then
      warn "Versão ${UBUNTU_VERSION} não é LTS suportada oficialmente (22.04 ou 24.04)."
      confirmar "Deseja continuar mesmo assim" "n" || { echo "Instalação cancelada."; exit 0; }
    fi
  fi

  # Verifica arquitetura
  ARCH=$(uname -m)
  if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    falha_critica "Arquitetura ${ARCH} não suportada. Use x86_64 ou aarch64 (ARM64)."
  fi
  ok "Arquitetura ${ARCH} suportada"

  # Verifica RAM
  RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
  if [ "$RAM_GB" -lt 4 ]; then
    falha_critica "Memória insuficiente: ${RAM_GB}GB detectados. Mínimo: 4GB."
  elif [ "$RAM_GB" -lt 8 ]; then
    warn "RAM: ${RAM_GB}GB. Recomendado: 8GB ou mais para produção."
  else
    ok "RAM: ${RAM_GB}GB disponíveis"
  fi

  # Verifica espaço em disco
  DISCO_LIVRE=$(df / --output=avail -k | tail -1)
  DISCO_GB=$((DISCO_LIVRE / 1024 / 1024))
  if [ "$DISCO_GB" -lt 20 ]; then
    falha_critica "Espaço em disco insuficiente: ${DISCO_GB}GB livres. Mínimo: 20GB."
  elif [ "$DISCO_GB" -lt 40 ]; then
    warn "Disco: ${DISCO_GB}GB livres. Recomendado: 40GB ou mais para produção."
  else
    ok "Disco: ${DISCO_GB}GB livres disponíveis"
  fi

  # Verifica conexão com a internet
  progress "Verificando conexão com a internet"
  if curl -sf --max-time 10 https://download.docker.com &>/dev/null; then
    progress_ok
  else
    progress_fail
    falha_critica "Sem acesso à internet. Necessário para download do Docker e imagens."
  fi

  # Verifica se já está instalado
  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""
    warn "Uma instalação existente foi detectada em ${INSTALL_DIR}"
    warn "Prosseguir irá SOBRESCREVER a instalação atual."
    echo ""
    if ! confirmar "Tem certeza que deseja reinstalar" "n"; then
      echo "Instalação cancelada."
      exit 0
    fi
  fi

  echo ""
  ok "Todas as verificações iniciais passaram"
  pausar
}

# ─── ETAPA 1: Coleta de informações ──────────────────────────────────────────
coletar_informacoes() {
  banner
  step "1" "COLETA DE INFORMAÇÕES"

  echo -e "  Responda as perguntas abaixo para configurar o sistema."
  echo -e "  ${DIM}Valores entre colchetes [ ] são sugestões — pressione ENTER para aceitar.${NC}"
  echo ""

  # ── Domínio da aplicação ────────────────────────────────────────────────
  divisor
  echo -e "  ${WHITE}${BOLD}1.1  Configuração da aplicação${NC}"
  echo ""
  ask "Domínio de acesso à interface web (ex: admanager.empresa.com.br):"
  read -r APP_DOMAIN
  while [ -z "$APP_DOMAIN" ]; do
    warn "O domínio é obrigatório."
    ask "Domínio da aplicação:"
    read -r APP_DOMAIN
  done
  APP_URL="https://${APP_DOMAIN}"
  ok "Domínio definido: ${APP_DOMAIN}"

  # ── Active Directory ────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"
  echo ""
  info "Use ldaps:// (porta 636) para habilitar reset de senha via LDAPS."
  info "Use ldap://  (porta 389) apenas se o LDAPS não estiver disponível."
  echo ""

  ask "URL do Controlador de Domínio (ex: ldaps://dc01.empresa.com.br):"
  read -r AD_URL
  while [ -z "$AD_URL" ]; do
    warn "A URL do AD é obrigatória."
    ask "URL do AD:"
    read -r AD_URL
  done

  ask "Base DN do domínio (ex: DC=empresa,DC=com,DC=br):"
  read -r AD_BASE_DN
  while [ -z "$AD_BASE_DN" ]; do
    warn "O Base DN é obrigatório."
    ask "Base DN:"
    read -r AD_BASE_DN
  done

  ask "UPN da conta de serviço (ex: svc-admanager@empresa.com.br):"
  read -r AD_USERNAME
  while [ -z "$AD_USERNAME" ]; do
    warn "A conta de serviço é obrigatória."
    ask "Conta de serviço:"
    read -r AD_USERNAME
  done

  ask "Senha da conta de serviço:"
  read -rs AD_PASSWORD; echo ""
  while [ -z "$AD_PASSWORD" ]; do
    warn "A senha é obrigatória."
    ask "Senha da conta de serviço:"
    read -rs AD_PASSWORD; echo ""
  done

  ask "Domínio NetBIOS / UPN suffix (ex: empresa.com.br):"
  read -r AD_DOMAIN
  while [ -z "$AD_DOMAIN" ]; do
    warn "O domínio é obrigatório."
    ask "Domínio NetBIOS:"
    read -r AD_DOMAIN
  done

  ok "Active Directory configurado"

  # ── Testa conectividade com o AD ────────────────────────────────────────
  echo ""
  AD_HOST=$(echo "$AD_URL" | sed 's|ldaps\?://||' | cut -d: -f1)
  AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':')
  AD_PORT="${AD_PORT:-$(echo "$AD_URL" | grep -qi ldaps && echo 636 || echo 389)}"

  progress "Testando conectividade com ${AD_HOST}:${AD_PORT}"
  if nc -zw 5 "$AD_HOST" "$AD_PORT" 2>/dev/null; then
    progress_ok
  else
    progress_fail
    warn "Não foi possível conectar ao AD em ${AD_HOST}:${AD_PORT}."
    warn "Verifique a URL, porta e regras de firewall."
    if ! confirmar "Deseja continuar mesmo assim" "n"; then
      falha_critica "Conectividade com o AD não confirmada. Corrija e tente novamente."
    fi
  fi

  # ── Azure AD / Microsoft Graph ──────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.3  Azure AD / Microsoft 365 (Licenças)${NC}"
  echo ""
  info "Necessário apenas para gestão de licenças M365."
  info "Sem esta configuração, as funcionalidades de AD continuam disponíveis."
  echo ""

  if confirmar "Deseja configurar a integração com Microsoft 365"; then
    SETUP_GRAPH="s"
    ask "Azure Tenant ID (ex: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx):"
    read -r AZURE_TENANT_ID
    ask "Azure Client ID (Application ID):"
    read -r AZURE_CLIENT_ID
    ask "Azure Client Secret:"
    read -rs AZURE_CLIENT_SECRET; echo ""
    ok "Azure AD configurado"
  else
    warn "Integração M365 ignorada. Pode ser configurada posteriormente."
  fi

  # ── Administrador do sistema ────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.4  Conta de administrador do sistema${NC}"
  echo ""

  ask "Nome do usuário administrador [admin]:"
  read -r ADMIN_USER
  ADMIN_USER="${ADMIN_USER:-admin}"

  ask "Email do administrador (para alertas):"
  read -r ADMIN_EMAIL
  while [[ ! "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
    warn "Formato de email inválido. Ex: ti@empresa.com.br"
    ask "Email do administrador:"
    read -r ADMIN_EMAIL
  done

  echo ""
  info "A senha deve ter: mínimo 12 caracteres, maiúsculas, minúsculas, números e símbolos."
  ask "Senha do administrador (mín. 12 caracteres):"
  read -rs ADMIN_PASSWORD; echo ""

  while [ ${#ADMIN_PASSWORD} -lt 12 ]; do
    warn "Senha muito curta. Mínimo de 12 caracteres."
    ask "Senha do administrador:"
    read -rs ADMIN_PASSWORD; echo ""
  done

  ask "Confirme a senha do administrador:"
  read -rs ADMIN_CONFIRM; echo ""

  while [ "$ADMIN_PASSWORD" != "$ADMIN_CONFIRM" ]; do
    warn "As senhas não coincidem."
    ask "Senha do administrador:"
    read -rs ADMIN_PASSWORD; echo ""
    ask "Confirme a senha:"
    read -rs ADMIN_CONFIRM; echo ""
  done

  ok "Administrador configurado: ${ADMIN_USER} (${ADMIN_EMAIL})"

  # ── SMTP ────────────────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.5  Configuração de Email (SMTP)${NC}"
  echo ""
  info "Necessário para receber alertas, relatórios e notificações por email."
  echo ""

  if confirmar "Deseja configurar o envio de emails via SMTP"; then
    SETUP_SMTP="s"
    ask "Host do servidor SMTP (ex: smtp.empresa.com.br):"
    read -r SMTP_HOST
    ask "Porta SMTP [587]:"
    read -r SMTP_PORT
    SMTP_PORT="${SMTP_PORT:-587}"
    ask "Usar TLS/SSL na porta? (use 'true' para porta 465) [false]:"
    read -r SMTP_SECURE
    SMTP_SECURE="${SMTP_SECURE:-false}"
    ask "Usuário SMTP (deixe em branco para relay sem autenticação):"
    read -r SMTP_USER
    if [ -n "$SMTP_USER" ]; then
      ask "Senha SMTP:"
      read -rs SMTP_PASS; echo ""
    fi
    ok "SMTP configurado: ${SMTP_HOST}:${SMTP_PORT}"
  else
    warn "SMTP ignorado. Alertas por email não funcionarão."
  fi

  # ── Microsoft Teams ─────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.6  Alertas no Microsoft Teams (opcional)${NC}"
  echo ""
  info "Crie um Incoming Webhook no canal desejado do Teams."
  info "Canal → ··· → Conectores → Incoming Webhook → Configurar → Criar → Copiar URL"
  echo ""

  if confirmar "Deseja configurar alertas no Microsoft Teams"; then
    SETUP_TEAMS="s"
    ask "URL do Webhook do Teams:"
    read -r TEAMS_WEBHOOK_URL
    ok "Teams configurado"
  else
    warn "Teams ignorado. Pode ser configurado posteriormente nas Configurações."
  fi

  # ── Certificado TLS ─────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"
  echo ""
  echo -e "  Opções disponíveis:"
  echo -e "   ${GREEN}1)${NC} Let's Encrypt — gratuito, automático (requer acesso à internet na porta 80)"
  echo -e "   ${GREEN}2)${NC} Certificado próprio — PKI corporativa ou certificado comprado"
  echo -e "   ${GREEN}3)${NC} Self-signed — adequado apenas para desenvolvimento/testes"
  echo ""
  ask "Escolha o tipo de certificado [1/2/3]:"
  read -r CERT_OPCAO

  case "$CERT_OPCAO" in
    1)
      USAR_LETSENCRYPT="s"
      info "Let's Encrypt requer que ${APP_DOMAIN} aponte para este servidor e porta 80 acessível."
      ok "Let's Encrypt selecionado"
      ;;
    2)
      USAR_CERT_PROPRIO="s"
      info "Você precisará copiar os arquivos cert.pem e key.pem para:"
      info "${INSTALL_DIR}/infra/nginx/ssl/"
      warn "O instalador gerará um self-signed temporário. Substitua após a instalação."
      ok "Certificado próprio selecionado (self-signed temporário até substituição)"
      ;;
    *)
      USAR_CERT_PROPRIO="n"
      USAR_LETSENCRYPT="n"
      warn "Self-signed selecionado. NÃO use em produção."
      ok "Certificado self-signed será gerado"
      ;;
  esac

  # ── Resumo de confirmação ───────────────────────────────────────────────
  echo ""
  banner
  echo -e "  ${WHITE}${BOLD}RESUMO DA CONFIGURAÇÃO${NC}"
  echo ""
  divisor
  echo -e "  ${CYAN}Aplicação${NC}"
  echo -e "    Domínio:          ${APP_DOMAIN}"
  echo -e "    URL:              ${APP_URL}"
  echo ""
  echo -e "  ${CYAN}Active Directory${NC}"
  echo -e "    URL:              ${AD_URL}"
  echo -e "    Base DN:          ${AD_BASE_DN}"
  echo -e "    Conta de serviço: ${AD_USERNAME}"
  echo -e "    Domínio:          ${AD_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}Administrador${NC}"
  echo -e "    Usuário:          ${ADMIN_USER}"
  echo -e "    Email:            ${ADMIN_EMAIL}"
  echo ""
  echo -e "  ${CYAN}Integrações${NC}"
  echo -e "    Microsoft 365:    $([ "$SETUP_GRAPH" = "s" ] && echo "${GREEN}Configurado${NC}" || echo "${YELLOW}Não configurado${NC}")"
  echo -e "    SMTP:             $([ "$SETUP_SMTP" = "s" ]  && echo "${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}" || echo "${YELLOW}Não configurado${NC}")"
  echo -e "    Microsoft Teams:  $([ "$SETUP_TEAMS" = "s" ] && echo "${GREEN}Configurado${NC}" || echo "${YELLOW}Não configurado${NC}")"
  echo ""
  echo -e "  ${CYAN}Certificado TLS${NC}"
  echo -e "    Tipo:             $([ "$USAR_LETSENCRYPT" = "s" ] && echo "${GREEN}Let's Encrypt${NC}" || echo "${YELLOW}Self-signed / próprio${NC}")"
  divisor
  echo ""

  if ! confirmar "As informações estão corretas? Deseja iniciar a instalação"; then
    warn "Instalação cancelada pelo usuário."
    exit 0
  fi
}

# ─── ETAPA 2: Geração de segredos ─────────────────────────────────────────────
gerar_segredos() {
  step "2" "GERAÇÃO DE SEGREDOS CRIPTOGRÁFICOS"

  progress "Gerando JWT Secret (512 bits)"
  JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n/+=')
  progress_ok

  progress "Gerando JWT Refresh Secret (512 bits)"
  JWT_REFRESH_SECRET=$(openssl rand -base64 64 | tr -d '\n/+=')
  progress_ok

  progress "Gerando senha do PostgreSQL (256 bits)"
  DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32)
  progress_ok

  progress "Gerando senha do Redis (256 bits)"
  REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32)
  progress_ok

  progress "Gerando chave de criptografia AES-256"
  ENCRYPTION_KEY=$(openssl rand -hex 32)
  progress_ok

  ok "Todos os segredos gerados com segurança"
}

# ─── ETAPA 3: Preparação do sistema Ubuntu ─────────────────────────────────────
preparar_sistema() {
  step "3" "PREPARAÇÃO DO SISTEMA UBUNTU"

  # Atualização de pacotes
  substep "Atualizando lista de pacotes..."
  apt-get update -qq >> "$INSTALL_LOG" 2>&1
  ok "Lista de pacotes atualizada"

  substep "Aplicando atualizações de segurança..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" >> "$INSTALL_LOG" 2>&1
  ok "Atualizações aplicadas"

  # Dependências base
  substep "Instalando dependências base..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget git openssl netcat-openbsd python3 python3-pip \
    ca-certificates gnupg lsb-release apt-transport-https \
    software-properties-common cron nano vim htop net-tools \
    dnsutils jq unzip logrotate fail2ban auditd \
    >> "$INSTALL_LOG" 2>&1
  ok "Dependências base instaladas"

  # Usuário de serviço
  substep "Criando usuário de serviço 'admanager'..."
  if ! id admanager &>/dev/null; then
    useradd \
      --system \
      --no-create-home \
      --shell /sbin/nologin \
      --comment "AD License Manager Service Account" \
      admanager >> "$INSTALL_LOG" 2>&1
    ok "Usuário 'admanager' criado"
  else
    ok "Usuário 'admanager' já existe"
  fi

  # Estrutura de diretórios
  substep "Criando estrutura de diretórios..."
  mkdir -p \
    "${INSTALL_DIR}" \
    "${INSTALL_DIR}/logs" \
    "${INSTALL_DIR}/backups" \
    "${INSTALL_DIR}/infra/nginx/ssl" \
    "${INSTALL_DIR}/scripts"
  ok "Diretórios criados"

  # Configuração de timezone
  substep "Configurando timezone..."
  CURRENT_TZ=$(cat /etc/timezone 2>/dev/null || echo "")
  if [ -z "$CURRENT_TZ" ]; then
    timedatectl set-timezone America/Sao_Paulo >> "$INSTALL_LOG" 2>&1
    ok "Timezone definido: America/Sao_Paulo"
  else
    ok "Timezone atual: ${CURRENT_TZ}"
  fi

  # NTP com chrony
  substep "Configurando sincronização de horário (NTP)..."
  apt-get install -y -qq chrony >> "$INSTALL_LOG" 2>&1
  systemctl enable chrony >> "$INSTALL_LOG" 2>&1
  systemctl restart chrony >> "$INSTALL_LOG" 2>&1
  ok "Sincronização NTP habilitada via chrony"

  # Fail2ban
  substep "Configurando fail2ban (proteção SSH)..."
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
  systemctl enable fail2ban >> "$INSTALL_LOG" 2>&1
  systemctl restart fail2ban >> "$INSTALL_LOG" 2>&1
  ok "fail2ban configurado e ativo"

  # Auditd
  substep "Habilitando auditoria do sistema (auditd)..."
  systemctl enable auditd >> "$INSTALL_LOG" 2>&1
  systemctl start  auditd >> "$INSTALL_LOG" 2>&1
  auditctl -w "${INSTALL_DIR}/.env" -p rwxa -k admanager-config 2>/dev/null || true
  ok "auditd configurado"

  # UFW
  substep "Configurando firewall (UFW)..."
  ufw --force reset >> "$INSTALL_LOG" 2>&1
  ufw default deny incoming  >> "$INSTALL_LOG" 2>&1
  ufw default allow outgoing >> "$INSTALL_LOG" 2>&1
  ufw allow 22/tcp   comment "SSH - administracao remota"  >> "$INSTALL_LOG" 2>&1
  ufw allow 80/tcp   comment "AD Manager - HTTP redirect"  >> "$INSTALL_LOG" 2>&1
  ufw allow 443/tcp  comment "AD Manager - HTTPS"          >> "$INSTALL_LOG" 2>&1
  ufw deny  3001/tcp comment "Backend - apenas Docker"     >> "$INSTALL_LOG" 2>&1
  ufw deny  5432/tcp comment "PostgreSQL - apenas Docker"  >> "$INSTALL_LOG" 2>&1
  ufw deny  6379/tcp comment "Redis - apenas Docker"       >> "$INSTALL_LOG" 2>&1
  ufw --force enable >> "$INSTALL_LOG" 2>&1
  ok "UFW configurado — portas 22, 80 e 443 abertas"

  # Logrotate
  substep "Configurando rotação de logs..."
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
  ok "Logrotate configurado (retenção de 30 dias)"

  # Limites do sistema
  substep "Otimizando limites do sistema..."
  cat >> /etc/security/limits.conf << 'EOF'
admanager soft nofile 65536
admanager hard nofile 65536
admanager soft nproc  32768
admanager hard nproc  32768
EOF
  cat > /etc/sysctl.d/99-admanager.conf << 'EOF'
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.overcommit_memory = 1
EOF
  sysctl --system >> "$INSTALL_LOG" 2>&1
  ok "Limites do sistema otimizados"
}

# ─── ETAPA 4: Instalação do Docker ─────────────────────────────────────────────
instalar_docker() {
  step "4" "INSTALAÇÃO DO DOCKER ENGINE"

  # Remove versões antigas
  substep "Removendo instalações antigas do Docker..."
  apt-get remove -y -qq \
    docker docker-engine docker.io containerd runc \
    docker-compose docker-compose-plugin 2>/dev/null || true
  ok "Versões antigas removidas"

  # Adiciona chave GPG
  substep "Adicionando chave GPG oficial do Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
  chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  # Adiciona repositório
  substep "Adicionando repositório oficial do Docker..."
  UBUNTU_CODENAME=$(lsb_release -cs)
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    ${UBUNTU_CODENAME} stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -qq >> "$INSTALL_LOG" 2>&1
  ok "Repositório Docker adicionado"

  # Instala Docker
  substep "Instalando Docker Engine e Compose Plugin..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    >> "$INSTALL_LOG" 2>&1
  ok "Docker Engine instalado"

  # Habilita o serviço
  substep "Habilitando e iniciando o Docker..."
  systemctl enable docker >> "$INSTALL_LOG" 2>&1
  systemctl start  docker >> "$INSTALL_LOG" 2>&1
  ok "Docker iniciado e habilitado no boot"

  # Adiciona usuários ao grupo
  substep "Adicionando usuário 'admanager' ao grupo docker..."
  usermod -aG docker admanager
  ok "Usuário 'admanager' adicionado ao grupo docker"

  # Configura o daemon
  substep "Configurando daemon do Docker..."
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
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF
  systemctl restart docker >> "$INSTALL_LOG" 2>&1
  ok "Daemon Docker configurado"

  # Verifica instalação
  progress "Verificando instalação do Docker"
  if docker run --rm hello-world >> "$INSTALL_LOG" 2>&1; then
    progress_ok
  else
    progress_fail
    falha_critica "Docker instalado mas não está funcionando corretamente."
  fi

  DOCKER_VER=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
  COMPOSE_VER=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${DOCKER_VER} e Compose ${COMPOSE_VER} prontos"
}

# ─── ETAPA 5: Clone do repositório ─────────────────────────────────────────────
clonar_repositorio() {
  step "5" "DOWNLOAD DO SISTEMA"

  substep "Clonando repositório do AD License Manager..."

  if [ -d "${INSTALL_DIR}/.git" ]; then
    substep "Repositório existente encontrado. Atualizando..."
    cd "${INSTALL_DIR}"
    git fetch origin >> "$INSTALL_LOG" 2>&1
    git reset --hard origin/main >> "$INSTALL_LOG" 2>&1
  else
    cd /opt
    git clone \
      https://github.com/sua-org/ad-license-manager.git \
      ad-license-manager >> "$INSTALL_LOG" 2>&1
  fi

  ok "Código-fonte baixado em ${INSTALL_DIR}"

  substep "Tornando scripts executáveis..."
  chmod +x \
    "${INSTALL_DIR}/install.sh" \
    "${INSTALL_DIR}/scripts/"*.sh 2>/dev/null || true
  ok "Permissões dos scripts configuradas"
}

# ─── ETAPA 6: Geração do .env ─────────────────────────────────────────────────
gerar_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

  substep "Criando arquivo .env..."

  cat > "${INSTALL_DIR}/.env" << EOF
# ══════════════════════════════════════════════════════════════════════
#  AD License Manager — Configuração do Ambiente
#  Gerado automaticamente em $(date '+%d/%m/%Y às %H:%M:%S')
#  ATENÇÃO: Este arquivo contém credenciais sensíveis.
#           Nunca compartilhe ou commite este arquivo.
# ══════════════════════════════════════════════════════════════════════

# ── Aplicação ────────────────────────────────────────────────────────
APP_DOMAIN=${APP_DOMAIN}
APP_URL=${APP_URL}
NODE_ENV=production
PORT=3001
ALLOWED_ORIGINS=${APP_URL}

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

  # Permissão restritiva — somente o dono lê
  chmod 600 "${INSTALL_DIR}/.env"
  chown admanager:admanager "${INSTALL_DIR}/.env"
  ok ".env gerado com permissão 600 (somente leitura pelo proprietário)"

  # Backup imediato do .env
  cp "${INSTALL_DIR}/.env" "${INSTALL_DIR}/.env.install-backup"
  chmod 600 "${INSTALL_DIR}/.env.install-backup"
  ok "Backup do .env salvo em .env.install-backup"
}

# ─── ETAPA 7: Certificado TLS ─────────────────────────────────────────────────
configurar_tls() {
  step "7" "CONFIGURAÇÃO DO CERTIFICADO TLS"

  SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"
  mkdir -p "$SSL_DIR"

  if [ "$USAR_LETSENCRYPT" = "s" ]; then
    substep "Instalando Certbot..."
    apt-get install -y -qq certbot >> "$INSTALL_LOG" 2>&1
    ok "Certbot instalado"

    substep "Gerando certificado Let's Encrypt para ${APP_DOMAIN}..."
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        -d "$APP_DOMAIN" >> "$INSTALL_LOG" 2>&1; then

      cp "/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem" "${SSL_DIR}/cert.pem"
      cp "/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem"  "${SSL_DIR}/key.pem"
      ok "Certificado Let's Encrypt gerado com sucesso"

      # Script de renovação automática
      cat > /usr/local/bin/admanager-renew-cert.sh << EOF
#!/bin/bash
certbot renew --quiet
cp /etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem ${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem   ${SSL_DIR}/key.pem
chown admanager:admanager ${SSL_DIR}/cert.pem ${SSL_DIR}/key.pem
chmod 644 ${SSL_DIR}/cert.pem
chmod 600 ${SSL_DIR}/key.pem
docker compose -f ${INSTALL_DIR}/docker-compose.yml restart nginx
echo "\$(date): Certificado renovado." >> ${INSTALL_DIR}/logs/certbot.log
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      echo "0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh" \
        > /etc/cron.d/admanager-certbot
      ok "Renovação automática agendada para o dia 1 de cada mês às 02:00"
    else
      warn "Let's Encrypt falhou. Gerando certificado self-signed como fallback."
      warn "Substitua pelo certificado real após a instalação."
      USAR_LETSENCRYPT="n"
    fi
  fi

  if [ "$USAR_LETSENCRYPT" = "n" ]; then
    substep "Gerando certificado TLS self-signed..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
      -keyout "${SSL_DIR}/key.pem" \
      -out    "${SSL_DIR}/cert.pem" \
      -subj   "/CN=${APP_DOMAIN}/O=AD License Manager/C=BR/OU=TI" \
      -addext "subjectAltName=DNS:${APP_DOMAIN},DNS:localhost,IP:127.0.0.1" \
      >> "$INSTALL_LOG" 2>&1

    CERT_EXPIRY=$(openssl x509 -in "${SSL_DIR}/cert.pem" -noout -enddate | cut -d= -f2)
    ok "Certificado self-signed gerado (válido por 10 anos até: ${CERT_EXPIRY})"
    warn "Substitua este certificado por um válido antes de usar em produção."
  fi

  # Permissões corretas
  chown admanager:admanager "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  chmod 600 "${SSL_DIR}/key.pem"
  ok "Permissões do certificado configuradas"
}

# ─── ETAPA 8: Build das imagens Docker ────────────────────────────────────────
build_imagens() {
  step "8" "BUILD DAS IMAGENS DOCKER"

  cd "${INSTALL_DIR}"

  info "Este processo pode levar entre 8 e 20 minutos dependendo da internet."
  echo ""

  substep "Construindo imagens (backend, frontend, worker, nginx)..."
  echo ""

  if docker compose build \
      --no-cache \
      --parallel \
      >> "$INSTALL_LOG" 2>&1; then
    ok "Todas as imagens construídas com sucesso"
  else
    falha_critica "Erro no build das imagens Docker. Verifique o log: ${INSTALL_LOG}"
  fi

  # Lista as imagens criadas
  substep "Imagens disponíveis:"
  docker compose images 2>/dev/null | tail -n +2 | while read -r line; do
    echo "    ${line}"
  done
}

# ─── ETAPA 9: Inicialização dos serviços ──────────────────────────────────────
iniciar_servicos() {
  step "9" "INICIALIZAÇÃO DOS SERVIÇOS"

  cd "${INSTALL_DIR}"

  # PostgreSQL e Redis primeiro
  substep "Iniciando PostgreSQL e Redis..."
  docker compose up -d postgres redis >> "$INSTALL_LOG" 2>&1
  ok "PostgreSQL e Redis iniciados"

  # Aguarda o PostgreSQL estar pronto
  echo ""
  echo -ne "  Aguardando PostgreSQL ficar pronto"
  TENTATIVAS=0
  MAX=40
  while [ $TENTATIVAS -lt $MAX ]; do
    if docker compose exec -T postgres \
        pg_isready -U admanager -d admanager &>/dev/null; then
      echo -e " ${GREEN}pronto!${NC}"
      break
    fi
    echo -n "."
    sleep 3
    TENTATIVAS=$((TENTATIVAS + 1))
    if [ $TENTATIVAS -eq $MAX ]; then
      echo -e " ${RED}timeout!${NC}"
      falha_critica "PostgreSQL não ficou pronto após $((MAX * 3))s."
    fi
  done
  ok "PostgreSQL aceitando conexões"

  # Aguarda o Redis estar pronto
  echo -ne "  Aguardando Redis ficar pronto"
  TENTATIVAS=0
  while [ $TENTATIVAS -lt 20 ]; do
    if docker compose exec -T redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning ping \
        2>/dev/null | grep -q PONG; then
      echo -e " ${GREEN}pronto!${NC}"
      break
    fi
    echo -n "."
    sleep 2
    TENTATIVAS=$((TENTATIVAS + 1))
  done
  ok "Redis respondendo"

  # Migrations do banco
  substep "Aplicando migrations do banco de dados..."
  if docker compose run --rm backend node dist/migrate.js \
      >> "$INSTALL_LOG" 2>&1; then
    ok "Migrations aplicadas com sucesso"
  else
    falha_critica "Erro ao aplicar migrations. Verifique: ${INSTALL_LOG}"
  fi

  # Seed do banco
  substep "Criando usuário administrador e configurações padrão..."
  if docker compose run --rm backend node dist/seed.js \
      >> "$INSTALL_LOG" 2>&1; then
    ok "Dados iniciais criados"
  else
    falha_critica "Erro no seed do banco. Verifique: ${INSTALL_LOG}"
  fi

  # Sobe todos os serviços
  substep "Iniciando todos os serviços..."
  docker compose up -d >> "$INSTALL_LOG" 2>&1
  ok "Todos os serviços iniciados"

  # Aguarda o backend estar saudável
  echo ""
  echo -ne "  Aguardando backend ficar saudável"
  TENTATIVAS=0
  MAX=30
  while [ $TENTATIVAS -lt $MAX ]; do
    if curl -sf http://localhost:3001/health &>/dev/null; then
      echo -e " ${GREEN}saudável!${NC}"
      break
    fi
    echo -n "."
    sleep 4
    TENTATIVAS=$((TENTATIVAS + 1))
    if [ $TENTATIVAS -eq $MAX ]; then
      echo -e " ${YELLOW}ainda iniciando...${NC}"
      warn "Backend pode precisar de mais tempo. Verifique com: docker compose logs backend"
    fi
  done
}

# ─── ETAPA 10: systemd ────────────────────────────────────────────────────────
configurar_systemd() {
  step "10" "CONFIGURAÇÃO DE INICIALIZAÇÃO AUTOMÁTICA"

  substep "Criando serviço systemd..."

  cat > /etc/systemd/system/ad-license-manager.service << EOF
[Unit]
Description=AD License Manager
Documentation=https://github.com/sua-org/ad-license-manager
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
User=admanager
Group=admanager
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down --timeout 30
ExecReload=/usr/bin/docker compose up -d --remove-orphans
ExecStartPost=/bin/bash -c '\
  for i in \$(seq 1 30); do \
    curl -sf http://localhost:3001/health >/dev/null 2>&1 && exit 0; \
    sleep 4; \
  done; exit 0'
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
  systemctl enable ad-license-manager >> "$INSTALL_LOG" 2>&1
  ok "Serviço systemd criado e habilitado no boot"
}

# ─── ETAPA 11: Backup automático ──────────────────────────────────────────────
configurar_backup() {
  step "11" "CONFIGURAÇÃO DE BACKUP AUTOMÁTICO"

  substep "Criando script de backup..."

  cat > "${INSTALL_DIR}/scripts/backup.sh" << 'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/ad-license-manager"
BACKUP_DIR="${INSTALL_DIR}/backups/$(date +%Y-%m-%d)"
LOG="${INSTALL_DIR}/logs/backup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') — Iniciando backup..." | tee -a "$LOG"

mkdir -p "$BACKUP_DIR"

# Dump do PostgreSQL
docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T postgres \
  pg_dump -U admanager admanager \
  --format=custom \
  --compress=9 \
  > "${BACKUP_DIR}/database.dump"
echo "$(date '+%Y-%m-%d %H:%M:%S') — Banco de dados: OK" | tee -a "$LOG"

# Backup das configurações
cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"
echo "$(date '+%Y-%m-%d %H:%M:%S') — Configurações: OK" | tee -a "$LOG"

# Comprime os logs do dia
if [ -d "${INSTALL_DIR}/logs" ]; then
  tar -czf "${BACKUP_DIR}/logs.tar.gz" \
    -C "${INSTALL_DIR}" logs/ \
    2>/dev/null || true
  echo "$(date '+%Y-%m-%d %H:%M:%S') — Logs: OK" | tee -a "$LOG"
fi

# Remove backups com mais de 30 dias
find "${INSTALL_DIR}/backups" -maxdepth 1 -type d -mtime +30 \
  -exec rm -rf {} + 2>/dev/null || true

TAMANHO=$(du -sh "$BACKUP_DIR" | cut -f1)
echo "$(date '+%Y-%m-%d %H:%M:%S') — Backup concluído. Tamanho: ${TAMANHO} → ${BACKUP_DIR}" \
  | tee -a "$LOG"
BACKUP_SCRIPT

  chmod +x "${INSTALL_DIR}/scripts/backup.sh"
  chown admanager:admanager "${INSTALL_DIR}/scripts/backup.sh"
  ok "Script de backup criado"

  # Agendamento no cron
  substep "Agendando backup automático (diariamente às 03:00)..."
  cat > /etc/cron.d/admanager-backup << EOF
# Backup diario do AD License Manager
0 3 * * * admanager ${INSTALL_DIR}/scripts/backup.sh >> ${INSTALL_DIR}/logs/backup.log 2>&1
EOF
  ok "Backup automático agendado para 03:00 diariamente"

  # Script de health check
  substep "Criando script de health check..."
  cat > "${INSTALL_DIR}/scripts/health-check.sh" << HEALTH_SCRIPT
#!/usr/bin/env bash
source "${INSTALL_DIR}/.env" 2>/dev/null || true
FALHAS=0
check() {
  local nome=\$1 cmd=\$2 esperado=\$3
  if eval "\$cmd" 2>&1 | grep -q "\$esperado"; then
    echo "  ✓  \${nome}"
  else
    echo "  ✗  \${nome}"
    FALHAS=\$((FALHAS+1))
  fi
}
echo ""
echo "  ── Health Check AD License Manager — \$(date '+%d/%m/%Y %H:%M')"
echo ""
check "PostgreSQL" \
  "docker compose -f ${INSTALL_DIR}/docker-compose.yml exec -T postgres pg_isready -U admanager" \
  "accepting"
check "Redis" \
  "docker compose -f ${INSTALL_DIR}/docker-compose.yml exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping" \
  "PONG"
check "Backend API" \
  "curl -sf http://localhost:3001/health" \
  "healthy"
check "Nginx HTTPS" \
  "curl -skf https://localhost/health" \
  "healthy"
check "Worker" \
  "docker compose -f ${INSTALL_DIR}/docker-compose.yml ps worker" \
  "running"
echo ""
if [ \$FALHAS -gt 0 ]; then
  echo "  ✗  \${FALHAS} serviço(s) com problema."
  echo "     Execute: docker compose logs"
  exit 1
else
  echo "  ✓  Todos os serviços saudáveis."
fi
echo ""
HEALTH_SCRIPT

  chmod +x "${INSTALL_DIR}/scripts/health-check.sh"
  chown admanager:admanager "${INSTALL_DIR}/scripts/health-check.sh"
  ok "Script de health check criado"

  # Script de atualização
  substep "Criando script de atualização..."
  cat > "${INSTALL_DIR}/scripts/update.sh" << UPDATE_SCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "Criando backup antes de atualizar..."
${INSTALL_DIR}/scripts/backup.sh
echo "Baixando atualizações..."
cd "${INSTALL_DIR}"
git pull origin main
echo "Reconstruindo imagens..."
docker compose build --no-cache
echo "Aplicando migrations..."
docker compose run --rm backend node dist/migrate.js
echo "Reiniciando serviços..."
docker compose up -d --remove-orphans
echo "Atualização concluída."
docker compose ps
UPDATE_SCRIPT

  chmod +x "${INSTALL_DIR}/scripts/update.sh"
  chown admanager:admanager "${INSTALL_DIR}/scripts/update.sh"
  ok "Script de atualização criado"
}

# ─── ETAPA 12: Permissões finais ──────────────────────────────────────────────
ajustar_permissoes() {
  step "12" "AJUSTE FINAL DE PERMISSÕES"

  substep "Aplicando permissões na instalação completa..."
  chown -R admanager:admanager "${INSTALL_DIR}"
  chmod 600 "${INSTALL_DIR}/.env"
  chmod 600 "${INSTALL_DIR}/infra/nginx/ssl/key.pem"
  chmod 644 "${INSTALL_DIR}/infra/nginx/ssl/cert.pem"
  chmod 700 "${INSTALL_DIR}/logs"
  chmod 700 "${INSTALL_DIR}/backups"
  chmod +x  "${INSTALL_DIR}/scripts/"*.sh
  ok "Permissões aplicadas"
}

# ─── ETAPA 13: Verificação final ──────────────────────────────────────────────
verificacao_final() {
  step "13" "VERIFICAÇÃO FINAL DO SISTEMA"

  cd "${INSTALL_DIR}"

  echo ""
  substep "Status dos containers:"
  echo ""
  docker compose ps 2>/dev/null | while read -r linha; do
    echo "    ${linha}"
  done
  echo ""

  # Health check
  substep "Executando health check completo..."
  echo ""
  bash "${INSTALL_DIR}/scripts/health-check.sh" || true
  echo ""

  # Verifica o certificado TLS
  substep "Verificando certificado TLS..."
  CERT_INFO=$(openssl x509 -in "${INSTALL_DIR}/infra/nginx/ssl/cert.pem" \
    -noout -subject -dates 2>/dev/null || echo "erro")
  if echo "$CERT_INFO" | grep -q "notAfter"; then
    EXPIRA=$(echo "$CERT_INFO" | grep notAfter | cut -d= -f2)
    ok "Certificado TLS válido — expira em: ${EXPIRA}"
  else
    warn "Não foi possível verificar o certificado TLS"
  fi

  # Verifica a conectividade final
  progress "Testando endpoint de saúde via HTTPS"
  sleep 3
  if curl -skf https://localhost/health &>/dev/null; then
    progress_ok
  else
    progress_fail
    warn "O endpoint HTTPS ainda não está respondendo."
    warn "Aguarde alguns segundos e verifique: docker compose logs nginx"
  fi
}

# ─── ETAPA 14: Resumo e instruções finais ─────────────────────────────────────
exibir_resumo_final() {
  INSTALL_END=$(date +%s)
  DURACAO=$(( (INSTALL_END - INSTALL_START) / 60 ))

  banner

  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║                                                                  ║"
  echo "  ║           ✓  INSTALAÇÃO CONCLUÍDA COM SUCESSO!                  ║"
  echo "  ║                                                                  ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Tempo total: ${DURACAO} minutos${NC}"
  echo ""

  divisor
  echo -e "  ${WHITE}${BOLD}ACESSO AO SISTEMA${NC}"
  divisor
  echo ""
  echo -e "  ${CYAN}URL:${NC}      ${WHITE}${BOLD}${APP_URL}${NC}"
  echo -e "  ${CYAN}Usuário:${NC}  ${WHITE}${BOLD}${ADMIN_

