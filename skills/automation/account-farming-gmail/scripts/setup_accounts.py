#!/usr/bin/env python3
"""
Setup helper: Interactive input untuk accounts.txt
Jalankan: python3 scripts/setup_accounts.py
"""

from pathlib import Path

ACCOUNTS_FILE = Path("/home/runner/gmail_warming/accounts/accounts.txt")

def main():
    print("=" * 60)
    print("📝 SETUP ACCOUNTS.TXT - GMAIL WARMING")
    print("=" * 60)
    print("Format: email password (satu per baris)")
    print("Contoh: contoh1@gmail.com hehe1122")
    print("Gunakan App Password jika 2FA aktif!")
    print("Ketik 'selesai' untuk finish")
    print("-" * 60)
    
    accounts = []
    count = 1
    
    while True:
        email = input(f"Email #{count}: ").strip()
        if email.lower() == 'selesai':
            break
        if not email or '@' not in email:
            print("❌ Email tidak valid!")
            continue
            
        password = input(f"Password/App Password #{count}: ").strip()
        if not password:
            print("❌ Password tidak boleh kosong!")
            continue
        
        accounts.append(f"{email} {password}")
        print(f"✅ Ditambahkan: {email}")
        count += 1
        print()
    
    if accounts:
        with open(ACCOUNTS_FILE, 'w') as f:
            f.write('\n'.join(accounts) + '\n')
        print(f"\n✅ Berhasil simpan {len(accounts)} akun ke:")
        print(f"   {ACCOUNTS_FILE}")
        
        # Show summary
        print("\n📋 Ringkasan:")
        for i, acc in enumerate(accounts, 1):
            email = acc.split()[0]
            print(f"   {i}. {email}")
    else:
        print("\n⚠️ Tidak ada akun yang ditambahkan.")

if __name__ == "__main__":
    main()