#!/usr/bin/env python3
"""Print a gateway access token for a Cognito user with username and password (SRP), no browser.

Alternative to the PKCE helper for headless shells (containers, SSH). The app client allows
USER_SRP_AUTH. Needs `pip install pycognito`. The password is read from a prompt (or the
GATEWAY_PASSWORD variable, or the file named by GATEWAY_PASSWORD_FILE) and is never written
to disk by this script; the token goes to stdout:

    export AGENTCORE_OIDC_DISCOVERY_URL=... AGENTCORE_OIDC_CLIENT_ID=...   # as claude-token.sh does
    export ANTHROPIC_AUTH_TOKEN=$(python3 scripts/get-token-srp.py finanzas-user)

The token lasts 24 hours; run it again to renew.
"""

import getpass
import os
import sys
from urllib.parse import urlparse

from pycognito.aws_srp import AWSSRP


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: get-token-srp.py <cognito username>")
    discovery = urlparse(os.environ["AGENTCORE_OIDC_DISCOVERY_URL"])
    region = discovery.hostname.split(".")[1]  # cognito-idp.<region>.amazonaws.com
    pool_id = discovery.path.strip("/").split("/")[0]
    password_file = os.environ.get("GATEWAY_PASSWORD_FILE")
    password = (
        open(password_file).read().strip() if password_file
        else os.environ.get("GATEWAY_PASSWORD") or getpass.getpass("Password: ", stream=sys.stderr)
    )
    srp = AWSSRP(
        username=sys.argv[1],
        password=password,
        pool_id=pool_id,
        client_id=os.environ["AGENTCORE_OIDC_CLIENT_ID"],
        pool_region=region,
    )
    print(srp.authenticate_user()["AuthenticationResult"]["AccessToken"])


if __name__ == "__main__":
    main()
