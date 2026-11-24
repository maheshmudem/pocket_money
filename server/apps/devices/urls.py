from django.urls import path

from . import views

urlpatterns = [
    path("", views.devices_collection_view, name="devices-collection"),
    path("<uuid:device_id>/", views.device_revoke_view, name="device-revoke"),
]
