import uuid

from django.conf import settings
from django.db import models


class Profile(models.Model):
    PROFILE_TYPES = [
        ("personal", "Personal"),
        ("family", "Family"),
        ("business", "Business"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=80)
    profile_type = models.CharField(max_length=16, choices=PROFILE_TYPES)
    base_currency_code = models.CharField(max_length=3, default="INR")
    timezone = models.CharField(max_length=64, default="Asia/Kolkata")
    editors_can_post = models.BooleanField(default=True)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="owned_profiles",
    )
    version = models.PositiveIntegerField(default=1)
    created_at_utc = models.DateTimeField(auto_now_add=True)
    updated_at_utc = models.DateTimeField(auto_now=True)
    archived_at_utc = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "profiles"


class ProfileCurrencyHistory(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="currency_history")
    previous_currency_code = models.CharField(max_length=3)
    new_currency_code = models.CharField(max_length=3)
    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    effective_at_utc = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "profile_currency_history"
