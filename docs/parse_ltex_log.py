import json
import re
import sys
from collections import defaultdict

def extract_messages(file_path):
    """
    Extracts JSON objects from a log file.
    Handles both 'Content-Length: ... \r\n\r\n {json}' framing 
    and concatenated JSON objects.
    """
    messages = []
    try:
        with open(file_path, 'r', errors='ignore') as f:
            content = f.read()
    except FileNotFoundError:
        return []

    # Find all JSON objects using brace counting
    # This is more robust than regex for nested structures
    start_indices = [m.start() for m in re.finditer(r'\{', content)]
    
    for start in start_indices:
        # Optimization: if this index is already inside a processed message, skip
        if messages and start < messages[-1]['end_pos']:
            continue
            
        brace_count = 0
        end = start
        while end < len(content):
            if content[end] == '{':
                brace_count += 1
            elif content[end] == '}':
                brace_count -= 1
                if brace_count == 0:
                    try:
                        json_str = content[start:end+1]
                        msg = json.loads(json_str)
                        messages.append({
                            'data': msg,
                            'start_pos': start,
                            'end_pos': end + 1
                        })
                        break
                    except json.JSONDecodeError:
                        pass # Keep looking for the closing brace
            end += 1
    return [m['data'] for m in messages]

def analyze_logs(input_log_path, output_log_path):
    """
    Analyzes input and output logs to track requests and responses.
    
    Input Log:  Emacs -> Server
    Output Log: Server -> Emacs
    """
    input_msgs = extract_messages(input_log_path)
    output_msgs = extract_messages(output_log_path)

    # Track Client-initiated requests (Emacs -> Server)
    # ID is in input log (method), response is in output log (result/error)
    client_requests = {} # id -> method
    client_responses = {} # id -> response_data

    # Track Server-initiated requests (Server -> Emacs)
    # ID is in output log (method), response is in input log (result/error)
    server_requests = {} # id -> method
    server_responses = {} # id -> response_data

    # Process Input Log (Emacs -> Server)
    for msg in input_msgs:
        msg_id = msg.get('id')
        if msg_id is None:
            continue
        
        # Responses to server requests (Emacs answering Server)
        if 'result' in msg or 'error' in msg:
            server_responses[str(msg_id)] = msg
        # Requests to server (Emacs asking Server)
        elif 'method' in msg:
            client_requests[str(msg_id)] = msg.get('method')

    # Process Output Log (Server -> Emacs)
    for msg in output_msgs:
        msg_id = msg.get('id')
        if msg_id is None:
            continue

        # Responses to client requests (Server answering Emacs)
        if 'result' in msg or 'error' in msg:
            client_responses[str(msg_id)] = msg
        # Requests to client (Server asking Emacs)
        elif 'method' in msg:
            server_requests[str(msg_id)] = msg.get('method')

    print(f"\nLSP LOG ANALYSIS REPORT")
    print(f"========================")
    print(f"Input Log:  {input_log_path} ({len(input_msgs)} messages)")
    print(f"Output Log: {output_log_path} ({len(output_msgs)} messages)")

    # 1. Check for pending Emacs -> Server requests
    print(f"\n1. CLIENT-INITIATED REQUESTS (Emacs -> Server)")
    print(f"{'-'*60}")
    unresponded_client = []
    for mid, method in client_requests.items():
        if mid not in client_responses:
            unresponded_client.append((mid, method))
    
    if not unresponded_client:
        print("All client requests were responded to.")
    else:
        print(f"Found {len(unresponded_client)} unresponded requests:")
        for mid, method in sorted(unresponded_client, key=lambda x: (len(x[0]), x[0])):
            print(f"  ID: {mid:<10} | Method: {method}")

    # 2. Check for pending Server -> Emacs requests
    print(f"\n2. SERVER-INITIATED REQUESTS (Server -> Emacs)")
    print(f"{'-'*60}")
    unresponded_server = []
    for mid, method in server_requests.items():
        if mid not in server_responses:
            unresponded_server.append((mid, method))
    
    if not unresponded_server:
        print("All server requests were responded to.")
    else:
        print(f"Found {len(unresponded_server)} unresponded requests:")
        for mid, method in sorted(unresponded_server, key=lambda x: (len(x[0]), x[0])):
            print(f"  ID: {mid:<10} | Method: {method}")

    # 3. Check for Server Status messages
    print(f"\n3. SERVER STATUS (isChecking state)")
    print(f"{'-'*60}")
    last_status = None
    for msg in output_msgs:
        if 'result' in msg and isinstance(msg['result'], dict) and 'isChecking' in msg['result']:
            last_status = msg['result']
    
    if last_status:
        print(f"Last known status: isChecking={last_status.get('isChecking')}")
        if last_status.get('documentUriBeingChecked'):
            print(f"Document: {last_status.get('documentUriBeingChecked')}")
    else:
        print("No server status messages found.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        # Default to the paths found in the environment
        in_log = "/tmp/ltex-server-input.log"
        out_log = "/tmp/ltex-server-output.log"
        print(f"Usage: python3 parse_ltex_log.py <input_log> <output_log>")
        print(f"Defaulting to: {in_log} and {out_log}")
    else:
        in_log = sys.argv[1]
        out_log = sys.argv[2]
    
    analyze_logs(in_log, out_log)
