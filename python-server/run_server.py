"""
Run the FastAPI server with safe defaults for local testing.
By default the server listens on 127.0.0.1 (local-only). Pass the `--allow-remote`
CLI flag to bind to 0.0.0.0 and allow other devices on the same network to connect.
"""
import os
import socket
import argparse
import uvicorn
from backend import config as srv_cfg

def get_local_ip():
    """Get the local IP address of this machine."""
    try:
        # Create a socket to find the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Connect to an external address (doesn't actually send data)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "Unable to detect"

if __name__ == "__main__":
    local_ip = get_local_ip()
    
    print("\n" + "="*60)
    print("Starting Photo Organizer API Server")
    print("="*60)
    print(f"Local IP: {local_ip}")
    print("Server URLs:")
    print(f"   - Localhost:        http://127.0.0.1:8000")
    print(f"   - Local Network:    http://{local_ip}:8000")
    print(f"   - Android Emulator: http://10.0.2.2:8000")
    print(f"   - iOS Simulator:    http://localhost:8000")
    print('\nFor physical devices, use: http://{local_ip}:8000')
    print("   (Make sure device is on same WiFi network)")
    print("="*60 + "\n")
    
    parser = argparse.ArgumentParser(description="Start the Photo Organizer API server with options")
    parser.add_argument("--host", type=str, default=None,
                        help="Host to bind; default 127.0.0.1 unless --allow-remote is set")
    parser.add_argument("--allow-remote", action="store_true", help="If set, bind to 0.0.0.0 (LAN reachable)")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind")
    parser.add_argument("--allow-origins", type=str, default=None, help="Comma-separated list of CORS origins to allow")
    parser.add_argument("--reload", action="store_true", help="Enable uvicorn reload")
    parser.add_argument("--no-reload", action="store_true", help="Disable uvicorn reload")
    parser.add_argument("--upload-token", type=str, default=None, help="Optional upload token that the server requires")
    parser.add_argument("--persist-uploads", action="store_true", help="If set, do not remove uploaded files after processing")
    args = parser.parse_args()

    if args.allow_remote:
        host = "0.0.0.0"
    elif args.host:
        host = args.host
    else:
        host = "127.0.0.1"

    # Set values into backend.config so the FastAPI code uses them
    srv_cfg.ALLOW_REMOTE = args.allow_remote
    srv_cfg.UPLOAD_TOKEN = args.upload_token
    srv_cfg.PERSIST_UPLOADS = args.persist_uploads
    srv_cfg.ALLOW_ORIGINS = args.allow_origins
    # Reload: prefer --reload/--no-reload, default True for dev but can be disabled
    srv_cfg.RELOAD = True
    if args.no_reload:
        srv_cfg.RELOAD = False
    if args.reload:
        srv_cfg.RELOAD = True

    uvicorn.run(
        "backend.backend_api:app",
        host=host,
        port=args.port,
        reload=srv_cfg.RELOAD,
        log_level="info"
    )
