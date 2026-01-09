#!/usr/bin/env python3
"""
Run the full pipeline: S&P 500 → Wikipedia → LLM Facts → FAISS
"""
import subprocess
import sys
from pathlib import Path

PIPELINE_DIR = Path(__file__).parent

def run_step(script_name, description):
    print(f"\n{'='*60}")
    print(f"🚀 {description}")
    print(f"{'='*60}\n")
    
    result = subprocess.run(
        [sys.executable, PIPELINE_DIR / script_name],
        cwd=PIPELINE_DIR
    )
    
    if result.returncode != 0:
        print(f"❌ {script_name} failed!")
        sys.exit(1)
    
    print(f"\n✅ {description} complete!")

def main():
    print("""
╔════════════════════════════════════════════════════════════╗
║  STOKZ DATA PIPELINE                                        ║
║  S&P 500 → Wikipedia → LLM Fact Cards → FAISS Embeddings   ║
╚════════════════════════════════════════════════════════════╝
    """)
    
    # Step 1: Fetch S&P 500 list
    run_step("fetch_sp500.py", "Step 1: Fetching S&P 500 ticker list")
    
    # Step 2: Fetch Wikipedia content
    run_step("fetch_wikipedia.py", "Step 2: Fetching Wikipedia content")
    
    # Step 3: Generate fact cards with LLM
    run_step("generate_facts.py", "Step 3: Generating fact cards with LLM")
    
    # Step 4: Create FAISS embeddings
    run_step("create_embeddings.py", "Step 4: Creating FAISS embeddings")
    
    print("""
╔════════════════════════════════════════════════════════════╗
║  ✅ PIPELINE COMPLETE!                                      ║
║                                                             ║
║  Output files in pipeline/output/:                         ║
║    - stocks.faiss        (FAISS index for similarity)      ║
║    - stocks_metadata.json (stock info + fact cards)        ║
║    - config.json         (embedding config)                ║
║                                                             ║
║  Next: Copy to iOS app bundle                              ║
╚════════════════════════════════════════════════════════════╝
    """)

if __name__ == "__main__":
    main()
