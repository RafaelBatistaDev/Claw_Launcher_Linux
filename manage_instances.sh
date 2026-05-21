#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : manage_instances.sh
# Descrição    : Gerenciador rápido de instâncias (desinstalar, limpeza, etc)
# Autor        : Rafael Batista
# Versão       : 1.0.2
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Cores
G="\033[1;32m"; B="\033[1;34m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

log()     { echo -e "${B}[INFO]${N}    $*"; }
success() { echo -e "${G}[OK]${N}      $*"; }
warn()    { echo -e "${Y}[AVISO]${N}   $*"; }
error()   { echo -e "${R}[ERRO]${N}    $*" >&2; }
step()    { echo -e "${C}[→]${N}       $*"; }

# Configurações
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

BIN_DIR="${REAL_HOME}/.local/bin"
APPS_DIR="${REAL_HOME}/.local/share/applications"
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"

# ─────────────────────────────────────────────────────────────────────────────
# DESINSTALAR E REMOVER TUDO DE UMA INSTÂNCIA
# ─────────────────────────────────────────────────────────────────────────────
purge_instance() {
    local app_id="$1"

    if [ -z "$app_id" ]; then
        error "Use: $0 purge <APP_ID>"
        exit 1
    fi

    # Encontrar EXEC_NAME a partir do APP_ID
    local instance_folder="${SCRIPT_DIR}/instance_${app_id}"

    if [ ! -d "$instance_folder" ]; then
        error "Instância '${app_id}' não encontrada."
        exit 1
    fi

    local exec_name=$(grep "^EXEC_NAME" "${instance_folder}/Claw_Launcher_Linux.sh" 2>/dev/null | cut -d'"' -f2)
    local app_name=$(grep "^APP_NAME" "${instance_folder}/Claw_Launcher_Linux.py" 2>/dev/null | cut -d'"' -f2)

    if [ -z "$exec_name" ]; then
        error "Não foi possível determinar o EXEC_NAME da instância."
        exit 1
    fi

    echo -e "${Y}Desinstalando '${app_name}'...${N}"

    # Desinstalar (via script da instância)
    if [ -x "${instance_folder}/Claw_Launcher_Linux.sh" ]; then
        cd "$instance_folder"
        ./Claw_Launcher_Linux.sh --uninstall 2>/dev/null || true
    fi

    # Remover executável
    rm -f "${BIN_DIR}/${exec_name}" 2>/dev/null || true
    rm -f "${BIN_DIR}/${app_id}" 2>/dev/null || true

    # Remover arquivo desktop
    rm -f "${APPS_DIR}/${app_id}.desktop" 2>/dev/null || true

    # Remover ícones
    find "${ICONS_BASE}" -name "${app_id}.png" -delete 2>/dev/null || true

    # Limpar dados e cache persistentes (nova configuração de isolamento)
    step "Limpando dados e caches de ${app_id}..."
    rm -rf "${REAL_HOME}/.local/share/${app_id}" 2>/dev/null || true
    rm -rf "${REAL_HOME}/.cache/${app_id}" 2>/dev/null || true

    # Remover pasta
    rm -rf "$instance_folder"

    success "Instância '${app_name}' removida completamente!"
}

# ─────────────────────────────────────────────────────────────────────────────
# LISTAR TODAS AS INSTÂNCIAS INSTALADAS
# ─────────────────────────────────────────────────────────────────────────────
list_all_instances() {
    echo ""
    log "=== Instâncias Instaladas em ${BIN_DIR} ==="
    echo ""

    local found=0

    # Procurar por scripts executáveis Claw
    for bin_exec in "${BIN_DIR}"/claw-*; do
        if [ -x "$bin_exec" ]; then
            local exec_name=$(basename "$bin_exec")
            local py_file="${BIN_DIR}/$(basename "$bin_exec" | sed 's/^claw-/Claw_/').py"

            if [ -f "$py_file" ]; then
                local app_name=$(grep "^APP_NAME" "$py_file" | cut -d'"' -f2)
                echo -e "${C}[${found}]${N} ${B}${app_name}${N}"
                echo "    Executável: ${exec_name}"
                echo ""
            fi
            ((found++))
        fi
    done

    # Procurar em pastas de instância
    for instance_dir in "${SCRIPT_DIR}"/instance_*; do
        if [ -d "$instance_dir" ]; then
            local folder_name=$(basename "$instance_dir")
            local py_file="${instance_dir}/Claw_Launcher_Linux.py"

            if [ -f "$py_file" ]; then
                local app_id=$(grep "^APP_ID" "$py_file" | cut -d'"' -f2)
                local app_name=$(grep "^APP_NAME" "$py_file" | cut -d'"' -f2)
                local installed="✗"

                # Verificar se está instalada
                local exec_name=$(grep "^EXEC_NAME" "${instance_dir}/Claw_Launcher_Linux.sh" 2>/dev/null | cut -d'"' -f2)
                if [ -n "${exec_name}" ] && [ -x "${BIN_DIR}/${exec_name}" ]; then
                    installed="✓"
                fi

                echo -e "${C}[${found}]${N} ${B}${app_name}${N} (${installed})"
                echo "    Pasta: ${folder_name}"
                echo "    App ID: ${app_id}"
                echo ""
                ((found++))
            fi
        fi
    done

    if [ $found -eq 0 ]; then
        warn "Nenhuma instância encontrada."
    else
        success "Total: ${found} instância(s)"
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# LIMPAR CACHE DE TODAS AS INSTÂNCIAS
# ─────────────────────────────────────────────────────────────────────────────
clear_caches() {
    echo ""
    log "=== Limpando Caches de Todas as Instâncias ==="
    echo -e "${Y}Isso removerá logins e caches de TODOS os apps Claw/OneNote.${N}\n"

    local share_base="${REAL_HOME}/.local/share"
    local cache_base="${REAL_HOME}/.cache"
    local cleaned=0

    # Lista de IDs para limpar (OneNote + qualquer pasta começando com Claw_ em share ou cache)
    local targets=()
    mapfile -t targets < <( (echo "OneNote"; find "$share_base" "$cache_base" -maxdepth 1 -type d -name "Claw_*" -printf "%f\n" 2>/dev/null) | sort -u)

    for app_id in "${targets[@]}"; do
        [ -z "$app_id" ] && continue
        for base in "$share_base" "$cache_base"; do
            if [ -d "$base/$app_id" ]; then
                step "Limpando: $base/$app_id"
                rm -rf "$base/$app_id"
                ((cleaned++))
            fi
        done
    done

    if [ $cleaned -eq 0 ]; then
        warn "Nenhum cache encontrado para limpar."
    else
        success "Limpeza concluída! (${cleaned} item(ns) removido(s))"
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# DESINSTALAR TODAS AS INSTÂNCIAS
# ���────────────────────────────────────────────────────────────────────────────
uninstall_all() {
    echo ""
    log "=== Desinstalar TODAS as Instâncias ==="
    echo -e "${Y}Aviso: Isso removará todos os aplicativos Claw instalados!${N}"
    echo ""

    read -p "Tem CERTEZA? Digite 'sim' para confirmar: " confirm

    if [ "$confirm" != "sim" ]; then
        warn "Operação cancelada."
        return 0
    fi

    # Remover todos os executáveis Claw
    step "Removendo executáveis..."
    find "${BIN_DIR}" -name "claw-*" -type f -delete 2>/dev/null || true
    find "${BIN_DIR}" -name "Claw_*" -type f -delete 2>/dev/null || true

    # Remover todos os desktops
    step "Removendo atalhos de menu..."
    find "${APPS_DIR}" -name "Claw_*" -type f -delete 2>/dev/null || true

    # Remover todos os ícones
    step "Removendo ícones..."
    find "${ICONS_BASE}" -name "Claw_*" -delete 2>/dev/null || true

    # Limpar caches
    step "Limpando caches..."
    clear_caches

    success "Todas as instâncias foram removidas!"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# MOSTRAR HELP
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
    cat << EOF

${B}╔════════════════════════════════════════════════════════╗${N}
${B}║${N}  ${C}Gerenciador de Instâncias Claw Launcher${N}
${B}╚════════════════════════════════════════════════════════╝${N}

${B}Uso:${N}
  $0 <comando> [opções]

${B}Comandos:${N}

  ${C}list${N}
    Listar todas as instâncias instaladas e em pasta.

  ${C}purge <APP_ID>${N}
    Remover completamente uma instância (desinstalar + remover pasta).
    Exemplo: $0 purge Claw_ChatGPT

  ${C}clear-caches${N}
    Limpar o cache de todas as instâncias.

  ${C}uninstall-all${N}
    Desinstalar COMPLETAMENTE todas as instâncias do sistema.
    ${Y}⚠ Esta ação é irreversível!${N}

  ${C}help${N}
    Mostrar esta mensagem de ajuda.

${B}Exemplos:${N}

  # Listar todas as instâncias
  $0 list

  # Remover a instância ChatGPT
  $0 purge Claw_ChatGPT

  # Limpar cache
  $0 clear-caches

${B}Nota:${N}
  Para gerenciamento mais completo (criar, instalar, etc), use:
  ./create_app.sh

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-help}" in
    list)          list_all_instances ;;
    purge)         purge_instance "${2:-}" ;;
    clear-caches)  clear_caches ;;
    uninstall-all) uninstall_all ;;
    help|--help|-h) show_help ;;
    *)
        error "Comando desconhecido: $1"
        show_help
        exit 1
        ;;
esac
