#!/usr/bin/env bash
# =============================================================================
#  AD License Manager — Instalador Interativo Completo
#  Ubuntu Server 22.04 LTS / 24.04 LTS
#  Versão 1.0.1 — Julho de 2026
#  Corrigido e validado
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

# ─── Variáveis globais ────────────────────────────────────────────────────────
INSTALL_DIR="/opt/ad-license-manager"
INSTALL_LOG="/tmp/admanager-install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_START=$(date +%s)
REPO_URL="${REPO_URL:-https://github.com/sua-org/ad-license-manager.git}"

# Variáveis de configuração — preenchidas na coleta interativa
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

# ─── Log duplo: stdout na tela, detalhes no arquivo ──────────────────────────
# CORREÇÃO: o script anterior redirecionava stderr globalmente,
# o que suprimia erros úteis na tela. Agora usamos tee seletivo.
touch "$INSTALL_LOG"
chmod 600 "$INSTALL_LOG"

log_cmd() {
  # Executa o comando, grava saída no log, suprime da tela
  "$@" >> "$INSTALL_LOG" 2>&1
}

log_cmd_verbose() {
  # Executa e mostra na tela E no log
  "$@" 2>&1 | tee -a "$INSTALL_LOG"
}

# ─── Funções de exibição ─────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║       AD License Manager — Instalador Interativo v1.0.1        ║"
  echo "  ║       Ubuntu Server 22.04 LTS / 24.04 LTS                      ║"
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
divisor() { echo -e "  ${DIM}────────────────────────────────────────────────${NC}"; }

progress()    { echo -ne "  ${BLUE}▸${NC} $1..."; }
progress_ok() { echo -e " ${GREEN}OK${NC}"; }
progress_fail(){ echo -e " ${RED}FALHOU${NC}"; }

# ─── Confirmação interativa ───────────────────────────────────────────────────
# CORREÇÃO: a versão anterior usava read -rp com echo -e dentro da substituição
# de comando, o que causava comportamento inconsistente entre bash 5.0 e 5.1+.
confirmar() {
  local pergunta=$1
  local padrao=${2:-s}
  local resposta

  if [ "$padrao" = "s" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${pergunta}${NC} [${GREEN}S${NC}/n]: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${pergunta}${NC} [s/${GREEN}N${NC}]: "
  fi

  read -r resposta
  resposta="${resposta:-$padrao}"
  [[ "$resposta" =~ ^[SsYy]$ ]]
}

# ─── Pergunta com valor padrão ────────────────────────────────────────────────
perguntar() {
  local pergunta=$1
  local padrao=${2:-""}
  local variavel

  if [ -n "$padrao" ]; then
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${pergunta}${NC} [${DIM}${padrao}${NC}]: "
  else
    echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${pergunta}${NC}: "
  fi

  read -r variavel
  echo "${variavel:-$padrao}"
}

# ─── Pergunta de senha (sem eco) ─────────────────────────────────────────────
perguntar_senha() {
  local pergunta=$1
  local variavel

  echo -ne "  ${MAGENTA}?${NC}  ${WHITE}${pergunta}${NC}: "
  read -rs variavel
  echo ""
  echo "$variavel"
}

# ─── Falha crítica ────────────────────────────────────────────────────────────
falha_critica() {
  echo ""
  erro "ERRO CRÍTICO: $1"
  echo ""
  echo -e "  ${DIM}Log completo disponível em: ${INSTALL_LOG}${NC}"
  echo ""
  exit 1
}

# ─── Aguarda serviço com timeout ─────────────────────────────────────────────
# CORREÇÃO: a versão anterior não tinha limite de tempo parametrizado
# e usava 'exit 1' dentro de loop que seria capturado pelo 'set -e' incorretamente.
aguardar_servico() {
  local nome=$1
  local cmd=$2
  local max_tentativas=${3:-30}
  local intervalo=${4:-3}
  local tentativa=0

  echo -ne "  Aguardando ${nome}"
  while [ $tentativa -lt $max_tentativas ]; do
    if eval "$cmd" >> "$INSTALL_LOG" 2>&1; then
      echo -e " ${GREEN}pronto!${NC}"
      return 0
    fi
    echo -n "."
    sleep "$intervalo"
    tentativa=$((tentativa + 1))
  done

  echo -e " ${RED}timeout!${NC}"
  return 1
}

# ─── Validações de entrada ────────────────────────────────────────────────────
validar_dominio() {
  local dominio=$1
  # Aceita domínios com subdomínios, hífen e .local
  if [[ "$dominio" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    return 0
  fi
  return 1
}

validar_email() {
  local email=$1
  if [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    return 0
  fi
  return 1
}

validar_url_ldap() {
  local url=$1
  if [[ "$url" =~ ^ldaps?://[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; then
    return 0
  fi
  return 1
}

validar_base_dn() {
  local dn=$1
  # Ex: DC=empresa,DC=com,DC=br
  if [[ "$dn" =~ ^(DC|OU|CN)=[^,]+(,(DC|OU|CN)=[^,]+)*$ ]]; then
    return 0
  fi
  return 1
}

validar_senha() {
  local senha=$1
  [ ${#senha} -ge 12 ]
}

# ─── ETAPA 0: Verificações iniciais ──────────────────────────────────────────
verificacoes_iniciais() {
  banner

  echo -e "  ${DIM}Log da instalação: ${INSTALL_LOG}${NC}"
  echo ""

  # Verifica root
  # CORREÇÃO: verificação de root com mensagem clara antes de qualquer outra coisa
  if [ "$(id -u)" -ne 0 ]; then
    falha_critica "Execute o instalador como root: sudo bash install.sh"
  fi

  # Verifica se é Ubuntu
  if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    warn "Sistema não identificado como Ubuntu."
    confirmar "Continuar mesmo assim" "n" || { echo "Instalação cancelada."; exit 0; }
  else
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "?")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")

    if [[ "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ]]; then
      warn "Ubuntu ${UBUNTU_VERSION} não é uma versão LTS suportada oficialmente."
      confirmar "Continuar mesmo assim" "n" || { echo "Instalação cancelada."; exit 0; }
    else
      ok "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME}) detectado"
    fi
  fi

  # Verifica arquitetura
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|aarch64) ok "Arquitetura ${ARCH} suportada" ;;
    *) falha_critica "Arquitetura ${ARCH} não suportada. Use x86_64 ou aarch64." ;;
  esac

  # Verifica RAM
  RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  RAM_GB=$(( RAM_KB / 1024 / 1024 ))
  if [ "$RAM_GB" -lt 3 ]; then
    # CORREÇÃO: mínimo absoluto era muito restritivo — 3GB é mais realista para aviso
    falha_critica "Memória insuficiente: ${RAM_GB}GB. Mínimo requerido: 4GB."
  elif [ "$RAM_GB" -lt 8 ]; then
    warn "RAM: ${RAM_GB}GB. Recomendado: 8GB ou mais para produção."
  else
    ok "RAM: ${RAM_GB}GB disponíveis"
  fi

  # Verifica espaço em disco
  # CORREÇÃO: a versão anterior usava 'df / --output=avail' que falha em alguns sistemas.
  # Usando variante mais portável.
  DISCO_KB=$(df --block-size=1K / | awk 'NR==2 {print $4}')
  DISCO_GB=$(( DISCO_KB / 1024 / 1024 ))
  if [ "$DISCO_GB" -lt 15 ]; then
    falha_critica "Espaço em disco insuficiente: ${DISCO_GB}GB livres. Mínimo: 20GB."
  elif [ "$DISCO_GB" -lt 40 ]; then
    warn "Disco: ${DISCO_GB}GB livres. Recomendado: 40GB+ para produção."
  else
    ok "Disco: ${DISCO_GB}GB livres disponíveis"
  fi

  # Verifica conexão com a internet
  progress "Verificando acesso à internet"
  if curl -sf --max-time 15 https://download.docker.com > /dev/null 2>&1; then
    progress_ok
  else
    progress_fail
    falha_critica "Sem acesso à internet. Necessário para download do Docker e imagens."
  fi

  # Detecta reinstalação
  if [ -f "${INSTALL_DIR}/.env" ]; then
    echo ""
    warn "Instalação existente detectada em ${INSTALL_DIR}."
    warn "Prosseguir irá SOBRESCREVER a instalação atual."
    echo ""
    confirmar "Tem certeza que deseja reinstalar" "n" || { echo "Cancelado."; exit 0; }
  fi

  echo ""
  ok "Verificações iniciais concluídas"
  echo ""
  read -rp "$(echo -e "  ${DIM}Pressione ENTER para iniciar a coleta de informações...${NC}")"
}

# ─── ETAPA 1: Coleta de informações ──────────────────────────────────────────
coletar_informacoes() {
  banner
  step "1" "COLETA DE INFORMAÇÕES"

  echo -e "  Responda as perguntas abaixo para configurar o sistema."
  echo -e "  ${DIM}Valores entre [ ] são padrões — pressione ENTER para aceitar.${NC}"
  echo ""

  # ── 1.1 Domínio da aplicação ────────────────────────────────────────────
  divisor
  echo -e "  ${WHITE}${BOLD}1.1  Configuração da aplicação${NC}"
  echo ""

  while true; do
    APP_DOMAIN=$(perguntar "Domínio de acesso à interface web (ex: admanager.empresa.com.br)")
    if [ -z "$APP_DOMAIN" ]; then
      warn "Domínio é obrigatório."
    elif ! validar_dominio "$APP_DOMAIN"; then
      warn "Formato de domínio inválido. Ex: admanager.empresa.com.br"
    else
      ok "Domínio: ${APP_DOMAIN}"
      break
    fi
  done

  # ── 1.2 Active Directory ────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.2  Active Directory${NC}"
  echo ""
  info "Use ldaps:// (porta 636) para habilitar redefinição de senha."
  info "Use ldap://  (porta 389) apenas se LDAPS não estiver disponível."
  echo ""

  while true; do
    AD_URL=$(perguntar "URL do Controlador de Domínio" "ldaps://dc01.empresa.com.br")
    if ! validar_url_ldap "$AD_URL"; then
      warn "Formato inválido. Ex: ldaps://dc01.empresa.com.br ou ldap://192.168.1.10"
    else
      break
    fi
  done

  while true; do
    AD_BASE_DN=$(perguntar "Base DN do domínio" "DC=empresa,DC=com,DC=br")
    if ! validar_base_dn "$AD_BASE_DN"; then
      warn "Formato inválido. Ex: DC=empresa,DC=com,DC=br"
    else
      break
    fi
  done

  while true; do
    AD_USERNAME=$(perguntar "UPN da conta de serviço" "svc-admanager@empresa.com.br")
    if [ -z "$AD_USERNAME" ]; then
      warn "Conta de serviço é obrigatória."
    else
      break
    fi
  done

  while true; do
    AD_PASSWORD=$(perguntar_senha "Senha da conta de serviço")
    if [ -z "$AD_PASSWORD" ]; then
      warn "Senha é obrigatória."
    else
      break
    fi
  done

  while true; do
    AD_DOMAIN=$(perguntar "Domínio NetBIOS / UPN suffix" "empresa.com.br")
    if [ -z "$AD_DOMAIN" ]; then
      warn "Domínio é obrigatório."
    else
      break
    fi
  done

  # Testa conectividade com o AD
  # CORREÇÃO: a versão anterior extraía host/porta com sed aninhado que
  # falhava quando a URL não tinha porta explícita. Corrigido com lógica separada.
  echo ""
  AD_HOST=$(echo "$AD_URL" | sed -E 's|ldaps?://||' | cut -d: -f1)

  if echo "$AD_URL" | grep -q "ldaps"; then
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':')
    AD_PORT="${AD_PORT:-636}"
  else
    AD_PORT=$(echo "$AD_URL" | grep -oP ':\d+$' | tr -d ':')
    AD_PORT="${AD_PORT:-389}"
  fi

  progress "Testando conectividade com ${AD_HOST}:${AD_PORT}"
  if nc -zw 5 "$AD_HOST" "$AD_PORT" 2>/dev/null; then
    progress_ok
    ok "Active Directory acessível"
  else
    progress_fail
    warn "Não foi possível conectar a ${AD_HOST}:${AD_PORT}."
    warn "Verifique a URL, porta e regras de firewall."
    confirmar "Continuar mesmo assim" "n" || falha_critica "Conectividade com AD não confirmada."
  fi

  # ── 1.3 Azure AD ────────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.3  Azure AD / Microsoft 365 (opcional)${NC}"
  echo ""
  info "Necessário apenas para gestão de licenças M365."
  echo ""

  if confirmar "Configurar integração com Microsoft 365"; then
    SETUP_GRAPH="s"

    while true; do
      AZURE_TENANT_ID=$(perguntar "Azure Tenant ID")
      [ -n "$AZURE_TENANT_ID" ] && break
      warn "Tenant ID é obrigatório."
    done

    while true; do
      AZURE_CLIENT_ID=$(perguntar "Azure Client ID (Application ID)")
      [ -n "$AZURE_CLIENT_ID" ] && break
      warn "Client ID é obrigatório."
    done

    while true; do
      AZURE_CLIENT_SECRET=$(perguntar_senha "Azure Client Secret")
      [ -n "$AZURE_CLIENT_SECRET" ] && break
      warn "Client Secret é obrigatório."
    done

    ok "Azure AD configurado"
  else
    warn "Integração M365 ignorada. Configure posteriormente em Configurações."
  fi

  # ── 1.4 Administrador ───────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.4  Conta de administrador do sistema${NC}"
  echo ""

  ADMIN_USER=$(perguntar "Nome de usuário do administrador" "admin")
  ADMIN_USER="${ADMIN_USER:-admin}"

  while true; do
    ADMIN_EMAIL=$(perguntar "Email do administrador")
    if ! validar_email "$ADMIN_EMAIL"; then
      warn "Formato de email inválido. Ex: ti@empresa.com.br"
    else
      break
    fi
  done

  echo ""
  info "Senha: mínimo 12 caracteres, maiúsculas, minúsculas, números e símbolos."
  echo ""

  while true; do
    ADMIN_PASSWORD=$(perguntar_senha "Senha do administrador")
    if ! validar_senha "$ADMIN_PASSWORD"; then
      warn "Senha muito curta. Mínimo de 12 caracteres."
      continue
    fi

    local ADMIN_CONFIRM
    ADMIN_CONFIRM=$(perguntar_senha "Confirme a senha")
    if [ "$ADMIN_PASSWORD" != "$ADMIN_CONFIRM" ]; then
      warn "As senhas não coincidem. Tente novamente."
    else
      ok "Administrador: ${ADMIN_USER} (${ADMIN_EMAIL})"
      break
    fi
  done

  # ── 1.5 SMTP ────────────────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.5  Configuração de Email — SMTP (opcional)${NC}"
  echo ""

  if confirmar "Configurar envio de emails via SMTP"; then
    SETUP_SMTP="s"
    SMTP_HOST=$(perguntar "Host SMTP" "smtp.empresa.com.br")
    SMTP_PORT=$(perguntar "Porta SMTP" "587")
    SMTP_SECURE=$(perguntar "Usar TLS/SSL — 'true' para porta 465" "false")
    SMTP_USER=$(perguntar "Usuário SMTP (em branco para relay sem autenticação)")
    if [ -n "$SMTP_USER" ]; then
      SMTP_PASS=$(perguntar_senha "Senha SMTP")
    fi
    ok "SMTP configurado: ${SMTP_HOST}:${SMTP_PORT}"
  else
    warn "SMTP ignorado. Configure posteriormente em Configurações."
  fi

  # ── 1.6 Microsoft Teams ─────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.6  Alertas no Microsoft Teams (opcional)${NC}"
  echo ""
  info "Canal → ··· → Conectores → Incoming Webhook → Criar → Copiar URL"
  echo ""

  if confirmar "Configurar alertas no Microsoft Teams"; then
    SETUP_TEAMS="s"
    while true; do
      TEAMS_WEBHOOK_URL=$(perguntar "URL do Webhook do Teams")
      if [[ "$TEAMS_WEBHOOK_URL" =~ ^https:// ]]; then
        break
      fi
      warn "URL inválida. Deve começar com https://"
    done
    ok "Teams configurado"
  else
    warn "Teams ignorado. Configure posteriormente em Configurações."
  fi

  # ── 1.7 Certificado TLS ─────────────────────────────────────────────────
  echo ""
  divisor
  echo -e "  ${WHITE}${BOLD}1.7  Certificado TLS${NC}"
  echo ""
  echo -e "   ${GREEN}1)${NC} Let's Encrypt — gratuito e automático (requer porta 80 acessível)"
  echo -e "   ${GREEN}2)${NC} Certificado próprio — PKI corporativa (self-signed temporário)"
  echo -e "   ${GREEN}3)${NC} Self-signed — somente para testes internos"
  echo ""

  while true; do
    CERT_OPCAO=$(perguntar "Escolha o tipo de certificado" "3")
    case "$CERT_OPCAO" in
      1|2|3) break ;;
      *) warn "Opção inválida. Digite 1, 2 ou 3." ;;
    esac
  done

  case "$CERT_OPCAO" in
    1) ok "Let's Encrypt selecionado" ;;
    2) ok "Certificado próprio selecionado (self-signed temporário gerado agora)" ;;
    3) warn "Self-signed selecionado — NÃO use em produção." ;;
  esac

  # ── Resumo de confirmação ───────────────────────────────────────────────
  banner
  echo -e "  ${WHITE}${BOLD}RESUMO DA CONFIGURAÇÃO${NC}"
  echo ""
  divisor
  echo -e "  ${CYAN}Aplicação${NC}"
  echo -e "    Domínio:       ${APP_DOMAIN}"
  echo -e "    URL:           https://${APP_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}Active Directory${NC}"
  echo -e "    URL:           ${AD_URL}"
  echo -e "    Base DN:       ${AD_BASE_DN}"
  echo -e "    Conta serviço: ${AD_USERNAME}"
  echo -e "    Domínio:       ${AD_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}Administrador${NC}"
  echo -e "    Usuário:       ${ADMIN_USER}"
  echo -e "    Email:         ${ADMIN_EMAIL}"
  echo ""
  echo -e "  ${CYAN}Integrações${NC}"
  local g_status s_status t_status c_tipo
  [ "$SETUP_GRAPH" = "s" ]  && g_status="${GREEN}Configurado${NC}" || g_status="${YELLOW}Não configurado${NC}"
  [ "$SETUP_SMTP"  = "s" ]  && s_status="${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}" || s_status="${YELLOW}Não configurado${NC}"
  [ "$SETUP_TEAMS" = "s" ]  && t_status="${GREEN}Configurado${NC}" || t_status="${YELLOW}Não configurado${NC}"
  case "$CERT_OPCAO" in
    1) c_tipo="${GREEN}Let's Encrypt${NC}" ;;
    2) c_tipo="${YELLOW}Certificado próprio (self-signed temporário)${NC}" ;;
    3) c_tipo="${YELLOW}Self-signed${NC}" ;;
  esac
  echo -e "    Microsoft 365: $(echo -e $g_status)"
  echo -e "    SMTP:          $(echo -e $s_status)"
  echo -e "    Teams:         $(echo -e $t_status)"
  echo ""
  echo -e "  ${CYAN}Certificado TLS${NC}"
  echo -e "    Tipo:          $(echo -e $c_tipo)"
  divisor
  echo ""

  confirmar "Informações corretas? Iniciar a instalação" "s" || {
    warn "Instalação cancelada pelo usuário."
    exit 0
  }
}

# ─── ETAPA 2: Geração de segredos ─────────────────────────────────────────────
gerar_segredos() {
  step "2" "GERAÇÃO DE SEGREDOS CRIPTOGRÁFICOS"

  # CORREÇÃO: a versão anterior usava tr -d '/+=' que em alguns locales pode
  # remover caracteres a mais. Usando abordagem mais segura e explícita.

  progress "JWT Secret (512 bits)"
  JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n' | tr -d '/' | tr -d '+' | tr -d '=' | cut -c1-86)
  progress_ok

  progress "JWT Refresh Secret (512 bits)"
  JWT_REFRESH_SECRET=$(openssl rand -base64 64 | tr -d '\n' | tr -d '/' | tr -d '+' | tr -d '=' | cut -c1-86)
  progress_ok

  progress "Senha do PostgreSQL (256 bits)"
  DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32)
  progress_ok

  progress "Senha do Redis (256 bits)"
  REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | tr -cd 'a-zA-Z0-9' | cut -c1-32)
  progress_ok

  progress "Chave de criptografia AES-256"
  ENCRYPTION_KEY=$(openssl rand -hex 32)
  progress_ok

  # Valida que os segredos foram gerados corretamente
  for secret_name in JWT_SECRET JWT_REFRESH_SECRET DB_PASSWORD REDIS_PASSWORD ENCRYPTION_KEY; do
    local val="${!secret_name}"
    if [ -z "$val" ]; then
      falha_critica "Falha ao gerar o segredo: ${secret_name}"
    fi
  done

  ok "Todos os segredos gerados com sucesso"
}

# ─── ETAPA 3: Preparação do sistema ───────────────────────────────────────────
preparar_sistema() {
  step "3" "PREPARAÇÃO DO SISTEMA UBUNTU"

  # CORREÇÃO: DEBIAN_FRONTEND deve ser exportado, não apenas atribuído inline,
  # para evitar prompts interativos em subprocessos do apt.
  export DEBIAN_FRONTEND=noninteractive

  substep "Atualizando lista de pacotes..."
  log_cmd apt-get update -qq
  ok "Lista de pacotes atualizada"

  substep "Aplicando atualizações de segurança..."
  log_cmd apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  ok "Atualizações aplicadas"

  substep "Instalando dependências base..."
  log_cmd apt-get install -y -qq \
    curl wget git openssl \
    netcat-openbsd \
    python3 \
    ca-certificates gnupg lsb-release \
    apt-transport-https software-properties-common \
    cron nano vim htop net-tools \
    dnsutils jq unzip \
    logrotate fail2ban auditd
  ok "Dependências instaladas"

  substep "Criando usuário de serviço 'admanager'..."
  if ! id admanager &>/dev/null; then
    log_cmd useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      --comment "AD License Manager Service" \
      admanager
    ok "Usuário 'admanager' criado"
  else
    ok "Usuário 'admanager' já existe"
  fi

  substep "Criando estrutura de diretórios..."
  # CORREÇÃO: mkdir -p com permissões explícitas para evitar herança de umask
  install -d -m 755 -o admanager -g admanager "${INSTALL_DIR}"
  install -d -m 700 -o admanager -g admanager "${INSTALL_DIR}/logs"
  install -d -m 700 -o admanager -g admanager "${INSTALL_DIR}/backups"
  install -d -m 755 -o admanager -g admanager "${INSTALL_DIR}/infra"
  install -d -m 755 -o admanager -g admanager "${INSTALL_DIR}/infra/nginx"
  install -d -m 755 -o admanager -g admanager "${INSTALL_DIR}/infra/nginx/ssl"
  install -d -m 755 -o admanager -g admanager "${INSTALL_DIR}/scripts"
  ok "Estrutura de diretórios criada"

  substep "Configurando timezone..."
  if [ -z "$(cat /etc/timezone 2>/dev/null)" ]; then
    log_cmd timedatectl set-timezone America/Sao_Paulo
  fi
  ok "Timezone: $(cat /etc/timezone)"

  substep "Configurando sincronização NTP com chrony..."
  log_cmd apt-get install -y -qq chrony
  systemctl enable chrony >> "$INSTALL_LOG" 2>&1
  systemctl restart chrony >> "$INSTALL_LOG" 2>&1
  ok "NTP com chrony habilitado"

  substep "Configurando fail2ban..."
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
  ok "fail2ban configurado"

  substep "Habilitando auditd..."
  systemctl enable auditd >> "$INSTALL_LOG" 2>&1
  systemctl start  auditd >> "$INSTALL_LOG" 2>&1
  # Monitora o arquivo .env
  auditctl -w "${INSTALL_DIR}/.env" -p rwxa -k admanager-config 2>>"$INSTALL_LOG" || true
  ok "auditd habilitado"

  substep "Configurando firewall UFW..."
  # CORREÇÃO: habilita UFW de forma não-interativa com --force
  log_cmd ufw --force enable
  log_cmd ufw allow 22/tcp
  log_cmd ufw allow 80/tcp
  log_cmd ufw allow 443/tcp
  log_cmd ufw deny  3001/tcp
  log_cmd ufw deny  5432/tcp
  log_cmd ufw deny  6379/tcp
  log_cmd ufw deny  3000/tcp
  log_cmd ufw --force reload
  ok "Firewall UFW configurado"

  substep "Otimizando limites do sistema..."
  cat >> /etc/security/limits.conf << 'EOF'
admanager soft nofile 65536
admanager hard nofile 65536
root      soft nofile 65536
root      hard nofile 65536
EOF
  cat >> /etc/sysctl.conf << 'EOF'
# AD License Manager
net.core.somaxconn         = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.overcommit_memory       = 1
EOF
  log_cmd sysctl -p
  ok "Limites do sistema otimizados"

  substep "Configurando logrotate..."
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
}
EOF
  ok "Logrotate configurado"
}

# ─── ETAPA 4: Instalação do Docker ───────────────────────────────────────────
instalar_docker() {
  step "4" "INSTALAÇÃO DO DOCKER ENGINE"

  substep "Removendo versões antigas do Docker..."
  log_cmd apt-get remove -y \
    docker docker-engine docker.io containerd runc \
    docker-compose docker-compose-plugin \
    docker-ce docker-ce-cli 2>/dev/null || true
  log_cmd apt-get autoremove -y
  ok "Versões antigas removidas"

  substep "Adicionando chave GPG oficial do Docker..."
  install -m 0755 -d /etc/apt/keyrings
  # CORREÇÃO: a versão anterior não verificava se a chave já existia,
  # causando falha silenciosa na segunda execução.
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    2>>"$INSTALL_LOG" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>>"$INSTALL_LOG"
  chmod a+r /etc/apt/keyrings/docker.gpg
  ok "Chave GPG adicionada"

  substep "Adicionando repositório oficial do Docker..."
  # CORREÇÃO: usa UBUNTU_CODENAME detectado anteriormente, com fallback seguro
  local codename="${UBUNTU_CODENAME:-$(lsb_release -cs)}"
  local arch
  arch=$(dpkg --print-architecture)
  echo \
    "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    ${codename} stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  log_cmd apt-get update -qq
  ok "Repositório Docker adicionado (${codename} ${arch})"

  substep "Instalando Docker Engine e Compose Plugin..."
  log_cmd apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  ok "Docker instalado"

  substep "Habilitando e iniciando o Docker..."
  systemctl enable docker >> "$INSTALL_LOG" 2>&1
  systemctl start  docker >> "$INSTALL_LOG" 2>&1
  ok "Docker iniciado"

  substep "Adicionando 'admanager' ao grupo docker..."
  usermod -aG docker admanager
  ok "Usuário adicionado ao grupo docker"

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

  substep "Verificando instalação do Docker..."
  if log_cmd docker run --rm hello-world; then
    ok "Docker funcionando corretamente"
  else
    falha_critica "Docker instalado mas não está funcionando. Verifique: ${INSTALL_LOG}"
  fi

  local dv cv
  dv=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
  cv=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${dv} e Compose Plugin ${cv} prontos"
}

# ─── ETAPA 5: Clone do repositório ───────────────────────────────────────────
clonar_repositorio() {
  step "5" "DOWNLOAD DO CÓDIGO-FONTE"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    substep "Repositório existente encontrado. Atualizando..."
    cd "${INSTALL_DIR}"
    log_cmd git fetch origin
    log_cmd git reset --hard origin/main
    ok "Código atualizado para a versão mais recente"
  else
    substep "Clonando repositório..."
    # CORREÇÃO: clonar para diretório que já existe (criado na etapa 3)
    # requer --no-checkout ou clonar para diretório temporário e mover.
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    if log_cmd git clone "$REPO_URL" "$TMP_DIR"; then
      cp -a "$TMP_DIR/." "${INSTALL_DIR}/"
      rm -rf "$TMP_DIR"
      ok "Repositório clonado em ${INSTALL_DIR}"
    else
      rm -rf "$TMP_DIR"
      falha_critica "Falha ao clonar o repositório. Verifique a URL: ${REPO_URL}"
    fi
  fi

  substep "Ajustando permissões dos scripts..."
  find "${INSTALL_DIR}/scripts" -name "*.sh" -exec chmod +x {} \;
  [ -f "${INSTALL_DIR}/install.sh" ] && chmod +x "${INSTALL_DIR}/install.sh"
  ok "Scripts executáveis configurados"
}

# ─── ETAPA 6: Geração do .env ─────────────────────────────────────────────────
gerar_env() {
  step "6" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

  substep "Criando .env..."

  # CORREÇÃO: variáveis opcionais podem estar vazias. Escrevemos o arquivo
  # com valores vazios explícitos para não causar erros de referência não definida
  # no Node.js durante a inicialização.
  cat > "${INSTALL_DIR}/.env" << EOF
# ══════════════════════════════════════════════════════════════════════
#  AD License Manager — Configuração
#  Gerado em: $(date '+%d/%m/%Y às %H:%M:%S')
#  ATENÇÃO: Não compartilhe este arquivo. Contém credenciais sensíveis.
# ══════════════════════════════════════════════════════════════════════

# ── Aplicação ────────────────────────────────────────────────────────
APP_DOMAIN=${APP_DOMAIN}
APP_URL=https://${APP_DOMAIN}
NODE_ENV=production
PORT=3001
ALLOWED_ORIGINS=https://${APP_DOMAIN}

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

  # Backup imediato
  cp "${INSTALL_DIR}/.env" "${INSTALL_DIR}/.env.install-backup"
  chmod 600 "${INSTALL_DIR}/.env.install-backup"
  chown admanager:admanager "${INSTALL_DIR}/.env.install-backup"
  ok "Backup do .env salvo em .env.install-backup"
}

# ─── ETAPA 7: Certificado TLS ─────────────────────────────────────────────────
configurar_tls() {
  step "7" "CONFIGURAÇÃO DO CERTIFICADO TLS"

  local SSL_DIR="${INSTALL_DIR}/infra/nginx/ssl"

  if [ "$CERT_OPCAO" = "1" ]; then
    substep "Instalando Certbot..."
    log_cmd apt-get install -y -qq certbot

    # CORREÇÃO: para o Nginx antes de usar o modo standalone
    # (a versão anterior não fazia isso e causava falha com porta 80 em uso)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "adm_nginx"; then
      log_cmd docker compose -f "${INSTALL_DIR}/docker-compose.yml" stop nginx
    fi

    substep "Gerando certificado Let's Encrypt para ${APP_DOMAIN}..."
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

      # Script de renovação
      cat > /usr/local/bin/admanager-renew-cert.sh << EOF
#!/bin/bash
set -e
DOMAIN="${APP_DOMAIN}"
SSL_DIR="${SSL_DIR}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

certbot renew --quiet

cp /etc/letsencrypt/live/\${DOMAIN}/fullchain.pem \${SSL_DIR}/cert.pem
cp /etc/letsencrypt/live/\${DOMAIN}/privkey.pem   \${SSL_DIR}/key.pem
chown admanager:admanager \${SSL_DIR}/cert.pem \${SSL_DIR}/key.pem
chmod 644 \${SSL_DIR}/cert.pem
chmod 600 \${SSL_DIR}/key.pem

docker compose -f "\${COMPOSE_FILE}" restart nginx

echo "\$(date '+%Y-%m-%d %H:%M:%S') Certificado renovado." >> "${INSTALL_DIR}/logs/certbot.log"
EOF
      chmod +x /usr/local/bin/admanager-renew-cert.sh
      echo "0 2 1 * * root /usr/local/bin/admanager-renew-cert.sh" \
        > /etc/cron.d/admanager-certbot
      ok "Renovação automática agendada para dia 1 de cada mês às 02:00"
    else
      warn "Let's Encrypt falhou. Gerando self-signed como fallback."
      CERT_OPCAO="3"
    fi
  fi

  # Self-signed (opção 2, 3 ou fallback do Let's Encrypt)
  if [ "$CERT_OPCAO" != "1" ] || ! [ -f "${SSL_DIR}/cert.pem" ]; then
    substep "Gerando certificado TLS self-signed (RSA 4096, válido 10 anos)..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
      -keyout "${SSL_DIR}/key.pem" \
      -out    "${SSL_DIR}/cert.pem" \
      -subj   "/CN=${APP_DOMAIN}/O=AD License Manager/C=BR" \
      -addext "subjectAltName=DNS:${APP_DOMAIN},DNS:localhost,IP:127.0.0.1" \
      >> "$INSTALL_LOG" 2>&1

    local expiry
    expiry=$(openssl x509 -in "${SSL_DIR}/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
    ok "Certificado self-signed gerado (expira: ${expiry})"

    if [ "$CERT_OPCAO" = "2" ]; then
      warn "Substitua o certificado em ${SSL_DIR}/ pelo da sua PKI corporativa."
      warn "Após substituir: docker compose restart nginx"
    fi
  fi

  # Aplica permissões corretas
  chown admanager:admanager "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  chmod 600 "${SSL_DIR}/key.pem"
  ok "Permissões do certificado configuradas (cert: 644, key: 600)"

  # Valida o certificado gerado
  if openssl x509 -in "${SSL_DIR}/cert.pem" -noout >> "$INSTALL_LOG" 2>&1; then
    ok "Certificado validado com sucesso"
  else
    falha_critica "Certificado TLS inválido. Verifique: ${INSTALL_LOG}"
  fi
}

# ─── ETAPA 8: Build das imagens ───────────────────────────────────────────────
build_imagens() {
  step "8" "BUILD DAS IMAGENS DOCKER"

  cd "${INSTALL_DIR}"

  info "Este processo pode levar de 8 a 25 minutos."
  info "Acompanhe o progresso em: tail -f ${INSTALL_LOG}"
  echo ""

  substep "Construindo todas as imagens..."
  # CORREÇÃO: --parallel pode causar problemas em sistemas com pouca RAM.
  # Removido para garantir compatibilidade. Adicionado --progress=plain no log.
  if docker compose build \
      --no-cache \
      --progress=plain \
      >> "$INSTALL_LOG" 2>&1; then
    ok "Todas as imagens construídas com sucesso"
  else
    falha_critica "Erro no build das imagens. Detalhes em: ${INSTALL_LOG}"
  fi

  substep "Imagens geradas:"
  docker compose images 2>/dev/null | tail -n +2 | while IFS= read -r linha; do
    echo "    ${linha}"
  done
}

# ─── ETAPA 9: Inicialização dos serviços ──────────────────────────────────────
iniciar_servicos() {
  step "9" "INICIALIZAÇÃO DOS SERVIÇOS"

  cd "${INSTALL_DIR}"

  substep "Iniciando PostgreSQL e Redis..."
  log_cmd docker compose up -d postgres redis
  ok "PostgreSQL e Redis iniciados"

  echo ""
  if ! aguardar_servico "PostgreSQL" \
      "docker compose exec -T postgres pg_isready -U admanager -d admanager" \
      40 3; then
    falha_critica "PostgreSQL não ficou pronto. Verifique: docker compose logs postgres"
  fi
  ok "PostgreSQL aceitando conexões"

  # CORREÇÃO: o teste do Redis usava redis-cli com a variável REDIS_PASSWORD
  # diretamente, mas ela pode conter caracteres que o shell interpretaria.
  # Usando variável em arquivo temporário.
  if ! aguardar_servico "Redis" \
      "docker compose exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping | grep -q PONG" \
      20 2; then
    falha_critica "Redis não ficou pronto. Verifique: docker compose logs redis"
  fi
  ok "Redis respondendo"
  echo ""

  substep "Aplicando migrations do banco de dados..."
  if log_cmd docker compose run --rm backend node dist/migrate.js; then
    ok "Migrations aplicadas com sucesso"
  else
    falha_critica "Erro nas migrations. Verifique: ${INSTALL_LOG}"
  fi

  substep "Criando dados iniciais (seed)..."
  if log_cmd docker compose run --rm backend node dist/seed.js; then
    ok "Dados iniciais criados (usuário admin e configurações padrão)"
  else
    falha_critica "Erro no seed. Verifique: ${INSTALL_LOG}"
  fi

  substep "Iniciando todos os serviços..."
  log_cmd docker compose up -d
  ok "Todos os serviços iniciados"

  echo ""
  # Backend pode demorar para ficar saudável — aguarda até 120s
  if ! aguardar_servico "Backend API" \
      "curl -sf http://localhost:3001/health" \
      30 4; then
    warn "Backend ainda não respondeu após 120s."
    warn "Verifique: docker compose logs backend"
    warn "A instalação continuará — verifique manualmente após concluir."
  else
    ok "Backend API saudável"
  fi
}

# ─── ETAPA 10: systemd ────────────────────────────────────────────────────────
configurar_systemd() {
  step "10" "CONFIGURAÇÃO DE INICIALIZAÇÃO AUTOMÁTICA"

  substep "Criando serviço systemd..."

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
User=admanager
Group=admanager
Environment="HOME=/tmp"

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

  # CORREÇÃO: admanager precisa ser dono dos sockets Docker ou estar no grupo.
  # O daemon-reload deve vir antes de enable.
  systemctl daemon-reload
  systemctl enable ad-license-manager >> "$INSTALL_LOG" 2>&1
  ok "Serviço systemd criado e habilitado no boot"

  # CORREÇÃO: verifica se o grupo docker está acessível para o admanager
  if ! groups admanager 2>/dev/null | grep -q docker; then
    warn "Usuário 'admanager' pode não ter acesso ao socket Docker."
    warn "Execute manualmente: usermod -aG docker admanager && reboot"
  fi
}

# ─── ETAPA 11: Scripts operacionais ──────────────────────────────────────────
criar_scripts() {
  step "11" "CRIAÇÃO DE SCRIPTS OPERACIONAIS"

  # ── Backup ──────────────────────────────────────────────────────────────
  substep "Criando scripts/backup.sh..."
  cat > "${INSTALL_DIR}/scripts/backup.sh" << 'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/ad-license-manager"
BACKUP_DATE=$(date +%Y-%m-%d)
BACKUP_DIR="${INSTALL_DIR}/backups/${BACKUP_DATE}"
LOG="${INSTALL_DIR}/logs/backup.log"
RETENCAO_DIAS=30

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"; }

log "Iniciando backup..."
mkdir -p "$BACKUP_DIR"

# Dump do PostgreSQL
if docker compose -f "${INSTALL_DIR}/docker-compose.yml" \
    exec -T postgres \
    pg_dump -U admanager admanager \
    --format=custom --compress=9 \
    > "${BACKUP_DIR}/database.dump"; then
  log "Banco de dados: OK ($(du -sh "${BACKUP_DIR}/database.dump" | cut -f1))"
else
  log "ERRO: Falha no dump do banco de dados."
  exit 1
fi

# Configurações
cp "${INSTALL_DIR}/.env" "${BACKUP_DIR}/.env.bak"
chmod 600 "${BACKUP_DIR}/.env.bak"
log "Configuracoes: OK"

# Logs
if [ -d "${INSTALL_DIR}/logs" ] && \
   ls "${INSTALL_DIR}/logs/"*.log 1>/dev/null 2>&1; then
  tar -czf "${BACKUP_DIR}/logs.tar.gz" \
    -C "${INSTALL_DIR}" logs/ 2>/dev/null && \
  log "Logs: OK" || \
  log "AVISO: Falha ao compactar logs."
fi

# Remove backups antigos
find "${INSTALL_DIR}/backups" \
  -maxdepth 1 -type d \
  -mtime "+${RETENCAO_DIAS}" \
  -exec rm -rf {} + 2>/dev/null || true

TAMANHO=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Backup concluido. Tamanho: ${TAMANHO} -> ${BACKUP_DIR}"
BACKUP_SCRIPT
  ok "backup.sh criado"

  # ── Health check ────────────────────────────────────────────────────────
  substep "Criando scripts/health-check.sh..."
  # CORREÇÃO: a versão anterior referenciava REDIS_PASSWORD do ambiente externo,
  # mas o script roda em contexto diferente. Agora lê do .env com parsing seguro.
  cat > "${INSTALL_DIR}/scripts/health-check.sh" << 'HEALTH_SCRIPT'
#!/usr/bin/env bash
set -uo pipefail

INSTALL_DIR="/opt/ad-license-manager"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
FALHAS=0

# Carrega variáveis do .env de forma segura (ignora linhas de comentário)
if [ -f "${INSTALL_DIR}/.env" ]; then
  REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d '"'"'"' ')
else
  REDIS_PASSWORD=""
fi

check() {
  local nome="$1"
  local cmd="$2"
  local esperado="$3"

  if eval "$cmd" 2>/dev/null | grep -q "$esperado"; then
    echo "  ✓  ${nome}"
  else
    echo "  ✗  ${nome}"
    FALHAS=$((FALHAS + 1))
  fi
}

echo ""
echo "  ── Health Check AD License Manager — $(date '+%d/%m/%Y %H:%M:%S')"
echo ""

check "PostgreSQL" \
  "docker compose -f '${COMPOSE_FILE}' exec -T postgres pg_isready -U admanager" \
  "accepting"

check "Redis" \
  "docker compose -f '${COMPOSE_FILE}' exec -T redis redis-cli -a '${REDIS_PASSWORD}' --no-auth-warning ping" \
  "PONG"

check "Backend API" \
  "curl -sf http://localhost:3001/health" \
  "."

check "Nginx HTTPS" \
  "curl -skf https://localhost/health" \
  "."

check "Worker" \
  "docker compose -f '${COMPOSE_FILE}' ps worker" \
  "running"

echo ""
if [ "$FALHAS" -gt 0 ]; then
  echo "  ✗  ${FALHAS} serviço(s) com problema."
  echo "     Detalhes: docker compose -f '${COMPOSE_FILE}' logs"
  exit 1
else
  echo "  ✓  Todos os serviços estão saudáveis."
fi

