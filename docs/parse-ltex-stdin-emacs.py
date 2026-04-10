import json
import re
import sys
from collections import defaultdict

def parse_lsp_log(file_path):
    """
    Parses an LSP stdin log to find numeric ID collisions between 
    client requests and client responses.
    """
    collisions = defaultdict(list)
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File {file_path} not found.")
        return

    # Extract JSON objects. LSP framing is Content-Length: ... \r\n\r\n {json}
    # We use a non-greedy match for the JSON blocks.
    json_blocks = re.findall(r'\{.*?\}', content, re.DOTALL)
    
    for block in json_blocks:
        try:
            msg = json.loads(block)
            msg_id = msg.get('id')
            if msg_id is None:
                continue
                
            # Standardize ID to string for grouping, but keep original type info
            sid = str(msg_id)
            
            # Identify message direction/kind in the STDIN log:
            # - Has 'method': It's a Request sent FROM Emacs TO Server.
            # - Has 'result'/'error': It's a Response sent FROM Emacs TO Server (answering a server request).
            if 'method' in msg:
                kind = f"REQ: {msg['method']}"
            elif 'result' in msg or 'error' in msg:
                kind = "RESP: (Responding to Server)"
            else:
                kind = "OTHER"
                
            collisions[sid].append({
                'kind': kind,
                'raw_id': msg_id,
                'type': type(msg_id).__name__
            })
        except json.JSONDecodeError:
            continue

    print(f"\nAUDIT REPORT: ID Collisions in {file_path}")
    print(f"{'ID Value':<10} | {'JSON Type':<10} | {'LSP Message Kind'}")
    print("-" * 65)
    
    collision_count = 0
    for sid, instances in sorted(collisions.items(), key=lambda x: (len(x[0]), x[0])):
        # A collision occurs if the same numeric ID is used for more than one message
        if len(instances) > 1:
            collision_count += 1
            for inst in instances:
                print(f"{sid:<10} | {inst['type']:<10} | {inst['kind']}")
            print("-" * 65)
            
    if collision_count == 0:
        print("Success: No ID collisions detected.")
    else:
        print(f"Found {collision_count} unique ID values involved in collisions.")

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ltex-stdin-emacs.log"
    parse_lsp_log(path)
