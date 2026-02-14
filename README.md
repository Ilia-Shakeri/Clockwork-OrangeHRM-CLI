<div align="center">

<img width="40%" alt='OrangeHRM' src='https://raw.githubusercontent.com/wiki/orangehrm/orangehrm/logos/logo.svg#gh-light-mode-only'/><img width="40%" alt='OrangeHRM' src='https://raw.githubusercontent.com/wiki/orangehrm/orangehrm/logos/logo_dark_mode.svg#gh-dark-mode-only'/>

  <h1>Clockwork OrangeHRM CLI ⚙️🍊</h1>
  
  <p>
    <b>The missing CLI tool for Self-Hosted OrangeHRM instances.</b>
  </p>

  <p>
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/License-CC0_1.0-lightgrey.svg?style=flat-square" alt="License">
    </a>
    <img src="https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash" alt="Bash">
    <img src="https://img.shields.io/badge/Database-MariaDB-003545?style=flat-square&logo=mariadb" alt="MariaDB">
    <img src="https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker" alt="Docker">
  </p>
  
  <br>
</div>

**Clockwork OrangeHRM** is a robust, interactive CLI utility designed specifically for **Self-Hosted** OrangeHRM instances running on **MariaDB**.

It bypasses UI limitations by directly querying the database backend, giving DevOps engineers and System Admins instant access to work-hour calculations and attendance logs.

> _"No web interface needed. Just pure data extraction."_

---

## 🚀 Features

- **Self-Hosted Focus:** Optimized for local or VPS-hosted OrangeHRM containers.
- **Direct MariaDB Access:** Extracts data straight from the source of truth.
- **Interactive Mode:** Clean prompts for username, date ranges, and report types.
- **Smart Defaults:** Auto-calculates current month's hours.
- **Secure:** Supports `.env` file configuration.

## 🛠️ Prerequisites

- A **Self-Hosted** OrangeHRM instance.
- **MariaDB** as the database backend (MySQL is likely compatible but untested).
- Docker installed on the host machine.

## 📥 Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Ilia-Shakeri/Clockwork-OrangeHRM-CLI.git
   cd clockwork-orangehrm-cli
   ```

2. **Make the script executable:**

   ```bash
   chmod +x clockwork.sh
   ```

3. (Optional) Configure Environment:

   ```bash
   cp .env.example .env
   nano .env
   ```

## 💻 Usage

Run the script and follow the on-screen prompts:
    ```bash
    ./clockwork.sh
    ```

## 🖼️ Example Output

  ```text
    ____ _            _                     _
    / ___| | ___   ___| | _____      ___  __| | __
  | |   | |/ _ \ / __| |/ /\ \ /\ / / _ \/ _` |
  | |___| | (_) | (__|   <  \ V  V / (_) \__  |
    \____|_|\___/ \___|_|\_\  \_/\_/ \___/|___/

  :: Time Tracking Extraction Tool ::

  [+] Configuration loaded from .env

  [?] Target Username
      Enter username (Default: ilia):

  [?] Date Selection
      1) Current Month (Default)
      2) Custom Range
      Select option [1]: 1

  [*] Connecting to container 'orangehrm_mariadb'...
  [+] User verified! Employee ID: 12
  --------------------------------------------------------
  TOTAL WORK HOURS (2026-02-01 to 2026-02-14): 85.50
  ========================================================
  ```

## 📄 License

This project is dedicated to the public domain under the CC0 1.0 Universal license. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.
