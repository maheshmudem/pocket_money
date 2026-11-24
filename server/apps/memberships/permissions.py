from rest_framework.exceptions import PermissionDenied

from .models import ProfileMembership


def require_profile_membership(user, profile_id, *, action: str) -> ProfileMembership:
    """Centralized server-side RBAC enforcement (`ROLE_AND_PERMISSION_MATRIX.md`, `R-003`).
    Every profile route & sync operation MUST pass through this check.
    """
    membership = (
        ProfileMembership.objects.select_related("profile")
        .filter(
            user=user,
            profile_id=profile_id,
            membership_status="active",
        )
        .first()
    )
    if membership is None:
        raise PermissionDenied("You do not have active access to this profile.")

    role = membership.role
    editors_can_post = membership.profile.editors_can_post

    allowed = False
    if action == "view":
        allowed = role in ("owner", "admin", "editor", "viewer")
    elif action == "write_draft":
        allowed = role in ("owner", "admin", "editor")
    elif action == "post_transaction":
        allowed = role in ("owner", "admin") or (role == "editor" and editors_can_post)
    elif action == "reverse_or_void":
        allowed = role in ("owner", "admin")
    elif action == "manage_members":
        allowed = role in ("owner", "admin")
    elif action == "manage_profile_settings":
        allowed = role == "owner"
    elif action == "archive_profile":
        allowed = role == "owner"

    if not allowed:
        raise PermissionDenied(f"Role '{role}' is not permitted to perform '{action}'.")

    return membership
