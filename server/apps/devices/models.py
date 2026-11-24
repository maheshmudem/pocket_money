import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class RegisteredDevice(models.Model):
    PLATFORM_CHOICES = [
        ("android", "Android"),
        ("ios", "iOS"),
        ("windows", "Windows"),
        ("web", "Web"),
    ]

    device_id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="devices",
    )
    platform = models.CharField(max_length=16, choices=PLATFORM_CHOICES)
    app_version = models.CharField(max_length=32)
    device_label = models.CharField(max_length=80, blank=True, default="")
    last_seen_at_utc = models.DateTimeField(default=timezone.now)
    revoked_at_utc = models.DateTimeField(null=True, blank=True)
    created_at_utc = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "devices"
        ordering = ["-last_seen_at_utc"]
