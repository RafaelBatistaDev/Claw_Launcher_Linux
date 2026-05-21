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
EXEC_NAME="claw-onenote"
APP_NAME="OneNote"

REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

BIN_DIR="${REAL_HOME}/.local/bin"
APPS_DIR="${REAL_HOME}/.local/share/applications"
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"

# ── Dependências ──────────────────────────────────────────────────────────────
check_deps() {
    step "Verificando dependências Python (PyQt6, PyQt6-WebEngine)..."

    # ── 1. Detecta Python ──────────────────────────────────────────────────
    local PYTHON_CMD=""
    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null && "$cmd" -c "import sys; assert sys.version_info >= (3,9)" 2>/dev/null; then
            PYTHON_CMD="$cmd"
            break
        fi
    done

    if [[ -z "$PYTHON_CMD" ]]; then
        error "Python 3.9+ não encontrado. Instale via Distrobox ou rpm-ostree."
        exit 1
    fi

    # ── 2. Detecta pip vinculado ao Python encontrado ──────────────────────
    local PIP_CMD=""
    if "$PYTHON_CMD" -m pip --version &>/dev/null; then
        PIP_CMD="$PYTHON_CMD -m pip"   # Mais confiável: pip do mesmo Python
    else
        error "pip não encontrado para $PYTHON_CMD. Execute: $PYTHON_CMD -m ensurepip"
        exit 1
    fi

    # ── 3. Detecta ambiente (venv, distrobox, host imutável) ───────────────
    local IN_VENV=0
    local IN_DISTROBOX=0
    local IS_ATOMIC_HOST=0

    [[ -n "${VIRTUAL_ENV:-}" || -n "${CONDA_DEFAULT_ENV:-}" ]] && IN_VENV=1
    [[ -f /run/.containerenv || -f /.dockerenv ]] && IN_DISTROBOX=1
    [[ -f /run/ostree-booted ]] && IS_ATOMIC_HOST=1

    # ── 4. Verifica módulos ausentes ───────────────────────────────────────
    local -a MISSING=()

    "$PYTHON_CMD" -c "from PyQt6.QtWidgets import QApplication" 2>/dev/null \
        || MISSING+=("PyQt6")

    "$PYTHON_CMD" -c "from PyQt6.QtWebEngineWidgets import QWebEngineView" 2>/dev/null \
        || MISSING+=("PyQt6-WebEngine")

    if [[ ${#MISSING[@]} -eq 0 ]]; then
        success "Todas as dependências Python estão satisfeitas."
        return 0
    fi

    warn "Dependências ausentes: ${MISSING[*]}"

    # ── 5. Estratégia de instalação por contexto ───────────────────────────
    if [[ $IN_VENV -eq 1 ]]; then
        # Dentro de venv: pip direto, sem flags especiais
        step "Ambiente virtual detectado — instalando via pip..."
        if $PIP_CMD install "${MISSING[@]}"; then
            success "Dependências instaladas no venv."
            return 0
        fi

    elif [[ $IN_DISTROBOX -eq 1 ]]; then
        # Dentro de Distrobox/container: pip com --user
        step "Container detectado — instalando via pip --user..."
        if $PIP_CMD install --user "${MISSING[@]}"; then
            success "Dependências instaladas no container."
            return 0
        fi

    elif [[ $IS_ATOMIC_HOST -eq 1 ]]; then
        # Host imutável (Kinoite/Silverblue): NÃO usar pip no host
        error "Sistema imutável (ostree) detectado. pip no host não é recomendado."
        echo ""
        echo "  Opções recomendadas para Fedora Kinoite/Silverblue:"
        echo ""
        echo "  ① Instalar via rpm-ostree (requer reboot):"
        echo "      rpm-ostree install python3-qt6-webengine"
        echo ""
        echo "  ② Rodar este app dentro de um Distrobox (recomendado):"
        echo "      distrobox create --name pyqt-dev \\"
        echo "        --image registry.fedoraproject.org/fedora:latest"
        echo "      distrobox enter pyqt-dev"
        echo "      pip install ${MISSING[*]}"
        echo ""
        echo "  ③ Usar venv isolado (sem afetar o sistema):"
        echo "      python3 -m venv .venv && source .venv/bin/activate"
        echo "      pip install ${MISSING[*]}"
        echo ""
        exit 1

    else
        # Host mutável genérico (Ubuntu, Arch etc.)
        step "Tentando instalar via pip --user..."
        if $PIP_CMD install --user "${MISSING[@]}"; then
            success "Dependências instaladas com --user."
            return 0
        fi

        warn "pip --user falhou. Tentando com --break-system-packages..."
        if $PIP_CMD install --break-system-packages "${MISSING[@]}"; then
            success "Dependências instaladas com --break-system-packages."
            return 0
        fi
    fi

    # ── 6. Fallback: instrução manual por distro ───────────────────────────
    error "Não foi possível instalar automaticamente. Instale manualmente:"
    echo ""
    echo "  Fedora (mutável):  sudo dnf install python3-qt6-webengine"
    echo "  Fedora (Kinoite):  rpm-ostree install python3-qt6-webengine"
    echo "  Debian/Ubuntu:     sudo apt install python3-pyqt6.qtwebengine"
    echo "  Arch Linux:        sudo pacman -S python-pyqt6-webengine"
    echo "  Qualquer distro:   python3 -m venv .venv && source .venv/bin/activate"
    echo "                     pip install ${MISSING[*]}"
    exit 1
}

# ── Instalação ────────────────────────────────────────────────────────────────
do_install() {
    if command -v uv &>/dev/null; then
        step "UV detectado. Sincronizando ambiente..."
        uv sync --project "${SCRIPT_DIR}/.."
    else
        check_deps
    fi

    mkdir -p "${BIN_DIR}" "${APPS_DIR}"

    step "Instalando executáveis..."
    if [ ! -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" ]; then
        error "Arquivo Claw_Launcher_Linux.py não encontrado na pasta atual."
        exit 1
    fi

    cp -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" "${BIN_DIR}/${APP_ID}.py"
    chmod +x "${BIN_DIR}/${APP_ID}.py"

    # Determinar a raiz do workspace (onde está o pyproject.toml principal)
    WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

    cat > "${BIN_DIR}/${EXEC_NAME}" << EOF
#!/usr/bin/env bash
# Wrapper que verifica dependências antes de executar o app

# Cores para output
G="\033[1;32m"; R="\033[1;31m"; N="\033[0m"

# Função para verificar e instalar dependências
ensure_deps() {
    if command -v uv &>/dev/null; then
        return 0
    fi
    # Fallback para o check original se o UV não estiver presente
}

if command -v uv &>/dev/null; then
    exec uv run --project "${WORKSPACE_ROOT}" --package ${APP_ID,,} python "${BIN_DIR}/${APP_ID}.py" "\$@"
else
    ensure_deps
    exec python3 "${BIN_DIR}/${APP_ID}.py" "\$@"
fi
EOF
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