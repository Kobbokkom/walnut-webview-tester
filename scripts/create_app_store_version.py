#!/usr/bin/env python3
"""
App Store Connect API - Create New Version (Auto-Release)
Creates a new App Store version with automatic release after approval.
"""

import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

import jwt
import requests

# Configuration
BUNDLE_ID = "com.kobbokkom.wina"
ISSUER_ID = "a7524762-b1db-463b-84a8-bbee51a37cc2"
KEY_ID = "74HC92L9NA"
PRIVATE_KEY_PATH = Path("/Users/semanticist/Documents/API/AuthKey_74HC92L9NA.p8")
BASE_URL = "https://api.appstoreconnect.apple.com/v1"


def generate_token():
    private_key = PRIVATE_KEY_PATH.read_text()
    now = datetime.now(timezone.utc)
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + timedelta(minutes=20),
        "aud": "appstoreconnect-v1"
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})


def get_headers():
    return {
        "Authorization": f"Bearer {generate_token()}",
        "Content-Type": "application/json"
    }


def get_app_id():
    print("Looking for app...")
    resp = requests.get(f"{BASE_URL}/apps", headers=get_headers(), params={"filter[bundleId]": BUNDLE_ID})
    resp.raise_for_status()
    data = resp.json()
    if not data["data"]:
        raise ValueError(f"App not found: {BUNDLE_ID}")
    app_id = data["data"][0]["id"]
    app_name = data["data"][0]["attributes"]["name"]
    print(f"Found: {app_name} (ID: {app_id})")
    return app_id


def get_existing_versions(app_id):
    print("\nExisting versions:")
    resp = requests.get(
        f"{BASE_URL}/apps/{app_id}/appStoreVersions",
        headers=get_headers(),
        params={"filter[platform]": "IOS", "limit": 5}
    )
    resp.raise_for_status()
    for v in resp.json()["data"]:
        state = v["attributes"]["appStoreState"]
        version = v["attributes"]["versionString"]
        release_type = v["attributes"].get("releaseType", "N/A")
        print(f"   {version}: {state} (releaseType: {release_type})")
    return resp.json()["data"]


def create_new_version(app_id, version_string, release_type="AFTER_APPROVAL"):
    """
    Create a new App Store version.

    release_type options:
    - AFTER_APPROVAL: Auto-release after review approval
    - MANUAL: Manual release (PENDING_DEVELOPER_RELEASE)
    - SCHEDULED: Release at scheduled date
    """
    print(f"\nCreating version {version_string} (releaseType: {release_type})...")

    resp = requests.post(
        f"{BASE_URL}/appStoreVersions",
        headers=get_headers(),
        json={
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": "IOS",
                    "versionString": version_string,
                    "releaseType": release_type,
                    "copyright": f"Copyright {datetime.now().year} Semanticist"
                },
                "relationships": {
                    "app": {
                        "data": {"type": "apps", "id": app_id}
                    }
                }
            }
        }
    )

    if resp.status_code in [200, 201]:
        version_id = resp.json()["data"]["id"]
        print(f"Version {version_string} created! (ID: {version_id})")
        return version_id
    else:
        print(f"Failed: {resp.status_code}")
        print(resp.text)
        return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Create new App Store version')
    parser.add_argument('version', help='Version string (e.g., 1.8.4)')
    parser.add_argument('--manual', action='store_true', help='Use manual release instead of auto-release')
    args = parser.parse_args()

    release_type = "MANUAL" if args.manual else "AFTER_APPROVAL"

    print("=" * 60)
    print("App Store Connect - Create New Version")
    print(f"Bundle ID: {BUNDLE_ID}")
    print(f"Release Type: {release_type}")
    print("=" * 60)

    try:
        app_id = get_app_id()
        get_existing_versions(app_id)
        version_id = create_new_version(app_id, args.version, release_type)

        if version_id:
            print("\n" + "=" * 60)
            print("SUCCESS!")
            print(f"Version {args.version} created with {release_type}")
            print("=" * 60)
            return 0
        return 1

    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
