import os
import subprocess
import glob
import shutil
import requests
from flask import Flask, render_template, request, jsonify, send_from_directory, Response

app = Flask(__name__)
STORAGE_PATH = "/export/media/skycam"
METEOR_PATH = "/export/media/meteors"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def is_file_being_written(filename):
    target = os.path.realpath(filename)
    for fd_path in glob.glob('/proc/*/fd/*'):
        try:
            if os.path.realpath(fd_path) == target:
                parts = fd_path.split('/')
                pid, fd_num = parts[2], parts[4]
                info_path = f"/proc/{pid}/fdinfo/{fd_num}"
                with open(info_path, 'r') as f:
                    for line in f:
                        if line.startswith('flags:'):
                            flags_oct = int(line.split()[1], 8)
                            if (flags_oct & 3) in [1, 2]:
                                return True
        except (OSError, FileNotFoundError, ValueError):
            continue
    return False

@app.route('/')
def index():
    return render_template('index.html')

# --- PROXIES (To bypass CORS security) ---

@app.route('/stream_proxy')
def stream_proxy():
    url = "http://camera.ip/flv?port=1935&app=bcs&stream=channel0_main.bcs&user=admin&password=password"
    def generate():
        try:
            r = requests.get(url, stream=True, timeout=10)
            for chunk in r.iter_content(chunk_size=1024 * 32):
                if chunk:
                    yield chunk
        except Exception as e:
            print(f"Stream Proxy Error: {e}")
    return Response(generate(), mimetype='video/x-flv')

@app.route('/snap_proxy')
def snap_proxy():
    url = "http://camera.ip/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=1&user=admin&password=password&width=3840&height=2160"
    try:
        r = requests.get(url, timeout=10)
        return Response(r.content, mimetype='image/jpeg')
    except Exception as e:
        return jsonify({"status": f"Snap Error: {str(e)}"}), 500

# --- CAPTURE CONTROLS ---

@app.route('/start', methods=['POST'])
def start():
    hours = request.json.get('hours', 1)
    subprocess.Popen(['/bin/bash', os.path.join(SCRIPT_DIR, 'skycamcapture.sh'), str(hours)])
    return jsonify({"status": "Recording started"})

@app.route('/autodetect', methods=['POST'])
def autodetect():
    hours = request.json.get('hours', 1)
    subprocess.Popen(['/bin/bash', os.path.join(SCRIPT_DIR, 'skycamcapture.sh'), str(hours), "auto-detect-meteors"])
    return jsonify({"status": "AUTO-DETECT-METEORS: Recording started"})

@app.route('/stop', methods=['POST'])
def stop():
    subprocess.run(['pkill', '-f', 'skycamcapture.sh'])
    return jsonify({"status": "Stopped"})

@app.route('/stop_all', methods=['POST'])
def stop_all():
# 1. Send SIGUSR1 to skycamcapture to tell it NOT to start the pipeline
    subprocess.run(['pkill', '-USR1', '-f', 'skycamcapture.sh'])
    # 2. Kill everything else normally
    for proc in ['pipeline.sh', 'MetDetPy.py', 'ClipToolkit.py']:
        subprocess.run(['pkill', '-f', proc])
    return jsonify({"status": "ALL CAPTURE AND PIPELINES TERMINATED"})

# --- LOGS & PROCESSING ---

@app.route('/log')
def get_log():
    log_path = os.path.join(STORAGE_PATH, 'pipeline.log')
    if os.path.exists(log_path):
        with open(log_path, 'r') as f: return f.read()
    return "Log file not found."

@app.route('/log', methods=['DELETE'])
def delete_log():
    log_path = os.path.join(STORAGE_PATH, 'pipeline.log')
    if os.path.exists(log_path):
        os.remove(log_path)
        return jsonify({"status": "Log deleted"})
    return jsonify({"status": "Log not found"}), 404

@app.route('/timelapse/<path:filename>', methods=['POST'])
def trigger_timelapse(filename):
    parts = filename.split('/')
    full_path = os.path.join(STORAGE_PATH, "/".join(parts[1:]))
    subprocess.Popen(['/bin/bash', os.path.join(SCRIPT_DIR, 'timelapse.sh'), full_path])
    return jsonify({"status": "Timelapse started"})

@app.route('/transcode/<path:filename>', methods=['POST'])
def trigger_transcode(filename):
    parts = filename.split('/')
    full_path = os.path.join(STORAGE_PATH, "/".join(parts[1:]))
    subprocess.Popen(['/bin/bash', os.path.join(SCRIPT_DIR, 'transcode_720p.sh'), full_path])
    return jsonify({"status": "720p Transcode started"})

@app.route('/concat/<folder>', methods=['POST'])
def concat_meteors(folder):
    folder_path = os.path.join(METEOR_PATH, folder)
    if not os.path.exists(folder_path): return jsonify({"status": "Folder not found"}), 404
    files = sorted([f for f in os.listdir(folder_path) if f.endswith('.mp4') and '_meteors.mp4' not in f])
    if not files: return jsonify({"status": "No clips found"}), 400
    output_path = os.path.join(folder_path, f"{folder}_meteors.mp4")
    list_file = os.path.join(folder_path, "files.txt")
    try:
        with open(list_file, 'w') as f:
            for file in files: f.write(f"file '{file}'\n")
        subprocess.run(['ffmpeg', '-y', '-f', 'concat', '-safe', '0', '-i', list_file, '-c', 'copy', output_path], check=True)
        os.remove(list_file)
        subprocess.run(['chown', '1000:1000', output_path])
        return jsonify({"status": "Concatenation complete"})
    except Exception as e:
        return jsonify({"status": f"Error: {str(e)}"}), 500

# --- NAVIGATION & DELETION ---

@app.route('/folders')
def list_folders():
    sc = [{"name": f, "type": "skycam"} for f in os.listdir(STORAGE_PATH) if os.path.isdir(os.path.join(STORAGE_PATH, f))]
    met = [{"name": f, "type": "meteors"} for f in os.listdir(METEOR_PATH) if os.path.isdir(os.path.join(METEOR_PATH, f))]
    return jsonify(sorted(sc + met, key=lambda x: x['name'], reverse=True))

@app.route('/files/<type>/<folder>')
def list_files(type, folder):
    base = STORAGE_PATH if type == "skycam" else METEOR_PATH
    folder_path = os.path.join(base, folder)
    files = []
    if os.path.exists(folder_path):
        for f in sorted(os.listdir(folder_path), reverse=True):
            if f.lower().endswith(('.mp4', '.avi')):
                full_path = os.path.join(folder_path, f)
                is_busy = is_file_being_written(full_path)
                status = "IDLE"
                if is_busy:
                    if "_tl.mp4" in f: status = "TIMELAPSE"
                    elif "_720p.mp4" in f: status = "720P"
                    else: status = "RECORDING"
                files.append({"name": f, "path": f"{type}/{folder}/{f}", "status": status, "type": type})
    return jsonify(files)

@app.route('/video/<path:filename>')
def serve_video(filename):
    parts = filename.split('/')
    base = STORAGE_PATH if parts[0] == "skycam" else METEOR_PATH
    return send_from_directory(base, "/".join(parts[1:]))

@app.route('/delete/<path:filename>', methods=['DELETE'])
def delete_file(filename):
    parts = filename.split('/')
    base = STORAGE_PATH if parts[0] == "skycam" else METEOR_PATH
    file_path = os.path.join(base, "/".join(parts[1:]))
    if os.path.exists(file_path):
        os.remove(file_path)
        return jsonify({"status": "Deleted"})
    return jsonify({"status": "File not found"}), 404

@app.route('/delete_folder/<type>/<folder>', methods=['DELETE'])
def delete_folder(type, folder):
    base = STORAGE_PATH if type == "skycam" else METEOR_PATH
    folder_path = os.path.join(base, folder)
    if os.path.exists(folder_path):
        shutil.rmtree(folder_path)
        return jsonify({"status": "Folder deleted"})
    return jsonify({"status": "Not found"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5050)
