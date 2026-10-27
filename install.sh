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

readonly SCRIPT_VERSION="1.0.0"
readonly ROS_DISTRO_NAME="jazzy"
readonly TAG="[ros2-workshop]"
readonly ROS_APT_SOURCE_FALLBACK="1.3.0"
readonly LOG_FILE="$HOME/ros2_workshop_install.log"
# Wait for unattended-upgrades/PackageKit instead of failing, retry flaky
# mirrors, and never stop on a changed-config-file question.
readonly APT_OPTS=(-o DPkg::Lock::Timeout=600 -o Acquire::Retries=3
                   -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

RESULTS_OK=()
RESULTS_FAIL=()
CURRENT_STEP=""
STARTED=false
LOGGING=false

say()  { printf '\n\033[1;34m%s\033[0m %s\n' "$TAG" "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '\n\033[1;33m%s WARNING\033[0m %s\n' "$TAG" "$*" >&2; }
die()  { printf '\n\033[1;31m%s ERROR\033[0m %s\n' "$TAG" "$*" >&2; exit 1; }
trap '((BASH_SUBSHELL)) || printf "\n%s ERROR: command failed (line %s): %s\nRe-running the installer is safe once the problem is fixed.\n" "$TAG" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Steps and checks are counted for the final "N/M passed" summary.
step()       { CURRENT_STEP="$1"; say "$1"; }
step_done()  { [[ -z "$CURRENT_STEP" ]] || RESULTS_OK+=("$CURRENT_STEP"); CURRENT_STEP=""; }
check_ok()   { ok "$1"; RESULTS_OK+=("$1"); }
check_fail() { warn "$1${2:+: $2}"; RESULTS_FAIL+=("$1${2:+: $2}"); }
run_step()   { step "$1"; shift; "$@"; step_done; }

print_counts() {
  local n_ok=${#RESULTS_OK[@]} n_fail=${#RESULTS_FAIL[@]} item
  local total=$((n_ok + n_fail))
  ((total > 0)) || return 0
  if ((n_fail == 0)); then
    printf '\n\033[1;32m%s Results: %d/%d passed, 0 failed\033[0m\n' "$TAG" "$n_ok" "$total"
  else
    printf '\n\033[1;31m%s Results: %d/%d passed, %d failed\033[0m\n' "$TAG" "$n_ok" "$total" "$n_fail"
  fi
  for item in "${RESULTS_OK[@]}"; do printf '  \033[32m✓\033[0m %s\n' "$item"; done
  for item in "${RESULTS_FAIL[@]}"; do printf '  \033[31m✗\033[0m %s\n' "$item"; done
}

on_exit() {
  local rc=$?
  kill "${KEEPALIVE_PID:-}" 2>/dev/null || true
  if [[ "$STARTED" == true ]]; then
    if ((rc != 0)) && [[ -n "$CURRENT_STEP" ]]; then RESULTS_FAIL+=("$CURRENT_STEP (stopped the install)"); fi
    print_counts
    if ((${#RESULTS_FAIL[@]})); then
      printf '\nRe-running the same command is safe. If it keeps failing, send this log to your instructor:\n  %s\n' "$LOG_FILE"
    else
      printf '\nLog: %s\n' "$LOG_FILE"
    fi
  fi
  if [[ "$LOGGING" == true ]]; then
    exec 1>&- 2>&-
    wait "${TEE_PID:-}" 2>/dev/null || true
  fi
  exit "$rc"
}

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
  --apt-proxy URL     Use a classroom apt cache, e.g. http://10.0.0.5:3142 (apt-cacher-ng)
  --dry-run           Show what would be installed and exit without changing anything
  --yes, -y           Don't ask for confirmation
  --help, -h          Show this help

The install log is written to ~/ros2_workshop_install.log. The script exits 0
when every step and check passed, 1 when it stopped early, and 2 when it
finished but some checks failed.

Installed by default:
  ROS 2 Jazzy desktop-full (falls back to desktop), ros-dev-tools (colcon, rosdep, vcstool)
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

retry() {
  local n=1
  until "$@"; do
    ((n < 3)) || return 1
    warn "Attempt $n failed, retrying in $((n * 10))s: $*"
    sleep $((n * 10)); n=$((n + 1))
  done
}

# apt-get's own lock timeout covers apt; this also covers plain dpkg calls and
# tells students why nothing seems to happen.
wait_for_dpkg_lock() {
  command -v fuser >/dev/null 2>&1 || return 0
  local waited=0
  while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    ((waited > 0)) || say "Waiting for another software update to finish (this can take a few minutes)..."
    ((waited < 900)) || die "Another program has been using apt for 15 minutes. Reboot and run the installer again."
    sleep 5; waited=$((waited + 5))
  done
}

apt_get() { wait_for_dpkg_lock; sudo DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" "$@" </dev/null; }
apt_install() { apt_get install -y --no-install-recommends "$@"; }

# A broken third-party source (old Chrome/VS Code/PPA key) makes apt-get
# update fail. Stop only when a source the workshop needs is affected.
apt_update() {
  local out rc=0 problems
  out="$(mktemp)"
  apt_get update 2>&1 | tee "$out" || rc=$?
  problems="$(grep -E '^(E:|Err:|W: Failed to fetch|W: GPG error)' "$out" || true)"
  rm -f -- "$out"
  [[ -n "$problems" || "$rc" -ne 0 ]] || return 0
  if grep -qE 'packages\.ros\.org|download\.docker\.com|nvidia\.github\.io|ubuntu\.com/ubuntu' <<<"$problems"; then
    printf '%s\n' "$problems" >&2
    die "apt could not read a software source this installer needs (lines above). Check your internet connection, firewall or proxy, then re-run."
  fi
  warn "apt reported problems with other software sources that this workshop does not need; continuing.
$problems
  To silence this later, remove or fix the matching file in /etc/apt/sources.list.d/."
}

# Clone once; never touch an existing checkout.
clone_once() {
  local url="$1" dest="$2"; shift 2
  if [[ -d "$dest/.git" ]]; then
    say "$(basename "$dest") already cloned; leaving it untouched"
  elif [[ -e "$dest" ]]; then
    die "$dest exists but is not a git checkout"
  else
    retry git clone --depth 1 "$@" "$url" "$dest" </dev/null || die "Could not clone $url (network problem?). Re-run the installer."
  fi
}

gpu_driver_ok() { command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; }

install_base() {
  if [[ -n "$APT_PROXY" ]]; then
    echo "Acquire::http::Proxy \"$APT_PROXY\";" | sudo tee /etc/apt/apt.conf.d/01ros2-workshop-proxy >/dev/null
    ok "apt will use the cache at $APT_PROXY"
  fi
  # A Ctrl+C, closed lid or power cut during an earlier apt run leaves dpkg
  # half-done; finish it so re-running is always safe.
  if sudo dpkg --audit 2>/dev/null | grep -q .; then
    say "Finishing an earlier interrupted install"
    wait_for_dpkg_lock
    sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a </dev/null
    apt_get -f install -y
  fi
  apt_update
  apt_install software-properties-common ca-certificates curl gnupg lsb-release \
    git wget jq locales build-essential cmake pkg-config \
    python3-pip python3-venv python3-dev
  if ! locale -a 2>/dev/null | grep -qiE '^(en_US|C)\.utf-?8$'; then
    sudo locale-gen en_US.UTF-8 >/dev/null </dev/null
  fi
}

install_ros() {
  if apt-cache policy | grep -q '/universe '; then
    ok "universe repository already enabled"
  else
    sudo add-apt-repository -y universe </dev/null
    apt_update
  fi
  # Pre-2025 instructions wrote ros2.list + ros-archive-keyring.gpg, whose key
  # has since expired; ros2-apt-source is the upstream replacement and the two
  # conflict (different Signed-By), so the old pair is removed.
  local legacy_list=/etc/apt/sources.list.d/ros2.list legacy_key=/usr/share/keyrings/ros-archive-keyring.gpg
  if dpkg-query -W -f='${Status}' ros2-apt-source 2>/dev/null | grep -Fq 'install ok installed'; then
    ok "ros2-apt-source already installed"
    if [[ -f "$legacy_list" ]]; then
      sudo rm -f -- "$legacy_list" "$legacy_key"
      ok "removed the old ros2.list that conflicts with it"
    fi
  elif [[ ! -f "$legacy_list" ]] && grep -rqs 'packages.ros.org/ros2' /etc/apt/sources.list /etc/apt/sources.list.d/; then
    ok "an existing ROS 2 apt source is configured; keeping it"
  else
    if [[ -f "$legacy_list" ]]; then
      say "Replacing the old ROS 2 apt source with ros2-apt-source"
      sudo rm -f -- "$legacy_list" "$legacy_key"
    fi
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
      # Same key and source the package would install, in the legacy layout.
      # The next run replaces it with ros2-apt-source once that downloads.
      warn "Could not download ros2-apt-source; configuring the ROS 2 apt source manually."
      sudo curl -fsSL --retry 3 https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o "$legacy_key"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=$legacy_key] http://packages.ros.org/ros2/ubuntu ${codename} main" \
        | sudo tee "$legacy_list" >/dev/null
    fi
    rm -f -- "$deb"
  fi
  apt_update
  apt-cache show "ros-${ROS_DISTRO_NAME}-desktop" >/dev/null 2>&1 \
    || die "ROS 2 packages are not visible to apt. Check that this machine can reach http://packages.ros.org (firewall/proxy) and re-run."

  step_done

  step "Installing ROS 2 Jazzy desktop"
  if apt-cache show "ros-${ROS_DISTRO_NAME}-desktop-full" >/dev/null 2>&1; then
    ROS_DESKTOP_PACKAGE="ros-${ROS_DISTRO_NAME}-desktop-full"
  else
    warn "ros-${ROS_DISTRO_NAME}-desktop-full is not available; installing ros-${ROS_DISTRO_NAME}-desktop."
    ROS_DESKTOP_PACKAGE="ros-${ROS_DISTRO_NAME}-desktop"
  fi
  apt_get install -y "$ROS_DESKTOP_PACKAGE"
  step_done

  step "Installing ROS 2 development tools and rosdep"
  apt_install ros-dev-tools

  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    say "Initializing rosdep"
    sudo rosdep init </dev/null
  fi
  retry rosdep update --rosdistro "$ROS_DISTRO_NAME" </dev/null || die "rosdep update failed (network problem?). Re-run the installer."

  local line="source /opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  if ! grep -Fxq "$line" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# ROS 2 workshop setup\n%s\n' "$line" >> "$HOME/.bashrc"
  fi
}

install_sim() {
  local d="ros-${ROS_DISTRO_NAME}"
  apt_get install -y \
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
    "$d-rqt-joint-trajectory-controller"
}

build_rrbot() {
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
    clone_once "$url" "$WORKSPACE_PATH/$name"
    ok "cloned $url"
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
  local mode="$1" me
  me="$(id -un)"
  if [[ "$(docker context show 2>/dev/null || true)" == desktop-linux ]]; then
    warn "Docker Desktop is the active Docker context. This installer sets up Docker Engine;
  GPU containers (--gpus) don't work under Docker Desktop. Switch with: docker context use default"
  fi
  if dpkg -s docker-ce >/dev/null 2>&1 && { docker compose version >/dev/null 2>&1 || sudo docker compose version >/dev/null 2>&1; }; then
    ok "Docker and Compose v2 already installed"
  else
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
    # With recommends, like Docker's own guide (rootless extras, pigz).
    apt_get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  # Idempotent, and fixes a stopped or disabled daemon on an existing install.
  start_docker

  if ! id -nG "$me" | grep -qw docker; then
    sudo usermod -aG docker "$me"
    DOCKER_RELOGIN=true
  fi

  if [[ "$mode" == gpu ]]; then
    if command -v nvidia-ctk >/dev/null 2>&1; then
      ok "NVIDIA Container Toolkit already installed"
    else
      ok "installing the NVIDIA Container Toolkit"
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

  step_done

  # Checks only: a Docker Hub hiccup (classroom rate limits) must not throw
  # away the rest of the install.
  say "Checking Docker"
  if sudo docker info >/dev/null 2>&1 </dev/null; then check_ok "Docker daemon running"; else check_fail "Docker daemon running" "see: sudo systemctl status docker"; fi
  if sudo docker run --rm hello-world >/dev/null 2>&1 </dev/null; then
    check_ok "Docker test container (hello-world)"
  else
    check_fail "Docker test container (hello-world)" "could not pull from Docker Hub (offline or rate-limited); try later: docker run --rm hello-world"
  fi
  if [[ "$mode" == gpu ]]; then
    if sudo docker info --format '{{json .Runtimes}}' 2>/dev/null </dev/null | grep -q nvidia; then
      check_ok "NVIDIA runtime registered with Docker"
    else
      check_fail "NVIDIA runtime registered with Docker" "run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
    fi
    if [[ "${ROS2_WORKSHOP_SKIP_GPU_RUN:-0}" == 1 ]]; then
      ok "GPU container test skipped (ROS2_WORKSHOP_SKIP_GPU_RUN=1)"
    elif sudo docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L </dev/null; then
      check_ok "GPU visible inside containers"
    else
      check_fail "GPU visible inside containers" "try later: docker run --rm --gpus all ubuntu:24.04 nvidia-smi"
    fi
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
    if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then check_ok "Package found: $label ($pkg)"; else check_fail "Package found: $label ($pkg)" "not installed"; fi
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
  if [[ "$INSTALL_ROS" == true && "$(basename "${SHELL:-bash}")" == zsh ]]; then
    printf '\nYou use zsh: add ROS 2 to it with\n  echo "source /opt/ros/%s/setup.zsh" >> ~/.zshrc\n' "$ROS_DISTRO_NAME"
  fi
}

# Fail in the first seconds rather than 20 minutes in.
preflight() {
  local need=3 avail
  [[ "$INSTALL_ROS" != true ]] || need=$((need + 5))
  [[ "$INSTALL_SIM" != true ]] || need=$((need + 4))
  [[ "$DOCKER_MODE" == skip ]] || need=$((need + 3))
  avail="$(df -BG --output=avail / | tail -1 | tr -dc 0-9)"
  if ((avail < need)); then
    die "Not enough disk space: this needs about ${need} GB free on /, you have ${avail} GB. Free some space and re-run."
  fi
  check_ok "Disk space (${avail} GB free, about ${need} GB needed)"

  command -v curl >/dev/null 2>&1 || return 0
  local urls=(https://github.com) url unreachable=()
  [[ "$INSTALL_ROS" != true ]] || urls+=(http://packages.ros.org/ros2/ubuntu/ https://raw.githubusercontent.com)
  [[ "$DOCKER_MODE" == skip ]] || urls+=(https://download.docker.com)
  [[ "$DOCKER_MODE" != gpu ]] || urls+=(https://nvidia.github.io)
  for url in "${urls[@]}"; do
    curl -sS -o /dev/null -m 20 --retry 2 "$url" 2>/dev/null || unreachable+=("$url")
  done
  if ((${#unreachable[@]})); then
    die "Cannot reach: ${unreachable[*]}
  Check your internet connection. On a university or office network a firewall may block these; try a phone hotspot."
  fi
  check_ok "Internet access to the package servers"
}

# Stop a laptop from suspending mid-install (the usual way dpkg gets
# interrupted). The holder exits on its own when this script does.
keep_awake() {
  [[ -d /run/systemd/system ]] && command -v systemd-inhibit >/dev/null 2>&1 || return 0
  systemd-inhibit --what=sleep:idle --who=ros2-workshop-setup --why="Installing ROS 2" \
    bash -c "while kill -0 $$ 2>/dev/null; do sleep 5; done" >/dev/null 2>&1 &
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
  APT_PROXY=""
  DRY_RUN=false

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
      --apt-proxy) (($# >= 2)) || die "--apt-proxy needs a URL"; APT_PROXY="$2"; shift 2 ;;
      --apt-proxy=*) APT_PROXY="${1#*=}"; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
  done
  case "$DOCKER_MODE" in auto|cpu|gpu|skip) ;; *) die "Invalid --docker mode: $DOCKER_MODE (auto|gpu|cpu|skip)" ;; esac
  [[ -z "$APT_PROXY" || "$APT_PROXY" =~ ^https?://[^[:space:]\"]+$ ]] || die "--apt-proxy must be a URL like http://10.0.0.5:3142"
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
  elif [[ "$DOCKER_MODE" == gpu ]] && ! gpu_driver_ok && [[ "$DRY_RUN" != true ]]; then
    die "GPU mode needs a working NVIDIA driver. Install one (sudo ubuntu-drivers install), reboot, and re-run, or use the cpu mode instead."
  fi

  if [[ "$DRY_RUN" != true ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    TEE_PID=$!
    LOGGING=true
    printf '\n===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  fi
  trap on_exit EXIT

  say "ROS 2 workshop installer $SCRIPT_VERSION"
  printf '  ROS 2 Jazzy desktop:   %s\n' "$INSTALL_ROS"
  printf '  Simulation packages:   %s\n' "$INSTALL_SIM"
  printf '  RRBot source build:    %s\n' "$BUILD_RRBOT"
  printf '  Docker:                %s\n' "$DOCKER_MODE"
  printf '  Workspace:             %s\n' "$WORKSPACE_PATH"
  ((${#EXTRA_CLONES[@]} == 0)) || printf '  Extra clones:          %s\n' "${EXTRA_CLONES[*]}"
  [[ -z "$APT_PROXY" ]] || printf '  apt cache:             %s\n' "$APT_PROXY"
  if [[ "$DRY_RUN" == true ]]; then
    printf '\nDry run: nothing was changed.\n'
    exit 0
  fi
  printf '\nThis installs apt packages and apt sources with sudo and may restart Docker.\n'
  if [[ "$ASSUME_YES" != true ]]; then
    local reply
    reply="$(ask 'Continue? [y/N] ')" || die "No terminal to ask for confirmation. Re-run with --yes (e.g. ... | bash -s cpu --yes)."
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled; nothing was changed."
  fi

  say "Enter your login password if asked (nothing appears while you type; that is normal)"
  sudo -v
  # Keep the sudo timestamp fresh during long apt/colcon steps.
  ( while sleep 50; do sudo -n true 2>/dev/null || exit; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
  KEEPALIVE_PID=$!
  keep_awake
  STARTED=true

  step "Checking this computer"
  preflight
  CURRENT_STEP=""
  run_step "Installing base Ubuntu packages" install_base
  mkdir -p "$WORKSPACE_PATH"
  if [[ "$INSTALL_ROS" == true ]]; then
    step "Configuring the ROS 2 apt repository"
    install_ros
    step_done
    if [[ "$INSTALL_SIM" == true ]]; then
      run_step "Installing simulation packages (Gazebo, ros2_control, MoveIt 2, UR, Panda, TurtleBot 4, Nav2)" install_sim
    fi
    if [[ "$BUILD_RRBOT" == true ]]; then
      run_step "Building RRBot from ros2_control_demos (${ROS_DISTRO_NAME} branch)" build_rrbot
    fi
  fi
  if ((${#EXTRA_CLONES[@]})); then run_step "Cloning workshop repositories" clone_extras; fi
  if [[ "$DOCKER_MODE" != skip ]]; then run_step "Installing Docker ($DOCKER_MODE)" install_docker "$DOCKER_MODE"; fi
  if [[ "$INSTALL_ROS" == true ]]; then verify_ros; fi
  print_summary
  ((${#RESULTS_FAIL[@]} == 0)) || exit 2
}

main "$@"
