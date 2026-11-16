#!/usr/bin/env python3
import sys
import os
import json
import time
import urllib.request

CACHE_DIR = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
CACHE_FILE = os.path.join(CACHE_DIR, "shell27", "stocks.json")
CACHE_TTL = 90  # 90 seconds cache

def fetch_crypto():
    results = []
    try:
        url = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,solana&sparkline=true"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            for c in data:
                raw_spark = c.get("sparkline_in_7d", {}).get("price", [])
                # Downsample 168 pts to ~14 pts
                step = max(1, len(raw_spark) // 14)
                sampled_spark = raw_spark[::step][-14:] if raw_spark else []
                results.append({
                    "symbol": c.get("symbol", "").upper(),
                    "name": c.get("name", ""),
                    "price": round(float(c.get("current_price", 0)), 2),
                    "change24h": round(float(c.get("price_change_percentage_24h", 0)), 2),
                    "currency": "$",
                    "sparkline": sampled_spark
                })
    except Exception as e:
        pass
    return results

def fetch_stock_yahoo(symbol, name):
    try:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=15m"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            res = data.get("chart", {}).get("result", [{}])[0]
            meta = res.get("meta", {})
            curr_price = meta.get("regularMarketPrice") or meta.get("chartPreviousClose") or 0
            prev_close = meta.get("chartPreviousClose") or curr_price or 1
            change_pct = round(((curr_price - prev_close) / prev_close) * 100, 2)
            quote = res.get("indicators", {}).get("quote", [{}])[0].get("close", [])
            valid_pts = [round(float(p), 2) for p in quote if p is not None]
            # Downsample to ~14 pts
            step = max(1, len(valid_pts) // 14)
            sampled = valid_pts[::step][-14:] if valid_pts else []
            return {
                "symbol": symbol,
                "name": name,
                "price": round(float(curr_price), 2),
                "change24h": change_pct,
                "currency": "$",
                "sparkline": sampled
            }
    except Exception:
        pass
    return None

def main():
    now = time.time()
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    # Check cache
    if os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            if now - mtime < CACHE_TTL:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    print(f.read())
                    return
        except Exception:
            pass

    items = []
    # 1. Fetch Crypto
    crypto_list = fetch_crypto()
    items.extend(crypto_list)

    # 2. Fetch AAPL & NVDA
    for sym, nm in [("AAPL", "Apple"), ("NVDA", "NVIDIA")]:
        st = fetch_stock_yahoo(sym, nm)
        if st:
            items.append(st)

    out_json = json.dumps(items, ensure_ascii=False)
    if items:
        temp_file = CACHE_FILE + ".tmp"
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                f.write(out_json)
            os.replace(temp_file, CACHE_FILE)
        except OSError:
            try:
                os.remove(temp_file)
            except OSError:
                pass

    print(out_json)

if __name__ == "__main__":
    main()

