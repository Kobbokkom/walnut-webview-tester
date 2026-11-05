"""Exercise screenshot replacement without App Store Connect access."""

import runpy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


class ScreenshotReplacementTests(unittest.TestCase):
    def setUp(self):
        requests = SimpleNamespace(RequestException=OSError, put=Mock(return_value=self.response(200)))
        with patch.dict("sys.modules", {"requests": requests, "jwt": SimpleNamespace()}):
            script = runpy.run_path(str(Path(__file__).with_name("upload-screenshots-api.py")))
        self.replace = script["replace_screenshots"]
        self.error = script["ScreenshotUploadError"]
        self.globals = self.replace.__globals__
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "new.png"
        self.path.write_bytes(b"new screenshot")
        self.assets = ["original"]
        self.deleted = []
        self.reservations = 0
        self.delivery_state = "COMPLETE"
        self.commit_status = 200
        self.globals["api_request"] = self.api_request

    @staticmethod
    def response(status, **body):
        return SimpleNamespace(status_code=status, json=lambda: body)

    def api_request(self, method, endpoint, data=None):
        if method == "GET" and endpoint.startswith("/appScreenshotSets/"):
            return self.response(200, data=[{"id": asset} for asset in self.assets])
        if method == "POST":
            self.reservations += 1
            asset = f"new-{self.reservations}"
            self.assets.append(asset)
            return self.response(201, data={
                "id": asset,
                "attributes": {"uploadOperations": [
                    {"url": "test://upload", "offset": 0, "length": 14, "requestHeaders": []}
                ]}
            })
        if method == "PATCH":
            return self.response(self.commit_status)
        if method == "GET":
            self.assertIn("original", self.assets)
            return self.response(200, data={"attributes": {"assetDeliveryState": {"state": self.delivery_state}}})
        if method == "DELETE":
            asset = endpoint.rsplit("/", 1)[-1]
            self.deleted.append(asset)
            self.assets.remove(asset)
            return self.response(204)
        self.fail(f"Unexpected request: {method} {endpoint}")

    def test_commit_failure_cleans_only_staged_asset(self):
        self.commit_status = 500
        with self.assertRaisesRegex(self.error, "Upload failed"):
            self.replace("set", [self.path])
        self.assertEqual(self.assets, ["original"])
        self.assertEqual(self.deleted, ["new-1"])

    def test_processing_failure_cleans_only_staged_asset(self):
        self.delivery_state = "FAILED"
        with self.assertRaisesRegex(self.error, "Processing"):
            self.replace("set", [self.path])
        self.assertEqual(self.assets, ["original"])
        self.assertEqual(self.deleted, ["new-1"])

    def test_interruption_cleans_only_staged_asset(self):
        self.globals["wait_for_screenshots"] = Mock(side_effect=KeyboardInterrupt)
        with self.assertRaises(KeyboardInterrupt):
            self.replace("set", [self.path])
        self.assertEqual(self.assets, ["original"])
        self.assertEqual(self.deleted, ["new-1"])

    def test_success_replaces_original_after_processing(self):
        self.replace("set", [self.path])
        self.assertEqual(self.assets, ["new-1"])
        self.assertEqual(self.deleted, ["original"])

    def test_full_set_remains_untouched(self):
        self.assets = [str(index) for index in range(10)]
        with self.assertRaisesRegex(self.error, "free slots"):
            self.replace("set", [self.path])
        self.assertEqual(self.reservations, 0)
        self.assertEqual(self.deleted, [])

    def test_locale_failure_returns_nonzero_exit_status(self):
        self.globals.update(
            SCREENSHOTS_DIR=self.path.parent,
            get_app_store_version=lambda: ("version", "1.0", "PREPARE_FOR_SUBMISSION"),
            get_localizations=lambda _: {"en": "localization"},
            process_locale=lambda *_: (0, 0, "Upload failed"),
        )
        with patch("sys.stdout"):
            self.assertEqual(self.globals["main"](), 1)


if __name__ == "__main__":
    unittest.main()
