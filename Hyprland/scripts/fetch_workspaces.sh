#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# WORKSPACE OVERVIEW DATA FETCHER
# Outputs JSON with all workspaces and their windows for the overview popup
# -----------------------------------------------------------------------------

WORKSPACES=$(hyprctl workspaces -j 2>/dev/null)
CLIENTS=$(hyprctl clients -j 2>/dev/null)
ACTIVE_WS=$(hyprctl activeworkspace -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "1")

python3 << EOF
import json, sys

workspaces = json.loads('''$WORKSPACES''')
clients = json.loads('''$CLIENTS''')
active_id = $ACTIVE_WS

# Build a map of workspace -> windows
ws_windows = {}
for c in clients:
    if c.get('mapped', False) and not c.get('hidden', False):
        ws_id = c['workspace']['id']
        if ws_id not in ws_windows:
            ws_windows[ws_id] = []
        ws_windows[ws_id].append({
            'title': c.get('title', '')[:60],
            'class': c.get('class', ''),
            'floating': c.get('floating', False),
            'fullscreen': c.get('fullscreen', False)
        })

# Output workspace info
result = []
for ws in sorted(workspaces, key=lambda w: w['id']):
    wid = ws['id']
    result.append({
        'id': wid,
        'name': ws.get('name', str(wid)),
        'monitor': ws.get('monitor', ''),
        'windows': ws.get('windows', 0),
        'hasfullscreen': ws.get('hasfullscreen', False),
        'isactive': wid == active_id,
        'windowlist': ws_windows.get(wid, [])
    })

print(json.dumps(result))
EOF
