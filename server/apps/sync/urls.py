from django.urls import path

from . import views

urlpatterns = [
    path("push/", views.sync_push_view, name="sync-push"),
    path("pull/", views.sync_pull_view, name="sync-pull"),
    path("status/", views.sync_status_view, name="sync-status"),
]
