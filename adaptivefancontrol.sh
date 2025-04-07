#!/bin/sh
set -e

# Default values if not provided
: "${CHECK_INTERVAL:=30}"
: "${TEMP_THRESHOLD_LOW:=40}"
: "${TEMP_THRESHOLD_HIGH:=80}"
: "${MIN_FAN_SPEED:=10}"
: "${MAX_FAN_SPEED:=100}"
: "${HYSTERESIS:=2}"
: "${LOG_LEVEL:=info}"

# IPMI command with credentials (built once to avoid repetition)
IPMI_CMD="ipmitool -I lanplus -H ${IDRAC_HOST} -U ${IDRAC_USER} -P ${IDRAC_PW}"

# Logging function with timestamps and log levels
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Only log if the current level is sufficient
    case "$LOG_LEVEL" in
        debug)
            echo "[$timestamp] [$level] $message"
            ;;
        info)
            if [ "$level" != "debug" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
        warning)
            if [ "$level" != "debug" ] && [ "$level" != "info" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
        error)
            if [ "$level" = "error" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
    esac
}

# Function to get the maximum temperature from all sensors
get_temp() {
    local temp
    local max_temp=0
    
    # Use a more efficient command to get temperatures
    # The -c flag makes the output more compact and easier to parse
    temp=$(${IPMI_CMD} sdr type temperature -c 2>/dev/null || echo "ERROR")
    
    if [ "$temp" = "ERROR" ]; then
        log "error" "Failed to get temperature data from iDRAC"
        return 1
    fi
    
    # Parse the compact output to find the maximum temperature
    max_temp=$(echo "$temp" | awk -F"|" '{split($5,a," "); if(a[1]>max) max=a[1]} END{print max}')
    
    if [ -z "$max_temp" ] || [ "$max_temp" = "0" ]; then
        log "error" "Failed to parse temperature data"
        return 1
    fi
    
    echo "$max_temp"
    return 0
}

# Function to set fan speed with error handling
set_fan_speed() {
    local speed="$1"
    local hex_speed
    
    # Convert decimal to hex
    hex_speed=$(printf "0x%02x" "$speed")
    
    log "debug" "Setting fan speed to ${speed}% (${hex_speed})"
    
    # Set the fan speed and capture any errors
    if ! ${IPMI_CMD} raw 0x30 0x30 0x02 0xff "$hex_speed" >/dev/null 2>&1; then
        log "error" "Failed to set fan speed to ${speed}%"
        return 1
    fi
    
    return 0
}

# Function to calculate fan speed based on temperature
calculate_fan_speed() {
    local temp="$1"
    local current_speed="$2"
    local new_speed
    
    # Apply hysteresis to prevent oscillation
    # Only change speed if temperature has changed significantly
    if [ -n "$current_speed" ] && [ "$current_speed" -gt 0 ]; then
        local temp_for_current=$(get_temp_for_speed "$current_speed")
        if [ $(echo "$temp <= $temp_for_current + $HYSTERESIS && $temp >= $temp_for_current - $HYSTERESIS" | bc -l) -eq 1 ]; then
            log "debug" "Temperature ($temp°C) within hysteresis range of current speed ($current_speed%), maintaining"
            echo "$current_speed"
            return 0
        fi
    fi
    
    # Calculate new fan speed based on temperature thresholds
    if [ $(echo "$temp < $TEMP_THRESHOLD_LOW" | bc -l) -eq 1 ]; then
        # Below low threshold, use minimum speed
        new_speed=$MIN_FAN_SPEED
    elif [ $(echo "$temp >= $TEMP_THRESHOLD_HIGH" | bc -l) -eq 1 ]; then
        # Above high threshold, use maximum speed
        new_speed=$MAX_FAN_SPEED
    else
        # Between thresholds, use a non-linear curve
        # This curve increases more steeply at higher temperatures
        local temp_range=$(echo "$temp - $TEMP_THRESHOLD_LOW" | bc -l)
        local temp_percent=$(echo "scale=4; $temp_range / ($TEMP_THRESHOLD_HIGH - $TEMP_THRESHOLD_LOW)" | bc -l)
        
        # Apply a quadratic curve: MIN_SPEED + (MAX_SPEED - MIN_SPEED) * (temp_percent^2)
        local speed_range=$(echo "$MAX_FAN_SPEED - $MIN_FAN_SPEED" | bc -l)
        local speed_float=$(echo "scale=4; $MIN_FAN_SPEED + $speed_range * ($temp_percent * $temp_percent)" | bc -l)
        new_speed=$(echo "$speed_float / 1" | bc)
    fi
    
    echo "$new_speed"
    return 0
}

# Function to get the temperature that would result in a given fan speed
# This is used for hysteresis calculations
get_temp_for_speed() {
    local speed="$1"
    local temp
    
    if [ "$speed" -le "$MIN_FAN_SPEED" ]; then
        temp=$TEMP_THRESHOLD_LOW
    elif [ "$speed" -ge "$MAX_FAN_SPEED" ]; then
        temp=$TEMP_THRESHOLD_HIGH
    else
        # Reverse the quadratic formula to get temperature from speed
        local speed_percent=$(echo "scale=4; ($speed - $MIN_FAN_SPEED) / ($MAX_FAN_SPEED - $MIN_FAN_SPEED)" | bc -l)
        local temp_percent=$(echo "scale=4; sqrt($speed_percent)" | bc -l)
        temp=$(echo "scale=1; $TEMP_THRESHOLD_LOW + ($TEMP_THRESHOLD_HIGH - $TEMP_THRESHOLD_LOW) * $temp_percent" | bc -l)
    fi
    
    echo "$temp"
    return 0
}

# Main function
main() {
    log "info" "Starting Dell iDRAC Fan Control"
    log "info" "Check interval: ${CHECK_INTERVAL}s"
    log "info" "Temperature thresholds: ${TEMP_THRESHOLD_LOW}°C - ${TEMP_THRESHOLD_HIGH}°C"
    log "info" "Fan speed range: ${MIN_FAN_SPEED}% - ${MAX_FAN_SPEED}%"
    
    local current_speed=0
    local last_temp=0
    local consecutive_errors=0
    
    while true; do
        # Get current temperature
        local temp
        if ! temp=$(get_temp); then
            consecutive_errors=$((consecutive_errors + 1))
            log "warning" "Failed to get temperature (attempt $consecutive_errors)"
            
            # If we've had too many consecutive errors, try to recover
            if [ "$consecutive_errors" -ge 3 ]; then
                log "error" "Too many consecutive errors, setting fans to maximum for safety"
                set_fan_speed $MAX_FAN_SPEED
                sleep 60  # Wait longer before retrying
                consecutive_errors=0
            else
                sleep "$CHECK_INTERVAL"
            fi
            continue
        fi
        
        # Reset error counter on success
        consecutive_errors=0
        
        # Only recalculate if temperature has changed
        if [ "$temp" != "$last_temp" ]; then
            # Calculate new fan speed
            local new_speed
            new_speed=$(calculate_fan_speed "$temp" "$current_speed")
            
            # Only update if speed has changed
            if [ "$new_speed" != "$current_speed" ]; then
                log "info" "Exhaust Temperature is ${temp}°C: Changing fan speed from ${current_speed}% to ${new_speed}%"
                
                if set_fan_speed "$new_speed"; then
                    current_speed="$new_speed"
                fi
            else
                log "debug" "Exhaust Temperature is ${temp}°C: Maintaining fan speed at ${current_speed}%"
            fi
            
            last_temp="$temp"
        else
            log "debug" "Temperature unchanged at ${temp}°C, fan speed at ${current_speed}%"
        fi
        
        # Sleep for the specified interval
        sleep "$CHECK_INTERVAL"
    done
}

# Check if required environment variables are set
if [ -z "$IDRAC_HOST" ] || [ -z "$IDRAC_USER" ] || [ -z "$IDRAC_PW" ]; then
    log "error" "Required environment variables not set (IDRAC_HOST, IDRAC_USER, IDRAC_PW)"
    exit 1
fi

# Start the main function
main
