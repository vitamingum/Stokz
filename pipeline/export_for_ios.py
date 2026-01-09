#!/usr/bin/env python3
"""
Export stock data for iOS app.
Creates:
1. stock_facts.json - All fact cards for display
2. stock_similarity.json - Precomputed similar stocks for each ticker
"""
import json
import numpy as np
import faiss
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent / "output"
IOS_DIR = Path(__file__).parent / "ios_bundle"
IOS_DIR.mkdir(exist_ok=True)

def main():
    print("=" * 50)
    print("EXPORT FOR iOS")
    print("=" * 50)
    
    # Load FAISS index and metadata
    index = faiss.read_index(str(OUTPUT_DIR / "stocks.faiss"))
    with open(OUTPUT_DIR / "stocks_metadata.json") as f:
        metadata = json.load(f)
    
    print(f"Loaded {len(metadata)} stocks")
    
    # 1. Export fact cards for iOS
    facts_for_ios = {}
    for m in metadata:
        facts_for_ios[m["ticker"]] = {
            "company": m["company"],
            "sector": m["sector"],
            "subIndustry": m["sub_industry"],
            "summary": m["summary"],
            "industry": m["industry"],
            "tags": m["tags"],
            "founded": m["founded"],
            "headquarters": m["headquarters"],
        }
    
    facts_file = IOS_DIR / "stock_facts.json"
    with open(facts_file, "w") as f:
        json.dump(facts_for_ios, f)
    print(f"💾 Saved {facts_file} ({facts_file.stat().st_size/1024:.0f}KB)")
    
    # 2. Precompute similar stocks (top 10 for each)
    print("\n📊 Computing similarity matrix...")
    tickers = [m["ticker"] for m in metadata]
    n = len(tickers)
    
    similarity = {}
    for i, ticker in enumerate(tickers):
        # Get embedding
        query = np.zeros((1, 384), dtype="float32")
        index.reconstruct(i, query[0])
        
        # Search top 11 (including self)
        distances, indices = index.search(query, 11)
        
        # Store top 10 similar (excluding self)
        similar = []
        for dist, idx in zip(distances[0], indices[0]):
            if idx != i:
                similar.append({
                    "ticker": tickers[idx],
                    "score": round(float(dist), 3)
                })
        similarity[ticker] = similar[:10]
        
        if (i + 1) % 100 == 0:
            print(f"  {i+1}/{n}")
    
    sim_file = IOS_DIR / "stock_similarity.json"
    with open(sim_file, "w") as f:
        json.dump(similarity, f)
    print(f"💾 Saved {sim_file} ({sim_file.stat().st_size/1024:.0f}KB)")
    
    # 3. Create combined bundle
    bundle = {
        "facts": facts_for_ios,
        "similarity": similarity,
        "version": "1.0",
        "stockCount": len(facts_for_ios)
    }
    
    bundle_file = IOS_DIR / "stock_data_bundle.json"
    with open(bundle_file, "w") as f:
        json.dump(bundle, f)
    print(f"💾 Saved {bundle_file} ({bundle_file.stat().st_size/1024:.0f}KB)")
    
    # Show summary
    print("\n" + "=" * 50)
    print("iOS BUNDLE READY")
    print("=" * 50)
    print(f"Files in {IOS_DIR}:")
    for f in IOS_DIR.iterdir():
        print(f"  {f.name}: {f.stat().st_size/1024:.0f}KB")

if __name__ == "__main__":
    main()
