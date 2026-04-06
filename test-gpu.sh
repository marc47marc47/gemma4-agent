#!/bin/sh
curl -s http://127.0.0.1:8089/props 2>/dev/null | python -m json.tool 2>/dev/null || curl -s http://127.0.0.1:8089/props
