#!/usr/bin/env python3
"""
Step 3: Generate fact cards using local LLM (MLX + Qwen2.5-7B)
"""
import json
from pathlib import Path
from tqdm import tqdm
import mlx_lm
from mlx_lm.sample_utils import make_sampler

DATA_DIR = Path(__file__).parent / "data"

# Model to use - Qwen2.5-7B-Instruct is great for this
MODEL_NAME = "mlx-community/Qwen2.5-7B-Instruct-4bit"

def load_stocks():
    with open(DATA_DIR / "sp500_with_wiki.json") as f:
        return json.load(f)

def generate_fact_card(model, tokenizer, sampler, stock):
    """Generate a 400-char fact card for a stock"""
    
    prompt = f"""Generate a concise fact card (max 400 characters) for this company.
Include: 1-sentence summary, key business, and 3-5 tags.

Company: {stock['company']}
Ticker: {stock['ticker']}
Sector: {stock['sector']}
Industry: {stock['sub_industry']}
Wikipedia Summary: {stock['wiki_summary'][:1000]}

Format your response as JSON:
{{"summary": "...", "business": "...", "tags": ["tag1", "tag2", ...]}}

Keep total under 400 characters. Be factual and concise."""

    messages = [{"role": "user", "content": prompt}]
    
    response = mlx_lm.generate(
        model,
        tokenizer,
        prompt=tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True),
        max_tokens=300,
        sampler=sampler
    )
    
    # Extract JSON from response
    try:
        # Find JSON in response
        start = response.find('{')
        end = response.rfind('}') + 1
        if start >= 0 and end > start:
            fact_card = json.loads(response[start:end])
            return fact_card
    except:
        pass
    
    # Fallback
    return {
        "summary": f"{stock['company']} operates in the {stock['sub_industry']} industry.",
        "business": stock['sub_industry'],
        "tags": [stock['sector'].lower()]
    }

def main():
    stocks = load_stocks()
    
    print(f"🤖 Loading model: {MODEL_NAME}")
    print("   This may take a minute on first run (downloading ~5GB)...")
    model, tokenizer = mlx_lm.load(MODEL_NAME)
    sampler = make_sampler(temp=0.3)
    print("✅ Model loaded!")
    
    results = []
    
    print(f"\n📝 Generating fact cards for {len(stocks)} companies...")
    for stock in tqdm(stocks):
        fact_card = generate_fact_card(model, tokenizer, sampler, stock)
        
        results.append({
            **stock,
            'fact_card': fact_card
        })
    
    # Save results
    output_file = DATA_DIR / "sp500_with_facts.json"
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\n💾 Saved to {output_file}")
    
    # Show samples
    print("\n📊 Sample fact cards:")
    for r in results[:3]:
        print(f"\n  {r['ticker']} - {r['company']}")
        print(f"  Summary: {r['fact_card'].get('summary', 'N/A')[:100]}...")
        print(f"  Tags: {r['fact_card'].get('tags', [])}")

if __name__ == "__main__":
    main()
