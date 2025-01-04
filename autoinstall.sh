#!/bin/bash

# autoinstall.sh - Automated installer for aiOS CLI

# Variables
INSTALL_URL="https://download.hyper.space/api/install"
UNINSTALL_URL="https://download.hyper.space/api/uninstall"
LOG_DIR="$HOME/.cache/hyperspace/kernel-logs"
OS=$(uname -s)
AIOS_CLI="aios-cli"

# Colors for terminal output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Functions

# Print a success message
success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
# Print an error message
error() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
# Print a warning message
warning() { echo -e "${YELLOW}[WARNING]${RESET} $1"; }

# Detect OS
detect_os() {
    case "$OS" in
        Linux*)   PLATFORM="Linux" ;;
        Darwin*)  PLATFORM="Mac" ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) PLATFORM="Windows" ;;
        *)        error "Unsupported operating system: $OS" ;;
    esac
    success "Detected OS: $PLATFORM"
}

# Install aiOS CLI
install_aios_cli() {
    success "Installing aiOS CLI for $PLATFORM..."
    case "$PLATFORM" in
        Linux)   curl $INSTALL_URL | bash || error "Failed to install aiOS CLI on Linux." ;;
        Mac)     curl $INSTALL_URL | sh || error "Failed to install aiOS CLI on Mac." ;;
        Windows) powershell -Command "(Invoke-WebRequest \"$INSTALL_URL?platform=windows\").Content | powershell -" || error "Failed to install aiOS CLI on Windows." ;;
    esac
    success "aiOS CLI installed successfully."
}

# Check installation
check_installation() {
    if command -v $AIOS_CLI > /dev/null 2>&1; then
        success "aiOS CLI is successfully installed and available globally."
    else
        error "aiOS CLI is not detected. Please check the installation logs."
    fi
}

# Start Daemon
start_daemon() {
    LOG_FILE="$HOME/aios-daemon.log"
    PID_FILE="$HOME/aios-daemon.pid"
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            warning "Daemon is already running with PID $PID."
            return
        else
            warning "Stale PID file found. Cleaning up..."
            rm -f "$PID_FILE"
        fi
    fi
    success "Starting aiOS CLI daemon in the background..."
    nohup $AIOS_CLI start > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 2
    if ps -p $(cat "$PID_FILE") > /dev/null 2>&1; then
        success "Daemon started. Logs: $LOG_FILE, PID: $PID_FILE"
    else
        error "Failed to start aiOS daemon. Check $LOG_FILE."
    fi
}

# Stop Daemon
stop_daemon() {
    echo "Kill Daemon"
    $AIOS_CLI kill
}

# Show system info
show_system_info() {
    success "Fetching system information..."
    $AIOS_CLI system-info || warning "Unable to retrieve system information."
}

# Show available models
show_models() {
    success "Fetching available models..."
    $AIOS_CLI models available || warning "Failed to fetch available models."
}

# Add Model
add_model() {
    # Ask the user if they want to add the default model
    read -p "Do you want to add the default model? (y/n): " choice

    case "$choice" in
        [Yy]*)
            # User selected default model
            default_model="hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf"
            success "Adding default model: $default_model"
            $AIOS_CLI models add "$default_model" || warning "Failed to add default model."
            success "Default model added successfully."
            ;;
        [Nn]*)
            # User selected to enter a custom model
            read -p "Enter the model to install (e.g., hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf): " model_name
            $AIOS_CLI models add "$model_name" || warning "Failed to add model $model_name."
            success "Model $model_name added successfully."
            ;;
        *)
            # Invalid input
            warning "Invalid choice. Please enter 'y' or 'n'."
            add_model
            ;;
    esac
}


# Setup Hive (Import keys and connect)
setup_hive() {
    success "Configuring Hive..."

    # Ask if the user already has a private key
    read -p "Do you have a private key before? (y/n): " choice

    case "$choice" in
        [Yy]*)
            # User has a private key
            read -p "Paste your private key: " private_key

            # Save the private key to a file
            echo "$private_key" > ./my.pem
            chmod 600 ./my.pem  # Secure the key file
            success "Private key saved successfully to ./my.pem"

            # Import the saved key
            $AIOS_CLI hive import-keys ./my.pem || warning "Failed to import private key."
            success "Private key imported successfully."
            ;;
        
        [Nn]*)
            # No private key, run default import command
            $AIOS_CLI hive import-keys ./my.pem || warning "Failed to import default private key."
            success "Default private key imported successfully."
            ;;

        *)
            # Invalid input
            warning "Invalid choice. Please enter 'y' or 'n'."
            setup_hive
            ;;
    esac
}


# Login to Hive
login_hive() {
    success "Logging into Hive..."
    $AIOS_CLI hive login || warning "Failed to login to Hive."
    $AIOS_CLI hive connect || warning "Failed to connect to Hive network."
    success "Hive login and connection successful."
}

# Select Tier
select_tier() {
    echo -e "\n${GREEN}Select GPU Memory Tier:${RESET}"
    echo "1 : 30GB"
    echo "2 : 20GB"
    echo "3 : 8GB"
    echo "4 : 4GB"
    echo "5 : 2GB"
    read -p "Enter your choice (1-5): " gpu_choice

    case $gpu_choice in
        1) TIER=1 ;;
        2) TIER=2 ;;
        3) TIER=3 ;;
        4) TIER=4 ;;
        5) TIER=5 ;;
        *) warning "Invalid choice. Defaulting to Tier 5."; TIER=5 ;;
    esac

    $AIOS_CLI hive select-tier $TIER || warning "Failed to select Tier $TIER."
    success "Tier $TIER selected successfully."
}

# Run Inference with Prompt
run_inference() {
    read -p "Enter the model to use for inference: " model_name
    read -p "Enter your prompt: " user_prompt
    $AIOS_CLI infer --model "$model_name" --prompt "$user_prompt" || warning "Failed to run inference."
    success "Inference completed."
}

# Chek status daemon
status_daemon() {
    
    echo "Checking Daemon Status"
    $AIOS_CLI status
    PID_FILE="$HOME/aios-daemon.pid"
    # if [ -f "$PID_FILE" ]; then
    #     PID=$(cat "$PID_FILE")
    #     if ps -p "$PID" > /dev/null 2>&1; then
    #         success "Daemon is running with PID $PID."
    #     else
    #         warning "Daemon is not running, but PID file exists. Cleaning up PID file."
    #         rm -f "$PID_FILE"
    #     fi
    # else
    #     warning "Daemon is not running. No PID file found."
    # fi
}

# Main Menu
main_menu() {
    curl -s https://raw.githubusercontent.com/dwisyafriadi2/logo/main/logo.sh | bash
    echo -e "\n${GREEN}aiOS CLI Automation Script${RESET}"
    echo "1. Install aiOS CLI"
    echo "2. Start Daemon"
    echo "3. Status Daemon"
    echo "4. Stop Daemon"
    echo "5. Show System Info"
    echo "6. Show Available Models"
    echo "7. Add Model"
    echo "8. Setup Hive"
    echo "9. Login to Hive"
    echo "10. Select Tier"
    echo "11. Run Inference"
    echo "12. Exit"

    read -p "Select an option (1-12): " choice
    case $choice in
        1) detect_os; install_aios_cli; check_installation ;;
        2) start_daemon ;;
        3) status_daemon ;;
        4) stop_daemon ;;
        5) show_system_info ;;
        6) show_models ;;
        7) add_model ;;
        8) setup_hive ;;
        9) login_hive ;;
        10) select_tier ;;
        11) run_inference ;;
        12) success "Goodbye!"; exit 0 ;;
        *) warning "Invalid option. Please select a valid choice." ;;
    esac
    main_menu
}

# Start the script
main_menu
