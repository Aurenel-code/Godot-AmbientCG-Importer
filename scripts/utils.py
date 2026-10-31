import subprocess
import urllib.request
import json
import tarfile
import os
import shutil

# Pinned GUT release used for unit tests. Bump deliberately.
GUT_VERSION = "v9.7.1"

def get_godot_command():
    # Try environment variable first
    env_godot = os.environ.get("GODOT")
    if env_godot:
        if os.path.exists(env_godot):
            return os.path.abspath(env_godot)
        
        found = shutil.which(env_godot)
        if found:
            return found

    # Try 'godot' in PATH
    found = shutil.which("godot")
    if found:
        return found
    
    return "godot"

def run_command(command, description):
    if command and command[0] == "godot":
        command[0] = get_godot_command()

    print(f"=== {description} ===")
    
    try:
        subprocess.run(command, check=True, text=True)
        return True
    except subprocess.CalledProcessError:
        print(f"\nError during {description}!")
        return False
    except FileNotFoundError:
        print(f"\nError: Executable '{command[0]}' not found.")
        return False

def get_latest_godot_version():
    fallback = "4.3"
    token = os.environ.get("GITHUB_TOKEN")
    url = "https://api.github.com/repos/godotengine/godot/releases/latest"
    req = urllib.request.Request(url)
    if token:
        req.add_header("Authorization", f"token {token}")
    
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            return data["tag_name"].replace("-stable", "")
    except Exception as e:
        print(f"Warning: Failed to fetch latest Godot version ({e}). Using fallback: {fallback}")
        return fallback

def ensure_gut():
    if os.path.exists("addons/gut"):
        return False
    print(f"=== Downloading GUT {GUT_VERSION} ===")

    tarball_url = f"https://api.github.com/repos/bitwes/Gut/tarball/{GUT_VERSION}"
    try:
        file_path, _ = urllib.request.urlretrieve(tarball_url)
    except Exception as e:
        print(f"Error: Failed to download GUT {GUT_VERSION} ({e}).")
        return False

    with tarfile.open(file_path, "r:gz") as tar:
        for member in tar.getmembers():
            parts = member.name.split("/")
            if len(parts) < 3 or parts[1:3] != ["addons", "gut"]:
                continue
            if not (member.isfile() or member.isdir()):
                continue
            member.name = "/".join(parts[1:])
            if os.path.isabs(member.name) or ".." in member.name.split("/"):
                continue
            tar.extract(member, path=".")
    os.remove(file_path)
    return True

def clean_project():
    paths = ["AmbientCG", ".godot"]
    for path in paths:
        if os.path.exists(path):
            shutil.rmtree(path)
            print(f"Removed: {path}")
