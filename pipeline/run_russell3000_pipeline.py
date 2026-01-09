#!/usr/bin/env python3
"""
Russell 3000 Pipeline - Fetch Wikipedia, Generate Facts, Create Embeddings
Run this to generate stock_data_bundle.json for ~1000+ stocks

Usage:
    python3 run_russell3000_pipeline.py [--skip-wiki] [--skip-facts]
"""

import json
import time
import sys
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

INPUT_FILE = DATA_DIR / "russell3000_stocks.json"
WIKI_FILE = DATA_DIR / "russell3000_with_wiki.json"
FACTS_FILE = DATA_DIR / "russell3000_facts.json"
BUNDLE_FILE = Path(__file__).parent.parent / "Stokz" / "stock_data_bundle.json"

# Use fast model
MODEL_NAME = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

def step1_fetch_wikipedia():
    """Fetch Wikipedia content for all stocks"""
    print("\n" + "="*60)
    print("STEP 1: Fetching Wikipedia content")
    print("="*60)
    
    import wikipediaapi
    from tqdm import tqdm
    
    with open(INPUT_FILE) as f:
        stocks = json.load(f)
    
    # Check for existing progress
    if WIKI_FILE.exists():
        with open(WIKI_FILE) as f:
            existing = json.load(f)
        existing_tickers = {s['ticker'] for s in existing}
        stocks = [s for s in stocks if s['ticker'] not in existing_tickers]
        print(f"📂 Found {len(existing)} existing, {len(stocks)} remaining")
        results = existing
    else:
        results = []
    
    if not stocks:
        print("✅ All Wikipedia content already fetched")
        return
    
    wiki = wikipediaapi.Wikipedia(
        user_agent='StokzApp/1.0 (contact@example.com)',
        language='en'
    )
    
    print(f"📥 Fetching Wikipedia for {len(stocks)} stocks...")
    
    for stock in tqdm(stocks):
        ticker = stock['ticker']
        company = stock['company']
        
        # Try different title variations
        titles_to_try = [
            company,
            company.replace(' Inc.', '').replace(' Corp.', '').replace(' Ltd.', ''),
            f"{company} (company)",
            ticker,  # Some stocks have Wikipedia page by ticker
        ]
        
        page = None
        for title in titles_to_try:
            try:
                page = wiki.page(title)
                if page.exists():
                    break
            except:
                continue
        
        if page and page.exists():
            summary = page.summary[:2000] if page.summary else ""
            results.append({
                **stock,
                'wiki_page': page.title,
                'wiki_summary': summary,
                'wiki_url': page.fullurl
            })
        else:
            # Use basic info if no Wikipedia page
            results.append({
                **stock,
                'wiki_page': None,
                'wiki_summary': f"{company} is a company in the {stock.get('sector', 'various')} sector.",
                'wiki_url': None
            })
        
        # Save progress every 50 stocks
        if len(results) % 50 == 0:
            with open(WIKI_FILE, 'w') as f:
                json.dump(results, f, indent=2)
        
        time.sleep(0.05)  # Be nice to Wikipedia
    
    with open(WIKI_FILE, 'w') as f:
        json.dump(results, f, indent=2)
    
    wiki_found = sum(1 for r in results if r.get('wiki_page'))
    print(f"✅ Fetched {len(results)} stocks ({wiki_found} with Wikipedia pages)")

def step2_generate_facts():
    """Generate LLM fact cards for all stocks"""
    print("\n" + "="*60)
    print("STEP 2: Generating LLM fact cards")
    print("="*60)
    
    with open(WIKI_FILE) as f:
        stocks = json.load(f)
    
    # Load existing progress
    existing = {}
    if FACTS_FILE.exists():
        with open(FACTS_FILE) as f:
            existing = json.load(f)
        print(f"📂 Found {len(existing)} existing facts")
    
    remaining = [s for s in stocks if s['ticker'] not in existing]
    if not remaining:
        print("✅ All facts already generated")
        return
    
    print(f"📥 Generating facts for {len(remaining)} stocks...")
    print(f"⏱️  Estimated time: {len(remaining) * 10 / 60:.0f} minutes")
    
    # Load model
    print(f"Loading {MODEL_NAME}...")
    from mlx_lm import load, generate
    model, tokenizer = load(MODEL_NAME)
    print("✅ Model loaded")
    
    facts = existing.copy()
    done = 0
    errors = 0
    start = time.time()
    
    for i, stock in enumerate(remaining):
        ticker = stock['ticker']
        company = stock['company']
        wiki = stock.get('wiki_summary', '')[:1500]
        
        prompt = f"""Create a JSON fact card for {company} ({ticker}).

Info: {wiki[:800]}

Return JSON with: summary (2 sentences, max 200 chars), industry, tags (3-5 keywords), founded (year or null), headquarters (city or null).
JSON only:"""
        
        print(f"[{len(facts)+1:4d}/{len(stocks)}] {ticker:6s}", end=" ", flush=True)
        
        try:
            t0 = time.time()
            resp = generate(model, tokenizer, prompt=prompt, max_tokens=250, verbose=False)
            dt = time.time() - t0
            
            # Extract JSON
            s = resp.find("{")
            if s >= 0:
                depth = 0
                e = s
                for j, c in enumerate(resp[s:], s):
                    if c == '{': depth += 1
                    elif c == '}': depth -= 1
                    if depth == 0:
                        e = j + 1
                        break
                
                json_str = resp[s:e]
                data = json.loads(json_str)
                
                facts[ticker] = {
                    "ticker": ticker,
                    "company": company,
                    "sector": stock.get("sector", ""),
                    "sub_industry": stock.get("sub_industry", ""),
                    **data
                }
                
                ind = data.get('industry', '?')[:15]
                print(f"✓ {ind:15s} ({dt:.1f}s)")
                done += 1
            else:
                print(f"✗ no JSON")
                errors += 1
        except Exception as e:
            print(f"✗ {str(e)[:30]}")
            errors += 1
        
        # Save progress every 25 stocks
        if done % 25 == 0 and done > 0:
            with open(FACTS_FILE, "w") as f:
                json.dump(facts, f, indent=2)
            elapsed = time.time() - start
            rate = done / elapsed if done > 0 else 1
            remaining_count = len(remaining) - i - 1
            eta = remaining_count / rate / 60
            print(f"    >>> Saved {len(facts)} | {errors} errors | ETA {eta:.0f}min <<<")
    
    with open(FACTS_FILE, "w") as f:
        json.dump(facts, f, indent=2)
    
    elapsed = (time.time() - start) / 60
    print(f"\n✅ Generated {done} facts, {errors} errors in {elapsed:.1f} minutes")

def step3_create_embeddings():
    """Create similarity embeddings with sector weighting"""
    print("\n" + "="*60)
    print("STEP 3: Creating embeddings and similarity matrix")
    print("SECTOR WEIGHTING ENABLED - same sector stocks get +0.3 boost")
    print("="*60)
    
    from sentence_transformers import SentenceTransformer
    import numpy as np
    
    with open(FACTS_FILE) as f:
        facts = json.load(f)
    
    print(f"📥 Creating embeddings for {len(facts)} stocks...")
    
    # Load embedding model
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    # Create text for each stock (focus on business description, not just Wikipedia)
    tickers = list(facts.keys())
    texts = []
    sectors = []  # Track sectors for weighting
    
    for ticker in tickers:
        f = facts[ticker]
        # Build embedding text - emphasize business model and industry
        sector = f.get('sector', '') or f.get('industry', '')
        sub_industry = f.get('sub_industry', '') or f.get('subIndustry', '')
        tags = ' '.join(f.get('tags', []))
        summary = f.get('summary', '')
        
        # Weight sector/industry terms more heavily by repeating them
        text = f"{f.get('company', '')} {sector} {sector} {sub_industry} {sub_industry} {summary} {tags}"
        texts.append(text)
        sectors.append(sector.lower().strip())
    
    print("Creating embeddings...")
    embeddings = model.encode(texts, show_progress_bar=True)
    
    print("Computing similarity matrix with sector weighting...")
    # Normalize for cosine similarity
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    normalized = embeddings / norms
    
    # Compute base similarity matrix (cosine similarity)
    similarity_matrix = np.dot(normalized, normalized.T)
    
    # Apply sector weighting: boost same-sector stocks by 0.3
    SECTOR_BOOST = 0.3
    print(f"Applying sector boost of {SECTOR_BOOST}...")
    
    for i in range(len(tickers)):
        for j in range(len(tickers)):
            if i != j and sectors[i] and sectors[j] and sectors[i] == sectors[j]:
                # Boost same-sector similarity
                similarity_matrix[i, j] = min(1.0, similarity_matrix[i, j] + SECTOR_BOOST)
    
    # Create similarity dict (top 10 similar for each stock)
    similarity = {}
    for i, ticker in enumerate(tickers):
        scores = similarity_matrix[i]
        # Get top 10 (excluding self)
        top_indices = np.argsort(scores)[::-1][1:11]
        similarity[ticker] = [
            {"ticker": tickers[j], "score": round(float(scores[j]), 4)}
            for j in top_indices
        ]
    
    # Show sample results
    print("\n📊 Sample similarity results:")
    sample_tickers = ['GOOGL', 'AAPL', 'TSLA', 'JPM', 'XOM']
    for t in sample_tickers:
        if t in similarity:
            top3 = [f"{s['ticker']}" for s in similarity[t][:3]]
            print(f"  {t}: {', '.join(top3)}")
    
    print(f"\n✅ Created similarity matrix for {len(tickers)} stocks")
    
    return similarity

def step4_bundle_for_ios(similarity):
    """Create iOS bundle JSON"""
    print("\n" + "="*60)
    print("STEP 4: Creating iOS bundle")
    print("="*60)
    
    with open(FACTS_FILE) as f:
        facts_raw = json.load(f)
    
    # Reformat facts for iOS
    facts = {}
    for ticker, f in facts_raw.items():
        # Handle both nested (fact_card) and flat structures
        fact_card = f.get("fact_card", {})
        
        facts[ticker] = {
            "company": f.get("company", ticker),
            "sector": f.get("sector", ""),
            "subIndustry": f.get("sub_industry", f.get("subIndustry", "")),
            "summary": fact_card.get("summary", f.get("summary", "")),
            "industry": fact_card.get("industry", f.get("industry", "")),
            "tags": fact_card.get("tags", f.get("tags", [])),
            "founded": fact_card.get("founded", f.get("founded")),
            "headquarters": fact_card.get("headquarters", f.get("headquarters")),
        }
    
    bundle = {
        "facts": facts,
        "similarity": similarity,
        "version": "2.0",
        "stockCount": len(facts)
    }
    
    with open(BUNDLE_FILE, 'w') as f:
        json.dump(bundle, f)
    
    size = BUNDLE_FILE.stat().st_size
    print(f"✅ Created {BUNDLE_FILE}")
    print(f"📦 Bundle size: {size:,} bytes ({size/1024:.1f} KB)")
    print(f"📊 Stocks: {len(facts)}")

def main():
    args = sys.argv[1:]
    skip_wiki = '--skip-wiki' in args
    skip_facts = '--skip-facts' in args
    
    print("🚀 RUSSELL 3000 STOCK DATA PIPELINE")
    print(f"📂 Input: {INPUT_FILE}")
    print(f"📦 Output: {BUNDLE_FILE}")
    
    if not INPUT_FILE.exists():
        print(f"❌ Run fetch_russell3000.py first to get stock list")
        sys.exit(1)
    
    start = time.time()
    
    if not skip_wiki:
        step1_fetch_wikipedia()
    else:
        print("\n⏭️  Skipping Wikipedia fetch")
    
    if not skip_facts:
        step2_generate_facts()
    else:
        print("\n⏭️  Skipping fact generation")
    
    similarity = step3_create_embeddings()
    step4_bundle_for_ios(similarity)
    
    elapsed = (time.time() - start) / 60
    print("\n" + "="*60)
    print(f"🎉 PIPELINE COMPLETE in {elapsed:.1f} minutes")
    print("="*60)
    print(f"\nNext steps:")
    print(f"  1. Rebuild app: xcodebuild -scheme Stokz -destination 'generic/platform=iOS' -quiet")
    print(f"  2. Install: xcrun devicectl device install app --device <UUID> <path/to/Stokz.app>")

if __name__ == "__main__":
    main()
