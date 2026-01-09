#!/usr/bin/env python3
"""
Step 1: Fetch S&P 500 tickers and company names
"""
import requests
import pandas as pd
import json
from pathlib import Path
from io import StringIO

OUTPUT_DIR = Path(__file__).parent / "data"
OUTPUT_DIR.mkdir(exist_ok=True)

def fetch_sp500_from_wikipedia():
    """Fetch S&P 500 list from Wikipedia"""
    url = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"
    
    print("📥 Fetching S&P 500 list from Wikipedia...")
    
    # Use requests with proper headers
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) StokzApp/1.0'
    }
    response = requests.get(url, headers=headers)
    response.raise_for_status()
    
    tables = pd.read_html(StringIO(response.text))
    df = tables[0]  # First table is the current S&P 500
    
    # Clean up columns
    stocks = []
    for _, row in df.iterrows():
        ticker = row['Symbol'].replace('.', '-')  # BRK.B -> BRK-B
        company = row['Security']
        sector = row['GICS Sector']
        sub_industry = row['GICS Sub-Industry']
        
        # Wikipedia page title (usually company name)
        wiki_title = company
        # Handle special cases
        if 'Inc.' in wiki_title:
            wiki_title = wiki_title.replace(' Inc.', '')
        if 'Corp.' in wiki_title:
            wiki_title = wiki_title.replace(' Corp.', '')
            
        stocks.append({
            'ticker': ticker,
            'company': company,
            'sector': sector,
            'sub_industry': sub_industry,
            'wiki_title': wiki_title
        })
    
    print(f"✅ Found {len(stocks)} companies")
    return stocks

def save_stocks(stocks):
    """Save to JSON"""
    output_file = OUTPUT_DIR / "sp500_stocks.json"
    with open(output_file, 'w') as f:
        json.dump(stocks, f, indent=2)
    print(f"💾 Saved to {output_file}")
    
    # Also save a simple ticker list
    tickers_file = OUTPUT_DIR / "tickers.txt"
    with open(tickers_file, 'w') as f:
        for s in stocks:
            f.write(f"{s['ticker']}\n")
    print(f"💾 Saved ticker list to {tickers_file}")

if __name__ == "__main__":
    stocks = fetch_sp500_from_wikipedia()
    save_stocks(stocks)
    
    # Show sample
    print("\n📊 Sample entries:")
    for s in stocks[:5]:
        print(f"  {s['ticker']:6} | {s['company'][:30]:30} | {s['sector']}")
