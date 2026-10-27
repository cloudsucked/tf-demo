#!/usr/bin/env python3
"""Traffic generator for the Petstore Cloudflare API Shield demo.

Generates realistic, schema-compliant API traffic from simulated users and
several kinds of non-compliant traffic (schema violations, JWT abuse, shadow
endpoints, volumetric scraping, and out-of-sequence calls).
"""

import argparse
import base64
import json
import os
import random
import ssl
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

KEY_FILE = Path(__file__).with_name("jwt-private.pem")
REPO_ROOT = Path(__file__).resolve().parents[2]
ZONE_STACK = os.environ.get("ZONE_STACK", "stacks/zones/orangecloud.dev")
KID = "petstore-demo-es256-1"
ISSUER = "petstore-api-shield-demo"
USER_AGENTS = [
    "PetstoreMobile/4.2.1 (iPhone; iOS 19.1)",
    "PetstoreMobile/4.2.0 (Android 16; Pixel 9)",
    "PetstoreWeb/2026.10",
]
PET_STATUSES = ["available", "pending", "sold"]

# Chain and hostname are still verified; strict mode rejects TLS-inspection roots
# (e.g. Cloudflare Zero Trust) that lack the keyUsage extension.
SSL_CONTEXT = ssl.create_default_context()
SSL_CONTEXT.verify_flags &= ~ssl.VERIFY_X509_STRICT

stats = defaultdict(Counter)
stats_lock = threading.Lock()
verbose = False


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def keygen(force: bool) -> None:
    if KEY_FILE.exists() and not force:
        raise SystemExit(f"{KEY_FILE} already exists; use --force to replace it")
    key = ec.generate_private_key(ec.SECP256R1())
    KEY_FILE.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    KEY_FILE.chmod(0o600)
    print_public_key(key)


def print_public_key(key: ec.EllipticCurvePrivateKey) -> None:
    pub = key.public_key().public_numbers()
    print(f"# Add to {ZONE_STACK}/terraform.tfvars")
    print("petstore_jwt_public_key = {")
    print(f'  kid = "{KID}"')
    print(f'  x   = "{b64url(pub.x.to_bytes(32, "big"))}"')
    print(f'  y   = "{b64url(pub.y.to_bytes(32, "big"))}"')
    print("}")


def resolve_base_url(cli_value: str | None) -> str:
    if url := cli_value or os.environ.get("PETSTORE_BASE_URL"):
        return url
    try:
        return subprocess.run(
            ["terraform", f"-chdir={REPO_ROOT / ZONE_STACK}", "output", "-raw", "petstore_url"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        raise SystemExit(f"Set --base-url or PETSTORE_BASE_URL (could not read petstore_url from {ZONE_STACK}: {e})")


def load_key() -> ec.EllipticCurvePrivateKey:
    if not KEY_FILE.exists():
        raise SystemExit(f"{KEY_FILE} not found; run `{Path(__file__).name} keygen` first")
    return serialization.load_pem_private_key(KEY_FILE.read_bytes(), password=None)


def mint(key, sub: str, ttl: int = 3600, kid: str = KID) -> str:
    now = int(time.time())
    claims = {"iss": ISSUER, "aud": "petstore", "sub": sub, "iat": now, "nbf": now, "exp": now + ttl,
              "scope": "read:pets write:pets"}
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": kid})


class Client:
    def __init__(self, base_url: str, scenario: str, token: str | None = None):
        self.base_url = base_url.rstrip("/")
        self.origin = "{0.scheme}://{0.netloc}".format(urllib.parse.urlsplit(self.base_url))
        self.scenario = scenario
        self.token = token
        self.user_agent = random.choice(USER_AGENTS)

    def call(self, method, path, *, params=None, body=None, raw=None, content_type="application/json",
             absolute=False, headers=None):
        url = (self.origin if absolute else self.base_url) + path
        if params:
            url += "?" + urllib.parse.urlencode(params, doseq=True)
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        hdrs = {"Accept": "application/json", "User-Agent": self.user_agent}
        if data is not None:
            hdrs["Content-Type"] = content_type
        if self.token:
            hdrs["Authorization"] = f"Bearer {self.token}"
        hdrs.update(headers or {})
        req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
        ray = "-"
        try:
            with urllib.request.urlopen(req, timeout=15, context=SSL_CONTEXT) as resp:
                status, ray = resp.status, resp.headers.get("cf-ray", "-")
                resp.read()
        except urllib.error.HTTPError as e:
            status, ray = e.code, e.headers.get("cf-ray", "-")
        except (urllib.error.URLError, TimeoutError) as e:
            status = f"ERR:{type(e).__name__}"
        with stats_lock:
            stats[self.scenario][status] += 1
        if verbose:
            print(f"[{self.scenario:<10}] {method:<6} {url.removeprefix(self.origin):<60} -> {status} ({ray})")
        return status


def random_pet(pet_id=None):
    pet_id = pet_id or random.randint(1000, 999999)
    return {
        "id": pet_id,
        "name": random.choice(["doggie", "Rex", "Mittens", "Nemo", "Bella", "Coco"]),
        "category": {"id": 1, "name": random.choice(["Dogs", "Cats", "Fish"])},
        "photoUrls": [f"https://img.example.com/pets/{pet_id}.jpg"],
        "tags": [{"id": 1, "name": "tag1"}],
        "status": random.choice(PET_STATUSES),
    }


def random_order(pet_id=None):
    return {
        "id": random.randint(1000, 999999),
        "petId": pet_id or random.randint(1, 10),
        "quantity": random.randint(1, 3),
        "shipDate": (datetime.now(timezone.utc) + timedelta(days=2)).isoformat(timespec="seconds"),
        "status": "placed",
        "complete": False,
    }


# --- Compliant traffic -------------------------------------------------------

def flow_browse(c):
    c.call("GET", "/pet/findByStatus", params={"status": random.choice(PET_STATUSES)})
    for pet_id in random.sample(range(1, 11), random.randint(1, 3)):
        think()
        c.call("GET", f"/pet/{pet_id}")
    if random.random() < 0.3:
        c.call("GET", "/pet/findByTags", params={"tags": ["tag1", "tag2"]})


def flow_shop(c):
    c.call("GET", "/store/inventory")
    think()
    order = random_order()
    c.call("POST", "/store/order", body=order)
    think()
    c.call("GET", f"/store/order/{order['id']}")


def flow_manage_pet(c):
    pet = random_pet()
    c.call("POST", "/pet", body=pet)
    think()
    pet["status"] = "sold"
    c.call("PUT", "/pet", body=pet)
    think()
    c.call("POST", f"/pet/{pet['id']}", params={"name": pet["name"], "status": "pending"})
    if random.random() < 0.5:
        c.call("DELETE", f"/pet/{pet['id']}")


def flow_account(c, username):
    c.call("GET", "/user/login", params={"username": username, "password": "demo-password"})
    think()
    c.call("GET", f"/user/{username}")
    if random.random() < 0.3:
        c.call("PUT", f"/user/{username}", body={"username": username, "email": f"{username}@example.com",
                                                 "firstName": "Demo", "lastName": "User", "userStatus": 1})
    c.call("GET", "/user/logout")


def think():
    time.sleep(random.uniform(0.3, 2.0))


def run_user(base_url, key, username, stop):
    token, token_exp = None, 0
    while not stop.is_set():
        if time.time() > token_exp - 60:
            token, token_exp = mint(key, username), time.time() + 3600
        c = Client(base_url, "baseline", token)
        flow = random.choices(
            [flow_browse, flow_shop, flow_manage_pet, lambda cl: flow_account(cl, username)],
            weights=[50, 25, 15, 10],
        )[0]
        flow(c)
        stop.wait(random.uniform(1, 5))


def baseline(base_url, key, users):
    stop = threading.Event()
    threads = [threading.Thread(target=run_user, args=(base_url, key, f"user{i}", stop), daemon=True)
               for i in range(1, users + 1)]
    for t in threads:
        t.start()
    return stop, threads


# --- Non-compliant traffic ---------------------------------------------------

def attack_schema(base_url, key):
    c = Client(base_url, "schema", mint(key, "schema-fuzzer"))
    c.call("GET", "/pet/findByStatus", params={"status": "flying"})
    c.call("GET", "/pet/findByStatus")
    c.call("GET", "/pet/not-a-number")
    c.call("POST", "/pet", body={"id": 42, "status": "available"})
    c.call("POST", "/pet", body={**random_pet(), "status": "stolen"})
    c.call("POST", "/pet", body={**random_pet(), "name": 1337, "photoUrls": "not-an-array"})
    c.call("POST", "/pet", raw=b'{"id": 1, "name": "broken', content_type="application/json")
    c.call("POST", "/pet", raw=b"name=Rex", content_type="text/plain")
    c.call("POST", "/store/order", body={**random_order(), "quantity": "lots", "shipDate": "yesterday"})
    c.call("PUT", "/user/user1", body={"username": ["user1"], "userStatus": "active"})


def attack_jwt(base_url, key):
    rogue_key = ec.generate_private_key(ec.SECP256R1())
    header = b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"sub": "admin", "exp": int(time.time()) + 3600}).encode())
    tokens = {
        "missing": None,
        "expired": mint(key, "user1", ttl=-600),
        "forged": mint(rogue_key, "admin"),
        "wrong-kid": mint(key, "user1", kid="unknown-kid"),
        "alg-none": f"{header}.{payload}.",
        "garbage": "not-a-jwt",
    }
    for token in tokens.values():
        c = Client(base_url, "jwt", token)
        c.call("GET", f"/pet/{random.randint(1, 10)}")
        c.call("GET", "/store/inventory")
        c.call("DELETE", f"/pet/{random.randint(1, 10)}")


def attack_shadow(base_url, key):
    c = Client(base_url, "shadow", mint(key, "shadow-explorer"))
    c.call("GET", "/api/v3/admin/users", absolute=True)
    c.call("GET", "/api/v3/pet/1/owner", absolute=True)
    c.call("GET", "/api/v2/pet/1", absolute=True)
    c.call("POST", "/api/v3/user/user1/reset-password", body={"password": "x"}, absolute=True)
    c.call("GET", "/api/internal/metrics", absolute=True)
    c.call("PATCH", "/api/v3/pet/1", body={"status": "sold"}, absolute=True)


def attack_volumetric(base_url, key, requests=150, concurrency=10):
    c = Client(base_url, "volumetric", mint(key, "scraper-bot"))
    with ThreadPoolExecutor(concurrency) as pool:
        list(pool.map(lambda i: c.call("GET", f"/pet/{i % 50 + 1}"), range(requests)))


def attack_sequence(base_url, key, attempts=10):
    for _ in range(attempts):
        c = Client(base_url, "sequence", mint(key, f"impatient-{uuid.uuid4().hex[:8]}"))
        c.call("POST", "/store/order", body=random_order())


ATTACKS = {
    "schema": attack_schema,
    "jwt": attack_jwt,
    "shadow": attack_shadow,
    "volumetric": attack_volumetric,
    "sequence": attack_sequence,
}


def print_summary():
    print("\nScenario     Responses")
    with stats_lock:
        for scenario, counts in sorted(stats.items()):
            print(f"{scenario:<12} " + ", ".join(f"{k}: {v}" for k, v in sorted(counts.items(), key=str)))


def main():
    global verbose
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", help="API base URL (default: $PETSTORE_BASE_URL or the zone stack's petstore_url output)")
    parser.add_argument("-v", "--verbose", action="store_true", help="print every request")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("keygen", help="generate the ES256 signing key and print the public JWK tfvars")
    p.add_argument("--force", action="store_true")
    sub.add_parser("pubkey", help="print the public JWK tfvars for the existing key")

    p = sub.add_parser("baseline", help="compliant traffic from simulated users")
    p.add_argument("--users", type=int, default=8)
    p.add_argument("--duration", type=int, default=300, help="seconds")

    p = sub.add_parser("attack", help="send one burst of non-compliant traffic")
    p.add_argument("kind", choices=[*ATTACKS, "all"])

    p = sub.add_parser("demo", help="baseline traffic with random attack bursts")
    p.add_argument("--users", type=int, default=8)
    p.add_argument("--duration", type=int, default=900, help="seconds")
    p.add_argument("--attack-every", type=int, default=30, help="seconds between attack bursts")

    args = parser.parse_args()
    verbose = args.verbose

    if args.command == "keygen":
        return keygen(args.force)
    key = load_key()
    if args.command == "pubkey":
        return print_public_key(key)
    args.base_url = resolve_base_url(args.base_url)
    print(f"Target: {args.base_url}")

    try:
        if args.command == "attack":
            for name, fn in ATTACKS.items():
                if args.kind in (name, "all"):
                    fn(args.base_url, key)
        else:
            stop, threads = baseline(args.base_url, key, args.users)
            deadline = time.time() + args.duration
            attack_every = getattr(args, "attack_every", 0)
            next_attack = time.time() + attack_every
            while time.time() < deadline:
                time.sleep(1)
                if args.command == "demo" and time.time() >= next_attack:
                    name = random.choice(list(ATTACKS))
                    print(f"--- attack burst: {name}")
                    ATTACKS[name](args.base_url, key)
                    next_attack = time.time() + attack_every
            stop.set()
            for t in threads:
                t.join(timeout=20)
    except KeyboardInterrupt:
        pass
    print_summary()


if __name__ == "__main__":
    main()
