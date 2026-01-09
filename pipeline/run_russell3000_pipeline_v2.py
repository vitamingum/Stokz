#!/usr/bin/env python3
"""
Russell 3000 Pipeline v2 - With Hallucination Prevention
Key improvements:
1. Better prompts with company name emphasis
2. Post-generation validation 
3. Retry logic for failed generations
4. Fallback to simpler factual output

Usage:
    python3 run_russell3000_pipeline_v2.py [--skip-wiki] [--skip-facts] [--fix-only]
"""

import json
import time
import sys
import re
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

INPUT_FILE = DATA_DIR / "russell3000_stocks.json"
WIKI_FILE = DATA_DIR / "russell3000_with_wiki.json"
FACTS_FILE = DATA_DIR / "russell3000_facts.json"
BUNDLE_FILE = Path(__file__).parent.parent / "Stokz" / "stock_data_bundle.json"

# Use fast model
MODEL_NAME = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

# Known hallucination patterns to reject
HALLUCINATION_PATTERNS = [
    r"is a (type|kind|form) of",
    r"is a term",
    r"refers to",
    r"is a word",
    r"is a (common|popular)",
    r"is an? (object|thing|device|tool|material|substance)",
    r"is a (food|drink|plant|animal|game|sport)",
    r"is a (place|city|country|region)",
    r"is a (route|path|way|road)",
    r"in the english language",
    r"merriam-webster|oxford dictionary",
    r"internet meme",
    r"O RLY\?",  # Specific meme reference
    r"is a (Pakistani|Indian|Chinese|Japanese) (fashion|designer|actor|singer)",
]

def validate_summary(summary: str, company: str, ticker: str) -> tuple[bool, str]:
    """
    Validate that a summary is about the actual company, not a hallucination.
    Returns (is_valid, reason)
    """
    if not summary or len(summary) < 20:
        return False, "Too short"
    
    # Check for hallucination patterns
    for pattern in HALLUCINATION_PATTERNS:
        if re.search(pattern, summary, re.IGNORECASE):
            return False, f"Matches hallucination pattern: {pattern}"
    
    # Check if company name or ticker appears in summary
    company_words = [w.lower() for w in company.split() if len(w) > 3]
    summary_lower = summary.lower()
    ticker_lower = ticker.lower()
    
    # Must contain either company name word or ticker
    has_company_ref = any(word in summary_lower for word in company_words[:2])
    has_ticker_ref = ticker_lower in summary_lower
    
    # Also accept business terms as fallback
    biz_terms = ['company', 'corporation', 'inc', 'corp', 'group', 'holdings', 
                 'manufacturer', 'provider', 'operator', 'headquartered', 'founded']
    has_biz_term = any(term in summary_lower for term in biz_terms)
    
    if not has_company_ref and not has_ticker_ref and not has_biz_term:
        return False, "No company reference or business terms"
    
    return True, "OK"


def create_prompt_v2(company: str, ticker: str, sector: str, sub_industry: str, wiki: str) -> str:
    """
    Create an improved prompt that emphasizes the company identity
    """
    # Clean up wiki - remove any empty/useless content
    if wiki and len(wiki) > 50:
        wiki_context = f"\nBackground: {wiki[:800]}"
    else:
        wiki_context = ""
    
    # Build a clear, company-focused prompt
    prompt = f"""You are writing a fact card for a PUBLICLY TRADED COMPANY.

Company: {company}
Stock Ticker: {ticker}
Sector: {sector or 'Unknown'}
Industry: {sub_industry or 'Unknown'}
{wiki_context}

Write a JSON fact card. The "summary" MUST be about {company} the company, NOT about what the word "{ticker}" means.

Return this exact JSON structure:
{{
  "summary": "2 sentences describing {company}'s business. Max 200 chars.",
  "industry": "primary industry",
  "tags": ["keyword1", "keyword2", "keyword3"],
  "founded": "year or null",
  "headquarters": "city, state or null"
}}

JSON only, no other text:"""
    
    return prompt


def create_fallback_summary(company: str, ticker: str, sector: str, sub_industry: str) -> dict:
    """
    Create a minimal but accurate fact card when LLM fails
    """
    industry = sub_industry or sector or "Various"
    
    # Simple factual summary that won't hallucinate
    summary = f"{company} is a publicly traded company in the {industry.lower()} industry."
    
    return {
        "summary": summary,
        "industry": industry,
        "tags": [sector.lower()] if sector else ["stock"],
        "founded": None,
        "headquarters": None
    }


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
            ticker,
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
            results.append({
                **stock,
                'wiki_page': None,
                'wiki_summary': "",
                'wiki_url': None
            })
        
        if len(results) % 50 == 0:
            with open(WIKI_FILE, 'w') as f:
                json.dump(results, f, indent=2)
        
        time.sleep(0.05)
    
    with open(WIKI_FILE, 'w') as f:
        json.dump(results, f, indent=2)
    
    wiki_found = sum(1 for r in results if r.get('wiki_page'))
    print(f"✅ Fetched {len(results)} stocks ({wiki_found} with Wikipedia pages)")


def step2_generate_facts(fix_only=False):
    """Generate LLM fact cards with hallucination prevention"""
    print("\n" + "="*60)
    print("STEP 2: Generating LLM fact cards (v2 - with validation)")
    print("="*60)
    
    with open(WIKI_FILE) as f:
        stocks = json.load(f)
    
    stocks_by_ticker = {s['ticker']: s for s in stocks}
    
    # Load existing facts
    existing = {}
    if FACTS_FILE.exists():
        with open(FACTS_FILE) as f:
            existing = json.load(f)
        print(f"📂 Found {len(existing)} existing facts")
    
    # Determine which stocks need processing
    if fix_only:
        # Only re-process stocks with bad summaries
        to_process = []
        for ticker, data in existing.items():
            summary = data.get('summary', '')
            company = data.get('company', ticker)
            is_valid, reason = validate_summary(summary, company, ticker)
            if not is_valid:
                if ticker in stocks_by_ticker:
                    to_process.append(stocks_by_ticker[ticker])
                    print(f"  Will fix: {ticker} - {reason}")
        print(f"\n📋 Found {len(to_process)} stocks to fix")
    else:
        # Process stocks without facts
        to_process = [s for s in stocks if s['ticker'] not in existing]
    
    if not to_process:
        print("✅ All facts already generated and valid")
        return
    
    print(f"📥 Generating facts for {len(to_process)} stocks...")
    print(f"⏱️  Estimated time: {len(to_process) * 12 / 60:.0f} minutes")
    
    # Load model
    print(f"Loading {MODEL_NAME}...")
    from mlx_lm import load, generate
    model, tokenizer = load(MODEL_NAME)
    print("✅ Model loaded")
    
    facts = existing.copy()
    done = 0
    errors = 0
    fallbacks = 0
    start = time.time()
    
    for i, stock in enumerate(to_process):
        ticker = stock['ticker']
        company = stock['company']
        sector = stock.get('sector', '')
        sub_industry = stock.get('sub_industry', '')
        wiki = stock.get('wiki_summary', '')
        
        print(f"[{i+1:4d}/{len(to_process)}] {ticker:6s} ({company[:25]})", end=" ", flush=True)
        
        success = False
        attempts = 0
        max_attempts = 2
        
        while not success and attempts < max_attempts:
            attempts += 1
            
            try:
                prompt = create_prompt_v2(company, ticker, sector, sub_industry, wiki)
                
                t0 = time.time()
                resp = generate(model, tokenizer, prompt=prompt, max_tokens=300, verbose=False)
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
                    
                    # Validate the summary
                    summary = data.get('summary', '')
                    is_valid, reason = validate_summary(summary, company, ticker)
                    
                    if is_valid:
                        facts[ticker] = {
                            "ticker": ticker,
                            "company": company,
                            "sector": sector,
                            "sub_industry": sub_industry,
                            **data
                        }
                        ind = data.get('industry', '?')[:15]
                        print(f"✓ {ind:15s} ({dt:.1f}s)")
                        done += 1
                        success = True
                    else:
                        if attempts < max_attempts:
                            print(f"⚠ {reason[:20]}, retry...", end=" ")
                        else:
                            print(f"⚠ {reason[:20]}", end=" ")
                else:
                    if attempts >= max_attempts:
                        print(f"✗ no JSON", end=" ")
                        
            except Exception as e:
                if attempts >= max_attempts:
                    print(f"✗ {str(e)[:20]}", end=" ")
        
        # If still not successful, use fallback
        if not success:
            fallback_data = create_fallback_summary(company, ticker, sector, sub_industry)
            facts[ticker] = {
                "ticker": ticker,
                "company": company,
                "sector": sector,
                "sub_industry": sub_industry,
                **fallback_data
            }
            print(f"→ fallback")
            fallbacks += 1
            done += 1
        
        # Save progress every 25 stocks
        if done % 25 == 0 and done > 0:
            with open(FACTS_FILE, "w") as f:
                json.dump(facts, f, indent=2)
            elapsed = time.time() - start
            rate = done / elapsed if done > 0 else 1
            remaining_count = len(to_process) - i - 1
            eta = remaining_count / rate / 60
            print(f"    >>> Saved {len(facts)} | {fallbacks} fallbacks | ETA {eta:.0f}min <<<")
    
    with open(FACTS_FILE, "w") as f:
        json.dump(facts, f, indent=2)
    
    elapsed = (time.time() - start) / 60
    print(f"\n✅ Generated {done} facts ({fallbacks} used fallback) in {elapsed:.1f} minutes")


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
    
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    tickers = list(facts.keys())
    texts = []
    sectors = []
    
    for ticker in tickers:
        f = facts[ticker]
        sector = f.get('sector', '') or f.get('industry', '')
        sub_industry = f.get('sub_industry', '') or f.get('subIndustry', '')
        tags = ' '.join(f.get('tags', []))
        summary = f.get('summary', '')
        
        text = f"{f.get('company', '')} {sector} {sector} {sub_industry} {sub_industry} {summary} {tags}"
        texts.append(text)
        sectors.append(sector.lower().strip())
    
    print("Creating embeddings...")
    embeddings = model.encode(texts, show_progress_bar=True)
    
    print("Computing similarities with sector weighting...")
    from sklearn.metrics.pairwise import cosine_similarity
    sim_matrix = cosine_similarity(embeddings)
    
    # Apply sector weighting
    SECTOR_BOOST = 0.3
    for i in range(len(tickers)):
        for j in range(len(tickers)):
            if i != j and sectors[i] and sectors[j] and sectors[i] == sectors[j]:
                sim_matrix[i][j] = min(1.0, sim_matrix[i][j] + SECTOR_BOOST)
    
    # Build similarity dict
    similarity = {}
    for i, ticker in enumerate(tickers):
        scores = [(tickers[j], float(sim_matrix[i][j])) for j in range(len(tickers)) if i != j]
        scores.sort(key=lambda x: x[1], reverse=True)
        similarity[ticker] = [{"ticker": t, "score": round(s, 3)} for t, s in scores[:10]]
    
    print(f"✅ Created similarity matrix for {len(tickers)} stocks")
    return similarity


def step4_create_bundle():
    """Create the final bundle for the iOS app"""
    print("\n" + "="*60)
    print("STEP 4: Creating iOS bundle")
    print("="*60)
    
    with open(FACTS_FILE) as f:
        raw_facts = json.load(f)
    
    # Create similarity
    similarity = step3_create_embeddings()
    
    # Format facts for iOS
    facts = {}
    for ticker, data in raw_facts.items():
        facts[ticker] = {
            "company": data.get("company", ticker),
            "sector": data.get("sector", ""),
            "subIndustry": data.get("sub_industry", data.get("subIndustry", "")),
            "summary": data.get("summary", ""),
            "industry": data.get("industry", ""),
            "tags": data.get("tags", []),
            "founded": str(data.get("founded", "")) if data.get("founded") else None,
            "headquarters": data.get("headquarters")
        }
    
    bundle = {
        "version": "2.0",
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "stockCount": len(facts),
        "facts": facts,
        "similarity": similarity
    }
    
    with open(BUNDLE_FILE, 'w') as f:
        json.dump(bundle, f)
    
    size_kb = BUNDLE_FILE.stat().st_size / 1024
    print(f"✅ Created bundle: {BUNDLE_FILE}")
    print(f"   {len(facts)} stocks, {size_kb:.0f} KB")


def validate_bundle():
    """Check the bundle for any remaining issues"""
    print("\n" + "="*60)
    print("VALIDATION: Checking bundle quality")
    print("="*60)
    
    with open(BUNDLE_FILE) as f:
        bundle = json.load(f)
    
    facts = bundle.get('facts', {})
    issues = []
    
    for ticker, data in facts.items():
        summary = data.get('summary', '')
        company = data.get('company', ticker)
        is_valid, reason = validate_summary(summary, company, ticker)
        if not is_valid:
            issues.append((ticker, company, reason, summary[:100]))
    
    if issues:
        print(f"⚠️  Found {len(issues)} stocks with potential issues:")
        for ticker, company, reason, summary in issues[:20]:
            print(f"  {ticker}: {reason}")
            print(f"    Summary: {summary}...")
        if len(issues) > 20:
            print(f"  ... and {len(issues) - 20} more")
    else:
        print("✅ All summaries validated successfully!")
    
    return len(issues)


if __name__ == "__main__":
    skip_wiki = "--skip-wiki" in sys.argv
    skip_facts = "--skip-facts" in sys.argv
    fix_only = "--fix-only" in sys.argv
    
    if fix_only:
        print("🔧 FIX MODE: Only re-processing invalid summaries")
        step2_generate_facts(fix_only=True)
        step4_create_bundle()
        validate_bundle()
    else:
        if not skip_wiki:
            step1_fetch_wikipedia()
        
        if not skip_facts:
            step2_generate_facts()
        
        step4_create_bundle()
        validate_bundle()
    
    print("\n" + "="*60)
    print("🎉 PIPELINE COMPLETE!")
    print("="*60)
