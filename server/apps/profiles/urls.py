from django.urls import path

from . import views

urlpatterns = [
    path("", views.profiles_collection_view, name="profiles-collection"),
    path("<uuid:profile_id>/", views.profile_detail_view, name="profile-detail"),
    path("<uuid:profile_id>/members/", views.profile_members_view, name="profile-members"),
    path(
        "<uuid:profile_id>/members/<uuid:member_id>/",
        views.profile_member_detail_view,
        name="profile-member-detail",
    ),
]
