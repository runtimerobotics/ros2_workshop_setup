#!/usr/bin/env bash
# ROS 2 workshop setup for Ubuntu 24.04 (Noble), ROS 2 Jazzy.
#
# Installs ROS 2 Jazzy desktop(-full), the workshop simulation stack
# (Gazebo Harmonic, ros2_control, MoveIt 2, Universal Robots, Franka Panda,
# TurtleBot 4, Nav2, SLAM Toolbox, RRBot) and Docker with or without
# NVIDIA GPU support.
#
# One-liner (run as your normal user, NOT with sudo):
#   curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s gpu
#
# Or download first and inspect:
#   curl -fsSLO https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh
#   bash install.sh --help
#
# Safe to re-run: anything already installed or cloned is left in place.
# This script never installs an NVIDIA driver; do that separately and reboot.

# Everything lives in main(), called on the last line, so that a truncated
# download does nothing and `curl | bash` reads the whole script before any
# command can consume stdin.

# shellcheck disable=SC1090,SC1091  # /etc/os-release and ROS setup files are sourced at runtime
set -Eeuo pipefail

readonly SCRIPT_VERSION="2026-10-27"
readonly ROS_DISTRO_NAME="jazzy"
readonly TAG="[ros2-workshop]"
readonly ROS_APT_SOURCE_FALLBACK="1.3.0"

say()  { printf '\n\033[1;34m%s\033[0m %s\n' "$TAG" "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '\n\033[1;33m%s WARNING\033[0m %s\n' "$TAG" "$*" >&2; }
die()  { printf '\n\033[1;31m%s ERROR\033[0m %s\n' "$TAG" "$*" >&2; exit 1; }
trap '((BASH_SUBSHELL)) || printf "\n%s ERROR: command failed (line %s): %s\nRe-running the installer is safe once the problem is fixed.\n" "$TAG" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
  cat <<'HELP'
Usage: install.sh [MODE] [OPTIONS]
  (piped:  curl -fsSL <url>/install.sh | bash -s MODE [OPTIONS])

Modes (shortcuts):
  gpu                 ROS 2 + simulation + Docker with NVIDIA GPU
  cpu                 ROS 2 + simulation + Docker without GPU
  ros                 ROS 2 + simulation, no Docker
  docker-gpu          Only Docker with NVIDIA GPU
  docker-cpu          Only Docker without GPU

Docker:
  --docker auto       GPU Docker if nvidia-smi works, otherwise CPU (default)
  --docker gpu        Docker + NVIDIA Container Toolkit (needs a working driver)
  --docker cpu        Docker + Compose only, no NVIDIA toolkit
  --docker skip       Leave Docker untouched

What to install:
  --docker-only       Only Docker (same as --no-ros)
  --no-ros            Skip ROS 2 and the simulation packages
  --no-sim            Install ROS 2 desktop only, skip the simulation packages
  --skip-rrbot        Skip the RRBot (ros2_control_demos) source build
  --clone URL         Also git clone URL into the workspace (repeatable),
                      e.g. a workshop's own code repository

General:
  --workspace PATH    Workspace for cloned/built code (default: ~/ros2_workshop)
  --yes, -y           Don't ask for confirmation
  --help, -h          Show this help

Installed by default:
  ROS 2 Jazzy desktop-full (falls back to desktop), ros-dev-tools, rosdep
  Gazebo Harmonic (ros_gz), ros2_control + controllers + gz_ros2_control demos
  MoveIt 2, Franka Panda MoveIt config, Universal Robots + ur_simulation_gz
  TurtleBot 4 simulator, Nav2, SLAM Toolbox, cv_bridge, image_transport
  RRBot built from ros2_control_demos (jazzy branch) in <workspace>/rrbot_ws
  Docker Engine + Compose v2 (+ NVIDIA Container Toolkit in GPU mode)

Requirements: Ubuntu 24.04 amd64, a sudo-capable user, internet access.
The Docker step removes Ubuntu's conflicting docker.io/podman-docker packages
(images in /var/lib/docker are kept) and may restart the Docker service.
HELP
}

# Read a line from the user even when the script itself arrives on stdin.
ask() {
  local prompt="$1" reply=""
  if [[ -t 0 ]]; then
    read -r -p "$prompt" reply
  elif { exec 3</dev/tty; } 2>/dev/null; then
    printf '%s' "$prompt" >/dev/tty
    read -r reply <&3
    exec 3<&-
  else
    return 1
  fi
  printf '%s' "$reply"
}

apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" </dev/null; }
apt_update()  { sudo apt-get update </dev/null; }

# Clone once; never touch an existing checkout.
clone_once() {
  local url="$1" dest="$2"; shift 2
  if [[ -d "$dest/.git" ]]; then
    say "$(basename "$dest") already cloned; leaving it untouched"
  elif [[ -e "$dest" ]]; then
    die "$dest exists but is not a git checkout"
  else
    git clone --depth 1 "$@" "$url" "$dest" </dev/null
  fi
}

gpu_driver_ok() { command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; }

install_base() {
  say "Installing base Ubuntu packages"
  apt_update
  apt_install software-properties-common ca-certificates curl gnupg lsb-release \
    git wget jq locales build-essential cmake pkg-config \
    python3-pip python3-venv python3-dev
  if ! locale -a 2>/dev/null | grep -qiE '^(en_US|C)\.utf-?8$'; then
    sudo locale-gen en_US.UTF-8 </dev/null
  fi
}

install_ros() {
  say "Configuring the ROS 2 apt repository"
  if apt-cache policy | grep -q '/universe '; then
    ok "universe repository already enabled"
  else
    sudo add-apt-repository -y universe </dev/null
    apt_update
  fi
  if dpkg-query -W -f='${Status}' ros2-apt-source 2>/dev/null | grep -Fq 'install ok installed'; then
    ok "ros2-apt-source already installed"
  elif apt-cache show "ros-${ROS_DISTRO_NAME}-desktop" >/dev/null 2>&1; then
    ok "an existing ROS 2 apt source already provides Jazzy; keeping it"
  else
    # Resolve the latest release with git (no GitHub API, so a whole classroom
    # behind one IP doesn't hit the API rate limit); fall back to a known tag.
    local version codename deb
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    version="$(git ls-remote --tags --refs https://github.com/ros-infrastructure/ros-apt-source.git 2>/dev/null \
      | sed -n 's#.*refs/tags/\([0-9][0-9.]*\)$#\1#p' | sort -V | tail -1 || true)"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || version="$ROS_APT_SOURCE_FALLBACK"
    deb="$(mktemp --suffix=.deb)"
    if curl -fsSL --retry 3 -o "$deb" \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/ros2-apt-source_${version}.${codename}_all.deb"; then
      ok "installing ros2-apt-source $version"
      apt_install "$deb"
    else
      # Same key and source the package would install, written by hand.
      warn "Could not download ros2-apt-source; configuring the ROS 2 apt source manually."
      sudo curl -fsSL --retry 3 https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${codename} main" \
        | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
    fi
    rm -f -- "$deb"
  fi
  apt_update
  apt-cache show "ros-${ROS_DISTRO_NAME}-desktop" >/dev/null 2>&1 \
    || die "ROS 2 packages are not visible to apt. Check that this machine can reach http://packages.ros.org (firewall/proxy) and re-run."

  say "Installing ROS 2 Jazzy desktop"
  if apt-cache show "ros-${ROS_DISTRO_NAME}-desktop-full" >/dev/null 2>&1; then
    ROS_DESKTOP_PACKAGE="ros-${ROS_DISTRO_NAME}-desktop-full"
  else
    warn "ros-${ROS_DISTRO_NAME}-desktop-full is not available; installing ros-${ROS_DISTRO_NAME}-desktop."
    ROS_DESKTOP_PACKAGE="ros-${ROS_DISTRO_NAME}-desktop"
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$ROS_DESKTOP_PACKAGE" </dev/null

  say "Installing ROS 2 development tools"
  apt_install ros-dev-tools python3-colcon-common-extensions python3-vcstool python3-rosdep

  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    say "Initializing rosdep"
    sudo rosdep init </dev/null
  fi
  rosdep update --rosdistro "$ROS_DISTRO_NAME" </dev/null

  local line="source /opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  if ! grep -Fxq "$line" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# ROS 2 workshop setup\n%s\n' "$line" >> "$HOME/.bashrc"
  fi
}

install_sim() {
  local d="ros-${ROS_DISTRO_NAME}"
  say "Installing simulation packages (Gazebo, ros2_control, MoveIt 2, UR, Panda, TurtleBot 4, Nav2)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "$d-tf2-tools" "$d-xacro" \
    "$d-robot-state-publisher" "$d-joint-state-publisher-gui" \
    "$d-ros-gz" "$d-ros-gz-sim-demos" \
    "$d-ros2-control" "$d-ros2-controllers" \
    "$d-gz-ros2-control" "$d-gz-ros2-control-demos" \
    "$d-moveit" \
    "$d-moveit-resources-panda-description" \
    "$d-moveit-resources-panda-moveit-config" \
    "$d-ur" "$d-ur-simulation-gz" \
    "$d-turtlebot4-simulator" \
    "$d-navigation2" "$d-nav2-bringup" "$d-slam-toolbox" \
    "$d-cv-bridge" "$d-image-transport" \
    "$d-rqt-joint-trajectory-controller" </dev/null
}

build_rrbot() {
  say "Building RRBot from ros2_control_demos (${ROS_DISTRO_NAME} branch)"
  RR_WORKSPACE="$WORKSPACE_PATH/rrbot_ws"
  local repo="$RR_WORKSPACE/src/ros2_control_demos"
  mkdir -p "$RR_WORKSPACE/src"
  clone_once https://github.com/ros-controls/ros2_control_demos.git "$repo" --branch "$ROS_DISTRO_NAME"
  set +u
  source "/opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  set -u
  rosdep install --rosdistro "$ROS_DISTRO_NAME" --from-paths \
    "$repo/example_1" "$repo/ros2_control_demo_description" "$repo/ros2_control_demo_test_utils" \
    --ignore-src -r -y </dev/null
  ( cd "$RR_WORKSPACE" && colcon build --symlink-install --packages-up-to ros2_control_demo_example_1 \
      --cmake-args -DPython3_EXECUTABLE=/usr/bin/python3 -DPYTHON_EXECUTABLE=/usr/bin/python3 </dev/null )
}

clone_extras() {
  local url name
  for url in "${EXTRA_CLONES[@]}"; do
    name="$(basename "${url%/}" .git)"
    [[ -n "$name" && "$name" != . && "$name" != / ]] || die "Cannot derive a folder name from $url"
    say "Cloning $url"
    clone_once "$url" "$WORKSPACE_PATH/$name"
  done
}

# systemd on normal installs; `service` where there is none (WSL, containers).
start_docker() {
  if [[ -d /run/systemd/system ]]; then
    if [[ "${1:-}" == restart ]]; then sudo systemctl restart docker; else sudo systemctl enable --now docker; fi
  else
    sudo service docker "${1:-start}" || true
    if ! sudo docker info >/dev/null 2>&1 && ! pgrep -x dockerd >/dev/null; then
      sudo sh -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
    fi
    local _; for _ in $(seq 1 20); do sudo docker info >/dev/null 2>&1 && return; sleep 1; done
    die "Docker daemon did not start."
  fi </dev/null
}

# Docker Engine + Compose v2 (+ NVIDIA Container Toolkit), per
# https://docs.docker.com/engine/install/ubuntu/ and
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
install_docker() {
  local mode="$1"
  if docker compose version >/dev/null 2>&1 || sudo docker compose version >/dev/null 2>&1; then
    ok "Docker and Compose v2 already installed"
  else
    say "Installing Docker Engine and Compose v2"
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      if dpkg -s "$pkg" >/dev/null 2>&1; then sudo apt-get remove -y "$pkg" </dev/null; fi
    done
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt_update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    start_docker
  fi

  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    DOCKER_RELOGIN=true
  fi

  if [[ "$mode" == gpu ]]; then
    if command -v nvidia-ctk >/dev/null 2>&1; then
      ok "NVIDIA Container Toolkit already installed"
    else
      say "Installing NVIDIA Container Toolkit"
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
      curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
      apt_update
      apt_install nvidia-container-toolkit
    fi
    if grep -qs '"nvidia"' /etc/docker/daemon.json; then
      ok "Docker already has the nvidia runtime"
    else
      # Restarting Docker stops running containers, so only do it when needed.
      sudo nvidia-ctk runtime configure --runtime=docker
      start_docker restart
    fi
  fi

  say "Checking Docker"
  sudo docker run --rm hello-world >/dev/null </dev/null && ok "docker run hello-world"
  if [[ "$mode" == gpu ]]; then
    sudo docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L </dev/null && ok "GPU visible inside containers"
  fi
}

verify_ros() {
  say "Checking ROS 2 packages"
  set +u
  source "/opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  [[ -n "${RR_WORKSPACE:-}" && -f "$RR_WORKSPACE/install/setup.bash" ]] && source "$RR_WORKSPACE/install/setup.bash"
  set -u
  local entry label pkg
  local checks=("ROS 2 CLI|ros2cli")
  if [[ "$INSTALL_SIM" == true ]]; then
    checks+=("UR Gazebo|ur_simulation_gz" "Franka MoveIt|moveit_resources_panda_moveit_config"
             "TurtleBot 4|turtlebot4_gz_bringup" "Gazebo control|gz_ros2_control_demos" "Nav2|nav2_bringup")
  fi
  [[ -n "${RR_WORKSPACE:-}" ]] && checks+=("RRBot|ros2_control_demo_example_1")
  for entry in "${checks[@]}"; do
    label="${entry%%|*}" pkg="${entry#*|}"
    if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then ok "$label ($pkg)"; else warn "Not found: $label ($pkg)"; FAILED_CHECKS=true; fi
  done
}

print_summary() {
  say "Done"
  printf '  ROS 2:     %s\n' "${ROS_DESKTOP_PACKAGE:-skipped}"
  printf '  Docker:    %s\n' "$DOCKER_MODE"
  printf '  Workspace: %s\n' "$WORKSPACE_PATH"
  if [[ "$INSTALL_ROS" == true ]]; then
    cat <<EOF

Open a NEW terminal (so ~/.bashrc sources ROS 2), then try one simulator at a time:
  ros2 run demo_nodes_cpp talker
EOF
    if [[ "$INSTALL_SIM" == true ]]; then
      cat <<'EOF'
  ros2 launch ur_simulation_gz ur_sim_moveit.launch.py ur_type:=ur5e
  ros2 launch moveit_resources_panda_moveit_config demo.launch.py
  ros2 launch turtlebot4_gz_bringup turtlebot4_gz.launch.py
  ros2 launch gz_ros2_control_demos diff_drive_example.launch.py
EOF
    fi
    if [[ -n "${RR_WORKSPACE:-}" ]]; then
      printf '  source %s/install/setup.bash && ros2 launch ros2_control_demo_example_1 rrbot.launch.py\n' "$RR_WORKSPACE"
    fi
  fi
  if [[ "${DOCKER_RELOGIN:-false}" == true ]]; then
    printf '\nYou were added to the docker group: log out and back in (or run "newgrp docker") to use docker without sudo.\n'
  fi
  if [[ "$DOCKER_MODE" == gpu ]]; then
    printf 'GPU containers: docker run --rm --gpus all ubuntu:24.04 nvidia-smi\n'
  fi
  if [[ -n "${SHADOW_PYTHON:-}" ]]; then
    warn "'python3' in your shell is $SHADOW_PYTHON, not Ubuntu's /usr/bin/python3.
  ROS 2 Jazzy needs /usr/bin/python3 (3.12); colcon builds will fail with errors like
  \"No module named 'catkin_pkg'\" while that one comes first on PATH. Remove it,
  move it later in PATH, or deactivate conda/venv/pyenv before building ROS code."
  fi
  if [[ "${FAILED_CHECKS:-false}" == true ]]; then
    warn "Some package checks failed; scroll up for details. Re-running the installer is safe."
  fi
}

main() {
  DOCKER_MODE="auto"
  WORKSPACE_PATH="${ROS2_WORKSHOP_WORKSPACE:-$HOME/ros2_workshop}"
  INSTALL_ROS=true
  INSTALL_SIM=true
  BUILD_RRBOT=true
  ASSUME_YES=false
  EXTRA_CLONES=()
  RR_WORKSPACE=""

  while (($#)); do
    case "$1" in
      --docker) (($# >= 2)) || die "--docker needs auto, gpu, cpu or skip"; DOCKER_MODE="$2"; shift 2 ;;
      --docker=*) DOCKER_MODE="${1#*=}"; shift ;;
      gpu|cpu|auto) DOCKER_MODE="$1"; shift ;;
      ros|nodocker) DOCKER_MODE=skip; shift ;;
      docker-gpu|docker-cpu) INSTALL_ROS=false; DOCKER_MODE="${1#docker-}"; shift ;;
      --gpu) DOCKER_MODE=gpu; shift ;;
      --cpu|--no-gpu) DOCKER_MODE=cpu; shift ;;
      --docker-only|--no-ros) INSTALL_ROS=false; shift ;;
      --no-sim) INSTALL_SIM=false; shift ;;
      --skip-rrbot|--no-rrbot) BUILD_RRBOT=false; shift ;;
      --clone) (($# >= 2)) || die "--clone needs a URL"; EXTRA_CLONES+=("$2"); shift 2 ;;
      --workspace) (($# >= 2)) || die "--workspace needs a path"; WORKSPACE_PATH="$2"; shift 2 ;;
      --workspace=*) WORKSPACE_PATH="${1#*=}"; shift ;;
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
  done
  case "$DOCKER_MODE" in auto|cpu|gpu|skip) ;; *) die "Invalid --docker mode: $DOCKER_MODE (auto|gpu|cpu|skip)" ;; esac
  [[ "$INSTALL_ROS" == true ]] || { INSTALL_SIM=false; BUILD_RRBOT=false; }
  [[ "$INSTALL_SIM" == true ]] || BUILD_RRBOT=false
  if [[ "$INSTALL_ROS" == false && "$DOCKER_MODE" == skip && ${#EXTRA_CLONES[@]} -eq 0 ]]; then
    die "Nothing to do: --no-ros together with --docker skip."
  fi

  # ROS 2 Jazzy is built against Ubuntu's Python. A conda/venv/pyenv or
  # ~/.local python3 earlier on PATH breaks rosdep/colcon, so put /usr/bin first.
  SHADOW_PYTHON=""
  if [[ "$(command -v python3 || true)" != /usr/bin/python3 ]]; then
    SHADOW_PYTHON="$(command -v python3 || true)"
    warn "Ignoring $SHADOW_PYTHON for this install and using Ubuntu's /usr/bin/python3."
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    unset PYTHONPATH PYTHONHOME VIRTUAL_ENV CONDA_PREFIX
  fi

  ((EUID != 0)) || die "Run as your normal user, not root/sudo. The script calls sudo itself."
  command -v sudo >/dev/null || die "sudo is required."
  [[ -r /etc/os-release ]] || die "Cannot identify the operating system."
  local os_id os_ver
  os_id="$(. /etc/os-release && echo "$ID")"
  os_ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
  [[ "$os_id" == ubuntu && "$os_ver" == 24.04 ]] || die "ROS 2 Jazzy needs Ubuntu 24.04 (found $os_id ${os_ver:-unknown})."
  [[ "$(dpkg --print-architecture)" == amd64 ]] || die "Only amd64 (x86_64) machines are supported."

  WORKSPACE_PATH="${WORKSPACE_PATH/#\~/$HOME}"
  [[ "$WORKSPACE_PATH" == /* ]] || WORKSPACE_PATH="$PWD/$WORKSPACE_PATH"
  [[ "$WORKSPACE_PATH" != / && "$WORKSPACE_PATH" != "$HOME" && "$WORKSPACE_PATH" != "$HOME/" ]] || die "Pick a dedicated --workspace folder, not / or your home."

  if [[ "$DOCKER_MODE" == auto ]]; then
    if gpu_driver_ok; then DOCKER_MODE=gpu
    else DOCKER_MODE=cpu; warn "No working NVIDIA driver (nvidia-smi); using CPU Docker."; fi
  elif [[ "$DOCKER_MODE" == gpu ]] && ! gpu_driver_ok; then
    die "GPU mode needs a working NVIDIA driver. Install one (sudo ubuntu-drivers install), reboot, and re-run, or use the cpu mode instead."
  fi

  say "ROS 2 workshop installer $SCRIPT_VERSION"
  printf '  ROS 2 Jazzy desktop:   %s\n' "$INSTALL_ROS"
  printf '  Simulation packages:   %s\n' "$INSTALL_SIM"
  printf '  RRBot source build:    %s\n' "$BUILD_RRBOT"
  printf '  Docker:                %s\n' "$DOCKER_MODE"
  printf '  Workspace:             %s\n' "$WORKSPACE_PATH"
  ((${#EXTRA_CLONES[@]} == 0)) || printf '  Extra clones:          %s\n' "${EXTRA_CLONES[*]}"
  printf '\nThis installs apt packages and apt sources with sudo and may restart Docker.\n'
  if [[ "$ASSUME_YES" != true ]]; then
    local reply
    reply="$(ask 'Continue? [y/N] ')" || die "No terminal to ask for confirmation. Re-run with --yes (e.g. ... | bash -s cpu --yes)."
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled; nothing was changed."
  fi

  say "Enter your login password if asked (nothing appears while you type; that is normal)"
  sudo -v
  # Keep the sudo timestamp fresh during long apt/colcon steps.
  ( while sleep 50; do sudo -n true 2>/dev/null || exit; kill -0 "$$" 2>/dev/null || exit; done ) &
  KEEPALIVE_PID=$!
  trap 'kill "${KEEPALIVE_PID:-}" 2>/dev/null || true' EXIT

  install_base
  mkdir -p "$WORKSPACE_PATH"
  if [[ "$INSTALL_ROS" == true ]]; then
    install_ros
    [[ "$INSTALL_SIM" == true ]] && install_sim
    [[ "$BUILD_RRBOT" == true ]] && build_rrbot
  fi
  ((${#EXTRA_CLONES[@]} == 0)) || clone_extras
  if [[ "$DOCKER_MODE" != skip ]]; then install_docker "$DOCKER_MODE"; fi
  [[ "$INSTALL_ROS" == true ]] && verify_ros
  print_summary
}

main "$@"
