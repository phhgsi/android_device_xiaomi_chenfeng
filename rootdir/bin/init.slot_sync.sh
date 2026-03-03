#!/vendor/bin/sh
# Slot synchronization script
# Ensures the active boot slot matches the current running slot
# This fixes the issue where flashing slot A but device boots to slot B

LOG_TAG="init.slot_sync"
LOG_FILE="/data/local/tmp/slot_sync.log"

# Create log directory if needed
mkdir -p $(dirname $LOG_FILE)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG: $1" >> $LOG_FILE
    log -t "$LOG_TAG" -p i "$1"
}

log "Starting slot synchronization..."

# Get current boot slot from kernel cmdline
BOOT_SLOT_SUFFIX=$(cat /proc/cmdline | tr ' ' '\n' | grep "^androidboot.slot_suffix=" | cut -d '=' -f 2)
BOOT_SLOT=$(cat /proc/cmdline | tr ' ' '\n' | grep "^androidboot.slot=" | cut -d '=' -f 2)

# Fallback to ro.boot properties if cmdline didn't have it
if [ -z "$BOOT_SLOT_SUFFIX" ]; then
    BOOT_SLOT_SUFFIX=$(getprop ro.boot.slot_suffix 2>/dev/null)
fi
if [ -z "$BOOT_SLOT" ]; then
    BOOT_SLOT=$(getprop ro.boot.slot 2>/dev/null)
fi

# Convert suffix to slot letter
if [ -n "$BOOT_SLOT_SUFFIX" ]; then
    case "$BOOT_SLOT_SUFFIX" in
        "_a") BOOT_SLOT="a" ;;
        "_b") BOOT_SLOT="b" ;;
    esac
fi

# Default to slot a if still unknown
if [ -z "$BOOT_SLOT" ]; then
    BOOT_SLOT="a"
    BOOT_SLOT_SUFFIX="_a"
fi

log "Current boot slot: $BOOT_SLOT (suffix: $BOOT_SLOT_SUFFIX)"

# Check if bootctl is available  
if [ ! -x /system/bin/bootctl ] && [ ! -x /vendor/bin/bootctl ]; then
    log "bootctl not found, skipping slot sync"
    exit 0
fi

# Determine bootctl path
BOOTCTL="/system/bin/bootctl"
[ -x /vendor/bin/bootctl ] && BOOTCTL="/vendor/bin/bootctl"

# Get the currently marked active slot
ACTIVE_SLOT_NUM=$($BOOTCTL get-active-slot 2>/dev/null)
log "Bootctl reports active slot number: $ACTIVE_SLOT_NUM"

case "$ACTIVE_SLOT_NUM" in
    0) ACTIVE_SLOT="a" ;;
    1) ACTIVE_SLOT="b" ;;
    *) ACTIVE_SLOT="unknown" ;;
esac

log "Active slot from bootloader: $ACTIVE_SLOT, Booted slot: $BOOT_SLOT"

# If mismatch, set the correct active slot
if [ "$ACTIVE_SLOT" != "$BOOT_SLOT" ]; then
    log "Slot mismatch detected! Setting active slot to: $BOOT_SLOT"
    $BOOTCTL set-active-slot "$BOOT_SLOT" 2>/dev/null
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        log "Successfully set active slot to: $BOOT_SLOT"
    else
        log "Failed to set active slot, error code: $RESULT"
    fi
else
    log "Slots are synchronized, no action needed"
fi

# Also mark current slot as successful to prevent rollback
log "Marking current slot as successful..."
$BOOTCTL mark-boot-successful 2>/dev/null

log "Slot synchronization complete"
exit 0
