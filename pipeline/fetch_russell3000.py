#!/usr/bin/env python3
"""
Fetch Russell 3000 tickers from Wikipedia and other sources.
Russell 3000 = Russell 1000 (large cap) + Russell 2000 (small cap)
"""
import requests
import pandas as pd
import json
import time
from pathlib import Path
from io import StringIO

OUTPUT_DIR = Path(__file__).parent / "data"
OUTPUT_DIR.mkdir(exist_ok=True)

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) StokzApp/1.0'
}

def fetch_russell_1000():
    """Fetch Russell 1000 from Wikipedia"""
    url = "https://en.wikipedia.org/wiki/Russell_1000_Index"
    
    print("📥 Fetching Russell 1000 from Wikipedia...")
    
    response = requests.get(url, headers=HEADERS)
    response.raise_for_status()
    
    tables = pd.read_html(StringIO(response.text))
    
    stocks = []
    # Find the table with stock tickers (usually has 'Ticker' or 'Symbol' column)
    for table in tables:
        if 'Ticker' in table.columns or 'Symbol' in table.columns or 'Ticker symbol' in table.columns:
            ticker_col = 'Ticker' if 'Ticker' in table.columns else ('Symbol' if 'Symbol' in table.columns else 'Ticker symbol')
            company_col = 'Company' if 'Company' in table.columns else 'Security'
            
            for _, row in table.iterrows():
                try:
                    ticker = str(row[ticker_col]).strip().replace('.', '-')
                    company = str(row[company_col]).strip() if company_col in table.columns else ticker
                    
                    if ticker and ticker != 'nan' and len(ticker) <= 5:
                        stocks.append({
                            'ticker': ticker,
                            'company': company,
                            'source': 'russell_1000'
                        })
                except:
                    continue
    
    print(f"✅ Found {len(stocks)} Russell 1000 stocks")
    return stocks

def fetch_russell_2000():
    """
    Russell 2000 isn't fully on Wikipedia - we'll use NASDAQ's screener
    to get small cap stocks not in Russell 1000
    """
    print("📥 Fetching additional small caps from NASDAQ...")
    
    # NASDAQ provides a CSV of all listed stocks
    url = "https://api.nasdaq.com/api/screener/stocks?tableonly=true&limit=5000&marketcap=small|micro"
    
    try:
        response = requests.get(url, headers={
            **HEADERS,
            'Accept': 'application/json'
        })
        data = response.json()
        
        stocks = []
        if 'data' in data and 'rows' in data['data']:
            for row in data['data']['rows']:
                ticker = row.get('symbol', '').replace('.', '-')
                company = row.get('name', ticker)
                
                if ticker and len(ticker) <= 5:
                    stocks.append({
                        'ticker': ticker,
                        'company': company,
                        'source': 'nasdaq_smallcap'
                    })
        
        print(f"✅ Found {len(stocks)} NASDAQ small caps")
        return stocks
    except Exception as e:
        print(f"⚠️ NASDAQ API failed: {e}")
        return []

def fetch_sp500_existing():
    """Load existing S&P 500 data if available"""
    sp500_file = OUTPUT_DIR / "sp500_stocks.json"
    if sp500_file.exists():
        with open(sp500_file) as f:
            data = json.load(f)
        print(f"📂 Loaded {len(data)} existing S&P 500 stocks")
        return data
    return []

def fetch_from_slickcharts():
    """Fetch Russell 3000 approximation from slickcharts (has good lists)"""
    stocks = []
    
    # Try to get Russell 1000 components
    try:
        print("📥 Trying slickcharts Russell 1000...")
        url = "https://www.slickcharts.com/russell1000"
        response = requests.get(url, headers=HEADERS, timeout=10)
        
        if response.ok:
            tables = pd.read_html(StringIO(response.text))
            for table in tables:
                if 'Symbol' in table.columns:
                    for _, row in table.iterrows():
                        ticker = str(row['Symbol']).strip().replace('.', '-')
                        company = str(row.get('Company', ticker))
                        if ticker and ticker != 'nan' and len(ticker) <= 5:
                            stocks.append({
                                'ticker': ticker,
                                'company': company,
                                'source': 'slickcharts_r1000'
                            })
            print(f"✅ Found {len(stocks)} from slickcharts")
    except Exception as e:
        print(f"⚠️ Slickcharts failed: {e}")
    
    return stocks

def merge_and_dedupe(all_lists):
    """Merge all stock lists and remove duplicates"""
    seen = set()
    unique = []
    
    for stock_list in all_lists:
        for stock in stock_list:
            ticker = stock['ticker'].upper()
            if ticker not in seen and ticker and len(ticker) <= 5:
                seen.add(ticker)
                unique.append({
                    'ticker': ticker,
                    'company': stock.get('company', ticker),
                    'sector': stock.get('sector', ''),
                    'sub_industry': stock.get('sub_industry', ''),
                    'source': stock.get('source', 'unknown')
                })
    
    return unique

def save_stocks(stocks, filename="russell3000_stocks.json"):
    """Save to JSON"""
    output_file = OUTPUT_DIR / filename
    with open(output_file, 'w') as f:
        json.dump(stocks, f, indent=2)
    print(f"💾 Saved {len(stocks)} stocks to {output_file}")
    
    # Also save a simple ticker list
    tickers_file = OUTPUT_DIR / "russell3000_tickers.txt"
    with open(tickers_file, 'w') as f:
        for s in stocks:
            f.write(f"{s['ticker']}\n")
    print(f"💾 Saved ticker list to {tickers_file}")

if __name__ == "__main__":
    print("🚀 Fetching Russell 3000 stocks...\n")
    
    # Gather from multiple sources
    all_stocks = []
    
    # 1. Existing S&P 500 (already have good data)
    sp500 = fetch_sp500_existing()
    all_stocks.append(sp500)
    
    # 2. Russell 1000 from Wikipedia
    time.sleep(1)
    r1000 = fetch_russell_1000()
    all_stocks.append(r1000)
    
    # 3. Try slickcharts for more comprehensive list
    time.sleep(1)
    slick = fetch_from_slickcharts()
    all_stocks.append(slick)
    
    # 4. NASDAQ small caps (Russell 2000 proxy)
    time.sleep(1)
    small_caps = fetch_russell_2000()
    all_stocks.append(small_caps)
    
    # Merge and dedupe
    print("\n🔄 Merging and deduplicating...")
    merged = merge_and_dedupe(all_stocks)
    
    # Sort by ticker
    merged.sort(key=lambda x: x['ticker'])
    
    save_stocks(merged)
    
    # Show stats
    print(f"\n📊 Final count: {len(merged)} unique stocks")
    print("\n📊 Sample entries:")
    for s in merged[:10]:
        print(f"  {s['ticker']:6} | {s['company'][:35]:35} | {s['source']}")
    
    # Show source breakdown
    sources = {}
    for s in merged:
        src = s['source']
        sources[src] = sources.get(src, 0) + 1
    print("\n📊 By source:")
    for src, count in sorted(sources.items(), key=lambda x: -x[1]):
        print(f"  {src}: {count}")
