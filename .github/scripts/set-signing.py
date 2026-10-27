#!/usr/bin/env python3
"""Sets the Say Piano app target (only) up for an App Store build on CI.

The app is archived unsigned and then signed during export with Apple's cloud-managed
distribution certificate, using only the App Store Connect API key (.p8). No .p12
certificate file or provisioning profile is needed, and nothing is created or revoked.

Settings are written into the app target's build configurations instead of being passed on
the xcodebuild command line, because command-line settings also hit the MelodyPopKit Swift
package.

Usage: set-signing.py PROJECT.pbxproj  (reads TEAM, BUNDLE_ID, VER, BUILD from the environment)
"""
import os
import re
import sys

path = sys.argv[1]
text = open(path).read()
env = os.environ
wanted = {
    "DEVELOPMENT_TEAM": env["TEAM"],
    "CODE_SIGN_STYLE": "Automatic",
    "PRODUCT_BUNDLE_IDENTIFIER": env["BUNDLE_ID"],
    "MARKETING_VERSION": env["VER"],
    "CURRENT_PROJECT_VERSION": env["BUILD"],
}
# Leftovers from older manual-signing setups are removed.
drop = ['"CODE_SIGN_IDENTITY[sdk=iphoneos*]"', "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER"]

# The app target's configurations are the ones with the app's base bundle ID.
block_re = re.compile(r"(buildSettings = \{\n)(.*?)(\n\t\t\t\};)", re.S)
changed = 0


def fix(m):
    global changed
    body = m.group(2)
    if "PRODUCT_BUNDLE_IDENTIFIER = com.saystudios.melodypop;" not in body:
        return m.group(0)
    keys = list(wanted) + drop
    lines = [l for l in body.split("\n")
             if not any(re.match(r"\s*%s = " % re.escape(k), l) for k in keys)]
    lines += ["\t\t\t\t%s = %s;" % (k, v) for k, v in wanted.items()]
    changed += 1
    return m.group(1) + "\n".join(lines) + m.group(3)


text = block_re.sub(fix, text)
if changed != 2:
    sys.exit("Expected 2 app build configurations, changed %d" % changed)
open(path, "w").write(text)
print("App target: team %s, %s, version %s (%s)" % (env["TEAM"], env["BUNDLE_ID"], env["VER"], env["BUILD"]))
