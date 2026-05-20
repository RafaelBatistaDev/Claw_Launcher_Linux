#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : Claw_Launcher_Linux.sh
# Descrição    : Instala OneNote (Versão PyQt6 para KDE)
# Autor        : Rafael Batista
# Versão       : 1.0.2
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

G="\033[1;32m"; B="\033[1;34m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

log()     { echo -e "${B}[INFO]${N}    $*"; }
success() { echo -e "${G}[OK]${N}      $*"; }
warn()    { echo -e "${Y}[AVISO]${N}   $*"; }
error()   { echo -e "${R}[ERRO]${N}    $*" >&2; }
step()    { echo -e "${C}[→]${N}       $*"; }

# ── Configurações ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
APP_ID="OneNote"
EXEC_NAME="OneNote"
APP_NAME="OneNote"

REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

BIN_DIR="${REAL_HOME}/.local/bin"
APPS_DIR="${REAL_HOME}/.local/share/applications"
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"

# ── Dependências ──────────────────────────────────────────────────────────────
check_deps() {
    step "Verificando dependências Python necessárias (PyQt6, PyQt6-WebEngine)..."

    # Determina se usa 'pip' ou 'pip3'
    PIP_CMD="pip3"
    if ! command -v pip3 &>/dev/null && command -v pip &>/dev/null; then
        PIP_CMD="pip"
    fi

    if ! command -v "$PIP_CMD" &>/dev/null; then
        error "Gerenciador 'pip' não encontrado. Por favor, instale python3-pip."
        exit 1
    fi

    # Verifica cada módulo necessário
    MISSING_PYTHON_DEPS=0
    MISSING_PYTHON_PACKAGES=()

    # Check PyQt6
    if ! python3 -c "from PyQt6.QtWidgets import QApplication" 2>/dev/null; then
        MISSING_PYTHON_PACKAGES+=("PyQt6")
        MISSING_PYTHON_DEPS=1
    fi

    # Check PyQt6-WebEngine
    if ! python3 -c "from PyQt6.QtWebEngineWidgets import QWebEngineView" 2>/dev/null; then
        MISSING_PYTHON_PACKAGES+=("PyQt6-WebEngine")
        MISSING_PYTHON_DEPS=1
    fi

    if [ $MISSING_PYTHON_DEPS -eq 1 ]; then
        warn "Dependências Python incompletas. Tentando instalar: ${MISSING_PYTHON_PACKAGES[*]}"

        # Try installing with --break-system-packages first
        if ! $PIP_CMD install "${MISSING_PYTHON_PACKAGES[@]}" --break-system-packages 2>/dev/null; then
            # If that fails, try without the flag
            if ! $PIP_CMD install "${MISSING_PYTHON_PACKAGES[@]}" 2>/dev/null; then
                error "Falha ao instalar dependências Python via pip. Tente manualmente: $PIP_CMD install ${MISSING_PYTHON_PACKAGES[*]}"
                exit 1
            fi
        fi
        success "Dependências Python instaladas com sucesso."

        # Re-check after pip installation to see if system deps are still missing
        MISSING_SYSTEM_DEPS=0
        if ! python3 -c "from PyQt6.QtWidgets import QApplication" 2>/dev/null; then
            MISSING_SYSTEM_DEPS=1
        fi
        if ! python3 -c "from PyQt6.QtWebEngineWidgets import QWebEngineView" 2>/dev/null; then
            MISSING_SYSTEM_DEPS=1
        fi

        if [ $MISSING_SYSTEM_DEPS -eq 1 ]; then
            error "Parece que as dependências do sistema para PyQt6/QtWebEngine estão faltando."
            echo "Por favor, instale os pacotes de sistema apropriados para Qt6 WebEngine."
            echo "Exemplos:"
            echo "  Debian/Ubuntu: sudo apt install python3-pyqt6.qtwebengine"
            echo "  Fedora: sudo dnf install python3-qt6-webengine"
            echo "  Arch Linux: sudo pacman -S python-pyqt6-webengine"
            exit 1
        fi
    else
        success "Todas as dependências Python estão satisfeitas."
    fi
}

# ── Instalação ────────────────────────────────────────────────────────────────
do_install() {
    check_deps

    mkdir -p "${BIN_DIR}" "${APPS_DIR}"

    step "Instalando executáveis..."
    if [ ! -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" ]; then
        error "Arquivo Claw_Launcher_Linux.py não encontrado na pasta atual."
        exit 1
    fi

    cp -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" "${BIN_DIR}/${APP_ID}.py"
    chmod +x "${BIN_DIR}/${APP_ID}.py"

    cat > "${BIN_DIR}/${EXEC_NAME}" << 'EOF'
#!/usr/bin/env bash
# Wrapper que verifica dependências antes de executar o app

# Cores para output
G="\033[1;32m"; R="\033[1;31m"; N="\033[0m"

# Função para verificar e instalar dependências
ensure_deps() {
    # Tenta importar módulos necessários
    if ! python3 -c "from PyQt6.QtWidgets import QApplication; from PyQt6.QtWebEngineWidgets import QWebEngineView" 2>/dev/null; then
        # Se falhar, recomenda instalação
        echo -e "${R}[ERRO]${N} Dependências ausentes (PyQt6, PyQt6-WebEngine)"
        echo "Instalando automaticamente..."

        PIP_CMD="pip3"
        if ! command -v pip3 &>/dev/null && command -v pip &>/dev/null; then
            PIP_CMD="pip"
        fi

        if command -v "$PIP_CMD" &>/dev/null; then
            if ! $PIP_CMD install PyQt6 PyQt6-WebEngine --break-system-packages 2>/dev/null; then
                $PIP_CMD install PyQt6 PyQt6-WebEngine 2>/dev/null || {
                    echo -e "${R}[ERRO]${N} Falha ao instalar dependências."
                    echo "Execute manualmente: $PIP_CMD install PyQt6 PyQt6-WebEngine"
                    exit 1
                }
            fi
            echo -e "${G}[OK]${N} Dependências instaladas. Iniciando aplicativo..."
        else
            echo -e "${R}[ERRO]${N} pip não encontrado. Instale: python3-pip"
            exit 1
        fi
    fi
}

ensure_deps
exec python3 "$(dirname "$0")/${APP_ID}.py" "$@"
EOF
    sed -i "s|\${APP_ID}\.py|${APP_ID}.py|g" "${BIN_DIR}/${EXEC_NAME}"
    chmod +x "${BIN_DIR}/${EXEC_NAME}"

    step "Instalando ícones..."
    ICON_SRC="${SCRIPT_DIR}/${APP_ID}.png"
    if [ ! -f "$ICON_SRC" ]; then
        ICON_SRC="${SCRIPT_DIR}/Claw_Launcher_Linux-256.png"
    fi

    if [ -f "$ICON_SRC" ]; then
        for size in 16 32 48 64 128 256; do
            mkdir -p "${ICONS_BASE}/${size}x${size}/apps"
            cp -f "$ICON_SRC" "${ICONS_BASE}/${size}x${size}/apps/${APP_ID}.png"
        done
        success "Ícones instalados."
    else
        warn "Ícone de origem ($ICON_SRC) não encontrado. O aplicativo funcionará, mas sem ícone personalizado."
    fi

    step "Instalando atalho de menu..."
    if [ -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" ]; then
        cp -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" "${APPS_DIR}/${APP_ID}.desktop"

        # Ajustar caminhos no .desktop
        sed -i "s@^Exec=.*@Exec=${BIN_DIR}/${EXEC_NAME} %U@" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Icon=.*@Icon=${APP_ID}@" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^StartupWMClass=.*@StartupWMClass=${APP_ID}@" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Name=.*@Name=${APP_NAME}@" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Comment=.*@Comment=${APP_NAME} - Dashboard IA@" "${APPS_DIR}/${APP_ID}.desktop"
        success "Atalho instalado."
    else
        warn "Arquivo .desktop não encontrado. Atalho de menu não criado."
    fi

    step "Atualizando caches do sistema..."
    update-desktop-database "${APPS_DIR}" 2>/dev/null || true
    gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true

    if command -v kbuildsycoca6 &>/dev/null; then kbuildsycoca6 --noincremental; fi
    if command -v kbuildsycoca5 &>/dev/null; then kbuildsycoca5 --noincremental; fi

    success "Instalação concluída! Procure por 'OneNote' no seu menu."
}

# ── Desinstalação ─────────────────────────────────────────────────────────────
do_uninstall() {
    rm -f "${BIN_DIR}/${EXEC_NAME}" "${BIN_DIR}/${APP_ID}.py" "${APPS_DIR}/${APP_ID}.desktop"
    find "${ICONS_BASE}" -name "${APP_ID}.png" -delete
    success "Removido com sucesso."
}

case "${1:-}" in
    --install)   do_install   ;;
    --uninstall) do_uninstall ;;
    *) echo "Uso: $0 [--install | --uninstall]"; exit 1 ;;
esac