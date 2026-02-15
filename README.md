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

- **Multi-User Support:** Query single or multiple users (comma-separated) in one batch.
- **Data Export:** Save reports instantly as **JSON** or **CSV** files.
- **Auto-Logging:** Automatically saves session logs to the `./logs` directory.
- **Interactive Session:** Run multiple queries without restarting the script.
- **Direct MariaDB Access:** Extracts data straight from the source of truth.
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
`bash
    ./clockwork.sh
    `

## 🖼️ Example Output

```text
 ██████╗██╗      ██████╗ ██████╗██╗  ██╗██╗     ██╗ ██████╗ ██████╗ ██╗  ██╗
██╔════╝██║     ██╔═══██╗██╔════╝██║ ██╔╝██║     ██║██╔═══██╗██╔══██╗██║ ██╔╝
██║     ██║     ██║   ██║██║     █████╔╝ ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
██║     ██║     ██║   ██║██║     ██╔═██╗ ██║███╗██║██║   ██║██╔══██╗██╔═██╗
╚██████╗███████╗╚██████╔╝╚██████╗██║  ██╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
 ╚═════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
             ORANGEHRM CLI EDITION  v2.0.0

 :: Session Started at Sat Feb 15 11:00:00 UTC 2026 ::

 [+] Configuration loaded from .env

 [?] Target Username(s)
     Tip: Separate multiple users with comma (e.g. ilia,admin)
     Enter username(s) (Default: root): ilia, admin

 [?] Date Selection
     1) Current Month (Default)
     2) Custom Range
     Select option [1]: 1
 [Config] Date Range: Current Month (2026-02-01 to 2026-02-15)

 [*] Connecting to container 'orangehrm_mariadb'...

 --- Report for: ilia ---
 Date         | In       | Out      | Hours
 -------------+----------+----------+-------
 2026-02-01   | 09:00    | 17:00    | 8.00
 -------------+----------+----------+-------
 TOTAL HOURS: 8.00

 [?] Export data for ilia?
     1) No (Default)
     2) JSON
     3) CSV
     Select option: 2
 [✔] Exported to ./clockwork_ilia_1771153200.json

 --- Report for: admin ---
 ```

## 📄 License

This project is dedicated to the public domain under the CC0 1.0 Universal license. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.
