# Dell-IDRAC-FanControl
 
Docker image that will adjust fan speed based on the exhaust temperature. This project has been refactored to be more resource-efficient and responsive.

## Features

- **Adaptive Fan Control**: Adjusts fan speed based on server exhaust temperature using a non-linear curve
- **Resource Efficient**: Optimized script with minimal resource usage
- **Responsive**: Quick response to temperature changes with configurable parameters
- **Hysteresis**: Prevents fan speed oscillation by requiring significant temperature changes before adjusting speed
- **Error Handling**: Robust error handling with automatic recovery
- **Logging**: Detailed logging with configurable levels

## Usage

### Docker Compose

```yml
version: '3'
services:
  dell-idrac-fancontrol:
    image: pdiddy973/dell-idrac-fancontrol:latest
    container_name: dell-idrac-fancontrol
    restart: unless-stopped
    environment:
      - IDRAC_HOST=192.168.1.120  # Your iDRAC IP address
      - IDRAC_USER=root           # Your iDRAC username
      - IDRAC_PW=password         # Your iDRAC password
      - CHECK_INTERVAL=30         # How often to check temperature (seconds)
      - TEMP_THRESHOLD_LOW=40     # Temperature below which fans run at minimum speed (°C)
      - TEMP_THRESHOLD_HIGH=80    # Temperature above which fans run at maximum speed (°C)
      - MIN_FAN_SPEED=10          # Minimum fan speed percentage
      - MAX_FAN_SPEED=100         # Maximum fan speed percentage
      - HYSTERESIS=2              # Temperature change required to adjust fan speed (°C)
      - LOG_LEVEL=info            # Logging level (debug, info, warning, error)
```

## Environment Variables

| Environment Variable | Description | Default |
| :----: | --- | :----: |
| `IDRAC_HOST` | iDRAC IP Address | *Required* |
| `IDRAC_USER` | iDRAC Username | *Required* |
| `IDRAC_PW` | iDRAC Password | *Required* |
| `CHECK_INTERVAL` | How often to check temperature (seconds) | 30 |
| `TEMP_THRESHOLD_LOW` | Temperature below which fans run at minimum speed (°C) | 40 |
| `TEMP_THRESHOLD_HIGH` | Temperature above which fans run at maximum speed (°C) | 80 |
| `MIN_FAN_SPEED` | Minimum fan speed percentage | 10 |
| `MAX_FAN_SPEED` | Maximum fan speed percentage | 100 |
| `HYSTERESIS` | Temperature change required to adjust fan speed (°C) | 2 |
| `LOG_LEVEL` | Logging level (debug, info, warning, error) | info |

## Fan Speed Curve

The fan speed is calculated using a quadratic curve between the low and high temperature thresholds:

- Below `TEMP_THRESHOLD_LOW`: Fan speed is fixed at `MIN_FAN_SPEED`
- Above `TEMP_THRESHOLD_HIGH`: Fan speed is fixed at `MAX_FAN_SPEED`
- Between thresholds: Fan speed follows a quadratic curve that increases more steeply at higher temperatures

The hysteresis value prevents the fan speed from changing unless the temperature has changed significantly, reducing unnecessary adjustments and system load.
