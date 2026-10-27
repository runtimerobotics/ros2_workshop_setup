# ROS 2 Workshop Setup

Sets up an **Ubuntu 24.04** PC for a ROS 2 workshop with one command:
ROS 2 Jazzy, the simulation packages we use in class, and Docker.

## Quick start

1. Open a terminal (**Ctrl + Alt + T**).
2. Copy **one** command below and paste it into the terminal (**Ctrl + Shift + V**), then press **Enter**.
3. Type `y` and press **Enter** when it asks `Continue? [y/N]`.
4. Type your login password when asked. **Nothing appears on screen while you type the password. That's normal.** Press **Enter** when you're done.
5. Wait about 15 to 30 minutes. When it says **Done**, close the terminal and open a new one.

### PC with an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s gpu
```

### PC without an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s cpu
```

Not sure which one you have? Run `nvidia-smi`. If it prints a table with your GPU, use **gpu**. If not, use **cpu**.

## Check it works

In a **new** terminal:

```bash
ros2 run demo_nodes_cpp talker
```

You should see `Publishing: 'Hello World: 1'` and so on. Press **Ctrl + C** to stop.

## Try the simulations

Run one at a time, and press **Ctrl + C** to stop each one:

```bash
ros2 launch ur_simulation_gz ur_sim_moveit.launch.py ur_type:=ur5e      # UR arm + MoveIt
ros2 launch moveit_resources_panda_moveit_config demo.launch.py          # Franka Panda
ros2 launch turtlebot4_gz_bringup turtlebot4_gz.launch.py                # TurtleBot 4
ros2 launch gz_ros2_control_demos diff_drive_example.launch.py           # Gazebo + ros2_control

source ~/ros2_workshop/rrbot_ws/install/setup.bash
ros2 launch ros2_control_demo_example_1 rrbot.launch.py                  # RRBot
```

## Other modes

Swap the last word of the command:

| Last word | What it installs |
|---|---|
| `gpu` | ROS 2 + simulation + Docker with NVIDIA GPU |
| `cpu` | ROS 2 + simulation + Docker without GPU |
| `ros` | ROS 2 + simulation, no Docker |
| `docker-gpu` | Only Docker, with NVIDIA GPU |
| `docker-cpu` | Only Docker, without GPU |

For example, to install only Docker with GPU support:

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh | bash -s docker-gpu
```

<details>
<summary>Advanced options (for instructors)</summary>

Add these after the mode, e.g. `| bash -s gpu --yes --skip-rrbot`:

| Flag | What it does |
|---|---|
| `--yes` | Don't ask for confirmation (lab imaging, scripts) |
| `--no-sim` | Only ROS 2 desktop, no simulation packages |
| `--skip-rrbot` | Don't build RRBot |
| `--clone URL` | Also clone a workshop repo into `~/ros2_workshop` (can repeat) |
| `--workspace PATH` | Use a different folder instead of `~/ros2_workshop` |
| `--docker auto` | Pick GPU or CPU automatically (the default when no mode is given) |

To read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/main/install.sh
bash install.sh --help
```

</details>

## What gets installed

- ROS 2 Jazzy `desktop-full`, colcon and rosdep, with ROS set up automatically in every new terminal
- Gazebo Harmonic, ros2_control, MoveIt 2, Universal Robots, Franka Panda, TurtleBot 4, Nav2, SLAM Toolbox
- RRBot, built in `~/ros2_workshop/rrbot_ws`
- Docker + Compose, plus NVIDIA GPU support for containers in `gpu` mode

## Troubleshooting

| Problem | Fix |
|---|---|
| It stopped with an error | Fix what it says, then run the same command again. It's safe to re-run, and anything already installed is skipped. |
| "GPU mode needs a working NVIDIA driver" | Run `sudo ubuntu-drivers install`, reboot, and try again. Or use `cpu`. |
| "ROS 2 packages are not visible to apt" | Your network blocks `packages.ros.org`. Try another network, such as a phone hotspot. |
| A warning that `python3` is not `/usr/bin/python3` | Another Python (conda, pyenv, or one in `~/.local/bin`) is ahead of Ubuntu's. Deactivate or remove it before building ROS code. |
| `docker: permission denied` | Log out and back in once, or run `newgrp docker`. |
| `ros2: command not found` | Open a new terminal. The current one was opened before the install. |

Requires Ubuntu 24.04 (64-bit) and internet access. The script doesn't install NVIDIA drivers.
