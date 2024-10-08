#!/bin/bash

# Switch to workdir
cd "${STEAMAPPDIR}"

xvfbpid=""
ckpid=""

function kill_corekeeperserver {
        if [[ ! -z "$ckpid" ]]; then
                kill $ckpid
                wait $ckpid
        fi
        if [[ ! -z "$xvfbpid" ]]; then
                kill $xvfbpid
        fi
}

trap kill_corekeeperserver EXIT

if ! (dpkg -l xvfb >/dev/null) ; then
    echo "Installing xvfb dependency..."
    sleep 1
    sudo apt-get update -yy && sudo apt-get install xvfb -yy
fi

set -m

rm -f /tmp/.X99-lock

Xvfb :99 -screen 0 1x1x24 -nolisten tcp &
export DISPLAY=:99
xvfbpid=$!

# Wait for xvfb ready.
retry_count=0
max_retries=2
xvfb_test=0
until [ $retry_count -gt $max_retries ]; do
    xvinfo
    xvfb_test=$?
    if [ $xvfb_test != 255 ]; then
        retry_count=$(($max_retries + 1))
    else
        retry_count=$(($retry_count + 1))
        echo "Failed to start Xvfb, retry: $retry_count"
        sleep 2
    fi 
done
if [ $xvfb_test == 255 ]; then exit 255; fi

rm -f GameID.txt

chmod +x ./CoreKeeperServer

#Build Parameters
declare -a params
params=(-batchmode -logfile "CoreKeeperServerLog.txt")
if [ ! -z "${WORLD_INDEX}" ]; then params=( "${params[@]}" -world "${WORLD_INDEX}" ); fi
if [ ! -z "${WORLD_NAME}" ]; then params=( "${params[@]}" -worldname "${WORLD_NAME}" ); fi
if [ ! -z "${WORLD_SEED}" ]; then params=( "${params[@]}" -worldseed "${WORLD_SEED}" ); fi
if [ ! -z "${WORLD_MODE}" ]; then params=( "${params[@]}" -worldmode "${WORLD_MODE}" ); fi
if [ ! -z "${GAME_ID}" ]; then params=( "${params[@]}" -gameid "${GAME_ID}" ); fi
if [ ! -z "${DATA_PATH}" ]; then params=( "${params[@]}" -datapath "${DATA_PATH}" ); fi
if [ ! -z "${MAX_PLAYERS}" ]; then params=( "${params[@]}" -maxplayers "${MAX_PLAYERS}" ); fi
if [ ! -z "${SEASON}" ]; then params=( "${params[@]}" -season "${SEASON}" ); fi
if [ ! -z "${SERVER_IP}" ]; then params=( "${params[@]}" -ip "${SERVER_IP}" ); fi
if [ ! -z "${SERVER_PORT}" ]; then params=( "${params[@]}" -port "${SERVER_PORT}" ); fi

echo "${params[@]}"

DISPLAY=:99 LD_LIBRARY_PATH="$LD_LIBRARY_PATH:../Steamworks SDK Redist/linux64/" ./CoreKeeperServer "${params[@]}"&

ckpid=$!

echo "Started server process with pid $ckpid"

while [ ! -f GameID.txt ]; do
        sleep 0.1
done

gameid=$(cat GameID.txt)
echo "Game ID: ${gameid}"

if [ -z "$DISCORD" ]; then
	DISCORD=0
fi

if [ $DISCORD -eq 1 ]; then 
  echo "Discord eq 1" 
  if [ -z "$DISCORD_HOOK" ]; then 
    echo "Please set DISCORD_WEBHOOK url." 
  else 
    echo "Discord gameid"
    format="${DISCORD_PRINTF_STR:-%s}"
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "{\"content\": \"$(printf "${format}" "${gameid}")\"}" "${DISCORD_HOOK}" 
    
    # Monitor server logs for player join/leave
    tail -f CoreKeeperServerLog.txt | while read LOGLINE
	
    do
        # Add timestamp to each log line
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $LOGLINE"

        # Detect player join based on log: [userid:12345] is using new name PlayerName
        if echo "$LOGLINE" | grep -q "is using new name"; then
            PLAYER_NAME=$(echo "$LOGLINE" | grep -oP "is using new name \K\w+")
            echo "Player Name: $PLAYER_NAME"  # Debugging: ensure player name is correct
            if [ -n "$PLAYER_NAME" ]; then
                WELCOME_MSG=$(echo "${DISCORD_MESSAGE_WELCOME:-'Welcome, \$\$user!'}" | sed "s/\$\$user/$PLAYER_NAME/g")
                echo "Generated Welcome Message: $WELCOME_MSG"  # Debugging: ensure message is correct
                
                # Check if WELCOME_MSG is empty before sending
                if [ -z "$WELCOME_MSG" ]; then
                    echo "Error: Welcome message is empty"
                else
                    curl -i -H "Accept: application/json" -H "Content-Type: application/json" -X POST --data "{\"content\": \"$(printf "${format}" "${WELCOME_MSG}")\"}" "${DISCORD_HOOK}"
                fi
            fi
        fi

        # Detect potential player leave
        if echo "$LOGLINE" | grep -q "Accepted connection from .* with result OK awaiting authentication"; then
            PLAYER_NAME=$(echo "$LOGLINE" | grep -oP "Connected to userid:.*")
            if [ -n "$PLAYER_NAME" ]; then
                BYE_MSG=$(echo "${DISCORD_MESSAGE_BYE:-'Goodbye, $$user!'}" | sed "s/\$\$user/$PLAYER_NAME/g")
                echo "Generated Bye Message: $BYE_MSG"  # Debugging: ensure message is correct
                
                # Check if BYE_MSG is empty before sending
                if [ -z "$BYE_MSG" ]; then
                    echo "Error: Bye message is empty"
                else
                    curl -i -H "Accept: application/json" -H "Content-Type: application/json" -X POST --data "{\"content\": \"$(printf "${format}" "${BYE_MSG}")\"}" "${DISCORD_HOOK}"
                fi
            fi
        fi
    done
  fi
fi

wait $ckpid
ckpid=""
