from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

from apps.accounts.models import User
from apps.audit.models import record_audit_event
from apps.memberships.models import ProfileMembership
from apps.memberships.permissions import require_profile_membership
from common.envelopes import error_response, ok_response

from .models import Profile, ProfileCurrencyHistory


class ProfileCreateSerializer(serializers.Serializer):
    id = serializers.UUIDField(required=False)
    name = serializers.CharField(min_length=1, max_length=80)
    profile_type = serializers.ChoiceField(choices=["personal", "family", "business"])
    base_currency_code = serializers.RegexField(regex=r"^[A-Z]{3}$", default="INR")
    timezone = serializers.CharField(max_length=64, required=False, default="Asia/Kolkata")
    editors_can_post = serializers.BooleanField(required=False, default=True)


class ProfilePatchSerializer(serializers.Serializer):
    name = serializers.CharField(min_length=1, max_length=80, required=False)
    timezone = serializers.CharField(max_length=64, required=False)
    base_currency_code = serializers.RegexField(regex=r"^[A-Z]{3}$", required=False)
    editors_can_post = serializers.BooleanField(required=False)
    expected_version = serializers.IntegerField(min_value=1, required=False)


class MemberInviteSerializer(serializers.Serializer):
    email = serializers.EmailField()
    role = serializers.ChoiceField(choices=["admin", "editor", "viewer"])


class MemberPatchSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=["owner", "admin", "editor", "viewer"])
    confirm_password = serializers.CharField(required=False, allow_blank=True)


def _serialize_profile(profile: Profile, role: str) -> dict:
    return {
        "id": str(profile.id),
        "name": profile.name,
        "profile_type": profile.profile_type,
        "base_currency_code": profile.base_currency_code,
        "timezone": profile.timezone,
        "editors_can_post": profile.editors_can_post,
        "role": role,
        "version": profile.version,
        "archived_at_utc": profile.archived_at_utc.isoformat() if profile.archived_at_utc else None,
    }


def _serialize_member(m: ProfileMembership) -> dict:
    return {
        "id": str(m.id),
        "profile_id": str(m.profile_id),
        "user_id": str(m.user_id),
        "email": m.user.email,
        "display_name": m.user.display_name,
        "role": m.role,
        "membership_status": m.membership_status,
    }


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def profiles_collection_view(request):
    if request.method == "GET":
        memberships = (
            ProfileMembership.objects.select_related("profile")
            .filter(
                user=request.user,
                membership_status="active",
                profile__archived_at_utc__isnull=True,
            )
            .order_by("profile__created_at_utc")
        )
        return ok_response(
            [_serialize_profile(m.profile, m.role) for m in memberships],
            request,
        )

    ser = ProfileCreateSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    d = ser.validated_data

    with transaction.atomic():
        kwargs = {
            "name": d["name"].strip(),
            "profile_type": d["profile_type"],
            "base_currency_code": d["base_currency_code"],
            "timezone": d["timezone"],
            "editors_can_post": d["editors_can_post"],
            "owner": request.user,
        }
        if "id" in d:
            kwargs["id"] = d["id"]
        profile = Profile.objects.create(**kwargs)
        ProfileMembership.objects.create(
            profile=profile,
            user=request.user,
            role="owner",
            membership_status="active",
            accepted_at_utc=timezone.now(),
        )
        record_audit_event(
            actor_user_id=str(request.user.id),
            profile_id=profile.id,
            action="profile.created",
            target_type="profile",
            target_id=str(profile.id),
            request=request,
            metadata={"profile_type": profile.profile_type},
        )
    return ok_response(
        _serialize_profile(profile, "owner"),
        request,
        status_code=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def profile_detail_view(request, profile_id):
    if request.method == "GET":
        m = require_profile_membership(request.user, profile_id, action="view")
        return ok_response(_serialize_profile(m.profile, m.role), request)

    if request.method == "DELETE":
        m = require_profile_membership(request.user, profile_id, action="archive_profile")
        profile = m.profile
        profile.archived_at_utc = timezone.now()
        profile.version += 1
        profile.save(update_fields=["archived_at_utc", "version", "updated_at_utc"])
        record_audit_event(
            actor_user_id=str(request.user.id),
            profile_id=profile.id,
            action="profile.archived",
            target_type="profile",
            target_id=str(profile.id),
            request=request,
        )
        return ok_response(_serialize_profile(profile, m.role), request)

    m = require_profile_membership(request.user, profile_id, action="manage_profile_settings")
    ser = ProfilePatchSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    d = ser.validated_data

    with transaction.atomic():
        profile = Profile.objects.select_for_update().get(id=profile_id)
        if "expected_version" in d and d["expected_version"] != profile.version:
            return error_response(
                "VERSION_CONFLICT",
                "Profile was modified concurrently. Refresh before saving.",
                request,
                status.HTTP_409_CONFLICT,
            )

        if "name" in d:
            profile.name = d["name"].strip()
        if "timezone" in d:
            profile.timezone = d["timezone"]
        if "editors_can_post" in d:
            profile.editors_can_post = d["editors_can_post"]
        if "base_currency_code" in d and d["base_currency_code"] != profile.base_currency_code:
            ProfileCurrencyHistory.objects.create(
                profile=profile,
                previous_currency_code=profile.base_currency_code,
                new_currency_code=d["base_currency_code"],
                changed_by=request.user,
            )
            profile.base_currency_code = d["base_currency_code"]

        profile.version += 1
        profile.save()
    return ok_response(_serialize_profile(profile, m.role), request)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def profile_members_view(request, profile_id):
    if request.method == "GET":
        require_profile_membership(request.user, profile_id, action="view")
        members = ProfileMembership.objects.select_related("user").filter(profile_id=profile_id)
        return ok_response([_serialize_member(m) for m in members], request)

    require_profile_membership(request.user, profile_id, action="manage_members")
    ser = MemberInviteSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    target_user = User.objects.filter(email=ser.validated_data["email"].strip().lower()).first()
    if target_user is None:
        return error_response(
            "RESOURCE_NOT_FOUND",
            "No registered Pocket CFO user found with that email.",
            request,
            status.HTTP_404_NOT_FOUND,
        )

    member, _ = ProfileMembership.objects.update_or_create(
        profile_id=profile_id,
        user=target_user,
        defaults={
            "role": ser.validated_data["role"],
            "membership_status": "active",
            "accepted_at_utc": timezone.now(),
        },
    )
    record_audit_event(
        actor_user_id=str(request.user.id),
        profile_id=profile_id,
        action="membership.added",
        target_type="membership",
        target_id=str(member.id),
        request=request,
        metadata={"role": member.role},
    )
    return ok_response(_serialize_member(member), request, status_code=status.HTTP_201_CREATED)


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def profile_member_detail_view(request, profile_id, member_id):
    caller = require_profile_membership(request.user, profile_id, action="manage_members")
    member = (
        ProfileMembership.objects.select_related("user")
        .filter(id=member_id, profile_id=profile_id)
        .first()
    )
    if member is None:
        return error_response(
            "RESOURCE_NOT_FOUND",
            "Profile member not found.",
            request,
            status.HTTP_404_NOT_FOUND,
        )

    if request.method == "DELETE":
        if member.role == "owner":
            return error_response(
                "VALIDATION_ERROR",
                "Cannot remove the profile owner.",
                request,
                status.HTTP_400_BAD_REQUEST,
            )
        member.membership_status = "revoked"
        member.version += 1
        member.save(update_fields=["membership_status", "version"])
        return ok_response({"revoked": True}, request, status_code=status.HTTP_204_NO_CONTENT)

    ser = MemberPatchSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    new_role = ser.validated_data["role"]
    if new_role == "owner":
        # Ownership transfer requires Owner + explicit password re-authentication (`ROLE_AND_PERMISSION_MATRIX.md`).
        if caller.role != "owner" or not request.user.check_password(
            ser.validated_data.get("confirm_password", "")
        ):
            return error_response(
                "PROFILE_ACCESS_DENIED",
                "Ownership transfer requires the current Owner and valid password re-authentication.",
                request,
                status.HTTP_403_FORBIDDEN,
            )
        with transaction.atomic():
            caller.role = "admin"
            caller.save(update_fields=["role"])
            member.role = "owner"
            member.save(update_fields=["role"])
            Profile.objects.filter(id=profile_id).update(owner=member.user)
    else:
        member.role = new_role
        member.version += 1
        member.save(update_fields=["role", "version"])
    return ok_response(_serialize_member(member), request)
