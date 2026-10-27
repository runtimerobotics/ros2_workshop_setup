# ROS 2 Workshop Setup

One command to prepare an **Ubuntu 24.04** laptop or lab PC for a ROS 2 workshop:
ROS 2 **Jazzy** desktop, the simulation packages we use in class, and **Docker**
with or without NVIDIA GPU support.

Run it as your normal user (not `sudo`); it asks for your password once.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash
```

This installs everything and picks the Docker mode for you: GPU if `nvidia-smi`
works, otherwise CPU. It shows what it will do and asks before changing anything.

## Common variants

| What you want | Command |
|---|---|
| Everything, Docker with NVIDIA GPU | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --docker gpu` |
| Everything, Docker without GPU | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --docker cpu` |
| ROS 2 + simulation, no Docker | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --docker skip` |
| ROS 2 desktop only | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --no-sim --docker skip` |
| Docker only (GPU) | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --docker-only --docker gpu` |
| Docker only (no GPU) | `curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \| bash -s -- --docker-only --docker cpu` |
| Unattended (lab imaging) | add `--yes` to any of the above |

Prefer to read the script first?

```bash
curl -fsSLO https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh
less install.sh
bash install.sh --help
bash install.sh --docker cpu
```

## Options

| Flag | Meaning |
|---|---|
| `--docker auto` | GPU Docker if an NVIDIA driver works, else CPU (default) |
| `--docker gpu` (`--gpu`) | Docker + Compose + NVIDIA Container Toolkit. Needs a working driver |
| `--docker cpu` (`--cpu`) | Docker + Compose only |
| `--docker skip` | Leave Docker alone |
| `--docker-only` / `--no-ros` | Skip ROS 2 entirely |
| `--no-sim` | ROS 2 desktop + dev tools only, no simulation packages |
| `--skip-rrbot` | Don't build RRBot from source |
| `--clone URL` | Also clone a repo into the workspace (repeatable), e.g. the workshop's code |
| `--workspace PATH` | Where code is cloned/built (default `~/ros2_workshop`) |
| `--yes`, `-y` | Don't ask for confirmation |

Example for a specific workshop:

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh \
  | bash -s -- --docker gpu --clone https://github.com/runtimerobotics/vlm_packt_workshop.git
```

## What gets installed

- **ROS 2 Jazzy** `desktop-full` (falls back to `desktop`), `ros-dev-tools`, colcon, vcstool, rosdep, and `source /opt/ros/jazzy/setup.bash` in `~/.bashrc`
- **Simulation:** Gazebo Harmonic (`ros_gz`), `ros2_control` + controllers, `gz_ros2_control` demos, MoveIt 2, Franka Panda MoveIt config, Universal Robots + `ur_simulation_gz`, TurtleBot 4 simulator, Nav2, SLAM Toolbox, `cv_bridge`, `image_transport`
- **RRBot**, built from [`ros2_control_demos`](https://github.com/ros-controls/ros2_control_demos) (jazzy branch) in `~/ros2_workshop/rrbot_ws`
- **Docker** Engine + Compose v2 from Docker's apt repo, your user added to the `docker` group, and in GPU mode the **NVIDIA Container Toolkit** with the Docker runtime configured

The script does **not** install NVIDIA drivers. For GPU mode, install one first:

```bash
sudo ubuntu-drivers install && sudo reboot
nvidia-smi   # should list your GPU
```

## After installing

Open a **new terminal**, then try one simulator at a time:

```bash
ros2 run demo_nodes_cpp talker
ros2 launch ur_simulation_gz ur_sim_moveit.launch.py ur_type:=ur5e
ros2 launch moveit_resources_panda_moveit_config demo.launch.py
ros2 launch turtlebot4_gz_bringup turtlebot4_gz.launch.py
ros2 launch gz_ros2_control_demos diff_drive_example.launch.py

source ~/ros2_workshop/rrbot_ws/install/setup.bash
ros2 launch ros2_control_demo_example_1 rrbot.launch.py
```

Docker without `sudo` needs a fresh login (or `newgrp docker`). GPU check:

```bash
docker run --rm --gpus all ubuntu:24.04 nvidia-smi
```

## Notes

- Requires Ubuntu 24.04 on amd64 and internet access. Expect a few GB of downloads.
- Safe to re-run: installed packages are skipped and existing clones are never modified.
- The Docker step removes Ubuntu's conflicting `docker.io` / `podman-docker` packages (images in `/var/lib/docker` are kept) and may restart Docker.
- Piped through `curl | bash`, the confirmation prompt reads from your terminal. With no terminal at all (CI, ssh without a tty), pass `--yes`.
