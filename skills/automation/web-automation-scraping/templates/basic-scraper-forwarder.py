import requests
from bs4 import BeautifulSoup
import time

# --- CONFIGURATION ---
TARGET_URL = "https://example.com"
SENDER_API_URL = "https://api.telegram.org/bot<TOKEN>/sendMessage"
SENDER_CHAT_ID = "CHAT_ID"

session = requests.Session()

def forward_data(text):
    payload = {"chat_id": SENDER_CHAT_ID, "text": text}
    requests.post(SENDER_API_URL, data=payload)

def scrape_and_forward():
    try:
        response = session.get(TARGET_URL, timeout=15)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Replace with actual selector
        elements = soup.find_all('div', class_='data-field')
        for el in elements:
            data = el.text.strip()
            forward_data(f"Update: {data}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    while True:
        scrape_and_forward()
        time.sleep(60)
