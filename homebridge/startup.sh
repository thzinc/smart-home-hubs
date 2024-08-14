#!/bin/bash
set -euo pipefail

CONFIG_JSON=/homebridge/config.json
if [ ! -f "$CONFIG_JSON" ]; then
    cp /defaults/config.json "$CONFIG_JSON"

    HOMEBRIDGE_BRIDGE_NAME=${HOMEBRIDGE_BRIDGE_NAME:-$BALENA_DEVICE_NAME_AT_INIT}

    UNIQUE_BRIDGE_USERNAME=$(shuf -i 0-255 -n 6 | xargs -- printf "%02x:" | tr 'a-f' 'A-F')
    HOMEBRIDGE_BRIDGE_USERNAME=${UNIQUE_BRIDGE_USERNAME:0:17}

    UNIQUE_BRIDGE_PIN_A="000$(shuf -i 0-999 -n1)"
    UNIQUE_BRIDGE_PIN_B="00$(shuf -i 0-99 -n1)"
    UNIQUE_BRIDGE_PIN_C="000$(shuf -i 0-999 -n1)"
    HOMEBRIDGE_BRIDGE_PIN=${HOMEBRIDGE_BRIDGE_PIN:-"${UNIQUE_BRIDGE_PIN_A: -3}-${UNIQUE_BRIDGE_PIN_B: -2}-${UNIQUE_BRIDGE_PIN_C: -3}"}
fi

CONFIG=$(<"$CONFIG_JSON")

HOMEBRIDGE_BRIDGE_NAME=${HOMEBRIDGE_BRIDGE_NAME:-$(jq -r '.bridge.name' <<<"$CONFIG")}
HOMEBRIDGE_BRIDGE_USERNAME=${HOMEBRIDGE_BRIDGE_USERNAME:-$(jq -r '.bridge.username' <<<"$CONFIG")}
HOMEBRIDGE_BRIDGE_PORT=${HOMEBRIDGE_BRIDGE_PORT:-$(jq -r '.bridge.port' <<<"$CONFIG")}
HOMEBRIDGE_BRIDGE_PIN=${HOMEBRIDGE_BRIDGE_PIN:-$(jq -r '.bridge.pin' <<<"$CONFIG")}
HOMEBRIDGE_PLATFORMS_CONFIG_PORT=${HOMEBRIDGE_PLATFORMS_CONFIG_PORT:-$(jq -r '(.platforms[] | select(.platform  == "config") .port)' <<<"$CONFIG")}

jq \
    --arg HOMEBRIDGE_BRIDGE_NAME "$HOMEBRIDGE_BRIDGE_NAME" \
    --arg HOMEBRIDGE_BRIDGE_USERNAME "$HOMEBRIDGE_BRIDGE_USERNAME" \
    --arg HOMEBRIDGE_BRIDGE_PORT "$HOMEBRIDGE_BRIDGE_PORT" \
    --arg HOMEBRIDGE_BRIDGE_PIN "$HOMEBRIDGE_BRIDGE_PIN" \
    --arg HOMEBRIDGE_PLATFORMS_CONFIG_PORT "$HOMEBRIDGE_PLATFORMS_CONFIG_PORT" \
    '
        .bridge.name = $HOMEBRIDGE_BRIDGE_NAME |
        .bridge.username = $HOMEBRIDGE_BRIDGE_USERNAME |
        .bridge.port = ($HOMEBRIDGE_BRIDGE_PORT | tonumber) |
        .bridge.pin = $HOMEBRIDGE_BRIDGE_PIN |
        (.platforms[] | select(.platform  == "config") .port) |= ($HOMEBRIDGE_PLATFORMS_CONFIG_PORT | tonumber)
    ' <<<"$CONFIG" >"$CONFIG_JSON"
