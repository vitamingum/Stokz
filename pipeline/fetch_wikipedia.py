#!/usr/bin/env python3
"""
Step 2: Fetch Wikipedia content for each company
"""
import json
import wikipediaapi
from pathlib import Path
from tqdm import tqdm
import time

DATA_DIR = Path(__file__).parent / "data"

def load_stocks():
    with open(DATA_DIR / "sp500_stocks.json") as f:
        return json.load(f)

def fetch_wikipedia_content(stocks):
    """Fetch Wikipedia page content for each company"""
    wiki = wikipediaapi.Wikipedia(
        user_agent='StokzApp/1.0 (charlesburns@example.com)',
        language='en'
    )
    
    results = []
    failed = []
    
    print(f"📥 Fetching Wikipedia content for {len(stocks)} companies...")
    
    for stock in tqdm(stocks):
        ticker = stock['ticker']
        company = stock['company']
        wiki_title = stock['wiki_title']
        
        # Try different title variations
        titles_to_try = [
            wiki_title,
            company,
            f"{company} (company)",
            f"{wiki_title} (company)",
        ]
        
        page = None
        for title in titles_to_try:
            page = wiki.page(title)
            if page.exists():
                break
        
        if page and page.exists():
            # Get first 2000 chars of summary (enough for LLM context)
            summary = page.summary[:2000] if page.summary else ""
            
            results.append({
                **stock,
                'wiki_page': page.title,
                'wiki_summary': summary,
                'wiki_url': page.fullurl
            })
        else:
            failed.append(stock)
            results.append({
                **stock,
                'wiki_page': None,
                'wiki_summary': f"{company} is a company in the {stock['sector']} sector.",
                'wiki_url': None
            })
        
        # Be nice to Wikipedia
        time.sleep(0.1)
    
    print(f"✅ Fetched {len(results) - len(failed)} pages")
    if failed:
        print(f"⚠️  Failed to find {len(failed)} pages:")
        for f in failed[:10]:
            print(f"    - {f['ticker']}: {f['company']}")
    
    return results

def save_results(results):
    output_file = DATA_DIR / "sp500_with_wiki.json"
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"💾 Saved to {output_file}")

if __name__ == "__main__":
    stocks = load_stocks()
    results = fetch_wikipedia_content(stocks)
    save_results(results)
    
    # Show sample
    print("\n📊 Sample entry:")
    sample = results[0]
    print(f"  Ticker: {sample['ticker']}")
    print(f"  Company: {sample['company']}")
    print(f"  Wiki: {sample.get('wiki_page', 'N/A')}")
    print(f"  Summary: {sample['wiki_summary'][:200]}...")
