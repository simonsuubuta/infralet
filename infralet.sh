#!/usr/bin/env bash
# set -u

export INFRALET_VERSION="0.0.6"
export RUN_PATH="$(pwd)"
export RUN_MODULE=""
export RUN_MODULE_LOCATION=""

#
# Printing colored text
# @param $1 expression
# @param $2 color
# @param $3 arrow
# @return void
#
colored_echo() {

    local MESSAGE="$1";
    local COLOR="$2";
    local ARROW="$3";

    if ! [[ $COLOR =~ '^[0-9]$' ]] ; then
       case $(echo $COLOR | tr '[:upper:]' '[:lower:]') in
        black) COLOR=0 ;;
        red) COLOR=1 ;;
        green) COLOR=2 ;;
        yellow) COLOR=3 ;;
        blue) COLOR=4 ;;
        magenta) COLOR=5 ;;
        cyan) COLOR=6 ;;
        white|*) COLOR=7 ;; # white or invalid color
       esac
    fi

    tput bold;
    tput setaf "$COLOR";
    echo "$ARROW $MESSAGE";
    tput sgr0;

}

#
# Print info message
# @param $1 message
# @return void
#
info() {
    colored_echo "$1" blue "=>"
}

#
# Print warning message
# @param $1 message
# @return void
#
warning() {
    colored_echo "$1" yellow "=>"
}

#
# Print success message
# @param $1 message
# @return void
#
success() {
    colored_echo "$1" green "=>"
}

#
# Print error message
# @param $1 message
# @return void
#
error() {
    colored_echo "$1" red "=>"
}

#
# Ask for a response
# @param $1 variable name
# @param $2 default value
# @param $3 question
# @return something
#
ask() {

    local VARIABLE="$1"
    local DEFAULT="$2"
    local QUESTION="$3"
    local EXTRA=""

    if [ $DEFAULT != "" ]; then
        EXTRA=" [Default: $DEFAULT]"
    fi

    if [[ ${!VARIABLE} == "" ]] ; then
        read -p "$QUESTION$EXTRA: " ANWSER
        ANWSER="${ANWSER:-${DEFAULT}}"
        export "$VARIABLE=$ANWSER"
    fi

}

#
# Ask for a yes/no response
# @param $1 variable name
# @param $2 default value
# @param $3 question
# @return false if N, true if Y
#
ask_yes_no() {

    local VARIABLE="$1"
    local DEFAULT="$2"
    local QUESTION="$3"

    while true; do
        ask $VARIABLE $DEFAULT "$QUESTION (Y/N)"
        case ${!VARIABLE} in
            [Yy]*) export "$VARIABLE=Y"; return 0 ;;
            [Nn]*) export "$VARIABLE=N"; return 1 ;;
        esac
    done

}

#
# Ask for sudo password
# @return void
#
ask_sudo_password() {

    if [ ${EUID:-$(id -u)} -eq 0 ]; then
        success "Sudo credentials OK."
    else
        error "Running as not sudo, please use: sudo infralet [command]..."
        exit 1;
    fi

}

#
# Copy file to a location
# Also replace variables inside a file
# and append a warning comment on header file if necessary
# @see envsubst
# @param $1 source
# @param $2 destination
# @param $3 comment format or false
# @return void
#
copy() {

    local SOURCE="$1"
    local DESTINATION="$2"
    local COMMENT="$3"
    local OVERWRITTEN=""

    if [ -z "$COMMENT" ]; then
        COMMENT='#'
    fi

    if [ ! -f "$SOURCE" ]; then
        error "Copy failed. Source file does not exists: $SOURCE"
        exit 1;
    fi

    if [ -e "$DESTINATION" ] || [ -h "$DESTINATION" ]; then
        OVERWRITTEN="(Overwritten)"
        if ! rm -r "$DESTINATION"; then
            error "Copy error. Failed to remove existing file(s) at $DESTINATION."
            exit 1;
        fi
    fi

    if cp "$SOURCE" "$DESTINATION"; then
        success "Copied $SOURCE to $DESTINATION. $OVERWRITTEN"
    else
        error "Copy of $SOURCE to $DESTINATION failed."
        exit 1;
    fi

    if [ $COMMENT != false ]; then
    cat <<< "$COMMENT ***************
$COMMENT Warning: this is a file auto-generated by infralet.
$COMMENT Do not edit it. Instead, edit the source file located at:
$COMMENT $SOURCE
$COMMENT ***************
$(cat $DESTINATION)" > "$DESTINATION"
    fi

    local TEMPORARY="/tmp/.infralet"
    envsubst < $DESTINATION > $TEMPORARY && mv $TEMPORARY $DESTINATION

}

#
# Append content on file
# Also replace variables inside the file
# @param $1 source
# @param $2 destination
# @return void
#
append() {

    local SOURCE="$1"
    local DESTINATION="$2"
    local TEMPORARY="/tmp/.infralet"

    if [ ! -f "$SOURCE" ]; then
        error "Append failed. Source file does not exists: $SOURCE"
        exit 1;
    fi

    if [ ! -f "$DESTINATION" ]; then
        error "Append failed. Destination file does not exists: $DESTINATION"
        exit 1;
    fi

    envsubst < $SOURCE > $TEMPORARY && \
    cat $TEMPORARY >> $DESTINATION && \
    rm $TEMPORARY

    success "Content of $SOURCE added to $DESTINATION."

}

#
# Make symbolic link
# @param $1 source
# @param $2 destination
# @return void
#
symlink() {

    local SOURCE="$1"
    local DESTINATION="$2"
    local OVERWRITTEN=""

    if [ ! -f "$SOURCE" ]; then
        error "Symlink failed. Source file does not exists: $SOURCE"
        exit 1;
    fi

    if [ -e "$DESTINATION" ] || [ -h "$DESTINATION" ]; then
        OVERWRITTEN="(Overwritten)"
        if ! rm -r "$DESTINATION"; then
            error "Symlink error. Failed to remove existing file(s) at $DESTINATION."
            exit 1;
        fi
    fi

    if ln -s "$SOURCE" "$DESTINATION"; then
        success "Symlinked $DESTINATION to $SOURCE. $OVERWRITTEN"
    else
        error "Symlinking $DESTINATION to $SOURCE failed."
        exit 1;
    fi

}

#
# Print the version message
# @return void
#
version() {
    echo "Infralet version $INFRALET_VERSION"
}

#
# Print the help message
# @return void
#
help() {

    echo ""
    echo "Whatever you do, infralet it!"
    echo ""
    echo "infralet version - See the program version"
    echo "infralet help - Print this help message"
    echo ""
    echo "infralet install [module] - Install a user defined module"
    echo "infralet upgrade [module] - Upgrade a user defined module"
    echo ""

}

#
# Activate the variables file
# @param $1 module
# @param $2 variables file
# @return void
#
activate_variables() {

    local MODULE="$1"
    local FILE_LOCATION="$2"
    local FILE="variables.env"

    if [ -z "$FILE_LOCATION" ]; then
        if [ -f "$RUN_MODULE_LOCATION/$FILE" ]; then
            FILE_LOCATION="$RUN_MODULE_LOCATION/$FILE"
        else
            FILE_LOCATION="$RUN_PATH/$FILE"
        fi
    fi

    if [ ! -f "$FILE_LOCATION" ]; then
        error "No $FILE found. You must create or tell the $FILE file."
        exit 1;
    else
        info "Using the $FILE file located at: $FILE_LOCATION"
    fi

    source $FILE_LOCATION

}

#
# Install a module
# @param $1 module
# @param $2 variables file
# @return void
#
install() {

    local MODULE="$1"
    local VARIABLES="$2"
    local FILE="install.infra"
    local LOCATION="$RUN_PATH/$MODULE"

    if [ -z "$MODULE" ]; then
        error "You must tell the module to be installed."
        exit 1;
    fi

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION/$FILE"

    RUN_MODULE="$MODULE"
    RUN_MODULE_LOCATION="$LOCATION"

    activate_variables $MODULE $VARIABLES
    cd $LOCATION && source $FILE

    success "Module installation completed."
    exit 0

}

#
# Upgrade a module
# @param $1 module
# @param $2 variables file
# @return void
#
upgrade() {

    local MODULE="$1"
    local VARIABLES="$2"
    local FILE="upgrade.infra"
    local LOCATION="$RUN_PATH/$MODULE"

    if [ -z "$MODULE" ]; then
        error "You must tell the module to be upgraded."
        exit 1;
    fi

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION/$FILE"

    RUN_MODULE="$MODULE"
    RUN_MODULE_LOCATION="$LOCATION"

    activate_variables $MODULE $VARIABLES
    cd $LOCATION && source $FILE

    success "Module upgrade completed."
    exit 0

}

if [[ $1 =~ ^(version|help|install|upgrade)$ ]]; then
    "$@"
else
    echo "Invalid infralet subcommand: $1" >&2
    exit 1
fi