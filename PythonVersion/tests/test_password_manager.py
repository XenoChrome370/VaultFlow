from main import PasswordManager


def test_update_account_details_changes_account_fields():
    manager = PasswordManager.__new__(PasswordManager)
    manager.passwords_data = {
        "example.com": {
            "accounts": [
                {
                    "id": "acc1",
                    "username": "olduser",
                    "password": "oldpass",
                    "notes": "old note",
                    "created_date": "2024-01-01 00:00:00",
                    "length": 7,
                }
            ]
        }
    }

    updated = manager.update_account_details("acc1", "newuser", "newpass", "new note")

    assert updated is True
    account = manager.passwords_data["example.com"]["accounts"][0]
    assert account["username"] == "newuser"
    assert account["password"] == "newpass"
    assert account["notes"] == "new note"
    assert account["length"] == 7
