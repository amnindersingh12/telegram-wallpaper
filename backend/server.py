#!/usr/bin/env python3
"""
Telegram Backend Server
Uses Pyrogram with SESSION_STRING to access user's joined channels
Compatible with Python 3.10+ / 3.14+
"""

import os
import json
import asyncio
import base64
import threading
from io import BytesIO

# CRITICAL: Set up event loop BEFORE importing pyrogram (for Python 3.10+)
# Pyrogram uses asyncio.get_event_loop() during import which requires an existing loop
try:
    asyncio.get_running_loop()
except RuntimeError:
    # No running loop, create one and set it
    _main_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_main_loop)

from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
from pyrogram import Client
from pyrogram.enums import ChatType
from pyrogram.errors import FloodWait
from dotenv import load_dotenv

# Load environment variables from parent directory
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

app = Flask(__name__)
CORS(app)

# Telegram credentials
# IMPORTANT: Never hard-code credentials in source control.
API_ID = os.getenv('API_ID')
API_HASH = os.getenv('API_HASH')
SESSION_STRING = os.getenv('SESSION_STRING')


def _require_env(name: str) -> str:
    value = os.getenv(name)
    if value is None or not value.strip():
        raise ValueError(f"Missing required environment variable: {name}")
    return value.strip()

# Global async loop and client - managed in a dedicated thread
_loop = None
_loop_thread = None
_client = None


def _start_background_loop(loop):
    """Run the event loop in a background thread."""
    asyncio.set_event_loop(loop)
    loop.run_forever()


def get_loop():
    """Get or create the background event loop."""
    global _loop, _loop_thread
    if _loop is None or not _loop.is_running():
        _loop = asyncio.new_event_loop()
        _loop_thread = threading.Thread(target=_start_background_loop, args=(_loop,), daemon=True)
        _loop_thread.start()
    return _loop


def run_async(coro):
    """Run an async coroutine from sync code."""
    loop = get_loop()
    future = asyncio.run_coroutine_threadsafe(coro, loop)
    return future.result(timeout=60)  # 60 second timeout


async def get_client():
    """Get or create Pyrogram client."""
    global _client
    if _client is None:
        # Validate env vars at the last responsible moment.
        # This keeps import-time behavior predictable and errors actionable.
        api_id = int(_require_env("API_ID"))
        api_hash = _require_env("API_HASH")
        session_string = _require_env("SESSION_STRING")
        _client = Client(
            "wallpaper_session",
            api_id=api_id,
            api_hash=api_hash,
            session_string=session_string,
            in_memory=True
        )
    # Only start if not already connected
    if not _client.is_connected:
        try:
            await _client.start()
        except Exception as e:
            # If client is already started/initialized, just continue
            if "already" not in str(e).lower():
                raise
    return _client


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'session_available': bool(SESSION_STRING)})


@app.route('/channels', methods=['GET'])
def get_channels():
    """Get all channels/groups the user has joined"""
    try:
        include_photos = request.args.get('photos', 'false').lower() == 'true'
        
        async def fetch_channels():
            c = await get_client()
            channels = []
            
            async for dialog in c.get_dialogs():
                chat = dialog.chat
                
                # Only include channels and supergroups
                if chat.type in [ChatType.CHANNEL, ChatType.SUPERGROUP]:
                    channel_info = {
                        'id': chat.id,
                        'username': chat.username,
                        'title': chat.title,
                        'type': str(chat.type),
                        'photo_url': None,
                        'members_count': getattr(chat, 'members_count', None),
                        'description': getattr(chat, 'description', None),
                    }
                    
                    # Get photo URL if available (only if requested)
                    if include_photos and chat.photo:
                        try:
                            photo_data = await c.download_media(
                                chat.photo.small_file_id,
                                in_memory=True
                            )
                            if photo_data:
                                channel_info['photo_base64'] = base64.b64encode(
                                    photo_data.getvalue()
                                ).decode('utf-8')
                        except Exception as e:
                            print(f"Error downloading photo: {e}")
                    
                    channels.append(channel_info)
            
            return channels
        
        channels = run_async(fetch_channels())
        return jsonify({'success': True, 'channels': channels})
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/channel/<channel_id>/images', methods=['GET'])
def get_channel_images(channel_id):
    """Get images from a specific channel"""
    try:
        limit = request.args.get('limit', 50, type=int)
        offset_id = request.args.get('offset_id', 0, type=int)
        
        async def fetch_images():
            c = await get_client()
            images = []
            
            chat_id = int(channel_id) if channel_id.lstrip('-').isdigit() else channel_id
            
            async for message in c.get_chat_history(
                chat_id, 
                limit=limit,
                offset_id=offset_id
            ):
                if message.photo:
                    photo = message.photo
                    images.append({
                        'message_id': message.id,
                        'file_id': photo.file_id,
                        'file_unique_id': photo.file_unique_id,
                        'width': photo.width,
                        'height': photo.height,
                        'date': message.date.isoformat() if message.date else None,
                        'caption': message.caption,
                    })
                elif message.document and message.document.mime_type and message.document.mime_type.startswith('image/'):
                    images.append({
                        'message_id': message.id,
                        'file_id': message.document.file_id,
                        'file_unique_id': message.document.file_unique_id,
                        'width': getattr(message.document, 'width', None),
                        'height': getattr(message.document, 'height', None),
                        'date': message.date.isoformat() if message.date else None,
                        'caption': message.caption,
                        'file_name': message.document.file_name,
                    })
            
            return images
        
        images = run_async(fetch_images())
        return jsonify({'success': True, 'images': images})
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/download/<channel_id>/<int:message_id>', methods=['GET'])
def download_image(channel_id, message_id):
    """Download an image from a channel"""
    try:
        thumbnail = request.args.get('thumbnail', 'false').lower() == 'true'
        
        async def fetch_image():
            c = await get_client()
            
            chat_id = int(channel_id) if channel_id.lstrip('-').isdigit() else channel_id
            
            messages = await c.get_messages(chat_id, message_id)
            message = messages if not isinstance(messages, list) else messages[0]
            
            if message.photo:
                file_id = message.photo.file_id
                if thumbnail and hasattr(message.photo, 'thumbs') and message.photo.thumbs:
                    file_id = message.photo.thumbs[0].file_id
            elif message.document:
                file_id = message.document.file_id
                if thumbnail and hasattr(message.document, 'thumbs') and message.document.thumbs:
                    file_id = message.document.thumbs[0].file_id
            else:
                return None
            
            try:
                file_data = await c.download_media(file_id, in_memory=True)
                return file_data.getvalue() if file_data else None
            except FloodWait as e:
                print(f"FloodWait: Need to wait {e.value} seconds")
                return None
        
        image_data = run_async(fetch_image())
        
        if image_data:
            return send_file(
                BytesIO(image_data),
                mimetype='image/jpeg',
                as_attachment=False
            )
        else:
            return jsonify({'success': False, 'error': 'Image not found or rate limited'}), 404
    
    except FloodWait as e:
        return jsonify({'success': False, 'error': f'Rate limited. Wait {e.value} seconds'}), 429
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/file/<path:file_id>', methods=['GET'])
def get_file(file_id):
    """Download a file by its file_id"""
    try:
        async def fetch_file():
            c = await get_client()
            file_data = await c.download_media(file_id, in_memory=True)
            return file_data.getvalue() if file_data else None
        
        file_data = run_async(fetch_file())
        
        if file_data:
            return send_file(
                BytesIO(file_data),
                mimetype='image/jpeg',
                as_attachment=False
            )
        else:
            return jsonify({'success': False, 'error': 'File not found'}), 404
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/search', methods=['GET'])
def search_channels():
    """Search for public channels"""
    try:
        query = request.args.get('q', '')
        if not query:
            return jsonify({'success': False, 'error': 'Query parameter "q" is required'}), 400
        
        async def do_search():
            c = await get_client()
            results = []
            
            async for chat in c.search_global(query, limit=20):
                if hasattr(chat, 'chat') and chat.chat.type in [ChatType.CHANNEL, ChatType.SUPERGROUP]:
                    channel = chat.chat
                    results.append({
                        'id': channel.id,
                        'username': channel.username,
                        'title': channel.title,
                        'type': str(channel.type),
                        'members_count': getattr(channel, 'members_count', None),
                    })
            
            return results
        
        results = run_async(do_search())
        return jsonify({'success': True, 'channels': results})
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/me', methods=['GET'])
def get_me():
    """Get current user info"""
    try:
        async def fetch_me():
            c = await get_client()
            me = await c.get_me()
            return {
                'id': me.id,
                'first_name': me.first_name,
                'last_name': me.last_name,
                'username': me.username,
                'phone_number': me.phone_number,
            }
        
        user = run_async(fetch_me())
        return jsonify({'success': True, 'user': user})
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)}), 500


if __name__ == '__main__':
    print("=" * 60)
    print("Telegram Wallpaper Backend Server")
    print("=" * 60)
    print(f"API_ID: {API_ID}")
    print(f"API_HASH: {API_HASH[:8]}..." if API_HASH else "API_HASH: NOT SET")
    print(f"SESSION_STRING: {'Available' if SESSION_STRING else 'NOT FOUND!'}")
    print("=" * 60)
    
    if not SESSION_STRING:
        print("\n⚠️  WARNING: SESSION_STRING not found!")
        print("Make sure you have a .env file in the parent directory with SESSION_STRING set.")
    
    print("\nStarting server on http://0.0.0.0:5001")
    print("For Android emulator, use: http://10.0.2.2:5001")
    print("\nEndpoints:")
    print("  GET /health          - Check server status")
    print("  GET /me              - Get current user info")
    print("  GET /channels        - Get all joined channels")
    print("  GET /channel/<id>/images - Get images from a channel")
    print("  GET /download/<channel>/<msg_id> - Download an image")
    print("  GET /file/<file_id>  - Download file by file_id")
    print("  GET /search?q=<query> - Search for channels")
    print("=" * 60)
    
    # Initialize the background loop before starting Flask
    get_loop()
    
    app.run(host='0.0.0.0', port=5001, debug=False, threaded=True)
