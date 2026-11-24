import uuid

from django.db import models

from apps.profiles.models import Profile


class SyncedEntityRecord(models.Model):
    """Canonical server-side mirror of profile-scoped financial records with strict
    optimistic versioning and server-verified double-entry invariants (`POSTGRESQL_SCHEMA.md`).
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="synced_entities")
    entity_type = models.CharField(max_length=64, db_index=True)
    entity_id = models.UUIDField(db_index=True)
    status = models.CharField(max_length=32, default="active")
    is_immutable = models.BooleanField(default=False)
    payload = models.JSONField(default=dict)
    version = models.PositiveIntegerField(default=1)
    deleted_at_utc = models.DateTimeField(null=True, blank=True)
    updated_at_utc = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "synced_entity_records"
        constraints = [
            models.UniqueConstraint(
                fields=["profile", "entity_type", "entity_id"],
                name="uq_synced_entity_profile_type_id",
            )
        ]


def validate_server_ledger_invariants(entity_type: str, payload: dict) -> tuple[bool, str | None]:
    """Independently verifies double-entry invariants server-side on sync push.
    Server NEVER trusts client-calculated balances (`ARCH-003`, `DATA-003`).
    """
    if entity_type != "transaction":
        return True, None

    tx_status = payload.get("status")
    amount_minor = payload.get("amount_minor")
    if not isinstance(amount_minor, int) or amount_minor <= 0:
        return False, "amount_minor must be a strictly positive integer minor unit."

    if tx_status == "posted":
        postings = payload.get("postings")
        if not isinstance(postings, list) or len(postings) < 2:
            return False, "Posted transaction requires at least two double-entry postings."

        debits = 0
        credits = 0
        for p in postings:
            side = p.get("side")
            base_amt = p.get("base_amount_minor")
            orig_amt = p.get("original_amount_minor")
            if side not in ("debit", "credit"):
                return False, "Invalid posting side."
            if not isinstance(base_amt, int) or base_amt <= 0:
                return False, "Posting base_amount_minor must be positive integer."
            if not isinstance(orig_amt, int) or orig_amt <= 0:
                return False, "Posting original_amount_minor must be positive integer."
            if side == "debit":
                debits += base_amt
            else:
                credits += base_amt

        if debits != credits or debits <= 0:
            return False, f"Unbalanced posted journal: debits ({debits}) != credits ({credits})."

    return True, None
