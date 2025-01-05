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
    nohup $AIOS_CLI start --connect > "$LOG_FILE" 2>&1 &
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

# Run Inference with Default or Custom Model and Prompt
# Run Inference with Default or Custom Model and Prompt
run_inference() {
    success "Starting Inference..."

    # Array of 100 predefined prompts
    default_prompts=(
        "Can you explain how to write an HTTP server in Rust?"
        "What is the difference between AI and Machine Learning?"
        "How does blockchain technology work?"
        "Explain the basics of Kubernetes."
        "What are the core principles of object-oriented programming?"
        "Describe the TCP/IP networking model."
        "How do neural networks function in AI?"
        "What is the role of Docker in software development?"
        "Explain how DNS works."
        "What is the difference between HTTP and HTTPS?"
        "Describe the Agile methodology in project management."
        "Explain recursion with an example."
        "What is the difference between compiled and interpreted languages?"
        "How does the internet protocol (IP) address work?"
        "Explain the basics of cryptography."
        "What is a REST API?"
        "How do you secure a Linux server?"
        "Explain how load balancing works."
        "What are microservices, and how do they differ from monolithic architecture?"
        "Describe how a database index works."
        "Explain garbage collection in programming languages."
        "What is the CAP theorem in distributed systems?"
        "How do firewalls protect networks?"
        "Explain continuous integration and continuous deployment (CI/CD)."
        "What is virtualization in computing?"
        "Describe the concept of caching."
        "Explain the basics of quantum computing."
        "How does OAuth authentication work?"
        "What is a reverse proxy server?"
        "Explain how SSL/TLS encryption works."
        "What are the benefits of cloud computing?"
        "Describe the structure of a JSON object."
        "What is a container in Docker?"
        "Explain how version control systems like Git work."
        "Describe the process of data normalization."
        "What is SQL injection, and how can it be prevented?"
        "Explain the concept of DevOps."
        "How does serverless architecture work?"
        "What is a CDN (Content Delivery Network)?"
        "Explain cross-site scripting (XSS)."
        "Describe the role of an API Gateway."
        "What are the key differences between PostgreSQL and MySQL?"
        "How does pagination work in APIs?"
        "Explain how Blockchain achieves consensus."
        "What is the importance of DNS records?"
        "Describe the basics of Kubernetes Pods."
        "What is container orchestration?"
        "Explain the concept of zero-trust security."
        "How does NAT (Network Address Translation) work?"
        "What is a subnet mask?"
        "Describe the basics of SEO (Search Engine Optimization)."
        "Explain the concept of machine learning bias."
        "What is the difference between supervised and unsupervised learning?"
        "How does a load balancer distribute traffic?"
        "What are environment variables?"
        "Explain how the Linux filesystem works."
        "Describe the basics of multi-threading."
        "What is latency in networks?"
        "Explain SSL certificate pinning."
        "Describe the structure of an HTML document."
        "What is a hypervisor in virtualization?"
        "How does blockchain ensure immutability?"
        "Explain data serialization."
        "What are JWT (JSON Web Tokens)?"
        "How does Kubernetes handle scaling?"
        "What are the benefits of Infrastructure as Code (IaC)?"
        "Explain how API rate limiting works."
        "Describe a key-value database."
        "What is edge computing?"
        "How does a proxy server work?"
        "Explain the role of a data warehouse."
        "What is data encryption at rest and in transit?"
        "How do CDN edge nodes work?"
        "Explain the difference between UDP and TCP."
        "What is Elasticsearch used for?"
        "Describe the purpose of a VPN."
        "How does a message broker like RabbitMQ work?"
        "What are the types of database indexes?"
        "Explain the importance of a service mesh."
        "What is blue-green deployment?"
        "Describe the purpose of Helm in Kubernetes."
        "What is OAuth2.0?"
        "Explain how DNS caching works."
        "What is RAID in storage systems?"
        "Describe how CI/CD pipelines are implemented."
        "What are cron jobs in Linux?"
        "Explain how Kubernetes secrets work."
        "What are Docker volumes?"
        "What is the difference between Redis and Memcached?"
        "Explain data replication in databases."
        "How does Kubernetes handle high availability?"
        "What is the purpose of Redis in caching?"
        "Explain the concept of pub-sub messaging."
        "What are Docker namespaces?"
        "How does Kubernetes auto-scaling work?"
        "Explain the basics of Python virtual environments."
        "What is the difference between HTTPS and SSH?"
        "Describe SQL vs NoSQL databases."
        "What is multi-tenancy in cloud computing?"
        "Explain the basics of data warehousing."
        "Describe the CAP theorem in distributed systems."
    )

    # Ask if the user wants to use the default inference settings
    read -p "Do You Want to Run Inference with Default Settings? (y/n): " choice

    case "$choice" in
        [Yy]*)
            # Select a random prompt
            random_index=$((RANDOM % ${#default_prompts[@]}))
            random_prompt=${default_prompts[$random_index]}
            default_model="hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf"

            success "Using Default Model: $default_model"
            success "Using Random Prompt: \"$random_prompt\""

            $AIOS_CLI hive infer --model "$default_model" --prompt "$random_prompt" || warning "Failed to run inference with default settings."
            success "Inference completed with default settings."
            ;;
        
        [Nn]*)
            # User selects custom model and prompt
            read -p "Enter the model you want to use: " model_name
            read -p "Enter your prompt: " user_prompt

            success "Using Custom Model: $model_name"
            success "Using Custom Prompt: \"$user_prompt\""

            $AIOS_CLI hive infer --model "$model_name" --prompt "$user_prompt" || warning "Failed to run inference with custom settings."
            success "Inference completed with custom settings."
            ;;
        
        *)
            # Invalid input
            warning "Invalid choice. Please enter 'y' or 'n'."
            run_inference
            ;;
    esac
}



# Check Point Detail
check_point() {
    echo "Detail Point Your Point"
    echo "============================"
    $AIOS_CLI hive points
    
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

# Uninstall aiOS CLI
uninstall_aios_cli() {
    success "Uninstalling aiOS CLI..."

    case "$PLATFORM" in
        Linux)   
            curl $UNINSTALL_URL | bash || error "Failed to uninstall aiOS CLI on Linux."
            ;;
        Mac)     
            curl $UNINSTALL_URL | sh || error "Failed to uninstall aiOS CLI on Mac."
            ;;
        Windows) 
            powershell -Command "(Invoke-WebRequest \"$UNINSTALL_URL?platform=windows\").Content | powershell -" || error "Failed to uninstall aiOS CLI on Windows."
            ;;
        *) 
            error "Unsupported operating system for uninstallation."
            ;;
    esac

    success "aiOS CLI uninstalled successfully."
}

# Main Menu
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
    echo "12. Check Detail Point"
    echo "13. Uninstall Hyperspace"
    echo "14. Exit"

    read -p "Select an option (1-14): " choice
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
        12) check_point ;;
        13) uninstall_aios_cli ;;
        14) success "Goodbye!"; exit 0 ;;
        *) warning "Invalid option. Please select a valid choice." ;;
    esac
    main_menu
}


# Start the script
main_menu
