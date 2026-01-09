#!/usr/bin/env python3
"""
Generate fact cards for stocks using local LLM (MLX).
With progress output and resumability.
"""

import json
import sys
import time
from pathlib import Path

# Paths
DATA_DIR = Path(__file__).parent / "data"
INPUT_FILE = DATA_DIR / "sp500_with_wiki.json"
OUTPUT_FILE = DATA_DIR / "stock_facts.json"

# Model config  
MODEL_NAME = "mlx-community/Qwen2.5-7B-Instruct-4bit"

def create_prompt(stock: dict) -> str:
    """Create a prompt for the LLM to generate a fact card."""
    wiki = stock.get("wiki_summary", "")[:2000]
    
    return f"""Based on this Wikipedia summary, create a concise fact card for {stock['company']} ({stock['ticker']}).

Wikipedia: {wiki}

Generate a JSON object with these fields:
- summary: 2-3 sentence company description (max 300 chars)
- industry: primary industry category  
- tags: array of 3-5 relevant tags (e.g., "tech", "healthcare", "dividend", "growth")
- founded: year founded (if known, else null)
- headquarters: city, state/country (if known, else null)

Return ONLY valid JSON, no markdown or explanation."""

def main():
    print("=" * 60, flush=True)
    print("STOCK FACT GENERATOR", flush=True)
    print("=" * 60, flush=True)
    
    print("\n[1/3] Loading stock data...", flush=True)
    with open(INPUT_FILE) as f:
        stocks = json.load(f)
    
    stocks_with_wiki = [s for s in stocks if s.get("wiki_summary")]
    print(f"      Found {len(stocks)} stocks, {len(stocks_with_wiki)} have Wikipedia data", flush=True)
    
    # Load existing facts to resume
    existing_facts = {}
    if OUTPUT_FILE.exists():
        with open(OUTPUT_FILE) as f:
            existing_facts = json.load(f)
        print(f"      Resuming from {len(existing_facts)} existing facts", flush=True)
    
    print(f"\n[2/3] Loading model: {MODEL_NAME}", flush=True)
    print("      This may take a few minutes on first run (downloading ~5GB)...", flush=True)
    sys.stdout.flush()
    
    from mlx_lm import load, generate
    
    start_load = time.time()
    model, tokenizer = load(MODEL_NAME)
    print(f"      Model loaded in {time.time() - start_load:.1f}s", flush=True)
    
    print(f"\n[3/3] Generating fact cards...", flush=True)
    print("-" * 60, flush=True)
    
    facts = existing_facts.copy()
    processed = 0
    skipped = 0
    errors = 0
    start_time = time.time()
    
    for i, stock in enumerate(stocks_with_wiki):
        ticker = stock["ticker"]
        
        # Skip if already processed
        if ticker in facts:
            skipped += 1
            continue
        
        elapsed = time.time() - start_time
        rate = processed / elapsed if elapsed > 0 and processed > 0 else 0
        remaining = (len(stocks_with_wiki) - i) / rate if rate > 0 else 0
        
        print(f"[{i+1:3d}/{len(stocks_with_wiki)}] {ticker:6s} ", end="", flush=True)
        
        try:
            prompt = create_prompt(stock)
            
            gen_start = time.time()
            response = generate(
                model,
                tokenizer,
                prompt=prompt,
                max_tokens=400,
                verbose=False,
            )
            gen_time = time.time() - gen_start
            
            # Parse JSON from response
            start = response.find("{")
            end = response.rfind("}") + 1
            if start >= 0 and end > start:
                fact_data = json.loads(response[start:end])
                facts[ticker] = {
                    "ticker": ticker,
                    "company": stock["company"],
                    "sector": stock.get("sector", ""),
                    "sub_industry": stock.get("sub_industry", ""),
                    **fact_data
                }
                industry = fact_data.get('industry', 'Unknown')[:20]
                print(f"✓ {industry:20s} ({gen_time:.1f}s)", flush=True)
                processed += 1
            else:
                print(f"✗ No JSON in response", flush=True)
                errors += 1
                
        except json.JSONDecodeError as e:
            print(f"✗ JSON parse error", flush=True)
            errors += 1
        except Exception as e:
            print(f"✗ {str(e)[:40]}", flush=True)
            errors += 1
        
        # Save progress every 10 stocks
        if processed > 0 and processed % 10 == 0:
            with open(OUTPUT_FILE, "w") as f:
                json.dump(facts, f, indent=2)
            eta_min = remaining / 60
            print(f"      --- Saved {len(facts)} facts | ETA: {eta_min:.0f}min ---", flush=True)
    
    # Final save
    with open(OUTPUT_FILE, "w") as f:
        json.dump(facts, f, indent=2)
    
    total_time = time.time() - start_time
    print("-" * 60, flush=True)
    print(f"\nDONE!", flush=True)
    print(f"  Processed: {processed}", flush=True)
    print(f"  Skipped:   {skipped}", flush=True)  
    print(f"  Errors:    {errors}", flush=True)
    print(f"  Total:     {len(facts)} fact cards", flush=True)
    print(f"  Time:      {total_time/60:.1f} minutes", flush=True)
    print(f"  Output:    {OUTPUT_FILE}", flush=True)

if __name__ == "__main__":
    main()
