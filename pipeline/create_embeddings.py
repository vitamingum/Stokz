#!/usr/bin/env python3
"""
Create FAISS embeddings for stock similarity search.
Uses sentence-transformers for semantic embeddings.
"""
import json
import numpy as np
import faiss
from pathlib import Path
from sentence_transformers import SentenceTransformer
from tqdm import tqdm

DATA_DIR = Path(__file__).parent / "data"
OUTPUT_DIR = Path(__file__).parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)

# Normalized facts file
FACTS_FILE = DATA_DIR / "stock_facts_normalized.json"
WIKI_FILE = DATA_DIR / "sp500_with_wiki.json"

# Use a good embedding model for semantic similarity
EMBEDDING_MODEL = "all-MiniLM-L6-v2"  # 384 dimensions, fast, good quality

def load_stocks():
    """Load facts and merge with wiki data for full context"""
    with open(FACTS_FILE) as f:
        facts = json.load(f)
    with open(WIKI_FILE) as f:
        wiki = {s['ticker']: s for s in json.load(f)}
    
    # Merge
    stocks = []
    for ticker, data in facts.items():
        w = wiki.get(ticker, {})
        stocks.append({
            **data,
            'sub_industry': w.get('sub_industry', ''),
        })
    return stocks

def create_embedding_text(stock):
    """Create text to embed for each stock"""
    # Combine relevant info for embedding
    parts = [
        stock.get('company', ''),
        stock.get('sector', ''),
        stock.get('sub_industry', ''),
        stock.get('summary', ''),
        stock.get('industry', ''),
        ' '.join(stock.get('tags', []))
    ]
    
    return ' '.join(p for p in parts if p)

def main():
    stocks = load_stocks()
    
    print(f"🤖 Loading embedding model: {EMBEDDING_MODEL}")
    model = SentenceTransformer(EMBEDDING_MODEL)
    print("✅ Model loaded!")
    
    # Create texts for embedding
    print(f"\n📝 Creating embeddings for {len(stocks)} stocks...")
    texts = [create_embedding_text(s) for s in stocks]
    
    # Generate embeddings
    embeddings = model.encode(texts, show_progress_bar=True)
    embeddings = np.array(embeddings).astype('float32')
    
    print(f"✅ Generated {len(embeddings)} embeddings of dimension {embeddings.shape[1]}")
    
    # Create FAISS index
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatIP(dimension)  # Inner product (cosine similarity for normalized vectors)
    
    # Normalize for cosine similarity
    faiss.normalize_L2(embeddings)
    index.add(embeddings)
    
    print(f"✅ FAISS index created with {index.ntotal} vectors")
    
    # Save index
    index_file = OUTPUT_DIR / "stocks.faiss"
    faiss.write_index(index, str(index_file))
    print(f"💾 Saved FAISS index to {index_file}")
    
    # Save stock metadata (for lookup after search)
    metadata = []
    for i, stock in enumerate(stocks):
        metadata.append({
            'id': i,
            'ticker': stock['ticker'],
            'company': stock.get('company', ''),
            'sector': stock.get('sector', ''),
            'sub_industry': stock.get('sub_industry', ''),
            'summary': stock.get('summary', ''),
            'industry': stock.get('industry', ''),
            'tags': stock.get('tags', []),
            'founded': stock.get('founded'),
            'headquarters': stock.get('headquarters'),
        })
    
    metadata_file = OUTPUT_DIR / "stocks_metadata.json"
    with open(metadata_file, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"💾 Saved metadata to {metadata_file}")
    
    # Save embedding model name for iOS
    config_file = OUTPUT_DIR / "config.json"
    with open(config_file, 'w') as f:
        json.dump({
            'embedding_model': EMBEDDING_MODEL,
            'dimension': dimension,
            'num_stocks': len(stocks)
        }, f, indent=2)
    print(f"💾 Saved config to {config_file}")
    
    # Test similarity search
    print("\n🔍 Testing similarity search...")
    test_ticker = "AAPL"
    test_idx = next(i for i, s in enumerate(stocks) if s['ticker'] == test_ticker)
    
    query = embeddings[test_idx:test_idx+1]
    distances, indices = index.search(query, 6)  # Top 6 (includes self)
    
    print(f"\n  Stocks similar to {test_ticker} ({stocks[test_idx]['company']}):")
    for i, (dist, idx) in enumerate(zip(distances[0], indices[0])):
        if idx != test_idx:  # Skip self
            s = stocks[idx]
            print(f"    {i}. {s['ticker']:6} ({dist:.3f}) - {s['company'][:30]} [{s['sector']}]")

if __name__ == "__main__":
    main()
