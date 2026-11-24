
from django.db import models

from apps.profiles.models import Profile


class SyncOperation(models.Model):
    """Idempotency ledger for sync push operations (`ARCH-004`, `AC-SYNC-001`)."""

    OUTCOME_CHOICES = [
        ("accepted", "Accepted"),
        ("duplicate", "Duplicate"),
        ("retryable_error", "Retryable Error"),
        ("permanent_error", "Permanent Error"),
        ("conflict", "Conflict"),
    ]

    operation_id = models.UUIDField(primary_key=True)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="sync_operations")
    device_id = models.UUIDField()
    entity_type = models.CharField(max_length=64)
    entity_id = models.UUIDField()
    operation_type = models.CharField(max_length=16)
    payload_version = models.PositiveIntegerField(default=1)
    outcome = models.CharField(max_length=24, choices=OUTCOME_CHOICES)
    server_version = models.PositiveIntegerField(null=True, blank=True)
    error_code = models.CharField(max_length=64, null=True, blank=True)
    received_at_utc = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "sync_operations"


class SyncChange(models.Model):
    """Monotonic per-profile change feed backing `/sync/pull/?cursor=...` (`POSTGRESQL_SCHEMA.md`)."""

    sequence = models.BigAutoField(primary_key=True)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="sync_changes")
    entity_type = models.CharField(max_length=64)
    entity_id = models.UUIDField()
    change_type = models.CharField(max_length=16)  # create | update | archive | delete (tombstone)
    version = models.PositiveIntegerField(default=1)
    payload = models.JSONField(default=dict)
    created_at_utc = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "sync_changes"
        ordering = ["sequence"]
        indexes = [
            models.Index(fields=["profile", "sequence"], name="idx_sync_changes_prof_seq"),
        ]
