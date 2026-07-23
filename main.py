import sys
import random
import string
import json
import os
import shutil
import base64
from datetime import datetime
from PyQt5.QtWidgets import (QApplication, QMainWindow, QVBoxLayout, QHBoxLayout,
                             QWidget, QLabel, QLineEdit, QPushButton, QCheckBox,
                             QTextEdit, QSpinBox, QMessageBox, QGroupBox, QTableWidget,
                             QTableWidgetItem, QHeaderView, QAbstractItemView, QTabWidget,
                             QPlainTextEdit, QDialog, QDialogButtonBox, QFormLayout)
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QFont, QPalette, QColor

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

INIT_X = 25
INIT_Y = 70
INIT_XY = [INIT_X, INIT_Y]
WIDTH = 1200
HEIGHT = 800
INIT_WH = [WIDTH, HEIGHT]
user_password = "passwords.json"

PBKDF2_ITERATIONS = 480_000
CLIPBOARD_CLEAR_SECONDS = 30


def derive_key(master_password, salt):
    """Derive a Fernet-compatible key from a master password and salt."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=PBKDF2_ITERATIONS,
    )
    key = kdf.derive(master_password.encode('utf-8'))
    return base64.urlsafe_b64encode(key)


class MasterPasswordDialog(QDialog):
    """Used both to create a new master password (first run / migrating an old
    plaintext vault) and to unlock an existing encrypted vault."""

    def __init__(self, parent=None, mode='unlock', error_message=None, extra_info=None):
        super().__init__(parent)
        self.mode = mode
        self.setWindowTitle('Create Master Password' if mode == 'create' else 'Unlock VaultFlow')
        self.setMinimumWidth(400)
        self.setModal(True)

        layout = QVBoxLayout(self)

        if mode == 'create':
            info_text = ('Choose a master password to encrypt your vault.\n'
                          'This password is not stored anywhere - if you forget it, '
                          'your saved passwords cannot be recovered.')
        else:
            info_text = 'Enter your master password to unlock VaultFlow.'
        if extra_info:
            info_text += '\n\n' + extra_info

        info_label = QLabel(info_text)
        info_label.setWordWrap(True)
        layout.addWidget(info_label)

        if error_message:
            error_label = QLabel(error_message)
            error_label.setStyleSheet('color: red;')
            error_label.setWordWrap(True)
            layout.addWidget(error_label)

        form = QFormLayout()
        self.password_input = QLineEdit()
        self.password_input.setEchoMode(QLineEdit.Password)
        form.addRow('Master Password:', self.password_input)

        self.confirm_input = None
        if mode == 'create':
            self.confirm_input = QLineEdit()
            self.confirm_input.setEchoMode(QLineEdit.Password)
            form.addRow('Confirm Password:', self.confirm_input)

        layout.addLayout(form)

        show_cb = QCheckBox('Show password')

        def toggle(checked):
            echo = QLineEdit.Normal if checked else QLineEdit.Password
            self.password_input.setEchoMode(echo)
            if self.confirm_input:
                self.confirm_input.setEchoMode(echo)

        show_cb.toggled.connect(toggle)
        layout.addWidget(show_cb)

        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.validate_and_accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

        self.password_input.setFocus()

    def validate_and_accept(self):
        password = self.password_input.text()
        if not password:
            QMessageBox.warning(self, 'Warning', 'Please enter a password!')
            return
        if self.mode == 'create':
            if len(password) < 8:
                QMessageBox.warning(self, 'Warning', 'Master password should be at least 8 characters.')
                return
            if password != self.confirm_input.text():
                QMessageBox.warning(self, 'Warning', 'Passwords do not match!')
                return
        self.accept()

    def get_password(self):
        return self.password_input.text()


def unlock_vault(passwords_file):
    """Load and, if necessary, decrypt the vault file. Returns (data, fernet, salt).
    Exits the application if the user cancels or fails to authenticate."""

    salt = None
    encrypted_payload = None
    legacy_plaintext_data = None

    if os.path.exists(passwords_file):
        try:
            with open(passwords_file, 'r') as f:
                raw = f.read()
            parsed = json.loads(raw) if raw.strip() else {}
        except (json.JSONDecodeError, OSError):
            parsed = {}

        if isinstance(parsed, dict) and 'salt' in parsed and 'vault' in parsed:
            salt = base64.urlsafe_b64decode(parsed['salt'])
            encrypted_payload = parsed['vault']
        elif isinstance(parsed, dict):
            legacy_plaintext_data = parsed
        else:
            legacy_plaintext_data = {}
    else:
        legacy_plaintext_data = {}

    if salt is not None:
        # Existing encrypted vault: prompt to unlock, allow a few attempts.
        attempts = 0
        error_message = None
        max_attempts = 3
        while attempts < max_attempts:
            dialog = MasterPasswordDialog(mode='unlock', error_message=error_message)
            if dialog.exec_() != QDialog.Accepted:
                sys.exit(0)
            key = derive_key(dialog.get_password(), salt)
            fernet = Fernet(key)
            try:
                decrypted = fernet.decrypt(encrypted_payload.encode('utf-8'))
                data = json.loads(decrypted.decode('utf-8'))
                return data, fernet, salt
            except (InvalidToken, ValueError, Exception):
                attempts += 1
                remaining = max_attempts - attempts
                error_message = f'Incorrect master password. {remaining} attempt(s) remaining.'
        QMessageBox.critical(None, 'Locked Out', 'Too many failed attempts. Closing VaultFlow.')
        sys.exit(1)
    else:
        # No encrypted vault yet: first run, or migrating an existing plaintext file.
        is_migration = bool(legacy_plaintext_data)
        extra_info = ('An existing unencrypted passwords.json was found - it will be '
                       'encrypted with this new master password.') if is_migration else None
        dialog = MasterPasswordDialog(mode='create', extra_info=extra_info)
        if dialog.exec_() != QDialog.Accepted:
            sys.exit(0)
        new_salt = os.urandom(16)
        key = derive_key(dialog.get_password(), new_salt)
        fernet = Fernet(key)
        return legacy_plaintext_data, fernet, new_salt


class PasswordManager(QMainWindow):
    def __init__(self, initial_data, fernet, salt, passwords_file):
        super().__init__()
        self.passwords_file = passwords_file
        self.fernet = fernet
        self.salt = salt
        self.passwords_data = self.convert_old_format(initial_data or {})

        # Clipboard auto-clear support
        self.clipboard_timer = QTimer(self)
        self.clipboard_timer.setSingleShot(True)
        self.clipboard_timer.timeout.connect(self.clear_clipboard_if_unchanged)
        self._last_copied_value = None

        self.initUI()
        self.refresh_password_list()

        # If this was a first run or a migration from an unencrypted file, persist
        # immediately so the vault is encrypted on disk right away.
        self.save_passwords_to_file()

    def initUI(self):
        self.setWindowTitle('VaultFlow')
        self.setGeometry(*INIT_XY, *INIT_WH)
        self.setMinimumSize(700, 600)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)

        self.tab_widget = QTabWidget()
        main_layout.addWidget(self.tab_widget)

        self.create_generator_tab()
        self.create_add_password_tab()
        self.create_manager_tab()

    def create_add_password_tab(self):
        add_tab = QWidget()
        self.tab_widget.addTab(add_tab, "Add Password")

        layout = QVBoxLayout(add_tab)
        layout.setSpacing(20)

        title = QLabel('Add Existing Password')
        title.setFont(QFont('Arial', 20, QFont.Bold))
        title.setAlignment(Qt.AlignCenter)
        layout.addWidget(title)

        # Account Information
        account_group = QGroupBox('Account Information')
        account_layout = QVBoxLayout(account_group)

        service_label = QLabel('Website/Service Name:')
        self.add_service_input = QLineEdit()
        self.add_service_input.setPlaceholderText('e.g., gmail.com, facebook.com')

        username_label = QLabel('Username/Email:')
        self.add_username_input = QLineEdit()
        self.add_username_input.setPlaceholderText('e.g., john@example.com or username')

        password_label = QLabel('Password:')
        self.add_password_input = QLineEdit()
        self.add_password_input.setPlaceholderText('Enter your existing password')
        self.add_password_input.setEchoMode(QLineEdit.Password)

        confirm_label = QLabel('Confirm Password:')
        self.add_confirm_password_input = QLineEdit()
        self.add_confirm_password_input.setPlaceholderText('Re-enter the password to confirm')
        self.add_confirm_password_input.setEchoMode(QLineEdit.Password)

        show_password_cb = QCheckBox('Show password')
        show_password_cb.toggled.connect(lambda checked: (
            self.add_password_input.setEchoMode(QLineEdit.Normal if checked else QLineEdit.Password),
            self.add_confirm_password_input.setEchoMode(QLineEdit.Normal if checked else QLineEdit.Password)
        ))

        notes_label = QLabel('Notes (optional):')
        self.add_notes_input = QPlainTextEdit()
        self.add_notes_input.setPlaceholderText('e.g., Work account, Personal email, Admin access...')
        self.add_notes_input.setMaximumHeight(80)

        account_layout.addWidget(service_label)
        account_layout.addWidget(self.add_service_input)
        account_layout.addWidget(username_label)
        account_layout.addWidget(self.add_username_input)
        account_layout.addWidget(password_label)
        account_layout.addWidget(self.add_password_input)
        account_layout.addWidget(confirm_label)
        account_layout.addWidget(self.add_confirm_password_input)
        account_layout.addWidget(show_password_cb)
        account_layout.addWidget(notes_label)
        account_layout.addWidget(self.add_notes_input)

        layout.addWidget(account_group)

        # Action buttons
        button_layout = QHBoxLayout()

        self.add_copy_btn = QPushButton('Copy Password')
        self.add_copy_btn.clicked.connect(self.copy_add_password)

        self.add_save_btn = QPushButton('Save Password')
        self.add_save_btn.setFont(QFont('Arial', 14, QFont.Bold))
        self.add_save_btn.clicked.connect(self.save_add_password)
        self.add_save_btn.setMinimumHeight(40)

        self.add_clear_btn = QPushButton('Clear All')
        self.add_clear_btn.clicked.connect(self.clear_add_form)

        button_layout.addWidget(self.add_copy_btn)
        button_layout.addWidget(self.add_save_btn)
        button_layout.addWidget(self.add_clear_btn)

        layout.addLayout(button_layout)
        layout.addStretch()

    def create_generator_tab(self):
        generator_tab = QWidget()
        self.tab_widget.addTab(generator_tab, "Generate Password")

        layout = QVBoxLayout(generator_tab)
        layout.setSpacing(20)

        title = QLabel('VaultFlow Password Manager')
        title.setFont(QFont('Arial', 20, QFont.Bold))
        title.setAlignment(Qt.AlignCenter)
        layout.addWidget(title)

        # Account Information for Generated Password
        account_group = QGroupBox('Account Information')
        account_layout = QVBoxLayout(account_group)

        service_label = QLabel('Website/Service Name:')
        self.gen_service_input = QLineEdit()
        self.gen_service_input.setPlaceholderText('e.g., gmail.com, facebook.com')

        username_label = QLabel('Username/Email:')
        self.gen_username_input = QLineEdit()
        self.gen_username_input.setPlaceholderText('e.g., john@example.com or username')

        notes_label = QLabel('Notes (optional):')
        self.gen_notes_input = QPlainTextEdit()
        self.gen_notes_input.setPlaceholderText('e.g., Work account, Personal email, Admin access...')
        self.gen_notes_input.setMaximumHeight(60)

        account_layout.addWidget(service_label)
        account_layout.addWidget(self.gen_service_input)
        account_layout.addWidget(username_label)
        account_layout.addWidget(self.gen_username_input)
        account_layout.addWidget(notes_label)
        account_layout.addWidget(self.gen_notes_input)
        layout.addWidget(account_group)

        # Generation Settings
        settings_group = QGroupBox('Password Settings')
        settings_layout = QVBoxLayout(settings_group)

        # Length
        length_layout = QHBoxLayout()
        length_label = QLabel('Password Length:')
        self.length_spinbox = QSpinBox()
        self.length_spinbox.setMinimum(1)
        self.length_spinbox.setMaximum(128)
        self.length_spinbox.setValue(12)

        length_layout.addWidget(length_label)
        length_layout.addWidget(self.length_spinbox)
        length_layout.addStretch()
        settings_layout.addLayout(length_layout)

        # Character Types
        self.lowercase_cb = QCheckBox('Include lowercase letters (a-z)')
        self.lowercase_cb.setChecked(True)
        self.uppercase_cb = QCheckBox('Include uppercase letters (A-Z)')
        self.uppercase_cb.setChecked(True)
        self.numbers_cb = QCheckBox('Include numbers (0-9)')
        self.numbers_cb.setChecked(True)
        self.symbols_cb = QCheckBox('Include symbols (!@#$%^&*)')
        self.symbols_cb.setChecked(True)

        settings_layout.addWidget(self.lowercase_cb)
        settings_layout.addWidget(self.uppercase_cb)
        settings_layout.addWidget(self.numbers_cb)
        settings_layout.addWidget(self.symbols_cb)

        layout.addWidget(settings_group)

        # Generate Button
        self.generate_btn = QPushButton('Generate Password')
        self.generate_btn.setFont(QFont('Arial', 16, QFont.Bold))
        self.generate_btn.clicked.connect(self.generate_password)
        self.generate_btn.setMinimumHeight(45)
        layout.addWidget(self.generate_btn)

        # Generated Password Display
        password_group = QGroupBox()
        password_layout = QVBoxLayout(password_group)

        self.password_display = QTextEdit()
        self.password_display.setMaximumHeight(80)
        self.password_display.setFont(QFont('Courier', 12))
        self.password_display.setReadOnly(True)
        self.password_display.setPlainText('Click "Generate Password" to create a new password')

        password_layout.addWidget(self.password_display)
        layout.addWidget(password_group)

        # Action buttons
        button_layout = QHBoxLayout()

        self.copy_generated_btn = QPushButton('Copy Password')
        self.copy_generated_btn.clicked.connect(self.copy_generated_password)
        self.copy_generated_btn.setEnabled(False)

        self.save_generated_btn = QPushButton('Save Password')
        self.save_generated_btn.setFont(QFont('Arial', 14, QFont.Bold))
        self.save_generated_btn.clicked.connect(self.save_generated_password)
        self.save_generated_btn.setEnabled(False)
        self.save_generated_btn.setMinimumHeight(40)

        self.clear_generated_btn = QPushButton('Clear All')
        self.clear_generated_btn.clicked.connect(self.clear_generator_form)

        button_layout.addWidget(self.copy_generated_btn)
        button_layout.addWidget(self.save_generated_btn)
        button_layout.addWidget(self.clear_generated_btn)

        layout.addLayout(button_layout)
        layout.addStretch()

    def create_manager_tab(self):
        manager_tab = QWidget()
        self.tab_widget.addTab(manager_tab, "Manage Passwords")

        layout = QVBoxLayout(manager_tab)

        title = QLabel('Saved Passwords')
        title.setFont(QFont('Arial', 16, QFont.Bold))
        title.setAlignment(Qt.AlignCenter)
        layout.addWidget(title)

        search_layout = QHBoxLayout()
        search_label = QLabel('Search:')
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText('Search by website, username, or notes...')
        self.search_input.textChanged.connect(self.filter_passwords)

        search_layout.addWidget(search_label)
        search_layout.addWidget(self.search_input)
        layout.addLayout(search_layout)

        self.password_table = QTableWidget()
        self.password_table.setColumnCount(6)
        self.password_table.setHorizontalHeaderLabels(['Website/Service', 'Username', 'Password', 'Notes', 'Created Date', 'Actions'])

        # Alternating row colors
        self.password_table.setAlternatingRowColors(True)
        self.password_table.setStyleSheet("alternate-background-color: #f5f5f5;")

        header = self.password_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Stretch)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.Stretch)
        header.setSectionResizeMode(4, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(5, QHeaderView.ResizeToContents)

        self.password_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.password_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.password_table.setVerticalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.password_table.setHorizontalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.password_table.setWordWrap(False)
        self.password_table.setAlternatingRowColors(True)
        self.password_table.verticalHeader().setDefaultSectionSize(32)

        layout.addWidget(self.password_table)

        button_layout = QHBoxLayout()

        self.refresh_btn = QPushButton('Refresh')
        self.refresh_btn.clicked.connect(self.refresh_password_list)

        self.delete_btn = QPushButton('Delete Selected')
        self.delete_btn.clicked.connect(self.delete_password)

        self.edit_btn = QPushButton('Edit Selected')
        self.edit_btn.clicked.connect(self.edit_selected_password)

        self.export_btn = QPushButton('Export All')
        self.export_btn.clicked.connect(self.export_passwords)

        button_layout.addWidget(self.refresh_btn)
        button_layout.addWidget(self.edit_btn)
        button_layout.addWidget(self.delete_btn)
        button_layout.addWidget(self.export_btn)
        button_layout.addStretch()

        layout.addLayout(button_layout)

    # Clipboard helpers
    def copy_to_clipboard_with_autoclear(self, text):
        clipboard = QApplication.clipboard()
        clipboard.setText(text)
        self._last_copied_value = text
        self.clipboard_timer.start(CLIPBOARD_CLEAR_SECONDS * 1000)

    def clear_clipboard_if_unchanged(self):
        clipboard = QApplication.clipboard()
        # Only clear it if the user hasn't already copied something else since.
        if clipboard.text() == self._last_copied_value:
            clipboard.clear()
        self._last_copied_value = None

    # Add Password Tab Methods
    def copy_add_password(self):
        password = self.add_password_input.text()
        if password:
            self.copy_to_clipboard_with_autoclear(password)
            QMessageBox.information(self, 'Success',
                                     f'Password copied to clipboard!\nIt will be cleared automatically in {CLIPBOARD_CLEAR_SECONDS} seconds.')
        else:
            QMessageBox.warning(self, 'Warning', 'No password to copy!')

    def save_add_password(self):
        password = self.add_password_input.text().strip()
        confirm_password = self.add_confirm_password_input.text().strip()
        service = self.add_service_input.text().strip()
        username = self.add_username_input.text().strip()
        notes = self.add_notes_input.toPlainText().strip()

        if not password:
            QMessageBox.warning(self, 'Warning', 'Please enter a password!')
            return
        if password != confirm_password:
            QMessageBox.warning(self, 'Warning', 'Passwords do not match!')
            return
        if not service:
            QMessageBox.warning(self, 'Warning', 'Please enter a website/service name!')
            return
        if not username:
            QMessageBox.warning(self, 'Warning', 'Please enter a username/email!')
            return

        if self.save_password_data(service, username, password, notes):
            self.clear_add_form()

    def clear_add_form(self):
        self.add_service_input.clear()
        self.add_username_input.clear()
        self.add_password_input.clear()
        self.add_confirm_password_input.clear()
        self.add_notes_input.clear()

    # Generator Tab Methods
    def generate_password(self):
        length = self.length_spinbox.value()
        chars = ""

        if self.lowercase_cb.isChecked():
            chars += string.ascii_lowercase
        if self.uppercase_cb.isChecked():
            chars += string.ascii_uppercase
        if self.numbers_cb.isChecked():
            chars += string.digits
        if self.symbols_cb.isChecked():
            chars += "!@#$%^&*()_+-=[]{}|;:,.<>?"

        if not chars:
            QMessageBox.warning(self, 'Warning', 'Please select at least one character type!')
            return

        # Use a cryptographically secure RNG for password generation.
        password = ''.join(random.SystemRandom().choice(chars) for _ in range(length))
        self.password_display.setPlainText(password)
        self.copy_generated_btn.setEnabled(True)
        self.save_generated_btn.setEnabled(True)

    def copy_generated_password(self):
        password = self.password_display.toPlainText()
        if password and password != 'Click "Generate Password" to create a new password':
            self.copy_to_clipboard_with_autoclear(password)
            QMessageBox.information(self, 'Success',
                                     f'Password copied to clipboard!\nIt will be cleared automatically in {CLIPBOARD_CLEAR_SECONDS} seconds.')

    def save_generated_password(self):
        password = self.password_display.toPlainText()
        service = self.gen_service_input.text().strip()
        username = self.gen_username_input.text().strip()
        notes = self.gen_notes_input.toPlainText().strip()

        if not password or password == 'Click "Generate Password" to create a new password':
            QMessageBox.warning(self, 'Warning', 'Please generate a password first!')
            return
        if not service:
            QMessageBox.warning(self, 'Warning', 'Please enter a website/service name!')
            return
        if not username:
            QMessageBox.warning(self, 'Warning', 'Please enter a username/email!')
            return

        if self.save_password_data(service, username, password, notes):
            self.clear_generator_form()

    def clear_generator_form(self):
        self.gen_service_input.clear()
        self.gen_username_input.clear()
        self.gen_notes_input.clear()
        self.password_display.setPlainText('Click "Generate Password" to create a new password')
        self.copy_generated_btn.setEnabled(False)
        self.save_generated_btn.setEnabled(False)

    # Shared Methods
    def save_password_data(self, service, username, password, notes):
        """Common method for saving password data from either tab"""

        # Create new account entry
        new_account = {
            'id': self.generate_account_id(),
            'username': username,
            'password': password,
            'notes': notes,
            'created_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'length': len(password)
        }

        # Check if service exists
        if service not in self.passwords_data:
            # Create new service entry
            self.passwords_data[service] = {
                'accounts': [new_account]
            }
            message = f'Password for "{service}" saved successfully!'
        else:
            # Check if username already exists for this service
            existing_usernames = [acc['username'] for acc in self.passwords_data[service]['accounts']]
            if username in existing_usernames:
                reply = QMessageBox.question(self, 'Username Exists',
                                           f'Username "{username}" already exists for "{service}". Add anyway?',
                                           QMessageBox.Yes | QMessageBox.No)
                if reply != QMessageBox.Yes:
                    return False

            # Add new account to existing service
            self.passwords_data[service]['accounts'].append(new_account)
            account_count = len(self.passwords_data[service]['accounts'])
            message = f'Password saved! "{service}" now has {account_count} accounts.'

        if self.save_passwords_to_file():
            QMessageBox.information(self, 'Success', message)
            self.refresh_password_list()
            return True
        return False

    def convert_old_format(self, data):
        """Convert old single-password format to new multi-password format"""
        new_format = {}
        for service, entry in data.items():
            # Check if it's already in new format (has 'accounts' key)
            if 'accounts' in entry:
                new_format[service] = entry
            else:
                # Convert old format to new format
                new_format[service] = {
                    'accounts': [{
                        'id': self.generate_account_id(),
                        'username': entry.get('username', ''),
                        'password': entry.get('password', ''),
                        'notes': '',
                        'created_date': entry.get('created_date', ''),
                        'length': entry.get('length', 0)
                    }]
                }
        return new_format

    def generate_account_id(self):
        """Generate unique ID for each account"""
        return datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:20]

    def save_passwords_to_file(self):
        try:
            passwords_file = getattr(self, 'passwords_file', None) or 'passwords.json'
            # Sort the passwords alphabetically by service name before saving
            sorted_passwords = dict(sorted(self.passwords_data.items(), key=lambda x: x[0].lower()))

            plaintext = json.dumps(sorted_passwords, indent=2).encode('utf-8')
            encrypted = self.fernet.encrypt(plaintext)
            payload = {
                'salt': base64.urlsafe_b64encode(self.salt).decode('utf-8'),
                'vault': encrypted.decode('utf-8'),
            }

            # Write to a temp file and atomically replace, keeping one rolling backup,
            # so a crash mid-save can't corrupt or lose the vault.
            tmp_file = passwords_file + '.tmp'
            with open(tmp_file, 'w') as f:
                json.dump(payload, f, indent=2)

            if os.path.exists(passwords_file):
                shutil.copy2(passwords_file, passwords_file + '.bak')

            os.replace(tmp_file, passwords_file)

            # Update the in-memory data to match the sorted version
            self.passwords_data = sorted_passwords
            return True
        except Exception as e:
            QMessageBox.critical(self, 'Error', f'Failed to save passwords: {str(e)}')
            return False

    def refresh_password_list(self):
        self.password_table.setUpdatesEnabled(False)

        # Count total accounts across all services
        total_accounts = sum(len(service_data['accounts']) for service_data in self.passwords_data.values())

        self.password_table.setRowCount(total_accounts)
        row = 0

        # Sort services alphabetically
        sorted_services = sorted(self.passwords_data.items(), key=lambda x: x[0].lower())

        for service, service_data in sorted_services:
            # Sort accounts by creation date (newest first)
            sorted_accounts = sorted(service_data['accounts'], key=lambda x: x.get('created_date', ''), reverse=True)

            for i, account in enumerate(sorted_accounts):
                # Service name (show only for first account of each service)
                if i == 0:
                    service_item = QTableWidgetItem(f"{service}")
                else:
                    service_item = QTableWidgetItem("")
                self.password_table.setItem(row, 0, service_item)

                # Username
                self.password_table.setItem(row, 1, QTableWidgetItem(account.get('username', '')))

                # Password (hidden)
                password_item = QTableWidgetItem('•' * len(account.get('password', '')))
                password_item.setData(Qt.UserRole, account.get('password', ''))
                password_item.setData(Qt.UserRole + 1, account['id'])  # Store account ID
                self.password_table.setItem(row, 2, password_item)

                # Notes (truncated if too long)
                notes = account.get('notes', '')
                display_notes = notes[:50] + "..." if len(notes) > 50 else notes
                notes_item = QTableWidgetItem(display_notes)
                notes_item.setToolTip(notes)  # Full notes on hover
                self.password_table.setItem(row, 3, notes_item)

                # Created date
                self.password_table.setItem(row, 4, QTableWidgetItem(account.get('created_date', '')))

                # Action buttons
                action_widget = QWidget()
                action_layout = QHBoxLayout(action_widget)
                action_layout.setContentsMargins(5, 2, 5, 2)

                show_btn = QPushButton('Show')
                show_btn.setMaximumWidth(50)
                show_btn.clicked.connect(lambda checked, acc_id=account['id']: self.toggle_password_visibility(acc_id, show_btn))

                copy_btn = QPushButton('Copy')
                copy_btn.setMaximumWidth(50)
                copy_btn.clicked.connect(lambda checked, pwd=account['password']: self.copy_specific_password(pwd))

                edit_btn = QPushButton('Edit')
                edit_btn.setMaximumWidth(50)
                edit_btn.clicked.connect(lambda checked, acc_id=account['id']: self.edit_account_details(acc_id))

                action_layout.addWidget(show_btn)
                action_layout.addWidget(copy_btn)
                action_layout.addWidget(edit_btn)
                action_layout.addStretch()
                self.password_table.setCellWidget(row, 5, action_widget)

                row += 1

        self.password_table.setUpdatesEnabled(True)

    def toggle_password_visibility(self, account_id, btn=None):
        # Find the row with this account ID
        target_row = None
        for r in range(self.password_table.rowCount()):
            password_item = self.password_table.item(r, 2)
            if password_item and password_item.data(Qt.UserRole + 1) == account_id:
                target_row = r
                break

        if target_row is None:
            return

        password_item = self.password_table.item(target_row, 2)
        actual_password = password_item.data(Qt.UserRole)
        current_text = password_item.text()

        if current_text.startswith('•'):
            password_item.setText(actual_password)
            # Update button text
            widget = self.password_table.cellWidget(target_row, 5)
            if widget:
                show_btn = widget.findChildren(QPushButton)[0]
                show_btn.setText('Hide')
        else:
            password_item.setText('•' * len(actual_password))
            # Update button text
            widget = self.password_table.cellWidget(target_row, 5)
            if widget:
                show_btn = widget.findChildren(QPushButton)[0]
                show_btn.setText('Show')

    def copy_specific_password(self, password):
        self.copy_to_clipboard_with_autoclear(password)
        QMessageBox.information(self, 'Success',
                                 f'Password copied to clipboard!\nIt will be cleared automatically in {CLIPBOARD_CLEAR_SECONDS} seconds.')

    def edit_selected_password(self):
        current_row = self.password_table.currentRow()
        if current_row < 0:
            QMessageBox.warning(self, 'Warning', 'Please select a password to edit!')
            return

        password_item = self.password_table.item(current_row, 2)
        if not password_item:
            return

        account_id = password_item.data(Qt.UserRole + 1)
        self.edit_account_details(account_id)

    def edit_account_details(self, account_id):
        account = None
        service_name = None

        for service, service_data in self.passwords_data.items():
            for candidate in service_data.get('accounts', []):
                if candidate.get('id') == account_id:
                    account = candidate
                    service_name = service
                    break
            if account is not None:
                break

        if account is None:
            QMessageBox.warning(self, 'Warning', 'The selected password entry could not be found.')
            return

        dialog = QDialog(self)
        dialog.setWindowTitle(f'Edit {service_name}')
        dialog.setMinimumWidth(420)

        dialog_layout = QVBoxLayout(dialog)
        form_layout = QFormLayout()

        username_input = QLineEdit(account.get('username', ''))
        password_input = QLineEdit(account.get('password', ''))
        password_input.setEchoMode(QLineEdit.Password)

        confirm_input = QLineEdit(account.get('password', ''))
        confirm_input.setEchoMode(QLineEdit.Password)

        notes_input = QPlainTextEdit()
        notes_input.setPlainText(account.get('notes', ''))
        notes_input.setMaximumHeight(100)

        show_password_cb = QCheckBox('Show password')
        show_password_cb.toggled.connect(
            lambda checked: (
                password_input.setEchoMode(QLineEdit.Normal if checked else QLineEdit.Password),
                confirm_input.setEchoMode(QLineEdit.Normal if checked else QLineEdit.Password)
            )
        )

        form_layout.addRow('Username/Email:', username_input)
        form_layout.addRow('Password:', password_input)
        form_layout.addRow('Confirm Password:', confirm_input)
        form_layout.addRow('', show_password_cb)
        form_layout.addRow('Notes:', notes_input)

        dialog_layout.addLayout(form_layout)

        button_box = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        button_box.accepted.connect(dialog.accept)
        button_box.rejected.connect(dialog.reject)
        dialog_layout.addWidget(button_box)

        if dialog.exec_():
            username = username_input.text().strip()
            password = password_input.text().strip()
            confirm_password = confirm_input.text().strip()
            notes = notes_input.toPlainText().strip()

            if not username:
                QMessageBox.warning(self, 'Warning', 'Please enter a username/email!')
                return
            if not password:
                QMessageBox.warning(self, 'Warning', 'Please enter a password!')
                return
            if password != confirm_password:
                QMessageBox.warning(self, 'Warning', 'Passwords do not match!')
                return

            if self.update_account_details(account_id, username, password, notes):
                QMessageBox.information(self, 'Success', 'Account updated successfully!')

    def update_account_details(self, account_id, username, password, notes):
        for service, service_data in self.passwords_data.items():
            for account in service_data.get('accounts', []):
                if account.get('id') == account_id:
                    account['username'] = username
                    account['password'] = password
                    account['notes'] = notes
                    account['length'] = len(password)
                    if self.save_passwords_to_file():
                        self.refresh_password_list()
                        return True
                    return False
        return False

    def filter_passwords(self):
        search_text = self.search_input.text().lower()
        for row in range(self.password_table.rowCount()):
            # Check service name, username, and notes
            service_item = self.password_table.item(row, 0)
            username_item = self.password_table.item(row, 1)
            notes_item = self.password_table.item(row, 3)

            should_show = False
            if service_item and search_text in service_item.text().lower():
                should_show = True
            elif username_item and search_text in username_item.text().lower():
                should_show = True
            elif notes_item and search_text in notes_item.text().lower():
                should_show = True

            self.password_table.setRowHidden(row, not should_show)

    def delete_password(self):
        current_row = self.password_table.currentRow()
        if current_row < 0:
            QMessageBox.warning(self, 'Warning', 'Please select a password to delete!')
            return

        # Get account ID from the password item
        password_item = self.password_table.item(current_row, 2)
        if not password_item:
            return

        account_id = password_item.data(Qt.UserRole + 1)
        username_item = self.password_table.item(current_row, 1)
        username = username_item.text() if username_item else "Unknown"

        reply = QMessageBox.question(self, 'Confirm Delete',
                                   f'Are you sure you want to delete the account "{username}"?',
                                   QMessageBox.Yes | QMessageBox.No)

        if reply != QMessageBox.Yes:
            return

        # Find and remove the account
        service_to_remove = None
        for service, service_data in self.passwords_data.items():
            service_data['accounts'] = [acc for acc in service_data['accounts'] if acc['id'] != account_id]

            # If no accounts left, mark service for removal
            if not service_data['accounts']:
                service_to_remove = service
                break

        # Remove empty service
        if service_to_remove:
            del self.passwords_data[service_to_remove]
            message = f'Last account deleted. Service "{service_to_remove}" removed.'
        else:
            message = f'Account "{username}" deleted successfully!'

        if self.save_passwords_to_file():
            QMessageBox.information(self, 'Success', message)
            self.refresh_password_list()

    def export_passwords(self):
        if not self.passwords_data:
            QMessageBox.information(self, 'Info', 'No passwords to export!')
            return

        reply = QMessageBox.question(self, 'Confirm Export',
                                   'This will copy every saved password, in plain text, to your clipboard.\n\n'
                                   'Continue?',
                                   QMessageBox.Yes | QMessageBox.No)
        if reply != QMessageBox.Yes:
            return

        export_text = "Password Export\n" + "="*60 + "\n\n"

        # Sort services alphabetically
        sorted_services = sorted(self.passwords_data.items(), key=lambda x: x[0].lower())

        for service, service_data in sorted_services:
            export_text += f"🌐 Website/Service: {service}\n"
            export_text += f"   Number of accounts: {len(service_data['accounts'])}\n"
            export_text += "-" * 40 + "\n"

            for i, account in enumerate(service_data['accounts'], 1):
                export_text += f"  Account #{i}:\n"
                export_text += f"    Username: {account['username']}\n"
                export_text += f"    Password: {account['password']}\n"
                if account.get('notes'):
                    export_text += f"    Notes: {account['notes']}\n"
                export_text += f"    Created: {account['created_date']}\n"
                export_text += f"    Length: {account['length']} characters\n\n"

            export_text += "=" * 60 + "\n\n"

        clipboard = QApplication.clipboard()
        clipboard.setText(export_text)
        QMessageBox.information(self, 'Success',
                              'All passwords exported to clipboard!\n\n'
                              'WARNING: This contains plain text passwords. Handle with care, '
                              'and clear your clipboard once you\'re done pasting it.')

def main():
    app = QApplication(sys.argv)
    app.setApplicationName('VaultFlow')
    app.setApplicationDisplayName('VaultFlow')
    app.setStyle('Fusion')

    # Light Fusion theme
    palette = QPalette()
    palette.setColor(QPalette.Window, QColor(240, 240, 240))
    palette.setColor(QPalette.WindowText, Qt.black)
    palette.setColor(QPalette.Base, QColor(255, 255, 255))
    palette.setColor(QPalette.AlternateBase, QColor(245, 245, 245))
    palette.setColor(QPalette.ToolTipBase, Qt.black)
    palette.setColor(QPalette.ToolTipText, Qt.white)
    palette.setColor(QPalette.Text, Qt.black)
    palette.setColor(QPalette.Button, QColor(240, 240, 240))
    palette.setColor(QPalette.ButtonText, Qt.black)
    palette.setColor(QPalette.BrightText, Qt.red)
    palette.setColor(QPalette.Highlight, QColor(51, 153, 255))
    palette.setColor(QPalette.HighlightedText, Qt.white)
    app.setPalette(palette)

    passwords_file = user_password
    data, fernet, salt = unlock_vault(passwords_file)

    window = PasswordManager(data, fernet, salt, passwords_file)
    window.show()

    sys.exit(app.exec_())

if __name__ == '__main__':
    main()
    