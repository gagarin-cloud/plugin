"""
What OpenAI's plugin portal requires of plugin.json and mcp.json, as rules a
test can feed a bad manifest to.

check.sh used to hold these as jq programs quoted inside bash strings, and one
of them — the review-case completeness check — turned out to be a no-op that
passed an empty case, because `|` binds loosest in jq and nothing ever fed it a
bad case. The rules live here now, where test_check_portable_manifest.py does
exactly that to each of them.

The limits and refusals are the portal's own: displayName and shortDescription
at most 30 characters, longDescription at most 4000, icons square and 48 to
4096 px and under 5 MiB, exactly five positive and three negative review cases,
HTTPS everywhere, and a package that holds no hooks, app references, server
headers or credentials. Schema validation stays in check.sh, where ajv is.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ENDPOINT = "https://mcp.gagarin.cloud/mcp"

INTERFACE_URLS = ("websiteURL", "supportURL", "privacyPolicyURL", "termsOfServiceURL")
FORBIDDEN_KEYS = ("test_credentials", "reviewer_instructions", "clientSecret", "client_secret")
CREDENTIAL_SHAPED = re.compile(r'bearer [A-Za-z0-9_-]{8,}|"authorization"', re.IGNORECASE)
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def png_dims(path: Path):
    """(width, height) of a PNG, or None when the file is not one."""
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != PNG_MAGIC or len(head) < 24:
        return None
    return struct.unpack(">II", head[16:24])


def nonempty(value) -> bool:
    return isinstance(value, str) and value != ""


def https(value) -> bool:
    return isinstance(value, str) and value.startswith("https://")


def check(root: Path, endpoint: str = ENDPOINT) -> list[str]:
    """Every rule the plugin folder at `root` breaks, as one sentence each."""
    errors: list[str] = []
    portable = root / "plugin.json"
    mcp = root / "mcp.json"

    try:
        manifest = json.loads(portable.read_text())
        servers = json.loads(mcp.read_text())
    except (OSError, ValueError) as e:
        return [f"cannot read the portable manifests: {e}"]

    # The package: a ZIP carrying app references or lifecycle hooks cannot be
    # submitted at all, and these are the shapes they take.
    for name in ("hooks", ".app.json", ".codex-plugin"):
        if (root / name).exists():
            errors.append(
                f"{name} exists; hooks and app references make the plugin ineligible for the "
                "directory, and a .codex-plugin overlay is ignored once extensions.com.openai is set"
            )
    oai = manifest.get("extensions", {}).get("com.openai")
    if not isinstance(oai, dict):
        return errors + ["plugin.json has no extensions.com.openai object"]
    for key in ("apps", "hooks"):
        if key in oai:
            errors.append(f"extensions.com.openai must not declare {key}")

    # The onboarding skill runs after installation; it must be one of ours.
    onboarding = oai.get("onboardingSkill")
    if not nonempty(onboarding):
        errors.append("extensions.com.openai.onboardingSkill is missing")
    elif not (root / onboarding.removeprefix("./")).is_file():
        errors.append(f"onboardingSkill {onboarding} does not exist")

    # The listing.
    iface = oai.get("interface")
    if not isinstance(iface, dict):
        errors.append("extensions.com.openai.interface is missing")
        iface = {}
    for key in ("displayName", "shortDescription"):
        n = len(iface.get(key) or "")
        if not 1 <= n <= 30:
            errors.append(f"interface.{key} must be 1 to 30 characters (is {n})")
    n = len(iface.get("longDescription") or "")
    if not 1 <= n <= 4000:
        errors.append(f"interface.longDescription must be 1 to 4000 characters (is {n})")
    for key in ("developerName", "category"):
        if not nonempty(iface.get(key)):
            errors.append(f"interface.{key} is missing")
    for key in INTERFACE_URLS:
        if not https(iface.get(key)):
            errors.append(f"interface.{key} must be an https:// URL")
    prompts = iface.get("defaultPrompt")
    if not (isinstance(prompts, list) and prompts and all(nonempty(p) for p in prompts)):
        errors.append("interface.defaultPrompt must be a non-empty array of strings")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", iface.get("brandColor") or ""):
        errors.append("interface.brandColor must be a #rrggbb colour")
    caps = iface.get("capabilities")
    if not (isinstance(caps, list) and caps):
        errors.append("interface.capabilities must be a non-empty array")
    for key in ("composerIcon", "logo"):
        img = iface.get(key)
        if not nonempty(img):
            errors.append(f"interface.{key} is missing")
            continue
        if not img.startswith("./assets/"):
            errors.append(f"interface.{key} must live under ./assets/ (is {img})")
            continue
        path = root / img.removeprefix("./")
        if not path.is_file():
            errors.append(f"{key} {img} does not exist")
            continue
        dims = png_dims(path)
        if dims is None:
            errors.append(f"{key} {img} is not a PNG")
            continue
        w, h = dims
        if w != h:
            errors.append(f"{key} is {w}x{h}, not square")
        if not 48 <= w <= 4096:
            errors.append(f"{key} is {w} px a side, not 48 to 4096")
        if path.stat().st_size >= 5 * 1024 * 1024:
            errors.append(f"{key} is 5 MiB or more")

    # Review material: exactly five positive and three negative cases, each
    # with a description and a prompt, the positives with the tools they
    # trigger and the behaviour expected.
    review = oai.get("review")
    if not isinstance(review, dict):
        errors.append("extensions.com.openai.review is missing")
        review = {}
    cases = review.get("test_cases") or {}
    positive = cases.get("positive") or []
    negative = cases.get("negative") or []
    if len(positive) != 5:
        errors.append(f"review needs exactly five positive test cases (has {len(positive)})")
    if len(negative) != 3:
        errors.append(f"review needs exactly three negative test cases (has {len(negative)})")
    for i, case in enumerate(positive):
        for key in ("description", "prompt", "tools_triggered", "expected_behavior"):
            if not nonempty(case.get(key)):
                errors.append(f"positive case {i + 1} needs a non-empty {key}")
    for i, case in enumerate(negative):
        for key in ("description", "prompt"):
            if not nonempty(case.get(key)):
                errors.append(f"negative case {i + 1} needs a non-empty {key}")
    if not https(review.get("demo_recording_url")):
        errors.append("review.demo_recording_url must be an https:// URL")
    if review.get("commerce") is not False:
        errors.append("review.commerce must be false; nothing is sold through the plugin")

    # Nothing credential-shaped in a public package. Reviewer credentials go in
    # the dashboard form, never the ZIP, and the portal rejects the keys it has
    # seen people try.
    texts = {"plugin.json": portable.read_text(), "mcp.json": mcp.read_text()}
    for name, text in texts.items():
        for key in FORBIDDEN_KEYS:
            if f'"{key}"' in text:
                errors.append(f"{name}: '{key}' belongs in the dashboard form, never in the package")
        if CREDENTIAL_SHAPED.search(text):
            errors.append(f"{name}: a credential-shaped string is in a manifest; this repository is public")

    # The endpoint is the one thing a user cannot override: exactly one remote
    # server, over streamable HTTP, with no headers — the portal rejects a
    # nonempty headers object, and a header here would be a credential.
    entries = servers.get("mcpServers")
    if not isinstance(entries, dict) or len(entries) != 1:
        errors.append("mcp.json must declare exactly one server")
    else:
        (server,) = entries.values()
        if server.get("type") != "streamable-http":
            errors.append("mcp.json: the server must be streamable-http")
        if server.get("url") != endpoint:
            errors.append(f"mcp.json does not point at {endpoint}")
        if "headers" in server:
            errors.append("mcp.json must not carry headers; the portal rejects them and one here would be a credential")

    return errors


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "plugin")
    errors = check(root)
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f"  ok  portable manifests fit the portal ({root}/plugin.json, {root}/mcp.json)")


if __name__ == "__main__":
    main()
