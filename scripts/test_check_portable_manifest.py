"""
Each portal rule, fed the one manifest that breaks it. A rule with no failing
case here is a rule that may be a no-op — which is how the jq version of the
review-case check passed an empty case for as long as it existed.
"""

from __future__ import annotations

import copy
import json
import shutil
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from check_portable_manifest import ENDPOINT, check

ROOT = Path(__file__).resolve().parent.parent / "plugin"


def png(side: int, width: int | None = None) -> bytes:
    """A valid, tiny, black PNG of the given size."""
    w, h = width or side, side

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    raw = b"".join(b"\x00" + b"\x00" * w for _ in range(h))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def case(**overrides) -> dict:
    base = {
        "description": "A scenario.",
        "prompt": "Do the thing.",
        "tools_triggered": "whoami",
        "expected_behavior": "Calls whoami.",
    }
    base.update(overrides)
    return base


def manifest() -> dict:
    return {
        "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
        "name": "gagarin",
        "version": "1.0.0",
        "extensions": {
            "com.openai": {
                "onboardingSkill": "./skills/setup/SKILL.md",
                "interface": {
                    "displayName": "Gagarin Cloud",
                    "shortDescription": "Your agent ships the app",
                    "longDescription": "Long enough.",
                    "developerName": "Gagarin Cloud",
                    "category": "Developer Tools",
                    "capabilities": ["Read", "Write"],
                    "websiteURL": "https://gagarin.cloud",
                    "supportURL": "https://gagarin.cloud/docs",
                    "privacyPolicyURL": "https://gagarin.cloud/privacy",
                    "termsOfServiceURL": "https://gagarin.cloud/terms",
                    "defaultPrompt": ["Is my project up?"],
                    "brandColor": "#0b4fd1",
                    "composerIcon": "./assets/icon.png",
                    "logo": "./assets/logo.png",
                },
                "review": {
                    "test_cases": {
                        "positive": [case() for _ in range(5)],
                        "negative": [case() for _ in range(3)],
                    },
                    "demo_recording_url": "https://example.com/demo",
                    "commerce": False,
                },
            }
        },
    }


def servers() -> dict:
    return {
        "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
        "mcpServers": {"gagarin": {"type": "streamable-http", "url": ENDPOINT}},
    }


class Fixture:
    """A minimal valid plugin folder in a temporary directory."""

    def __init__(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "skills" / "setup").mkdir(parents=True)
        (self.dir / "skills" / "setup" / "SKILL.md").write_text("---\nname: setup\n---\n")
        (self.dir / "assets").mkdir()
        (self.dir / "assets" / "icon.png").write_bytes(png(64))
        (self.dir / "assets" / "logo.png").write_bytes(png(256))
        self.manifest = manifest()
        self.servers = servers()

    def write(self) -> Path:
        (self.dir / "plugin.json").write_text(json.dumps(self.manifest))
        (self.dir / "mcp.json").write_text(json.dumps(self.servers))
        return self.dir

    @property
    def oai(self) -> dict:
        return self.manifest["extensions"]["com.openai"]

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class PortalRules(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()
        self.addCleanup(self.f.cleanup)

    def errors(self) -> list[str]:
        return check(self.f.write())

    def assertRefused(self, fragment: str):
        errors = self.errors()
        self.assertTrue(any(fragment in e for e in errors), f"expected a refusal mentioning {fragment!r}, got {errors}")

    def test_the_fixture_itself_passes(self):
        self.assertEqual(self.errors(), [])

    def test_the_real_plugin_passes(self):
        self.assertEqual(check(ROOT), [])

    def test_an_empty_review_case_is_refused(self):
        # The jq version let exactly this through.
        self.f.oai["review"]["test_cases"]["positive"][0] = {
            "description": "",
            "prompt": None,
            "tools_triggered": "",
            "expected_behavior": "",
        }
        errors = self.errors()
        for key in ("description", "prompt", "tools_triggered", "expected_behavior"):
            self.assertTrue(any(f"positive case 1 needs a non-empty {key}" == e for e in errors), errors)

    def test_a_negative_case_without_a_prompt_is_refused(self):
        self.f.oai["review"]["test_cases"]["negative"][2] = {"description": "x"}
        self.assertRefused("negative case 3 needs a non-empty prompt")

    def test_four_positive_cases_are_refused(self):
        del self.f.oai["review"]["test_cases"]["positive"][0]
        self.assertRefused("exactly five positive")

    def test_two_negative_cases_are_refused(self):
        del self.f.oai["review"]["test_cases"]["negative"][0]
        self.assertRefused("exactly three negative")

    def test_commerce_must_be_false(self):
        self.f.oai["review"]["commerce"] = True
        self.assertRefused("commerce must be false")

    def test_demo_url_must_be_https(self):
        self.f.oai["review"]["demo_recording_url"] = "http://example.com"
        self.assertRefused("demo_recording_url")

    def test_hooks_directory_is_refused(self):
        (self.f.dir / "hooks").mkdir()
        self.assertRefused("hooks exists")

    def test_app_reference_is_refused(self):
        (self.f.dir / ".app.json").write_text("{}")
        self.assertRefused(".app.json exists")
        self.f.oai["apps"] = "./.app.json"
        self.assertRefused("must not declare apps")

    def test_hooks_key_is_refused(self):
        self.f.oai["hooks"] = "./hooks/hooks.json"
        self.assertRefused("must not declare hooks")

    def test_missing_onboarding_skill_is_refused(self):
        self.f.oai["onboardingSkill"] = "./skills/nope/SKILL.md"
        self.assertRefused("does not exist")

    def test_display_name_over_thirty_is_refused(self):
        self.f.oai["interface"]["displayName"] = "x" * 31
        self.assertRefused("displayName must be 1 to 30")

    def test_long_description_over_limit_is_refused(self):
        self.f.oai["interface"]["longDescription"] = "x" * 4001
        self.assertRefused("longDescription must be 1 to 4000")

    def test_http_url_is_refused(self):
        self.f.oai["interface"]["privacyPolicyURL"] = "http://gagarin.cloud/privacy"
        self.assertRefused("privacyPolicyURL must be an https")

    def test_empty_default_prompt_is_refused(self):
        self.f.oai["interface"]["defaultPrompt"] = [""]
        self.assertRefused("defaultPrompt")

    def test_bad_brand_colour_is_refused(self):
        self.f.oai["interface"]["brandColor"] = "blue"
        self.assertRefused("brandColor")

    def test_icon_outside_assets_is_refused(self):
        self.f.oai["interface"]["logo"] = "./.claude-plugin/icon.png"
        self.assertRefused("must live under ./assets/")

    def test_non_png_icon_is_refused(self):
        (self.f.dir / "assets" / "icon.png").write_text("not a png")
        self.assertRefused("is not a PNG")

    def test_non_square_icon_is_refused(self):
        (self.f.dir / "assets" / "icon.png").write_bytes(png(64, width=96))
        self.assertRefused("not square")

    def test_tiny_icon_is_refused(self):
        (self.f.dir / "assets" / "icon.png").write_bytes(png(32))
        self.assertRefused("not 48 to 4096")

    def test_forbidden_keys_are_refused(self):
        self.f.oai["review"]["test_credentials"] = {"user": "x"}
        self.assertRefused("test_credentials")

    def test_credential_shaped_string_is_refused(self):
        self.f.oai["review"]["test_cases"]["positive"][0]["expected_behavior"] = "send Bearer abcdefghijkl"
        self.assertRefused("credential-shaped")

    def test_headers_on_the_server_are_refused(self):
        self.f.servers["mcpServers"]["gagarin"]["headers"] = {"Authorization": "x"}
        self.assertRefused("must not carry headers")

    def test_wrong_endpoint_is_refused(self):
        self.f.servers["mcpServers"]["gagarin"]["url"] = "https://example.com/mcp"
        self.assertRefused("does not point at")

    def test_two_servers_are_refused(self):
        self.f.servers["mcpServers"]["other"] = copy.deepcopy(self.f.servers["mcpServers"]["gagarin"])
        self.assertRefused("exactly one server")

    def test_sse_transport_is_refused(self):
        self.f.servers["mcpServers"]["gagarin"]["type"] = "sse"
        self.assertRefused("streamable-http")


if __name__ == "__main__":
    unittest.main()
