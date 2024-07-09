#!/bin/bash
#Usage ./netperf.sh 2>&1 | tee netperf.out

set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN="\033[0;36m"
ERROR='\033[41m'
NC='\033[0m'
export IFS=";"

# Read .env file
if [ -f .env ]; then
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] || [[ -z "$key" ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    export "$key=$value"
  done < .env
fi

############################## Checking Mandatory ##############################
if [ -z "$NAME" ]
then
        printf "${ERROR} 'NAME' EnvVar not set.${NC}\n"
        exit 1
fi
if [ -z "$SERVER" ]
then
        printf "${ERROR} 'SERVER' EnvVar not set.${NC}\n"
        exit 1
fi
if [ -z "$ADAPTER" ]
then
        printf "${ERROR} 'ADAPTER' EnvVar not set.${NC}\n"
        exit 1
fi

# If all iperf config is empty run only the defaults
if [ -z "$IPERF_DURATION" ] && [ -z "$IPERF_PROTOCOL" ] && [ -z "$IPERF_DIRECTION" ] && [ -z "$IPERF_STREAMS" ] && [ -z "$IPERF_BUFFER_LENGTH" ] && [ -z "$IPERF_WINDOW_SIZE" ] && [ -z "$IPERF_MTU" ] && [ -z "$IPERF_LATENCY" ] && [ -z "$IPERF_PACKET_LOSS" ];
then
        RUN_DEFAULT_IPERF=1
fi

# If all ping config is empty run only the defaults
if [ -z "$PING_PACKET_SIZE" ] && [ -z "$PING_LATENCY" ];
then
        RUN_DEFAULT_PING=1
fi
############################ End Checking Mandatory ############################

#################################### Setup #####################################
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'catch' EXIT
catch() {
if [ $? -ne 0 ]; then
        printf "${ERROR}${last_command} command failed with exit code $?.${NC}\n"
fi
}

printf "\n${GREEN}Measuring network performance for setup: ${NAME}.${NC}\n"
RUN_STAMP=$(date +%Y-%m-%d-%H-%M-%S)
printf "\n${CYAN}Storing results at: ${OUTPUT_DIR}/${RUN_STAMP}/ direcotry.${NC}\n"
mkdir -p $OUTPUT_DIR/${RUN_STAMP}

ORIGIN_MTU=$(ifconfig "${ADAPTER}" | grep -i mtu | awk '{print $4}')
echo "Original MTU was: ${ORIGIN_MTU}"
ip link set dev ${ADAPTER} mtu 1500
tc qdisc del dev ${ADAPTER} root || true
sleep 3

printf "\n${CYAN}Installing required packages.${NC}\n"
DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
apt-get install -y net-tools
apt-get install -y iputils-ping
apt-get install -y iproute2
################################## End Setup ###################################

############################ Bandwidth Measurements ############################
printf "\n${CYAN}Measuring bandwidth network performance.${NC}\n"

echo ${NAME} > ${OUTPUT_DIR}/info.txt
base_iperf_cmd="iperf3 -c ${SERVER} -p ${IPERF_PORT} -O 5 -J --get-server-output"
echo Base command: ${base_iperf_cmd} >> ${OUTPUT_DIR}/info.txt

### Basic run
if [ "$RUN_DEFAULT_IPERF" == "1" ]; then
        RESULTS_FILENAME="iperf_basic"
        echo "${base_iperf_cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
        eval "${base_iperf_cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
else
        ### Test Duration
        for duration in $IPERF_DURATION;
        do
                sleep 3
                RESULTS_FILENAME="iperf_duration_${duration}"
                cmd="${base_iperf_cmd} -t ${duration}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test Protocol
        for protocol in $IPERF_PROTOCOL;
        do
                sleep 3
                if [ "$protocol" == "TCP" ]; then
                        RESULTS_FILENAME="iperf_protocol_${protocol}"
                        cmd="${base_iperf_cmd}"
                        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                fi
                if [ "$protocol" == "UDP" ]; then
                        RESULTS_FILENAME="iperf_protocol_${protocol}"
                        cmd="${base_iperf_cmd} -u -b 0"
                        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                fi
        done

        ### Test Direction
        for direction in $IPERF_DIRECTION;
        do
                sleep 3
                if [ "$direction" == "NORMAL" ]; then
                        RESULTS_FILENAME="iperf_direction_${direction}"
                        cmd="${base_iperf_cmd}"
                        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                fi
                if [ "$direction" == "REVERSE" ]; then
                        RESULTS_FILENAME="iperf_direction_${direction}"
                        cmd="${base_iperf_cmd} -R"
                        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                fi
                if [ "$direction" == "BIDIRECTIONAL" ]; then
                        RESULTS_FILENAME="iperf_direction_${direction}"
                        cmd="${base_iperf_cmd} --bidir"
                        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                fi
        done

        ### Test Streams
        for streams in $IPERF_STREAMS;
        do
                sleep 3
                RESULTS_FILENAME="iperf_streams_${streams}"
                cmd="${base_iperf_cmd} -P ${streams}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test Buffer Length
        for buffer_length in $IPERF_BUFFER_LENGTH;
        do
                sleep 3
                RESULTS_FILENAME="iperf_buffer_length_${buffer_length}"
                cmd="${base_iperf_cmd} -l ${buffer_length}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test Window Size
        for window_size in $IPERF_WINDOW_SIZE;
        do
                sleep 3
                RESULTS_FILENAME="iperf_window_size_${window_size}"
                cmd="${base_iperf_cmd} -w ${window_size}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done


        ### Test MTU
        for mtu in $IPERF_MTU;
        do
                sleep 3
                RESULTS_FILENAME="iperf_mtu_${mtu}"
                echo "ip link set dev ${ADAPTER} mtu ${mtu}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                ip link set dev ${ADAPTER} mtu ${mtu}
                sleep 3
                cmd="${base_iperf_cmd}"
                echo "${cmd}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test with Latency
        for latency in $IPERF_LATENCY;
        do
                sleep 3
                RESULTS_FILENAME="iperf_latency_${latency}"
                echo "tc qdisc add dev ${ADAPTER} root netem delay ${latency}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc add dev ${ADAPTER} root netem delay ${latency}
                sleep 3
                cmd="${base_iperf_cmd}"
                echo "${cmd}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                echo "tc qdisc del dev ${ADAPTER} root netem delay ${latency}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc del dev ${ADAPTER} root netem delay ${latency}
                sleep 3
        done

        ### Test with Packet Loss
        for packet_loss in $IPERF_PACKET_LOSS;
        do
                sleep 3
                RESULTS_FILENAME="iperf_packet_loss_${packet_loss}"
                echo "tc qdisc add dev ${ADAPTER} root netem loss ${packet_loss}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc add dev ${ADAPTER} root netem loss ${packet_loss}
                sleep 3
                cmd="${base_iperf_cmd}"
                echo "${cmd}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                echo "tc qdisc del dev ${ADAPTER} root netem loss ${packet_loss}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc del dev ${ADAPTER} root netem loss ${packet_loss}
                sleep 3
        done


fi

########################## End Bandwidth Measurements ##########################


############################# Latency Measurements #############################
printf "\n${CYAN}Measuring latency network performance.${NC}\n"

base_ping_cmd="ping ${SERVER} -I ${ADAPTER}"
ip link set dev ${ADAPTER} mtu 1500
tc qdisc del dev ${ADAPTER} root || true
sleep 3

if [ "$RUN_DEFAULT_PING" == "1" ]; then
        RESULTS_FILENAME="ping_basic"
        echo "${base_ping_cmd} -c 10" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
        eval "${base_ping_cmd} -c 10" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
else
        ### Test Interval
        for interval in $PING_INTERVAL;
        do
                sleep 3
                RESULTS_FILENAME="ping_interval_${interval}"
                cmd="${base_ping_cmd} -c 10 -i ${interval}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test packet size
        for packet_size in $PING_PACKET_SIZE;
        do
                sleep 3
                RESULTS_FILENAME="ping_packet_size_${packet_size}"
                cmd="${base_ping_cmd} -c 10 -s ${packet_size}"
                echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
        done

        ### Test flood ping
        sleep 3
        RESULTS_FILENAME="ping_flood"
        cmd="${base_ping_cmd} -c 100 -i 0.002 -f"
        echo "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
        eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"


        ### Test with Latency
        for latency in $PING_LATENCY;
        do
                sleep 3
                RESULTS_FILENAME="ping_latency_${latency}"
                echo "tc qdisc add dev ${ADAPTER} root netem delay ${latency}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc add dev ${ADAPTER} root netem delay ${latency}
                sleep 3
                cmd="${base_ping_cmd} -c 10"
                echo "${cmd}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                eval "${cmd}" > "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.json"
                echo "tc qdisc del dev ${ADAPTER} root netem delay ${latency}" >> "${OUTPUT_DIR}/${RUN_STAMP}/${RESULTS_FILENAME}.cmd"
                tc qdisc del dev ${ADAPTER} root netem delay ${latency}
                sleep 3
        done
fi
  

########################### End Latency Measurements ###########################
#Revert original MTU
ip link set dev ${ADAPTER} mtu ${ORIGIN_MTU}

printf "\n${GREEN}Results stored at: ${OUTPUT_DIR}/${RUN_STAMP}/.${NC}\n"
printf "\n${GREEN}All finished.${NC}\n"
