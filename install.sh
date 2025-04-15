set -euo pipefail

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

KEY_PATH=~/.ssh/id_rsa
INPUT=$1 

IFS=',' read -ra SERVERS <<< "$INPUT"

echo -e "${YELLOW}CHECKING | Checking the load on the servers...${NC}"
LOW_LOAD=2
TARGET_SERVER=""

for SERVER in "${SERVERS[@]}"; do
    IFS=':' read -r HOST PORT <<< "$SERVER"
    PORT=${PORT:-22} 
    echo -e "${YELLOW}CHECKING | Checking $HOST:$PORT...${NC}"

    if ! ssh -o ConnectTimeout=5 -p "$PORT" -i "$KEY_PATH" root@"$HOST" "exit" &>/dev/null; then
        echo -e "${RED}ERROR    | Cannot connect to $HOST:$PORT via SSH.${NC}"
        continue
    fi

    LOAD=$(ssh -p "$PORT" -i "$KEY_PATH" root@"$HOST" "uptime" | awk -F'load average: ' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    echo "$HOST:$PORT: $LOAD"
    LOAD_INT=${LOAD%.*}

    if (( LOAD_INT < LOW_LOAD )); then
        LOW_LOAD=$LOAD_INT
        TARGET_SERVER="$HOST:$PORT"
    fi
done


if [ -z "$TARGET_SERVER" ]; then
  echo -e "${RED}ERROR    | No reachable servers found.${NC}"
  exit 1
fi


for SERVER_ANOTHER in "${SERVERS[@]}"; do
  if [ "$SERVER_ANOTHER" != "$TARGET_SERVER" ]; then
    OTHER_SERVER=$SERVER_ANOTHER
    break
  fi
done

if [ -z "${OTHER_SERVER:-}" ]; then
  echo -e "${RED}ERROR   | No second server found in list.${NC}"
  exit 1
fi


echo -e "${GREEN}SUCCESS | Installation will proceed on: $TARGET_SERVER${NC}"

TARGET_HOST=$(echo "$TARGET_SERVER" | cut -d':' -f1)
TARGET_PORT=$(echo "$TARGET_SERVER" | cut -d':' -f2)

echo "$TARGET_HOST ansible_port=$TARGET_PORT ansible_user=root" > inventory.ini|| {
  echo -e "${RED}ERROR   | Failed to write inventory.ini.${NC}"
  exit 1
}

if ! command -v ansible-playbook &>/dev/null; then
  echo -e "${RED}ERROR   | ansible-playbook not found. Please install Ansible.${NC}"
  exit 1
fi



if ! ANSIBLE_HOST_KEY_CHECKING=False \
  ansible-playbook -i inventory.ini playbook.yml \
  --private-key "$KEY_PATH" \
  -e "student_ip=$(echo $OTHER_SERVER | cut -d':' -f1)"; then
    echo -e "${RED}ERROR | Ansible playbook failed.${NC}"
    exit 1
fi

echo -e "${GREEN}SUCCESS | Ansible playbook completed successfully!${NC}"
