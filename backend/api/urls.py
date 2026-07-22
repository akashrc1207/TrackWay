from django.urls import path
from . import views

urlpatterns = [
    path("routes/", views.route_list, name="route-list"),
    path("buses/", views.bus_list, name="bus-list"),
    path("drivers/", views.driver_list, name="driver-list"),
    path("bus-stops/", views.bus_stop_list, name="bus-stop-list"),
    path("gps/", views.gps_list, name="gps-list"),
    path("gps/update/", views.gps_update, name="gps-update"),
    path("gps/latest/<int:bus_id>/", views.latest_gps, name="latest-gps"),
    path("gps/latest/<int:bus_id>/", views.latest_gps, name="latest-gps"),
]