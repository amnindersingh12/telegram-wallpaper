# Backend (optional)

This folder contains an optional Flask + Pyrogram backend used to:

- List the channels/groups your Telegram account has joined
- Fetch images from private/restricted channels via your user session

Public channels can still be scraped directly in the Flutter app without this backend.

## Security

Never commit:

- `.env`
- `SESSION_STRING`
- Pyrogram `*.session*` files

## Setup

1) Create a Python environment and install deps:

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

2) Create a `.env` in the repo root (copy from `.env.example`) and set:

- `API_ID`
- `API_HASH`
- `SESSION_STRING`

3) Run the server:

```bash
cd backend
python server.py
```

Health check:

`GET /health`

Joined channels:

`GET /channels?photos=true`

## Generating SESSION_STRING

From the repo root (after setting `API_ID`/`API_HASH` in your environment):

```bash
cd backend
export API_ID=12345
export API_HASH=your_api_hash
python generate_session.py
```

Copy the printed `SESSION_STRING` into your local `.env`.
