#!/bin/sh
# routeros-setup.sh — Provision and manage netinstall container on RouterOS via REST API
# Requires: curl, jq, RouterOS 7.22+ (REST API property names changed in 7.22)
set -e

# --- Defaults (override via env or flags) ---
ROUTER="${ROUTER:-192.168.88.1}"
ROS_PORT="${ROS_PORT:-}"
ROS_SCHEME="${ROS_SCHEME:-}"
ROS_USER="${ROS_USER:-admin}"
ROS_PASS="${ROS_PASS:-}"
SSH_PORT="${SSH_PORT:-22}"
DISK="${DISK:-}"
PORT="${PORT:-}"
ARCH="${ARCH:-arm64}"
CHANNEL="${CHANNEL:-stable}"
PKGS="${PKGS:-wifi-qcom}"
OPTS="${OPTS:--b -r}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resource names and addressing
VETH=veth-netinstall
BRIDGE=bridge-netinstall
ENVLIST=NETINSTALL
VETH_ADDR=172.17.9.200/24
VETH_GW=172.17.9.1
GW_ADDR=172.17.9.1/24

# --- Usage ---
usage() {
  cat <<'EOF'
Usage: routeros-setup.sh <command> [options]

Commands:
  setup    Create VETH, bridge, envs, and container on RouterOS
  start    Start the netinstall container
  stop     Stop the netinstall container
  status   Show container status
  logs     Show recent container log entries
  remove   Remove container and all netinstall resources
  credentials  Store router username/password in system keychain

Options:
  -r ROUTER  Router address (default: 192.168.88.1, env: ROUTER)
  -P PORT    REST API port (auto-detected, env: ROS_PORT)
  -S SCHEME  http or https (auto-detected, env: ROS_SCHEME)
  -s SSHPORT SSH port for SCP upload (default: 22, env: SSH_PORT)
  -d DISK    Disk path on router, required for setup (e.g. disk1, env: DISK)
  -p PORT    Ethernet port for netinstall, required for setup (e.g. ether5, env: PORT)
  -a ARCH    Target architecture (default: arm64, env: ARCH)
  -c CHANNEL Version channel (default: stable, env: CHANNEL)
  -k PKGS    Extra packages (default: wifi-qcom, env: PKGS)
  -o OPTS    netinstall flags (default: "-b -r", env: OPTS)
  -u USER    Router username (default: admin, env: ROS_USER)
  -w PASS    Router password (env: ROS_PASS, or keychain, or prompted)

The setup command builds the OCI image locally (requires make + crane),
uploads it to the router via SCP, and creates the container from the file.
Install sshpass (brew install hudochenkov/sshpass/sshpass) for non-interactive
SCP, otherwise you will be prompted for the SSH password.

Credentials are resolved in order: env vars (ROS_USER/ROS_PASS),
macOS Keychain / Linux secret-tool, then interactive prompt.

First-time setup — store credentials in keychain:
  routeros-setup.sh credentials -r 192.168.74.1 -P 7080 -S http
After that, only the router address and port are needed:
  routeros-setup.sh status -r 192.168.74.1 -P 7080 -S http
EOF
  exit 1
}

# --- Parse flags ---
CMD="${1:-}"; shift 2>/dev/null || true
while getopts "r:P:S:s:d:p:a:c:k:o:u:w:" opt 2>/dev/null; do
  case "$opt" in
    r) ROUTER="$OPTARG" ;;
    P) ROS_PORT="$OPTARG" ;;
    S) ROS_SCHEME="$OPTARG" ;;
    s) SSH_PORT="$OPTARG" ;;
    d) DISK="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    a) ARCH="$OPTARG" ;;
    c) CHANNEL="$OPTARG" ;;
    k) PKGS="$OPTARG" ;;
    o) OPTS="$OPTARG" ;;
    u) ROS_USER="$OPTARG" ;;
    w) ROS_PASS="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$CMD" ] && usage

# --- Credential resolution ---
# Keychain service name: "routeros://HOST" with account = username
_keychain_svc="routeros://$ROUTER"

get_credentials() {
  # Already have both from env/flags
  if [ -n "$ROS_USER" ] && [ "$ROS_USER" != "admin" ] && [ -n "$ROS_PASS" ]; then
    return 0
  fi

  # macOS Keychain — retrieve both username and password
  if command -v security >/dev/null 2>&1; then
    _kc_user=$(security find-generic-password -s "$_keychain_svc" 2>/dev/null \
      | sed -n 's/.*"acct".*="\([^"]*\)".*/\1/p') || true
    _kc_pass=$(security find-generic-password -s "$_keychain_svc" -w 2>/dev/null) || true
    if [ -n "$_kc_user" ] && [ -n "$_kc_pass" ]; then
      # Only override if not explicitly set via flags
      [ "$ROS_USER" = "admin" ] && ROS_USER="$_kc_user"
      [ -z "$ROS_PASS" ] && ROS_PASS="$_kc_pass"
      return 0
    fi
  fi

  # Linux secret-tool — retrieve both
  if command -v secret-tool >/dev/null 2>&1; then
    _st_user=$(secret-tool lookup service routeros host "$ROUTER" attribute username 2>/dev/null) || true
    _st_pass=$(secret-tool lookup service routeros host "$ROUTER" 2>/dev/null) || true
    if [ -n "$_st_user" ] && [ -n "$_st_pass" ]; then
      [ "$ROS_USER" = "admin" ] && ROS_USER="$_st_user"
      [ -z "$ROS_PASS" ] && ROS_PASS="$_st_pass"
      return 0
    fi
  fi

  # Interactive prompt
  if [ "$ROS_USER" = "admin" ]; then
    printf "Username for %s: " "$ROUTER" >&2
    read -r ROS_USER
  fi
  printf "Password for %s@%s: " "$ROS_USER" "$ROUTER" >&2
  stty -echo 2>/dev/null || true
  read -r ROS_PASS
  stty echo 2>/dev/null || true
  printf "\n" >&2
}

# Store credentials in platform keystore
save_credentials() {
  _user="$1"; _pass="$2"
  if command -v security >/dev/null 2>&1; then
    security add-generic-password \
      -s "$_keychain_svc" \
      -a "$_user" \
      -w "$_pass" \
      -l "RouterOS $ROUTER" \
      -U 2>/dev/null
    echo "Credentials saved to macOS Keychain (service: $_keychain_svc)"
  elif command -v secret-tool >/dev/null 2>&1; then
    printf "%s" "$_pass" | secret-tool store \
      --label "RouterOS $ROUTER" \
      service routeros \
      host "$ROUTER" \
      attribute username \
      username "$_user" 2>/dev/null
    echo "Credentials saved to secret-tool"
  else
    echo "No keystore available (install macOS Keychain or secret-tool)" >&2
    return 1
  fi
}

# --- REST API helpers ---
# Auto-detect scheme and port on first call
api_base() {
  if [ -n "$_API_BASE" ]; then return; fi
  _scheme="${ROS_SCHEME:-}"
  _port="${ROS_PORT:-}"
  if [ -z "$_scheme" ]; then
    # Try HTTPS first (443), then HTTP on common ports
    if [ -z "$_port" ]; then
      if curl -sf -k --max-time 5 -o /dev/null -u "$ROS_USER:$ROS_PASS" "https://$ROUTER/rest/system/resource" 2>/dev/null; then
        _scheme=https; _port=443
      elif curl -sf --max-time 5 -o /dev/null -u "$ROS_USER:$ROS_PASS" "http://$ROUTER/rest/system/resource" 2>/dev/null; then
        _scheme=http; _port=80
      elif curl -sf --max-time 5 -o /dev/null -u "$ROS_USER:$ROS_PASS" "http://$ROUTER:8728/rest/system/resource" 2>/dev/null; then
        _scheme=http; _port=8728
      else
        _scheme=http; _port="${ROS_PORT:-80}"
      fi
    else
      # Port given but not scheme — guess from port number
      case "$_port" in
        443|8729) _scheme=https ;;
        *)        _scheme=http ;;
      esac
    fi
  fi
  if [ "$_port" = "443" ] || [ "$_port" = "80" ]; then
    _API_BASE="$_scheme://$ROUTER"
  else
    _API_BASE="$_scheme://$ROUTER:$_port"
  fi
  export _API_BASE
}

api() {
  api_base
  _method="$1"; _path="$2"; _data="${3:-}"
  _url="$_API_BASE/rest$_path"
  if [ -n "$_data" ]; then
    _resp=$(curl -s -k --max-time 30 -w "\n%{http_code}" -u "$ROS_USER:$ROS_PASS" \
      -X "$_method" \
      -H "content-type: application/json" \
      --data "$_data" \
      "$_url" 2>/dev/null)
  else
    _resp=$(curl -s -k --max-time 30 -w "\n%{http_code}" -u "$ROS_USER:$ROS_PASS" \
      -X "$_method" \
      "$_url" 2>/dev/null)
  fi
  _code=$(echo "$_resp" | tail -1)
  _body=$(echo "$_resp" | sed '$d')
  case "$_code" in
    2*) echo "$_body" ;;
    401) echo "Error: authentication failed for $ROUTER" >&2; exit 1 ;;
    *)
      _msg=$(echo "$_body" | jq -r '.message // .detail // "unknown error"' 2>/dev/null)
      echo "Error: $_method $_path -> $_code $_msg" >&2
      return 1 ;;
  esac
}

# Convenience wrappers
api_get()    { api GET    "$@"; }
api_put()    { api PUT    "$@"; }
api_patch()  { api PATCH  "$@"; }
api_post()   { api POST   "$@"; }
api_delete() { api DELETE "$@"; }

# Find .id of a resource by filter query params
# Usage: find_id "/path" "name=foo" or find_id "/path" "name=foo&key=bar"
find_id() {
  api_get "$1?$2" | jq -r 'if length > 0 then .[0][".id"] else empty end'
}

# Find container .id (by tag or root-dir containing "netinstall")
find_container_id() {
  api_get "/container" | jq -r '[.[] | select(
    (.tag // "" | test("netinstall")) or
    (."root-dir" // "" | test("netinstall"))
  )][0][".id"] // empty'
}

# --- Setup steps ---
ensure_veth() {
  printf "  VETH %s ... " "$VETH"
  _id=$(find_id "/interface/veth" "name=$VETH")
  if [ -n "$_id" ]; then
    echo "exists"
  else
    api_put "/interface/veth" \
      "{\"name\":\"$VETH\",\"address\":\"$VETH_ADDR\",\"gateway\":\"$VETH_GW\"}" >/dev/null
    echo "created"
  fi
}

ensure_ip() {
  printf "  IP %s on %s ... " "$GW_ADDR" "$VETH"
  _id=$(find_id "/ip/address" "interface=$VETH")
  if [ -n "$_id" ]; then
    echo "exists"
  else
    api_put "/ip/address" \
      "{\"address\":\"$GW_ADDR\",\"interface\":\"$VETH\"}" >/dev/null
    echo "added"
  fi
}

ensure_bridge() {
  printf "  Bridge %s ... " "$BRIDGE"
  _id=$(find_id "/interface/bridge" "name=$BRIDGE")
  if [ -n "$_id" ]; then
    echo "exists"
  else
    api_put "/interface/bridge" \
      "{\"name\":\"$BRIDGE\"}" >/dev/null
    echo "created"
  fi
}

ensure_bridge_port() {
  _iface="$1"
  printf "  Bridge port %s -> %s ... " "$_iface" "$BRIDGE"
  _id=$(find_id "/interface/bridge/port" "interface=$_iface")
  if [ -n "$_id" ]; then
    # Check if already in the right bridge
    _current=$(api_get "/interface/bridge/port?interface=$_iface" | jq -r '.[0].bridge // empty')
    if [ "$_current" = "$BRIDGE" ]; then
      echo "exists"
    else
      echo "reassigning from $_current"
      api_patch "/interface/bridge/port/$_id" \
        "{\"bridge\":\"$BRIDGE\"}" >/dev/null
    fi
  else
    api_put "/interface/bridge/port" \
      "{\"bridge\":\"$BRIDGE\",\"interface\":\"$_iface\"}" >/dev/null
    echo "added"
  fi
}

ensure_firewall() {
  printf "  LAN list member %s ... " "$BRIDGE"
  _id=$(find_id "/interface/list/member" "list=LAN&interface=$BRIDGE")
  if [ -n "$_id" ]; then
    echo "exists"
  else
    api_put "/interface/list/member" \
      "{\"list\":\"LAN\",\"interface\":\"$BRIDGE\"}" >/dev/null
    echo "added"
  fi
}

ensure_container_config() {
  printf "  Container registry config ... "
  api_post "/container/config/set" \
    "{\"registry-url\":\"https://registry-1.docker.io\",\"tmpdir\":\"$DISK/pulls\"}" >/dev/null
  echo "set (tmpdir=$DISK/pulls)"
}

ensure_envs() {
  echo "  Environment variables ($ENVLIST):"
  for _pair in "ARCH:$ARCH" "CHANNEL:$CHANNEL" "PKGS:$PKGS" "OPTS:$OPTS" "IFACE:$VETH"; do
    _key="${_pair%%:*}"
    _val="${_pair#*:}"
    _id=$(find_id "/container/envs" "list=$ENVLIST&key=$_key")
    if [ -n "$_id" ]; then
      api_patch "/container/envs/$_id" \
        "{\"value\":\"$_val\"}" >/dev/null
      printf "    %s=%s (updated)\n" "$_key" "$_val"
    else
      api_put "/container/envs" \
        "{\"list\":\"$ENVLIST\",\"key\":\"$_key\",\"value\":\"$_val\"}" >/dev/null
      printf "    %s=%s (created)\n" "$_key" "$_val"
    fi
  done
}

# Detect router architecture and map to Docker platform
detect_router_arch() {
  _res=$(api_get "/system/resource")
  _ros_arch=$(echo "$_res" | jq -r '."architecture-name"')
  case "$_ros_arch" in
    arm64)  _IMAGE_PLATFORM=linux/arm64 ;;
    arm)    _IMAGE_PLATFORM=linux/arm/v7 ;;
    x86)    _IMAGE_PLATFORM=linux/amd64 ;;
    *)      echo "Error: unsupported router architecture: $_ros_arch" >&2; exit 1 ;;
  esac
  echo "$_IMAGE_PLATFORM"
}

# SCP wrapper — uses sshpass if available for non-interactive upload
ros_scp() {
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$ROS_PASS" scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$@"
  else
    echo "    (sshpass not found — you may be prompted for SSH password)" >&2
    scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$@"
  fi
}

# Build OCI image for the router's platform and upload via SCP
upload_image() {
  _plat=$(detect_router_arch)
  _ptag=$(echo "$_plat" | tr '/' '-')
  _tar="images/netinstall-${_ptag}.tar"

  if [ -f "$SCRIPT_DIR/$_tar" ]; then
    echo "  Using existing image: $_tar ($_plat)"
  elif command -v crane >/dev/null 2>&1; then
    echo "  Building image for $_plat ..."
    make -C "$SCRIPT_DIR" image-platform "IMAGE_PLATFORM=$_plat"
    echo "  Build complete: $_tar"
  else
    echo "Error: no image found at $_tar" >&2
    echo "  Build images first:  make image" >&2
    echo "  Or install crane:    go install github.com/google/go-containerregistry/cmd/crane@latest" >&2
    exit 1
  fi

  printf "  Uploading %s to %s:%s/ ... " "$_tar" "$ROUTER" "$DISK"
  ros_scp "$SCRIPT_DIR/$_tar" "$ROS_USER@$ROUTER:$DISK/netinstall.tar"
  echo "uploaded"
}

ensure_container() {
  _id=$(find_container_id)
  if [ -n "$_id" ]; then
    printf "  Container ... exists (%s)\n" "$_id"
  else
    upload_image
    printf "  Container ... "
    api_put "/container" \
      "{\"file\":\"$DISK/netinstall.tar\",\"interface\":\"$VETH\",\"envlists\":\"$ENVLIST\",\"root-dir\":\"$DISK/root-netinstall\",\"workdir\":\"/app\",\"logging\":\"yes\"}" >/dev/null
    echo "created"
  fi
}

# --- Commands ---
cmd_setup() {
  [ -z "$DISK" ] && echo "Error: -d DISK required (e.g. disk1)" >&2 && exit 1
  [ -z "$PORT" ] && echo "Error: -p PORT required (e.g. ether5)" >&2 && exit 1

  echo "Setting up netinstall container on $ROUTER"
  echo "  disk=$DISK port=$PORT arch=$ARCH channel=$CHANNEL"
  echo ""
  ensure_veth
  ensure_ip
  ensure_bridge
  ensure_bridge_port "$VETH"
  ensure_bridge_port "$PORT"
  ensure_firewall
  ensure_container_config
  ensure_envs
  ensure_container
  echo ""
  echo "Done. Monitor with: $0 status -r $ROUTER"
  echo "Start with:         $0 start -r $ROUTER"
}

cmd_start() {
  _id=$(find_container_id)
  [ -z "$_id" ] && echo "Error: no netinstall container found" >&2 && exit 1
  printf "Starting container %s ... " "$_id"
  api_post "/container/start" "{\".id\":\"$_id\"}" >/dev/null
  echo "started"
}

cmd_stop() {
  _id=$(find_container_id)
  [ -z "$_id" ] && echo "Error: no netinstall container found" >&2 && exit 1
  printf "Stopping container %s ... " "$_id"
  api_post "/container/stop" "{\".id\":\"$_id\"}" >/dev/null
  echo "stopped"
}

cmd_status() {
  _container=$(api_get "/container" | jq '[.[] | select(
    (.tag // "" | test("netinstall")) or
    (."root-dir" // "" | test("netinstall"))
  )][0] // empty')
  if [ -z "$_container" ] || [ "$_container" = "null" ]; then
    echo "No netinstall container found on $ROUTER"
    exit 1
  fi
  echo "Container on $ROUTER:"
  echo "$_container" | jq -r '"  ID:     " + .[".id"],
    "  Tag:    " + (.tag // "n/a"),
    "  Status: " + (if .running == "true" then "running" else "stopped" end),
    "  Root:   " + (."root-dir" // "n/a"),
    "  Arch:   " + (.arch // "n/a")'

  # Show env vars
  _envs=$(api_get "/container/envs?list=$ENVLIST" 2>/dev/null) || true
  if [ -n "$_envs" ] && [ "$_envs" != "[]" ]; then
    echo "  Envs:"
    echo "$_envs" | jq -r '.[] | "    " + .key + "=" + .value'
  fi
}

cmd_logs() {
  echo "Recent container logs from $ROUTER:"
  api_get "/log?topics=container" | jq -r '.[-20:] | .[] | .time + " " + .message'
}

cmd_remove() {
  echo "Removing netinstall resources from $ROUTER"

  # Stop and remove container
  _id=$(find_container_id)
  if [ -n "$_id" ]; then
    printf "  Stopping container ... "
    api_post "/container/stop" "{\".id\":\"$_id\"}" >/dev/null 2>&1 || true
    echo "sent"
    # Wait for container to fully stop
    for _i in 1 2 3 4 5 6; do
      sleep 2
      _running=$(api_get "/container" | jq -r --arg id "$_id" '.[] | select(.[".id"] == $id) | .running')
      [ "$_running" != "true" ] && break
      printf "    waiting (%s)...\n" "$_i"
    done
    printf "  Removing container %s ... " "$_id"
    for _i in 1 2 3 4 5; do
      api_delete "/container/$_id" >/dev/null 2>&1 && break
      sleep 3
    done
    echo "removed"
  fi

  # Remove env vars
  _envs=$(api_get "/container/envs?list=$ENVLIST" 2>/dev/null) || true
  if [ -n "$_envs" ] && [ "$_envs" != "[]" ]; then
    echo "$_envs" | jq -r '.[].".id"' | while read -r _eid; do
      printf "  Removing env %s ... " "$_eid"
      api_delete "/container/envs/$_eid" >/dev/null
      echo "removed"
    done
  fi

  # Remove firewall list member
  _id=$(find_id "/interface/list/member" "list=LAN&interface=$BRIDGE")
  if [ -n "$_id" ]; then
    printf "  Removing LAN list member ... "
    api_delete "/interface/list/member/$_id" >/dev/null
    echo "removed"
  fi

  # Remove bridge ports
  _ports=$(api_get "/interface/bridge/port?bridge=$BRIDGE" 2>/dev/null) || true
  if [ -n "$_ports" ] && [ "$_ports" != "[]" ]; then
    echo "$_ports" | jq -r '.[].".id"' | while read -r _pid; do
      printf "  Removing bridge port %s ... " "$_pid"
      api_delete "/interface/bridge/port/$_pid" >/dev/null
      echo "removed"
    done
  fi

  # Remove IP address
  _id=$(find_id "/ip/address" "interface=$VETH")
  if [ -n "$_id" ]; then
    printf "  Removing IP address ... "
    api_delete "/ip/address/$_id" >/dev/null
    echo "removed"
  fi

  # Remove bridge
  _id=$(find_id "/interface/bridge" "name=$BRIDGE")
  if [ -n "$_id" ]; then
    printf "  Removing bridge %s ... " "$BRIDGE"
    api_delete "/interface/bridge/$_id" >/dev/null
    echo "removed"
  fi

  # Remove VETH
  _id=$(find_id "/interface/veth" "name=$VETH")
  if [ -n "$_id" ]; then
    printf "  Removing VETH %s ... " "$VETH"
    api_delete "/interface/veth/$_id" >/dev/null
    echo "removed"
  fi

  echo ""
  echo "Cleanup complete."
}

# --- Credentials command ---
cmd_credentials() {
  printf "Username for %s: " "$ROUTER" >&2
  read -r _cred_user
  printf "Password for %s@%s: " "$_cred_user" "$ROUTER" >&2
  stty -echo 2>/dev/null || true
  read -r _cred_pass
  stty echo 2>/dev/null || true
  printf "\n" >&2

  # Test connection before saving
  ROS_USER="$_cred_user"
  ROS_PASS="$_cred_pass"
  printf "Testing connection to %s ... " "$ROUTER" >&2
  if api_get "/system/resource" >/dev/null 2>&1; then
    echo "OK" >&2
    save_credentials "$_cred_user" "$_cred_pass"
  else
    echo "FAILED" >&2
    echo "Credentials not saved. Check address, port, and credentials." >&2
    exit 1
  fi
}

# --- Main ---

# credentials command runs before normal auth flow
if [ "$CMD" = "credentials" ]; then
  cmd_credentials
  exit 0
fi

get_credentials

# Verify connectivity (also triggers scheme/port auto-detection)
if ! api_get "/system/resource" >/dev/null 2>&1; then
  echo "Error: cannot connect to $ROUTER (check address, port, and credentials)" >&2
  echo "  Try: $0 credentials -r $ROUTER -P 7080 -S http" >&2
  exit 1
fi

case "$CMD" in
  setup)       cmd_setup ;;
  start)       cmd_start ;;
  stop)        cmd_stop ;;
  status)      cmd_status ;;
  logs)        cmd_logs ;;
  remove)      cmd_remove ;;
  credentials) ;; # already handled above
  *)           usage ;;
esac
