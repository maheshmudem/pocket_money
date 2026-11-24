import json
import logging
import re

PROHIBITED_KEY_SUBSTRINGS = (
    "password",
    "token",
    "secret",
    "authorization",
    "key",
    "amount",
    "balance",
    "description",
    "memo",
    "note",
    "account_number",
    "csv",
    "payload",
    "email",
    "pin",
)

BEARER_RE = re.compile(r"Bearer\s+[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE)
JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def sanitize_text(text: str) -> str:
    text = BEARER_RE.sub("Bearer [REDACTED]", text)
    text = JWT_RE.sub("[REDACTED_JWT]", text)
    return EMAIL_RE.sub("[REDACTED_EMAIL]", text)


def sanitize_mapping(data: dict) -> dict:
    clean = {}
    for key, val in data.items():
        lower = str(key).lower()
        if any(s in lower for s in PROHIBITED_KEY_SUBSTRINGS):
            clean[key] = "[REDACTED]"
        elif isinstance(val, dict):
            clean[key] = sanitize_mapping(val)
        elif isinstance(val, str):
            clean[key] = sanitize_text(val)
        else:
            clean[key] = val
    return clean


class RedactingJsonFormatter(logging.Formatter):
    """Structured JSON log formatter enforcing `LOGGING_AND_MONITORING.md`."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp_utc": self.formatTime(record, "%Y-%m-%dT%H:%M:%SZ"),
            "severity": record.levelname.lower(),
            "logger": record.name,
            "message": sanitize_text(record.getMessage()),
        }
        if hasattr(record, "request_id") and record.request_id:
            payload["request_id"] = record.request_id
        if hasattr(record, "error_category") and record.error_category:
            payload["error_category"] = record.error_category
        return json.dumps(payload)
