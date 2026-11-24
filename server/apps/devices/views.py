from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

from apps.accounts.models import RefreshSession
from apps.audit.models import record_audit_event
from common.envelopes import error_response, ok_response

from .models import RegisteredDevice


class DeviceRegistrationSerializer(serializers.Serializer):
    device_id = serializers.UUIDField()
    platform = serializers.ChoiceField(choices=["android", "ios", "windows", "web"])
    app_version = serializers.CharField(max_length=32)
    device_label = serializers.CharField(max_length=80, required=False, allow_blank=True)


def _serialize_device(d: RegisteredDevice) -> dict:
    return {
        "device_id": str(d.device_id),
        "platform": d.platform,
        "app_version": d.app_version,
        "device_label": d.device_label,
        "last_seen_at_utc": d.last_seen_at_utc.isoformat(),
        "revoked_at_utc": d.revoked_at_utc.isoformat() if d.revoked_at_utc else None,
    }


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def devices_collection_view(request):
    if request.method == "GET":
        devices = RegisteredDevice.objects.filter(user=request.user)
        return ok_response([_serialize_device(d) for d in devices], request)

    ser = DeviceRegistrationSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    data = ser.validated_data
    device, _ = RegisteredDevice.objects.update_or_create(
        device_id=data["device_id"],
        defaults={
            "user": request.user,
            "platform": data["platform"],
            "app_version": data["app_version"],
            "device_label": data.get("device_label", ""),
            "last_seen_at_utc": timezone.now(),
            "revoked_at_utc": None,
        },
    )
    return ok_response(_serialize_device(device), request, status_code=status.HTTP_201_CREATED)


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def device_revoke_view(request, device_id):
    device = RegisteredDevice.objects.filter(device_id=device_id).first()
    if device is None:
        return error_response(
            "RESOURCE_NOT_FOUND",
            "Device not found.",
            request,
            status.HTTP_404_NOT_FOUND,
        )
    if device.user_id != request.user.id:
        return error_response(
            "PROFILE_ACCESS_DENIED",
            "Cannot revoke a device belonging to another user.",
            request,
            status.HTTP_403_FORBIDDEN,
        )

    now = timezone.now()
    with transaction.atomic():
        device.revoked_at_utc = now
        device.save(update_fields=["revoked_at_utc"])
        RefreshSession.objects.filter(
            user=request.user,
            device_id=device_id,
            revoked_at_utc__isnull=True,
        ).update(revoked_at_utc=now)
        record_audit_event(
            actor_user_id=str(request.user.id),
            action="device.revoked",
            target_type="device",
            target_id=str(device_id),
            request=request,
        )
    return ok_response({"revoked": True}, request, status_code=status.HTTP_204_NO_CONTENT)
