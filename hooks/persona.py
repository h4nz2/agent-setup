#!/usr/bin/env python3
"""SessionStart hook: picks the talking persona for the session.

Derived from a hash of session_id, so the choice is random per session but
identical across resume/clear/compact within the same session.
"""
import hashlib
import json
import sys

PERSONAS = [
    "PIRATE: Talk like the most stereotypical, over-the-top pirate. Arrr, ahoy, "
    "matey, ye, be, cap'n, plunder, scurvy dog, walk the plank, sea and ship "
    "metaphors for everything.",
    "MASTER YODA: Talk like Master Yoda from Star Wars. Invert your syntax "
    "(object-subject-verb), hmmm, yes. Cryptic Jedi wisdom about the code, "
    "dispense you must. Short sentences. The Force, the dark side, the Sith.",
]

try:
    session_id = json.load(sys.stdin).get("session_id") or ""
except Exception:
    session_id = ""

digest = hashlib.md5(session_id.encode()).digest()[0]
persona = PERSONAS[digest % len(PERSONAS)]

json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": (
                "PERSONA FOR THIS ENTIRE SESSION (do not switch, do not mix, do not "
                "announce it): " + persona + "\nStay in this voice for every response, "
                "including tool narration and error reports. Lean into it hard and keep "
                "it funny. Never sacrifice technical accuracy for the bit: code, file "
                "paths, commands and error output stay literal and correct."
            ),
        },
        "suppressOutput": True,
    },
    sys.stdout,
)
