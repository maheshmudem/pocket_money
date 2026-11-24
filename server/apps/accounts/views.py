from datetime import timedelta

from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.tokens import AccessToken

from apps.audit.models import record_audit_event
from apps.devices.models import RegisteredDevice
from common.envelopes import error_response, ok_response

from .models import RefreshSession, User


class AuthRateThrottle(ScopedRateThrottle):
    scope = "auth"


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(min_length=10, max_length=128, write_only=True)
    display_name = serializers.CharField(min_length=1, max_length=80)
    device_id = serializers.UUIDField(required=False)
    platform = serializers.ChoiceField(
        choices=["android", "ios", "windows", "web"],
        required=False,
        default="android",
    )
    app_version = serializers.CharField(max_length=32, required=False, default="1.0.0")
    device_label = serializers.CharField(max_length=80, required=False, allow_blank=True)

    def validate_password(self, value: str) -> str:
        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(list(exc.messages)) from exc
        return value


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)
    device_id = serializers.UUIDField(required=False)
    platform = serializers.ChoiceField(
        choices=["android", "ios", "windows", "web"],
        required=False,
        default="android",
    )
    app_version = serializers.CharField(max_length=32, required=False, default="1.0.0")
    device_label = serializers.CharField(max_length=80, required=False, allow_blank=True)


def _issue_session_payload(user: User, *, device_id=None, token_family_id=None) -> dict:
    access = AccessToken.for_user(user)
    raw_refresh = RefreshSession.generate_raw_token()
    session_kwargs = {
        "user": user,
        "device_id": device_id,
        "token_hash": RefreshSession.hash_token(raw_refresh),
        "expires_at_utc": timezone.now() + timedelta(days=30),
    }
    if token_family_id is not None:
        session_kwargs["token_family_id"] = token_family_id
    RefreshSession.objects.create(**session_kwargs)

    return {
        "access_token": str(access),
        "refresh_token": raw_refresh,
        "expires_in_seconds": int(access.lifetime.total_seconds()),
        "user": {
            "id": str(user.id),
            "email": user.email,
            "display_name": user.display_name,
        },
    }


def _upsert_device(user: User, validated: dict):
    device_id = validated.get("device_id")
    if not device_id:
        return None
    device, _ = RegisteredDevice.objects.update_or_create(
        device_id=device_id,
        defaults={
            "user": user,
            "platform": validated.get("platform", "android"),
            "app_version": validated.get("app_version", "1.0.0"),
            "device_label": validated.get("device_label") or "",
            "last_seen_at_utc": timezone.now(),
            "revoked_at_utc": None,
        },
    )
    return device.device_id


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def register_view(request):
    ser = RegisterSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    email = ser.validated_data["email"].strip().lower()

    if User.objects.filter(email=email).exists():
        return error_response(
            "VALIDATION_ERROR",
            "An account with this email already exists.",
            request,
            status.HTTP_400_BAD_REQUEST,
            field_errors={"email": ["Email is already registered."]},
        )

    with transaction.atomic():
        user = User.objects.create_user(
            email=email,
            password=ser.validated_data["password"],
            display_name=ser.validated_data["display_name"].strip(),
        )
        dev_id = _upsert_device(user, ser.validated_data)
        payload = _issue_session_payload(user, device_id=dev_id)
        record_audit_event(
            actor_user_id=str(user.id),
            action="auth.register",
            target_type="user",
            target_id=str(user.id),
            request=request,
        )
    return ok_response(payload, request, status_code=status.HTTP_201_CREATED)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def login_view(request):
    ser = LoginSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    email = ser.validated_data["email"].strip().lower()
    user = authenticate(request, email=email, password=ser.validated_data["password"])
    if user is None or not user.is_active:
        return error_response(
            "AUTHENTICATION_REQUIRED",
            "Invalid email or password.",
            request,
            status.HTTP_401_UNAUTHORIZED,
        )

    with transaction.atomic():
        dev_id = _upsert_device(user, ser.validated_data)
        payload = _issue_session_payload(user, device_id=dev_id)
        record_audit_event(
            actor_user_id=str(user.id),
            action="auth.login",
            target_type="user",
            target_id=str(user.id),
            request=request,
        )
    return ok_response(payload, request)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def refresh_view(request):
    raw_token = (request.data or {}).get("refresh_token", "")
    if not raw_token:
        return error_response(
            "AUTHENTICATION_REQUIRED",
            "Refresh token is required.",
            request,
            status.HTTP_401_UNAUTHORIZED,
        )

    token_hash = RefreshSession.hash_token(raw_token)
    with transaction.atomic():
        session = (
            RefreshSession.objects.select_for_update()
            .select_related("user")
            .filter(token_hash=token_hash)
            .first()
        )
        if session is None:
            return error_response(
                "AUTHENTICATION_REQUIRED",
                "Invalid refresh token.",
                request,
                status.HTTP_401_UNAUTHORIZED,
            )

        # Replay / reuse detection: if already rotated, revoke the ENTIRE token family immediately!
        if session.rotated_at_utc is not None or session.revoked_at_utc is not None:
            RefreshSession.objects.filter(
                token_family_id=session.token_family_id,
                revoked_at_utc__isnull=True,
            ).update(revoked_at_utc=timezone.now())
            record_audit_event(
                actor_user_id=str(session.user_id),
                action="auth.refresh_reuse_detected",
                target_type="session_family",
                target_id=str(session.token_family_id),
                result="revoked",
                request=request,
            )
            return error_response(
                "AUTHENTICATION_REQUIRED",
                "Session invalidated for security. Please sign in again.",
                request,
                status.HTTP_401_UNAUTHORIZED,
            )

        if session.expires_at_utc <= timezone.now():
            return error_response(
                "AUTHENTICATION_REQUIRED",
                "Refresh session expired. Please sign in again.",
                request,
                status.HTTP_401_UNAUTHORIZED,
            )

        if session.device_id:
            dev = RegisteredDevice.objects.filter(device_id=session.device_id).first()
            if dev and dev.revoked_at_utc is not None:
                session.revoked_at_utc = timezone.now()
                session.save(update_fields=["revoked_at_utc"])
                return error_response(
                    "AUTHENTICATION_REQUIRED",
                    "This device has been revoked. Please sign in again.",
                    request,
                    status.HTTP_401_UNAUTHORIZED,
                )

        session.rotated_at_utc = timezone.now()
        session.save(update_fields=["rotated_at_utc"])
        payload = _issue_session_payload(
            session.user,
            device_id=session.device_id,
            token_family_id=session.token_family_id,
        )
    return ok_response(payload, request)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout_view(request):
    raw_token = (request.data or {}).get("refresh_token", "")
    now = timezone.now()
    if raw_token:
        RefreshSession.objects.filter(
            user=request.user,
            token_hash=RefreshSession.hash_token(raw_token),
        ).update(revoked_at_utc=now)
    else:
        RefreshSession.objects.filter(
            user=request.user,
            revoked_at_utc__isnull=True,
        ).update(revoked_at_utc=now)
    record_audit_event(
        actor_user_id=str(request.user.id),
        action="auth.logout",
        target_type="user",
        target_id=str(request.user.id),
        request=request,
    )
    return ok_response({"revoked": True}, request)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def password_reset_view(request):
    # Uniform response preventing email enumeration (`FR-001`, `SEC-001`).
    return ok_response(
        {"message": "If an account exists for that email, recovery instructions have been queued."},
        request,
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me_view(request):
    return ok_response(
        {
            "id": str(request.user.id),
            "email": request.user.email,
            "display_name": request.user.display_name,
        },
        request,
    )
