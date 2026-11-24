import uuid

from django.db import models

from common.logging_filters import sanitize_mapping


class AuditEvent(models.Model):
    """Append-only security & administrative audit log (`POSTGRESQL_SCHEMA.md`)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor_user_id = models.CharField(max_length=64, db_index=True)
    profile_id = models.UUIDField(null=True, blank=True, db_index=True)
    action = models.CharField(max_length=96, db_index=True)
    target_type = models.CharField(max_length=64)
    target_id = models.CharField(max_length=64)
    result = models.CharField(max_length=32)
    request_id = models.CharField(max_length=64, null=True, blank=True)
    metadata_redacted = models.JSONField(default=dict)
    created_at_utc = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "audit_events"
        ordering = ["-created_at_utc"]


def record_audit_event(
    *,
    actor_user_id: str,
    action: str,
    target_type: str,
    target_id: str,
    result: str = "success",
    profile_id=None,
    request=None,
    metadata: dict | None = None,
) -> AuditEvent:
    return AuditEvent.objects.create(
        actor_user_id=str(actor_user_id),
        profile_id=profile_id,
        action=action,
        target_type=target_type,
        target_id=str(target_id),
        result=result,
        request_id=getattr(request, "request_id", None) if request else None,
        metadata_redacted=sanitize_mapping(metadata or {}),
    )
