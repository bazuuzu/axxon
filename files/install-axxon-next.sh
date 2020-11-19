#!/bin/sh

AXXONSOFT_REPO_URL=http://download.axxonsoft.com/debian-repository
AXXONSOFT_APT_SOURCE_FILE=/etc/apt/sources.list.d/axxonsoft.list
AXXONSOFT_REPO_SUITE=wheezy
AXXONSOFT_BACKPORTS_SUITE=wheezy

LOG_INFO_CMD="echo I: "
LOG_ERROR_CMD="echo E: "
LOG_WARNING_CMD="echo W: "
log_info () {
    $LOG_INFO_CMD "$@"
}
log_error () {
    $LOG_ERROR_CMD "$@"
}
log_warning () {
    $LOG_WARNING_CMD "$@"
}

#if [ -f /lib/lsb/init-functions ]
#then
#    . /lib/lsb/init-functions
#    LOG_INFO_CMD="log_success_msg"
#    LOG_ERROR_CMD="log_failure_msg "
#    LOG_WARNING_CMD="log_warning_msg"
#fi

init_debian () {
    apt-get update
    install_package wget
    AN_PKGS_TO_INSTALL="axxon-next-db axxon-next" 
    REPO_ARCH=$(dpkg --print-architecture)
}

initialization () {
    if [ "root" != `whoami` ]
    then
        log_error "you must be root to run the script"
        return 1
    fi
    case "${1:-${AXXONSOFT_REPO_SUITE}}" in
        wheezy|wheezy-release|release)
            AXXONSOFT_BACKPORTS_SUITE=wheezy
            AXXONSOFT_REPO_SUITE=wheezy ;;
        wheezy-weekly|weekly)
            AXXONSOFT_BACKPORTS_SUITE=wheezy
            AXXONSOFT_REPO_SUITE=next-weekly ;;
        *)
            log_error "unsupported release plan ($1) was specified. Supported values are: wheezy | wheezy-release | release and  wheezy-weekly | weekly. Default is ${AXXONSOFT_REPO_SUITE}"
            return 1 ;;
    esac
    case `lsb_release -i -s` in
        Debian)
            case `lsb_release -c -s` in
                wheezy|jessie)
                    init_debian
                    return $? ;;
            esac
            ;;
        Ubuntu)
            case `lsb_release -c -s` in
                precise|trusty)
                    init_debian
                    return $? ;;
            esac
            ;;
        AstraLinux*)
            case `lsb_release -c -s` in
                orel|smolensk)
                    init_debian
                    return $? ;;
            esac
            ;;
        *)
            ;;
    esac
    log_error "your OS distribution is not supported by the installation script"
    return 1
}

install_package () {
    log_info "installing package(s) $@ ..."
    apt-get install "$@" </dev/tty
}

prompt_install_package () {
    echo "    apt-get install $@"
}

get_dependency_package_version () {
    apt-cache depends "$1" 2>/dev/null | awk '$1 ~ /:$/ && $2 ~ /'"$2"'[0-9]/ { gsub(/<|>/, "", $2); print substr($2, length("'"$2"'") + 1) }'
}

get_postgresql_minimal_required_version () {
    get_dependency_package_version axxon-next-db postgresql-
}

get_xerces_minimal_required_version () {
    get_dependency_package_version axxon-next libxerces-c
}

is_package_available () {
    for arg #in "$@"
    do
        apt-cache madison "$arg" 2>/dev/null | grep -qw "$arg" || return $?
    done
}

is_postgresql_version_available () {
    log_info "checking minimal required version of PostgreSQL is available..."
    minimal_version=$1
    installed_version=$(dpkg --status postgresql postgresql-${minimal_version} 2>/dev/null | awk '$1 == "Version:" {print $2; exit(0)}')
    if [ -n "${installed_version}" ] && dpkg --compare-versions "${installed_version}" ge "${minimal_version}"
    then
        return 0
    fi
    for available_version in $(apt-cache madison postgresql postgresql-[0-9]* | awk '$1 == "postgresql" || $1 ~ /^postgresql-[0-9]/{ print $3 }')
    do
        pg_ver=$(echo ${available_version} | cut -f1 -d+ | cut -f1,2 -d.)
        if dpkg --compare-versions "${available_version}" ge "${minimal_version}" && is_package_available postgresql-${pg_ver}
        then
            return 0
        fi
    done
    return 1
}

is_axxonsoft_repository_registered () {
    log_info "checking AxxonSoft Debian package repository is registered..."
    grep -q "${AXXONSOFT_REPO_URL}" "${AXXONSOFT_APT_SOURCE_FILE}" 2>/dev/null || return 1
    [ -z "${AXXONSOFT_BACKPORTS_SUITE}" ] || grep -q "backports/main" "${AXXONSOFT_APT_SOURCE_FILE}" 2>/dev/null || return 1
}

register_axxonsoft_repository () {
    log_info "registering AxxonSoft Debian package repository..."
    echo "deb [arch=${REPO_ARCH}] ${AXXONSOFT_REPO_URL} ${AXXONSOFT_REPO_SUITE} main" > "${AXXONSOFT_APT_SOURCE_FILE}"
    [ -z "${AXXONSOFT_BACKPORTS_SUITE}" ] || echo "deb [arch=${REPO_ARCH}] ${AXXONSOFT_REPO_URL} ${AXXONSOFT_BACKPORTS_SUITE} backports/main" >> "${AXXONSOFT_APT_SOURCE_FILE}"
    wget --quiet -O - "${AXXONSOFT_REPO_URL}/info@axxonsoft.com.gpg.key" | apt-key --keyring /etc/apt/trusted.gpg.d/axxonsoft.gpg add -
    apt-get update
}

suggest_postgresql_setup_instructions () {
    minimal_version=$1
    pg_install_sh_url=$(wget --quiet -O - http://wiki.postgresql.org/wiki/Apt | grep -i 'this shell script' | sed 's@^.*[[:space:]]href="\([^\"]\+\)".*$@\1@')
    log_info "Please,${pg_install_sh_url:+ try to run the following command:\n  wget --quiet -O - \"${pg_install_sh_url}\" | $0 -\nor} visit http://wiki.postgresql.org/wiki/Apt for PostgreSQL ${minimal_version} (or newer) detailed installation instructions"
}

register_postgresql_repository () {
    log_info "registering PostgreSQL Debian package repository..."
    install_package ca-certificates
    echo "deb [arch=${REPO_ARCH}] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
    apt-get update
}

get_package_version () {
    dpkg --status "$@"
}

is_mercurial_available () {
    log_info "checking mercurial is available..."
    is_package_available mercurial
}

is_xercesc_version_available () {
    log_info "checking xerces-c $1 is available..."
    is_package_available libxerces-c$1
}

register_wheezy_repository () {
    log_info "registering Debian wheezy package repository..."
    echo "deb [arch=${REPO_ARCH}] http://ftp.debian.org/debian/ wheezy main" > /etc/apt/sources.list.d/debian-wheezy.list &&
    echo "deb [arch=${REPO_ARCH}] http://security.debian.org/ wheezy/updates main" >> /etc/apt/sources.list.d/debian-wheezy.list &&
    echo "Package: *
Pin: release o=Debian,n=wheezy
Pin-Priority: 100" > /etc/apt/preferences.d/debian-wheezy-pinning &&
    #wget --quiet -O - https://ftp-master.debian.org/keys/archive-key-7.0.asc | apt-key add -
    apt-get update &&
    apt-get install debian-keyring -t wheezy </dev/tty
}

register_repository_for_mercurial () {
    log_info "registering Debian package repository for mercurial..."
    register_wheezy_repository
}

register_repository_for_xercesc_version () {
    log_info "registering Debian package repository for xerces-c $1..."
    register_wheezy_repository
}

initialization "$@" || exit $?
is_axxonsoft_repository_registered || register_axxonsoft_repository || exit $?
PG_MIN_VER=$(get_postgresql_minimal_required_version)
if ! is_postgresql_version_available ${PG_MIN_VER}
then
    register_postgresql_repository || exit $?
    if ! is_postgresql_version_available ${PG_MIN_VER}
    then
        log_error "failed to find appropriate PostgreSQL version"
        suggest_postgresql_setup_instructions ${PG_MIN_VER} >&2
        exit 1
    fi
fi
if ! is_mercurial_available
then
    register_repository_for_mercurial || exit $?
    if ! is_mercurial_available
    then
        log_error "mercurial is not available"
        exit 1
    fi
fi
XERCESC_VER=$(get_xerces_minimal_required_version)
if [ -n "$XERCESC_VER" ] && ! is_xercesc_version_available ${XERCESC_VER}
then
    register_repository_for_xercesc_version ${XERCESC_VER} || exit $?
    if ! is_xercesc_version_available ${XERCESC_VER}
    then
        log_error "failed to find package for xerces-c ${XERCESC_VER}"
        exit 1
    fi
fi

if ! install_package ${AN_PKGS_TO_INSTALL}
then
    log_error "Axxon Next installation failed"
    log_info "To re-try the installation please run the following command as root:"
    prompt_install_package ${AN_PKGS_TO_INSTALL}
    exit 1
fi
log_info "Axxon Next installation completed. The following packages has been installed"
get_package_version ${AN_PKGS_TO_INSTALL}
