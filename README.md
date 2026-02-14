# Clockwork OrangeHRM CLI ⚙️🍊

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat&logo=gnu-bash)
![Docker](https://img.shields.io/badge/Integration-Docker-2496ED?style=flat&logo=docker)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

**Clockwork OrangeHRM** is a powerful, interactive CLI utility designed for DevOps engineers and System Administrators managing self-hosted OrangeHRM instances.

It bypasses UI limitations by directly querying the MariaDB backend via Docker, giving you instant access to work-hour calculations and attendance logs.

> _"A tool for those who prefer the terminal over the mouse."_

## 🚀 Features

- **Interactive Experience:** Clean, color-coded prompts for username and date selection.
- **Smart Defaults:** Automatically calculates hours for the current month if no date is provided.
- **Secure Authentication:** Supports `.env` configuration to keep database credentials safe.
- **Dual Modes:** Get a quick summary total or a detailed daily breakdown table.
- **Zero Dependencies:** Requires only `docker` and `bash`.

## 🛠️ Installation

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/YOUR_USERNAME/clockwork-orangehrm-cli.git](https://github.com/YOUR_USERNAME/clockwork-orangehrm-cli.git)
   cd clockwork-orangehrm-cli
   Make the script executable:
   ```

Bash
chmod +x clockwork.sh
(Optional) Configure Environment:
To skip the password prompt, copy the example config and edit it:

Bash
cp .env.example .env
nano .env
Add your DB password and container name in .env.

💻 Usage
Run the script and follow the on-screen prompts:

Bash
./clockwork.sh
Example Output
Plaintext

---

/ **_| | _** **\_| | \_\_\_** **\_ **| | **
| | | |/ \_ \ / **| |/ /\ \ /\ / / _ \/ _` |
| |**_| | (_) | (**| < \ V V / (\_) \_\_ |
\_**_|_|\_**/ \_**|\_|\_\ \_/\_/ \_**/|\_\_\_/
ORANGEHRM CLI EDITION v1.0.0

[+] Configuration loaded from .env

[?] Target Username
Enter username (Default: ilia):

[?] Date Selection 1) Current Month (Default) 2) Custom Range
Select option [1]:

[*] Connecting to container 'orangehrm_mariadb'...
[+] User verified! Employee ID: 12

---

# TOTAL WORK HOURS (2026-02-01 to 2026-02-14): 85.50

🤝 Contributing
Contributions are welcome! Please feel free to submit a Pull Request.
