from django.urls import path
from . import views

urlpatterns = [
    path("routes/", views.route_list, name="route-list"),
    path("buses/", views.bus_list, name="bus-list"),
    path("buses/available/", views.available_buses, name="available-buses"),
    path("drivers/", views.driver_list, name="driver-list"),
    path("bus-stops/", views.bus_stop_list, name="bus-stop-list"),
    path("gps/", views.gps_list, name="gps-list"),
    path("gps/update/", views.gps_update, name="gps-update"),
    path("gps/latest/<int:bus_id>/", views.latest_gps, name="latest-gps"),
    path("routes/<int:route_id>/details/", views.route_details, name="route-details"),
    path("search/", views.search_bus, name="search-bus"),
    path("journey/start/", views.start_journey, name="start-journey"),
    path("journey/stop/", views.stop_journey, name="stop-journey"),
    path("auth/login/", views.login_driver, name="auth-login"),
    path("buses/<int:bus_id>/eta/", views.get_bus_eta, name="bus-eta"),
    path("metrics/", views.metrics_summary, name="metrics-summary"),
]