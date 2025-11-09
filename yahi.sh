#!/usr/bin/env bash

# Yet-Another-Hardware-Info
# Server Hardware and Disk Health Monitoring Script
# Compatible with most Linux distributions and terminal types

VERSION="v1"

# Parse command line arguments
EXTENDED_MODE=0
OUTPUT_FILE=""
TEST_MODE=0
while getopts "ehto:" opt; do
    case $opt in
        e)
            EXTENDED_MODE=1
            ;;
        t)
            TEST_MODE=1
            ;;
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        h)
            echo "Usage: $0 [-e] [-t] [-o FILE] [-h]"
            echo "  -e         Extended mode (show all details)"
            echo "  -t         Test mode (run I/O benchmarks on disks and RAM)"
            echo "  -o FILE    Write output to file (also displays to screen)"
            echo "  -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0           # Quick overview"
            echo "  $0 -e        # Extended details"
            echo "  $0 -t        # With I/O performance tests"
            echo "  $0 -e -t     # Extended details + tests"
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Setup output redirection if specified
if [ -n "$OUTPUT_FILE" ]; then
    exec > >(tee "$OUTPUT_FILE") 2>&1
fi

# Cache system info
ARCH=$(uname -m)
KERNEL=$(uname -r)

# Track critical issues for exit code (using array)
critical_issues_arr=()

# Color support detection (works with any terminal)
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    COLORS=$(tput colors 2>/dev/null || echo 0)
    if [ "$COLORS" -ge 8 ]; then
        BOLD=$(tput bold 2>/dev/null || echo '')
        RESET=$(tput sgr0 2>/dev/null || echo '')
        BLUE=$(tput setaf 4 2>/dev/null || echo '')
        GREEN=$(tput setaf 2 2>/dev/null || echo '')
        YELLOW=$(tput setaf 3 2>/dev/null || echo '')
        RED=$(tput setaf 1 2>/dev/null || echo '')
    fi
fi

# Detect WSL (Windows Subsystem for Linux) environment
IS_WSL=0
if [ -f /proc/version ] && grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
    IS_WSL=1
elif [ -f /proc/sys/kernel/osrelease ] && grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; then
    IS_WSL=1
elif [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ]; then
    IS_WSL=1
fi

# Check for missing dependencies and sudo status
missing_pkgs=()
needs_sudo=""
has_smartctl=0
has_dmidecode=0
has_mdadm=0
has_lsblk=0
has_lscpu=0
has_lspci=0

# Check if we're running as root (POSIX-compliant method)
if [ "$(id -u)" -ne 0 ]; then
    needs_sudo=1
fi

# Helper function to find a binary and update status
check_dependency() {
    local cmd="$1"
    local bin_var_name="$2"
    local has_var_name="$3"
    local pkg_name="${4:-$cmd}"
    local bin_path=""
    
    if bin_path=$(command -v "$cmd" 2>/dev/null); then
        : # Found in PATH
    elif [ -x "/usr/sbin/$cmd" ]; then
        bin_path="/usr/sbin/$cmd"
    elif [ -x "/sbin/$cmd" ]; then
        bin_path="/sbin/$cmd"
    fi
    
    if [ -n "$bin_path" ]; then
        eval "$bin_var_name=\"$bin_path\""
        eval "$has_var_name=1"
    else
        missing_pkgs+=("$pkg_name")
        eval "$has_var_name=0"
    fi
}

# Check for dependencies using helper function
SMARTCTL_BIN=""
DMIDECODE_BIN=""
MDADM_BIN=""

check_dependency "smartctl" "SMARTCTL_BIN" "has_smartctl" "smartmontools"
check_dependency "dmidecode" "DMIDECODE_BIN" "has_dmidecode"
check_dependency "mdadm" "MDADM_BIN" "has_mdadm"

# Check for other commonly used tools (simpler checks)
if command -v lsblk >/dev/null 2>&1; then
    has_lsblk=1
fi

if command -v lscpu >/dev/null 2>&1; then
    has_lscpu=1
fi

if command -v lspci >/dev/null 2>&1; then
    has_lspci=1
fi

    # Collect warnings/notices to show at end
    END_WARNINGS=""
    END_NOTICES=""

    # Function to print section headers (YABS-style)
    print_header() {
        echo ""
        echo "$1:"
        echo "---------------------------------"
    }

    # Function to print key-value pairs (YABS-style)
    print_info() {
        printf "%-14s : %s\n" "$1" "$2"
    }

    # Print YABS-style banner
    echo ""
    if [ "$IS_WSL" -eq 1 ]; then
        echo "${YELLOW}⚠  WSL (Windows Subsystem for Linux) detected${RESET}"
        echo "${YELLOW}   Hardware monitoring features will be limited${RESET}"
        echo ""
    fi
    echo "# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #"
    echo "#                                                     #"
    
    # Calculate centering for title
    title="Yet-Another-Hardware-Info"
    box_width=53  # Width between the # marks
    title_len=${#title}
    pad=$(( (box_width - title_len) / 2 ))
    printf "#%*s%s%*s#\n" $pad "" "$title" $((box_width - title_len - pad)) ""
    
    # Calculate centering for version
    version_len=${#VERSION}
    pad=$(( (box_width - version_len) / 2 ))
    printf "#%*s%s%*s#\n" $pad "" "$VERSION" $((box_width - version_len - pad)) ""
    
    echo "#                                                     #"
    echo "# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #"
    echo ""
    date

    # System Information
    print_header "Basic System Information"
    print_info "Hostname" "$(hostname)"

    # Uptime - more portable and locale-independent
    if command -v uptime >/dev/null 2>&1 && uptime -p >/dev/null 2>&1; then
        print_info "Uptime" "$(uptime -p)"
    else
        # Fallback using /proc/uptime (works on all Linux)
        if [ -f /proc/uptime ]; then
            uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
            uptime_days=$((uptime_seconds / 86400))
            uptime_hours=$(((uptime_seconds % 86400) / 3600))
            uptime_mins=$(((uptime_seconds % 3600) / 60))
            
            if [ $uptime_days -gt 0 ]; then
                uptime_str="${uptime_days}d ${uptime_hours}h ${uptime_mins}m"
            elif [ $uptime_hours -gt 0 ]; then
                uptime_str="${uptime_hours}h ${uptime_mins}m"
            else
                uptime_str="${uptime_mins}m"
            fi
            print_info "Uptime" "$uptime_str"
        else
            # Last resort fallback
            print_info "Uptime" "$(uptime | sed 's/.*up \([^,]*\),.*/\1/' 2>/dev/null || echo 'Unknown')"
        fi
    fi

    if [ "$EXTENDED_MODE" -eq 1 ]; then
        print_info "Current Time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    fi

    # CPU Information
    if [ "$has_lscpu" -eq 1 ]; then
        cpu_model=$(lscpu 2>/dev/null | awk -F': +' '/Model name/{print $2; exit}')
        cpu_threads=$(lscpu 2>/dev/null | awk -F': +' '/^CPU\(s\):/{print $2}')
    elif [ -f /proc/cpuinfo ]; then
        cpu_model=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)
        cpu_threads=$(grep -c "^processor" /proc/cpuinfo)
    else
        cpu_model="Unknown"
        cpu_threads="N/A"
    fi
    cpu_cores=$(command -v nproc >/dev/null 2>&1 && nproc 2>/dev/null || echo "$cpu_threads")
    print_info "CPU" "$cpu_model ($cpu_cores cores / $cpu_threads threads)"

    if [ "$EXTENDED_MODE" -eq 1 ]; then
        print_info "Architecture" "$ARCH"
    fi

    # Memory Information
    print_header "Memory Information"

    if [ "$IS_WSL" -eq 1 ]; then
        # WSL doesn't have access to DMI/SMBIOS tables
        mem_total=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null)
        print_info "Total RAM" "$mem_total"
        END_NOTICES="${END_NOTICES}  • WSL detected: Hardware details unavailable (dmidecode requires physical hardware access)\n"
    elif [ "$has_dmidecode" -eq 1 ]; then
        # Test dmidecode permissions first (silent check)
        if $DMIDECODE_BIN -t memory >/dev/null 2>&1; then
            # We have permissions, get full data
            dmi_mem=$($DMIDECODE_BIN -t memory 2>/dev/null)
            
            # Total RAM
            total_ram=$(echo "$dmi_mem" | awk '
                /Size: [0-9]+ GB/{s+=$2} 
                /Size: [0-9]+ MB/{s+=$2/1024} 
                END{if(s>0) printf "%.1f GB", s; else print "N/A"}
            ')
            
            # RAM Type
            ram_type=$(echo "$dmi_mem" | awk -F': +' '
                /Type: DDR|Type: SDR/{
                    if($2!="Unknown" && $2!="" && $2!="<OUT OF SPEC>"){
                        print $2; 
                        exit
                    }
                }
            ')
            
            # RAM Speed
            ram_speed=$(echo "$dmi_mem" | awk -F': +' '/Speed: [0-9]+ MT/{print $2; exit}')
            
            # Combine display
            ram_info="$total_ram"
            [ -n "$ram_type" ] && ram_info="$ram_info | $ram_type"
            [ -n "$ram_speed" ] && ram_info="$ram_info @ $ram_speed"
            print_info "Total RAM" "$ram_info"
            
            # ECC Status
            ecc_status=$(echo "$dmi_mem" | awk -F': +' '
                /Error Correction Type/{
                    if($2=="None") print "Non-ECC"
                    else if($2!="Unknown" && $2!="") print "ECC (" $2 ")"
                    else print $2
                    exit
                }
            ')
            [ -n "$ecc_status" ] && print_info "ECC Support" "$ecc_status"
            
            # Individual RAM Sticks - only in extended mode
            if [ "$EXTENDED_MODE" -eq 1 ]; then
                echo ""
                echo "${BOLD}RAM Modules:${RESET}"
                echo "$dmi_mem" | awk '
                    function print_device() {
                        if (size && size !~ /No Module/) {
                            slot++
                            info = size
                            if(type && type!="Unknown" && type!="<OUT OF SPEC>") info = info " | " type
                            if(speed && speed!="Unknown") info = info " @ " speed
                            printf "  Slot %d (%s): %s\n", slot, (locator ? locator : "N/A"), info
                            if(mfr && mfr!="NO DIMM" && mfr!="Unknown") printf "    Mfr: %s", mfr
                            if(part && part!="NO DIMM" && part!="Unknown") printf " | Part: %s", part
                            if(serial && serial!="NO DIMM" && serial!="Unknown" && serial!="SerNum00") printf " | SN: %s", serial
                            if(mfr && mfr!="NO DIMM" && mfr!="Unknown") printf "\n"
                        }
                    }
                    /^Memory Device$/ {
                        if (in_device) print_device()
                        in_device=1
                        size=locator=type=speed=mfr=part=serial=""
                        next
                    }
                    in_device {
                        if ($0 ~ /Size:/) { size = $0; sub(/^[^:]*: */, "", size) }
                        if ($0 ~ /Locator:/ && $0 !~ /Bank Locator/) { locator = $0; sub(/^[^:]*: */, "", locator) }
                        if ($0 ~ /Type: DDR|Type: SDR/) { type = $0; sub(/^[^:]*: */, "", type) }
                        if ($0 ~ /Speed: [0-9]+ MT/) { speed = $0; sub(/^[^:]*: */, "", speed) }
                        if ($0 ~ /Manufacturer:/) { mfr = $0; sub(/^[^:]*: */, "", mfr) }
                        if ($0 ~ /Part Number:/) { part = $0; sub(/^[^:]*: */, "", part) }
                        if ($0 ~ /Serial Number:/) { serial = $0; sub(/^[^:]*: */, "", serial) }
                    }
                    END { if (in_device) print_device() }
                '
            fi
            
            # Motherboard Info - only in extended mode
            if [ "$EXTENDED_MODE" -eq 1 ]; then
                echo ""
                dmi_board=$($DMIDECODE_BIN -t baseboard 2>/dev/null)
                mb_mfr=$(echo "$dmi_board" | awk -F': +' '/Manufacturer:/{print $2; exit}')
                mb_prod=$(echo "$dmi_board" | awk -F': +' '/Product Name:/{print $2; exit}')
                mb_ver=$(echo "$dmi_board" | awk -F': +' '/Version:/{print $2; exit}')
                mb_serial=$(echo "$dmi_board" | awk -F': +' '/Serial Number:/{print $2; exit}')
                
                if [ -n "$mb_mfr" ] && [ -n "$mb_prod" ]; then
                    mb_info="$mb_mfr $mb_prod"
                    [ -n "$mb_ver" ] && [ "$mb_ver" != "Not Specified" ] && mb_info="$mb_info | Ver: $mb_ver"
                    [ -n "$mb_serial" ] && [ "$mb_serial" != "Not Specified" ] && mb_info="$mb_info | SN: $mb_serial"
                    print_info "Motherboard" "$mb_info"
                fi
            fi
        else
            # Permission denied - show basic info, save warning for end
            mem_total=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null)
            print_info "Total RAM" "$mem_total"
            END_NOTICES="${END_NOTICES}  • Run 'sudo $0' for detailed RAM/hardware information\n"
        fi
    else
        # dmidecode not installed
        mem_total=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null)
        print_info "Total RAM" "$mem_total"
    fi

    # GPU Information (only show if found)
    if [ "$has_lspci" -eq 1 ]; then
        # Use lspci with class codes for accurate GPU detection
        # Class 0300 = VGA compatible controller
        # Class 0302 = 3D controller
        # Class 0380 = Display controller
        gpu_info=$(lspci -d ::0300 2>/dev/null; lspci -d ::0302 2>/dev/null; lspci -d ::0380 2>/dev/null)
    fi
    
    if [ -n "$gpu_info" ]; then
        print_header "GPU Information"
        echo "$gpu_info" | while IFS= read -r line; do
            # Clean up the line and remove the PCI address
            clean_line=$(echo "$line" | sed 's/^[0-9a-f:.]\+[[:space:]]*//; s/^[A-Z0-9]\+[[:space:]]*controller[[:space:]]*:[[:space:]]*//')
            if [ -n "$clean_line" ]; then
                print_info "GPU" "$clean_line"
            fi
        done
    fi

    # Network Information
    if [ "$EXTENDED_MODE" -eq 1 ]; then
        print_header "Network Interfaces"
        if command -v ip >/dev/null 2>&1; then
            ip -br link show 2>/dev/null | awk -v green="$GREEN" -v yellow="$YELLOW" -v reset="$RESET" 'NR>0{
                iface=$1
                state=$2
                mac=$3
                state_color=state
                if(state=="UP") {
                    state_color = green state reset
                } else if(state=="DOWN") {
                    state_color = yellow state reset
                }
                printf "%-15s %s", iface, state_color
                if(mac && mac!="") printf " [%s]", mac
                printf "\n"
            }'
        elif command -v ifconfig >/dev/null 2>&1; then
            ifconfig -a 2>/dev/null | awk '/^[a-z]/ {print $1}'
        else
            echo "${YELLOW}ip/ifconfig command not available${RESET}"
        fi
    fi

    # Disk Information
    print_header "Storage Devices"
    if [ "$has_lsblk" -eq 1 ]; then
        if [ "$EXTENDED_MODE" -eq 1 ]; then
            printf "${BOLD}%-13s %-10s %-10s %-15s${RESET}\n" "DEVICE" "SIZE" "TYPE" "MODEL"
            lsblk -bdno NAME,SIZE,ROTA,MODEL 2>/dev/null | awk '
                {
                    dev="/dev/"$1
                    size=sprintf("%.1f GB", $2/1000000000)
                    type=($3==1?"HDD":"SSD/NVMe")
                    model=""
                    for(i=4;i<=NF;i++) model=model" "$i
                    gsub(/^ +/, "", model)
                    printf "%-13s %-10s %-10s %-15s\n", dev, size, type, model
                }
            '
        else
            printf "${BOLD}%-13s %-10s %-10s${RESET}\n" "DEVICE" "SIZE" "TYPE"
            lsblk -bdno NAME,SIZE,ROTA 2>/dev/null | awk '
                {
                    dev="/dev/"$1
                    size=sprintf("%.1f GB", $2/1000000000)
                    type=($3==1?"HDD":"SSD/NVMe")
                    printf "%-13s %-10s %-10s\n", dev, size, type
                }
            '
        fi
    fi

    # Detailed Disk Health
    print_header "Disk Health & S.M.A.R.T. Data"

    # Store disk list for later testing (needed for performance tests)
    DISK_LIST=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2~/disk|nvme/{print $1}')
    
    if [ "$IS_WSL" -eq 1 ]; then
        # WSL doesn't have access to physical disk hardware
        print_info "Status" "WSL environment detected - S.M.A.R.T. data unavailable"
        END_NOTICES="${END_NOTICES}  • WSL detected: Disk health monitoring requires physical hardware access\n"
    elif [ "$has_smartctl" -eq 0 ]; then
        print_info "Status" "smartmontools not available"
    else
        smart_works=0
        permission_issue=0
        
        for disk in $DISK_LIST; do
            echo ""
            echo "${BOLD}${GREEN}▸  /dev/$disk${RESET}"
            
            # Get full SMART data (with NVMe support)
            full_smart=""
            nvme_device=0
            if [[ "$disk" == nvme* ]] && command -v nvme >/dev/null 2>&1; then
                # Use nvme-cli for NVMe drives
                nvme_device=1
                full_smart=$(LC_ALL=C nvme smart-log /dev/"$disk" 2>/dev/null)
            else
                # Fallback to smartctl for SATA/SAS drives
                full_smart=$(LC_ALL=C $SMARTCTL_BIN -a /dev/$disk 2>&1)
            fi
            
            # Check if we got permission denied
            if echo "$full_smart" | grep -q "Permission denied\|You must be root\|Operation not permitted"; then
                permission_issue=1
                # Try to get basic info from lsblk at least
                disk_model=$(lsblk -dno MODEL /dev/$disk 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                disk_size=$(lsblk -dno SIZE /dev/$disk 2>/dev/null)
                info_line=""
                [ -n "$disk_model" ] && info_line="$disk_model"
                [ -n "$disk_size" ] && info_line="$info_line ($disk_size)"
                [ -n "$info_line" ] && print_info "Info" "$info_line"
                print_info "Status" "Requires sudo for SMART data"
                continue
            fi
            
            smart_works=1
            
            # Model and Health combined
            if [ "$nvme_device" -eq 1 ]; then
                # NVMe device - get model from lsblk and check critical warning
                model=$(lsblk -dno MODEL /dev/$disk 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # NVMe doesn't have simple health status, check critical_warning field
                critical_warning=$(echo "$full_smart" | awk -F': ' '/^critical_warning/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
                if [ "$critical_warning" = "0" ] || [ "$critical_warning" = "0x0" ]; then
                    health="OK"
                elif [ -n "$critical_warning" ]; then
                    health="WARNING"
                fi
            else
                # SATA/SAS device
                model=$(echo "$full_smart" | awk -F': +' '/Device Model|Model Number/{print $2; exit}')
                health=$(echo "$full_smart" | awk -F': +' '/SMART overall-health|SMART Health Status/{print $2; exit}')
            fi
            
            model_line="$model"
            if [ "$health" = "PASSED" ] || [ "$health" = "OK" ]; then
                [ -n "$model_line" ] && model_line="$model_line | Health: ${GREEN}${health}${RESET}" || model_line="Health: ${GREEN}${health}${RESET}"
            elif [ -n "$health" ]; then
                [ -n "$model_line" ] && model_line="$model_line | Health: ${RED}${health} [CRITICAL]${RESET}" || model_line="Health: ${RED}${health} [CRITICAL]${RESET}"
                critical_issues_arr+=("• /dev/$disk: SMART health check failed (${health})")
            fi
            [ -n "$model_line" ] && print_info "Model" "$model_line"
            
            # Serial Number - only in extended mode
            if [ "$EXTENDED_MODE" -eq 1 ]; then
                serial=$(echo "$full_smart" | awk -F': +' '/Serial Number/{print $2; exit}')
                firmware=$(echo "$full_smart" | awk -F': +' '/Firmware Version/{print $2; exit}')
                serial_line=""
                [ -n "$serial" ] && serial_line="$serial"
                [ -n "$firmware" ] && serial_line="$serial_line | FW: $firmware"
                [ -n "$serial_line" ] && print_info "Serial/FW" "$serial_line"
            fi
            
            # Power-On Hours and Temperature combined
            if [ "$nvme_device" -eq 1 ]; then
                # NVMe parsing
                poh=$(echo "$full_smart" | awk -F': ' '/^power_on_hours/{gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/,/, "", $2); print $2}')
                temp=$(echo "$full_smart" | awk -F': ' '/^temperature/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | sed 's/[^0-9].*//')
            else
                # SATA/SAS parsing
                poh=$(echo "$full_smart" | awk '/Power_On_Hours|Power On Hours/{print $NF; exit}' | sed 's/,//g')
                temp=$(echo "$full_smart" | awk '/Temperature_Celsius/{print $10; exit} /Temperature:/{print $2; exit}')
            fi
            
            stats_line=""
            if [[ "$poh" =~ ^[0-9]+$ ]] && [ "$poh" -gt 0 ]; then
                years=$(awk "BEGIN{printf \"%.1f\", $poh/24/365}")
                if [ "$EXTENDED_MODE" -eq 1 ]; then
                    days=$((poh / 24))
                    stats_line="Uptime: $poh hrs ($days days / ~${years} yrs)"
                else
                    stats_line="Uptime: ~${years} yrs"
                fi
            fi
            
            if [ -n "$temp" ]; then
                temp_str=""
                if [ "${temp:-0}" -gt 60 ]; then
                    temp_str="Temp: ${RED}${temp}°C [CRITICAL]${RESET}"
                    critical_issues_arr+=("• /dev/$disk: Temperature critical (${temp}°C)")
                elif [ "${temp:-0}" -gt 50 ]; then
                    temp_str="Temp: ${RED}${temp}°C${RESET}"
                elif [ "${temp:-0}" -gt 40 ]; then
                    temp_str="Temp: ${YELLOW}${temp}°C${RESET}"
                else
                    temp_str="Temp: ${GREEN}${temp}°C${RESET}"
                fi
                [ -n "$stats_line" ] && stats_line="$stats_line | $temp_str" || stats_line="$temp_str"
            fi
            
            # Power Cycles in extended mode
            if [ "$EXTENDED_MODE" -eq 1 ]; then
                pcc=$(echo "$full_smart" | awk '/Power_Cycle_Count|Power Cycles/{print $NF; exit}' | sed 's/,//g')
                [ -n "$pcc" ] && stats_line="$stats_line | Cycles: $pcc"
            fi
            
            [ -n "$stats_line" ] && print_info "Stats" "$stats_line"
            
            # Total Data Written (TBW) - only in extended mode or if significant
            if [ "$EXTENDED_MODE" -eq 1 ]; then
                tbw=$(echo "$full_smart" | awk '
                    /Data Units Written/{
                        val=$(NF-1)
                        gsub(/,/,"",val)
                        if(val>0){
                            tb=val*512000/1000000000000
                            printf "%.2f", tb
                            exit
                        }
                    }
                ')
                
                if [ -z "$tbw" ] || [ "$tbw" = "0.00" ]; then
                    tbw=$(echo "$full_smart" | awk '
                        /Total_LBAs_Written/{
                            for(i=1;i<=NF;i++){
                                if($i~/^[0-9]+$/ && $i>1000){
                                    lba=$i
                                    tb=lba*512/1000000000000
                                    printf "%.2f", tb
                                    exit
                                }
                            }
                        }
                    ')
                fi
                
                if [ -n "$tbw" ] && [ "$tbw" != "0.00" ]; then
                    print_info "Total Written" "${tbw} TB (approx)"
                fi
            fi
            
            # Wear Level (SSDs) and Sector Issues (HDDs) - combined
            if [ "$nvme_device" -eq 1 ]; then
                # NVMe parsing
                wear=$(echo "$full_smart" | awk -F': ' '/^percentage_used/{gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/%/, "", $2); print $2}')
                # NVMe doesn't track sector issues the same way
                realloc=""
                pending=""
                offline=""
            else
                # SATA/SAS parsing
                wear=$(echo "$full_smart" | awk '/Percentage Used/{print $NF; exit}' | sed 's/%//')
                realloc=$(echo "$full_smart" | awk '$2=="Reallocated_Sector_Ct"{print $NF; exit}')
                pending=$(echo "$full_smart" | awk '$2=="Current_Pending_Sector"{print $NF; exit}')
                offline=$(echo "$full_smart" | awk '$2=="Offline_Uncorrectable"{print $NF; exit}')
            fi
            
            health_line=""
            
            # Wear level for SSDs
            if [ -n "$wear" ]; then
                remaining=$((100 - ${wear:-0}))
                if [ "${wear:-0}" -ge 80 ]; then
                    health_line="${RED}Wear: ${wear}% (${remaining}% left) [CRITICAL]${RESET}"
                    critical_issues_arr+=("• /dev/$disk: High wear level (${wear}%)")
                elif [ "${wear:-0}" -ge 50 ]; then
                    health_line="${RED}Wear: ${wear}%${RESET} (${remaining}% left)"
                elif [ "${wear:-0}" -ge 20 ]; then
                    health_line="${YELLOW}Wear: ${wear}%${RESET} (${remaining}% left)"
                else
                    health_line="${GREEN}Wear: ${wear}%${RESET} (${remaining}% left)"
                fi
            fi
            
            # Sector issues for HDDs
            if [ -n "$realloc" ] && ([ "${realloc:-0}" -gt 0 ] || [ "$EXTENDED_MODE" -eq 1 ]); then
                sector_str=""
                if [ "${realloc:-0}" -gt 0 ]; then
                    sector_str="${YELLOW}Realloc: ${realloc}${RESET}"
                else
                    sector_str="${GREEN}Realloc: ${realloc}${RESET}"
                fi
                [ -n "$health_line" ] && health_line="$health_line | $sector_str" || health_line="$sector_str"
            fi
            
            if [ -n "$pending" ] && [ "${pending:-0}" -gt 0 ]; then
                pending_str="${RED}Pending: ${pending} [CRITICAL]${RESET}"
                [ -n "$health_line" ] && health_line="$health_line | $pending_str" || health_line="$pending_str"
                critical_issues_arr+=("• /dev/$disk: Pending sectors (${pending})")
            fi
            
            if [ -n "$offline" ] && [ "${offline:-0}" -gt 0 ]; then
                offline_str="${RED}Uncorrectable: ${offline} [CRITICAL]${RESET}"
                [ -n "$health_line" ] && health_line="$health_line | $offline_str" || health_line="$offline_str"
                critical_issues_arr+=("• /dev/$disk: Offline uncorrectable sectors (${offline})")
            fi
            
            [ -n "$health_line" ] && print_info "Wear/Sectors" "$health_line"
        done
        
        # Track permission issues for end message
        if [ "$permission_issue" -eq 1 ]; then
            END_NOTICES="${END_NOTICES}  • Run with 'sudo $0' for complete disk health information\n"
        fi
    fi

    # RAID Status (Linux Software RAID)
    if [ "$IS_WSL" -eq 1 ]; then
        # WSL doesn't have software RAID
        : # Skip RAID section in WSL
    elif [ "$has_mdadm" -eq 1 ]; then
        # Check if there are any RAID arrays
        if [ -f /proc/mdstat ] && grep -q "^md" /proc/mdstat 2>/dev/null; then
            print_header "RAID Status"
            
            # Get list of RAID devices
            raid_devices=$(awk '/^md/ {print $1}' /proc/mdstat)
            
            for raid_dev in $raid_devices; do
                echo ""
                echo "${BOLD}${GREEN}▸  /dev/$raid_dev${RESET}"
                
                # Get RAID details
                if [ "$(id -u)" -eq 0 ]; then
                    raid_detail=$($MDADM_BIN --detail /dev/$raid_dev 2>/dev/null)
                    
                    # RAID Level and State
                    raid_level=$(echo "$raid_detail" | awk -F': +' '/Raid Level/{print $2}')
                    raid_state=$(echo "$raid_detail" | awk -F': +' '/State/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
                    
                    raid_info="$raid_level"
                    if [ "$raid_state" = "clean" ] || [ "$raid_state" = "active" ] || [ "$raid_state" = "clean, checking" ]; then
                        raid_info="$raid_info | State: ${GREEN}${raid_state}${RESET}"
                    elif echo "$raid_state" | grep -iq "degraded\|fail\|recover\|resyncing"; then
                        raid_info="$raid_info | State: ${RED}${raid_state} [CRITICAL]${RESET}"
                        critical_issues_arr+=("• /dev/$raid_dev: RAID degraded or failed (${raid_state})")
                    elif [ -n "$raid_state" ]; then
                        raid_info="$raid_info | State: ${YELLOW}${raid_state}${RESET}"
                    fi
                    print_info "RAID Info" "$raid_info"
                    
                    # Array Size
                    array_size=$(echo "$raid_detail" | awk -F': +' '/Array Size/{print $2}')
                    [ -n "$array_size" ] && print_info "Array Size" "$array_size"
                    
                    # Device count
                    total_devices=$(echo "$raid_detail" | awk -F': +' '/Total Devices/{print $2}')
                    active_devices=$(echo "$raid_detail" | awk -F': +' '/Active Devices/{print $2}')
                    working_devices=$(echo "$raid_detail" | awk -F': +' '/Working Devices/{print $2}')
                    failed_devices=$(echo "$raid_detail" | awk -F': +' '/Failed Devices/{print $2}')
                    
                    device_info="Total: $total_devices"
                    [ -n "$active_devices" ] && device_info="$device_info | Active: ${GREEN}${active_devices}${RESET}"
                    [ -n "$working_devices" ] && device_info="$device_info | Working: ${GREEN}${working_devices}${RESET}"
                    if [ -n "$failed_devices" ] && [ "${failed_devices:-0}" -gt 0 ]; then
                        device_info="$device_info | Failed: ${RED}${failed_devices} [CRITICAL]${RESET}"
                        critical_issues_arr+=("• /dev/$raid_dev: $failed_devices failed device(s)")
                    fi
                    print_info "Devices" "$device_info"
                    
                    # Show member devices in extended mode
                    if [ "$EXTENDED_MODE" -eq 1 ]; then
                        echo "  ${BOLD}Member Devices:${RESET}"
                        echo "$raid_detail" | awk '
                            /Number.*Major.*Minor.*RaidDevice.*State/ {in_devices=1; next}
                            in_devices && /^[[:space:]]*$/ {exit}
                            in_devices && NF>0 {
                                state=$NF
                                device=$(NF-1)
                                if(state~/active/) printf "    %s: %s\n", device, state
                                else printf "    %s: %s\n", device, state
                            }
                        '
                    fi
                else
                    # No root - show basic info from /proc/mdstat
                    raid_info=$(grep -A 3 "^$raid_dev " /proc/mdstat | head -2 | tail -1)
                    print_info "Info" "$raid_info"
                    print_info "Status" "Run with sudo for detailed RAID information"
                fi
            done
        fi
    fi

    # Performance Testing
    if [ "$TEST_MODE" -eq 1 ]; then
        print_header "Performance Tests"
        if [ "$IS_WSL" -eq 1 ]; then
            echo "${YELLOW}Note: Running in WSL - results reflect virtualized environment performance${RESET}"
            echo ""
        fi
        echo "${BOLD}${YELLOW}⚠  Running I/O benchmarks (30-60 sec)...${RESET}"
        echo ""
        
        # RAM Speed Test
        if command -v dd >/dev/null 2>&1; then
            # Test RAM write speed using /dev/shm (RAM disk)
            test_size="1G"
            if [ -d /dev/shm ]; then
                ram_test_file="/dev/shm/test_$$"
                trap 'rm -f "$ram_test_file"' EXIT
                echo -n "RAM Write (1GB):      "
                
                # Run dd once and save output (with C locale for consistent number parsing)
                ram_result=$(LC_ALL=C dd if=/dev/zero of="$ram_test_file" bs=1M count=1024 2>&1)
                
                # Try to parse speed directly
                speed=$(echo "$ram_result" | grep -o '[0-9.]* [MG]B/s' | tail -1)
                
                if [ -n "$speed" ]; then
                    echo "${GREEN}${speed}${RESET}"
                else
                    # Parse from older dd format using the same robust method as the disk test
                    bytes=$(echo "$ram_result" | awk '/copied/{for(i=1;i<=NF;i++){if($i~/^[0-9]+$/&&$(i+1)=="bytes"){print $i; exit}}}')
                    time=$(echo "$ram_result" | awk '/copied/{for(i=1;i<=NF;i++){if($i~/^[0-9.]+$/&&$(i+1)~/^[s,]/){print $i; exit}}}')
                    
                    if [ -n "$bytes" ] && [ -n "$time" ] && [ "$(awk "BEGIN{print ($time > 0)}")" -eq 1 ]; then
                        speed=$(awk "BEGIN{printf \"%.1f MB/s\", $bytes/$time/1024/1024}")
                        echo "${GREEN}${speed}${RESET}"
                    else
                        echo "${YELLOW}Unable to parse${RESET}"
                    fi
                fi
                
                rm -f "$ram_test_file" 2>/dev/null
                trap - EXIT
            else
                echo "${YELLOW}/dev/shm not available - skipping RAM test${RESET}"
            fi
        else
            echo "${RED}dd command not found${RESET}"
        fi
        
        # Disk I/O Tests
        if command -v dd >/dev/null 2>&1; then
            # Find writable mount points for each disk
            for disk in $DISK_LIST; do
                mount_point=""
                
                # First, try direct disk mount
                mount_point=$(df 2>/dev/null | grep "^/dev/$disk" | awk '{print $NF}' | head -1)
                
                # If not found, try to find partition
                if [ -z "$mount_point" ]; then
                    partition=$(lsblk -lno NAME,TYPE 2>/dev/null | grep "^${disk}.*part" | head -1 | awk '{print $1}')
                    if [ -n "$partition" ]; then
                        mount_point=$(df 2>/dev/null | grep "^/dev/$partition" | awk '{print $NF}' | head -1)
                    fi
                fi
                
                # If still not found, use lsblk tree to find any mounted device using this disk
                # This handles RAID, LVM, partitions, etc. by checking all children recursively
                if [ -z "$mount_point" ]; then
                    # Get all devices that are children of this disk (including RAID, LVM, partitions)
                    # lsblk -nro NAME,MOUNTPOINT shows the tree with mount points
                    # Find the first device with a non-empty mount point
                    mount_point=$(lsblk -nro NAME,MOUNTPOINT /dev/$disk 2>/dev/null | awk -v disk="$disk" '
                        BEGIN { found_disk=0 }
                        $1 == disk { found_disk=1; next }
                        found_disk {
                            if ($2 && $2 != "" && $2 != "/") {
                                print $2
                                exit
                            }
                        }
                    ' | head -1)
                    
                    # Alternative: check all mounted filesystems and find which device uses this disk
                    if [ -z "$mount_point" ]; then
                        # Get all children of this disk recursively
                        all_children=$(lsblk -nro NAME /dev/$disk 2>/dev/null | grep -v "^${disk}$")
                        
                        # Check each mounted filesystem
                        while IFS= read -r mount_line; do
                            device=$(echo "$mount_line" | awk '{print $1}' | sed 's|/dev/||')
                            mp=$(echo "$mount_line" | awk '{print $NF}')
                            
                            # Check if this device is a child of our disk
                            if echo "$all_children" | grep -q "^${device}$"; then
                                mount_point="$mp"
                                break
                            fi
                        done < <(df 2>/dev/null | tail -n +2 | grep "^/dev/")
                    fi
                fi
                
                if [ -n "$mount_point" ] && [ -w "$mount_point" ]; then
                    # Check available space (need at least 300MB for safety)
                    available_mb=$(df -m "$mount_point" 2>/dev/null | awk 'NR==2{print $4}')
                    if [ -z "$available_mb" ] || [ "$available_mb" -lt 300 ]; then
                        echo "/dev/$disk: ${YELLOW}Insufficient space on mount point${RESET}"
                        continue
                    fi
                    
                    disk_type=$(lsblk -dno ROTA /dev/$disk 2>/dev/null)
                    if [ "$disk_type" = "1" ]; then
                        type_label="HDD"
                    else
                        type_label="SSD"
                    fi
                    
                    printf "%-14s %-4s: " "/dev/$disk" "($type_label)"
                    
                    test_file="${mount_point}/.hwtest_$$"
                    trap 'rm -f "$test_file"' EXIT
                    
                    # Quick 256MB test with sync (with C locale for consistent number parsing)
                    disk_result=$(LC_ALL=C dd if=/dev/zero of="$test_file" bs=64k count=4096 conv=fdatasync 2>&1)
                    
                    # Parse speed
                    speed=$(echo "$disk_result" | grep -o '[0-9.]* [MG]B/s' | tail -1)
                    
                    if [ -n "$speed" ]; then
                        # Color code based on type and speed
                        speed_value=$(echo "$speed" | awk '{print $1}')
                        speed_unit=$(echo "$speed" | awk '{print $2}')
                        
                        if [ "$speed_unit" = "GB/s" ]; then
                            echo "${GREEN}${speed}${RESET}"
                        elif [ "$disk_type" = "1" ]; then
                            # HDD expectations: >100 MB/s is good
                            if [ "$(awk "BEGIN{print ($speed_value > 100)}")" -eq 1 ]; then
                                echo "${GREEN}${speed}${RESET}"
                            elif [ "$(awk "BEGIN{print ($speed_value > 50)}")" -eq 1 ]; then
                                echo "${YELLOW}${speed}${RESET}"
                            else
                                echo "${RED}${speed} [SLOW]${RESET}"
                            fi
                        else
                            # SSD/NVMe expectations: >200 MB/s is good
                            if [ "$(awk "BEGIN{print ($speed_value > 200)}")" -eq 1 ]; then
                                echo "${GREEN}${speed}${RESET}"
                            elif [ "$(awk "BEGIN{print ($speed_value > 100)}")" -eq 1 ]; then
                                echo "${YELLOW}${speed}${RESET}"
                            else
                                echo "${RED}${speed} [SLOW]${RESET}"
                            fi
                        fi
                    else
                        # Parse from older dd format
                        bytes=$(echo "$disk_result" | awk '/copied/{for(i=1;i<=NF;i++){if($i~/^[0-9]+$/&&$(i+1)=="bytes"){print $i; exit}}}')
                        time=$(echo "$disk_result" | awk '/copied/{for(i=1;i<=NF;i++){if($i~/^[0-9.]+$/&&$(i+1)~/^[s,]/){print $i; exit}}}')
                        
                        if [ -n "$bytes" ] && [ -n "$time" ]; then
                            speed=$(awk "BEGIN{printf \"%.1f MB/s\", $bytes/$time/1024/1024}")
                            echo "${GREEN}${speed}${RESET}"
                        else
                            echo "${YELLOW}Unable to parse${RESET}"
                        fi
                    fi
                    
                    rm -f "$test_file" 2>/dev/null
                    trap - EXIT
                else
                    echo "/dev/$disk: ${YELLOW}No writable mount point found${RESET}"
                fi
            done
        else
            echo "${RED}dd command not found${RESET}"
        fi
        echo "${BLUE}ℹ  Tests: 1GB RAM, 256MB disk. Use 'fio' for detailed benchmarks.${RESET}"
    fi

    # OS Information
    print_header "Operating System"
    os_name=$(cat /etc/os-release 2>/dev/null | awk -F'=' '/^PRETTY_NAME/{gsub(/"/, "", $2); print $2}')
    kernel_info="$KERNEL"
    if [ "$EXTENDED_MODE" -eq 1 ]; then
        kernel_info="$kernel_info | $ARCH"
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
        [ -n "$load_avg" ] && kernel_info="$kernel_info | Load: $load_avg"
    fi
    [ -n "$os_name" ] && print_info "Distribution" "$os_name"
    print_info "Kernel" "$kernel_info"

    # Footer with warnings/notices (YABS-style)
    echo ""

    # Show critical issues first if any
    if [ ${#critical_issues_arr[@]} -gt 0 ]; then
        echo "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo "${BOLD}${RED}  ⚠  CRITICAL HARDWARE ALERTS DETECTED${RESET}"
        echo ""
        printf '  %s\n' "${critical_issues_arr[@]}"
        echo ""
        echo "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo ""
    fi

    # Show missing packages warning at end
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        pkgs_list="${missing_pkgs[*]}"
        echo "${YELLOW}Missing packages:${RESET} $pkgs_list"
        echo "Install: sudo apt install $pkgs_list (Debian/Ubuntu)"
        echo "     or: sudo dnf install $pkgs_list (RHEL/Fedora)"
        echo ""
    fi

    # Show other notices at end
    if [ -n "$END_NOTICES" ]; then
        echo "${BLUE}Notes:${RESET}"
        echo -e "$END_NOTICES"
    fi

    # Exit with appropriate code if critical issues found
    if [ ${#critical_issues_arr[@]} -gt 0 ]; then
        exit 2
    fi

    exit 0
