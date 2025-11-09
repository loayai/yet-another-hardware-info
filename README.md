# Yet-Another-Hardware-Info

A comprehensive server hardware information and health monitoring script for Linux systems. Displays detailed system information, disk health (S.M.A.R.T. data), RAID status, and optional performance benchmarks.

## How to Run

**Using curl:**
```bash
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash
```

**Using wget:**
```bash
wget -qO- https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash
```

**Download first, then run:**
```bash
wget https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh
chmod +x yahi.sh
sudo ./yahi.sh
```

## Usage

### Command-Line Options

| Option | Description |
|--------|-------------|
| `-e` | Extended mode - Shows additional details including RAM modules, motherboard info, network interfaces, disk serial numbers, firmware versions, and power cycles |
| `-t` | Test mode - Runs I/O performance benchmarks on RAM and all disks (takes 30-60 seconds) |
| `-o FILE` | Write output to file while also displaying to screen |
| `-h` | Show help message |

### Usage Examples

```bash
# Quick overview (basic information)
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash

# Extended details (all hardware information)
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash -s -- -e

# With I/O performance tests
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash -s -- -t

# Extended details + performance tests
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash -s -- -e -t

# Save output to file
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | sudo bash -s -- -e -t -o hardware-report.txt

# Show help
curl -sL https://raw.githubusercontent.com/loayai/yet-another-hardware-info/master/yahi.sh | bash -s -- -h
```

### Running Without Sudo

The script can run without `sudo`, but with limited functionality:
- Basic system information will be shown
- Disk health (S.M.A.R.T.) data will be unavailable
- Detailed RAM information will be unavailable
- RAID details will be limited

The script will display notices about missing information when run without sufficient permissions.

## Example Output

```
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
#                                                     #
#              Yet-Another-Hardware-Info              #
#                         v1                          #
#                                                     #
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

Sun Nov  9 13:43:21 UTC 2025

Basic System Information:
---------------------------------
Hostname       : ks-le-b
Uptime         : up 3 days, 28 minutes
CPU            : Intel(R) Xeon(R) CPU E3-1270 v6 @ 3.80GHz (8 cores / 8 threads)

Memory Information:
---------------------------------
Total RAM      : 64.0 GB | DDR4 @ 2400 MT/s
ECC Support    : ECC (Single-bit ECC)

GPU Information:
---------------------------------
GPU            : VGA compatible controller: Matrox Electronics Systems Ltd. MGA G200e [Pilot] ServerEngines (SEP1) (rev 05)

Storage Devices:
---------------------------------
DEVICE        SIZE       TYPE
/dev/sda      2000.4 GB  HDD
/dev/sdb      2000.4 GB  HDD
/dev/nvme1n1  450.1 GB   SSD/NVMe
/dev/nvme0n1  450.1 GB   SSD/NVMe

Disk Health & S.M.A.R.T. Data:
---------------------------------

▸  /dev/sda
Model          : HGST HUS726020ALA610 | Health: PASSED
Stats          : Uptime: ~6.2 yrs | Temp: 31°C

▸  /dev/sdb
Model          : HGST HUS726020ALA610 | Health: PASSED
Stats          : Uptime: ~6.2 yrs | Temp: 32°C

▸  /dev/nvme1n1
Model          : INTEL SSDPE2MX450G7 | Health: PASSED
Stats          : Uptime: ~6.2 yrs | Temp: 18°C
Wear/Sectors   : Wear: 16% (84% left)

▸  /dev/nvme0n1
Model          : INTEL SSDPE2MX450G7 | Health: PASSED
Stats          : Uptime: ~6.3 yrs | Temp: 18°C
Wear/Sectors   : Wear: 16% (84% left)

RAID Status:
---------------------------------

▸  /dev/md3
RAID Info      : raid0 | State: clean
Array Size     : 3902566400 (3.63 TiB 4.00 TB)
Devices        : Total: 2 | Active: 2 | Working: 2

▸  /dev/md2
RAID Info      : raid1 | State: clean
Array Size     : 1046528 (1022.00 MiB 1071.64 MB)
Devices        : Total: 2 | Active: 2 | Working: 2

Operating System:
---------------------------------
Distribution   : Debian GNU/Linux 13 (trixie)
Kernel         : 6.12.48+deb13-amd64
```

### Extended Mode Output

When using `-e` flag, additional information is displayed:
- Individual RAM module details (slot, size, type, speed, manufacturer, part number, serial)
- Motherboard information (manufacturer, model, version, serial number)
- Network interfaces with status and MAC addresses
- Disk serial numbers and firmware versions
- Power cycle counts for disks
- Total data written (TBW) for SSDs
- System load average

### Test Mode Output

When using `-t` flag, performance benchmarks are run:
- RAM write speed test (1GB test)
- Disk I/O speed test for each disk (256MB test)
- Color-coded results (green/yellow/red based on performance)

## Troubleshooting

### "Permission denied" Errors

**Problem:** Script shows "Permission denied" or "Requires sudo" messages.

**Solution:** Run the script with `sudo`:
```bash
sudo ./yahi.sh
```

### Missing S.M.A.R.T. Data

**Problem:** Disk health information is not shown.

**Solutions:**
1. Install `smartmontools`: `sudo apt install smartmontools` (Debian/Ubuntu) or `sudo dnf install smartmontools` (RHEL/Fedora)
2. Run with `sudo`: `sudo ./yahi.sh`
3. For NVMe drives, install `nvme-cli`: `sudo apt install nvme-cli`

### No RAID Information

**Problem:** RAID arrays are not detected.

**Solutions:**
1. Install `mdadm`: `sudo apt install mdadm` or `sudo dnf install mdadm`
2. Run with `sudo` for detailed RAID information
3. The script only detects Linux software RAID (mdadm), not hardware RAID controllers

### Limited RAM Information

**Problem:** Only basic RAM size is shown, no details about modules.

**Solutions:**
1. Install `dmidecode`: `sudo apt install dmidecode` or `sudo dnf install dmidecode`
2. Run with `sudo`: `sudo ./yahi.sh -e` for extended RAM details

### Performance Tests Fail

**Problem:** I/O benchmarks don't run or show errors.

**Solutions:**
1. Ensure you have write permissions on the disk mount points
2. Check available disk space (at least 300MB free required)
3. Some disks may not have writable mount points (e.g., unmounted disks)

## Exit Codes

- `0` - Success, no critical issues detected
- `2` - Critical hardware issues detected (e.g., disk failures, high temperatures, RAID degradation)

## Features

- **System Information**: Hostname, uptime, CPU details, architecture
- **Memory Details**: Total RAM, type (DDR3/DDR4/DDR5), speed, ECC support, individual RAM modules (extended mode)
- **Storage Devices**: List of all disks with size and type (HDD/SSD/NVMe)
- **Disk Health Monitoring**: 
  - S.M.A.R.T. data for SATA/SAS drives
  - NVMe health status via `nvme-cli`
  - Temperature monitoring with critical alerts
  - Wear level tracking for SSDs
  - Sector error tracking for HDDs
  - Power-on hours and power cycles
- **RAID Status**: Linux software RAID (mdadm) array information and health
- **GPU Information**: VGA/3D controller detection
- **Network Interfaces**: Interface status and MAC addresses (extended mode)
- **Performance Tests**: I/O benchmarks for RAM and disks (test mode)
- **Critical Alerts**: Automatic detection and highlighting of hardware issues
- **Color-coded Output**: Terminal-friendly output with status indicators

## Requirements

### Required Tools
- `bash` (most Linux distributions include this)
- `sudo` access (for full functionality)

### Optional Dependencies
The script will work without these, but some features will be limited:

- **smartmontools** - For S.M.A.R.T. disk health data
- **dmidecode** - For detailed RAM, motherboard, and hardware information
- **mdadm** - For RAID array status
- **nvme-cli** - For NVMe drive health (recommended for NVMe systems)
- **lsblk**, **lscpu**, **lspci** - Usually pre-installed on most Linux systems

### Installation of Dependencies

**Debian/Ubuntu:**
```bash
sudo apt update
sudo apt install smartmontools dmidecode mdadm nvme-cli
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install smartmontools dmidecode mdadm nvme-cli
# or for older systems:
sudo yum install smartmontools dmidecode mdadm nvme-cli
```

**Arch Linux:**
```bash
sudo pacman -S smartmontools dmidecode mdadm nvme-cli
```

## Security Note

This script requires `sudo` access to read hardware information. Review the script before running if you download it from the internet. The script only reads information and does not modify system configuration.

## Acknowledgements

**Note:** This script was written by LLMs (Claude and other models) and is inspired by [YABS (Yet Another Bench Script)](https://github.com/masonr/yet-another-bench-script).

- **Contact me on LowEndTalk:** https://lowendtalk.com/profile/loay
- **Follow Telegram Channel:** https://t.me/lowendweb

## License

This script is provided as-is for informational purposes. Use at your own risk.
