# ROS 2 Workshop Setup

Sets up an **Ubuntu 24.04** PC for a ROS 2 workshop with one command:
ROS 2 Jazzy, the simulation packages we use in class, and Docker.

## Quick start

Open a terminal and run **one** of these as your normal user (not `sudo`).

### Laptop/PC with an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s -- --docker gpu
```

Make sure the NVIDIA driver works first: `nvidia-smi` should list your GPU.
If it doesn't, run `sudo ubuntu-drivers install && sudo reboot`, then try again.

### Laptop/PC without an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s -- --docker cpu
```

The script shows what it will install, asks `Continue? [y/N]`, then asks for
your password once. It takes about 15 to 30 minutes, depending on your internet speed.

When it finishes, **close the terminal and open a new one**, then check:

```bash
ros2 run demo_nodes_cpp talker
```

## Try the simulations

Run one at a time:

```bash
ros2 launch ur_simulation_gz ur_sim_moveit.launch.py ur_type:=ur5e      # UR arm + MoveIt
ros2 launch moveit_resources_panda_moveit_config demo.launch.py          # Franka Panda
ros2 launch turtlebot4_gz_bringup turtlebot4_gz.launch.py                # TurtleBot 4
ros2 launch gz_ros2_control_demos diff_drive_example.launch.py           # Gazebo + ros2_control

source ~/ros2_workshop/rrbot_ws/install/setup.bash
ros2 launch ros2_control_demo_example_1 rrbot.launch.py                  # RRBot
```

To use Docker without `sudo`, log out and back in once. To check that containers can see your GPU (GPU mode only):

```bash
docker run --rm --gpus all ubuntu:24.04 nvidia-smi
```

## What gets installed

- ROS 2 Jazzy `desktop-full`, colcon, rosdep, plus `source /opt/ros/jazzy/setup.bash` added to `~/.bashrc`
- Gazebo Harmonic, ros2_control, MoveIt 2, Universal Robots, Franka Panda, TurtleBot 4, Nav2, SLAM Toolbox
- RRBot built from source in `~/ros2_workshop/rrbot_ws`
- Docker + Compose, plus the NVIDIA Container Toolkit in GPU mode

## Other options

<details>
<summary>More install variants and flags</summary>

Everything goes after `| bash -s --`:

| Flag | What it does |
|---|---|
| `--docker gpu` | Docker with NVIDIA GPU support |
| `--docker cpu` | Docker without GPU |
| `--docker auto` | Picks GPU if `nvidia-smi` works, else CPU (the default if you leave out `--docker`) |
| `--docker skip` | Don't touch Docker |
| `--docker-only` | Only install Docker, no ROS 2 |
| `--no-sim` | Only ROS 2 desktop, no simulation packages |
| `--skip-rrbot` | Don't build RRBot |
| `--clone URL` | Also clone a workshop repo into `~/ros2_workshop` (can repeat) |
| `--workspace PATH` | Use a different folder instead of `~/ros2_workshop` |
| `--yes` | Don't ask for confirmation (lab imaging, scripts) |

Examples:

```bash
# Docker only, with GPU
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s -- --docker-only --docker gpu

# ROS 2 + simulation, no Docker
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s -- --docker skip

# GPU setup plus a workshop's own repo
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s -- --docker gpu --clone https://github.com/runtimerobotics/vlm_packt_workshop.git
```

Want to read the script before running it?

```bash
curl -fsSLO https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh
bash install.sh --help
```

</details>

## Troubleshooting

- **Something failed partway:** fix the issue it reports, then run the same command again. It's safe to re-run, and anything already installed is skipped.
- **"GPU mode needs a working NVIDIA driver":** install the driver (see Quick start) or use the CPU command.
- **"ROS 2 packages are not visible to apt":** your network is blocking `packages.ros.org`. Try another network or ask your IT team to allow it.
- **`docker: permission denied`:** log out and back in, or run `newgrp docker`.

Requires Ubuntu 24.04 (64-bit, x86) and internet access. NVIDIA drivers are not installed by the script. In Docker mode it removes Ubuntu's `docker.io` package if present, but keeps your images.
