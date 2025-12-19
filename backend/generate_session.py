#!/usr/bin/env python3
"""Generate a new Pyrogram SESSION_STRING.

Run this script to generate a new session string.
You'll need to enter your phone number and the verification code.

Security note:
- Do NOT commit session strings or .env files.
- This script prints the session string to stdout only.
"""

import asyncio
import os

# Set up event loop for Python 3.10+
try:
    asyncio.get_running_loop()
except RuntimeError:
    _main_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_main_loop)

from pyrogram import Client


def _require_env(name: str) -> str:
    value = os.getenv(name)
    if value is None or not value.strip():
        raise SystemExit(
            f"Missing required environment variable: {name}\n"
            "Set it before running, e.g.:\n"
            "  export API_ID=12345\n"
            "  export API_HASH=your_api_hash\n"
        )
    return value.strip()

async def main():
    print("=" * 60)
    print("Pyrogram Session String Generator")
    print("=" * 60)
    print()
    print("This will create a new session string for your Telegram account.")
    print("You'll need to enter your phone number and verification code.")
    print()
    
    api_id = int(_require_env("API_ID"))
    api_hash = _require_env("API_HASH")

    async with Client(
        "session_generator",
        api_id=api_id,
        api_hash=api_hash,
    ) as app:
        session_string = await app.export_session_string()
        
        print()
        print("=" * 60)
        print("SESSION_STRING GENERATED SUCCESSFULLY!")
        print("=" * 60)
        print()
        print("Copy this string and add it to your .env file:")
        print()
        print(f"SESSION_STRING={session_string}")
        print()
        print("=" * 60)
        
        print("\nIMPORTANT: Do NOT commit this session string. Add it to your local .env file only.")

if __name__ == "__main__":
    asyncio.run(main())
