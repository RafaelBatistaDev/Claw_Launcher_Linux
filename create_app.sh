#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : create_app.sh
# Descrição    : Gerenciador Master OneNote (Instalação de instâncias e limpeza)
# Autor        : Rafael Batista
# Versão       : 1.0.3
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
G="\033[1;32m"; B="\033[1;34m"; Y="\033[1;33m"; R="\033[1;31m"; C="\033[1;36m"; N="\033[0m"

log()     { echo -e "${B}[INFO]${N}    $*"; }
success() { echo -e "${G}[OK]${N}      $*"; }
warn()    { echo -e "${Y}[AVISO]${N}   $*"; }
error()   { echo -e "${R}[ERRO]${N}    $*" >&2; }
step()    { echo -e "${C}[→]${N}       $*"; }
removed() { echo -e "${Y}[DEL]${N}     $*"; }

# ── Configurações Compartilhadas ──────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

ICON_SIZES=(16 32 48 64 128 256)   # Array único — reflete Claw_Launcher_Linux.sh
ICONS_BASE="${REAL_HOME}/.local/share/icons/hicolor"
APPS_DIR="${REAL_HOME}/.local/share/applications"
BIN_DIR="${REAL_HOME}/.local/bin"
LAST_CREATED_FOLDER=""

# ── Helpers Compartilhados (espelham Claw_Launcher_Linux.sh) ──────────────────

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
    update-desktop-database "${APPS_DIR}"       2>/dev/null || true
    gtk-update-icon-cache -f -t "${ICONS_BASE}" 2>/dev/null || true
    if command -v kbuildsycoca6 &>/dev/null; then kbuildsycoca6 --noincremental 2>/dev/null; fi
    if command -v kbuildsycoca5 &>/dev/null; then kbuildsycoca5 --noincremental 2>/dev/null; fi
    success "Caches atualizados."
}

install_uv_if_missing() {
    if ! command -v uv &>/dev/null; then
        step "Instalando uv (gerenciador de pacotes rápido)..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="${REAL_HOME}/.local/bin:${PATH}"
    fi
}

# ── Instâncias ────────────────────────────────────────────────────────────────

get_instances() {
    find "$SCRIPT_DIR" -maxdepth 1 -type d -name "instance_*" | while read -r dir; do
        echo "${dir##*/instance_}"
    done | sort | uniq
}

generate_unique_app_id() {
    local base_id="$1"
    local candidate="$base_id"
    local index=1
    while [ -d "${SCRIPT_DIR}/instance_${candidate}" ]; do
        candidate="${base_id}_${index}"
        index=$((index + 1))
    done
    echo "$candidate"
}

# ── Cache ─────────────────────────────────────────────────────────────────────

clear_app_cache() {
    local app_id="$1"
    local exec_name="claw-$(echo "${app_id#Claw_}" | tr '[:upper:]' '[:lower:]')"

    log "═══ Limpando cache: ${app_id} ═══"

    # Dados de perfil (storage + cache do QtWebEngine)
    step "Removendo dados de perfil..."
    local share_dir="${REAL_HOME}/.local/share/${app_id}"
    if [[ -d "$share_dir" ]]; then
        # Remove individualmente espelhando o que o install cria
        remove_file "${share_dir}/config.json"
        [[ -d "${share_dir}/storage" ]] && { rm -rf "${share_dir}/storage"; removed "${share_dir}/storage/"; }
        [[ -d "${share_dir}/cache"   ]] && { rm -rf "${share_dir}/cache";   removed "${share_dir}/cache/";   }
        rmdir --ignore-fail-on-non-empty "${share_dir}" 2>/dev/null || true
    else
        warn "Sem dados de perfil: ${share_dir}"
    fi

    # Cache XDG separado
    step "Removendo cache XDG..."
    local cache_dir="${REAL_HOME}/.cache/${app_id}"
    if [[ -d "$cache_dir" ]]; then
        rm -rf "$cache_dir"
        removed "${cache_dir}/"
    else
        warn "Sem cache XDG: ${cache_dir}"
    fi

    success "═══ Cache limpo para ${app_id} ═══"
}

select_instance_id() {
    local options=()
    while IFS= read -r line; do
        [ -n "$line" ] && options+=("$line")
    done < <(get_instances)

    if [ ${#options[@]} -eq 0 ]; then
        warn "Nenhuma instância criada para limpar cache." >&2
        return 1
    fi

    echo -e "${B}Instâncias disponíveis:${N}" >&2
    for i in "${!options[@]}"; do
        printf "  %s) %s\n" "$((i+1))" "${options[i]}" >&2
    done
    read -r -p "Escolha a instância (número): " instance_choice >&2

    if [[ "$instance_choice" =~ ^[0-9]+$ ]] && \
       [ "$instance_choice" -ge 1 ] && \
       [ "$instance_choice" -le ${#options[@]} ]; then
        echo "${options[$((instance_choice-1))]}"
        return 0
    fi

    warn "Escolha inválida."
    return 1
}

clear_cache_menu() {
    echo -e "\n${B}Limpar cache de: ${N}"
    echo "  1) OneNote (app principal)"
    echo "  2) Instância criada"
    echo "  0) Cancelar"
    read -r -p "Opção: " cache_opt

    case "$cache_opt" in
        1) clear_app_cache "OneNote" ;;
        2)
            local instance_id
            instance_id=$(select_instance_id) || return
            clear_app_cache "$instance_id"
            ;;
        *) warn "Operação cancelada." ;;
    esac
}

# ── Ícones ────────────────────────────────────────────────────────────────────

list_icon_options() {
    if [ -d "${SCRIPT_DIR}/ICON" ]; then
        find "${SCRIPT_DIR}/ICON" -maxdepth 1 -type f -iname '*.png' | sort | sed 's|.*/||; s/\.png$//'
    fi
}

choose_icon() {
    local preferred_icon="$1"
    local icons=()
    if [ -d "${SCRIPT_DIR}/ICON" ]; then
        mapfile -t icons < <(find "${SCRIPT_DIR}/ICON" -maxdepth 1 -type f -iname '*.png' | sort | sed 's|.*/||; s/\.png$//')
    fi

    if [ -n "$preferred_icon" ] && [ -f "${SCRIPT_DIR}/ICON/${preferred_icon}.png" ]; then
        echo "$preferred_icon"; return 0
    fi

    [ ${#icons[@]} -eq 0 ] && return 1

    echo -e "${B}Ícones disponíveis em ICON/${N}"
    for i in "${!icons[@]}"; do
        printf "  %s) %s\n" "$((i+1))" "${icons[i]}"
    done
    echo "  0) Usar ícone padrão"

    while true; do
        read -r -p "Escolha um ícone por número ou nome (ENTER para padrão): " icon_choice
        [ -z "$icon_choice" ] && return 1
        if [[ "$icon_choice" =~ ^[0-9]+$ ]]; then
            [ "$icon_choice" -eq 0 ] && return 1
            if [ "$icon_choice" -ge 1 ] && [ "$icon_choice" -le ${#icons[@]} ]; then
                echo "${icons[$((icon_choice-1))]}"; return 0
            fi
        fi
        if [ -f "${SCRIPT_DIR}/ICON/${icon_choice}.png" ]; then
            echo "$icon_choice"; return 0
        fi
        warn "Ícone '${icon_choice}' não encontrado."
    done
}

# ── Links ─────────────────────────────────────────────────────────────────────

list_link_options() {
    local list_file="${SCRIPT_DIR}/ICON/Links.txt"
    [ ! -f "$list_file" ] && return
    grep -Eo '^https?://[^[:space:]]+' "$list_file" | sed 's/[[:space:]]*$//; /^[[:space:]]*$/d'
}

choose_link() {
    local options
    mapfile -t options < <(list_link_options)

    if [ ${#options[@]} -gt 0 ]; then
        echo
        echo -e "${B}Links disponíveis em ICON/Links.txt:${N}"
        for i in "${!options[@]}"; do
            printf "  %s) %s\n" "$((i+1))" "${options[i]}"
        done
        echo

        while true; do
            read -r -p "Número, URL ou ENTER para digitar manualmente: " link_choice
            [ -z "$link_choice" ] && { read -r -p "URL do Site: " link_choice; }

            if [[ "$link_choice" =~ ^[0-9]+$ ]] && \
               [ "$link_choice" -ge 1 ] && \
               [ "$link_choice" -le ${#options[@]} ]; then
                echo "${options[$((link_choice-1))]}"; return
            fi

            [[ "$link_choice" =~ ^https?:// ]] && { echo "$link_choice"; return; }
            warn "URL inválida. Use número da lista ou link com http(s)://"
        done
    fi

    read -r -p "URL do Site (ex: https://chat.openai.com): " link_choice
    echo "$link_choice"
}

save_link_option() {
    local url="$1"
    local list_file="${SCRIPT_DIR}/ICON/Links.txt"
    [[ -z "$url" || ! "$url" =~ ^https?:// ]] && return
    mkdir -p "${SCRIPT_DIR}/ICON"
    if [ ! -f "$list_file" ] || ! grep -Fxq "$url" "$list_file"; then
        printf '%s\n' "$url" >> "$list_file"
        success "Link salvo em ICON/Links.txt."
    fi
}

guess_app_name_from_url() {
    local url="$1"
    local host
    host=$(echo "$url" | sed -E 's#^https?://##; s#/.*$##; s/^www\.//i')
    case "$host" in
        *deepseek*)             echo "DeepSeek" ;;
        *github*)               echo "GitHub" ;;
        *mail.google.com*)      echo "Gmail" ;;
        *vscode.dev*)           echo "VSCode" ;;
        *gemini.google.com*)    echo "Gemini" ;;
        *claude.ai*)            echo "Claude" ;;
        *onedrive.live.com*)    echo "OneDrive" ;;
        *netflix.com*)          echo "Netflix" ;;
        *youtube.com*)          echo "YouTube" ;;
        *roblox.com*)           echo "Roblox" ;;
        *myetherwallet.com*)    echo "MyEtherWallet" ;;
        *heliowallet.com*)      echo "HelioWallet" ;;
        *etherscan.io*)         echo "Etherscan" ;;
        *onenote.cloud.microsoft*) echo "OneNote" ;;
        *) echo "$host" | sed -E 's/[^a-zA-Z0-9]+/ /g; s/^ //; s/ $//' ;;
    esac
}

guess_icon_name_from_url() {
    local url="$1"
    local host
    host=$(echo "$url" | sed -E 's#^https?://##; s#/.*$##; s/^www\.//i')
    case "$host" in
        *deepseek*)             echo "deepseek" ;;
        *github*)               echo "github-logo" ;;
        *mail.google.com*)      echo "gmail" ;;
        *vscode.dev*)           echo "vscode" ;;
        *gemini.google.com*)    echo "Gemini" ;;
        *claude.ai*)            echo "claudecode" ;;
        *onedrive.live.com*)    echo "onedrive" ;;
        *netflix.com*)          echo "netflix" ;;
        *youtube.com*)          echo "youtube" ;;
        *roblox.com*)           echo "roblox" ;;
        *myetherwallet.com*)    echo "myetherwallet" ;;
        *heliowallet.com*)      echo "HelioWallet" ;;
        *etherscan.io*)         echo "etherscan" ;;
        *onenote.cloud.microsoft*) echo "onenote" ;;
        *) echo "$host" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' ;;
    esac
}

# ── Criação de Instância ──────────────────────────────────────────────────────

install_new_instance() {
    local raw_name="${1:-}"
    local url="${2:-}"
    local preferred_icon="${3:-}"

    if [ -z "$raw_name" ]; then
        echo -e "${B}Instalando nova instância...${N}"
        read -r -p "Nome do Aplicativo (ex: ChatGPT): " raw_name
    fi

    [ -z "$url" ] && url=$(choose_link)
    if [ -z "$url" ]; then
        error "URL inválida."
        return 1
    fi

    save_link_option "$url"

    local clean_id
    clean_id=$(echo "$raw_name" | sed 's/[^a-zA-Z0-9]/_/g')
    [ -z "$clean_id" ] && { error "Nome inválido."; return 1; }

    local icon_src="${SCRIPT_DIR}/ICON/${clean_id}.png"
    LAST_CREATED_FOLDER=""

    install_uv_if_missing

    # Resolve ícone
    if [ ! -f "$icon_src" ] && [ -n "$preferred_icon" ] && [ -f "${SCRIPT_DIR}/ICON/${preferred_icon}.png" ]; then
        icon_src="${SCRIPT_DIR}/ICON/${preferred_icon}.png"
    fi
    if [ ! -f "$icon_src" ]; then
        local icon_choice
        icon_choice=$(choose_icon "$preferred_icon") || true
        if [ -n "${icon_choice:-}" ] && [ -f "${SCRIPT_DIR}/ICON/${icon_choice}.png" ]; then
            icon_src="${SCRIPT_DIR}/ICON/${icon_choice}.png"
        else
            icon_src=""
        fi
    fi

    local app_id="Claw_${clean_id}"
    app_id=$(generate_unique_app_id "$app_id")
    local exec_name="claw-$(echo "${app_id#Claw_}" | tr '[:upper:]' '[:lower:]')"
    local folder="instance_${app_id}"

    log "═══ Criando instância: ${raw_name} ═══"

    # 1. Pasta da instância
    step "Criando pasta da instância..."
    mkdir -p "${SCRIPT_DIR}/${folder}"
    success "Pasta: ${SCRIPT_DIR}/${folder}"

    # 2. Script Python
    step "Copiando script Python..."
    cp "${SCRIPT_DIR}/Claw_Launcher_Linux.py" "${SCRIPT_DIR}/${folder}/"
    sed -i "s|^APP_ID[[:space:]]*=.*|APP_ID   = \"${app_id}\"|"  "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"
    sed -i "s|^APP_NAME[[:space:]]*=.*|APP_NAME = \"${raw_name}\"|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"
    sed -i "s|^URL[[:space:]]*=.*|URL      = \"${url}\"|"         "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"
    success "Script Python configurado."

    # 3. Script shell
    step "Copiando script shell..."
    cp "${SCRIPT_DIR}/Claw_Launcher_Linux.sh" "${SCRIPT_DIR}/${folder}/"
    sed -i "s/^APP_ID=.*/APP_ID=\"${app_id}\"/"       "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"
    sed -i "s/^EXEC_NAME=.*/EXEC_NAME=\"${exec_name}\"/" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"
    sed -i "s/^APP_NAME=.*/APP_NAME=\"${raw_name}\"/"  "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"
    success "Script shell configurado."

    # 4. Ícone
    step "Copiando ícone..."
    if [ -n "${icon_src}" ] && [ -f "${icon_src}" ]; then
        cp "${icon_src}" "${SCRIPT_DIR}/${folder}/${app_id}.png"
        success "Ícone: ${app_id}.png"
    elif [ -f "${SCRIPT_DIR}/Claw_Launcher_Linux-256.png" ]; then
        cp "${SCRIPT_DIR}/Claw_Launcher_Linux-256.png" "${SCRIPT_DIR}/${folder}/${app_id}.png"
        warn "Ícone padrão usado."
    else
        warn "Nenhum ícone disponível."
    fi

    # 5. Arquivo .desktop
    step "Copiando .desktop..."
    if [ -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" ]; then
        cp "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" "${SCRIPT_DIR}/${folder}/"
        sed -i "s|^Name=.*|Name=${raw_name}|"                          "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Comment=.*|Comment=${raw_name} - Dashboard IA|"     "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Exec=.*|Exec=${exec_name} %U|"                      "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Icon=.*|Icon=${app_id}|"                            "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^StartupWMClass=.*|StartupWMClass=${app_id}|"        "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        success "Arquivo .desktop configurado."
    else
        warn "Arquivo .desktop não encontrado."
    fi

    # 6. pyproject.toml para UV workspace
    step "Gerando pyproject.toml..."
    cat > "${SCRIPT_DIR}/${folder}/pyproject.toml" << TOML
[project]
name = "${app_id,,}"
version = "0.1.0"
requires-python = ">=3.9"
dependencies = []
TOML
    success "pyproject.toml criado."

    # 7. Sincronização UV
    step "Sincronizando Workspace UV..."
    uv sync --project "$(dirname "$(readlink -f "$0")")"
    success "Workspace sincronizado."

    LAST_CREATED_FOLDER="$folder"
    success "═══ Instância '${raw_name}' pronta! ═══"
    echo -e "Para instalar: ${C}cd ${folder} && ./Claw_Launcher_Linux.sh --install${N}"
}

# ── App Pré-configurado ───────────────────────────────────────────────────────

create_preconfigured_app() {
    local options
    mapfile -t options < <(list_link_options)

    if [ ${#options[@]} -eq 0 ]; then
        warn "Nenhum link pré-configurado em ICON/Links.txt."
        return
    fi

    echo
    echo -e "${B}Apps pré-configurados disponíveis:${N}"
    for i in "${!options[@]}"; do
        local url="${options[i]}"
        local title
        title=$(guess_app_name_from_url "$url")
        printf "  %s) %s\n      %s\n" "$((i+1))" "$title" "$url"
    done
    echo "  0) Cancelar"
    echo

    read -r -p "Escolha o app: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#options[@]} ]; then
        local url="${options[$((choice-1))]}"
        local raw_name icon_name
        raw_name=$(guess_app_name_from_url "$url")
        icon_name=$(guess_icon_name_from_url "$url")

        if install_new_instance "$raw_name" "$url" "$icon_name"; then
            if [ -n "$LAST_CREATED_FOLDER" ] && \
               [ -x "${SCRIPT_DIR}/${LAST_CREATED_FOLDER}/Claw_Launcher_Linux.sh" ]; then
                step "Instalando app pré-configurado no sistema..."
                (cd "${SCRIPT_DIR}/${LAST_CREATED_FOLDER}" && ./Claw_Launcher_Linux.sh --install)
                success "App '${raw_name}' criado e instalado."
            else
                warn "App criado mas não instalado automaticamente."
            fi
        fi
    else
        warn "Operação cancelada."
    fi
}

# ── Instalar / Desinstalar Instância ──────────────────────────────────────────

install_instance() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local options=()
        while IFS= read -r line; do [ -n "$line" ] && options+=("$line"); done < <(get_instances)
        [ ${#options[@]} -eq 0 ] && { warn "Nenhuma instância criada."; return; }
        select opt in "${options[@]}" "Cancelar"; do
            [[ "$opt" == "Cancelar" || -z "$opt" ]] && return
            name=$opt; break
        done
    fi

    local folder="${SCRIPT_DIR}/instance_${name}"
    if [ -d "$folder" ] && [ -x "$folder/Claw_Launcher_Linux.sh" ]; then
        step "Instalando ${name}..."
        (cd "$folder" && ./Claw_Launcher_Linux.sh --install)
    else
        error "Pasta não encontrada: $folder"
    fi
}

uninstall_instance() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local options=()
        while IFS= read -r line; do [ -n "$line" ] && options+=("$line"); done < <(get_instances)
        [ ${#options[@]} -eq 0 ] && { warn "Nenhuma instância encontrada."; return; }
        echo -e "${B}Selecione a instância para desinstalar:${N}"
        select opt in "${options[@]}" "Cancelar"; do
            [[ "$opt" == "Cancelar" || -z "$opt" ]] && return
            name=$opt; break
        done
    fi

    local folder="${SCRIPT_DIR}/instance_${name}"
    if [ -d "$folder" ] && [ -x "$folder/Claw_Launcher_Linux.sh" ]; then
        step "Desinstalando ${name} do sistema..."
        (cd "$folder" && ./Claw_Launcher_Linux.sh --uninstall)
        success "Desinstalação concluída: ${name}"

        read -r -p "Deletar também a pasta de origem? (s/N): " del_folder
        if [[ "$del_folder" =~ ^[Ss]$ ]]; then
            rm -rf "$folder"
            removed "${folder}/"
        fi
    else
        error "Pasta ou script não encontrado: $folder"
    fi
}

list_all() {
    echo -e "${B}Instâncias disponíveis:${N}"
    local found=0
    while IFS= read -r name; do
        [ -n "$name" ] && { echo "  • instance_${name}"; found=1; }
    done < <(get_instances)
    [ $found -eq 0 ] && warn "Nenhuma instância criada."
}

# ── Menu ──────────────────────────────────────────────────────────────────────

show_menu() {
    echo -e "\n${B}╔════════════════════════════════════════════════════════╗${N}"
    echo -e "${B}║${N}          ${C}GERENCIADOR MASTER ONENOTE${N}            ${B}║${N}"
    echo -e "${B}╚════════════════════════════════════════════════════════╝${N}"
    echo "  1. Instalar app pré-configurado (Links.txt)"
    echo "  2. Instalar nova instância"
    echo "  3. Desinstalar instância"
    echo "  4. Listar instâncias"
    echo "  5. Instalar OneNote (app principal)"
    echo "  6. Desinstalar OneNote (app principal)"
    echo "  7. Limpar cache (OneNote / instância)"
    echo "  0. Sair"
    echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────

if [ $# -gt 0 ]; then
    case "$1" in
        create|install-new)             install_new_instance "${2:-}" "${3:-}" "${4:-}" ;;
        preconfigured|create-preconfigured) create_preconfigured_app ;;
        install)                        install_instance "${2:-}" ;;
        uninstall)                      uninstall_instance "${2:-}" ;;
        list)                           list_all ;;
        *) error "Uso: $0 {create|install-new|preconfigured|install|uninstall|list}"; exit 1 ;;
    esac
else
    while true; do
        show_menu
        read -r -p "Opção: " opt
        case "$opt" in
            1) install_uv_if_missing; create_preconfigured_app ;;
            2) install_uv_if_missing; install_new_instance ;;
            3) uninstall_instance ;;
            4) list_all ;;
            5) install_uv_if_missing; bash "$SCRIPT_DIR/Claw_Launcher_Linux.sh" --install ;;
            6) bash "$SCRIPT_DIR/Claw_Launcher_Linux.sh" --uninstall ;;
            7) clear_cache_menu ;;
            0) exit 0 ;;
            *) warn "Opção inválida" ;;
        esac
    done
fi