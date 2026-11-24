from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated

from apps.audit.models import record_audit_event
from apps.ledger.models import SyncedEntityRecord, validate_server_ledger_invariants
from apps.memberships.permissions import require_profile_membership
from common.envelopes import error_response, ok_response

from .models import SyncChange, SyncOperation


class SyncOperationInputSerializer(serializers.Serializer):
    operation_id = serializers.UUIDField()
    profile_id = serializers.UUIDField()
    entity_type = serializers.CharField(max_length=64)
    entity_id = serializers.UUIDField()
    operation_type = serializers.ChoiceField(choices=["create", "update", "archive", "delete"])
    payload_version = serializers.IntegerField(min_value=1, default=1)
    base_version = serializers.IntegerField(required=False, allow_null=True)
    payload = serializers.DictField()


class SyncPushRequestSerializer(serializers.Serializer):
    device_id = serializers.UUIDField()
    operations = SyncOperationInputSerializer(many=True, min_length=1, max_length=100)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def sync_push_view(request):
    """Idempotent batched outbox processor (`OPENAPI_V1.yaml`, `ARCH-004`, `AC-SYNC-001`)."""
    ser = SyncPushRequestSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    device_id = ser.validated_data["device_id"]
    results = []

    for op in ser.validated_data["operations"]:
        op_id = op["operation_id"]
        profile_id = op["profile_id"]
        entity_type = op["entity_type"]
        entity_id = op["entity_id"]
        op_type = op["operation_type"]
        payload = op["payload"]
        base_version = op.get("base_version")

        # 1. Verify active membership & required role for this exact profile (`R-003`).
        required_action = "post_transaction"
        if entity_type == "transaction_reversal":
            required_action = "reverse_or_void"
        elif entity_type == "transaction" and payload.get("status") == "draft":
            required_action = "write_draft"
        elif entity_type == "profile":
            required_action = "manage_profile_settings"

        try:
            require_profile_membership(request.user, profile_id, action=required_action)
        except PermissionDenied:
            results.append(
                {
                    "operation_id": str(op_id),
                    "outcome": "permanent_error",
                    "server_version": None,
                    "error_code": "PROFILE_ACCESS_DENIED",
                }
            )
            continue

        with transaction.atomic():
            # 2. Idempotency replay check: same operation_id NEVER applies twice (`AC-SYNC-001`).
            prior = SyncOperation.objects.select_for_update().filter(operation_id=op_id).first()
            if prior is not None:
                results.append(
                    {
                        "operation_id": str(op_id),
                        "outcome": "duplicate",
                        "server_version": prior.server_version,
                        "error_code": prior.error_code,
                    }
                )
                continue

            # 3. Server-side financial invariant validation (`DATA-003`).
            valid_ledger, ledger_err = validate_server_ledger_invariants(entity_type, payload)
            if not valid_ledger:
                SyncOperation.objects.create(
                    operation_id=op_id,
                    profile_id=profile_id,
                    device_id=device_id,
                    entity_type=entity_type,
                    entity_id=entity_id,
                    operation_type=op_type,
                    payload_version=op["payload_version"],
                    outcome="permanent_error",
                    error_code="LEDGER_INVARIANT_VIOLATION",
                )
                results.append(
                    {
                        "operation_id": str(op_id),
                        "outcome": "permanent_error",
                        "server_version": None,
                        "error_code": "LEDGER_INVARIANT_VIOLATION",
                        "detail": ledger_err,
                    }
                )
                continue

            existing = (
                SyncedEntityRecord.objects.select_for_update()
                .filter(profile_id=profile_id, entity_type=entity_type, entity_id=entity_id)
                .first()
            )

            # 4. Posted financial records are strictly immutable (`R-005`, `ADR-012`).
            if existing is not None and existing.is_immutable and op_type in ("update", "delete"):
                SyncOperation.objects.create(
                    operation_id=op_id,
                    profile_id=profile_id,
                    device_id=device_id,
                    entity_type=entity_type,
                    entity_id=entity_id,
                    operation_type=op_type,
                    payload_version=op["payload_version"],
                    outcome="permanent_error",
                    server_version=existing.version,
                    error_code="IMMUTABLE_POSTED_RECORD",
                )
                results.append(
                    {
                        "operation_id": str(op_id),
                        "outcome": "permanent_error",
                        "server_version": existing.version,
                        "error_code": "IMMUTABLE_POSTED_RECORD",
                    }
                )
                continue

            # 5. Optimistic concurrency check on mutable drafts/metadata (no silent LWW!).
            if (
                existing is not None
                and base_version is not None
                and base_version != existing.version
            ):
                results.append(
                    {
                        "operation_id": str(op_id),
                        "outcome": "conflict",
                        "server_version": existing.version,
                        "error_code": "VERSION_CONFLICT",
                        "server_payload": existing.payload,
                    }
                )
                continue

            # 6. Apply mutation, bump server_version, append monotonic SyncChange & record SyncOperation.
            is_posted_tx = entity_type == "transaction" and payload.get("status") == "posted"
            if existing is None:
                record = SyncedEntityRecord.objects.create(
                    profile_id=profile_id,
                    entity_type=entity_type,
                    entity_id=entity_id,
                    status=payload.get("status", "active"),
                    is_immutable=is_posted_tx,
                    payload=payload,
                    version=1,
                    deleted_at_utc=timezone.now() if op_type == "delete" else None,
                )
            else:
                existing.payload = payload
                existing.status = payload.get("status", existing.status)
                existing.is_immutable = existing.is_immutable or is_posted_tx
                existing.version += 1
                if op_type == "delete":
                    existing.deleted_at_utc = timezone.now()
                existing.save()
                record = existing

            SyncChange.objects.create(
                profile_id=profile_id,
                entity_type=entity_type,
                entity_id=entity_id,
                change_type=op_type,
                version=record.version,
                payload={} if op_type == "delete" else payload,
            )
            SyncOperation.objects.create(
                operation_id=op_id,
                profile_id=profile_id,
                device_id=device_id,
                entity_type=entity_type,
                entity_id=entity_id,
                operation_type=op_type,
                payload_version=op["payload_version"],
                outcome="accepted",
                server_version=record.version,
            )
            record_audit_event(
                actor_user_id=str(request.user.id),
                profile_id=profile_id,
                action="sync.operation_accepted",
                target_type=entity_type,
                target_id=str(entity_id),
                request=request,
                metadata={"operation_type": op_type, "version": record.version},
            )
            results.append(
                {
                    "operation_id": str(op_id),
                    "outcome": "accepted",
                    "server_version": record.version,
                    "error_code": None,
                }
            )

    return ok_response({"results": results}, request)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def sync_pull_view(request):
    """Cursor-paginated incremental change feed scoped strictly to authorized profile."""
    profile_id = request.query_params.get("profile_id")
    if not profile_id:
        return error_response(
            "VALIDATION_ERROR",
            "profile_id query parameter is required.",
            request,
            status.HTTP_400_BAD_REQUEST,
        )

    require_profile_membership(request.user, profile_id, action="view")

    raw_cursor = request.query_params.get("cursor", "")
    after_seq = 0
    if raw_cursor.startswith("seq:"):
        try:
            after_seq = int(raw_cursor.split(":", 1)[1])
        except ValueError:
            return error_response(
                "VALIDATION_ERROR",
                "Malformed sync cursor.",
                request,
                status.HTTP_400_BAD_REQUEST,
            )

    try:
        limit = min(500, max(1, int(request.query_params.get("limit", "100"))))
    except ValueError:
        limit = 100

    qs = SyncChange.objects.filter(
        profile_id=profile_id,
        sequence__gt=after_seq,
    ).order_by("sequence")

    rows = list(qs[: limit + 1])
    has_more = len(rows) > limit
    page = rows[:limit]
    next_seq = page[-1].sequence if page else after_seq

    return ok_response(
        {
            "changes": [
                {
                    "sequence": c.sequence,
                    "entity_type": c.entity_type,
                    "entity_id": str(c.entity_id),
                    "change_type": c.change_type,
                    "version": c.version,
                    "payload": c.payload,
                    "created_at_utc": c.created_at_utc.isoformat(),
                }
                for c in page
            ],
            "next_cursor": f"seq:{next_seq}",
            "has_more": has_more,
        },
        request,
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def sync_status_view(request):
    profile_id = request.query_params.get("profile_id")
    if not profile_id:
        return error_response(
            "VALIDATION_ERROR",
            "profile_id query parameter is required.",
            request,
            status.HTTP_400_BAD_REQUEST,
        )
    require_profile_membership(request.user, profile_id, action="view")
    latest = (
        SyncChange.objects.filter(profile_id=profile_id)
        .order_by("-sequence")
        .first()
    )
    return ok_response(
        {
            "profile_id": profile_id,
            "latest_cursor": f"seq:{latest.sequence}" if latest else "seq:0",
            "latest_change_at_utc": latest.created_at_utc.isoformat() if latest else None,
        },
        request,
    )
