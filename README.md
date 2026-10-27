# ROS 2 Workshop Setup

Sets up an **Ubuntu 24.04** PC for a ROS 2 workshop with one command:
ROS 2 Jazzy, the simulation packages we use in class, and Docker.

## Before the workshop

Please do this **at home, a day or two before**, on good Wi-Fi. It downloads
several GB and takes 15 to 30 minutes.

- **Ubuntu 24.04 64-bit.** Check with `lsb_release -d`. It should say `Ubuntu 24.04`.
- **About 20 GB free disk space.** Check with `df -h /` and look at the `Avail` column.
- **Plugged into power,** so the laptop doesn't go to sleep halfway through.

## Quick start

1. Open a terminal (**Ctrl + Alt + T**).
2. Copy **one** command below and paste it into the terminal (**Ctrl + Shift + V**), then press **Enter**.
3. Type `y` and press **Enter** when it asks `Continue? [y/N]`.
4. Type your login password when asked. **Nothing appears on screen while you type the password. That's normal.** Press **Enter** when you're done.
5. At the end it prints a result like **`Results: 14/14 passed, 0 failed`**. Close the terminal and open a new one.

### PC with an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/v1.0.0/install.sh | bash -s gpu
```

### PC without an NVIDIA GPU

```bash
curl -fsSL https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/v1.0.0/install.sh | bash -s cpu
```

### Which one do I need?

1. Run `lspci | grep -i nvidia`. If it prints nothing, you don't have an NVIDIA GPU: use **cpu**.
2. If it shows a GPU, run `nvidia-smi`. If that prints a table with your GPU, the driver works: use **gpu**.
3. If it shows a GPU but `nvidia-smi` fails, install the driver first:
   ```bash
   sudo ubuntu-drivers install
   sudo reboot
   ```
   If **Secure Boot** is on, the install asks you to set a password. After the reboot, a blue **"Perform MOK management"** screen appears: choose **Enroll MOK**, then **Continue**, and type that password. If you skip this screen, the driver won't load. Then run `nvidia-smi` again and use **gpu**.

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

<details>
<summary>Advanced options (for instructors)</summary>

Add these after the mode, e.g. `| bash -s gpu --yes --skip-rrbot`:

| Flag | What it does |
|---|---|
| `--dry-run` | Show what would be installed, change nothing |
| `--yes` | Don't ask for confirmation (lab imaging, scripts) |
| `--no-sim` | Only ROS 2 desktop, no simulation packages |
| `--skip-rrbot` | Don't build RRBot |
| `--clone URL` | Also clone a workshop repo into `~/ros2_workshop` (can repeat) |
| `--workspace PATH` | Use a different folder instead of `~/ros2_workshop` |
| `--apt-proxy URL` | Use a classroom apt cache (apt-cacher-ng), e.g. `http://10.0.0.5:3142` |
| `--docker auto` | Pick GPU or CPU automatically (the default when no mode is given) |

**Versions.** The commands above are pinned to the `v1.0.0` release, so every student runs the same script. `main` is for development. Before a workshop, tag a new release and update the links here.

**Exit codes:** `0` means everything passed, `1` means it stopped early, and `2` means it finished but some checks failed. Every run is logged to `~/ros2_workshop_install.log`.

**GPU runner.** The CI workflow has a manual `real-gpu` job for a self-hosted runner with the labels `self-hosted, gpu`. Run it from the Actions tab before a workshop to test the real driver path.

To read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/runtimerobotics/ros2_workshop_setup/v1.0.0/install.sh
bash install.sh --help
```

</details>

## What gets installed

- ROS 2 Jazzy `desktop-full` and ros-dev-tools (colcon, rosdep), with ROS set up automatically in every new terminal
- Gazebo Harmonic, ros2_control, MoveIt 2, Universal Robots, Franka Panda, TurtleBot 4, Nav2, SLAM Toolbox
- RRBot, built in `~/ros2_workshop/rrbot_ws`
- Docker + Compose, plus NVIDIA GPU support for containers in `gpu` mode

## Troubleshooting

First, run the same command again. It's safe to re-run, and anything already installed is skipped. If it still fails, send `~/ros2_workshop_install.log` to your instructor.

| Problem | Fix |
|---|---|
| "Waiting for another software update to finish" | Ubuntu is installing updates in the background. The script waits, up to 15 minutes. If it gives up, reboot and run it again. |
| "Could not get lock" or "dpkg was interrupted" | Run the command again. It finishes the interrupted install first. |
| "apt reported problems with other software sources" | An old Chrome, VS Code or PPA source has a broken key. The install continues anyway. To fix it, remove the file it names from `/etc/apt/sources.list.d/`. |
| "Not enough disk space" | Free up the amount it shows, then run it again. |
| "Cannot reach ..." or "ROS 2 packages are not visible to apt" | Your network blocks a package server. Try another network, such as a phone hotspot. |
| "GPU mode needs a working NVIDIA driver" | See [Which one do I need?](#which-one-do-i-need), or use `cpu`. |
| "Docker test container (hello-world)" failed | Docker installed fine, but Docker Hub was busy or rate-limited. Later, try `docker run --rm hello-world`. |
| A warning that `python3` is not `/usr/bin/python3` | Another Python (conda, pyenv, or one in `~/.local/bin`) comes before Ubuntu's. Deactivate or remove it before building ROS code. |
| `docker: permission denied` | Log out and back in once, or run `newgrp docker`. |
| `ros2: command not found` | Open a new terminal. If you use zsh, run `echo "source /opt/ros/jazzy/setup.zsh" >> ~/.zshrc`. |
| Gazebo is very slow or shows a black window (laptop with NVIDIA + Intel/AMD graphics) | Run it on the NVIDIA GPU: `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ros2 launch ...`, or switch permanently with `sudo prime-select nvidia` and reboot. |
| Gazebo shows a black window in a virtual machine | Use software rendering: `LIBGL_ALWAYS_SOFTWARE=1 ros2 launch ...` |

Requires Ubuntu 24.04 (64-bit) and internet access. The script doesn't install NVIDIA drivers.
