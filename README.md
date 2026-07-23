# VaultFlow

A secure and user-friendly password generator and manager built with Python, PyQt5, and Cryptography. Generate strong passwords, save existing ones, store multiple accounts per website, and securely manage all your credentials in an encrypted vault.

![Password Manager](https://img.shields.io/badge/Python-3.6%2B-blue)
![PyQt5](https://img.shields.io/badge/PyQt5-Required-green)
![Cryptography](https://img.shields.io/badge/Cryptography-Fernet-blueviolet)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

### 🔐 Strong Master Password & Encryption
- **AES-128-CBC Encryption**: Vault data is encrypted at rest using Fernet symmetric encryption.
- **PBKDF2 Key Derivation**: Uses PBKDF2HMAC-SHA256 with 480,000 iterations and random per-vault salts to resist brute-force attacks.
- **Master Password Prompt**: On startup, VaultFlow prompts for your master password to unlock the vault (allowing up to 3 failed attempts before locking out).
- **Automated Migration**: Plaintext `passwords.json` files from legacy versions are automatically prompt-guided to encrypt upon first launch.

### 🛡️ Clipboard & Data Protection
- **Auto-Clearing Clipboard**: Passwords copied to the clipboard are automatically cleared after 30 seconds (if the clipboard contents haven't been altered).
- **Atomic File Writes**: Prevents vault corruption during unexpected crashes by writing to a temporary file (`passwords.json.tmp`) before replacing the primary file.
- **Rolling Backups**: Automatically creates a `.bak` copy of your vault on every save.
- **Secure Random Generation**: Uses `random.SystemRandom()` for cryptographically secure password generation.

### ⚙️ Password Generation
- **Customizable Length**: Generate passwords from 1 to 128 characters.
- **Character Type Selection**:
  - Lowercase letters (`a-z`)
  - Uppercase letters (`A-Z`)
  - Numbers (`0-9`)
  - Symbols (`!@#$%^&*()_+-=[]{}|;:,.<>?`)
- **Real-time Generation**: Instant creation with your specifications.
- **Direct Save**: Attach generated credentials directly to a service name, username, and optional notes.

### ➕ Add Existing Passwords
- Manually enter existing account details without running the generator.
- Toggle visibility ("Show password") for error-free typing.
- Copy password to clipboard prior to saving.

### 🔍 Password Management
- **Masked Passwords**: Hidden as dots (`••••••••`) by default in the manager view.
- **Interactive Table**: Dedicated Show/Hide, Copy, and Edit actions for each saved entry.
- **Live Search**: Filter accounts dynamically by website/service name, username, or notes.
- **Edit & Delete**: Easily edit username/password/notes or remove unwanted records.
- **Bulk Export**: Formatted text export to clipboard with clear security warnings.

---

## Installation

### Prerequisites
- Python 3.6 or higher
- PyQt5
- cryptography

### Install Dependencies
```bash
pip install pyqt5 cryptography
