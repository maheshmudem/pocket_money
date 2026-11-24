import uuid

from django.conf import settings
from django.db import models

from apps.profiles.models import Profile


class ProfileMembership(models.Model):
    ROLE_CHOICES = [
        ("owner", "Owner"),
        ("admin", "Admin"),
        ("editor", "Editor"),
        ("viewer", "Viewer"),
    ]
    STATUS_CHOICES = [
        ("active", "Active"),
        ("invited", "Invited"),
        ("revoked", "Revoked"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile_memberships",
    )
    role = models.CharField(max_length=16, choices=ROLE_CHOICES)
    membership_status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="active")
    invited_at_utc = models.DateTimeField(auto_now_add=True)
    accepted_at_utc = models.DateTimeField(null=True, blank=True)
    version = models.PositiveIntegerField(default=1)

    class Meta:
        db_table = "profile_memberships"
        constraints = [
            models.UniqueConstraint(
                fields=["profile", "user"],
                name="uq_profile_membership_profile_user",
            )
        ]
