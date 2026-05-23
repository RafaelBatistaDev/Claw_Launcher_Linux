#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : manage_instances.sh
# Descrição    : Gerenciador rápido de instâncias (purge, lista, cache, etc)
# Autor        : Rafael Batista
# Versão       : 1.0.4 (com melhorias opcionais)
# ──────────────────────────────────────────────────────────────────────────────
# 
# CHANGELOG v1.0.4:
#   + Logging em arquivo (.local/log/)
#   + Validação de integridade antes de purge
#   + Backup automático em clear-caches (opcional)
#   + Dry-run mode para purge
#   + Help melhorado com exemplos
#   + Exit codes mais granulares
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
G="\033[1;32m"; B="\033[1;34m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

log()     { echo -e "${B}[INFO]${N}    $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${B}[INFO]${N}    $*"; }
success() { echo -e "${G}[OK]${N}      $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${G}[OK]${N}      $*"; }
warn()    { echo -e "${Y}[AVISO]${N}   $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${Y}[AVISO]${N}   $*"; }
error()   { echo -e "${R}[ERRO]${N}    $*" >&2 | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${R}[ERRO]${N}    $*" >&2; }
step()    { echo -e "${C}[→]${N}       $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${C}[→]${N}       $*"; }
removed() { echo -e "${Y}[DEL]${N}     $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${Y}[DEL]${N}     $*"; }

# ── Configurações Compartilhadas ──────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

ICON_SIZES=(16 32 48 64 128 256)
BIN_DIR="${REAL_HOME}/.local/bin"
APPS_DIR="${REAL_HOME}/.local/share/applications"
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"

# ── Logging (novo em v1.0.4) ──────────────────────────────────────────────────
LOG_DIR="${REAL_HOME}/.local/log"
LOG_FILE="${LOG_DIR}/manage_instances_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true

# ── Flags Globais ─────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false
BACKUP_ON_CLEAR=true

# ── Helpers Compartilhados ────────────────────────────────────────────────────

remove_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            removed "(DRY-RUN) Seria removido: $file"
        else
            rm -f "$file"
            removed "$file"
        fi
    else
        [[ "$VERBOSE" == "true" ]] && warn "Não encontrado (já removido?): $file"
    fi
}

remove_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            removed "(DRY-RUN) Seria removido: ${dir}/"
        else
            rm -rf "$dir"
            removed "${dir}/"
        fi
    else
        [[ "$VERBOSE" == "true" ]] && warn "Diretório não encontrado (já removido?): ${dir}/"
    fi
}

update_caches() {
    step "Atualizando caches do sistema..."
    update-desktop-database "${APPS_DIR}"       2>/dev/null || true
    gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true
    if command -v kbuildsycoca6 &>/dev/null; then kbuildsycoca6 --noincremental 2>/dev/null || true; fi
    if command -v kbuildsycoca5 &>/dev/null; then kbuildsycoca5 --noincremental 2>/dev/null || true; fi
    success "Caches atualizados."
}

# ── Validação de Integridade (novo em v1.0.4) ────────────────────────────────
validate_instance() {
    local app_id="$1"
    local instance_folder="${SCRIPT_DIR}/instance_${app_id}"
    local exec_name

    [[ ! -d "$instance_folder" ]] && return 1

    exec_name=$(grep "^EXEC_NAME" "${instance_folder}/Claw_Launcher_Linux.sh" 2>/dev/null | cut -d'"' -f2 || echo "")
    
    local checks_passed=0
    local checks_total=4

    # Checks:
    [[ -f "${instance_folder}/Claw_Launcher_Linux.sh" ]] && ((checks_passed++))
    [[ -f "${instance_folder}/Claw_Launcher_Linux.py" ]] && ((checks_passed++))
    [[ -x "${BIN_DIR}/${exec_name}" ]] && ((checks_passed++))
    [[ -f "${APPS_DIR}/${app_id}.desktop" ]] && ((checks_passed++))

    if [[ $checks_passed -ge 3 ]]; then
        return 0
    else
        warn "Integridade comprometida: ${checks_passed}/${checks_total} checks ok"
        return 1
    fi
}

# ── Backup (novo em v1.0.4) ──────────────────────────────────────────────────
backup_app_data() {
    local app_id="$1"
    local share_dir="${REAL_HOME}/.local/share/${app_id}"
    local backup_dir="${REAL_HOME}/.local/share/claw_backups"

    [[ ! -d "$share_dir" ]] && return 0

    mkdir -p "$backup_dir"

    local backup_file="${backup_dir}/${app_id}_$(date +%Y%m%d_%H%M%S).tar.gz"
    step "Fazendo backup: ${app_id} → ${backup_dir}/"
    
    tar czf "$backup_file" -C "${REAL_HOME}/.local/share" "$app_id" 2>/dev/null || {
        warn "Falha ao fazer backup de ${app_id}"
        return 1
    }

    success "Backup salvo: $(basename "$backup_file")"
    return 0
}

# ── Purge com Validação ──────────────────────────────────────────────────────
purge_instance() {
    local app_id="${1:-}"
    [ -z "$app_id" ] && { error "Use: $0 purge <APP_ID>"; exit 1; }

    local instance_folder="${SCRIPT_DIR}/instance_${app_id}"
    [ ! -d "$instance_folder" ] && { error "Instância '${app_id}' não encontrada."; exit 1; }

    # Validação de integridade
    if ! validate_instance "$app_id"; then
        warn "Instância parece parcialmente removida. Continuando limpeza..."
    fi

    local exec_name app_name
    exec_name=$(grep "^EXEC_NAME" "${instance_folder}/Claw_Launcher_Linux.sh" 2>/dev/null | cut -d'"' -f2 || true)
    app_name=$(grep  "^APP_NAME"  "${instance_folder}/Claw_Launcher_Linux.py"  2>/dev/null | cut -d'"' -f2 || true)
    app_name="${app_name:-$app_id}"

    [ -z "$exec_name" ] && { error "Não foi possível determinar EXEC_NAME de '${app_id}'."; exit 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        log "═══ DRY-RUN: Purge de ${app_name} (${app_id}) ═══"
    else
        log "═══ Purge: ${app_name} (${app_id}) ═══"
    fi

    # 1. Desinstala via script
    if [ -x "${instance_folder}/Claw_Launcher_Linux.sh" ]; then
        step "Executando desinstalação da instância..."
        if [[ "$DRY_RUN" == "true" ]]; then
            step "(DRY-RUN) Pulando: ./Claw_Launcher_Linux.sh --uninstall"
        else
            (cd "$instance_folder" && ./Claw_Launcher_Linux.sh --uninstall) || true
        fi
    fi

    # 2. Executáveis
    step "Removendo executáveis..."
    remove_file "${BIN_DIR}/${exec_name}"
    remove_file "${BIN_DIR}/${app_id}.py"

    # 3. .desktop
    step "Removendo atalho de menu..."
    remove_file "${APPS_DIR}/${app_id}.desktop"

    # 4. Ícones
    step "Removendo ícones..."
    for size in "${ICON_SIZES[@]}"; do
        remove_file "${ICONS_BASE}/${size}x${size}/apps/${app_id}.png"
    done

    # 5. Dados de perfil
    step "Removendo dados de perfil..."
    remove_file "${REAL_HOME}/.local/share/${app_id}/config.json"
    remove_dir  "${REAL_HOME}/.local/share/${app_id}/storage"
    remove_dir  "${REAL_HOME}/.local/share/${app_id}/cache"
    if [[ "$DRY_RUN" != "true" ]]; then
        rmdir --ignore-fail-on-non-empty "${REAL_HOME}/.local/share/${app_id}" 2>/dev/null || true
    fi

    # 6. Cache XDG
    step "Removendo cache XDG..."
    remove_dir "${REAL_HOME}/.cache/${app_id}"

    # 7. Pasta da instância
    step "Removendo pasta da instância..."
    remove_dir "$instance_folder"

    # 8. Caches do sistema
    if [[ "$DRY_RUN" != "true" ]]; then
        update_caches
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "═══ DRY-RUN: Nada foi deletado! Execute sem --dry-run para confirmar ═══"
    else
        success "═══ '${app_name}' removido completamente! ═══"
    fi
}

# ── Listar instâncias ──────────────────────────────────────────────────────────
list_all_instances() {
    echo ""
    log "═══ Instâncias do Projeto ═══"
    echo ""

    local found=0

    for instance_dir in "${SCRIPT_DIR}"/instance_*; do
        [ -d "$instance_dir" ] || continue

        local py_file="${instance_dir}/Claw_Launcher_Linux.py"
        [ -f "$py_file" ] || continue

        local app_id app_name exec_name installed="✗" integrity="✓"
        app_id=$(  grep "^APP_ID"   "$py_file" | cut -d'"' -f2)
        app_name=$(grep "^APP_NAME" "$py_file" | cut -d'"' -f2)
        exec_name=$(grep "^EXEC_NAME" "${instance_dir}/Claw_Launcher_Linux.sh" 2>/dev/null | cut -d'"' -f2 || true)

        [ -n "$exec_name" ] && [ -x "${BIN_DIR}/${exec_name}" ] && installed="✓"
        
        if ! validate_instance "$app_id" 2>/dev/null; then
            integrity="⚠"
        fi

        echo -e "  ${C}[${found}]${N} ${B}${app_name}${N} (${installed} instalado, integridade: ${integrity})"
        echo "      Pasta:     instance_${app_id}"
        echo "      App ID:    ${app_id}"
        echo "      Exec:      ${exec_name:-desconhecido}"
        echo ""
        (( found++ )) || true
    done

    if [ $found -eq 0 ]; then
        warn "Nenhuma instância encontrada."
    else
        success "Total: ${found} instância(s)"
    fi
    echo ""
}

# ── Limpar cache com backup ──────────────────────────────────────────────────
clear_all_caches() {
    echo ""
    log "═══ Limpando Caches de Todas as Instâncias ═══"
    echo -e "${Y}Isso removerá logins e caches de TODOS os apps Claw/OneNote.${N}\n"

    local cleaned=0

    local -a targets=()
    mapfile -t targets < <(
        (
            echo "OneNote"
            find "${REAL_HOME}/.local/share" "${REAL_HOME}/.cache" \
                 -maxdepth 1 -type d -name "Claw_*" -printf "%f\n" 2>/dev/null
        ) | sort -u
    )

    for app_id in "${targets[@]}"; do
        [ -z "$app_id" ] && continue

        # Backup se habilitado
        if [[ "$BACKUP_ON_CLEAR" == "true" ]]; then
            backup_app_data "$app_id" || warn "Falha no backup de ${app_id}"
        fi

        log "Cache: ${app_id}"

        step "  Dados de perfil..."
        remove_file "${REAL_HOME}/.local/share/${app_id}/config.json" 2>/dev/null || true
        remove_dir  "${REAL_HOME}/.local/share/${app_id}/storage"     2>/dev/null || true
        remove_dir  "${REAL_HOME}/.local/share/${app_id}/cache"       2>/dev/null || true
        if [[ "$DRY_RUN" != "true" ]]; then
            rmdir --ignore-fail-on-non-empty "${REAL_HOME}/.local/share/${app_id}" 2>/dev/null || true
        fi

        step "  Cache XDG..."
        remove_dir "${REAL_HOME}/.cache/${app_id}" 2>/dev/null || true

        (( cleaned++ )) || true
    done

    [ $cleaned -eq 0 ] && warn "Nenhum cache encontrado." || success "Cache limpo para ${cleaned} app(s)."
    echo ""
}

# ── Desinstalar tudo ───────────────────────────────────────────────────────────
uninstall_all() {
    echo ""
    log "═══ Desinstalar TODAS as Instâncias ═══"
    echo -e "${Y}Aviso: Remove todos os aplicativos Claw do sistema!${N}"
    echo ""
    read -r -p "Tem CERTEZA? Digite 'sim' para confirmar: " confirm
    [[ "$confirm" != "sim" ]] && { warn "Operação cancelada."; return 0; }

    local found=0
    for instance_dir in "${SCRIPT_DIR}"/instance_*; do
        [ -d "$instance_dir" ] || continue
        local app_id="${instance_dir##*/instance_}"
        step "Purgando instância: ${app_id}"
        purge_instance "$app_id" || warn "Falha ao purgar ${app_id} — continuando..."
        (( found++ )) || true
    done

    step "Removendo executáveis avulsos..."
    while IFS= read -r f; do remove_file "$f"; done < <(find "${BIN_DIR}" -maxdepth 1 \( -name "claw-*" -o -name "Claw_*.py" \) -type f 2>/dev/null || true)

    step "Removendo atalhos avulsos..."
    while IFS= read -r f; do remove_file "$f"; done < <(find "${APPS_DIR}" -maxdepth 1 -name "Claw_*.desktop" -type f 2>/dev/null || true)

    step "Removendo ícones avulsos..."
    for size in "${ICON_SIZES[@]}"; do
        while IFS= read -r f; do remove_file "$f"; done < <(find "${ICONS_BASE}/${size}x${size}/apps" -maxdepth 1 -name "Claw_*.png" -type f 2>/dev/null || true)
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        update_caches
    fi

    success "═══ Todas as instâncias removidas! (${found} purgadas) ═══"
    echo ""
}

# ── Help ───────────────────────────────────────────────────────────────────────
show_help() {
    cat << HELP_EOF

${B}╔════════════════════════════════════════════════════════╗${N}
${B}║${N}  ${C}Gerenciador de Instâncias Claw Launcher v1.0.4${N}
${B}╚════════════════════════════════════════════════════════╝${N}

${B}Uso:${N}
  $0 [FLAGS] <comando> [opções]

${B}FLAGS GLOBAIS:${N}
  ${C}--dry-run${N}         Simula operação sem deletar nada
  ${C}--verbose${N}         Mostra detalhes extras
  ${C}--no-backup${N}       Não faz backup ao limpar cache

${B}Comandos:${N}
  ${C}list${N}
      Listar todas as instâncias com status e integridade.
      Exemplo: $0 list

  ${C}purge <APP_ID> [FLAGS]${N}
      Remove completamente uma instância.
      Exemplo: $0 purge Claw_ChatGPT
      Exemplo: $0 --dry-run purge Claw_ChatGPT  (simular)

  ${C}clear-caches${N}
      Limpa cache de todas as instâncias (com backup automático).
      Exemplo: $0 clear-caches
      Exemplo: $0 --no-backup clear-caches  (sem backup)

  ${C}uninstall-all${N}
      Desinstala TODAS as instâncias. ${Y}⚠ Irreversível!${N}
      Exemplo: $0 uninstall-all

  ${C}help${N}
      Mostra esta mensagem.

${B}Exemplos Avançados:${N}
  # Testar remoção sem deletar
  $0 --dry-run --verbose purge Claw_ChatGPT

  # Listar com detalhes
  $0 --verbose list

  # Limpar cache sem backup
  $0 --no-backup clear-caches

${B}Arquivos de Log:${N}
  Salvo em: ~/.local/log/manage_instances_YYYYMMDD_HHMMSS.log

${B}Fluxo do projeto:${N}
  create_app.sh          → criar e instalar instâncias
  Claw_Launcher_Linux.sh → instalar/desinstalar instância individual
  manage_instances.sh    → purge, lista, cache em massa
  Claw_Launcher_Linux.py → app em execução

HELP_EOF
}

# ── Parsing de Flags ───────────────────────────────────────────────────────────
parse_global_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)   DRY_RUN=true; shift ;;
            --verbose)   VERBOSE=true; shift ;;
            --no-backup) BACKUP_ON_CLEAR=false; shift ;;
            *)           break ;;
        esac
    done
}

# ── Entry point ────────────────────────────────────────────────────────────────
parse_global_flags "$@"

case "${1:-help}" in
    list)           list_all_instances ;;
    purge)          purge_instance "${2:-}" ;;
    clear-caches)   clear_all_caches ;;
    uninstall-all)  uninstall_all ;;
    help|--help|-h) show_help ;;
    *)
        error "Comando desconhecido: $1"
        show_help
        exit 1
        ;;
esac

log "Operação concluída. Log: $LOG_FILE"