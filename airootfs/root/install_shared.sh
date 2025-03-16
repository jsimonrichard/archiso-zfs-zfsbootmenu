#!/bin/bash

# Shared functions and variables
if [[ -z "$PROGRESS_FILE" ]]; then
    PROGRESS_FILE="/tmp/install_progress"
fi
LAST_COMPLETED_STEP=0

# Common required variables
COMMON_REQUIRED_VARS=("HOSTNAME" "TIMEZONE" "USERNAME")

print_step() {
    local blue='\033[0;34m'
    local reset='\033[0m'
    echo -e "${blue}==> $1${reset}"
}

init_progress() {
    local start_step=$1
    local ignore_progress=$2

    if [[ -z "$ignore_progress" ]]; then
        echo $start_step > $PROGRESS_FILE
        LAST_COMPLETED_STEP=$start_step
    elif [[ -f $PROGRESS_FILE ]]; then
        LAST_COMPLETED_STEP=$(cat $PROGRESS_FILE)
    fi
}

mark_completed() {
    local step=$1
    echo $step > $PROGRESS_FILE
    LAST_COMPLETED_STEP=$step
}

should_skip() {
    local step=$1
    if [[ -f $PROGRESS_FILE ]]; then
        LAST_COMPLETED_STEP=$(cat $PROGRESS_FILE)
        [[ $LAST_COMPLETED_STEP -ge $step ]]
    else
        false
    fi
}

# Function to check if required environment variables are set
check_required_vars() {
    local missing_vars=()

    # Handle both zsh and bash parameter expansion
    if [[ -n "$ZSH_VERSION" ]]; then
        # ZSH version
        for var in "$@"; do
            if [[ -z "${(P)var}" ]]; then
                missing_vars+=("$var")
            fi
        done
    else
        # Bash version
        for var in "$@"; do
            if [[ -z "${!var}" ]]; then
                missing_vars+=("$var")
            fi
        done
    fi

    if (( ${#missing_vars[@]} > 0 )); then
        echo "Error: The following required environment variables are not set:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}