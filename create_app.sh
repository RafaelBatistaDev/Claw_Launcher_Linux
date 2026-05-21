#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Script       : create_app.sh
# Descrição    : Gerenciador Master OneNote (Instalação de instâncias e limpeza)
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

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REAL_HOME="${HOME}"
[[ -n "${SUDO_USER:-}" ]] && REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
LAST_CREATED_FOLDER=""

# ── Funções de Auxílio ────────────────────────────────────────────────────────

get_instances() {
    # Retorna o ID real da instância baseado no nome da pasta (o que vem após 'instance_')
    # Isso garante que pegamos o nome exato para as operações de desinstalação e cache.
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

clear_app_cache() {
    local app_id="$1"
    local share_dir="${REAL_HOME}/.local/share/${app_id}"
    local cache_dir="${REAL_HOME}/.cache/${app_id}"
    local removed=0

    for d in "$share_dir" "$cache_dir"; do
        if [ -d "$d" ]; then
            step "Removendo dados em: $d"
            rm -rf "$d"
            removed=1
        fi
    done

    if [ $removed -eq 1 ]; then
        success "Cache limpo para ${app_id}."
    else
        warn "Nenhum cache encontrado para ${app_id}."
    fi
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

    if [[ "$instance_choice" =~ ^[0-9]+$ ]] && [ "$instance_choice" -ge 1 ] && [ "$instance_choice" -le ${#options[@]} ]; then
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
        1)
            clear_app_cache "OneNote"
            ;;
        2)
            local instance_id
            instance_id=$(select_instance_id) || return
            clear_app_cache "$instance_id"
            ;;
        *)
            warn "Operação cancelada."
            ;;
    esac
}

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
        echo "$preferred_icon"
        return 0
    fi

    if [ ${#icons[@]} -eq 0 ]; then
        return 1
    fi

    echo -e "${B}Ícones disponíveis em ICON/${N}"
    for i in "${!icons[@]}"; do
        printf "  %s) %s\n" "$((i+1))" "${icons[i]}"
    done
    echo "  0) Usar ícone padrão"

    while true; do
        read -r -p "Escolha um ícone por número ou nome do arquivo (ENTER para padrão): " icon_choice
        if [ -z "$icon_choice" ]; then
            return 1
        fi
        if [[ "$icon_choice" =~ ^[0-9]+$ ]]; then
            if [ "$icon_choice" -eq 0 ]; then
                return 1
            fi
            if [ "$icon_choice" -ge 1 ] && [ "$icon_choice" -le ${#icons[@]} ]; then
                echo "${icons[$((icon_choice-1))]}"
                return 0
            fi
        fi
        if [ -f "${SCRIPT_DIR}/ICON/${icon_choice}.png" ]; then
            echo "$icon_choice"
            return 0
        fi
        echo -e "${Y}Ícone '${icon_choice}' não encontrado. Use o número da lista ou o nome do arquivo sem extensão.${N}"
    done
}

list_link_options() {
    local list_file="${SCRIPT_DIR}/ICON/Links.txt"
    if [ ! -f "$list_file" ]; then
        return
    fi

    grep -Eo '^https?://[^[:space:]]+' "$list_file" | sed 's/[[:space:]]*$//' | sed '/^[[:space:]]*$/d'
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
            read -r -p "Digite um número, cole um URL novo ou ENTER para digitar manualmente: " link_choice

            if [ -z "$link_choice" ]; then
                read -r -p "URL do Site (ex: https://chat.openai.com): " link_choice
            fi

            if [[ "$link_choice" =~ ^[0-9]+$ ]] && [ "$link_choice" -ge 1 ] && [ "$link_choice" -le ${#options[@]} ]; then
                echo "${options[$((link_choice-1))]}"
                return
            fi

            if [[ "$link_choice" =~ ^https?:// ]]; then
                echo "$link_choice"
                return
            fi

            echo -e "${Y}URL inválida. Digite um número válido ou cole um link começando com http:// ou https://.${N}"
        done
    fi

    read -r -p "URL do Site (ex: https://chat.openai.com): " link_choice
    echo "$link_choice"
}

save_link_option() {
    local url="$1"
    local list_file="${SCRIPT_DIR}/ICON/Links.txt"

    if [ -z "$url" ] || [[ ! "$url" =~ ^https?:// ]]; then
        return
    fi

    mkdir -p "${SCRIPT_DIR}/ICON"
    if [ ! -f "$list_file" ] || ! grep -Fxq "$url" "$list_file"; then
        printf '%s\n' "$url" >> "$list_file"
        success "Link salvo automaticamente em ICON/Links.txt."
    fi
}

guess_app_name_from_url() {
    local url="$1"
    local host
    host=$(echo "$url" | sed -E 's#^https?://##; s#/.*$##; s/^www\.//i')
    case "$host" in
        *deepseek*) echo "DeepSeek" ;;
        *github*) echo "GitHub" ;;
        *mail.google.com*) echo "Gmail" ;;
        *vscode.dev*) echo "VSCode" ;;
        *gemini.google.com*) echo "Gemini" ;;
        *claude.ai*) echo "Claude" ;;
        *onedrive.live.com*) echo "OneDrive" ;;
        *netflix.com*) echo "Netflix" ;;
        *youtube.com*) echo "YouTube" ;;
        *roblox.com*) echo "Roblox" ;;
        *myetherwallet.com*) echo "MyEtherWallet" ;;
        *heliowallet.com*) echo "HelioWallet" ;;
        *etherscan.io*) echo "Etherscan" ;;
        *onenote.cloud.microsoft*) echo "OneNote" ;;
        *)
            echo "$host" | sed -E 's/[^a-zA-Z0-9]+/ /g' | sed -E 's/^ //; s/ $//'
            ;;
    esac
}

guess_icon_name_from_url() {
    local url="$1"
    local host
    host=$(echo "$url" | sed -E 's#^https?://##; s#/.*$##; s/^www\.//i')
    case "$host" in
        *deepseek*) echo "deepseek" ;;
        *github*) echo "github-logo" ;;
        *mail.google.com*) echo "gmail" ;;
        *vscode.dev*) echo "vscode" ;;
        *gemini.google.com*) echo "Gemini" ;;
        *claude.ai*) echo "claudecode" ;;
        *onedrive.live.com*) echo "onedrive" ;;
        *netflix.com*) echo "netflix" ;;
        *youtube.com*) echo "youtube" ;;
        *roblox.com*) echo "roblox" ;;
        *myetherwallet.com*) echo "myetherwallet" ;;
        *heliowallet.com*) echo "HelioWallet" ;;
        *etherscan.io*) echo "etherscan" ;;
        *onenote.cloud.microsoft*) echo "onenote" ;;
        *)
            echo "$host" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g'
            ;;
    esac
}

create_preconfigured_app() {
    local options
    mapfile -t options < <(list_link_options)

    if [ ${#options[@]} -eq 0 ]; then
        warn "Nenhum link pré-configurado encontrado em ICON/Links.txt."
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

    read -r -p "Escolha o app para criar e instalar automaticamente: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#options[@]} ]; then
        local url="${options[$((choice-1))]}"
        local raw_name
        raw_name=$(guess_app_name_from_url "$url")
        local icon_name
        icon_name=$(guess_icon_name_from_url "$url")
        if install_new_instance "$raw_name" "$url" "$icon_name"; then
            if [ -n "$LAST_CREATED_FOLDER" ] && [ -x "${SCRIPT_DIR}/${LAST_CREATED_FOLDER}/Claw_Launcher_Linux.sh" ]; then
                step "Instalando app pré-configurado..."
                (cd "${SCRIPT_DIR}/${LAST_CREATED_FOLDER}" && ./Claw_Launcher_Linux.sh --install)
                success "App pré-configurado '$raw_name' criado e instalado com sucesso."
            else
                warn "App criado, mas não foi possível instalar automaticamente."
            fi
        fi
    else
        warn "Operação cancelada."
    fi
}

# ── Funções Principais ────────────────────────────────────────────────────────

install_new_instance() {
    local raw_name="${1:-}"
    local url="${2:-}"
    local preferred_icon="${3:-}"

    if [ -z "$raw_name" ]; then
        echo -e "${B}Instalando nova instância...${N}"
        read -p "Nome do Aplicativo (ex: ChatGPT): " raw_name
    fi

    if [ -z "$url" ]; then
        url=$(choose_link)
    fi

    if [ -z "$url" ]; then
        error "URL inválida. Escolha um link válido ou informe uma URL."
        return 1
    fi
    
    save_link_option "$url"

    local clean_id=$(echo "$raw_name" | sed 's/[^a-zA-Z0-9]/_/g')
    if [ -z "$clean_id" ]; then
        error "Nome inválido. Use letras ou números para gerar o ID da instância."
        return 1
    fi

    local icon_filename="${clean_id}.png"
    local icon_src="${SCRIPT_DIR}/ICON/${icon_filename}"
    local icon_choice=""
    LAST_CREATED_FOLDER=""

    if [ ! -f "$icon_src" ] && [ -n "$preferred_icon" ] && [ -f "${SCRIPT_DIR}/ICON/${preferred_icon}.png" ]; then
        icon_src="${SCRIPT_DIR}/ICON/${preferred_icon}.png"
    fi

    if [ ! -f "$icon_src" ]; then
        local icon_choice
        icon_choice=$(choose_icon "$preferred_icon") || true
        if [ -n "$icon_choice" ] && [ -f "${SCRIPT_DIR}/ICON/${icon_choice}.png" ]; then
            icon_src="${SCRIPT_DIR}/ICON/${icon_choice}.png"
        else
            icon_src=""
        fi
    fi

    local app_id="Claw_${clean_id}"
    app_id=$(generate_unique_app_id "$app_id")
    local exec_name="claw-$(echo "${app_id#Claw_}" | tr '[:upper:]' '[:lower:]')"
    local folder="instance_${app_id}"

    step "Configurando arquivos em $folder..."
    mkdir -p "${SCRIPT_DIR}/${folder}"

    # Copia os arquivos base para a nova pasta
    cp "${SCRIPT_DIR}/Claw_Launcher_Linux.py" "${SCRIPT_DIR}/${folder}/"
    cp "${SCRIPT_DIR}/Claw_Launcher_Linux.sh" "${SCRIPT_DIR}/${folder}/"
    [ -f "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" ] && cp "${SCRIPT_DIR}/Claw_Launcher_Linux.desktop" "${SCRIPT_DIR}/${folder}/"

    if [ -n "${icon_src}" ] && [ -f "${icon_src}" ]; then
        cp "${icon_src}" "${SCRIPT_DIR}/${folder}/${app_id}.png"
    elif [ -f "${SCRIPT_DIR}/Claw_Launcher_Linux-256.png" ]; then
        cp "${SCRIPT_DIR}/Claw_Launcher_Linux-256.png" "${SCRIPT_DIR}/${folder}/${app_id}.png"
    fi

    # Atualiza as variáveis nos scripts da instância
    sed -i "s/^APP_ID=.*/APP_ID=\"${app_id}\"/" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"
    sed -i "s/^EXEC_NAME=.*/EXEC_NAME=\"${exec_name}\"/" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"
    sed -i "s/^APP_NAME=.*/APP_NAME=\"${raw_name}\"/" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.sh"

    sed -i "s|^APP_ID[[:space:]]*=.*|APP_ID   = \"${app_id}\"|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"
    sed -i "s|^APP_NAME[[:space:]]*=.*|APP_NAME = \"${raw_name}\"|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"
    sed -i "s|^URL[[:space:]]*=.*|URL      = \"${url}\"|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.py"

    if [ -f "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop" ]; then
        sed -i "s|^Name=.*|Name=${raw_name}|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Comment=.*|Comment=${raw_name} - Dashboard IA|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Exec=.*|Exec=${exec_name} %U|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^Icon=.*|Icon=${app_id}|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
        sed -i "s|^StartupWMClass=.*|StartupWMClass=${app_id}|" "${SCRIPT_DIR}/${folder}/Claw_Launcher_Linux.desktop"
    fi

    LAST_CREATED_FOLDER="$folder"
    success "Instância '$raw_name' preparada com sucesso!"
    echo -e "Para instalar, execute: ${C}cd $folder && ./Claw_Launcher_Linux.sh --install${N}"
}

install_instance() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        echo -e "${B}Selecione a instância para instalar:${N}"
        local options=()
        while IFS= read -r line; do [ -n "$line" ] && options+=("$line"); done < <(get_instances)

        if [ ${#options[@]} -eq 0 ]; then warn "Nenhuma instância criada."; return; fi
        select opt in "${options[@]}" "Cancelar"; do
            if [ "$opt" == "Cancelar" ] || [ -z "$opt" ]; then return; fi
            name=$opt; break
        done
    fi

    local folder="${SCRIPT_DIR}/instance_${name}"
    if [ -d "$folder" ] && [ -x "$folder/Claw_Launcher_Linux.sh" ]; then
        step "Instalando $name..."
        (cd "$folder" && ./Claw_Launcher_Linux.sh --install)
    else
        error "Pasta da instância não encontrada: $folder"
    fi
}

uninstall_instance() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local options=()
        while IFS= read -r line; do
            [ -n "$line" ] && options+=("$line")
        done < <(get_instances)

        echo -e "${B}Selecione a instância para desinstalar:${N}"
        if [ ${#options[@]} -eq 0 ]; then warn "Nenhuma pasta de instância ('instance_*') encontrada."; return; fi
        select opt in "${options[@]}" "Cancelar"; do
            if [ "$opt" == "Cancelar" ] || [ -z "$opt" ]; then return; fi
            name=$opt; break
        done
    fi

    local folder="${SCRIPT_DIR}/instance_${name}"
    if [ -d "$folder" ] && [ -x "$folder/Claw_Launcher_Linux.sh" ]; then
        step "Removendo $name do sistema..."
        (cd "$folder" && ./Claw_Launcher_Linux.sh --uninstall)
        success "Desinstalação concluída para $name."
        read -p "Deseja também deletar a pasta de origem? (s/N): " del_folder
        [[ "$del_folder" =~ ^[Ss]$ ]] && rm -rf "$folder" && success "Pasta deletada."
    else
        # Tenta via manage_instances para uma remoção completa (purge) caso a pasta não exista ou para garantir limpeza
        if [ -f "${SCRIPT_DIR}/manage_instances.sh" ]; then
            bash "${SCRIPT_DIR}/manage_instances.sh" purge "${name}"
        else
            error "Não foi possível localizar a pasta ou o script de gerenciamento: $folder"
        fi
    fi
}

list_all() {
    if [ -f "${SCRIPT_DIR}/manage_instances.sh" ]; then
        "${SCRIPT_DIR}/manage_instances.sh" list
    else
        echo -e "${B}Pastas de Instâncias Disponíveis:${N}"
        get_instances
    fi
}

# ── Menu / Argumentos ─────────────────────────────────────────────────────────

show_menu() {
    echo -e "\n${B}╔════════════════════════════════════════════════════════╗${N}"
    echo -e "${B}║${N}          ${C}GERENCIADOR MASTER ONENOTE${N}            ${B}║${N}"
    echo -e "${B}╚════════════════════════════════════════════════════════╝${N}"
    echo "  1. Instalar app pré-configurado (Links.txt)"
    echo "  2. Instalar nova instância"
    echo "  3. Desinstalar instância"
    echo "  4. Listar tudo e Ver Status"
    echo "  5. Instalar OneNote (app principal)"
    echo "  6. Desinstalar OneNote (app principal)"
    echo "  7. Limpar cache (OneNote / instância)"
    echo "  0. Sair"
    echo ""
}

if [ $# -gt 0 ]; then
    case "$1" in
        create|install-new)    install_new_instance "${2:-}" "${3:-}" "${4:-}" ;;
        preconfigured|create-preconfigured) create_preconfigured_app ;;
        install)              install_instance "${2:-}" ;;
        uninstall)            uninstall_instance "${2:-}" ;;
        list)                 list_all ;;
        *)                    error "Uso: $0 {create|install-new|install|uninstall|list}"; exit 1 ;;
    esac
else
    while true; do
        show_menu
        read -p "Opção: " opt
        case "$opt" in
            1) create_preconfigured_app ;;
            2) install_new_instance ;;
            3) uninstall_instance ;;
            4) list_all ;;
            5) ./Claw_Launcher_Linux.sh --install ;;
            6) ./Claw_Launcher_Linux.sh --uninstall ;;
            7) clear_cache_menu ;;
            0) exit 0 ;;
            *) warn "Opção inválida" ;;
        esac
    done
fi
