#!/bin/bash
# Simple HTTP server for Godot HTML5 export
# Serves on http://localhost:8080

echo "Starting HTTP server for BiologiDex client..."
echo "Access the app at: http://localhost:8080"
echo "Press Ctrl+C to stop"
echo ""

# Use Python's built-in HTTP server
python3 -m http.server 8080
