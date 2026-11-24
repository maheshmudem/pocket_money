import hashlib
import secrets
import uuid

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    def create_user(self, email: str, password: str | None = None, **extra_fields):
        if not email:
            raise ValueError("Email address is required.")
        normalized = self.normalize_email(email).strip().lower()
        user = self.model(email=normalized, **extra_fields)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, email: str, password: str, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("display_name", "Admin")
        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True, db_index=True)
    display_name = models.CharField(max_length=80)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at_utc = models.DateTimeField(auto_now_add=True)
    updated_at_utc = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["display_name"]

    class Meta:
        db_table = "users"


class RefreshSession(models.Model):
    """Tracks rotating SHA-256 hashed refresh tokens with token-family reuse detection (`SEC-001`)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="refresh_sessions")
    device_id = models.UUIDField(null=True, blank=True, db_index=True)
    token_family_id = models.UUIDField(default=uuid.uuid4, db_index=True)
    token_hash = models.CharField(max_length=64, unique=True, db_index=True)
    expires_at_utc = models.DateTimeField()
    rotated_at_utc = models.DateTimeField(null=True, blank=True)
    revoked_at_utc = models.DateTimeField(null=True, blank=True)
    created_at_utc = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "sessions"

    @staticmethod
    def hash_token(raw_token: str) -> str:
        return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()

    @staticmethod
    def generate_raw_token() -> str:
        return secrets.token_urlsafe(48)

    @property
    def is_valid(self) -> bool:
        return (
            self.revoked_at_utc is None
            and self.rotated_at_utc is None
            and self.expires_at_utc > timezone.now()
        )
