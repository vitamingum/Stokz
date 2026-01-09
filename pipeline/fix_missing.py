#!/usr/bin/env python3
"""
Regenerate missing/empty fact summaries.
"""

import json
import time
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
FACTS_FILE = DATA_DIR / "stock_facts_normalized.json"
WIKI_FILE = DATA_DIR / "sp500_with_wiki.json"

MODEL_NAME = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

def create_prompt(stock: dict) -> str:
    wiki = stock.get("wiki_summary", "")[:1500]
    company = stock.get("company", stock.get("ticker", "Unknown"))
    return f"""Create a JSON fact card for {company} ({stock['ticker']}).

Info: {wiki[:1000]}

Return ONLY valid JSON with these fields:
- summary: 2 engaging sentences about the company, max 200 chars
- industry: one word category
- tags: list of 3-5 keywords
- founded: year as number or null
- headquarters: city name or null

JSON:"""

def main():
    print("=" * 50)
    print("FIX MISSING SUMMARIES")
    print("=" * 50)
    
    with open(FACTS_FILE) as f:
        facts = json.load(f)
    
    with open(WIKI_FILE) as f:
        stocks = json.load(f)
    
    # Find stocks with wiki data
    wiki_lookup = {s["ticker"]: s for s in stocks if s.get("wiki_summary")}
    
    # Find missing
    missing = []
    for ticker, data in facts.items():
        summary = data.get("summary", "")
        if not summary or len(summary) < 30:
            if ticker in wiki_lookup:
                missing.append((ticker, wiki_lookup[ticker]))
    
    print(f"Missing summaries: {len(missing)}")
    
    if not missing:
        print("Nothing to fix!")
        return
    
    print(f"Loading {MODEL_NAME}...")
    from mlx_lm import load, generate
    model, tokenizer = load(MODEL_NAME)
    print("Ready!")
    print("-" * 50)
    
    fixed = 0
    errors = 0
    
    for ticker, stock in missing:
        print(f"{ticker:6s}", end=" ", flush=True)
        
        try:
            t0 = time.time()
            resp = generate(model, tokenizer, prompt=create_prompt(stock), max_tokens=300, verbose=False)
            dt = time.time() - t0
            
            # Extract JSON
            s = resp.find("{")
            if s >= 0:
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
                
                # Update
                facts[ticker]["summary"] = data.get("summary", "")
                facts[ticker]["tags"] = data.get("tags", [])
                facts[ticker]["industry"] = data.get("industry", "")
                facts[ticker]["founded"] = data.get("founded")
                facts[ticker]["headquarters"] = data.get("headquarters")
                
                print(f"✓ {data.get('summary', '')[:50]}... ({dt:.1f}s)")
                fixed += 1
            else:
                print(f"✗ no JSON")
                errors += 1
        except Exception as e:
            print(f"✗ {str(e)[:30]}")
            errors += 1
    
    # Save
    with open(FACTS_FILE, "w") as f:
        json.dump(facts, f, indent=2)
    
    print("-" * 50)
    print(f"Fixed: {fixed}, Errors: {errors}")

if __name__ == "__main__":
    main()
