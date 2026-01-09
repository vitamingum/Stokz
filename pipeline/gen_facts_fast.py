#!/usr/bin/env python3
"""
Fast fact card generation using smaller model.
Qwen2.5-1.5B is ~4x faster than 7B with decent quality.
"""

import json
import sys
import time
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
INPUT_FILE = DATA_DIR / "sp500_with_wiki.json"
OUTPUT_FILE = DATA_DIR / "stock_facts.json"

# Use smaller, faster model
MODEL_NAME = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

def create_prompt(stock: dict) -> str:
    wiki = stock.get("wiki_summary", "")[:1500]
    return f"""Create a JSON fact card for {stock['company']} ({stock['ticker']}).

Info: {wiki[:800]}

Return JSON with: summary (2 sentences, max 200 chars), industry, tags (3-5 keywords), founded (year or null), headquarters (city or null).
JSON only:"""

def main():
    print("=" * 50)
    print("FAST STOCK FACT GENERATOR")
    print("=" * 50)
    
    with open(INPUT_FILE) as f:
        stocks = json.load(f)
    
    stocks_with_wiki = [s for s in stocks if s.get("wiki_summary")]
    print(f"Stocks: {len(stocks_with_wiki)}")
    
    existing = {}
    if OUTPUT_FILE.exists():
        with open(OUTPUT_FILE) as f:
            existing = json.load(f)
        print(f"Resuming from {len(existing)}")
    
    print(f"Loading {MODEL_NAME}...")
    from mlx_lm import load, generate
    model, tokenizer = load(MODEL_NAME)
    print("Ready!")
    print("-" * 50)
    
    facts = existing.copy()
    done = 0
    errors = 0
    start = time.time()
    
    for i, stock in enumerate(stocks_with_wiki):
        ticker = stock["ticker"]
        if ticker in facts:
            continue
        
        print(f"[{i+1:3d}/{len(stocks_with_wiki)}] {ticker:6s}", end=" ", flush=True)
        
        try:
            t0 = time.time()
            resp = generate(model, tokenizer, prompt=create_prompt(stock), max_tokens=250, verbose=False)
            dt = time.time() - t0
            
            # Better JSON extraction - find first complete JSON object
            s = resp.find("{")
            if s >= 0:
                # Count braces to find matching close
                depth = 0
                e = s
                for i, c in enumerate(resp[s:], s):
                    if c == '{': depth += 1
                    elif c == '}': depth -= 1
                    if depth == 0:
                        e = i + 1
                        break
                
                json_str = resp[s:e]
                data = json.loads(json_str)
                facts[ticker] = {"ticker": ticker, "company": stock["company"], 
                                "sector": stock.get("sector",""), **data}
                ind = data.get('industry', '?')[:15]
                print(f"✓ {ind:15s} ({dt:.1f}s)")
                done += 1
            else:
                print(f"✗ no JSON")
                errors += 1
        except Exception as e:
            print(f"✗ {str(e)[:30]}")
            errors += 1
        
        if done % 20 == 0 and done > 0:
            with open(OUTPUT_FILE, "w") as f:
                json.dump(facts, f, indent=2)
            elapsed = time.time() - start
            rate = done / elapsed
            remaining = (len(stocks_with_wiki) - i) / rate / 60
            print(f"    >>> Saved {len(facts)} | ETA {remaining:.0f}min <<<")
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(facts, f, indent=2)
    
    print("-" * 50)
    print(f"Done: {done} facts, {errors} errors in {(time.time()-start)/60:.1f}min")

if __name__ == "__main__":
    main()
