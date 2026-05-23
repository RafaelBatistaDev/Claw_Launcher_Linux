#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : Claw_Launcher_Linux.sh
# Descrição    : Instala/Desinstala OneNote (Versão PyQt6 para KDE)
# Autor        : Rafael Batista
# Versão       : 1.0.3
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

G="\033[1;32m"; B="\033[1;34m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

log()     { echo -e "${B}[INFO]${N}    $*"; }
success() { echo -e "${G}[OK]${N}      $*"; }
warn()    { echo -e "${Y}[AVISO]${N}   $*"; }
error()   { echo -e "${R}[ERRO]${N}    $*" >&2; }
step()    { echo -e "${C}[→]${N}       $*"; }
removed() { echo -e "${Y}[DEL]${N}     $*"; }

# ── Configurações ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
APP_ID="OneNote"
EXEC_NAME="claw-onenote"
APP_NAME="OneNote"
ICON_SIZES=(16 32 48 64 128 256)

REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

BIN_DIR="${REAL_HOME}/.local/bin"
APPS_DIR="${REAL_HOME}/.local/share/applications"
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────
remove_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        rm -f "$file"
        removed "$file"
    else
        warn "Não encontrado (já removido?): $file"
    fi
}

update_caches() {
    step "Atualizando caches do sistema..."
    update-desktop-database "${APPS_DIR}"  2>/dev/null || true
    gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true
    if command -v kbuildsycoca6 &>/dev/null; then kbuildsycoca6 --noincremental 2>/dev/null; fi
    if command -v kbuildsycoca5 &>/dev/null; then kbuildsycoca5 --noincremental 2>/dev/null; fi
    success "Caches atualizados."
}

# ── Dependências ──────────────────────────────────────────────────────────────
check_deps() {
    step "Verificando dependências Python (PyQt6, PyQt6-WebEngine)..."

    local PYTHON_CMD=""
    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null && "$cmd" -c "import sys; assert sys.version_info >= (3,9)" 2>/dev/null; then
            PYTHON_CMD="$cmd"
            break
        fi
    done

    [[ -z "$PYTHON_CMD" ]] && { error "Python 3.9+ não encontrado. Instale via Distrobox ou rpm-ostree."; exit 1; }

    local PIP_CMD=""
    if "$PYTHON_CMD" -m pip --version &>/dev/null; then
        PIP_CMD="$PYTHON_CMD -m pip"
    else
        error "pip não encontrado para $PYTHON_CMD. Execute: $PYTHON_CMD -m ensurepip"
        exit 1
    fi

    local IN_VENV=0 IN_DISTROBOX=0 IS_ATOMIC_HOST=0
    [[ -n "${VIRTUAL_ENV:-}" || -n "${CONDA_DEFAULT_ENV:-}" ]] && IN_VENV=1
    [[ -f /run/.containerenv || -f /.dockerenv ]]               && IN_DISTROBOX=1
    [[ -f /run/ostree-booted ]]                                  && IS_ATOMIC_HOST=1

    local -a MISSING=()
    "$PYTHON_CMD" -c "from PyQt6.QtWidgets import QApplication"       2>/dev/null || MISSING+=("PyQt6")
    "$PYTHON_CMD" -c "from PyQt6.QtWebEngineWidgets import QWebEngineView" 2>/dev/null || MISSING+=("PyQt6-WebEngine")

    [[ ${#MISSING[@]} -eq 0 ]] && { success "Todas as dependências satisfeitas."; return 0; }

    warn "Dependências ausentes: ${MISSING[*]}"

    if [[ $IN_VENV -eq 1 ]]; then
        step "Ambiente virtual detectado — instalando via pip..."
        $PIP_CMD install "${MISSING[@]}" && { success "Dependências instaladas no venv."; return 0; }

    elif [[ $IN_DISTROBOX -eq 1 ]]; then
        step "Container detectado — instalando via pip --user..."
        $PIP_CMD install --user "${MISSING[@]}" && { success "Dependências instaladas no container."; return 0; }

    elif [[ $IS_ATOMIC_HOST -eq 1 ]]; then
        error "Sistema imutável (ostree) detectado. pip no host não é recomendado."
        echo ""
        echo "  Opções recomendadas para Fedora Kinoite/Silverblue:"
        echo ""
        echo "  ① rpm-ostree (requer reboot):"
        echo "      rpm-ostree install python3-qt6-webengine"
        echo ""
        echo "  ② Distrobox (recomendado):"
        echo "      distrobox create --name pyqt-dev \\"
        echo "        --image registry.fedoraproject.org/fedora:latest"
        echo "      distrobox enter pyqt-dev && pip install ${MISSING[*]}"
        echo ""
        echo "  ③ venv isolado:"
        echo "      python3 -m venv .venv && source .venv/bin/activate"
        echo "      pip install ${MISSING[*]}"
        exit 1

    else
        step "Tentando pip --user..."
        $PIP_CMD install --user "${MISSING[@]}" && { success "Dependências instaladas."; return 0; }
        warn "pip --user falhou. Tentando --break-system-packages..."
        $PIP_CMD install --break-system-packages "${MISSING[@]}" && { success "Dependências instaladas."; return 0; }
    fi

    error "Não foi possível instalar automaticamente. Instale manualmente:"
    echo "  Fedora (Kinoite):  rpm-ostree install python3-qt6-webengine"
    echo "  Debian/Ubuntu:     sudo apt install python3-pyqt6.qtwebengine"
    echo "  Arch Linux:        sudo pacman -S python-pyqt6-webengine"
    exit 1
}

# ── Instalação ────────────────────────────────────────────────────────────────
do_install() {
    log "═══ Instalando ${APP_NAME} ═══"

    # 1. Dependências
    if command -v uv &>/dev/null; then
        step "UV detectado — sincronizando ambiente..."
        uv sync --project "${SCRIPT_DIR}"
        success "Ambiente sincronizado via uv."
    else
        check_deps
    fi

    mkdir -p "${BIN_DIR}" "${APPS_DIR}"

    # 2. Script Python
    step "Instalando script Python..."
    [[ ! -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" ]] && {
        error "Claw_Launcher_Linux.py não encontrado em ${SCRIPT_DIR}"
        exit 1
    }
    cp -f "${SCRIPT_DIR}/Claw_Launcher_Linux.py" "${BIN_DIR}/${APP_ID}.py"
    chmod +x "${BIN_DIR}/${APP_ID}.py"
    success "Script instalado: ${BIN_DIR}/${APP_ID}.py"

    # 3. Wrapper executável
    step "Criando wrapper executável..."
    cat > "${BIN_DIR}/${EXEC_NAME}" << WRAPPER
#!/usr/bin/env bash
if command -v uv &>/dev/null; then
    exec uv run --project "${WORKSPACE_ROOT}" --package ${APP_ID,,} python "${BIN_DIR}/${APP_ID}.py" "\$@"
else
    exec python3 "${BIN_DIR}/${APP_ID}.py" "\$@"
fi
WRAPPER
    chmod +x "${BIN_DIR}/${EXEC_NAME}"
    success "Wrapper criado: ${BIN_DIR}/${EXEC_NAME}"

    # 4. Ícones (um por tamanho)
    step "Instalando ícones..."
    local ICON_SRC="${SCRIPT_DIR}/${APP_ID}.png"
    [[ ! -f "$ICON_SRC" ]] && ICON_SRC="${SCRIPT_DIR}/Claw_Launcher_Linux-256.png"

    if [[ -f "$ICON_SRC" ]]; then
        for size in "${ICON_SIZES[@]}"; do
            local dest="${ICONS_BASE}/${size}x${size}/apps"
            mkdir -p "$dest"
            cp -f "$ICON_SRC" "${dest}/${APP_ID}.png"
            success "Ícone ${size}x${size}: ${dest}/${APP_ID}.png"
        done
    else
        warn "Ícone não encontrado — app funciona sem ícone personalizado."
    fi

    # 5. Atalho .desktop
    step "Instalando atalho de menu..."
    if [[ -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" ]]; then
        cp -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Exec=.*@Exec=${BIN_DIR}/${EXEC_NAME} %U@"   "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Icon=.*@Icon=${APP_ID}@"                     "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^StartupWMClass=.*@StartupWMClass=${APP_ID}@" "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Name=.*@Name=${APP_NAME}@"                   "${APPS_DIR}/${APP_ID}.desktop"
        sed -i "s@^Comment=.*@Comment=${APP_NAME} - Dashboard IA@" "${APPS_DIR}/${APP_ID}.desktop"
        success "Atalho instalado: ${APPS_DIR}/${APP_ID}.desktop"
    else
        warn "Arquivo .desktop não encontrado — atalho de menu não criado."
    fi

    # 6. Caches
    update_caches

    success "═══ ${APP_NAME} instalado com sucesso! ═══"
    log "Execute: ${EXEC_NAME}"
}

# ── Desinstalação (espelho exato do install) ──────────────────────────────────
do_uninstall() {
    log "═══ Desinstalando ${APP_NAME} ═══"

    # 2. Script Python
    step "Removendo script Python..."
    remove_file "${BIN_DIR}/${APP_ID}.py"

    # 3. Wrapper executável
    step "Removendo wrapper executável..."
    remove_file "${BIN_DIR}/${EXEC_NAME}"

    # 4. Ícones (um por tamanho — mesma lista do install)
    step "Removendo ícones..."
    for size in "${ICON_SIZES[@]}"; do
        local icon="${ICONS_BASE}/${size}x${size}/apps/${APP_ID}.png"
        remove_file "$icon"
    done

    # 5. Atalho .desktop
    step "Removendo atalho de menu..."
    remove_file "${APPS_DIR}/${APP_ID}.desktop"

    # 6. Caches
    update_caches

    success "═══ ${APP_NAME} removido com sucesso! ═══"
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-}" in
    --install)   do_install   ;;
    --uninstall) do_uninstall ;;
    *) echo "Uso: $0 [--install | --uninstall]"; exit 1 ;;
esac