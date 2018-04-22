if test ! -z "${ARCHER_LAYER_BASH_REQUIRED}"
then
    return 1
fi
ARCHER_LAYER_BASH_REQUIRED=1

archer_core_require archer/core
archer_core_require archer/algorithm
archer_core_require archer/map

ARCHER_LAYER_DIR="${ARCHER_CORE_PWD}/.archer.d/layer"
ARCHER_LAYER_DEFAULT_PREFIX=
# ARCHER_LAYER_PREFIX=
# ARCHER_LAYER_DIR="${ARCHER_CORE_PREFIX_DIR}/etc/archer/layer"

archer_layer_is_absolute() {
    case "${1}" in
        /*) return 0 ;;
    esac
    return 1
}

archer_layer__load_user_config() {
    if test ! -z "${1}" -a -f "${1}/.archer.d/init.bash"
    then
        archer_core_info "loading user config file"
        if source "${1}/.archer.d/init.bash"
        then
            archer_core_info "user config file loaded"
        else
            archer_core_error "user config file loading failure"
            return 1
        fi
    else
        archer_core_error "user config file .archer.d/init.bash not found"
        return 1
    fi
    shift
    if test "$( type -t dotarcher_init )" = "function"
    then
        archer_core_info "dotarcher_init loading"
        if dotarcher_init "${@}"
        then
            archer_core_info "dotarcher_init loaded"
        else
            archer_core_error "dotarcher_init loaded failure"
        fi
    else
        archer_core_error "function dotarcher_init not found in user config file .archer.d/init.bash"
        return 1
    fi
}

archer_layer_load_pwd_user_config() {
    if archer_layer__load_user_config "${ARCHER_CORE_PWD}"
    then
        archer_core_info "ARCHER_LAYER_PREFIX=${ARCHER_LAYER_PREFIX}"
        return 0
    else
        return 1
    fi
}

archer_layer_to_absolute() {
    if ! archer_layer_is_absolute "${1}"
    then
        eval "${2}"='"${ARCHER_LAYER_PREFIX}/${1}"'
    else
        eval "${2}"='"${1}"'
    fi
    eval "${2}"='"$( sed "s@//*@/@g" <<< "${'"${2}"'}" )"'
}

archer_layer_dependencies() {
    # @param
    # 1. [in] (string) layer
    # 2. [out] (array) dependencies
    local __layer="${1}"
    local __deps_var="${2}"
    local __deps_script=
    #
    if test -z "${__deps_var}" || ! archer_layer_exists "${__layer}" __deps_script
    then
        return 1
    fi
    local LAYER=
    local LAYER_DEPENDENCIES=()
    __deps_script="${__deps_script}/metadata.bash"
    if test -f "${__deps_script}"
    then
        source "${__deps_script}"
    fi
    eval "${__deps_var}"='("${LAYER_DEPENDENCIES[@]}")'
}

archer_layer_normalized_dependencies() {
    # 1. [in] (string) layer
    # 2. [out] (array) dependencies
    archer_layer_dependencies "${1}" "${2}"
    archer_layer_normalize_layers "${2}"
}


archer_layer_exists() {
    # @param
    # $1.layer:
    # @result
    local __layer=
    archer_layer_to_absolute "${1}" __layer
    if test ! -z "${2}"
    then
        eval "${2}"='"${ARCHER_LAYER_DIR}${__layer}"'
    fi
    test -f "${ARCHER_LAYER_DIR}${__layer}/metadata.bash"
}

archer_layer_setup() {
    local __layer="${1}"
    local __script=
    if ! archer_layer_exists "${__layer}" __script
    then
        archer_core_warning "cannot find layer: \"${__layer}\""
        return 1
    fi
    __script="${__script}/main.bash"
    archer_core_info "setup layer: ${__layer}"
    source "${__script}"
}

archer_layer_setup_layers() {
    local __layers_var="${1}"
    local __layers=()
    eval __layers='("${'"${__layers_var}"'[@]}")'
    for __layer in "${__layers[@]}"
    do
        archer_layer_setup "${__layer}"
    done
}

archer_layer__exists_with_info() {
    if archer_layer_exists "${@}"
    then
        return 0
    else
        archer_core_warning "cannot find layer: \"${1}\", ignoring"
        return 1
    fi
}

archer_layer_normalize_layers() {
    eval __layers_='("${'"${1}"'[@]}")'
    eval "${1}"='()'
    for __layer in "${__layers_[@]}"
    do
        if archer_layer_to_absolute "${__layer}" __layer
        then
            eval "${1}"+='("${__layer}")'
        fi
    done
}

archer_layer_setup_layers_with_dependencies() {
    local __layers_var="${1}"
    local __layers=()
    local __sorted_=()
    local __cycled_=
    eval __layers='("${'"${__layers_var}"'[@]}")'
    archer_layer_normalize_layers __layers
    archer_core_info "resolving layer dependencies, layers: [${__layers[@]}]"
    archer_algorithm_topo_sort_vertexs __layers archer_layer_normalized_dependencies __sorted_ __cycled_ archer_layer__exists_with_info
    for __layer in "${__sorted_[@]}"
    do
        if archer_map_has_key __cycled_ "${__layer}"
        then
            archer_map_var_at __cycled_ "${__layer}" var
            eval arr='("${'"${var}"'[@]}")'
            archer_core_warning "cyclic depencencies detected, layer ${__layer} will be install before dependent layers (${arr[@]})"
        fi
        archer_core_info "resolved layer: ${__layer}"
    done
    archer_core_info "dependencies resolved" # "with sorted layers [${__sorted_[@]}]."
    archer_layer_setup_layers __sorted_
}

