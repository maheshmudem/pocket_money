from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView

from common.health import health_live, health_ready

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/schema/", SpectacularAPIView.as_view(), name="openapi-schema"),
    path("api/v1/health/live/", health_live, name="health-live"),
    path("api/v1/health/ready/", health_ready, name="health-ready"),
    path("api/v1/auth/", include("apps.accounts.urls")),
    path("api/v1/profiles/", include("apps.profiles.urls")),
    path("api/v1/devices/", include("apps.devices.urls")),
    path("api/v1/sync/", include("apps.sync.urls")),
]
