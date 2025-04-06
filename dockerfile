FROM alpine:3.19

# Install required packages and clean up in a single layer to reduce image size
RUN apk --no-cache add \
    ipmitool \
    bc \
    && rm -rf /var/cache/apk/*

# Copy the script
COPY adaptivefancontrol.sh /opt/adaptivefancontrol.sh

# Set proper permissions
RUN chmod 0755 /opt/adaptivefancontrol.sh

# Set environment variables with defaults
ENV CHECK_INTERVAL=30 \
    TEMP_THRESHOLD_LOW=40 \
    TEMP_THRESHOLD_HIGH=80 \
    MIN_FAN_SPEED=10 \
    MAX_FAN_SPEED=100 \
    HYSTERESIS=2 \
    LOG_LEVEL=info

# Run the script
CMD ["/opt/adaptivefancontrol.sh"]
