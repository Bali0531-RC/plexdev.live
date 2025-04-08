#!/bin/bash
# Unofficial PlexDevelopment Products Installer
# This script automatically detects your Linux distribution and installs selected Plex products 

#----- Color Definitions -----#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#----- Global Variables -----#
INSTALL_DIR="/var/www/plex"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
DISTRIBUTION=""
PKG_MANAGER=""

#----- Utility Functions -----#
print_header() {
    echo -e "\n${BOLD}${PURPLE}#----- $1 -----#${NC}\n"
}

print_step() {
    echo -e "${BLUE}[+] ${CYAN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

#----- System Detection -----#
detect_system() {
    print_header "System Detection"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRIBUTION=$ID
        print_step "Detected distribution: ${BOLD}$DISTRIBUTION${NC}"
        
        # Determine package manager
        if [ -x "$(command -v apt)" ]; then
            PKG_MANAGER="apt"
        elif [ -x "$(command -v dnf)" ]; then
            PKG_MANAGER="dnf"
        elif [ -x "$(command -v yum)" ]; then
            PKG_MANAGER="yum"
        elif [ -x "$(command -v pacman)" ]; then
            PKG_MANAGER="pacman"
        elif [ -x "$(command -v zypper)" ]; then
            PKG_MANAGER="zypper"
        else
            print_error "Unable to determine package manager"
            exit 1
        fi
        
        print_success "Using package manager: ${BOLD}$PKG_MANAGER${NC}"
    else
        print_error "Unable to detect Linux distribution"
        exit 1
    fi
}

#----- Install Dependencies -----#
install_dependencies() {
    print_header "Installing Dependencies"
    
    print_step "Updating package lists..."
    case $PKG_MANAGER in
        apt)
            sudo apt update -y
            sudo apt install -y curl wget git unzip nginx certbot python3-certbot-nginx tmux \
                dnsutils net-tools nano bind9-utils whois iputils-ping zip unzip telnet \
                software-properties-common apt-transport-https ca-certificates gnupg
            
            # Install Node.js 20+
            print_step "Installing Node.js 20+..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt install -y nodejs
            ;;
        dnf|yum)
            sudo $PKG_MANAGER update -y
            sudo $PKG_MANAGER install -y curl wget git unzip nginx certbot python3-certbot-nginx tmux \
                bind-utils net-tools nano whois iputils zip unzip telnet \
                dnf-plugins-core
            
            # Install Node.js 20+
            print_step "Installing Node.js 20+..."
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
            sudo $PKG_MANAGER install -y nodejs
            ;;
        pacman)
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm curl wget git unzip nginx certbot certbot-nginx tmux \
                bind dnsutils net-tools nano whois iputils inetutils zip unzip
            
            # Install Node.js 20+
            print_step "Installing Node.js 20+..."
            sudo pacman -S --noconfirm nodejs npm
            ;;
        zypper)
            sudo zypper refresh
            sudo zypper install -y curl wget git unzip nginx certbot python-certbot-nginx tmux \
                bind-utils net-tools nano whois iputils zip unzip \
                telnet
            
            # Install Node.js 20+
            print_step "Installing Node.js 20+..."
            sudo zypper install -y nodejs20
            ;;
        *)
            print_error "Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac
    
    # Verify node version
    NODE_VERSION=$(node -v)
    print_step "Node.js version: $NODE_VERSION"
    
    # Check if version starts with v20 or higher
    if [[ ! $NODE_VERSION =~ ^v[2-9][0-9] ]]; then
        print_warning "Node.js version 20+ is required. Your version may be incompatible."
        read -p "Continue anyway? (y/n): " continue_install
        if [[ $continue_install != "y" && $continue_install != "Y" ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi
    
    # Add check for DNS lookup tools
    if ! command -v dig &> /dev/null && ! command -v nslookup &> /dev/null && ! command -v host &> /dev/null; then
        print_warning "No DNS lookup tools (dig, nslookup, or host) found. Domain validation may be limited."
    else
        print_success "DNS lookup tools found. Domain validation will be available."
    fi
    
    print_success "Dependencies installed successfully"
}

#----- Check Domain DNS -----#
check_domain_dns() {
    local domain=$1
    local skip_check=${2:-false}
    
    if [[ "$skip_check" == true ]]; then
        return 0
    fi
    
    print_step "Checking if domain $domain is pointed to this server..."
    
    # Get server's public IP
    local server_ip=$(curl -s https://ifconfig.me)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s https://api.ipify.org)
    fi
    
    print_step "Server IP: $server_ip"
    
    # Check if domain resolves
    local domain_ip=""
    
    if command -v dig &> /dev/null; then
        domain_ip=$(dig +short A $domain | head -n1)
    elif command -v nslookup &> /dev/null; then
        domain_ip=$(nslookup $domain | grep -A1 'Name:' | grep 'Address:' | awk '{print $2}' | head -n1)
    elif command -v host &> /dev/null; then
        domain_ip=$(host $domain | grep 'has address' | awk '{print $4}' | head -n1)
    else
        print_warning "DNS lookup tools not found. Please install dig, nslookup, or host."
        
        while true; do
            read -p "Confirm domain $domain is pointed to $server_ip? (y/n/skip): " dns_confirm
            if [[ $dns_confirm == "y" || $dns_confirm == "Y" ]]; then
                return 0
            elif [[ $dns_confirm == "skip" ]]; then
                print_warning "Skipping domain validation. SSL setup might fail."
                return 0
            else
                print_step "Please update your DNS settings and try again."
            fi
        done
    fi
    
    if [ -z "$domain_ip" ]; then
        print_warning "Domain $domain does not resolve to any IP address."
        while true; do
            print_step "DNS configuration required:"
            print_step "1. Log in to your domain registrar or DNS provider"
            print_step "2. Add an A record pointing to $server_ip"
            print_step "3. Wait for DNS propagation (may take up to 24 hours)"
            read -p "Check DNS again? (y/n/skip): " dns_check
            if [[ $dns_check == "y" || $dns_check == "Y" ]]; then
                if command -v dig &> /dev/null; then
                    domain_ip=$(dig +short A $domain | head -n1)
                elif command -v nslookup &> /dev/null; then
                    domain_ip=$(nslookup $domain | grep -A1 'Name:' | grep 'Address:' | awk '{print $2}' | head -n1)
                elif command -v host &> /dev/null; then
                    domain_ip=$(host $domain | grep 'has address' | awk '{print $4}' | head -n1)
                fi
                
                if [ -n "$domain_ip" ] && [ "$domain_ip" == "$server_ip" ]; then
                    print_success "Domain $domain is now correctly pointed to this server!"
                    return 0
                elif [ -n "$domain_ip" ]; then
                    print_warning "Domain $domain is pointed to $domain_ip, not $server_ip"
                else
                    print_warning "Domain $domain still does not resolve"
                fi
            elif [[ $dns_check == "skip" ]]; then
                print_warning "Skipping domain validation. SSL setup might fail."
                return 0
            else
                print_error "Cannot proceed without proper DNS configuration"
                return 1
            fi
        done
    elif [ "$domain_ip" == "$server_ip" ]; then
        print_success "Domain $domain is correctly pointed to this server: $server_ip"
        return 0
    else
        print_warning "Domain $domain is pointed to $domain_ip, but this server's IP is $server_ip"
        while true; do
            print_step "DNS configuration required:"
            print_step "1. Log in to your domain registrar or DNS provider"
            print_step "2. Update the A record to point to $server_ip"
            print_step "3. Wait for DNS propagation (may take up to 24 hours)"
            read -p "Check DNS again? (y/n/skip): " dns_check
            if [[ $dns_check == "y" || $dns_check == "Y" ]]; then
                if command -v dig &> /dev/null; then
                    domain_ip=$(dig +short A $domain | head -n1)
                elif command -v nslookup &> /dev/null; then
                    domain_ip=$(nslookup $domain | grep -A1 'Name:' | grep 'Address:' | awk '{print $2}' | head -n1)
                elif command -v host &> /dev/null; then
                    domain_ip=$(host $domain | grep 'has address' | awk '{print $4}' | head -n1)
                fi
                
                if [ -n "$domain_ip" ] && [ "$domain_ip" == "$server_ip" ]; then
                    print_success "Domain $domain is now correctly pointed to this server!"
                    return 0
                elif [ -n "$domain_ip" ]; then
                    print_warning "Domain $domain is pointed to $domain_ip, not $server_ip"
                else
                    print_warning "Domain $domain does not resolve"
                fi
            elif [[ $dns_check == "skip" ]]; then
                print_warning "Skipping domain validation. SSL setup might fail."
                return 0
            else
                print_error "Cannot proceed without proper DNS configuration"
                return 1
            fi
        done
    fi
}

#----- Open Port in Firewall -----#
open_port() {
    local port=$1
    local description=$2
    
    print_step "Attempting to open port $port for $description..."
    
    # Check which firewall is in use
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian with UFW
        sudo ufw allow $port/tcp
        if [ $? -eq 0 ]; then
            print_success "Port $port opened using UFW"
        else
            print_warning "Failed to open port with UFW. You may need to open it manually."
        fi
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL/Fedora with firewalld
        sudo firewall-cmd --permanent --add-port=$port/tcp
        sudo firewall-cmd --reload
        if [ $? -eq 0 ]; then
            print_success "Port $port opened using firewalld"
        else
            print_warning "Failed to open port with firewalld. You may need to open it manually."
        fi
    elif command -v iptables &> /dev/null; then
        # Direct iptables as fallback
        sudo iptables -A INPUT -p tcp --dport $port -j ACCEPT
        if command -v iptables-save &> /dev/null; then
            case $PKG_MANAGER in
                apt)
                    sudo netfilter-persistent save
                    ;;
                dnf|yum)
                    sudo service iptables save
                    ;;
                pacman)
                    sudo iptables-save | sudo tee /etc/iptables/iptables.rules
                    ;;
                zypper)
                    sudo service SuSEfirewall2 save
                    ;;
            esac
        else
            print_warning "iptables-save not found. Firewall rules may not persist after reboot."
        fi
        print_success "Port $port opened using iptables"
    else
        print_warning "No supported firewall detected. Please open port $port manually in your firewall settings."
    fi
}


#----- Setup Nginx -----#
setup_nginx() {
    local domain=$1
    local port=$2
    local product=$3
    
    print_step "Setting up Nginx for $product at $domain (port $port)"
    
    # Create Nginx config
    if [[ "$product" == "plexstore" ]]; then
        # Special config for PlexStore with 502 page
        sudo tee "$NGINX_AVAILABLE/$domain.conf" > /dev/null << EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    error_page 502 /502.html;
    location = /502.html {
        root $INSTALL_DIR/plexstore;
    }
}
EOF
    else
        # Standard config for other products
        sudo tee "$NGINX_AVAILABLE/$domain.conf" > /dev/null << EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    fi
    
    # Create a 502 error page for PlexStore
    if [[ "$product" == "plexstore" ]]; then
        sudo mkdir -p "$INSTALL_DIR/plexstore"
        sudo tee "$INSTALL_DIR/plexstore/502.html" > /dev/null << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PlexStore - Service Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        p { font-size: 18px; }
    </style>
</head>
<body>
    <h1>502 - Service Unavailable</h1>
    <p>The PlexStore service is currently unavailable. Please try again later.</p>
    <p>If this issue persists, please contact the administrator.</p>
</body>
</html>
EOF
    fi
    
    # Enable site
    sudo ln -sf "$NGINX_AVAILABLE/$domain.conf" "$NGINX_ENABLED/"
    
    # Test Nginx config
    sudo nginx -t
    
    # Restart Nginx
    sudo systemctl restart nginx
    
    print_success "Nginx configured for $domain"
}

#----- Setup SSL with Certbot -----#
setup_ssl() {
    local domain=$1
    local email=$2
    
    print_step "Setting up SSL for $domain using Certbot"
    
    # Get SSL certificate
    sudo certbot --nginx -d $domain --non-interactive --agree-tos --email $email
    
    print_success "SSL certificate installed for $domain"
}

create_startup_script() {
    local product=$1
    local product_path=$2
    local service_name="plex-$product"
    local tmux_session_name="plex-$product"
    
    print_step "Creating startup script for $product using tmux..."
    
    # Create the startup script that starts the bot in a tmux session
    sudo tee "$product_path/start.sh" > /dev/null << EOF
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root

# Create a lock file to prevent multiple instances
LOCK_FILE="/tmp/$tmux_session_name.lock"

if [ -e \$LOCK_FILE ]; then
    PID=\$(cat \$LOCK_FILE)
    if ps -p \$PID > /dev/null; then
        echo "Process already running with PID \$PID"
        exit 0
    else
        echo "Removing stale lock file"
        rm -f \$LOCK_FILE
    fi
fi

# Store the PID
echo \$\$ > \$LOCK_FILE

# Check if the tmux session already exists
if ! /usr/bin/tmux has-session -t $tmux_session_name 2>/dev/null; then
    # Create a new tmux session for the bot
    /usr/bin/tmux new-session -d -s $tmux_session_name "cd $product_path && /usr/bin/node ."
    echo "Created new tmux session: $tmux_session_name"
    exit 0
else
    echo "Session $tmux_session_name already exists"
    exit 0
fi
EOF

    sudo chmod +x "$product_path/start.sh"
    
    # Create or update the systemd service file with an ExecStop that kills the tmux session
    sudo tee "/etc/systemd/system/$service_name.service" > /dev/null << EOF
[Unit]
Description=Plex $product service
After=network.target

[Service]
Type=forking
User=root
ExecStart=$product_path/start.sh
ExecStop=/usr/bin/tmux kill-session -t $tmux_session_name || true
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=plex-$product

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd so it picks up the new service file
    sudo systemctl daemon-reload
    
    # Enable the service to start on boot and start it now
    sudo systemctl enable $service_name
    if sudo systemctl start $service_name; then
        print_success "Service started successfully"
    else
        print_warning "Service failed to start. You can check the logs with: sudo journalctl -u $service_name"
        print_step "Attempting to run the start script directly..."
        sudo bash "$product_path/start.sh"
    fi
    
    print_success "Startup script created for $product"
    print_step "To configure the bot, run: nano $product_path/config.yml"
    print_step "Start the service with: sudo systemctl start $service_name"
    print_step "Stop the service with: sudo systemctl stop $service_name"
    print_step "Restart the service with: sudo systemctl restart $service_name"
    print_step "Attach to the tmux session with: tmux attach -t $tmux_session_name"
    print_step "The service is set to auto-start on reboot"
}
#----- Extract Product -----#
extract_product() {
    local archive_path=$1
    local extract_path=$2
    local product_name=$(basename "$extract_path")
    
    # Check if this is an unobfuscated version
    local is_unobf=false
    if [[ "$archive_path" == *"-Unobf"* ]]; then
        is_unobf=true
        print_step "Processing unobfuscated source code version"
    fi
    
    print_step "Extracting product from $archive_path to $extract_path..."
    
    # Create directory
    sudo mkdir -p "$extract_path"
    
    # Determine archive type and extract
    if [[ "$archive_path" =~ \.zip$ ]]; then
        sudo unzip -o "$archive_path" -d "$extract_path" > /dev/null 2>&1
    elif [[ "$archive_path" =~ \.rar$ ]]; then
        # Check if unrar is installed
        if ! command -v unrar &> /dev/null; then
            print_step "Installing unrar..."
            case $PKG_MANAGER in
                apt)
                    sudo apt install -y unrar > /dev/null 2>&1 ;;
                dnf|yum)
                    sudo $PKG_MANAGER install -y unrar > /dev/null 2>&1 ;;
                pacman)
                    sudo pacman -S --noconfirm unrar > /dev/null 2>&1 ;;
                zypper)
                    sudo zypper install -y unrar > /dev/null 2>&1 ;;
            esac
        fi
        sudo unrar x "$archive_path" "$extract_path" > /dev/null 2>&1
    else
        print_error "Unsupported archive format: $archive_path"
        return 1
    fi
    
    print_success "Product extracted successfully"
    
    # Check for product subfolder without printing anything
    local final_path=""
    
    # If this is an unobfuscated version, check for folders with -Unobf suffix first
    if [ "$is_unobf" = true ]; then
        # Check for product-name-Unobf directory
        if [ -d "$extract_path/${product_name}-Unobf" ]; then
            final_path="$extract_path/${product_name}-Unobf"
        # Check for any directory ending with -Unobf
        else
            local unobf_dir=$(find "$extract_path" -maxdepth 1 -type d -name "*-Unobf" | head -n 1)
            if [ -n "$unobf_dir" ]; then
                final_path="$unobf_dir"
            fi
        fi
    fi
    
    # If we haven't found an unobf directory, follow the regular path resolution
    if [ -z "$final_path" ]; then
        # Check if the product folder was created inside extract_path
        if [ -d "$extract_path/$product_name" ]; then
            final_path="$extract_path/$product_name"
        else
            # Check if there's any other directory created
            local subdir=$(find "$extract_path" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            if [ -n "$subdir" ]; then
                final_path="$subdir"
            else
                final_path="$extract_path"
            fi
        fi
    fi
    
    print_step "Installation path: $final_path"
    
    # Add extra information if we're using a source code version
    if [ "$is_unobf" = true ]; then
        print_step "Using unobfuscated source code version"
    fi
    
    # Return the path only
    echo "$final_path"
}
#----- Install NPM Dependencies -----#
install_npm_dependencies() {
    local product_path=$1
    
    print_step "Installing NPM dependencies in $product_path..."
    
    # Check if package.json exists
    if [ ! -f "$product_path/package.json" ]; then
        print_warning "No package.json found in $product_path"
        ls -la "$product_path"
        return 1
    fi
    
    # Navigate to the product directory and install dependencies
    cd "$product_path" && sudo npm install
    
    if [ $? -eq 0 ]; then
        print_success "NPM dependencies installed successfully"
    else
        print_error "Failed to install NPM dependencies"
    fi
}


#----- Check Existing Installation -----#
check_existing_installation() {
    local product="$1"
    local install_path="$INSTALL_DIR/$product"
    if [ -d "$install_path" ]; then
        print_warning "An existing installation of $product was found at $install_path"
        read -p "Do you want to purge the existing installation and proceed? (y/n): " purge_choice </dev/tty
        if [[ "$purge_choice" == "y" || "$purge_choice" == "Y" ]]; then
            print_step "Removing existing installation..."
            sudo rm -rf "$install_path"
            print_success "Existing installation removed"
        else
            print_warning "Installation aborted."
            exit 0
        fi
    fi
}

find_archive_files() {
    local product="$1"
    local search_dirs=("/home" "/root" "/tmp" "/var/tmp")
    local max_depth=3
    local found_archives=()
    local found_unobf_archives=()
    local log_file="./archive_search_log.txt"
    
    echo "Archive search started: $(date)" > "$log_file"
    echo "Searching for product: $product" >> "$log_file"
    
    print_step "Searching for archive files for $product..."
    
    # First search for unobfuscated versions specifically
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r file; do
                found_unobf_archives+=("$file")
                echo "Found unobfuscated match: $file" >> "$log_file"
            done < <(find "$dir" -maxdepth "$max_depth" -type f \( -iname "*${product}*-Unobf*.zip" -o -iname "*${product}*-Unobf*.rar" \) 2>/dev/null)
        fi
    done
    
    # Then search for regular versions
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r file; do
                # Skip if it contains -Unobf since we already included those
                if [[ "$file" != *"-Unobf"* ]]; then
                    found_archives+=("$file")
                    echo "Found product match: $file" >> "$log_file"
                fi
            done < <(find "$dir" -maxdepth "$max_depth" -type f \( -iname "*${product}*.zip" -o -iname "*${product}*.rar" \) 2>/dev/null)
        fi
    done

    # Combine arrays with unobfuscated versions first
    found_archives=("${found_unobf_archives[@]}" "${found_archives[@]}")

    if [ ${#found_archives[@]} -eq 0 ]; then
        print_warning "No product-specific archives found. Searching for any archives..."
        for dir in "${search_dirs[@]}"; do
            if [ -d "$dir" ]; then
                while IFS= read -r file; do
                    found_archives+=("$file")
                    echo "Found generic archive: $file" >> "$log_file"
                done < <(find "$dir" -maxdepth "$max_depth" -type f \( -iname "*.zip" -o -iname "*.rar" \) 2>/dev/null | head -n 10)
            fi
        done
    fi

    if [ ${#found_archives[@]} -gt 0 ]; then
        echo "----------------------------------------"
        echo "FOUND ${#found_archives[@]} ARCHIVE FILES:"
        echo "----------------------------------------"
        local i=1
        for archive in "${found_archives[@]}"; do
            file_size=$(du -h "$archive" 2>/dev/null | cut -f1 || echo "unknown")
            # Mark unobfuscated versions
            if [[ "$archive" == *"-Unobf"* ]]; then
                echo "$i) $archive ($file_size) [Source code version]"
            else
                echo "$i) $archive ($file_size)"
            fi
            i=$((i+1))
        done
        echo "0) Enter custom path"
        echo "----------------------------------------"
        while true; do
            read -p "Select option (0-${#found_archives[@]}): " choice </dev/tty
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                if [ "$choice" -eq 0 ]; then
                    read -p "Enter archive path: " custom_path </dev/tty
                    ARCHIVE_PATH="$custom_path"
                    break
                elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#found_archives[@]} ]; then
                    ARCHIVE_PATH="${found_archives[$((choice-1))]}"
                    break
                else
                    print_error "Invalid choice. Please try again."
                fi
            else
                print_error "Please enter a number."
            fi
        done
        
        # Let the user know if they selected a source code version
        if [[ "$ARCHIVE_PATH" == *"-Unobf"* ]]; then
            print_step "Source code version selected (unobfuscated)"
        fi
    else
        print_warning "No archives found. Please enter archive path manually."
        read -p "Archive path: " custom_path </dev/tty
        ARCHIVE_PATH="$custom_path"
    fi

    echo "----------------------------------------"
    echo "Archive search completed: $(date)" >> "$log_file"
    echo "----------------------------------------"
}

show_services_status() {
    print_header "Services Status"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        print_warning "No installations found in $INSTALL_DIR"
        return
    fi
    
    echo "----------------------------------------"
    echo "| Product      | Status          | Port | Domain         |"
    echo "----------------------------------------"
    
    for product in plextickets plexstaff plexstatus plexstore plexforms; do
        if [ -d "$INSTALL_DIR/$product" ]; then
            service_name="plex-$product"
            status=$(systemctl is-active $service_name 2>/dev/null || echo "not installed")
            
            # Get port and domain from nginx config if available
            domain="N/A"
            port="N/A"
            if [ -d "$NGINX_ENABLED" ]; then
                for conf in "$NGINX_ENABLED"/*.conf; do
                    if [ -f "$conf" ] && grep -q "$product" "$conf" 2>/dev/null; then
                        domain=$(grep "server_name" "$conf" 2>/dev/null | awk '{print $2}' | tr -d ';' | head -1)
                        port=$(grep "proxy_pass http://localhost:" "$conf" 2>/dev/null | sed 's/.*localhost:\([0-9]*\).*/\1/' | head -1)
                        break
                    fi
                done
            fi
            
            # Format with printf instead of echo -e
            if [[ "$status" == "active" ]]; then
                printf "| %-12s | ${GREEN}%-14s${NC} | %-4s | %-14s |\n" "$product" "$status" "$port" "$domain"
            else
                printf "| %-12s | ${RED}%-14s${NC} | %-4s | %-14s |\n" "$product" "$status" "$port" "$domain"
            fi
        fi
    done
    echo "----------------------------------------"
}

view_logs() {
    local product=$1
    local service_name="plex-$product"
    
    print_header "Viewing logs for $product"
    
    if systemctl status "$service_name" &>/dev/null; then
        echo "Last 50 log entries:"
        echo "----------------------------------------"
        journalctl -u "$service_name" -n 50 --no-pager
        echo "----------------------------------------"
        echo "View more logs with: journalctl -u $service_name -f"
    else
        print_error "Service $service_name is not active"
        
        # Try to find tmux session logs
        if tmux has-session -t "$service_name" 2>/dev/null; then
            print_step "Found tmux session. Attaching..."
            tmux attach-session -t "$service_name"
        else
            print_error "No tmux session found for $product"
        fi
    fi
}

system_health_check() {
    print_header "System Health Check"
    
    # Check disk space
    print_step "Checking disk space..."
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 85 ]; then
        print_warning "Disk usage is high: ${disk_usage}%"
    else
        print_success "Disk usage is acceptable: ${disk_usage}%"
    fi
    
    # Check memory
    print_step "Checking memory usage..."
    memory_free=$(free -m | awk 'NR==2 {print $4}')
    if [ "$memory_free" -lt 500 ]; then
        print_warning "Low memory available: ${memory_free} MB"
    else
        print_success "Memory available: ${memory_free} MB"
    fi
    
    # Check services
    print_step "Checking services status..."
    for product in plextickets plexstaff plexstatus plexstore plexforms; do
        if [ -d "$INSTALL_DIR/$product" ]; then
            service_name="plex-$product"
            if systemctl is-active --quiet "$service_name"; then
                print_success "$service_name is running"
            else
                print_warning "$service_name is not running"
            fi
        fi
    done
    
    # Check nginx
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_warning "Nginx is not running"
    fi
    
    # Check SSL certificates
    print_step "Checking SSL certificates..."
    for domain_conf in "$NGINX_ENABLED"/*.conf; do
        if [ -f "$domain_conf" ]; then
            domain=$(grep "server_name" "$domain_conf" | awk '{print $2}' | tr -d ';' | head -1)
            if [ -n "$domain" ]; then
                cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
                if [ -f "$cert_path" ]; then
                    expiry_date=$(sudo openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
                    expiry_epoch=$(sudo date -d "$expiry_date" +%s)
                    current_epoch=$(date +%s)
                    days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                    
                    if [ "$days_left" -lt 15 ]; then
                        print_warning "SSL for $domain expires in $days_left days"
                    else
                        print_success "SSL for $domain valid for $days_left more days"
                    fi
                else
                    print_warning "No SSL certificate found for $domain"
                fi
            fi
        fi
    done
}



manage_backups() {
    while true; do
        clear
        print_header "Backup Management"
        
        local backup_dir="$INSTALL_DIR/backups"
        sudo mkdir -p "$backup_dir"
        
        echo -e "${YELLOW}Backup Options:${NC}"
        echo -e "${CYAN}1) Create backup of a product${NC}"
        echo -e "${CYAN}2) Create backup of all products${NC}"
        echo -e "${CYAN}3) List available backups${NC}"
        echo -e "${CYAN}4) Restore from backup${NC}"
        echo -e "${CYAN}5) Delete backup${NC}"
        echo -e "${CYAN}6) Return to main menu${NC}"
        
        read -p "Enter your choice: " backup_choice </dev/tty
        
        case $backup_choice in
            1)
                # Backup single product
                echo "Available products:"
                local products=()
                local i=1
                for product in plextickets plexstaff plexstatus plexstore plexforms; do
                    if [ -d "$INSTALL_DIR/$product" ]; then
                        echo "$i) $product"
                        products+=("$product")
                        i=$((i+1))
                    fi
                done
                
                if [ ${#products[@]} -eq 0 ]; then
                    print_warning "No products installed"
                    read -p "Press Enter to continue..." </dev/tty
                    continue
                fi
                
                read -p "Select product to backup (1-${#products[@]}): " prod_choice </dev/tty
                if [[ "$prod_choice" =~ ^[0-9]+$ ]] && [ "$prod_choice" -ge 1 ] && [ "$prod_choice" -le ${#products[@]} ]; then
                    backup_installation "${products[$((prod_choice-1))]}"
                else
                    print_error "Invalid choice"
                fi
                ;;
            2)
                # Backup all products
                print_step "Creating backup of all products..."
                local timestamp=$(date +"%Y%m%d_%H%M%S")
                local backup_file="$backup_dir/all_products_$timestamp.tar.gz"
                
                local has_products=false
                for product in plextickets plexstaff plexstatus plexstore plexforms; do
                    if [ -d "$INSTALL_DIR/$product" ]; then
                        has_products=true
                        break
                    fi
                done
                
                if [ "$has_products" = true ]; then
                    sudo tar -czf "$backup_file" -C "$INSTALL_DIR" $(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d -name "plex*" -printf "%f ")
                    print_success "Backup created: $backup_file"
                else
                    print_warning "No products installed"
                fi
                ;;
            3)
                # List backups
                list_backups
                ;;
            4)
                # Restore backup
                restore_backup
                ;;
            5)
                # Delete backup
                delete_backup
                ;;
            6) 
                return 
                ;;
            *) 
                print_error "Invalid choice" 
                ;;
        esac
        
        read -p "Press Enter to continue..." </dev/tty
    done
}

list_backups() {
    local backup_dir="$INSTALL_DIR/backups"
    
    print_header "Available Backups"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        print_warning "No backups found"
        return
    fi
    
    echo "----------------------------------------"
    echo "| ID | Date               | Product    | Size     |"
    echo "----------------------------------------"
    
    local i=1
    while IFS= read -r file; do
        local filename=$(basename "$file")
        local date_part=$(echo "$filename" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        local formatted_date=$(date -d "$(echo $date_part | sed 's/_/ /')" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown date")
        local product=$(echo "$filename" | sed -E 's/(.*)_[0-9]{8}_[0-9]{6}\.tar\.gz/\1/')
        local size=$(du -h "$file" | cut -f1)
        
        printf "| %-2s | %-18s | %-10s | %-8s |\n" "$i" "$formatted_date" "$product" "$size"
        i=$((i+1))
    done < <(find "$backup_dir" -name "*.tar.gz" | sort -r)
    
    echo "----------------------------------------"
}

restore_backup() {
    local backup_dir="$INSTALL_DIR/backups"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        print_warning "No backups found"
        return
    fi
    
    print_header "Restore from Backup"
    
    # List backups for selection
    local backups=()
    local i=1
    while IFS= read -r file; do
        local filename=$(basename "$file")
        local date_part=$(echo "$filename" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        local formatted_date=$(date -d "$(echo $date_part | sed 's/_/ /')" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown date")
        local product=$(echo "$filename" | sed -E 's/(.*)_[0-9]{8}_[0-9]{6}\.tar\.gz/\1/')
        local size=$(du -h "$file" | cut -f1)
        
        echo "$i) $product ($formatted_date, $size)"
        backups+=("$file")
        i=$((i+1))
    done < <(find "$backup_dir" -name "*.tar.gz" | sort -r)
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return
    fi
    
    read -p "Select backup to restore (1-${#backups[@]}): " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
        local selected_backup="${backups[$((choice-1))]}"
        local filename=$(basename "$selected_backup")
        local product=$(echo "$filename" | sed -E 's/(.*)_[0-9]{8}_[0-9]{6}\.tar\.gz/\1/')
        
        print_warning "Restoring will overwrite existing installation. Data may be lost."
        read -p "Are you sure you want to restore $product? (y/n): " confirm </dev/tty
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            # Stop the service if running
            if [[ "$product" != "all_products" ]]; then
                if systemctl is-active --quiet "plex-$product"; then
                    print_step "Stopping service plex-$product..."
                    sudo systemctl stop "plex-$product"
                fi
                
                # Remove existing installation
                if [ -d "$INSTALL_DIR/$product" ]; then
                    print_step "Removing existing installation..."
                    sudo rm -rf "$INSTALL_DIR/$product"
                fi
                
                # Extract backup
                print_step "Restoring from backup..."
                sudo tar -xzf "$selected_backup" -C "$INSTALL_DIR"
                
                # Restart the service
                if systemctl list-unit-files | grep -q "plex-$product.service"; then
                    print_step "Starting service..."
                    sudo systemctl start "plex-$product"
                fi
                
                print_success "$product restored successfully"
            else
                # For all products backup
                print_step "Stopping all services..."
                for p in plextickets plexstaff plexstatus plexstore plexforms; do
                    if systemctl is-active --quiet "plex-$p"; then
                        sudo systemctl stop "plex-$p"
                    fi
                done
                
                # Extract backup
                print_step "Restoring from backup..."
                sudo tar -xzf "$selected_backup" -C "$INSTALL_DIR"
                
                # Restart services
                print_step "Restarting services..."
                for p in plextickets plexstaff plexstatus plexstore plexforms; do
                    if systemctl list-unit-files | grep -q "plex-$p.service"; then
                        sudo systemctl start "plex-$p"
                    fi
                done
                
                print_success "All products restored successfully"
            fi
        else
            print_warning "Restore cancelled"
        fi
    else
        print_error "Invalid choice"
    fi
}

delete_backup() {
    local backup_dir="$INSTALL_DIR/backups"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        print_warning "No backups found"
        return
    fi
    
    print_header "Delete Backup"
    
    # List backups for selection
    local backups=()
    local i=1
    while IFS= read -r file; do
        local filename=$(basename "$file")
        local date_part=$(echo "$filename" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        local formatted_date=$(date -d "$(echo $date_part | sed 's/_/ /')" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown date")
        local product=$(echo "$filename" | sed -E 's/(.*)_[0-9]{8}_[0-9]{6}\.tar\.gz/\1/')
        local size=$(du -h "$file" | cut -f1)
        
        echo "$i) $product ($formatted_date, $size)"
        backups+=("$file")
        i=$((i+1))
    done < <(find "$backup_dir" -name "*.tar.gz" | sort -r)
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return
    fi
    
    read -p "Select backup to delete (1-${#backups[@]}): " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
        local selected_backup="${backups[$((choice-1))]}"
        
        read -p "Are you sure you want to delete this backup? (y/n): " confirm </dev/tty
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            sudo rm -f "$selected_backup"
            print_success "Backup deleted successfully"
        else
            print_warning "Deletion cancelled"
        fi
    else
        print_error "Invalid choice"
    fi
}


manage_installations() {
    while true; do
        clear
        print_header "Manage Installations"
        
        # Show current status of all services
        show_services_status
        
        echo -e "\n${YELLOW}Management Options:${NC}"
        echo -e "${CYAN}1) Start service${NC}"
        echo -e "${CYAN}2) Stop service${NC}"
        echo -e "${CYAN}3) Restart service${NC}"
        echo -e "${CYAN}4) View logs${NC}"
        echo -e "${CYAN}5) Edit configuration${NC}"
        echo -e "${CYAN}6) Return to main menu${NC}"
        
        read -p "Enter your choice: " manage_choice </dev/tty
        
        case $manage_choice in
            1|2|3|4|5)
                read -p "Enter product name (plextickets, plexstaff, etc.): " product_name </dev/tty
                if [ ! -d "$INSTALL_DIR/$product_name" ]; then
                    print_error "Product $product_name not found"
                    read -p "Press Enter to continue..." </dev/tty
                    continue
                fi
                
                case $manage_choice in
                    1) sudo systemctl start "plex-$product_name" ;;
                    2) sudo systemctl stop "plex-$product_name" ;;
                    3) sudo systemctl restart "plex-$product_name" ;;
                    4) view_logs "$product_name" ;;
                    5) 
                        if [ -f "$INSTALL_DIR/$product_name/config.yml" ]; then
                            sudo nano "$INSTALL_DIR/$product_name/config.yml"
                        else
                            print_warning "No config.yml found. Looking for alternatives..."
                            config_files=$(find "$INSTALL_DIR/$product_name" -name "*.json" -o -name "*.yml" -o -name "*.yaml" -o -name "*.config.js" -maxdepth 2)
                            if [ -n "$config_files" ]; then
                                echo "Found possible configuration files:"
                                select config_file in $config_files; do
                                    if [ -n "$config_file" ]; then
                                        sudo nano "$config_file"
                                        break
                                    fi
                                done
                            else
                                print_error "No configuration files found"
                            fi
                        fi
                        ;;
                esac
                ;;
            6) return ;;
            *) print_error "Invalid choice" ;;
        esac
        
        read -p "Press Enter to continue..." </dev/tty
    done
}


backup_installation() {
    local product="$1"
    local install_path="$INSTALL_DIR/$product"
    
    if [ ! -d "$install_path" ]; then
        print_error "No installation found for $product"
        return 1
    fi
    
    print_header "Backing up $product"
    
    local backup_dir="$INSTALL_DIR/backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/${product}_backup_$timestamp.tar.gz"
    
    # Create backup directory if it doesn't exist
    sudo mkdir -p "$backup_dir"
    
    # Create backup
    print_step "Creating backup of $product..."
    sudo tar -czf "$backup_file" -C "$INSTALL_DIR" "$product"
    
    if [ $? -eq 0 ]; then
        print_success "Backup created: $backup_file"
        
        # Optional: copy configs separately for easy access
        if [ -f "$install_path/config.yml" ]; then
            sudo cp "$install_path/config.yml" "$backup_dir/${product}_config_$timestamp.yml"
            print_step "Configuration saved separately"
        fi
        
        return 0
    else
        print_error "Failed to create backup"
        return 1
    fi
}

#----- Install PlexTickets -----#
install_plextickets() {
    print_header "Installing PlexTickets"
    
    local product="plextickets"
    check_existing_installation "$product"
    find_archive_files "$product"

    local with_dashboard=$1
    local base_path="$INSTALL_DIR/plextickets"
    
    # Extract product and get the actual path (capture only the last line)
    local install_path=$(extract_product "$ARCHIVE_PATH" "$base_path" | tail -n 1)
    
    # Verify the path exists (remove any escape sequences)
    if [ ! -d "$install_path" ]; then
        print_error "Installation path not found: $install_path"
        exit 1
    fi
    
    # Install NPM dependencies
    install_npm_dependencies "$install_path"
    
    # Check if dashboard should be installed
    if [ "$with_dashboard" = true ]; then
        local dashboard_port
        local product="Dashboard"
        read -p "Enter port for PlexTickets Dashboard (default: 3000): " dashboard_port </dev/tty
        dashboard_port=${dashboard_port:-3000}
        # Open dashboard port in firewall
        open_port "$dashboard_port" "PlexTickets Dashboard"
        
        read -p "Enter domain for PlexTickets Dashboard (e.g., tickets.example.com): " domain </dev/tty
        read -p "Enter email for SSL certificate: " email
        
        find_archive_files "$product"
        
        # Create addons directory if it doesn't exist
        sudo mkdir -p "$install_path/addons"
        
        # Extract dashboard and get the actual path
        local dashboard_path=$(extract_product "$ARCHIVE_PATH" "$install_path/addons" | tail -n 1)
        
        
        if ! check_domain_dns "$domain"; then
            print_error "Domain verification failed for $domain"
            read -p "Do you want to proceed without proper DNS configuration? This may cause SSL setup to fail. (y/n): " proceed_anyway </dev/tty
            if [[ $proceed_anyway != "y" && $proceed_anyway != "Y" ]]; then
                print_error "Installation aborted."
                exit 1
            fi
        fi



        # Setup Nginx and SSL
        setup_nginx "$domain" "$dashboard_port" "plextickets"
        setup_ssl "$domain" "$email"
    fi
    
    # Ask about creating startup script
    read -p "Do you want to set up auto-start on boot? (y/n): " setup_startup </dev/tty
    if [[ $setup_startup == "y" || $setup_startup == "Y" ]]; then 
        create_startup_script "plextickets" "$install_path"
    fi
    
    print_success "PlexTickets installed successfully"
}

#----- Install PlexStaff -----#
install_plexstaff() {
    print_header "Installing PlexStaff"
    local base_path="$INSTALL_DIR/plexstaff"
    local product="plexstaff"
    check_existing_installation "$product"
    find_archive_files "$product"

    # Extract product and get the actual path (capture only the last line)
    local install_path=$(extract_product "$ARCHIVE_PATH" "$base_path" | tail -n 1)
    
    # Verify the path exists
    if [ ! -d "$install_path" ]; then
        print_error "Installation path not found: $install_path"
        exit 1
    fi
    
    print_step "Using installation path: $install_path"
    
    # Install NPM dependencies
    install_npm_dependencies "$install_path"
    
    # Get port
    local port
    read -p "Enter port for PlexStaff (default: 3001): " port </dev/tty
    port=${port:-3001}
    # Open port in firewall
    open_port "$port" "PlexStaff"
    
    # Get domain and email
    read -p "Enter domain for PlexStaff (e.g., staff.example.com): " domain </dev/tty
    read -p "Enter email for SSL certificate: " email </dev/tty
    
    # Check if domain is pointed to this server
    if ! check_domain_dns "$domain"; then
        print_error "Domain verification failed for $domain"
        read -p "Do you want to proceed without proper DNS configuration? This may cause SSL setup to fail. (y/n): " proceed_anyway </dev/tty
        if [[ $proceed_anyway != "y" && $proceed_anyway != "Y" ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi



    # Setup Nginx and SSL
    setup_nginx "$domain" "$port" "plexstaff"
    setup_ssl "$domain" "$email"
    
    # Ask about creating startup script
    read -p "Do you want to set up auto-start on boot? (y/n): " setup_startup </dev/tty
    if [[ $setup_startup == "y" || $setup_startup == "Y" ]]; then
        create_startup_script "plexstaff" "$install_path"
    fi
    
    print_success "PlexStaff installed successfully"
}

#----- Install PlexStatus -----#
install_plexstatus() {
    print_header "Installing PlexStatus"
    
    local base_path="$INSTALL_DIR/plexstatus"
    
    local product="plexstatus"
    check_existing_installation "$product"
    find_archive_files "$product"

    # Extract product and get the actual path (capture only the last line)
    local install_path=$(extract_product "$ARCHIVE_PATH" "$base_path" | tail -n 1)
    
    # Verify the path exists
    if [ ! -d "$install_path" ]; then
        print_error "Installation path not found: $install_path"
        exit 1
    fi
    
    print_step "Using installation path: $install_path"
    
    # Install NPM dependencies
    install_npm_dependencies "$install_path"
    
    # Get port
    local port
    read -p "Enter port for PlexStatus (default: 3002): " port </dev/tty
    port=${port:-3002}
    # Open port in firewall
    open_port "$port" "PlexStatus"
    
    # Get domain and email
    read -p "Enter domain for PlexStatus (e.g., status.example.com): " domain </dev/tty
    read -p "Enter email for SSL certificate: " email </dev/tty
    


    # Check if domain is pointed to this server
    if ! check_domain_dns "$domain"; then
        print_error "Domain verification failed for $domain"
        read -p "Do you want to proceed without proper DNS configuration? This may cause SSL setup to fail. (y/n): " proceed_anyway </dev/tty
        if [[ $proceed_anyway != "y" && $proceed_anyway != "Y" ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi
    # Setup Nginx and SSL
    setup_nginx "$domain" "$port" "plexstatus"
    setup_ssl "$domain" "$email"
    
    # Ask about creating startup script
    read -p "Do you want to set up auto-start on boot? (y/n): " setup_startup </dev/tty
    if [[ $setup_startup == "y" || $setup_startup == "Y" ]]; then
        create_startup_script "plexstatus" "$install_path"
    fi
    
    print_success "PlexStatus installed successfully"
}

#----- Install PlexStore -----#
install_plexstore() {
    print_header "Installing PlexStore"
    
    local base_path="$INSTALL_DIR/plexstore"
    
    local product="plexstore"
    check_existing_installation "$product"
    find_archive_files "$product"

    # Extract product and get the actual path (capture only the last line)
    local install_path=$(extract_product "$ARCHIVE_PATH" "$base_path" | tail -n 1)
    
    # Verify the path exists
    if [ ! -d "$install_path" ]; then
        print_error "Installation path not found: $install_path"
        exit 1
    fi
    
    print_step "Using installation path: $install_path"
    
    # Install NPM dependencies
    install_npm_dependencies "$install_path"
    
    # Get port
    local port
    read -p "Enter port for PlexStore (default: 3003): " port </dev/tty
    port=${port:-3003}
    # Open port in firewall
    open_port "$port" "PlexStore"
    
    # Get domain and email
    read -p "Enter domain for PlexStore (e.g., store.example.com): " domain </dev/tty
    read -p "Enter email for SSL certificate: " email </dev/tty
    
    # Check if domain is pointed to this server
    if ! check_domain_dns "$domain"; then
        print_error "Domain verification failed for $domain"
        read -p "Do you want to proceed without proper DNS configuration? This may cause SSL setup to fail. (y/n): " proceed_anyway </dev/tty
        if [[ $proceed_anyway != "y" && $proceed_anyway != "Y" ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi



    # Setup Nginx and SSL with special 502 page
    setup_nginx "$domain" "$port" "plexstore"
    setup_ssl "$domain" "$email"
    
    # Create 502 error page in the correct location
    sudo tee "$install_path/502.html" > /dev/null << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PlexStore - Service Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        p { font-size: 18px; }
    </style>
</head>
<body>
    <h1>502 - Service Unavailable</h1>
    <p>The PlexStore service is currently unavailable. Please try again later.</p>
    <p>If this issue persists, please contact the administrator.</p>
</body>
</html>
EOF
    
    # Ask about creating startup script
    read -p "Do you want to set up auto-start on boot? (y/n): " setup_startup </dev/tty
    if [[ $setup_startup == "y" || $setup_startup == "Y" ]]; then
        create_startup_script "plexstore" "$install_path"
    fi
    
    print_success "PlexStore installed successfully"
}

#----- Install PlexForms -----#
install_plexforms() {
    print_header "Installing PlexForms"
    
    local base_path="$INSTALL_DIR/plexforms"
    
    local product="plexforms"
    check_existing_installation "$product"
    find_archive_files "$product"

    # Extract product and get the actual path (capture only the last line)
    local install_path=$(extract_product "$ARCHIVE_PATH" "$base_path" | tail -n 1)
    
    # Verify the path exists
    if [ ! -d "$install_path" ]; then
        print_error "Installation path not found: $install_path"
        exit 1
    fi
    
    print_step "Using installation path: $install_path"
    
    # Install NPM dependencies
    install_npm_dependencies "$install_path"
    
    # Get port
    local port
    read -p "Enter port for PlexForms (default: 3004): " port </dev/tty
    port=${port:-3004}
    # Open port in firewall
    open_port "$port" "PlexForms"
    
    # Get domain and email
    read -p "Enter domain for PlexForms (e.g., forms.example.com): " domain </dev/tty
    read -p "Enter email for SSL certificate: " email </dev/tty
    
    # Check if domain is pointed to this server
    if ! check_domain_dns "$domain"; then
        print_error "Domain verification failed for $domain"
        read -p "Do you want to proceed without proper DNS configuration? This may cause SSL setup to fail. (y/n): " proceed_anyway </dev/tty
        if [[ $proceed_anyway != "y" && $proceed_anyway != "Y" ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi


    # Setup Nginx and SSL
    setup_nginx "$domain" "$port" "plexforms"
    setup_ssl "$domain" "$email"
    
    # Ask about creating startup script
    read -p "Do you want to set up auto-start on boot? (y/n): " setup_startup </dev/tty
    if [[ $setup_startup == "y" || $setup_startup == "Y" ]]; then
        create_startup_script "plexforms" "$install_path"
    fi
    
    print_success "PlexForms installed successfully"
}

#----- Main Script -----#
install() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  _____  _           _____                 _                                  _   "
    echo " |  __ \| |         |  __ \               | |                                | |  "
    echo " | |__) | | _____  _| |  | | _____   _____| | ___  _ __  _ __ ___   ___ _ __ | |_ "
    echo " |  ___/| |/ _ \ \/ / |  | |/ _ \ \ / / _ \ |/ _ \| '_ \| '_ \` _ \ / _ \ '_ \| __|"
    echo " | |    | |  __/>  <| |__| |  __/\ V /  __/ | (_) | |_) | | | | | |  __/ | | | |_ "
    echo " |_|    |_|\___/_/\_\_____/ \___| \_/ \___|_|\___/| .__/|_| |_| |_|\___|_| |_|\__|"
    echo "                                                  | |                             "
    echo "                                                  |_|                             "
    echo -e "${NC}"
    echo -e "${BOLD}${PURPLE}Installation Script for PlexDevelopment Products${NC}\n"

    
    # Detect system
    detect_system
    
    # Install dependencies
    install_dependencies
    
    # Create install directory
    sudo mkdir -p $INSTALL_DIR
    sleep 6
}
main(){
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  _____  _           _____                 _                                  _   "
    echo " |  __ \| |         |  __ \               | |                                | |  "
    echo " | |__) | | _____  _| |  | | _____   _____| | ___  _ __  _ __ ___   ___ _ __ | |_ "
    echo " |  ___/| |/ _ \ \/ / |  | |/ _ \ \ / / _ \ |/ _ \| '_ \| '_ \` _ \ / _ \ '_ \| __|"
    echo " | |    | |  __/>  <| |__| |  __/\ V /  __/ | (_) | |_) | | | | | |  __/ | | | |_ "
    echo " |_|    |_|\___/_/\_\_____/ \___| \_/ \___|_|\___/| .__/|_| |_| |_|\___|_| |_|\__|"
    echo "                                                  | |                             "
    echo "                                                  |_|                             "
    echo -e "${NC}"
    echo -e "${BOLD}${PURPLE}Installation Script for PlexDevelopment Products${NC}\n"


    # Product selection menu
    print_header "Product Selection"
    
    echo -e "${YELLOW}Please select an option:${NC}"
    echo -e "${CYAN}1) Install PlexTickets${NC}"
    echo -e "${CYAN}2) Install PlexStaff${NC}" 
    echo -e "${CYAN}3) Install PlexStatus${NC}"
    echo -e "${CYAN}4) Install PlexStore${NC}"
    echo -e "${CYAN}5) Install PlexForms${NC}"
    echo -e "${CYAN}6) Manage Existing Installations${NC}"
    echo -e "${CYAN}7) System Health Check${NC}"
    echo -e "${CYAN}8) Manage Backups${NC}"
    echo -e "${CYAN}0) Exit${NC}"
    

    read -p "Enter your choice: " choice </dev/tty


    case $choice in
        1)
            read -p "Install with dashboard? (y/n): " dashboard </dev/tty
            
            if [[ $dashboard == "y" || $dashboard == "Y" ]]; then
                install_plextickets true
            else
                install_plextickets false
            fi
            ;;
        2)
            install_plexstaff
            ;;
        3)
            install_plexstatus
            ;;
        4)
            install_plexstore
            ;;
        5)
            install_plexforms
            ;;
        6)
            manage_installations
            main  # Return to main menu after management
            ;;
        7)
            system_health_check
            read -p "Press Enter to return to the main menu..." </dev/tty
            main
            ;;
        8)
            manage_backups
            main  # Return to main menu after backup management
            ;;
        0)
            print_warning "Installation canceled"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    print_header "Installation Complete"
    print_success "Thank you for using PlexDevelopment Installer!"
}
install
# Run the main function
main
